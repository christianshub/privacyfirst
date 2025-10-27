# Simple HTTP file server for VM testing
# Serves the build directory on port 8080

param(
    [int]$Port = 8080
)

$buildPath = "c:\repos\privacyfirst\x64\Release"

if (-not (Test-Path $buildPath)) {
    Write-Host "Build directory not found: $buildPath" -ForegroundColor Red
    exit 1
}

Write-Host "=== PrivacyFirst HTTP File Server ===" -ForegroundColor Cyan
Write-Host "Serving: $buildPath" -ForegroundColor White
Write-Host "URL: http://$(hostname):$Port/" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

# Start Python HTTP server
Push-Location $buildPath
python -m http.server $Port
Pop-Location
