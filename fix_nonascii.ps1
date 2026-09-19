# ============================================================
# fix_nonascii.ps1 - v3
# Replaces non-ASCII characters with ASCII equivalents.
# v3: char-by-char walk, no explicit map, handles all box-drawing
#     (U+2500..U+257F) plus common typographic punctuation.
# ============================================================

$SrcDir = "G:\Surroundead_Mods_Dev\CraftScanner\MyCPPMods\CraftScanner\src"

# Translate a single char to its ASCII equivalent, or return $null
# if it should stay as-is.
function Convert-Char {
    param([char]$c)

    $code = [int]$c

    # ASCII: keep
    if ($code -lt 128) { return [string]$c }

    # ---- Box drawing (U+2500..U+257F) -> ASCII line chars ----
    if ($code -ge 0x2500 -and $code -le 0x257F) {
        # Horizontal-ish -> '-'
        if ($code -eq 0x2500) { return '-' }  # light horizontal
        if ($code -eq 0x2501) { return '-' }  # heavy horizontal
        if ($code -eq 0x2504) { return '-' }
        if ($code -eq 0x2505) { return '-' }
        if ($code -eq 0x2508) { return '-' }
        if ($code -eq 0x2509) { return '-' }
        # Vertical-ish -> '|'
        if ($code -eq 0x2502) { return '|' }
        if ($code -eq 0x2503) { return '|' }
        if ($code -eq 0x2506) { return '|' }
        if ($code -eq 0x2507) { return '|' }
        if ($code -eq 0x250A) { return '|' }
        if ($code -eq 0x250B) { return '|' }
        # Corners / tees / crosses -> '+'
        return '+'
    }

    # ---- Dashes ----
    if ($code -eq 0x2014) { return '-' }  # em-dash
    if ($code -eq 0x2013) { return '-' }  # en-dash
    if ($code -eq 0x2012) { return '-' }  # figure dash
    if ($code -eq 0x2015) { return '-' }  # horizontal bar

    # ---- Quotes ----
    if ($code -eq 0x2018 -or $code -eq 0x2019 -or $code -eq 0x201A -or $code -eq 0x201B) { return "'" }
    if ($code -eq 0x201C -or $code -eq 0x201D -or $code -eq 0x201E -or $code -eq 0x201F) { return '"' }
    if ($code -eq 0x00AB -or $code -eq 0x00BB) { return '"' }  # guillemets

    # ---- Ellipsis ----
    if ($code -eq 0x2026) { return '...' }

    # ---- Spaces ----
    if ($code -eq 0x00A0) { return ' ' }  # non-breaking
    if ($code -eq 0x2007) { return ' ' }  # figure space
    if ($code -eq 0x202F) { return ' ' }  # narrow nbsp
    if ($code -eq 0x2009) { return ' ' }  # thin space

    # ---- Arrows ----
    if ($code -eq 0x2192) { return '->' }
    if ($code -eq 0x2190) { return '<-' }
    if ($code -eq 0x21D2) { return '=>' }
    if ($code -eq 0x21D0) { return '<=' }

    # ---- Math-ish ----
    if ($code -eq 0x00D7) { return 'x' }   # multiplication
    if ($code -eq 0x00F7) { return '/' }   # division
    if ($code -eq 0x2264) { return '<=' }
    if ($code -eq 0x2265) { return '>=' }
    if ($code -eq 0x2260) { return '!=' }
    if ($code -eq 0x00B0) { return 'deg' } # degree

    # ---- Bullets / misc ----
    if ($code -eq 0x2022) { return '*' }   # bullet
    if ($code -eq 0x00B7) { return '*' }   # middle dot
    if ($code -eq 0x2713) { return 'v' }   # check mark
    if ($code -eq 0x2717) { return 'x' }   # ballot X

    # Unknown non-ASCII -> '?' as last resort, and report it
    return "?<U+{0:X4}>" -f $code
}

$files = Get-ChildItem -Path $SrcDir -File -Include *.cpp,*.hpp -Recurse

foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

    $enc = New-Object System.Text.UTF8Encoding($false)
    $txt = [System.IO.File]::ReadAllText($f.FullName, $enc)

    $sb = New-Object System.Text.StringBuilder
    $changed = $false
    foreach ($ch in $txt.ToCharArray()) {
        $repl = Convert-Char $ch
        if ($repl -ne [string]$ch) { $changed = $true }
        [void]$sb.Append($repl)
    }
    $newTxt = $sb.ToString()

    if ($changed) {
        $out = if ($hasBom) { New-Object System.Text.UTF8Encoding($true) } else { $enc }
        [System.IO.File]::WriteAllText($f.FullName, $newTxt, $out)
        Write-Host "Fixed: $($f.Name)" -ForegroundColor Green
    } else {
        Write-Host "Clean: $($f.Name)" -ForegroundColor DarkGray
    }

    # Diagnostic: report any remaining non-ASCII (should be none)
    $bytes2 = [System.IO.File]::ReadAllBytes($f.FullName)
    $start = 0
    if ($bytes2.Length -ge 3 -and $bytes2[0] -eq 0xEF -and $bytes2[1] -eq 0xBB -and $bytes2[2] -eq 0xBF) { $start = 3 }
    $leftover = @()
    for ($i = $start; $i -lt $bytes2.Length; $i++) {
        if ($bytes2[$i] -gt 127) {
            $leftover += ("0x{0:X2}@byte{1}" -f $bytes2[$i], $i)
            if ($leftover.Count -ge 6) { $leftover += "..."; break }
        }
    }
    if ($leftover.Count -gt 0) {
        Write-Host "  remaining non-ASCII in $($f.Name): $($leftover -join ', ')" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done."