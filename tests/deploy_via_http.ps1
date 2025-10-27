# Integrated deployment script using HTTP server
param(
    [string]$VMHostname = "192.168.0.143",
    [string]$VMUser = "john",
    [string]$VMPassword = "1",
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

Write-Host "=== PrivacyFirst HTTP Deployment ===" -ForegroundColor Cyan

# Get local IP address
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -like "192.168.*"} | Select-Object -First 1).IPAddress

if (-not $localIP) {
    Write-Host "Could not determine local IP address" -ForegroundColor Red
    $localIP = Read-Host "Enter your dev machine IP address"
}

Write-Host "Dev machine IP: $localIP" -ForegroundColor Green
Write-Host "VM IP: $VMHostname" -ForegroundColor Green
Write-Host ""

# Step 1: Start HTTP server in background
Write-Host "[1/3] Starting HTTP server..." -ForegroundColor Yellow

$buildPath = "c:\repos\privacyfirst\x64\Release"
$serverJob = Start-Job -ScriptBlock {
    param($path, $port)
    Set-Location $path
    python -m http.server $port
} -ArgumentList $buildPath, $Port

Start-Sleep -Seconds 2

if ($serverJob.State -eq "Running") {
    Write-Host "HTTP server started on port $Port" -ForegroundColor Green
} else {
    Write-Host "Failed to start HTTP server" -ForegroundColor Red
    exit 1
}

# Step 2: Create download script for VM
Write-Host "`n[2/3] Preparing VM download script..." -ForegroundColor Yellow

$vmScript = @"
# Download and run PrivacyFirst
`$url = 'http://${localIP}:${Port}'
`$dest = 'C:\PrivacyFirstTest'

if (-not (Test-Path `$dest)) { New-Item -Path `$dest -ItemType Directory -Force | Out-Null }

`$files = @('PrivacyFirst.exe', 'PrivacyFirst.dll', 'PrivacyCore.dll', 'PrivacyFirst.deps.json', 'PrivacyFirst.runtimeconfig.json')

Write-Host 'Downloading PrivacyFirst...' -ForegroundColor Cyan
foreach (`$file in `$files) {
    Invoke-WebRequest -Uri "`$url/`$file" -OutFile "`$dest\`$file" -ErrorAction SilentlyContinue
}
Write-Host 'Download complete!' -ForegroundColor Green
Write-Host 'Files at: C:\PrivacyFirstTest' -ForegroundColor White
"@

$vmScriptPath = "C:\PrivacyFirstTest\download.ps1"
$vmScript | Out-File -FilePath "\\$VMHostname\Tests\download.ps1" -Encoding UTF8 -Force

Write-Host "Download script created at: \\$VMHostname\Tests\download.ps1" -ForegroundColor Green

# Step 3: Instructions
Write-Host "`n[3/3] Deployment ready!" -ForegroundColor Green
Write-Host ""
Write-Host "=== On the VM (192.168.0.143), run: ===" -ForegroundColor Cyan
Write-Host "  cd C:\Tests" -ForegroundColor White
Write-Host "  .\download.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Then run PrivacyFirst:" -ForegroundColor Cyan
Write-Host "  cd C:\PrivacyFirstTest" -ForegroundColor White
Write-Host "  .\PrivacyFirst.exe" -ForegroundColor White
Write-Host ""
Write-Host "HTTP server is running. Press Ctrl+C when done." -ForegroundColor Yellow
Write-Host ""

# Keep server running
try {
    Wait-Job $serverJob
} finally {
    Stop-Job $serverJob
    Remove-Job $serverJob
    Write-Host "`nHTTP server stopped" -ForegroundColor Gray
}
