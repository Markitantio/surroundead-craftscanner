# ============================================================
# CraftScanner - project verification script (v3)
# Fix v3: removed invalid \" escape inside a PowerShell string.
# Fix v2: literal-mode Check-Contains receives raw patterns.
#         broader RE-UE4SS target detection (SHARED|MODULE).
# ============================================================

$ErrorActionPreference = "Continue"

$ProjectRoot   = "G:\Surroundead_Mods_Dev\CraftScanner"
$GameRoot      = "G:\SurrounDead v0.8.0\SurrounDead\Binaries\Win64\ue4ss"
$GameModDir    = Join-Path $GameRoot "Mods\CraftScanner"
$GameModsTxt   = Join-Path $GameRoot "Mods\mods.txt"

$SrcDir        = Join-Path $ProjectRoot "MyCPPMods\CraftScanner\src"
$ReRoot        = Join-Path $ProjectRoot "RE-UE4SS"

$script:passCount = 0
$script:failCount = 0
$script:warnCount = 0
$script:ue4ssTargetName = $null

function Section($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green;   $script:passCount++ }
function BAD($msg)  { Write-Host "  [FAIL] $msg" -ForegroundColor Red;     $script:failCount++ }
function WARN($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow;  $script:warnCount++ }

function Check-File($path, $label) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { OK "file: $label"; return $true }
    BAD "missing file: $label  ($path)"; return $false
}
function Check-Dir($path, $label) {
    if (Test-Path -LiteralPath $path) { OK "dir:  $label"; return $true }
    BAD "missing dir: $label  ($path)"; return $false
}
function Check-Contains($path, $pattern, $desc, $isRegex = $true) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { BAD "$desc -- file not found: $path"; return }
    $txt = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $txt) { BAD "$desc -- cannot read: $path"; return }
    $found = if ($isRegex) { [bool]($txt -match $pattern) } else { $txt.Contains($pattern) }
    if ($found) { OK $desc } else { BAD "$desc -- pattern not found in $path" }
}
function Check-NotContains($path, $pattern, $desc) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $txt = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $txt) { return }
    if ($txt -match $pattern) { BAD "$desc -- pattern unexpectedly present in $path" }
    else                       { OK $desc }
}

# ────────────────────────────────────────────────────────────
Section "1. Project root"
Check-Dir $ProjectRoot "project root"

# ────────────────────────────────────────────────────────────
Section "2. Directory tree"
Check-Dir (Join-Path $ProjectRoot "MyCPPMods")               "MyCPPMods"
Check-Dir (Join-Path $ProjectRoot "MyCPPMods\CraftScanner")  "MyCPPMods\CraftScanner"
Check-Dir $SrcDir                                            "MyCPPMods\CraftScanner\src"
Check-Dir $ReRoot                                            "RE-UE4SS"

if (Test-Path $ReRoot) {
    $item = Get-Item -LiteralPath $ReRoot -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $target = (Get-Item -LiteralPath $ReRoot).Target
        if ($target) { OK "RE-UE4SS is a junction -> $target" }
        else         { WARN "RE-UE4SS is a reparse point but target not resolved" }
    } else {
        WARN "RE-UE4SS is a plain directory (not a junction) -- fine if up to date"
    }

    $reCmake = Join-Path $ReRoot "CMakeLists.txt"
    if (Test-Path $reCmake) {
        OK "RE-UE4SS\CMakeLists.txt present"
        $reTxt = Get-Content -LiteralPath $reCmake -Raw -ErrorAction SilentlyContinue

        $m = [regex]::Match($reTxt, 'add_library\s*\(\s*([A-Za-z0-9_\-]+)\s+(SHARED|MODULE)')
        if ($m.Success) {
            $script:ue4ssTargetName = $m.Groups[1].Value
            OK "UE4SS target detected: '$($script:ue4ssTargetName)'"
        } else {
            $m2 = [regex]::Match($reTxt, 'add_library\s*\(\s*([A-Za-z0-9_\-]+)')
            if ($m2.Success) {
                $script:ue4ssTargetName = $m2.Groups[1].Value
                WARN "add_library found but not SHARED/MODULE: '$($script:ue4ssTargetName)' -- verify manually"
            } else {
                WARN "No add_library(...) found in RE-UE4SS\CMakeLists.txt"
                WARN "Printing first 40 lines for manual inspection:"
                ($reTxt -split "`r?`n" | Select-Object -First 40) | ForEach-Object {
                    Write-Host "    $_" -ForegroundColor DarkGray
                }
            }
        }
    } else {
        BAD "RE-UE4SS\CMakeLists.txt not found"
    }
}

