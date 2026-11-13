# Checks that every command-line switch this build adds is read through NetworkManager.mp8_dev_args(),
# which is empty outside a test build or the editor, while the game's own switches stay as
# the game reads them. A line is ours when its text (trimmed) is not one of src\'s lines, so a moved or
# re-indented game line still counts as the game's. Exits 1 on any failure:
#   R1  a get_cmdline_args or get_cmdline_user_args call on a line of ours, other than mp8_dev_args()'s own;
#   R2  a switch literal ("mp8<word>", "-debug-tools", "-trailer") on a line of ours that reads none of
#       mp8_dev_args(), an mp8_args variable or an _mp8_arg* helper, unless the innermost `for` around it
#       loops over one; an mp8_args assigned from anything else; an _mp8_arg* helper that doesn't loop
#       over mp8_dev_args();
#   R3  a line of ours that reads the game's own argument variable, in the function that fills it.
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

$switch = '"(mp8[a-z][a-z0-9]*=?|-debug-tools|-trailer)"'
$source = 'mp8_dev_args\(\)|\b_?mp8_args\b|\b_mp8_arg\w*\('

# Each line's function: the nearest column-0 func above it, or none at file scope.
function Get-Functions([string[]]$Lines) {
    $owner = New-Object int[] $Lines.Count
    $current = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = $Lines[$i]
        if ($l -cmatch '^(static\s+)?func\s') { $current = $i }
        elseif ($l -cmatch '^\S' -and $l -cnotmatch '^#') { $current = -1 }
        $owner[$i] = $current
    }
    return ,$owner
}

$failures = 0
$files = 0
foreach ($p in (Get-ChildItem -LiteralPath $Patched -Recurse -File -Filter '*.gd' | Sort-Object FullName)) {
    $rel = $p.FullName.Substring($Patched.Length + 1).Replace('\', '/')
    $v = Join-Path $Vanilla $rel
    $lines = [IO.File]::ReadAllLines($p.FullName)
    $game = [Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal)
    $vlines = @()
    if (Test-Path -LiteralPath $v) {
        $vlines = [IO.File]::ReadAllLines($v)
        foreach ($l in $vlines) { $t = $l.Trim(); if ($game.ContainsKey($t)) { $game[$t]++ } else { $game[$t] = 1 } }
    }
    $ours = New-Object bool[] $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($game.ContainsKey($t) -and $game[$t] -gt 0) { $game[$t]-- } else { $ours[$i] = $true }
    }
    $owner = Get-Functions $lines
    $out = [Collections.Generic.List[string]]::new()

    # The game's own argument variables: a game line that fills one, scoped to its function.
    $gameVars = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $ours[$i] -and $lines[$i] -cmatch '^\s*var\s+(\w+)\b[^=]*=.*get_cmdline_args') { $gameVars[$i] = $Matches[1] }
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $ours[$i]) { continue }
        $l = $lines[$i]
        $code = ($l -replace '^\s*#.*$', '')
        if (-not $code.Trim()) { continue }
        $n = $i + 1
        $f = $owner[$i]
        $fname = if ($f -ge 0) { ([regex]::Match($lines[$f], 'func\s+(\w+)')).Groups[1].Value } else { '' }

        if ($code -cmatch 'get_cmdline_(user_)?args' -and $fname -ne 'mp8_dev_args') { $out.Add("  R1 :$n get_cmdline_args on a line of ours: $($l.Trim())") }

        if ($code -cmatch $switch) {
            # The line names the source, or the innermost `for` around it loops over it.
            $read = $code -cmatch $source
            if (-not $read -and $f -ge 0) {
                $indent = ([regex]::Match($l, '^\t*')).Length
                for ($j = $i - 1; $j -gt $f; $j--) {
                    $u = $lines[$j]
                    if (-not $u.Trim() -or $u.Trim().StartsWith('#')) { continue }
                    $ui = ([regex]::Match($u, '^\t*')).Length
                    if ($ui -ge $indent) { continue }
                    $indent = $ui
                    if ($u -cmatch '^\s*for\s') { $read = $u -cmatch $source; break }
                }
            }
            if ($f -lt 0 -or -not $read) { $out.Add("  R2 :$n switch read outside mp8_dev_args(): $($l.Trim())") }
        }
        if ($code -cmatch '\b_?mp8_args\b\s*(:[^=]*)?=[^=]' -and $code -cnotmatch 'mp8_dev_args\(\)') { $out.Add("  R2 :$n mp8_args filled from something else: $($l.Trim())") }

        foreach ($k in $gameVars.Keys) {
            if ($owner[$k] -ne $f) { continue }
            $name = $gameVars[$k]
            if ($code -cmatch ('\b' + [regex]::Escape($name) + '\b')) {
                $out.Add("  R3 :$n reads the game's ``$name``: $($l.Trim())")
            }
        }
    }

    # Each _mp8_arg* helper loops over mp8_dev_args() and never over the raw command line.
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -cnotmatch '^(static\s+)?func\s+(_mp8_arg\w*)\s*\(') { continue }
        $name = $Matches[2]
        $body = $(for ($j = $i; $j -lt $lines.Count; $j++) { if ($owner[$j] -eq $i) { $lines[$j] } }) -join "`n"
        if ($body -cnotmatch 'mp8_dev_args\(\)' -or $body -cmatch 'get_cmdline_args') { $out.Add("  R2 :$($i + 1) helper $name doesn't read mp8_dev_args()") }
    }

    if ($out.Count -gt 0) {
        Write-Host $rel
        $out | ForEach-Object { Write-Host $_ }
        $failures += $out.Count
        $files++
    }
}
Write-Host ("Dev switches: {0} failures in {1} scripts" -f $failures, $files)
if ($failures -gt 0) { exit 1 }
exit 0
