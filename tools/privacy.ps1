# Privacy First - Main Menu
# Run this script as Administrator

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script requires Administrator privileges to work properly!" -ForegroundColor Red
    Write-Host "Please close this window and run the script as Administrator by:" -ForegroundColor Yellow
    Write-Host "1. Right-clicking on privacy.bat" -ForegroundColor Yellow
    Write-Host "2. Selecting 'Run as administrator'" -ForegroundColor Yellow
    Write-Host "3. Clicking 'Yes' when prompted by User Account Control" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
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

# Get the parent directory of tools folder (main project directory)
$mainDir = Split-Path -Parent $scriptDir
# Create scripts directory if it doesn't exist
$scriptsDir = Join-Path $mainDir "scripts"
if (-not (Test-Path $scriptsDir)) {
    New-Item -ItemType Directory -Path $scriptsDir | Out-Null
}

function Show-Menu {
    Clear-Host
    Write-Host "================ Privacy First ================" -ForegroundColor Cyan
    Write-Host "0. Create System Restore Point (HIGHLY RECOMMENDED)" -ForegroundColor Green
    Write-Host "1. Uninstall Game & Clear Traces (Revo Uninstaller)" -ForegroundColor Yellow
    Write-Host "2. Change Registry HWIDs" -ForegroundColor Yellow
    Write-Host "3. Setup VPN (OpenVPN with NordVPN)" -ForegroundColor Yellow
    Write-Host "4. Change Disk IDs / Serials" -ForegroundColor Yellow
    Write-Host "5. Change Hardware IDs" -ForegroundColor Yellow
    Write-Host "6. Change MAC Address" -ForegroundColor Yellow
    Write-Host "7. Change Monitor HWID" -ForegroundColor Yellow
    Write-Host "8. Hide Peripheral Serial Numbers" -ForegroundColor Yellow
    Write-Host "9. Privacy First Cleaner" -ForegroundColor Yellow
    Write-Host "10. Exit" -ForegroundColor Red
    Write-Host "=============================================" -ForegroundColor Cyan
}