# ────────────────────────────────────────────────────────────
Section "3. Top-level files"
Check-File (Join-Path $ProjectRoot "CMakeLists.txt")   "CMakeLists.txt (root)"
Check-File (Join-Path $ProjectRoot "build.ps1")        "build.ps1"
Check-File (Join-Path $ProjectRoot "deploy.ps1")       "deploy.ps1"
Check-File (Join-Path $ProjectRoot "CraftScanner.ini") "CraftScanner.ini"
Check-File (Join-Path $ProjectRoot "README.md")        "README.md"

# ────────────────────────────────────────────────────────────
Section "4. Source files"
$expectedSrc = @(
    "CS_Common.hpp","Config.hpp","Config.cpp","KeyMapper.hpp",
    "Notification.hpp","Notification.cpp",
    "CraftScannerHooks.hpp","CraftScannerHooks.cpp","CraftScannerMod.cpp"
)
foreach ($f in $expectedSrc) { Check-File (Join-Path $SrcDir $f) "src\$f" }

foreach ($stray in @("SurvivorAbilitiesHooks.cpp","SurvivorAbilitiesHooks.hpp","SurvivorAbilitiesMod.cpp")) {
    $p = Join-Path $SrcDir $stray
    if (Test-Path $p) { BAD "stray file still present: $stray" }
    else              { OK "no stray: $stray" }
}

# ────────────────────────────────────────────────────────────
Section "5. CMake files content"
$rootCmake = Join-Path $ProjectRoot "CMakeLists.txt"
Check-Contains $rootCmake 'project\s*\(\s*CraftScanner' "root CMake: project(CraftScanner)"
Check-Contains $rootCmake 'add_subdirectory\s*\(\s*\$\{RE_UE4SS_ROOT\}' "root CMake: adds RE-UE4SS subdir"
Check-Contains $rootCmake 'add_subdirectory\s*\(\s*MyCPPMods\s*\)'   "root CMake: adds MyCPPMods"

$myModsCmake = Join-Path $ProjectRoot "MyCPPMods\CMakeLists.txt"
Check-File $myModsCmake "MyCPPMods\CMakeLists.txt"
Check-Contains $myModsCmake '/wd4996' "MyCPPMods CMake: /wd4996"
Check-Contains $myModsCmake 'add_subdirectory\s*\(\s*CraftScanner\s*\)' "MyCPPMods CMake: adds CraftScanner"

$modCmake = Join-Path $ProjectRoot "MyCPPMods\CraftScanner\CMakeLists.txt"
Check-File $modCmake "MyCPPMods\CraftScanner\CMakeLists.txt"
Check-Contains $modCmake 'add_library\s*\(\s*CraftScanner\s+SHARED' "CraftScanner CMake: add_library SHARED"
Check-Contains $modCmake 'target_link_libraries\s*\(\s*CraftScanner\s+PRIVATE\s+UE4SS\s*\)' "CraftScanner CMake: links UE4SS"
Check-Contains $modCmake 'src[\\/]CraftScannerHooks\.cpp' "CraftScanner CMake: lists CraftScannerHooks.cpp"
Check-Contains $modCmake 'src[\\/]CraftScannerMod\.cpp'   "CraftScanner CMake: lists CraftScannerMod.cpp"

if ($script:ue4ssTargetName -and $script:ue4ssTargetName -ne "UE4SS") {
    WARN "RE-UE4SS builds target '$($script:ue4ssTargetName)' but CraftScanner links 'UE4SS'."
    WARN "If link fails, change target_link_libraries(CraftScanner PRIVATE UE4SS)."
}

# ────────────────────────────────────────────────────────────
Section "6. Source content sanity"
Check-Contains (Join-Path $SrcDir "CS_Common.hpp") 'CS_VERSION'                       "CS_Common.hpp: CS_VERSION defined"
Check-Contains (Join-Path $SrcDir "CS_Common.hpp") 'L"0\.1\.0"'                       "CS_Common.hpp: version 0.1.0"
Check-Contains (Join-Path $SrcDir "CS_Common.hpp") 'namespace\s+CraftScanner'         "CS_Common.hpp: namespace CraftScanner"
Check-Contains (Join-Path $SrcDir "CS_Common.hpp") 'Player_JigMultiComponent\s*=\s*0x07F0' "CS_Common.hpp: JigMultiComponent @0x07F0"
Check-Contains (Join-Path $SrcDir "CS_Common.hpp") 'Jig_MainJigContainers\s*=\s*0xC0' "CS_Common.hpp: MainJigContainers @0xC0"

Check-Contains (Join-Path $SrcDir "Config.cpp") 'GetPrivateProfileStringW' "Config.cpp: uses GetPrivateProfileStringW"
Check-Contains (Join-Path $SrcDir "Config.cpp") 'CraftScanner\.ini'        "Config.cpp: reads CraftScanner.ini"

