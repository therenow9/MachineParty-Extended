# Builds the MPML package (the mod folder and its zip) without modifying the installed game or PCK.
# -TestBuild packs network_manager.gd compiled with MP8_TEST_BUILD = true, which unlocks every dev switch
# (D119), into a folder whose parent ends in -test; the shipped build never comes from it.
param(
    [string]$Godot = '',
    [string]$Out = '',
    [string]$OriginalPack = '',
    [string]$RepositoryRoot = '',
    [switch]$TestBuild
)
$ErrorActionPreference = 'Stop'
$root = if ($RepositoryRoot) { [IO.Path]::GetFullPath($RepositoryRoot) } else { Split-Path -Parent $PSScriptRoot }
if (-not $Godot) { $Godot = $env:GODOT }
if (-not $Godot) { $Godot = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' }
if (-not $Out) { $Out = Join-Path $root 'dist\mpml\mp8_support' }
if (-not [IO.Path]::IsPathRooted($Out)) { $Out = Join-Path $root $Out }
$Out = [IO.Path]::GetFullPath($Out).TrimEnd('\','/')
if (-not $OriginalPack) { $OriginalPack = Join-Path $root 'game_test\Machine Party.pck.orig' }
$OriginalPack = [IO.Path]::GetFullPath($OriginalPack)
$parent = Split-Path -Parent $Out
function Assert-UnlinkedPath([string]$Path) {
    $probe = [IO.Path]::GetFullPath($Path)
    while (-not (Test-Path -LiteralPath $probe)) { $probe = Split-Path -Parent $probe }
    $node = Get-Item -LiteralPath $probe
    while ($null -ne $node) {
        if ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked output path: $($node.FullName)" }
        $node = $node.Parent
    }
}
if ($TestBuild -and (Split-Path -Leaf $parent) -notlike '*-test') { throw 'A test build goes in a folder ending in -test (dist\mp8-b<N>-test\mp8_support)' }
if (-not $TestBuild -and (Split-Path -Leaf $parent) -like '*-test') { throw 'A -test folder holds only a test build (-TestBuild)' }
$gdre = Join-Path $root 'tools\gdre\gdre_tools.exe'
if ($TestBuild -and -not (Test-Path -LiteralPath $gdre)) { throw "Missing build input: $gdre" }
if (-not $parent -or $Out -eq $root -or $root.StartsWith($Out + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe MPML output directory' }
foreach ($protected in @('patch','patch_gdc','src','mpml','tools','game','game_test')) {
    $p = [IO.Path]::GetFullPath((Join-Path $root $protected))
    if ($Out -eq $p -or $Out.StartsWith($p + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Output overlaps input directory: $p" }
}
foreach ($needed in @($Godot, $OriginalPack, (Join-Path $root 'src'), (Join-Path $root 'patch'),(Join-Path $root 'patch_gdc'), (Join-Path $root 'mpml\mp8_support\main.gd'), (Join-Path $root 'mpml\mp8_support\mp8_net.gd'), (Join-Path $root 'mpml\mp8_support\mod.json'), (Join-Path $root 'mpml\mp8_support\title_extended.png'), (Join-Path $root 'tools\probe\build_mpml_mod.gd'))) {
    if (-not (Test-Path -LiteralPath $needed)) { throw "Missing build input: $needed" }
}
# A mixed room with vanilla peers calls RPCs by table index (D115), and a shipped build must read no dev
# switch (D116), and a text triple whose languages differ in shape empties its label (D173): any of them
# refuses the build, test builds included.
foreach ($check in @('check_rpc_tables.ps1','check_dev_switches.ps1','check_text_triples.ps1')) {
    $report = & pwsh -NoProfile -File (Join-Path $PSScriptRoot $check) -Vanilla (Join-Path $root 'src') -Patched (Join-Path $root 'patch') 2>&1
    if ($LASTEXITCODE -ne 0) { $report | ForEach-Object { Write-Host $_ }; throw "$check found differences (exit $LASTEXITCODE); no build" }
}
if ((Test-Path -LiteralPath $Out) -and -not (Test-Path -LiteralPath $Out -PathType Container)) { throw 'Out must name a package directory' }
Assert-UnlinkedPath $Out
Assert-UnlinkedPath (Join-Path $parent '.mpml-build.lock')
if (Test-Path -LiteralPath $Out) {
    if ((Get-Item -LiteralPath $Out).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Out must not be a linked directory' }
    $existing = @(Get-ChildItem -LiteralPath $Out -Force)
    $ownedNames = @('main.gd','mp8_net.gd','mod.json','title_extended.png','vanilla_md5.json','mp8_support_overlay.zip','BUILDINFO.json')
    if (@($existing | Where-Object { $_.PSIsContainer -or $_.Name -notin $ownedNames -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) }).Count) { throw 'Refusing to replace a directory containing non-package files' }
    if ($existing.Count) {
        $existingMod = Get-Content -LiteralPath (Join-Path $Out 'mod.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($existingMod.id -ne 'mp8_support') { throw 'Output directory does not belong to Machine Party: Extended' }
    }
}

function Hash-File([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Quote-Argument([string]$Value) { '"' + $Value + '"' }
function Remove-OwnedTree([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not $absolute.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing cleanup outside output parent: $absolute" }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
$sources = @(Get-ChildItem -LiteralPath (Join-Path $root 'patch') -Recurse -File -Filter '*.gd' | Sort-Object FullName)
if (-not $sources.Count) { throw 'No patch sources' }
if (@($sources | Group-Object BaseName | Where-Object Count -gt 1).Count) { throw 'Duplicate flat bytecode basenames' }
$inputs = [ordered]@{}
$records = @()
foreach ($source in $sources) {
    $compiled = Join-Path $root ('patch_gdc\' + $source.BaseName + '.gdc')
    if (-not (Test-Path -LiteralPath $compiled)) { throw "Missing compiled script: $compiled" }
    if ((Get-Item -LiteralPath $compiled).LastWriteTimeUtc -lt $source.LastWriteTimeUtc) { throw "Stale compiled script: $($source.Name). Run build.ps1 -CompileOnly." }
    if ((Get-Item -LiteralPath $compiled).Length -eq 0) { throw "Empty compiled script: $compiled" }
    $inputs[$source.FullName] = Hash-File $source.FullName
    $inputs[$compiled] = Hash-File $compiled
    $relative = $source.FullName.Substring((Join-Path $root 'patch').Length + 1).Replace('\','/')
    $records += [ordered]@{path=$relative; source_sha256=$inputs[$source.FullName]; bytecode_sha256=$inputs[$compiled]}
}
foreach ($inputPath in @($OriginalPack, (Join-Path $root 'mpml\mp8_support\main.gd'), (Join-Path $root 'mpml\mp8_support\mp8_net.gd'), (Join-Path $root 'mpml\mp8_support\mod.json'), (Join-Path $root 'mpml\mp8_support\title_extended.png'), (Join-Path $root 'tools\probe\build_mpml_mod.gd'))) { $inputs[$inputPath] = Hash-File $inputPath }
$network = Get-Content -LiteralPath (Join-Path $root 'patch\modules\multiplayer\network_manager.gd') -Raw -Encoding UTF8
$match = [regex]::Match($network, 'const MP8_VERSION_TAG:\s*String\s*=\s*"mp-extended-([A-Za-z0-9.-]+)"')
if (-not $match.Success) { throw 'Cannot read safe version tag' }
$version = $match.Groups[1].Value
$mod = Get-Content -LiteralPath (Join-Path $root 'mpml\mp8_support\mod.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$declared = [string]$mod.version
$normalized = $declared -replace '^(\d+\.\d+)\.0(?=-|$)', '$1'
if ($normalized -ne $version -or $mod.id -ne 'mp8_support') { throw 'mod.json identity/version does not match compiled-source tag' }
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$lock = [IO.File]::Open((Join-Path $parent '.mpml-build.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$id = [guid]::NewGuid().ToString('N')
$stage = Join-Path $parent ('.mpml-stage-' + $id)
$stagedPackage = Join-Path $stage 'mp8_support'
$zipName = 'Machine-Party-Extended-' + $version + $(if ($TestBuild) { '-TEST' } else { '' }) + '-MPML.zip'
$stagedZip = Join-Path $stage $zipName
$finalZip = Join-Path $parent $zipName
$backupOut = Join-Path $parent ('.mpml-old-package-' + $id)
$backupZip = Join-Path $parent ('.mpml-old-archive-' + $id)
$oldOut = $false; $oldZip = $false; $newOut = $false; $newZip = $false; $published = $false
try {
    # -Out names the mod directory; its archive is a sibling. Do not replace a
    # same-named sibling unless every archived file matches this existing Out.
    if (Test-Path -LiteralPath $finalZip) {
        Assert-UnlinkedPath $finalZip
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($finalZip)
        try {
            $files = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
            $expected = @('main.gd','mp8_net.gd','mod.json','title_extended.png','vanilla_md5.json','mp8_support_overlay.zip','BUILDINFO.json')
            if ($files.Count -ne $expected.Count -or @($files.FullName | Select-Object -Unique).Count -ne $expected.Count) { throw 'Unowned sibling MPML archive' }
            foreach ($entry in $files) {
                $name = $entry.FullName -replace '^mp8_support/', ''
                $local = Join-Path $Out $name
                if (-not $entry.FullName.StartsWith('mp8_support/') -or $name -notin $expected -or -not (Test-Path -LiteralPath $local -PathType Leaf)) { throw 'Unowned sibling MPML archive' }
                $sha = [Security.Cryptography.SHA256]::Create()
                $stream = $entry.Open()
                try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') } finally { $stream.Dispose(); $sha.Dispose() }
                if ($hash -ne (Hash-File $local)) { throw 'Sibling MPML archive does not match the selected output directory; use a new output parent' }
            }
        } finally { $zip.Dispose() }
    }
    New-Item -ItemType Directory -Path $stagedPackage -Force | Out-Null
    $stdout = Join-Path $stage 'godot.stdout.txt'; $stderr = Join-Path $stage 'godot.stderr.txt'
    $arguments = @('--headless','--path',(Quote-Argument (Join-Path $root 'tools\probe')),'--script','build_mpml_mod.gd','--','--mp8-root',(Quote-Argument $root),'--mp8-output',(Quote-Argument $stagedPackage),'--mp8-original',(Quote-Argument $OriginalPack))
    $override = $null
    if ($TestBuild) {
        # The one line that differs from the shipped build: exactly one match, or no build.
        $testSource = Join-Path $stage 'test\network_manager.gd'
        $testOut = Join-Path $stage 'test\gdc'
        New-Item -ItemType Directory -Path $testOut -Force | Out-Null
        $text = [IO.File]::ReadAllText((Join-Path $root 'patch\modules\multiplayer\network_manager.gd'))
        $flag = [regex]::new('(?m)^const MP8_TEST_BUILD: bool = false(?=\r?$)')
        if ($flag.Matches($text).Count -ne 1) { throw 'network_manager.gd must have exactly one "const MP8_TEST_BUILD: bool = false" line' }
        [IO.File]::WriteAllText($testSource, $flag.Replace($text, 'const MP8_TEST_BUILD: bool = true'), (New-Object Text.UTF8Encoding($false)))
        $compile = Start-Process -FilePath $gdre -ArgumentList @('--headless',('--compile=' + (Quote-Argument $testSource)),'--bytecode=4.5.2',('--output=' + (Quote-Argument $testOut))) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $stage 'gdre.stdout.txt') -RedirectStandardError (Join-Path $stage 'gdre.stderr.txt')
        $testGdc = Join-Path $testOut 'network_manager.gdc'
        if ($compile.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $testGdc) -or (Get-Item -LiteralPath $testGdc).Length -eq 0) { throw 'Test build: network_manager.gd did not compile' }
        $override = [ordered]@{ path = 'modules/multiplayer/network_manager.gd'; source_sha256 = (Hash-File $testSource); bytecode_sha256 = (Hash-File $testGdc) }
        $arguments += @('--mp8-gdc-override',(Quote-Argument ('network_manager.gdc=' + $testGdc)))
    }
    $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    # Reading Handle before WaitForExit keeps ExitCode readable afterwards (a .NET quirk with -PassThru).
    $null = $process.Handle
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'MPML Godot packaging timed out' }
    if ($process.ExitCode -ne 0 -or (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
        Get-Content -LiteralPath $stdout -Encoding UTF8
        Get-Content -LiteralPath $stderr -Encoding UTF8
        throw "MPML Godot packaging failed (exit $($process.ExitCode))"
    }
    foreach ($name in @('main.gd','mp8_net.gd','mod.json','title_extended.png','vanilla_md5.json','mp8_support_overlay.zip')) {
        if (-not (Test-Path -LiteralPath (Join-Path $stagedPackage $name) -PathType Leaf)) { throw "Missing staged output: $name" }
    }
    foreach ($path in $inputs.Keys) {
        if (-not (Test-Path -LiteralPath $path) -or (Hash-File $path) -ne $inputs[$path]) { throw "Build input changed during packaging: $path" }
    }
    $manifest = Get-Content -LiteralPath (Join-Path $stagedPackage 'vanilla_md5.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $overlay = Join-Path $stagedPackage 'mp8_support_overlay.zip'
    if ($manifest.schema -ne 1 -or $manifest.game_version -ne ('mp-extended-' + $version) -or $manifest.overlay_size -ne (Get-Item -LiteralPath $overlay).Length -or $manifest.overlay_sha256 -ne (Hash-File $overlay)) { throw 'Staged overlay integrity metadata does not match' }
    if (@($manifest.files.PSObject.Properties).Count -ne $sources.Count) { throw 'Staged original-file manifest has wrong count' }
    $info = [ordered]@{
        schema=1; mod_tag=('mp-extended-' + $version); built_utc=[DateTime]::UtcNow.ToString('o')
        original_pack_sha256=$inputs[$OriginalPack]; files=$records; test_build=[bool]$TestBuild
        verification_note='Source/bytecode hashes and freshness checks record these inputs; they do not prove how bytecode was compiled.'
    }
    if ($override) { $info['test_override'] = $override }
    [IO.File]::WriteAllText((Join-Path $stagedPackage 'BUILDINFO.json'), ($info | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    Compress-Archive -LiteralPath $stagedPackage -DestinationPath $stagedZip
    # Both outputs are complete before either existing output is touched.
    if (Test-Path -LiteralPath $Out) { Move-Item -LiteralPath $Out -Destination $backupOut; $oldOut=$true }
    if (Test-Path -LiteralPath $finalZip) { Move-Item -LiteralPath $finalZip -Destination $backupZip; $oldZip=$true }
    Move-Item -LiteralPath $stagedPackage -Destination $Out; $newOut=$true
    Move-Item -LiteralPath $stagedZip -Destination $finalZip; $newZip=$true
    $published=$true
    Write-Host "MPML package: $Out"
    Write-Host "MPML archive: $finalZip"
} catch {
    if (-not $published) {
        if ($newZip -and (Test-Path -LiteralPath $finalZip)) { Remove-Item -LiteralPath $finalZip -Force }
        if ($newOut) { Remove-OwnedTree $Out }
        if ($oldOut) { Move-Item -LiteralPath $backupOut -Destination $Out }
        if ($oldZip) { Move-Item -LiteralPath $backupZip -Destination $finalZip }
    }
    throw
} finally {
    if ($published) {
        if ($oldOut) { Remove-OwnedTree $backupOut }
        if ($oldZip -and (Test-Path -LiteralPath $backupZip)) { Remove-Item -LiteralPath $backupZip -Force }
    }
    Remove-OwnedTree $stage
    $lock.Dispose()
}
