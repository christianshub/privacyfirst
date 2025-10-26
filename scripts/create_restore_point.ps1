# PrivacyFirst - Restore Point Helper
# Opens Windows System Protection UI so the user can manually create a restore point.

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

# Dot-source helper for consistent coloured output (if present)
$helperPath = Join-Path $scriptDir "PrivacyFirst-Helpers.ps1"
if (Test-Path $helperPath) { . $helperPath }

# Administrator privileges are recommended but not strictly required for opening the UI
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if (Get-Command Write-WarningX -ErrorAction SilentlyContinue) {
        Write-WarningX "Running without Administrator privileges. You might be asked for elevation inside the UI when creating a restore point."
    } else {
        Write-Warning "Running without Administrator privileges. You might be asked for elevation inside the UI when creating a restore point."
    }
}

Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "          PrivacyFirst - System Restore Point" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "" 
Write-Host "Windows will now open the System Protection window." -ForegroundColor Yellow
Write-Host "1. Click 'Create...' to generate a restore point." -ForegroundColor Green
Write-Host "2. Return to PrivacyFirst when finished." -ForegroundColor Green
Write-Host "" 

# Determine correct path to SystemPropertiesProtection.exe for 32-/64-bit sessions
$sysProtExe = Join-Path $env:SystemRoot "System32\SystemPropertiesProtection.exe"
if (-not (Test-Path $sysProtExe)) {
    $altPath = Join-Path $env:SystemRoot "Sysnative\SystemPropertiesProtection.exe"  # 32-bit redirection bypass
    if (Test-Path $altPath) { $sysProtExe = $altPath }
}

try {
    $launched = $false
    $candidates = @(
        @{Path=$sysProtExe; Args=$null },
        @{Path=Join-Path $env:SystemRoot 'System32\control.exe'; Args=@('/name','Microsoft.SystemRestore')},
        @{Path=Join-Path $env:SystemRoot 'System32\rundll32.exe'; Args=@('shell32.dll,Control_RunDLL','sysdm.cpl,,4')}
    )

    foreach ($cmd in $candidates) {
        if ($launched) { break }
        if (Test-Path $cmd.Path) {
            try {
                if ($cmd.Args) {
                    Start-Process -FilePath $cmd.Path -ArgumentList $cmd.Args -WindowStyle Normal -ErrorAction Stop
                } else {
                    Start-Process -FilePath $cmd.Path -WindowStyle Normal -ErrorAction Stop
                }
                Start-Sleep -Seconds 1  # Give the window time to appear
                $launched = $true
            } catch {
                # Continue to next candidate
            }
        }
    }

    if (-not $launched) {
        throw 'All launch methods failed.'
    }
} catch {
    if (Get-Command Write-ErrorX -ErrorAction SilentlyContinue) {
        Write-ErrorX "Failed to launch System Protection window: $_"
    } else {
        Write-Host "Failed to launch System Protection window: $_" -ForegroundColor Red
    }
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "ERROR: $($_ | Out-String)" -ForegroundColor Red
    Read-Host "Press Enter to continue"
}

Write-Host "" 
Write-Host "Press any key after you have created your restore point to return to the main menu..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') 