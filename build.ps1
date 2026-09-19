# ============================================================
# CraftScanner build script
# ASCII-only. Preserves PATH. Offline reconfigure supported.
# Produces PDB for crash analysis.
#
# v2: preserve SystemDrive / SystemRoot / windir across the
#     env-shrink used before invoking vcvarsall.bat. Without
#     this, MSVC helper tools create a literal "%SystemDrive%"
#     folder in the working directory.
#
# Usage:
#   .\build.ps1           -- normal incremental build
#   .\build.ps1 -Clean    -- wipe Output_ninja, full re-fetch
# ============================================================

param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$ProjectRoot = "G:\Surroundead_Mods_Dev\CraftScanner"
$BuildDir    = "Output_ninja"
$HashFile    = "$BuildDir\.csbuild_hash"

# Bump this when build flags change so the cache is invalidated once.
$FlagsVersion = "v1-pdb"

Set-Location $ProjectRoot

# --- Optional clean ---
if ($Clean) {
    Write-Host "[!] -Clean passed: removing $BuildDir" -ForegroundColor Yellow
    if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
}

# --- 0. Save original PATH and locate tools ---
$originalPath = $env:PATH
Write-Host "[0/5] Original PATH length: $($originalPath.Length) chars" -ForegroundColor Cyan

function Find-Tool {
    param([string]$name, [string[]]$fallbacks)
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return (Split-Path $cmd.Source -Parent) }
    foreach ($p in $fallbacks) {
        if (Test-Path (Join-Path $p "$name.exe")) { return $p }
    }
    return $null
}

$gitDir = Find-Tool "git" @(
    "C:\Program Files\Git\cmd",
    "C:\Program Files (x86)\Git\cmd",
    "G:\Program Files\Git\cmd",
    "D:\Git\cmd"
)
$cargoBinFallback = @("$env:USERPROFILE\.cargo\bin")
$rustcDir  = Find-Tool "rustc" $cargoBinFallback
$cargoDir  = Find-Tool "cargo" $cargoBinFallback
$pythonDir = Find-Tool "python" @("C:\Python311", "C:\Python312", "C:\Python310", "C:\Python314")

Write-Host "  git:    $(if($gitDir){$gitDir}else{'NOT FOUND'})" -ForegroundColor $(if($gitDir){'Green'}else{'Yellow'})
Write-Host "  rustc:  $(if($rustcDir){$rustcDir}else{'NOT FOUND'})" -ForegroundColor $(if($rustcDir){'Green'}else{'Red'})
Write-Host "  cargo:  $(if($cargoDir){$cargoDir}else{'NOT FOUND'})" -ForegroundColor $(if($cargoDir){'Green'}else{'Red'})
Write-Host "  python: $(if($pythonDir){$pythonDir}else{'NOT FOUND'})" -ForegroundColor $(if($pythonDir){'Green'}else{'Yellow'})

if (-not $rustcDir) { Write-Host "ERROR: rustc not found." -ForegroundColor Red; exit 1 }
if (-not $gitDir)   { Write-Host "ERROR: git not found."   -ForegroundColor Red; exit 1 }