Check-Contains (Join-Path $SrcDir "Notification.cpp") 'Conv_StringToText'    "Notification.cpp: uses Conv_StringToText"
Check-Contains (Join-Path $SrcDir "Notification.cpp") 'CreateNotificationUI' "Notification.cpp: uses CreateNotificationUI"
Check-Contains (Join-Path $SrcDir "Notification.cpp") 'KismetTextLibrary'    "Notification.cpp: resolves KismetTextLibrary"

Check-Contains (Join-Path $SrcDir "CraftScannerHooks.cpp") 'ResolveCurrentPawn'  "Hooks: ResolveCurrentPawn"
Check-Contains (Join-Path $SrcDir "CraftScannerHooks.cpp") 'WalkContainers'      "Hooks: WalkContainers"
Check-Contains (Join-Path $SrcDir "CraftScannerHooks.cpp") 'OnShowResources'     "Hooks: OnShowResources"
Check-Contains (Join-Path $SrcDir "CraftScannerHooks.cpp") 'g_bTeardownDetected' "Hooks: teardown guard"
Check-Contains (Join-Path $SrcDir "CraftScannerHooks.cpp") 'MainJigContainers'   "Hooks: walks MainJigContainers"

Check-Contains (Join-Path $SrcDir "CraftScannerMod.cpp") 'STR\("CraftScanner"\)' "Mod: ModName = CraftScanner"
Check-Contains (Join-Path $SrcDir "CraftScannerMod.cpp") 'start_mod'             "Mod: exports start_mod"
Check-Contains (Join-Path $SrcDir "CraftScannerMod.cpp") 'uninstall_mod'         "Mod: exports uninstall_mod"
Check-Contains (Join-Path $SrcDir "CraftScannerMod.cpp") 'CraftScanner::Install\(\)' "Mod: calls Install()"

# ────────────────────────────────────────────────────────────
Section "7. No SurvivorAbilities leftovers in source"
$strayPatterns = @('SA_VERSION','SA_LOG','SurvivorAbilities','Sprint Burst','Power Strike','Iron Skin')
foreach ($pat in $strayPatterns) {
    $hits = @()
    Get-ChildItem -Path $SrcDir -File -Include *.cpp,*.hpp -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            $c = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
            if ($c -and $c -match [regex]::Escape($pat)) { $hits += $_.Name }
        }
    if ($hits.Count -gt 0) { BAD "leftover pattern '$pat' in: $($hits -join ', ')" }
    else                   { OK  "no leftover '$pat'" }
}

# ────────────────────────────────────────────────────────────
Section "8. CraftScanner.ini structure"
$iniPath = Join-Path $ProjectRoot "CraftScanner.ini"
if (Test-Path $iniPath) {
    foreach ($section in @("[Settings]","[Filter]","[Display]")) {
        Check-Contains $iniPath $section "INI section: $section" $false
    }
    foreach ($key in @("Hotkey=F2","Enabled=1","DurationSec","MaxLines","ShowAll","IncludeTypes","IncludeItemIds","Title")) {
        Check-Contains $iniPath $key "INI key: $key" $false
    }
} else {
    BAD "CraftScanner.ini missing -- cannot validate"
}

# ────────────────────────────────────────────────────────────
Section "9. build.ps1 / deploy.ps1 sanity"
$buildPs1 = Join-Path $ProjectRoot "build.ps1"
Check-Contains $buildPs1 'CraftScanner' "build.ps1: references CraftScanner"
Check-Contains $buildPs1 '\$ProjectRoot\s*=\s*"G:\\Surroundead_Mods_Dev\\CraftScanner"' "build.ps1: correct project root"
Check-NotContains $buildPs1 'SurvivorAbilities' "build.ps1: no SurvivorAbilities leftovers"
Check-Contains $buildPs1 'cmake\s+--build\s+\$BuildDir\s+--target\s+CraftScanner' "build.ps1: builds target CraftScanner"

$deployPs1 = Join-Path $ProjectRoot "deploy.ps1"
Check-Contains $deployPs1 'CraftScanner\.dll'    "deploy.ps1: references CraftScanner.dll"
Check-NotContains $deployPs1 'SurvivorAbilities' "deploy.ps1: no SurvivorAbilities leftovers"

# ────────────────────────────────────────────────────────────
Section "10. Game-side setup"
if (Test-Path $GameModsTxt) {
    $modsTxt = Get-Content -LiteralPath $GameModsTxt -Raw -ErrorAction SilentlyContinue
    if ($modsTxt -match 'CraftScanner\s*:\s*1') { OK "mods.txt contains 'CraftScanner : 1'" }
    else                                        { BAD "mods.txt does NOT contain 'CraftScanner : 1' -- add it" }
} else {
    WARN "game mods.txt not found at $GameModsTxt"
}

