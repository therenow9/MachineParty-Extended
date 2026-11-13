<#
.SYNOPSIS
  Builds the release zips into dist/: our three mods on their own, and Machine Party: Extended's two bundles,
  each one machine_party_extended/ folder (Extended's build, id mp8_support) with our mods in subfolders, which
  Extended's main.gd starts.
.EXAMPLE
  pwsh ./tools/make_release.ps1                       # Extended from the newest extended/dist/mp8-b<N>
  pwsh ./tools/make_release.ps1 -Mp8Build extended/dist/mp8-b95/mp8_support
  pwsh ./tools/make_release.ps1 -Extract $env:TEMP/release-check   # also unpacks each zip as-is, for run_selftest.sh --mods-from
  pwsh ./tools/make_release.ps1 -Uncommitted -Out $env:TEMP/zips    # a check before committing; never into dist/
#>
param(
    [string]$Mp8Build,
    [string]$Out,
    [string]$Extract,
    [switch]$Uncommitted
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ext = Join-Path $repo 'extended'
$repoUrl = 'https://github.com/therenow9/MachineParty-Extended'
# Relative paths resolve against the shell's location, which a dot-run script doesn't share with .NET.
function Resolve-Arg([string]$Path) { [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)).TrimEnd('\','/') }
if (-not $Out) { $Out = Join-Path $repo 'dist' }
$Out = Resolve-Arg $Out
$dist = Resolve-Arg (Join-Path $repo 'dist')
if ($Uncommitted -and ([string]::Equals($Out, $dist, [StringComparison]::OrdinalIgnoreCase) -or $Out.StartsWith($dist + '\', [StringComparison]::OrdinalIgnoreCase))) { throw '-Uncommitted zips never go in dist/: pass -Out outside it' }

# id, the README's section heading and the zip's name.
$mods = [ordered]@{
    couch_lobby      = @{ Name = 'Better Couch Lobby';          Zip = 'BetterCouchLobby' }
    more_cosmetics   = @{ Name = 'More Cosmetics';              Zip = 'MoreCosmetics' }
    gamecube_support = @{ Name = 'GameCube Controller Support'; Zip = 'GameCubeControllerSupport' }
}
# A bundle's one folder. The loader never checks a folder's name against its id, which stays mp8_support.
$bundleFolder = 'machine_party_extended'
$buildNames = @('BUILDINFO.json','main.gd','mod.json','mp8_net.gd','mp8_support_overlay.zip','title_extended.png','vanilla_md5.json')

function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Hash-Bytes([byte[]]$Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)) }

# --- Extended's build: a shipped build, exactly the build script's files, its overlay intact ---
if (-not $Mp8Build) {
    $Mp8Build = Get-ChildItem -LiteralPath (Join-Path $ext 'dist') -Directory |
        Where-Object { $_.Name -match '^mp8-b(\d+)$' } | Sort-Object { [int]($_.Name -replace '^mp8-b', '') } |
        Select-Object -Last 1 | ForEach-Object { Join-Path $_.FullName 'mp8_support' }
    if (-not $Mp8Build) { throw "No build under $ext\dist (mp8-b<N>\mp8_support); pass -Mp8Build" }
}
$Mp8Build = Resolve-Arg $Mp8Build
$found = @(Get-ChildItem -LiteralPath $Mp8Build -Force | ForEach-Object { if ($_.PSIsContainer) { $_.Name + '/' } else { $_.Name } } | Sort-Object)
if (Compare-Object $found $buildNames) { throw "$Mp8Build is not one build's output: it holds $($found -join ', ')" }
$info = Read-Json (Join-Path $Mp8Build 'BUILDINFO.json')
if ($info.test_build -or (Split-Path -Leaf (Split-Path -Parent $Mp8Build)) -like '*-test*') { throw "$Mp8Build is a test build; a test build is never released" }
$mp8Mod = Read-Json (Join-Path $Mp8Build 'mod.json')
$manifest = Read-Json (Join-Path $Mp8Build 'vanilla_md5.json')
if ($mp8Mod.id -ne 'mp8_support') { throw "$Mp8Build\mod.json is '$($mp8Mod.id)', not mp8_support" }
# An older wrapper starts nothing in its subfolders, so a bundle built on it would ship mods that never run, and
# one without the two-folder check would mount twice beside a build's mods/mp8_support.
foreach ($needed in @('mpml_dir', 'INSTALLED_TWICE')) {
    if (-not (Select-String -LiteralPath (Join-Path $Mp8Build 'main.gd') -SimpleMatch $needed -Quiet)) { throw "$Mp8Build's main.gd lacks $needed (an older build, without the bundle checks)" }
}
if ($manifest.overlay_sha256 -ne (Get-FileHash -LiteralPath (Join-Path $Mp8Build 'mp8_support_overlay.zip') -Algorithm SHA256).Hash.ToLower()) { throw "$Mp8Build's overlay does not match its vanilla_md5.json" }
$mp8Version = [string]$mp8Mod.version
# The build script's own normalisation (build_mpml_mod.ps1): x.y.0 is tagged x.y, a suffix kept.
if ($info.mod_tag -ne ('mp-extended-' + ($mp8Version -replace '^(\d+\.\d+)\.0(?=-|$)', '$1'))) { throw "$Mp8Build is tagged $($info.mod_tag) but its mod.json says $mp8Version" }

# --- Everything that goes in a zip comes from a committed tree: our mods' tracked files, the READMEs and notices ---
$inputs = @('mods/README.md','LICENSE','NOTICE.md','README.md','extended/LICENSE','extended/NOTICE') + @($mods.Keys | ForEach-Object { "mods/$_" })
$dirty = git -C $repo status --porcelain --untracked-files=no -- @inputs
if ($dirty -and -not $Uncommitted) { throw "Uncommitted changes in what the zips are made from; release from a committed tree (or check with -Uncommitted):`n$($dirty -join "`n")" }
if ($dirty) { Write-Warning "Built from uncommitted changes, for a check only:`n$($dirty -join "`n")" }
$modFiles = @{}
foreach ($id in $mods.Keys) {
    $files = @(git -C $repo ls-files -- "mods/$id")
    if (-not $files) { throw "git tracks no files under mods/$id" }
    $modFiles[$id] = $files
    $mods[$id].Version = [string](Read-Json (Join-Path $repo "mods/$id/mod.json")).version
}

# --- README.txt and the notices, made from the READMEs at build time ---
function Get-Section([string[]]$Lines, [string]$Heading) {
    $start = [Array]::IndexOf($Lines, $Heading)
    if ($start -lt 0) { throw "README has no '$Heading' section" }
    $end = $start + 1
    while ($end -lt $Lines.Count -and $Lines[$end] -notmatch '^(## |---$)') { $end++ }
    , @($Lines[$start..($end - 1)])
}
# A relative link resolves from its README's folder ('' for the root's, 'mods' for the mods'), as GitHub resolves it.
function Resolve-Link([string]$Url, [string]$Folder) {
    if ($Url -match '^https?://') { return $Url }
    if ($Url.StartsWith('#')) { return $(if ($Folder) { "$repoUrl/tree/main/$Folder$Url" } else { "$repoUrl$Url" }) }
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($p in (@($Folder -split '/') + @($Url -split '/'))) {
        if ($p -eq '..') { if ($parts.Count -eq 0) { throw "link climbs out of the repo: $Url" }; $parts.RemoveAt($parts.Count - 1) }
        elseif ($p -and $p -ne '.') { $parts.Add($p) }
    }
    "$repoUrl/blob/main/$($parts -join '/')"
}
function ConvertTo-Text([string[]]$Lines, [string]$Folder) {
    $outLines = @()
    foreach ($l in $Lines) {
        if ($l -match '^```' -or $l -match '^!\[') { continue }
        $l = [regex]::Replace($l, '\[([^\]]+)\]\(([^)]+)\)', {
            param($m)
            "$($m.Groups[1].Value) ($(Resolve-Link $m.Groups[2].Value $Folder))"
        })
        $l = $l -replace '\*\*', '' -replace '`', ''
        if ($l -match '^(#{1,3}) (.+)$') {
            $outLines += $Matches[2]
            $outLines += ([string]$(if ($Matches[1].Length -le 2) { '=' } else { '-' })) * $Matches[2].Length
        } else { $outLines += $l }
    }
    $outLines
}
function Join-Text([string[]]$Lines) { (($Lines -join "`r`n").Trim() -replace "(`r`n){3,}", "`r`n`r`n") + "`r`n" }

$rootReadme = Get-Content -LiteralPath (Join-Path $repo 'mods/README.md') -Encoding UTF8
$extReadme = Get-Content -LiteralPath (Join-Path $repo 'README.md') -Encoding UTF8
$rootCommon = @{
    Requirements = Get-Section $rootReadme '## Requirements'
    Install      = Get-Section $rootReadme '## Install'
    Credits      = Get-Section $rootReadme '## Credits'
    License      = Get-Section $rootReadme '## License'
}
# The top table's line for each mod: | [Name](#anchor) | what it does |
function Get-Row([string]$Name) {
    $row = $rootReadme | Where-Object { $_ -like "| ``[$Name``]*" } | Select-Object -First 1
    if (-not $row) { throw "README's mod table has no row for $Name" }
    $row
}
function Get-Blurb([string]$Name) { ((Get-Row $Name) -split '\|')[2].Trim() }
function Get-ModUrl([string]$Name) {
    if ((Get-Row $Name) -notmatch '^\| \[[^\]]+\]\((#[^)]+)\)') { throw "README's mod table row for $Name has no #anchor" }
    Resolve-Link $Matches[1] 'mods'
}
# Inside a bundle the install steps are the bundle's own (its README.txt, one folder up).
function ModReadme([string]$Id, [switch]$Hosted) {
    $m = $mods[$Id]
    $setup = if ($Hosted) { @("Part of Machine Party: Extended's bundle, installed and removed with it: see ../README.txt.") }
             else { $rootCommon.Requirements + '' + $rootCommon.Install }
    $section = Get-Section $rootReadme "## $($m.Name)"
    # Inside the bundle, the section's "Not needed if Machine Party: Extended is installed" sentence says the opposite of
    # $setup, so it goes and the rest of its line (the Nexus link) stays. A reworded line throws rather than slip through.
    if ($Hosted) {
        $notNeeded = '^Not needed if \[Machine Party: Extended\]\([^)]*\) is installed: [^.]*\.\s*'
        $hits = @($section | Where-Object { $_ -match '^Not needed if' })
        if ($hits.Count -gt 0) {
            if ($hits.Count -ne 1 -or $hits[0] -notmatch $notNeeded) { throw "$($m.Name)'s README section has a 'Not needed if' line make_release.ps1 can't cut: $($hits -join ' | ')" }
            $section = @($section | ForEach-Object { if ($_ -match '^Not needed if') { $_ -replace $notNeeded, '' } else { $_ } })
        }
    }
    $lines = @("# $($m.Name) $($m.Version)", '', (Get-ModUrl $m.Name), '') + $setup + '' +
        $section + '' + $rootCommon.Credits + '' + $rootCommon.License
    Join-Text (ConvertTo-Text $lines 'mods')
}
function BundleReadme([string[]]$Ids) {
    $firstHeading = 1
    while ($firstHeading -lt $extReadme.Count -and $extReadme[$firstHeading] -notmatch '^## ') { $firstHeading++ }
    if ($firstHeading -ge $extReadme.Count) { throw "Extended's README has no '## ' section" }
    # The README's download buttons and "All downloads" link point at the release this zip came from. Exactly those
    # three lines go; any other line with a download arrow or "releases/download" means the wording moved.
    $all = @($extReadme[1..($firstHeading - 1)])
    $intro = @($all | Where-Object { $_ -notmatch '^### \[⬇ Download|^\[All downloads\]' })
    $left = @($intro | Where-Object { $_ -match '⬇|releases/download' })
    if ($all.Count - $intro.Count -ne 3 -or $left) { throw "Extended's README intro: expected 2 download buttons and the 'All downloads' line, cut $($all.Count - $intro.Count)$(if ($left) { "; left: $($left -join ' | ')" })" }
    $included = @('## What this zip holds', '', "One folder, $bundleFolder, holding:", '', "- Machine Party: Extended $mp8Version")
    foreach ($id in $Ids) { $included += "- $($mods[$id].Name) $($mods[$id].Version) ($bundleFolder/$id): $(Get-Blurb $mods[$id].Name)" }
    $included += @('', "Each of the other mods is described on $repoUrl/tree/main/mods.")
    $lines = @("# Machine Party: Extended $mp8Version", '', $repoUrl, '') + $intro + '' + $included + '' +
        (Get-Section $extReadme '## Requirements') + '' + (Get-Section $extReadme '## Install') + '' +
        (Get-Section $extReadme '## Online play') + '' + (Get-Section $extReadme '## License and credits')
    Join-Text (ConvertTo-Text $lines '')
}

# --- The zips: each entry is a name and either a file on disk or text ---
# Each mod folder carries its README.txt and the licence and notice it names (MIT asks for the notice in every
# copy), so nothing lands loose in mods/ and deleting the folder removes them too. In a bundle, $Prefix
# puts the folder inside the bundle's.
function ModEntries([string]$Id, [string]$Prefix = '') {
    foreach ($f in $modFiles[$Id]) { @{ Name = $Prefix + ($f -replace '^mods/', ''); Path = (Join-Path $repo $f) } }
    @{ Name = "$Prefix$Id/README.txt"; Text = (ModReadme $Id -Hosted:([bool]$Prefix)) }
    @{ Name = "$Prefix$Id/LICENSE"; Path = (Join-Path $repo 'LICENSE') }
    @{ Name = "$Prefix$Id/NOTICE.md"; Path = (Join-Path $repo 'NOTICE.md') }
}
function Mp8Entries([string[]]$Ids) {
    foreach ($n in $buildNames) { @{ Name = "$bundleFolder/$n"; Path = (Join-Path $Mp8Build $n) } }
    @{ Name = "$bundleFolder/README.txt"; Text = (BundleReadme $Ids) }
    @{ Name = "$bundleFolder/LICENSE"; Path = (Join-Path $ext 'LICENSE') }
    @{ Name = "$bundleFolder/NOTICE"; Path = (Join-Path $ext 'NOTICE') }
}

$zips = [ordered]@{}
foreach ($id in $mods.Keys) { $zips["$($mods[$id].Zip)-$($mods[$id].Version).zip"] = @(ModEntries $id) }
foreach ($bundle in @(@{ Suffix = '-with-GameCube'; Ids = @('couch_lobby','more_cosmetics','gamecube_support') },
                      @{ Suffix = '';               Ids = @('couch_lobby','more_cosmetics') })) {
    $entries = @(Mp8Entries $bundle.Ids)
    foreach ($id in $bundle.Ids) { $entries += @(ModEntries $id "$bundleFolder/") }
    $zips["Machine-Party-Extended-$mp8Version$($bundle.Suffix).zip"] = $entries
}

New-Item -ItemType Directory -Force $Out | Out-Null
foreach ($name in $zips.Keys) { if (Test-Path -LiteralPath (Join-Path $Out $name)) { throw "$Out\$name exists; bump the version or remove it first" } }
if ($Extract) {
    $Extract = Resolve-Arg $Extract
    foreach ($name in $zips.Keys) { if (Test-Path -LiteralPath (Join-Path $Extract ([IO.Path]::GetFileNameWithoutExtension($name)))) { throw "$Extract already holds $name's folder" } }
}

$utf8 = New-Object Text.UTF8Encoding($false)
foreach ($name in $zips.Keys) {
    $final = Join-Path $Out $name
    $partial = "$final.partial"
    $expected = @{}
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial }
    $fs = [IO.File]::Open($partial, [IO.FileMode]::CreateNew)
    try {
        $zip = [IO.Compression.ZipArchive]::new($fs, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($e in $zips[$name]) {
                $bytes = if ($e.Path) { [IO.File]::ReadAllBytes($e.Path) } else { $utf8.GetBytes($e.Text) }
                $expected[$e.Name] = Hash-Bytes $bytes
                $s = $zip.CreateEntry($e.Name, [IO.Compression.CompressionLevel]::Optimal).Open()
                try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $fs.Dispose() }

    # The tree check: the zip read back holds exactly the expected entries, byte for byte, and no game data
    # (a pack dump's compiled scripts, imported textures, scenes, resources or audio).
    $read = [IO.Compression.ZipFile]::OpenRead($partial)
    try {
        $names = @($read.Entries.FullName)
        $bad = @($names | Where-Object { $_ -match '\.(pck|gdc|import|ctex|stex|scn|res|oggvorbisstr|sample)$|(^|/)tools/|\\' })
        if ($bad) { throw "$name holds entries that never ship: $($bad -join ', ')" }
        $diff = Compare-Object @($names | Sort-Object) @($expected.Keys | Sort-Object)
        if ($diff) { throw "$name's entries differ from the expected tree:`n$($diff | Out-String)" }
        foreach ($entry in $read.Entries) {
            $s = $entry.Open(); $ms = [IO.MemoryStream]::new()
            try { $s.CopyTo($ms) } finally { $s.Dispose() }
            if ((Hash-Bytes $ms.ToArray()) -ne $expected[$entry.FullName]) { throw "$name`: $($entry.FullName) reads back different" }
        }
        $top = @($names | ForEach-Object { ($_ -split '/')[0] + $(if ($_ -like '*/*') { '/' } else { '' }) } | Sort-Object -Unique)
    } catch { $read.Dispose(); Remove-Item -LiteralPath $partial; throw } finally { $read.Dispose() }
    Move-Item -LiteralPath $partial -Destination $final
    "{0}  {1} entries  {2:N0} bytes  sha256 {3}" -f $name, $names.Count, (Get-Item -LiteralPath $final).Length, (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash
    "  top level: $($top -join ' ')"
    if ($Extract) { [IO.Compression.ZipFile]::ExtractToDirectory($final, (Join-Path $Extract ([IO.Path]::GetFileNameWithoutExtension($name)))) }
}
"Extended from $Mp8Build (mod_tag $($info.mod_tag), built $($info.built_utc))"
if ($Extract) { "Extracted under $Extract" }
