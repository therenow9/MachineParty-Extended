# Machine Party 8 Player Support: compile and pack
#
# Compiles every .gd under patch\ to .gdc, with its res:// path taken from the directory layout,
# and packs them into the PCK. A new patch file needs no change here.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\build.ps1
#
#   - Always packs from Machine Party.pck.orig, never on top of a packed PCK
#   - Packs to res://xxx.gdc (the .gd is remapped there; packing the .gd does nothing)
#   - Compiles with --bytecode=4.5.2
#   - Every game instance must be closed before the PCK is swapped
#   - gdre_tools writes its progress bar to stderr, so an empty stderr proves nothing:
#     the script checks for each .gdc and filters stderr for real errors
#   - -CompileOnly: compile to patch_gdc\ only; no PCK, no game process killed.
#     The full four steps are for the local test bench.

param(
    [switch] $CompileOnly
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $root "tools\gdre\gdre_tools.exe"
$p    = Join-Path $root "patch"
$out  = Join-Path $root "patch_gdc"
$gt   = Join-Path $root "game_test"
$orig = Join-Path $gt "Machine Party.pck.orig"

$needs = @($exe, (Join-Path $root 'tools\gdre\gdre_tools.pck'), $p)
if (-not $CompileOnly) { $needs += $orig }
foreach ($needed in $needs) {
    if (-not (Test-Path $needed)) { throw "Not found: $needed" }
}

if ($CompileOnly) {
    Write-Host "[1/4] Compile-only mode: game instances left running, PCK untouched"
} else {
    Write-Host "[1/4] Closing every game instance"
    Get-Process "Machine Party" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

$sources = Get-ChildItem $p -Recurse -Filter "*.gd" -File
if ($sources.Count -eq 0) { throw "patch\ has no .gd files" }

# gdre's --output takes only a directory, so each .gdc lands in patch_gdc\ by base name: two .gd files
# of one name in different directories overwrite each other, and both res:// paths silently get the
# same bytecode. State-machine scripts (idle_state.gd, play_state.gd) are the likely clash.
$dupes = $sources | Group-Object BaseName | Where-Object { $_.Count -gt 1 }
if ($dupes) {
    Write-Host "Base name clash (the compiled files would overwrite each other; rename one or change the build script):" -ForegroundColor Red
    foreach ($d in $dupes) {
        Write-Host ("  {0}.gd :" -f $d.Name) -ForegroundColor Red
        foreach ($f in $d.Group) {
            Write-Host ("      " + $f.FullName.Substring($p.Length + 1)) -ForegroundColor Red
        }
    }
    throw "patch\ has scripts with the same name"
}

Write-Host "[2/4] Compiling $($sources.Count) scripts -> .gdc"
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $out -Filter "*.gdc" -ErrorAction SilentlyContinue | Remove-Item -Force

$cargs = @("--headless")
foreach ($s in $sources) { $cargs += "--compile=`"$($s.FullName)`"" }
$cargs += @("--bytecode=4.5.2", "--output=`"$out`"")

$cerr = Join-Path $env:TEMP "mp8_compile.err"
$compilerProcess = Start-Process $exe -ArgumentList $cargs -WindowStyle Hidden -Wait -PassThru `
    -RedirectStandardOutput (Join-Path $env:TEMP "mp8_compile.out") -RedirectStandardError $cerr

# Every source must produce a .gdc of the same name; a missing one is a failed compile.
$missing = @()
foreach ($s in $sources) {
    $gdc = Join-Path $out ($s.BaseName + ".gdc")
    if (-not (Test-Path $gdc)) { $missing += $s.Name }
}
if ($missing.Count -gt 0 -or $compilerProcess.ExitCode -ne 0) {
    Write-Host "Compile failed, missing output: $($missing -join ', ')" -ForegroundColor Red
    ((Get-Content $cerr -Raw) -split "`r|`n") |
        Where-Object { $_ -match "rror|ailed" } | Select-Object -First 20
    throw "Compile failed"
}

if ($CompileOnly) {
    Write-Host "[3/4] Skipping the pack (-CompileOnly)"
    Write-Host "[4/4] Skipping the PCK swap (-CompileOnly)"
    Write-Host ""
    Write-Host ("Done: {0} .gdc files -> {1}" -f $sources.Count, $out) -ForegroundColor Green
    Write-Host "      Next: tools\build_mpml_mod.ps1 -Out dist\<build>\mp8_support -Godot <Godot console exe> -OriginalPack <vanilla Machine Party.pck>" -ForegroundColor Green
    return
}

Write-Host "[3/4] Packing from .orig"
$pargs = @("--headless", "--pck-patch=`"$orig`"")
foreach ($s in $sources) {
    # patch\modules\multiplayer\network_manager.gd
    #   -> res://modules/multiplayer/network_manager.gdc
    $rel = $s.FullName.Substring($p.Length + 1) -replace '\\', '/' -replace '\.gd$', '.gdc'
    $gdc = Join-Path $out ($s.BaseName + ".gdc")
    $pargs += "--patch-file=$gdc=res://$rel"
    Write-Host ("      res://{0}" -f $rel)
}
$newPck = Join-Path $gt "new.pck"
if (Test-Path $newPck) { Remove-Item $newPck -Force }
$pargs += "--output=`"$newPck`""

Start-Process $exe -ArgumentList $pargs -WindowStyle Hidden -Wait `
    -RedirectStandardError (Join-Path $env:TEMP "mp8_pack.err")

if (-not (Test-Path $newPck)) { throw "Pack failed: no new.pck produced" }

# -- [3b] Trim the 28 x 00 + "GDPC" trailer gdre's --pck-patch appends (an embedded-PCK end marker) --
# The engine ignores it, but MachinePartyModLoader's index parser needs the index to end at the end of
# the file ("Could not locate the file index"), so with it MPML cannot install beside this build.
# Trimmed only on the exact pattern: another gdre may not write it, and a blind trim would cut real data.
$TRAILER = 32
$tail = New-Object byte[] $TRAILER
$fsr = [System.IO.File]::OpenRead($newPck)
try {
    $pckLen = $fsr.Length
    if ($pckLen -gt $TRAILER) {
        $fsr.Seek($pckLen - $TRAILER, 'Begin') | Out-Null
        $fsr.Read($tail, 0, $TRAILER) | Out-Null
    }
} finally { $fsr.Close() }

# Expected: 28 zero bytes, then "GDPC" (0x47 0x44 0x50 0x43).
$looksLikeTrailer = ($pckLen -gt $TRAILER) -and
                    ($tail[28] -eq 0x47) -and ($tail[29] -eq 0x44) -and
                    ($tail[30] -eq 0x50) -and ($tail[31] -eq 0x43)
if ($looksLikeTrailer) {
    for ($i = 0; $i -lt 28; $i++) { if ($tail[$i] -ne 0) { $looksLikeTrailer = $false; break } }
}

if ($looksLikeTrailer) {
    $fsw = [System.IO.File]::Open($newPck, 'Open', 'Write')
    try { $fsw.SetLength($pckLen - $TRAILER) } finally { $fsw.Close() }

    # The index offset in the header at 0x20 must still fall inside the file. A bad trim fails here,
    # before new.pck replaces the live PCK.
    $fsc = [System.IO.File]::OpenRead($newPck)
    try {
        $hdr = New-Object byte[] 40
        $fsc.Read($hdr, 0, 40) | Out-Null
        $newLen = $fsc.Length
    } finally { $fsc.Close() }
    $dirOff = [System.BitConverter]::ToUInt64($hdr, 32)
    if ($dirOff -ge $newLen) {
        throw "Check after trimming the trailer failed: index offset $dirOff is past the file length $newLen - PCK not swapped, the live one is unchanged"
    }
    Write-Host ("      Trimmed the {0}-byte embedded-PCK trailer (28x00 + GDPC); untrimmed, players cannot install MPML" -f $TRAILER)
} else {
    Write-Host "      The trailer is not the expected 28x00 + GDPC, left as is (no trim, safe)" -ForegroundColor Yellow
    Write-Host "         gdre may have changed its output. Players will not be able to install MachinePartyModLoader. See build.ps1 section [3b]." -ForegroundColor Yellow
}

Write-Host "[4/4] Swapping in the new PCK"
$live = Join-Path $gt "Machine Party.pck"
if (Test-Path $live) { Remove-Item $live -Force }
Rename-Item $newPck "Machine Party.pck" -Force

$info = Get-Item $live
Write-Host ""
Write-Host ("Done: {0}  {1:N0} bytes  {2}" -f $info.Name, $info.Length, $info.LastWriteTime) -ForegroundColor Green