if (Test-Path $GameModDir) {
    OK "game mod folder exists: $GameModDir"
    $dllsDir = Join-Path $GameModDir "dlls"
    if (Test-Path $dllsDir) {
        $dlls = @(Get-ChildItem $dllsDir -Filter "*.dll" -File -ErrorAction SilentlyContinue)
        if ($dlls.Count -eq 0)      { WARN "no DLL deployed yet in $dllsDir -- run deploy.ps1 after building" }
        elseif ($dlls.Count -eq 1) {
            if ($dlls[0].Name -eq "CraftScanner.dll") { OK "exactly one DLL deployed: CraftScanner.dll" }
            else                                      { BAD "single DLL is '$($dlls[0].Name)' -- expected CraftScanner.dll" }
        } else {
            BAD "$($dlls.Count) DLLs in dlls\ -- UE4SS will load the wrong one:"
            $dlls | ForEach-Object { Write-Host "        $($_.Name)" -ForegroundColor Red }
        }
        if (Test-Path (Join-Path $dllsDir "main.dll")) { BAD "stale main.dll present in dlls\" }
        else                                            { OK "no stale main.dll" }
    } else {
        WARN "dlls\ subfolder does not exist yet in game mod folder"
    }
    $gameIni = Join-Path $GameModDir "CraftScanner.ini"
    if (Test-Path $gameIni) { OK "game INI present: CraftScanner.ini" }
    else                    { WARN "game INI not present yet -- copy it after first deploy" }
} else {
    WARN "game mod folder does not exist yet: $GameModDir"
    WARN "It will be created by deploy.ps1 on first run."
}

# ────────────────────────────────────────────────────────────
Section "11. Build artifacts"
$dll   = Join-Path $ProjectRoot "Output_ninja\MyCPPMods\CraftScanner\CraftScanner.dll"
$pdb   = Join-Path $ProjectRoot "Output_ninja\MyCPPMods\CraftScanner\CraftScanner.pdb"
$cache = Join-Path $ProjectRoot "Output_ninja\CMakeCache.txt"

if (Test-Path $cache) { OK "CMake cache present" } else { WARN "no CMake cache yet -- first build will take 15-30 min" }
if (Test-Path $dll)   { $i = Get-Item $dll; OK "DLL built: $([math]::Round($i.Length/1KB,2)) KB, $($i.LastWriteTime)" } else { WARN "DLL not built yet" }
if (Test-Path $pdb)   { $p = Get-Item $pdb; OK "PDB built: $([math]::Round($p.Length/1KB,2)) KB" }                     else { WARN "PDB not built yet" }

# ────────────────────────────────────────────────────────────
Section "12. Common pitfalls"
$nonAsciiFiles = @()
Get-ChildItem -Path $SrcDir -File -Include *.cpp,*.hpp -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $start = 0
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $start = 3 }
        for ($i = $start; $i -lt $bytes.Length; $i++) {
            if ($bytes[$i] -gt 127) { $nonAsciiFiles += $_.Name; break }
        }
    }
if ($nonAsciiFiles.Count -gt 0) {
    WARN "files contain non-ASCII bytes (beyond BOM): $($nonAsciiFiles -join ', ')"
    WARN "Replace em-dashes and curly quotes with plain ASCII characters."
} else {
    OK "all source files are ASCII (BOM ignored)"
}

$cppHpp = @{ "Config.cpp"="Config.hpp"; "Notification.cpp"="Notification.hpp"; "CraftScannerHooks.cpp"="CraftScannerHooks.hpp" }
foreach ($k in $cppHpp.Keys) {
    $cpp = Join-Path $SrcDir $k
    if (Test-Path $cpp) { Check-Contains $cpp ([regex]::Escape("#include `"$($cppHpp[$k])`"")) "$k includes $($cppHpp[$k])" }
}
Check-Contains (Join-Path $SrcDir "CraftScannerMod.cpp") 'CppUserModBase' "Mod.cpp: inherits CppUserModBase"

$csDefCount = 0
Get-ChildItem -Path $SrcDir -File -Include *.cpp,*.hpp -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object {
        $c = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
        if ($c -match 'CS_VERSION\s*=') { $csDefCount++ }
    }
if ($csDefCount -eq 1) { OK "CS_VERSION defined exactly once" } else { BAD "CS_VERSION defined $csDefCount times (expected 1)" }

# ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "  PASS: $script:passCount" -ForegroundColor Green
Write-Host "  WARN: $script:warnCount" -ForegroundColor Yellow
Write-Host "  FAIL: $script:failCount" -ForegroundColor Red
Write-Host "=========================================" -ForegroundColor Cyan

if ($script:failCount -eq 0) {
    Write-Host ""
    Write-Host "Verdict: OK -- project structure and contents are valid." -ForegroundColor Green
    Write-Host "Next: .\build.ps1 -Clean" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "Verdict: $script:failCount issue(s) must be fixed before building." -ForegroundColor Red
    exit 1
}