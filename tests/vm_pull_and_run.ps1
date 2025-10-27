# Script to run ON the VM - pulls files from dev machine and runs tests
param(
    [string]$DevMachineIP = "",  # IP of your dev machine
    [int]$Port = 8080,
    [string]$LocalPath = "C:\PrivacyFirstTest"
)

if ([string]::IsNullOrEmpty($DevMachineIP)) {
    $DevMachineIP = Read-Host "Enter dev machine IP address"
}

$baseUrl = "http://${DevMachineIP}:${Port}"

Write-Host "=== PrivacyFirst VM Test Client ===" -ForegroundColor Cyan
Write-Host "Pulling from: $baseUrl" -ForegroundColor Gray
Write-Host "Local path: $LocalPath" -ForegroundColor Gray
Write-Host ""

# Create local directory
if (-not (Test-Path $LocalPath)) {
    New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null
    Write-Host "Created directory: $LocalPath" -ForegroundColor Green
}

# List of files to download
$files = @(
    "PrivacyFirst.exe",
    "PrivacyFirst.dll",
    "PrivacyFirst.pdb",
    "PrivacyFirst.deps.json",
    "PrivacyFirst.runtimeconfig.json",
    "PrivacyCore.dll"
)

Write-Host "Downloading files..." -ForegroundColor Yellow

foreach ($file in $files) {
    try {
        $url = "$baseUrl/$file"
        $destination = Join-Path $LocalPath $file

        Write-Host "  Downloading $file..." -NoNewline
        Invoke-WebRequest -Uri $url -OutFile $destination -ErrorAction Stop
        Write-Host " OK" -ForegroundColor Green
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

Write-Host "`nDownload complete!" -ForegroundColor Green
Write-Host "`nTo run PrivacyFirst:" -ForegroundColor Cyan
Write-Host "  cd $LocalPath" -ForegroundColor White
Write-Host "  .\PrivacyFirst.exe" -ForegroundColor White
Write-Host ""

# Optionally launch PrivacyFirst
$launch = Read-Host "Launch PrivacyFirst now? (Y/N)"
if ($launch -eq "Y" -or $launch -eq "y") {
    Push-Location $LocalPath
    Start-Process ".\PrivacyFirst.exe" -Verb RunAs
    Pop-Location
}
