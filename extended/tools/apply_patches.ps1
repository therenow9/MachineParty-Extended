# Machine Party 8 Player Support: apply patches\ to the src\ you recovered yourself
#
# The mod ships diffs, not whole scripts: those are mostly the game's own decompiled code, which is
# not distributed. Recover src\ from your own copy of the game, then run this to get a patch\
# byte-identical to the author's.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\apply_patches.ps1
#   powershell -ExecutionPolicy Bypass -File tools\apply_patches.ps1 -Src D:\mp\src
#
# Prerequisites: docs\BUILD.md (gdre_tools v2.6.4, the game at v2.1.2, git)

param(
    [string] $Src = "",       # the recovered game scripts, default <repo>\src
    [string] $Out = "",       # output folder, default <repo>\patch
    [switch] $Force           # empty the output folder first if it exists
)

$ErrorActionPreference = "Stop"

$root    = Split-Path -Parent $PSScriptRoot
$patches = Join-Path $root "patches"

if ($Src -eq "") { $Src = Join-Path $root "src" }
if ($Out -eq "") { $Out = Join-Path $root "patch" }

if (-not (Test-Path $patches)) { throw "Not found: $patches" }
if (-not (Test-Path $Src)) {
    throw @"
Not found: $Src

Recover the scripts from your own copy of the game's PCK with gdre_tools first; docs\BUILD.md has the steps.
In short:
  gdre_tools.exe --headless --recover="<game folder>\Machine Party.pck" --output="$Src"
"@
}

$git = (Get-Command git -ErrorAction SilentlyContinue)
if ($null -eq $git) { throw "git is required (patches are applied with git apply)" }

$list = Get-ChildItem $patches -Recurse -Filter "*.patch" -File
if ($list.Count -eq 0) { throw "patches\ has no .patch files" }

if (Test-Path $Out) {
    if ($Force) { Remove-Item $Out -Recurse -Force }
    else { throw "$Out already exists. Rerun with -Force if it may be overwritten." }
}
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path

Write-Host "Applying patches: $($list.Count)"

$missing = @()
$failed  = @()
$ok      = 0

# $Out defaults to inside the repo (<repo>\patch). Inside a repo, git apply resolves patch paths from
# the repo root, prints "Skipped patch" when they do not match and still returns 0. With $Out's parent
# as the ceiling, git finds no enclosing repo and applies relative to the current folder.
$ceilingBefore = $env:GIT_CEILING_DIRECTORIES
$env:GIT_CEILING_DIRECTORIES = Split-Path -Parent $Out
try {
foreach ($p in $list) {
    # patches\modules\multiplayer\network_manager.gd.patch
    #   -> modules\multiplayer\network_manager.gd
    $rel = $p.FullName.Substring($patches.Length + 1)
    $rel = $rel.Substring(0, $rel.Length - 6)      # strip .patch

    $from = Join-Path $Src $rel
    if (-not (Test-Path $from)) { $missing += $rel; continue }

    $dest = Join-Path $Out $rel
    New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null
    Copy-Item $from $dest -Force

    # Both -c are needed: with core.autocrlf on (common on Windows) apply writes CRLF, and the output
    # still compiles but no longer matches the author's byte for byte.
    Push-Location $Out
    git -c core.autocrlf=false -c core.eol=lf apply --whitespace=nowarn "$($p.FullName)" 2>&1 | Out-Null
    $code = $LASTEXITCODE
    Pop-Location

    # Every patch changes its file, so an output identical to the source failed, whatever the exit code.
    if ($code -ne 0 -or (Get-FileHash $dest).Hash -eq (Get-FileHash $from).Hash) { $failed += $rel } else { $ok++ }
}
} finally {
    $env:GIT_CEILING_DIRECTORIES = $ceilingBefore
}

Write-Host ""
if ($missing.Count -gt 0) {
    Write-Host "These files are missing from src\ ($($missing.Count)):" -ForegroundColor Red
    foreach ($x in $missing) { Write-Host "    $x" -ForegroundColor Red }
    Write-Host "-> Most likely the wrong game version. This mod targets v2.1.2;" -ForegroundColor Yellow
    Write-Host "  after a game update, wait for an updated mod or port it yourself with docs\UPDATING.md." -ForegroundColor Yellow
}
if ($failed.Count -gt 0) {
    Write-Host "These patches do not apply ($($failed.Count)):" -ForegroundColor Red
    foreach ($x in $failed) { Write-Host "    $x" -ForegroundColor Red }
    Write-Host "-> Two common causes:" -ForegroundColor Yellow
    Write-Host "  1. the recovery used a gdre other than v2.6.4 (the decompiled lines differ);" -ForegroundColor Yellow
    Write-Host "  2. the game is not v2.1.2." -ForegroundColor Yellow
}
if ($missing.Count -gt 0 -or $failed.Count -gt 0) {
    throw "Not every patch applied: $ok of $($list.Count) succeeded"
}

Write-Host "All applied: $ok -> $Out" -ForegroundColor Green
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -File tools\build.ps1 -CompileOnly" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -File tools\build_mpml_mod.ps1 -Out dist\<build>\mp8_support -Godot <Godot console exe> -OriginalPack <vanilla Machine Party.pck>" -ForegroundColor Yellow
