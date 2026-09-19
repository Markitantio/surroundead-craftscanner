# ============================================================
# CraftScanner - deploy DLL + PDB to the game
# ASCII-only.
# ============================================================

$ErrorActionPreference = "Stop"

$Mod       = "G:\SurrounDead v0.8.0\SurrounDead\Binaries\Win64\ue4ss\Mods\CraftScanner"
$BuildRoot = "G:\Surroundead_Mods_Dev\CraftScanner"

$dllSource = Join-Path $BuildRoot "Output_ninja\MyCPPMods\CraftScanner\CraftScanner.dll"
$pdbSource = Join-Path $BuildRoot "Output_ninja\MyCPPMods\CraftScanner\CraftScanner.pdb"

if (-not (Test-Path $dllSource)) {
    Write-Host "DLL not built: $dllSource" -ForegroundColor Red
    Write-Host "Run .\build.ps1 first." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $pdbSource)) {
    Write-Host "PDB not built: $pdbSource" -ForegroundColor Yellow
}

$dllsDir = Join-Path $Mod "dlls"
New-Item -ItemType Directory -Force -Path $dllsDir | Out-Null

# Remove stale DLLs / PDBs
foreach ($f in @(
    (Join-Path $dllsDir "main.dll"),
    (Join-Path $dllsDir "main.pdb"),
    (Join-Path $dllsDir "CraftScanner.dll"),
    (Join-Path $dllsDir "CraftScanner.pdb")
)) {
    if (Test-Path $f) {
        Remove-Item $f -Force
        Write-Host "Removed stale: $f" -ForegroundColor DarkGray
    }
}

Copy-Item $dllSource (Join-Path $dllsDir "CraftScanner.dll") -Force
Write-Host "DLL deployed:  CraftScanner.dll" -ForegroundColor Green

if (Test-Path $pdbSource) {
    Copy-Item $pdbSource (Join-Path $dllsDir "CraftScanner.pdb") -Force
    Write-Host "PDB deployed:  CraftScanner.pdb" -ForegroundColor Green
}

# INI intentionally NOT copied.

$dllsInFolder = @(Get-ChildItem $dllsDir -Filter "*.dll" -File -ErrorAction SilentlyContinue)
if ($dllsInFolder.Count -eq 0) {
    Write-Host "ERROR: no DLL in $dllsDir after deploy" -ForegroundColor Red
    exit 1
}
if ($dllsInFolder.Count -gt 1) {
    Write-Host "ERROR: multiple DLLs found in $dllsDir -- UE4SS will load main.dll first!" -ForegroundColor Red
    $dllsInFolder | ForEach-Object { Write-Host ("  - " + $_.Name) -ForegroundColor Red }
    exit 1
}
if ($dllsInFolder[0].Name -ne "CraftScanner.dll") {
    Write-Host ("WARNING: unexpected DLL name: " + $dllsInFolder[0].Name) -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "Deployed to: $Mod" -ForegroundColor Green
Get-ChildItem -Recurse -Force $Mod -File |
    Select-Object @{N='RelativePath';E={$_.FullName.Substring($Mod.Length + 1)}}, Length, LastWriteTime |
    Format-Table -AutoSize

Write-Host "Verdict: " -NoNewline
if ($dllsInFolder.Count -eq 1 -and $dllsInFolder[0].Name -eq "CraftScanner.dll") {
    Write-Host "OK (single DLL, correct name, INI untouched)" -ForegroundColor Green
} else {
    Write-Host "REVIEW MANUALLY" -ForegroundColor Yellow
}