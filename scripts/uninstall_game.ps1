# Game Uninstaller with Revo
# This script helps uninstall games using Revo Uninstaller

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

# Get script directory with multiple fallback methods
$scriptDir = $null
if ($PSScriptRoot) {
    $scriptDir = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
} elseif ($MyInvocation.MyCommand.Definition) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
} else {
    $scriptDir = Get-Location
    Write-Warning "Could not determine script directory. Using current location: $scriptDir"
}

# Configuration - use absolute path construction
$toolsDir = Join-Path (Split-Path $scriptDir -Parent) "tools"
$revoLocalPath = "$toolsDir\RevoUninstaller.exe"

# Create tools directory if it doesn't exist
if (-not (Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
}

# List of files to clean up after Revo closes
$revoDataFiles = @(
    "ctrlbars.dat",
    "settings.ini", 
    "un_report.dat"
)

function Check-RevoInstaller {
    if (Test-Path $revoLocalPath) {
        return $true
    }
    return $false
}

function Clean-RevoDataFiles {
    # Clean up Revo data files from main directory (silently)
    $projectRoot = Split-Path $scriptDir -Parent
    foreach ($file in $revoDataFiles) {
        $filePath = Join-Path $projectRoot $file
        if (Test-Path $filePath) {
            try {
                Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
            }
            catch {
                # Silently continue if file can't be removed
            }
        }
    }
}

function Show-UninstallInstructions {
    Clear-Host
    Write-Host "=== Game Uninstaller Tool ===" -ForegroundColor Cyan
    Write-Host "`nRevo Uninstaller will open when you are ready." -ForegroundColor Green
    Write-Host "`nInstructions:" -ForegroundColor Cyan
    Write-Host "1. Find your game in the list" -ForegroundColor Yellow
    Write-Host "2. Right-click and select 'Uninstall'" -ForegroundColor Yellow
    Write-Host "3. Use 'Advanced' mode for cleanup" -ForegroundColor Yellow
    Write-Host "4. Select and delete leftover files/entries" -ForegroundColor Yellow
    Write-Host "5. Close Revo Uninstaller when finished" -ForegroundColor Yellow
    # Wait for the user so slower readers aren’t rushed
    $null = Read-Host -Prompt "`nPress Enter to launch Revo Uninstaller"
}

function Run-RevoUninstaller {
    try {
        $revoFullPath = Resolve-Path $revoLocalPath -ErrorAction Stop
        Start-Process -FilePath $revoFullPath -Verb RunAs -Wait
        return $true
    }
    catch {
        Write-Host "Error: Could not start Revo Uninstaller" -ForegroundColor Red
        Write-Host "Make sure RevoUninstaller.exe is in the tools folder." -ForegroundColor Yellow
        return $false
    }
    finally {
        Clean-RevoDataFiles
    }
}

# Main script
Write-Host "=== Game Uninstaller Tool ===" -ForegroundColor Cyan

if (-not (Check-RevoInstaller)) {
    Write-Host "Revo Uninstaller not found at: $revoLocalPath" -ForegroundColor Red
    Write-Host "Please place RevoUninstaller.exe in the tools directory: $toolsDir" -ForegroundColor Yellow
    $response = Read-Host "`nPress Enter when you've added the file, or type 'skip' to exit"
    if ($response -eq "skip") { return }
    if (-not (Check-RevoInstaller)) {
        Write-Host "Revo Uninstaller still not found. Exiting..." -ForegroundColor Red
        Start-Sleep -Seconds 3
        return
    }
}

Show-UninstallInstructions
$success = Run-RevoUninstaller

if (-not $success) {
    Write-Host "`nTroubleshooting:" -ForegroundColor Cyan
    Write-Host "1. Make sure RevoUninstaller.exe is in: $toolsDir" -ForegroundColor Yellow
    Write-Host "2. Try running the app manually" -ForegroundColor Yellow
    Write-Host "3. Ensure you're running this script as Administrator" -ForegroundColor Yellow
    return
}

Write-Host "`nRevo Uninstaller has closed." -ForegroundColor Green
Write-Host "Press any key to return to the main menu..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
