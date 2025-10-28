#requires -Version 5.1
param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$publishDir = Join-Path $repoRoot "publish\$Runtime"
$distDir = Join-Path $repoRoot "dist"

Write-Host "Publishing PrivacyFirst ($Configuration, $Runtime)..." -ForegroundColor Cyan
dotnet publish "$repoRoot\ui\PrivacyFirst.UI\PrivacyFirst.UI.csproj" `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    /p:PublishSingleFile=true `
    /p:IncludeNativeLibrariesForSelfExtract=true `
    /p:EnableCompressionInSingleFile=true `
    /p:PublishTrimmed=false `
    -o $publishDir

Write-Host "Publish output: $publishDir" -ForegroundColor Green

if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}

$isccCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) }

if (-not $isccCandidates) {
    Write-Warning "Inno Setup (ISCC.exe) not found. Installer not built."
    Write-Host "Install Inno Setup 6 and rerun this script." -ForegroundColor Yellow
    exit 1
}

$iscc = $isccCandidates | Select-Object -First 1
Write-Host ("Using Inno Setup compiler: {0}" -f $iscc) -ForegroundColor Cyan

$installerScript = Join-Path $repoRoot "installer\PrivacyFirstInstaller.iss"

$isccArgs = @(
    "/DPublishDir=$publishDir",
    "/DMyAppVersion=$Version",
    "/DOutputDir=$distDir",
    $installerScript
)

Write-Host "Compiling installer..." -ForegroundColor Cyan
& "$iscc" @isccArgs
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed (exit code $LASTEXITCODE)."
}

$setupExe = Join-Path $distDir "PrivacyFirst-Setup.exe"
if (Test-Path $setupExe) {
    Write-Host "Installer ready: $setupExe" -ForegroundColor Green
} else {
    Write-Host "Installer output directory: $distDir" -ForegroundColor Green
}
