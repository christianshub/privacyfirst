# Change Registry HWIDs
# This script changes HwProfileGuid and MachineGuid to random values and provides restore functionality

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
    # Last resort - use current directory and assume we're in scripts folder
    $scriptDir = Get-Location
    Write-Warning "Could not determine script directory. Using current location: $scriptDir"
}

# Dot-source helper functions for consistent coloured output
$helperPath = Join-Path $scriptDir "PrivacyFirst-Helpers.ps1"
if (Test-Path $helperPath) { . $helperPath }

# Cache file for original registry values - use absolute path construction
$toolsDir = Join-Path (Split-Path $scriptDir -Parent) "tools"
$cacheFile = Join-Path $toolsDir "original_registry_hwids.json"

# Ensure tools directory exists
if (-not (Test-Path $toolsDir)) {
    try {
        New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Host "Warning: Could not create tools directory: $toolsDir" -ForegroundColor Yellow
    }
}

function New-GuidString {
    # Generate a GUID in the format {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}
    return "{" + [guid]::NewGuid().ToString() + "}"
}

function New-RegularGuid {
    # Generate a GUID in the format xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (without braces)
    return [guid]::NewGuid().ToString()
}

function Load-OriginalValues {
    if (Test-Path $cacheFile) {
        try {
            $content = Get-Content $cacheFile -Raw | ConvertFrom-Json
            return $content
        }
        catch {
            Write-ErrorX "Error reading cache file: $_"
            return $null
        }
    }
    return $null
}

function Save-OriginalValues {
    param($originalValues)
    
    try {
        $originalValues | ConvertTo-Json -Depth 3 | Set-Content $cacheFile
        Write-Success "Original values backed up successfully."
    }
    catch {
        Write-ErrorX "Error saving original values: $_"
    }
}

