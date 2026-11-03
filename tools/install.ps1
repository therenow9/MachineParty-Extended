<#
.SYNOPSIS
  Copies a mod from this repo's mods/ folder into Machine Party's mods folder (or removes it).
.EXAMPLE
  ./tools/install.ps1                              # Better Couch Lobby
  ./tools/install.ps1 -ModId local_glasses -Uninstall   # a retired mod: removing needs no mods/ folder
  ./tools/install.ps1 -ModId gamecube_support
  ./tools/install.ps1 -ModId gamecube_support -Uninstall
  ./tools/install.ps1 -GameDir "D:\Games\Machine Party_Windows"
#>
param(
    [string]$ModId = 'couch_lobby',
    [string]$GameDir,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
# The id becomes a path under mods\ that -Uninstall deletes: '', '.' or '..' would name mods\ or the game folder.
if ($ModId -notmatch '^[A-Za-z0-9_]+$') { throw "'$ModId' is not a mod id (letters, digits and _ only)" }
$source = Join-Path $PSScriptRoot "..\mods\$ModId"
if (-not $Uninstall -and -not (Test-Path (Join-Path $source 'mod.json'))) {
    throw "No mod '$ModId' in $(Resolve-Path (Join-Path $PSScriptRoot '..\mods')). Available: $((Get-ChildItem (Join-Path $PSScriptRoot '..\mods') -Directory).Name -join ', ')"
}
$AppId = '4108000'

function Find-GameDir {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { $steam = 'C:\Program Files (x86)\Steam' }
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    $libraries = @($steam)
    if (Test-Path $vdf) {
        $libraries += Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' |
            ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\', '\' }
    }
    foreach ($lib in $libraries | Select-Object -Unique) {
        $manifest = Join-Path $lib "steamapps\appmanifest_$AppId.acf"
        if (-not (Test-Path $manifest)) { continue }
        $installDir = (Select-String -Path $manifest -Pattern '"installdir"\s+"([^"]+)"').Matches[0].Groups[1].Value
        $exe = Get-ChildItem (Join-Path $lib "steamapps\common\$installDir") -Recurse -Filter 'Machine Party.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) { return $exe.DirectoryName }
    }
    throw "Machine Party install not found. Pass -GameDir <folder containing 'Machine Party.exe'>."
}

if (-not $GameDir) { $GameDir = Find-GameDir }
$modsDir = Join-Path $GameDir 'mods'
$target = Join-Path $modsDir $ModId

# Replacing a loaded mod's files under a running game can break the session in progress.
if (Get-Process 'Machine Party' -ErrorAction SilentlyContinue) {
    throw "Machine Party is running. Close the game, then run this again."
}

if ($Uninstall) {
    if (-not (Test-Path $target)) { "Not installed: $target"; return }
    # Only a folder that is this mod: its mod.json names this id (or has none, and the folder name is the id).
    $manifest = Join-Path $target 'mod.json'
    if (-not (Test-Path $manifest)) { throw "$target has no mod.json; not removing it" }
    $id = (Get-Content $manifest -Raw | ConvertFrom-Json).id
    if ($id -and $id -ne $ModId) { throw "$target is mod '$id', not '$ModId'; not removing it" }
    Remove-Item $target -Recurse -Force
    "Removed $target"
    return
}

if (-not (Test-Path (Join-Path $GameDir 'MachinePartyModLoader.exe'))) {
    Write-Warning "MachinePartyModLoader.exe not found in $GameDir. Install the mod loader first: https://github.com/Krunk-theduck/MachinePartyModLoader"
}
New-Item -ItemType Directory -Force $modsDir | Out-Null
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Copy-Item $source $target -Recurse
"Installed to $target"