# --- 0b. Clean toolchain env vars ---
foreach ($v in @("_CL_", "CL", "_LINK_", "LINK", "INCLUDE", "LIB", "LIBPATH")) {
    if (Test-Path "Env:$v") { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
}

$shortTmp = "C:\Temp\csbuild"
if (-not (Test-Path $shortTmp)) { New-Item -ItemType Directory -Force -Path $shortTmp | Out-Null }
$env:TMP  = $shortTmp
$env:TEMP = $shortTmp

# --- 1. Activate MSVC with SHORT PATH ---
Write-Host "[1/5] Activating MSVC 14.51..." -ForegroundColor Cyan
$vcvars = "G:\VisualStudio\VC\Auxiliary\Build\vcvarsall.bat"
if (-not (Test-Path $vcvars)) { Write-Host "NOT FOUND: $vcvars" -ForegroundColor Red; exit 1 }
$vcvarsArg = "x64 -vcvars_ver=14.51.36231"

# -----------------------------------------------------------------
# Critical: cmd.exe has a 32 KB limit on the inherited environment.
# We shrink the env before invoking cmd /c to guarantee it fits.
# We save values we need, wipe the environment, then restore after.
# -----------------------------------------------------------------
$shortPath = "C:\Windows\System32;C:\Windows;$gitDir"

# Save PowerShell-relevant env so we can restore after.
# SystemDrive / SystemRoot / windir MUST be here: MSVC helper tools
# resolve %SystemDrive%\ProgramData\... at init time and will create
# a literal "%SystemDrive%" folder if the variable is missing.
$savedEnv = @{}
foreach ($v in @(
    "PATH", "TMP", "TEMP",
    "SystemDrive", "SystemRoot", "windir", "ComSpec",
    "USERPROFILE", "HOMEDRIVE", "HOMEPATH",
    "APPDATA", "LOCALAPPDATA"
)) {
    if (Test-Path "Env:$v") { $savedEnv[$v] = (Get-Item "Env:$v").Value }
}

# --- Wipe the environment (leaves only Windows essentials) ---
Get-ChildItem Env: | ForEach-Object {
    try { Remove-Item "Env:$($_.Name)" -ErrorAction SilentlyContinue } catch {}
}

# Restore the bare minimum for cmd.exe + vcvarsall to run.
$env:SystemRoot          = if ($savedEnv.ContainsKey("SystemRoot")) { $savedEnv["SystemRoot"] } else { "C:\Windows" }
$env:windir              = $env:SystemRoot
$env:SystemDrive         = if ($savedEnv.ContainsKey("SystemDrive")) { $savedEnv["SystemDrive"] } else { "C:" }
$env:ComSpec             = if ($savedEnv.ContainsKey("ComSpec")) { $savedEnv["ComSpec"] } else { "C:\Windows\System32\cmd.exe" }
$env:PATHEXT             = ".COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC"
$env:PATH                = $shortPath
$env:TMP                 = $shortTmp
$env:TEMP                = $shortTmp
if ($savedEnv.ContainsKey("USERPROFILE")) { $env:USERPROFILE = $savedEnv["USERPROFILE"] }
if ($savedEnv.ContainsKey("HOMEDRIVE"))   { $env:HOMEDRIVE   = $savedEnv["HOMEDRIVE"] }
if ($savedEnv.ContainsKey("HOMEPATH"))    { $env:HOMEPATH    = $savedEnv["HOMEPATH"] }

Write-Host "  Shrunk env for cmd; invoking vcvarsall..." -ForegroundColor DarkGray

$cmdLine = "call `"$vcvars`" $vcvarsArg && set"
$envOutput = cmd /c $cmdLine 2>&1

# --- Restore the original environment from saved values ---
if ($savedEnv.ContainsKey("PATH"))         { $env:PATH         = $savedEnv["PATH"] }
if ($savedEnv.ContainsKey("TMP"))          { $env:TMP          = $savedEnv["TMP"] }
if ($savedEnv.ContainsKey("TEMP"))         { $env:TEMP         = $savedEnv["TEMP"] }
if ($savedEnv.ContainsKey("SystemDrive"))  { $env:SystemDrive  = $savedEnv["SystemDrive"] }
if ($savedEnv.ContainsKey("SystemRoot"))   { $env:SystemRoot   = $savedEnv["SystemRoot"] }
if ($savedEnv.ContainsKey("windir"))       { $env:windir       = $savedEnv["windir"] }
if ($savedEnv.ContainsKey("ComSpec"))      { $env:ComSpec      = $savedEnv["ComSpec"] }
if ($savedEnv.ContainsKey("APPDATA"))      { $env:APPDATA      = $savedEnv["APPDATA"] }
if ($savedEnv.ContainsKey("LOCALAPPDATA")) { $env:LOCALAPPDATA = $savedEnv["LOCALAPPDATA"] }

if ($LASTEXITCODE -ne 0) {
    Write-Host "vcvarsall failed: $LASTEXITCODE" -ForegroundColor Red
    Write-Host $envOutput
    exit 1
}

$vcvarsPath = $null
$count = 0
$envOutput | ForEach-Object {
    if ($_ -match '^PATH=(.*)$') { $vcvarsPath = $matches[1] }
    if ($_ -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        $count++
    }
}
Write-Host "  Applied env vars: $count" -ForegroundColor Green

# Re-assert SystemDrive in case vcvarsall's output stomped it.
if ($savedEnv.ContainsKey("SystemDrive")) { $env:SystemDrive = $savedEnv["SystemDrive"] }
if (-not $env:SystemDrive) { $env:SystemDrive = "C:" }

$allPaths = New-Object System.Collections.Generic.List[string]
$seen     = New-Object System.Collections.Generic.HashSet[string]

function Add-Paths {
    param([string]$pathString, $list, $set)
    if (-not $pathString) { return }
    foreach ($p in ($pathString -split ';')) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $p = $p.TrimEnd('\')
        if ($set.Add($p)) { $list.Add($p) | Out-Null }
    }
}

Add-Paths $vcvarsPath   $allPaths $seen
Add-Paths $originalPath $allPaths $seen

foreach ($dir in @($rustcDir, $cargoDir, $pythonDir)) {
    if ($dir) {
        $dir = $dir.TrimEnd('\')
        if ($seen.Add($dir)) { $allPaths.Insert(0, $dir) | Out-Null }
    }
}

$env:PATH = ($allPaths -join ';')
Write-Host "  Final PATH length: $($env:PATH.Length) chars" -ForegroundColor Green

# --- 2. Verify ---
Write-Host "[2/5] Verifying tools..." -ForegroundColor Cyan
$required = @("cl", "git", "rustc", "cargo")
$missing  = @()
foreach ($tool in $required) {
    $found = Get-Command $tool -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "  $tool -> $($found.Source)" -ForegroundColor Green
    } else {
        Write-Host "  $tool -> NOT FOUND" -ForegroundColor Red
        $missing += $tool
    }
}
if ($missing.Count -gt 0) {
    Write-Host "ERROR: missing required tools: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

# --- 3. Configure ---
Set-Location $ProjectRoot

$needsReconfigure = $false
if (-not (Test-Path "$BuildDir\CMakeCache.txt")) {
    $needsReconfigure = $true
    Write-Host "[3/5] No cache: full configure (builds RE-UE4SS, 15-30 min)..." -ForegroundColor Cyan
} elseif (-not (Test-Path $HashFile) -or (Get-Content $HashFile -Raw).Trim() -ne $FlagsVersion) {
    Write-Host "[3/5] Flag set changed (need PDB): reconfiguring..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $BuildDir
    $needsReconfigure = $true
} else {
    Write-Host "[3/5] Reusing existing CMake cache (offline mode)" -ForegroundColor Cyan
}

$platformFlags  = "/DUE_BUILD_SHIPPING=1 /DPLATFORM_WINDOWS=1 /DPLATFORM_MICROSOFT=1 /DUBT_COMPILED_PLATFORM=Windows /EHsc /DWIN32 /D_WINDOWS"

$debugFlagsC    = "/MDd /Ob0 /Od /RTC1 /Z7"
$debugFlagsCXX  = "/MDd /Ob0 /Od /RTC1 /Z7"

$releaseFlagsC    = "/MD /O2 /Ob2 /DNDEBUG /Zi /FS"
$releaseFlagsCXX  = "/MD /O2 /Ob2 /DNDEBUG /Zi /FS"

$releaseLinkFlags = "/DEBUG:FULL /OPT:REF /OPT:ICF /INCREMENTAL:NO"

if ($needsReconfigure) {
    Write-Host "[3/5] Configuring..." -ForegroundColor Cyan

    cmake -S . -B $BuildDir -G Ninja `
      -DCMAKE_BUILD_TYPE=Release `
      -DCMAKE_C_FLAGS:STRING="$platformFlags" `
      -DCMAKE_CXX_FLAGS:STRING="$platformFlags" `
      -DCMAKE_C_FLAGS_DEBUG:STRING="$debugFlagsC" `
      -DCMAKE_CXX_FLAGS_DEBUG:STRING="$debugFlagsCXX" `
      -DCMAKE_C_FLAGS_RELEASE:STRING="$releaseFlagsC" `
      -DCMAKE_CXX_FLAGS_RELEASE:STRING="$releaseFlagsCXX" `
      -DCMAKE_SHARED_LINKER_FLAGS_RELEASE:STRING="$releaseLinkFlags" `
      -DCMAKE_EXE_LINKER_FLAGS_RELEASE:STRING="$releaseLinkFlags" `
      -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT:STRING= `
      -DUE4SS_VERSION_CHECK:BOOL=OFF

    if ($LASTEXITCODE -ne 0) {
        Write-Host "CMake configure FAILED" -ForegroundColor Red
        exit 1
    }

    Set-Content -Path $HashFile -Value $FlagsVersion -Encoding ASCII
    Write-Host "  Hash written: $HashFile ($FlagsVersion)" -ForegroundColor Green
}