function Get-CurrentRegistryValues {
    $hwProfilePath = "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001"
    $cryptographyPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
    
    try {
        $hwProfileGuid = (Get-ItemProperty -Path $hwProfilePath).HwProfileGuid
        $machineGuid = (Get-ItemProperty -Path $cryptographyPath).MachineGuid
        
        return @{
            HwProfileGuid = $hwProfileGuid
            MachineGuid = $machineGuid
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    catch {
        Write-ErrorX "Error reading current registry values: $_"
        return $null
    }
}

function Change-RegistryHWIDs {
    Clear-Host
    Write-Host "=== Change Registry HWIDs ===" -ForegroundColor Cyan
    Write-Host "`nThis tool will change important system identifiers:" -ForegroundColor Yellow

    # Get current values
    $currentValues = Get-CurrentRegistryValues
    if (-not $currentValues) {
        Write-ErrorX "Failed to read current registry values."
        return
    }

    # Check if we need to backup original values
    $originalValues = Load-OriginalValues
    if (-not $originalValues) {
        Write-Host "`nBacking up original values before making changes..." -ForegroundColor Yellow
        Save-OriginalValues -originalValues $currentValues
        $originalValues = $currentValues
    }

    # Generate new values
    $newHwProfileGuid = New-GuidString
    $newMachineGuid = New-RegularGuid

    # Display current and new values
    Write-Host "`n========== CURRENT VALUES ==========" -ForegroundColor Cyan
    Write-Host "HwProfileGuid: $($currentValues.HwProfileGuid)" -ForegroundColor Yellow
    Write-Host "MachineGuid: $($currentValues.MachineGuid)" -ForegroundColor Yellow

    Write-Host "`n========== NEW VALUES ==========" -ForegroundColor Cyan
    Write-Host "HwProfileGuid: $newHwProfileGuid" -ForegroundColor Green
    Write-Host "MachineGuid: $newMachineGuid" -ForegroundColor Green

    # Show original values if different from current
    if ($originalValues.HwProfileGuid -ne $currentValues.HwProfileGuid -or 
        $originalValues.MachineGuid -ne $currentValues.MachineGuid) {
        Write-Host "`n========== ORIGINAL VALUES (Backed Up) ==========" -ForegroundColor Magenta
        Write-Host "HwProfileGuid: $($originalValues.HwProfileGuid)" -ForegroundColor Magenta
        Write-Host "MachineGuid: $($originalValues.MachineGuid)" -ForegroundColor Magenta
    }

    # Ask for confirmation
    Write-Host "`n" -NoNewline
    $confirmation = Read-Host "Do you want to proceed with these changes? (Y/N)"

    if ($confirmation -eq "Y" -or $confirmation -eq "y") {
        Write-Host "`nChanging Registry HWIDs..." -ForegroundColor Cyan
        
        $hwProfilePath = "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001"
        $cryptographyPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
        
        # Change HwProfileGuid
        try {
            Set-ItemProperty -Path $hwProfilePath -Name "HwProfileGuid" -Value $newHwProfileGuid -Type String
            $verifyHw = (Get-ItemProperty -Path $hwProfilePath).HwProfileGuid
            if ($verifyHw -eq $newHwProfileGuid) {
                Write-Success "HwProfileGuid successfully changed!"
            } else {
                Write-ErrorX "Verification failed: HwProfileGuid does not match expected value."
            }
        }
        catch {
            Write-ErrorX "Error changing HwProfileGuid: $_"
        }

        # Change MachineGuid
        try {
            Set-ItemProperty -Path $cryptographyPath -Name "MachineGuid" -Value $newMachineGuid -Type String
            $verifyMg = (Get-ItemProperty -Path $cryptographyPath).MachineGuid
            if ($verifyMg -eq $newMachineGuid) {
                Write-Success "MachineGuid successfully changed!"
            } else {
                Write-ErrorX "Verification failed: MachineGuid does not match expected value."
            }
        }
        catch {
            Write-ErrorX "Error changing MachineGuid: $_"
        }

        Write-Host "`nRegistry HWIDs have been changed." -ForegroundColor Cyan
        Write-Host "Original values are safely backed up and can be restored using option 2." -ForegroundColor Yellow
    } else {
        Write-Host "`nOperation canceled. No changes were made." -ForegroundColor Yellow
    }
}

function Restore-OriginalRegistryHWIDs {
    Clear-Host
    Write-Host "=== Restore Original Registry HWIDs ===" -ForegroundColor Cyan
    
    # Load original values
    $originalValues = Load-OriginalValues
    if (-not $originalValues) {
        Write-ErrorX "No backup found. Cannot restore original values."
        Write-Host "Original values are only available after using the change function first." -ForegroundColor Yellow
        return
    }

    # Get current values
    $currentValues = Get-CurrentRegistryValues
    if (-not $currentValues) {
        Write-ErrorX "Failed to read current registry values."
        return
    }

    Write-Host "`nBackup Information:" -ForegroundColor Yellow
    Write-Host "Backup Date: $($originalValues.Timestamp)" -ForegroundColor Gray

    Write-Host "`n========== CURRENT VALUES ==========" -ForegroundColor Cyan
    Write-Host "HwProfileGuid: $($currentValues.HwProfileGuid)" -ForegroundColor Yellow
    Write-Host "MachineGuid: $($currentValues.MachineGuid)" -ForegroundColor Yellow

    Write-Host "`n========== ORIGINAL VALUES (TO RESTORE) ==========" -ForegroundColor Cyan
    Write-Host "HwProfileGuid: $($originalValues.HwProfileGuid)" -ForegroundColor Green
    Write-Host "MachineGuid: $($originalValues.MachineGuid)" -ForegroundColor Green

    # Check if already restored
    if ($currentValues.HwProfileGuid -eq $originalValues.HwProfileGuid -and 
        $currentValues.MachineGuid -eq $originalValues.MachineGuid) {
        Write-Host "`nRegistry values are already set to their original values." -ForegroundColor Green
        Write-Host "Do you want to remove the backup file? (Y/N): " -NoNewline -ForegroundColor Yellow
        $removeBackup = Read-Host
        if ($removeBackup -eq "Y" -or $removeBackup -eq "y") {
            try {
                Remove-Item $cacheFile -Force
                Write-Success "Backup file removed successfully."
            }
            catch {
                Write-ErrorX "Error removing backup file: $_"
            }
        }
        return
    }

    # Ask for confirmation
    Write-Host "`n" -NoNewline
    $confirmation = Read-Host "Do you want to restore the original values? (Y/N)"

    if ($confirmation -eq "Y" -or $confirmation -eq "y") {
        Write-Host "`nRestoring original Registry HWIDs..." -ForegroundColor Cyan
        
        $hwProfilePath = "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001"
        $cryptographyPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
        
        # Restore HwProfileGuid
        try {
            Set-ItemProperty -Path $hwProfilePath -Name "HwProfileGuid" -Value $originalValues.HwProfileGuid -Type String
            $verifyHw = (Get-ItemProperty -Path $hwProfilePath).HwProfileGuid
            if ($verifyHw -eq $originalValues.HwProfileGuid) {
                Write-Success "HwProfileGuid successfully restored!"
            } else {
                Write-ErrorX "Verification failed: HwProfileGuid does not match expected value."
            }
        }
        catch {
            Write-ErrorX "Error restoring HwProfileGuid: $_"
        }

        # Restore MachineGuid
        try {
            Set-ItemProperty -Path $cryptographyPath -Name "MachineGuid" -Value $originalValues.MachineGuid -Type String
            $verifyMg = (Get-ItemProperty -Path $cryptographyPath).MachineGuid
            if ($verifyMg -eq $originalValues.MachineGuid) {
                Write-Success "MachineGuid successfully restored!"
            } else {
                Write-ErrorX "Verification failed: MachineGuid does not match expected value."
            }
        }
        catch {
            Write-ErrorX "Error restoring MachineGuid: $_"
        }

        Write-Host "`nOriginal Registry HWIDs have been restored." -ForegroundColor Cyan
        
        # Ask if user wants to remove backup
        Write-Host "`nDo you want to remove the backup file now that values are restored? (Y/N): " -NoNewline -ForegroundColor Yellow
        $removeBackup = Read-Host
        if ($removeBackup -eq "Y" -or $removeBackup -eq "y") {
            try {
                Remove-Item $cacheFile -Force
                Write-Success "Backup file removed successfully."
            }
            catch {
                Write-ErrorX "Error removing backup file: $_"
            }
        }
    } else {
        Write-Host "`nRestore operation canceled. No changes were made." -ForegroundColor Yellow
    }
}

function Show-CurrentStatus {
    Clear-Host
    Write-Host "=== Registry HWID Status ===" -ForegroundColor Cyan
    
    # Get current values
    $currentValues = Get-CurrentRegistryValues
    if (-not $currentValues) {
        Write-ErrorX "Failed to read current registry values."
        return
    }

    # Load original values if available
    $originalValues = Load-OriginalValues

    Write-Host "`n========== CURRENT VALUES ==========" -ForegroundColor Cyan
    Write-Host "HwProfileGuid: $($currentValues.HwProfileGuid)" -ForegroundColor Yellow
    Write-Host "MachineGuid: $($currentValues.MachineGuid)" -ForegroundColor Yellow

    if ($originalValues) {
        Write-Host "`n========== ORIGINAL VALUES (Backed Up) ==========" -ForegroundColor Magenta
        Write-Host "HwProfileGuid: $($originalValues.HwProfileGuid)" -ForegroundColor Magenta
        Write-Host "MachineGuid: $($originalValues.MachineGuid)" -ForegroundColor Magenta
        Write-Host "Backup Date: $($originalValues.Timestamp)" -ForegroundColor Gray

        # Check if values have been changed
        if ($currentValues.HwProfileGuid -eq $originalValues.HwProfileGuid -and 
            $currentValues.MachineGuid -eq $originalValues.MachineGuid) {
            Write-Host "`nStatus: Registry values are set to ORIGINAL values" -ForegroundColor Green
        } else {
            Write-Host "`nStatus: Registry values have been CHANGED from original" -ForegroundColor Red
        }
    } else {
        Write-Host "`nNo backup available - these are the current system values." -ForegroundColor Gray
        Write-Host "Run option 1 to change values and create a backup." -ForegroundColor Yellow
    }
}

# Main menu loop
do {
    Clear-Host
    Write-Host "=== PRIVACY FIRST - Registry Changer ===" -ForegroundColor Cyan
    Write-Host "`nSelect an option:" -ForegroundColor Yellow
    Write-Host "1. Change Registry HWIDs (HwProfileGuid & MachineGuid)" -ForegroundColor White
    Write-Host "2. Restore Original Registry HWIDs" -ForegroundColor White
    Write-Host "3. Show Current Status" -ForegroundColor White
    Write-Host "0. Return to Main Menu" -ForegroundColor Gray
    Write-Host "`nChoice: " -NoNewline -ForegroundColor Yellow
    
    $choice = Read-Host

    switch ($choice) {
        "1" { Change-RegistryHWIDs }
        "2" { Restore-OriginalRegistryHWIDs }
        "3" { Show-CurrentStatus }
        "0" { 
            Write-Host "`nReturning to main menu..." -ForegroundColor Cyan
            break 
        }
        default { 
            Write-Host "`nInvalid choice. Please select 0-3." -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }
    }

    if ($choice -ne "0") {
        Write-Host "`nPress any key to continue..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
} while ($choice -ne "0")