function Invoke-PrivacyFirstCleaner {
    Clear-Host
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "             PrivacyFirst System Cleaner" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This tool will clean various system traces that" -ForegroundColor Yellow
    Write-Host "can be used to identify your system." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Select a cleaning option:" -ForegroundColor Cyan
    Write-Host "1. Clean Temporary Files" -ForegroundColor Yellow
    Write-Host "2. Clear Windows Event Logs" -ForegroundColor Yellow
    Write-Host "3. Clear DNS Cache" -ForegroundColor Yellow
    Write-Host "0. Return to Main Menu" -ForegroundColor Red
    Write-Host ""
    
    $cleanOption = Read-Host "Select an option"
    
    switch ($cleanOption) {
        1 {
            Write-Host ""
            Write-Host "Cleaning temporary files..." -ForegroundColor Cyan
            Remove-Item -Path "$env:TEMP\*" -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item -Path "C:\Windows\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue
            Write-Host "Temporary files cleaned successfully!" -ForegroundColor Green
        }
        2 {
            Write-Host ""
            Write-Host "Clearing Windows Event Logs..." -ForegroundColor Cyan
            $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.RecordCount -gt 0 -and $_.IsEnabled -eq $true } | Select-Object LogName
            foreach ($log in $logs) {
                Write-Host "Clearing $($log.LogName)..." -ForegroundColor Yellow
                try {
                    [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog("$($log.LogName)")
                } catch {
                    Write-Host "Could not clear $($log.LogName)" -ForegroundColor Red
                }
            }
            Write-Host "Windows Event Logs cleared successfully!" -ForegroundColor Green
        }
        3 {
            Write-Host ""
            Write-Host "Clearing DNS Cache..." -ForegroundColor Cyan
            ipconfig /flushdns
            Write-Host "DNS Cache cleared successfully!" -ForegroundColor Green
        }
        4 {
            Write-Host ""
            Write-Host "Clearing Recent Files History..." -ForegroundColor Cyan
            Remove-Item -Path "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -Recurse -ErrorAction SilentlyContinue
            Write-Host "Recent Files History cleared successfully!" -ForegroundColor Green
        }
        5 {
            Write-Host ""
            Write-Host "Cleaning Browser Data..." -ForegroundColor Cyan
            
            # Chrome
            $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
            if (Test-Path $chromePath) {
                Write-Host "Cleaning Chrome browser data..." -ForegroundColor Yellow
                Remove-Item -Path "$chromePath\Cookies*" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$chromePath\History*" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$chromePath\Cache\*" -Force -Recurse -ErrorAction SilentlyContinue
            }
            
            # Firefox
            $firefoxProfiles = "$env:APPDATA\Mozilla\Firefox\Profiles"
            if (Test-Path $firefoxProfiles) {
                Write-Host "Cleaning Firefox browser data..." -ForegroundColor Yellow
                Get-ChildItem -Path $firefoxProfiles -Directory | ForEach-Object {
                    Remove-Item -Path "$($_.FullName)\cookies.sqlite" -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "$($_.FullName)\places.sqlite" -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "$($_.FullName)\cache2\*" -Force -Recurse -ErrorAction SilentlyContinue
                }
            }
            
            # Edge
            $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
            if (Test-Path $edgePath) {
                Write-Host "Cleaning Edge browser data..." -ForegroundColor Yellow
                Remove-Item -Path "$edgePath\Cookies*" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$edgePath\History*" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$edgePath\Cache\*" -Force -Recurse -ErrorAction SilentlyContinue
            }
            
            Write-Host "Browser data cleaned successfully!" -ForegroundColor Green
        }
        6 {
            Write-Host ""
            Write-Host "Running all cleaners..." -ForegroundColor Cyan
            
            # Clean Temp Files
            Write-Host "Cleaning temporary files..." -ForegroundColor Yellow
            Remove-Item -Path "$env:TEMP\*" -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item -Path "C:\Windows\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue
            
            # Clear Event Logs
            Write-Host "Clearing Windows Event Logs..." -ForegroundColor Yellow
            $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.RecordCount -gt 0 -and $_.IsEnabled -eq $true } | Select-Object LogName
            foreach ($log in $logs) {
                try {
                    [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog("$($log.LogName)")
                } catch {
                    # Silently continue
                }
            }
            
            # Clear DNS Cache
            Write-Host "Clearing DNS Cache..." -ForegroundColor Yellow
            ipconfig /flushdns
            
            # Clear Recent Files
            Write-Host "Clearing Recent Files History..." -ForegroundColor Yellow
            Remove-Item -Path "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -Recurse -ErrorAction SilentlyContinue
            
            # Clean Browser Data
            Write-Host "Cleaning Browser Data..." -ForegroundColor Yellow
            
            # Chrome
            $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
            if (Test-Path $chromePath) {
                Remove-Item -Path "$chromePath\Cookies*" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$chromePath\History*" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$chromePath\Cache\*" -Force -Recurse -ErrorAction SilentlyContinue
            }
            
            # Firefox
            $firefoxProfiles = "$env:APPDATA\Mozilla\Firefox\Profiles"
            if (Test-Path $firefoxProfiles) {
                Get-ChildItem -Path $firefoxProfiles -Directory | ForEach-Object {
                    Remove-Item -Path "$($_.FullName)\cookies.sqlite" -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "$($_.FullName)\places.sqlite" -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "$($_.FullName)\cache2\*" -Force -Recurse -ErrorAction SilentlyContinue
                }
            }
            
            # Edge
            $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
            if (Test-Path $edgePath) {
                Remove-Item -Path "$edgePath\Cookies*" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$edgePath\History*" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$edgePath\Cache\*" -Force -Recurse -ErrorAction SilentlyContinue
            }
            
            Write-Host ""
            Write-Host "All cleaning tasks completed successfully!" -ForegroundColor Green
        }
        0 {
            return
        }
        default {
            Write-Host "Invalid option. Returning to main menu..." -ForegroundColor Red
            Start-Sleep -Seconds 2
            return
        }
    }
    
    Write-Host ""
    Write-Host "Press any key to return to the PrivacyFirst Cleaner menu..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    Invoke-PrivacyFirstCleaner
}

function Invoke-Option {
    param (
        [int]$Option
    )

    switch ($Option) {
        0 { 
            & "$scriptsDir\create_restore_point.ps1"
        }
        1 { 
            & "$scriptsDir\uninstall_game.ps1"
        }
        2 { 
            & "$scriptsDir\change_registry_hwids.ps1"
        }
        3 { 
            & "$scriptsDir\setup_vpn.ps1"
        }
        4 { 
            & "$scriptsDir\change_disk_ids.ps1"
        }
        5 { 
            # Run the updated hardware ID changer script with backup/restore functionality
            & "$scriptsDir\change_hardware_ids.ps1"
        }
        6 { 
            & "$scriptsDir\change_mac_address.ps1"
        }
        7 { 
            & "$scriptsDir\change_monitor_hwid.ps1"
        }
        8 { 
            & "$scriptsDir\hide_peripheral_serials.ps1"
        }
        9 { 
            & "$scriptsDir\PrivacyFirst_cleaner.ps1"
        }

        10 { 
            return $false
        }
        default {
            Write-Host "Invalid option. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
    return $true
}

# Main program loop
$continue = $true

# Show a recommendation for creating a restore point on first run
Clear-Host
Write-Host "================ Privacy First ================" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT RECOMMENDATION:" -ForegroundColor Red
Write-Host "Before making any system changes, it is HIGHLY RECOMMENDED" -ForegroundColor Yellow
Write-Host "that you create a system restore point (Option 0)." -ForegroundColor Yellow
Write-Host "This will allow you to revert your system if needed." -ForegroundColor Yellow
Write-Host ""
Write-Host "Press any key to continue to the main menu..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

while ($continue) {
    Show-Menu
    $option = Read-Host "Select an option"
    
    if ($option -match '^\d+$') {
        $continue = Invoke-Option -Option ([int]$option)
    }
    else {
        Write-Host "Please enter a valid number." -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
} 