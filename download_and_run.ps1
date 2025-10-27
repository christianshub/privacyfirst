# PrivacyFirst - Download and Run Script
# Run this on your VM to download PrivacyFirst from GitHub

param(
    [string]$GitHubUser = "john",  # Change to your GitHub username
    [string]$RepoName = "privacyfirst",
    [string]$Branch = "main",
    [string]$LocalPath = "C:\PrivacyFirstTest"
)

$ErrorActionPreference = "Stop"

Write-Host "=== PrivacyFirst Installer ===" -ForegroundColor Cyan
Write-Host ""

# GitHub raw URLs
$baseUrl = "https://raw.githubusercontent.com/$GitHubUser/$RepoName/$Branch/x64/Release"

# Create local directory
if (-not (Test-Path $LocalPath)) {
    Write-Host "Creating directory: $LocalPath" -ForegroundColor Yellow
    New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null
}

# Files to download
$files = @(
    "PrivacyFirst.exe",
    "PrivacyFirst.dll",
    "PrivacyCore.dll",
    "PrivacyFirst.deps.json",
    "PrivacyFirst.runtimeconfig.json"
)

Write-Host "Downloading PrivacyFirst from GitHub..." -ForegroundColor Cyan
Write-Host "Repository: $GitHubUser/$RepoName" -ForegroundColor Gray
Write-Host ""

$successCount = 0
foreach ($file in $files) {
    try {
        $url = "$baseUrl/$file"
        $destination = Join-Path $LocalPath $file

        Write-Host "  Downloading $file..." -NoNewline
        Invoke-WebRequest -Uri $url -OutFile $destination -ErrorAction Stop
        Write-Host " OK" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

Write-Host ""
if ($successCount -eq $files.Count) {
    Write-Host "Download complete! ($successCount/$($files.Count) files)" -ForegroundColor Green
    Write-Host ""
    Write-Host "PrivacyFirst installed to: $LocalPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To run PrivacyFirst (as Administrator):" -ForegroundColor Yellow
    Write-Host "  cd $LocalPath" -ForegroundColor White
    Write-Host "  .\PrivacyFirst.exe" -ForegroundColor White
    Write-Host ""

    # Optionally launch now
    $launch = Read-Host "Launch PrivacyFirst now? (Y/N)"
    if ($launch -eq "Y" -or $launch -eq "y") {
        Push-Location $LocalPath
        Start-Process ".\PrivacyFirst.exe" -Verb RunAs
        Pop-Location
        Write-Host "PrivacyFirst launched!" -ForegroundColor Green
    }
}
else {
    Write-Host "Download incomplete! ($successCount/$($files.Count) files)" -ForegroundColor Red
    Write-Host "Check the repository URL and try again." -ForegroundColor Yellow
}
