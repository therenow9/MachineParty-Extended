# Checks every NetworkManager.mp8_text(en, zhs, zht) call in patch\ (D173): three string literals (or a
# String const of the same file), none empty, Chinese in the ZHS and ZHT slots and none in the EN slot, and
# the same % specifiers in the same order and the same number of \n in all three. A triple that differs
# formats to an error and an empty label with nothing in the log. Exits 1 on any failure.
param(
    [string]$Vanilla = '',
    [string]$Patched = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Patched) { $Patched = Join-Path $root 'patch' }
$Patched = [IO.Path]::GetFullPath($Patched).TrimEnd('\','/')
if (-not (Test-Path -LiteralPath $Patched -PathType Container)) { throw "Missing folder: $Patched" }

$cjk = '[㐀-鿿＀-￯　-〿]'
$spec = '%[-+ 0#]*[0-9*]*(\.[0-9*]+)?[sdifxXcvo%]'

# The arguments of the call whose "(" is at $open, split at depth 0; $null if the call never closes.
function Get-Arguments([string]$Text, [int]$Open) {
    $parts = New-Object System.Collections.Generic.List[string]
    $depth = 0; $start = $Open + 1; $inString = $false
    for ($i = $Open; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inString) {
            if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $inString = $false }
            continue
        }
        if ($c -eq '"') { $inString = $true }
        elseif ($c -eq '(' -or $c -eq '[' -or $c -eq '{') { $depth++ }
        elseif ($c -eq ')' -or $c -eq ']' -or $c -eq '}') {
            $depth--
            if ($depth -eq 0) { $parts.Add($Text.Substring($start, $i - $start)); return ,$parts }
        }
        elseif ($c -eq ',' -and $depth -eq 1) { $parts.Add($Text.Substring($start, $i - $start)); $start = $i + 1 }
    }
    return $null
}

$failures = 0; $calls = 0; $files = 0
foreach ($file in Get-ChildItem -LiteralPath $Patched -Recurse -Filter '*.gd' -File) {
    $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    if ($text -cnotmatch '\bmp8_text\(') { continue }
    $rel = $file.FullName.Substring($Patched.Length + 1)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($text, '\bmp8_text\(')) {
        $lineStart = $text.LastIndexOf("`n", [Math]::Max(0, $m.Index - 1)) + 1
        $before = $text.Substring($lineStart, $m.Index - $lineStart)
        if ($before.TrimStart().StartsWith('#') -or $before -cmatch '\bfunc\s+$') { continue }
        $n = ($text.Substring(0, $m.Index) -split "`n").Count
        $calls++
        $arguments = Get-Arguments $text ($m.Index + $m.Length - 1)
        if ($null -eq $arguments -or $arguments.Count -ne 3) { $out.Add("  :$n not three arguments"); continue }
        $values = @()
        foreach ($a in $arguments) {
            $a = $a.Trim()
            if ($a -cmatch '^"((?:[^"\\]|\\.)*)"$') { $values += $Matches[1]; continue }
            if ($a -cmatch '^[A-Z][A-Z0-9_]*$') {
                $const = [regex]::Match($text, '(?m)^const\s+' + $a + '\s*:\s*String\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
                if ($const.Success) { $values += $const.Groups[1].Value; continue }
            }
            $values += $null
        }
        if ($values -contains $null) { $out.Add("  :$n an argument is not a string literal or a String const of this file"); continue }
        $en, $zhs, $zht = $values
        if ($values | Where-Object { $_.Trim() -eq '' }) { $out.Add("  :$n an empty string") }
        if ($en -match $cjk) { $out.Add("  :$n Chinese in the EN slot: $en") }
        if ($zhs -notmatch $cjk) { $out.Add("  :$n no Chinese in the ZHS slot: $zhs") }
        if ($zht -notmatch $cjk) { $out.Add("  :$n no Chinese in the ZHT slot: $zht") }
        $want = ([regex]::Matches($en, $spec) | ForEach-Object Value) -join ' '
        $lines = ([regex]::Matches($en, '\\n')).Count
        foreach ($pair in @(@('ZHS', $zhs), @('ZHT', $zht))) {
            $got = ([regex]::Matches($pair[1], $spec) | ForEach-Object Value) -join ' '
            if ($got -cne $want) { $out.Add("  :$n $($pair[0]) specifiers '$got', EN '$want'") }
            if (([regex]::Matches($pair[1], '\\n')).Count -ne $lines) { $out.Add("  :$n $($pair[0]) line breaks differ from EN's $lines") }
        }
    }
    if ($out.Count -gt 0) {
        Write-Host $rel
        $out | ForEach-Object { Write-Host $_ }
        $failures += $out.Count
        $files++
    }
}
Write-Host ("Text triples: {0} calls, {1} failures in {2} scripts" -f $calls, $failures, $files)
if ($failures -gt 0) { exit 1 }
if ($calls -eq 0) { Write-Host 'No mp8_text call found'; exit 1 }
exit 0
