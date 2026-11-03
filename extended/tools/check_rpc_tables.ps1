# Compares the @rpc declarations of every game script this build replaces (patch\) against the game's
# own (src\): names, mode, sync, transfer mode, channel and parameters, the extends line, and rpc_config
# calls. Godot 4.5 sends an RPC as its index in the node's RPC names sorted by code point
# (scene_rpc_interface.cpp, _parse_rpc_config), so any difference here makes a mixed room with vanilla
# peers run the wrong method or drop the call. Exits 1 on any difference (D115).
param(
    [string]$Vanilla = '',
    [string]$Patched = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Vanilla) { $Vanilla = Join-Path $root 'src' }
if (-not $Patched) { $Patched = Join-Path $root 'patch' }
$Vanilla = [IO.Path]::GetFullPath($Vanilla).TrimEnd('\','/')
$Patched = [IO.Path]::GetFullPath($Patched).TrimEnd('\','/')
foreach ($dir in @($Vanilla, $Patched)) { if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "Missing folder: $dir" } }

# Godot's defaults for a bare @rpc: authority, call_remote, unreliable, channel 0. Arguments may come in
# any order, so each declaration is reduced to the four values.
function Get-RpcConfig([string]$Arguments) {
    $config = [ordered]@{ mode = 'authority'; sync = 'call_remote'; transfer = 'unreliable'; channel = '0' }
    foreach ($token in [regex]::Matches($Arguments, '"([^"]*)"|(\d+)')) {
        $value = if ($token.Groups[1].Success) { $token.Groups[1].Value } else { $token.Groups[2].Value }
        switch -Regex ($value) {
            '^(any_peer|authority)$' { $config.mode = $value }
            '^(call_local|call_remote)$' { $config.sync = $value }
            '^(reliable|unreliable|unreliable_ordered)$' { $config.transfer = $value }
            '^\d+$' { $config.channel = $value }
            default { throw "Unknown @rpc argument: $value" }
        }
    }
    return ($config.Values -join ',')
}

# Returns name -> "config | parameters" for each @rpc function, and the extends line. Signatures and
# annotations may span lines, and default values may hold parentheses.
function Read-Script([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    # Ordinal, as Godot's names, sort and checksum are: a PowerShell @{} would match names that differ in case.
    $rpcs = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $count = [regex]::Matches($text, '(?m)^[ \t]*@rpc\b').Count
    foreach ($m in [regex]::Matches($text, '(?ms)^[ \t]*@rpc\b(?:\s*\((?<args>[^)]*)\))?(?:\s*@\w+(?:\([^)]*\))?)*\s*(?:static\s+)?func\s+(?<name>\w+)\s*\(')) {
        $depth = 1
        $i = $m.Index + $m.Length
        $start = $i
        while ($depth -gt 0) {
            if ($i -ge $text.Length) { throw "Unclosed parameter list for $($m.Groups['name'].Value) in $Path" }
            $c = $text[$i]
            if ($c -eq '(') { $depth++ } elseif ($c -eq ')') { $depth-- }
            $i++
        }
        $params = ($text.Substring($start, $i - 1 - $start) -replace '\s', '').TrimEnd(',')
        $rpcs[$m.Groups['name'].Value] = (Get-RpcConfig $m.Groups['args'].Value) + ' | ' + $params
    }
    if ($rpcs.Count -ne $count) { throw "$Path has $count @rpc annotations but $($rpcs.Count) parsed functions" }
    $extends = [regex]::Match($text, '(?m)^(?:class_name\s+\w+\s+)?extends\s+(\S+)').Groups[1].Value
    $className = [regex]::Match($text, '(?m)^class_name\s+(\w+)').Groups[1].Value
    $rpcConfig = [regex]::Matches($text, '\brpc_config\s*\(').Count
    return @{ rpcs = $rpcs; extends = $extends; className = $className; rpcConfig = $rpcConfig }
}

function Get-SortedNames($Table) {
    $names = [string[]]@($Table.Keys)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    return $names
}

$added = 0; $removed = 0; $changed = 0; $shifted = 0; $extendsChanged = 0; $configCalls = 0
$differing = New-Object System.Collections.Generic.List[object]
$newScripts = New-Object System.Collections.Generic.List[string]
foreach ($file in Get-ChildItem -LiteralPath $Patched -Recurse -File -Filter '*.gd' | Sort-Object FullName) {
    $rel = $file.FullName.Substring($Patched.Length + 1)
    $vanillaPath = Join-Path $Vanilla $rel
    if (-not (Test-Path -LiteralPath $vanillaPath)) { $newScripts.Add($rel); continue }
    $a = Read-Script $vanillaPath
    $b = Read-Script $file.FullName
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($name in Get-SortedNames $b.rpcs) {
        if (-not $a.rpcs.ContainsKey($name)) { $lines.Add("  + $name  ($($b.rpcs[$name]))"); $added++ }
        elseif ($a.rpcs[$name] -cne $b.rpcs[$name]) { $lines.Add("  ~ $name  ($($a.rpcs[$name]))  ->  ($($b.rpcs[$name]))"); $changed++ }
    }
    foreach ($name in Get-SortedNames $a.rpcs) {
        if (-not $b.rpcs.ContainsKey($name)) { $lines.Add("  - $name  ($($a.rpcs[$name]))"); $removed++ }
    }
    $sa = Get-SortedNames $a.rpcs
    $sb = Get-SortedNames $b.rpcs
    $moved = @($sa | Where-Object { $sb -ccontains $_ -and [Array]::IndexOf($sa, $_) -ne [Array]::IndexOf($sb, $_) })
    if ($moved.Count -gt 0) { $lines.Add("  IDs shifted: $($moved.Count) of the game's $($sa.Count)"); $shifted++ }
    if ($a.extends -cne $b.extends) { $lines.Add("  extends $($a.extends) -> $($b.extends)"); $extendsChanged++ }
    if ($b.rpcConfig -ne $a.rpcConfig) { $lines.Add("  rpc_config calls: $($a.rpcConfig) -> $($b.rpcConfig)"); $configCalls++ }
    if ($lines.Count -gt 0) {
        Write-Host $rel.Replace('\', '/')
        $lines | ForEach-Object { Write-Host $_ }
        $differing.Add(@{ rel = $rel; className = $a.className })
    }
}

# A node's table includes its base classes' RPCs, so a game script that extends a differing one differs too.
if ($differing.Count -gt 0) {
    $vanillaScripts = Get-ChildItem -LiteralPath $Vanilla -Recurse -File -Filter '*.gd'
    foreach ($d in $differing) {
        $resPath = 'res://' + $d.rel.Replace('\', '/')
        $pattern = '(?m)^(?:class_name\s+\w+\s+)?extends\s+(?:"' + [regex]::Escape($resPath) + '"'
        if ($d.className) { $pattern += '|' + [regex]::Escape($d.className) + '\b' }
        $pattern += ')'
        foreach ($s in $vanillaScripts) {
            if ([regex]::IsMatch([IO.File]::ReadAllText($s.FullName), $pattern)) {
                Write-Host "$($d.rel.Replace('\', '/')) is inherited by $($s.FullName.Substring($Vanilla.Length + 1).Replace('\', '/'))"
            }
        }
    }
}

foreach ($n in $newScripts) { Write-Host "new script, not the game's (not compared): $($n.Replace('\', '/'))" }
$total = $added + $removed + $changed + $shifted + $extendsChanged + $configCalls
Write-Host ("RPC tables: {0} added, {1} removed, {2} changed, IDs shifted in {3} scripts, {4} extends changed, {5} rpc_config differences, in {6} of the game's scripts" -f $added, $removed, $changed, $shifted, $extendsChanged, $configCalls, $differing.Count)
if ($total -gt 0) { exit 1 }
exit 0