# --- 4. Build ---
Write-Host "[4/5] Building CraftScanner..." -ForegroundColor Cyan
cmake --build $BuildDir --target CraftScanner
if ($LASTEXITCODE -ne 0) {
    Write-Host "BUILD FAILED" -ForegroundColor Red
    exit 1
}

# --- 5. Done ---
$dllDir = "$ProjectRoot\$BuildDir\MyCPPMods\CraftScanner"
$dll    = "$dllDir\CraftScanner.dll"
$pdb    = "$dllDir\CraftScanner.pdb"

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
if (Test-Path $dll) {
    $i = Get-Item $dll
    Write-Host "DLL:  $($i.FullName)" -ForegroundColor Green
    Write-Host "Size: $([math]::Round($i.Length/1KB,2)) KB" -ForegroundColor Green
    Write-Host "Time: $($i.LastWriteTime)" -ForegroundColor Green
} else {
    Write-Host "DLL not found: $dll" -ForegroundColor Yellow
}

if (Test-Path $pdb) {
    $p = Get-Item $pdb
    Write-Host "PDB:  $($p.FullName)" -ForegroundColor Green
    Write-Host "Size: $([math]::Round($p.Length/1KB,2)) KB" -ForegroundColor Green
    Write-Host "Time: $($p.LastWriteTime)" -ForegroundColor Green
} else {
    Write-Host "PDB not found (would be: $pdb)" -ForegroundColor Yellow
}

# --- 6. Safety: check that no stray "%SystemDrive%" appeared ---
if (Test-Path (Join-Path $ProjectRoot '%SystemDrive%')) {
    Write-Host ""
    Write-Host "[WARN] '%SystemDrive%' folder appeared again -- MSVC helpers still missing SystemDrive." -ForegroundColor Yellow
    Write-Host "       Remove it manually and report the issue." -ForegroundColor Yellow
}