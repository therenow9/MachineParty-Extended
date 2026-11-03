# Machine Party 8 Player Support: runtime parse smoke check of the patched scripts
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\parsecheck.ps1
# Needs:  tools\build.ps1 run first (this mounts the patched PCK)
#
# gdre's compile does not resolve base-class identifiers: `self.global_transform` in a Minigame
# (a Node, not a Node3D) compiles and packs clean, then fails to load in game, and the session
# hangs at SessionIntro as if spawns or the player count were at fault. This catches that.
#
# Sources are fed to GDScript.reload() while the same classes are loaded from the PCK, so there is
# noise the unpatched src\ reports too ("Cannot assign a value of type X as Y", "Node export is only
# supported in Node-derived classes", "Identifier not found: GameManager", "class_name isn't allowed
# in built-in scripts"), varying with scan order. Zero errors is not the bar; the only verdict is:
#   `not declared in the current scope` = a real error, to fix. All other noise is ignored.
# For a stricter answer run a baseline with $env:MP8_CHECK_DIR="...\src": only errors the patched
# run reports and the baseline does not are ours.

param([string]$Godot = $env:GODOT, [string]$Pck = '', [string]$Overlay = '')
$ErrorActionPreference = "Stop"

$root  = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Godot)) { $Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" }
$probe = Join-Path $root "tools\probe"
if ([string]::IsNullOrWhiteSpace($Pck)) { $Pck = Join-Path $root "game_test\Machine Party.pck" }
$Pck = [IO.Path]::GetFullPath($Pck)

$neededPaths = @($godot, $pck, (Join-Path $probe "parsecheck.gd"))
if ($Overlay) { $Overlay = [IO.Path]::GetFullPath($Overlay); $neededPaths += $Overlay }
foreach ($needed in $neededPaths) {
    if (-not (Test-Path $needed)) { throw "Not found: $needed" }
}

$runId = [guid]::NewGuid().ToString('N')
$out = Join-Path $env:TEMP "mp8_parsecheck-$runId.out"
$err = Join-Path $env:TEMP "mp8_parsecheck-$runId.err"

Write-Host "Mounting the PCK and parsing every .gd under patch\ ..." -ForegroundColor Cyan
$probeArguments = @("--headless", "--path", "`"$probe`"", "--script", "`"$probe\parsecheck.gd`"", '--', "`"$Pck`"", "`"$(Join-Path $root 'patch')`"")
if ($Overlay) { $probeArguments += '"' + $Overlay + '"' }
$process = Start-Process $Godot `
    -ArgumentList $probeArguments `
    -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
if ($process.ExitCode -eq 2 -or -not (Select-String -LiteralPath $out -Pattern 'Parse self-check' -Quiet)) { throw "Probe did not load the PCK; see $err" }
Write-Host "Probe logs: $out / $err"

# "---- <file>" lines in stderr tie each error to its file. A file reporting `inherits "RefCounted"` has
# an unresolved base, so every Node member it uses reads as undeclared: its scope errors are undecidable.
# In any other file a scope error is real. Steam* names are the Steam GDExtension's singletons, not
# loaded by the headless probe, and are skipped.
$lines = (Get-Content $err -Raw) -split "`r?`n"
$current = "?"
$scope = @{}
$baseBroken = @{}
foreach ($l in $lines) {
    if ($l -match '^----\s*(.+)$') { $current = $Matches[1].Trim(); continue }
    if ($l -match 'inherits "RefCounted"') { $baseBroken[$current] = $true; continue }
    if ($l -match 'Identifier "(.+?)" not declared in the current scope') {
        $id = $Matches[1]
        if ($id -like "Steam*") { continue }
        if (-not $scope.ContainsKey($current)) { $scope[$current] = @() }
        if ($scope[$current] -notcontains $id) { $scope[$current] += $id }
    }
}

$real = @()
$unknown = @()
foreach ($f in $scope.Keys) {
    if ($baseBroken.ContainsKey($f)) { $unknown += $f } else { $real += $f }
}

Write-Host ""
if ($real.Count -gt 0) {
    Write-Host "❌ Real scope errors - this PCK will fail to load, do not run it:" -ForegroundColor Red
    foreach ($f in $real) {
        Write-Host ("   {0}: {1}" -f $f, ($scope[$f] -join ", ")) -ForegroundColor Red
    }
    exit 1
}

Write-Host "✅ No scope errors in the scripts whose base class resolves." -ForegroundColor Green
$failedScripts = @(Select-String -LiteralPath $out -Pattern 'parse failed\(err=').Count
if ($failedScripts -gt 0) {
    Write-Host "   The probe reports $failedScripts scripts that failed to parse or compile (see the logs); this command judges scope errors only, not a full parse pass." -ForegroundColor Yellow
}
if ($unknown.Count -gt 0) {
    Write-Host ("   Undecidable (base class unresolved in the probe, probe noise): {0}" -f ($unknown -join ", ")) -ForegroundColor DarkGray
}
Write-Host "   This is not zero risk; the limits are at the top of this script." -ForegroundColor DarkGray
exit 0
