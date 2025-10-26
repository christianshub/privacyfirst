# PrivacyFirst Peripheral Serial Number Hider
# This script hides serial numbers of various peripherals like mouse, keyboard, controllers, etc.

# Get script directory for backup files
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backupFile = Join-Path $scriptDir "peripheral_serials_backup.json"
$attemptedFile = Join-Path $scriptDir "peripheral_serials_attempted.json"

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

function Get-PeripheralDevices {
    $deviceList = @()
    
    # Get USB devices
    Write-Host "  Scanning USB devices..." -ForegroundColor Gray
    $usbDevices = Get-WmiObject Win32_USBControllerDevice | ForEach-Object { [Wmi]$_.Dependent }
    
    # Get HID devices
    Write-Host "  Scanning HID devices..." -ForegroundColor Gray
    $hidDevices = Get-WmiObject Win32_PnPEntity | Where-Object { 
        $_.PNPClass -eq "HIDClass" -or 
        $_.PNPClass -eq "Mouse" -or 
        $_.PNPClass -eq "Keyboard" -or
        $_.PNPClass -eq "Media" -or
        $_.Name -like "*controller*" -or
        $_.Name -like "*gamepad*" -or
        $_.Name -like "*joystick*" -or
        $_.Name -like "*mouse*" -or
        $_.Name -like "*keyboard*"
    }
    
    # Process USB devices
    foreach ($device in $usbDevices) {
        if (-not [string]::IsNullOrEmpty($device.DeviceID)) {
            $serialNumber = Get-SerialNumberFromDeviceID -DeviceID $device.DeviceID
            if (-not [string]::IsNullOrEmpty($serialNumber)) {
                $deviceList += [PSCustomObject]@{
                    Name = $device.Name
                    DeviceID = $device.DeviceID
                    Type = "USB"
                    SerialNumber = $serialNumber
                }
            }
        }
    }
    
    # Process HID devices
    foreach ($device in $hidDevices) {
        if (-not [string]::IsNullOrEmpty($device.DeviceID)) {
            $serialNumber = Get-SerialNumberFromDeviceID -DeviceID $device.DeviceID
            if (-not [string]::IsNullOrEmpty($serialNumber)) {
                $deviceList += [PSCustomObject]@{
                    Name = $device.Name
                    DeviceID = $device.DeviceID
                    Type = "HID"
                    SerialNumber = $serialNumber
                }
            }
        }
    }
    
    # Remove duplicates based on DeviceID
    $uniqueDevices = $deviceList | Group-Object DeviceID | ForEach-Object { $_.Group[0] }
    
    # Filter out devices without serial numbers
    $devicesWithSerial = $uniqueDevices | Where-Object { -not [string]::IsNullOrEmpty($_.SerialNumber) }
    
    return $devicesWithSerial
}

function Get-SerialNumberFromDeviceID {
    param (
        [string]$DeviceID
    )
    
    # Extract serial number from device ID (format varies, this covers common formats)
    if ($DeviceID -match "\\(\w+)$") {
        return $matches[1]
    }
    elseif ($DeviceID -match "\\(\w+)&") {
        return $matches[1]
    }
    elseif ($DeviceID -match "\\(\w+)\\") {
        return $matches[1]
    }
    
    return $null
}

function Get-DeviceRegistryPath {
    param (
        [string]$DeviceID
    )
    
    # Format device ID for registry path
    $regPath = $DeviceID -replace "\\", "\\"
    
    # Check common peripheral registry paths
    $possiblePaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Enum\$regPath",
        "HKLM:\SYSTEM\CurrentControlSet\Enum\HID\$regPath",
        "HKLM:\SYSTEM\CurrentControlSet\Enum\USB\$regPath"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    # Try to find the path by searching for the last part of the device ID
    if ($DeviceID -match "([^\\]+)$") {
        $lastPart = $matches[1]
        $searchResults = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum" -Recurse -ErrorAction SilentlyContinue | 
            Where-Object { $_.PSPath -like "*$lastPart*" }
        
        if ($searchResults.Count -gt 0) {
            return $searchResults[0].PSPath
        }
    }
    
    return $null
}

function Save-Backup {
    param (
        [object[]]$Devices
    )
    
    try {
        $backupData = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Devices = @()
        }
        
        foreach ($device in $Devices) {
            $registryPath = Get-DeviceRegistryPath -DeviceID $device.DeviceID
            if ($registryPath) {
                $backupData.Devices += @{
                    Name = $device.Name
                    DeviceID = $device.DeviceID
                    Type = $device.Type
                    SerialNumber = $device.SerialNumber
                    RegistryPath = $registryPath
                }
            }
        }
        
        $backupData | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8
        Write-Host "Backup saved to: $backupFile" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error saving backup: $_" -ForegroundColor Red
        return $false
    }
}

function Load-Backup {
    try {
        if (Test-Path $backupFile) {
            $backupData = Get-Content -Path $backupFile -Raw | ConvertFrom-Json
            return $backupData
        }
        return $null
    }
    catch {
        Write-Host "Error loading backup: $_" -ForegroundColor Red
        return $null
    }
}

function Save-AttemptedChanges {
    param (
        [object[]]$Devices
    )
    
    try {
        $attemptedData = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Devices = $Devices
        }
        
        $attemptedData | ConvertTo-Json -Depth 10 | Out-File -FilePath $attemptedFile -Encoding UTF8
        return $true
    }
    catch {
        Write-Host "Error saving attempted changes: $_" -ForegroundColor Red
        return $false
    }
}

function Load-AttemptedChanges {
    try {
        if (Test-Path $attemptedFile) {
            $attemptedData = Get-Content -Path $attemptedFile -Raw | ConvertFrom-Json
            return $attemptedData
        }
        return $null
    }
    catch {
        Write-Host "Error loading attempted changes: $_" -ForegroundColor Red
        return $null
    }
}

function Remove-DeviceSerialNumber {
    param (
        [string]$RegistryPath,
        [string]$DeviceName
    )
    
    try {
        $modified = $false
        
        # Method 1: Remove device serial number property if it exists
        $serialProps = @("SerialNumber", "DeviceSerialNumber", "HardwareID")
        
        foreach ($prop in $serialProps) {
            if (Get-ItemProperty -Path $RegistryPath -Name $prop -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $RegistryPath -Name $prop -Force
                Write-Host "  Removed $prop property" -ForegroundColor Green
                $modified = $true
            }
        }
        
        # Method 2: Add registry key to hide device instance ID
        $deviceParamsPath = "$RegistryPath\Device Parameters"
        if (Test-Path $deviceParamsPath) {
            if (-not (Get-ItemProperty -Path $deviceParamsPath -Name "HideDeviceInstanceID" -ErrorAction SilentlyContinue)) {
                New-ItemProperty -Path $deviceParamsPath -Name "HideDeviceInstanceID" -Value 1 -PropertyType DWORD -Force
                Write-Host "  Added HideDeviceInstanceID property" -ForegroundColor Green
                $modified = $true
            }
            else {
                Set-ItemProperty -Path $deviceParamsPath -Name "HideDeviceInstanceID" -Value 1
                Write-Host "  Updated HideDeviceInstanceID property" -ForegroundColor Green
                $modified = $true
            }
        }
        
        if ($modified) {
            Write-Host "  Successfully hidden serial number for: $DeviceName" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "  No serial properties found to modify for: $DeviceName" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "  Error hiding serial number: $_" -ForegroundColor Red
        return $false
    }
}

function Set-RegistryPermissionsDeny {
    param (
        [string]$RegistryPath,
        [string]$DeviceName
    )
    
    try {
        # Convert PowerShell registry path to legacy path for acl functions
        $legacyRegPath = $RegistryPath -replace "HKLM:", "HKEY_LOCAL_MACHINE"
        
        # Get current ACL
        $acl = Get-Acl "Registry::$legacyRegPath"
        
        # Create a new rule that denies read permission to the Everyone group
        $everyoneID = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
        $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $denyReadRule = New-Object System.Security.AccessControl.RegistryAccessRule(
            $everyoneID,
            [System.Security.AccessControl.RegistryRights]::ReadKey,
            $inheritanceFlags,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Deny
        )
        
        # Add the new rule to the ACL
        $acl.AddAccessRule($denyReadRule)
        
        # Apply the updated ACL to the registry key
        Set-Acl -Path "Registry::$legacyRegPath" -AclObject $acl
        
        Write-Host "  Applied DENY Read permissions for the registry key" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  Error setting permissions: $_" -ForegroundColor Red
        return $false
    }
}

function Restore-DeviceSerialNumbers {
    param (
        [object]$BackupData
    )
    
    if (-not $BackupData -or -not $BackupData.Devices) {
        Write-Host "No backup data found to restore." -ForegroundColor Yellow
        return $false
    }
    
    Write-Host "Restoring original serial numbers..." -ForegroundColor Cyan
    $successful = 0
    $failed = 0
    
    foreach ($device in $BackupData.Devices) {
        Write-Host "Processing: $($device.Name)" -ForegroundColor Cyan
        
        if (Test-Path $device.RegistryPath) {
            try {
                # Restore Device Parameters if it was modified
                $deviceParamsPath = "$($device.RegistryPath)\Device Parameters"
                if (Test-Path $deviceParamsPath) {
                    if (Get-ItemProperty -Path $deviceParamsPath -Name "HideDeviceInstanceID" -ErrorAction SilentlyContinue) {
                        Remove-ItemProperty -Path $deviceParamsPath -Name "HideDeviceInstanceID" -Force
                        Write-Host "  Restored Device Parameters" -ForegroundColor Green
                    }
                }
                
                # Note: We can't easily restore removed properties, but we can remove the hiding properties
                $successful++
                Write-Host "  Successfully restored: $($device.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "  Error restoring: $_" -ForegroundColor Red
                $failed++
            }
        }
        else {
            Write-Host "  Registry path not found. Skipping..." -ForegroundColor Yellow
            $failed++
        }
    }
    
    Write-Host "Restore complete. Success: $successful, Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
    return $true
}

function Show-DeviceList {
    param (
        [object[]]$Devices,
        [string]$Title = "Current Devices"
    )
    
    Write-Host "`n$Title" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host " ID | Device Type | Serial Number | Device Name" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------------------------" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $Devices.Count; $i++) {
        $device = $Devices[$i]
        $truncatedName = if ($device.Name.Length -gt 40) { $device.Name.Substring(0, 37) + "..." } else { $device.Name }
        
        Write-Host (" {0,2} | {1,-10} | {2,-12} | {3}" -f $i, $device.Type, $device.SerialNumber, $truncatedName)
    }
    
    Write-Host "-----------------------------------------------------------------------" -ForegroundColor Cyan
}

function Show-Menu {
    Clear-Host
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "           PrivacyFirst Peripheral Serial Number Hider               " -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "This tool hides the serial numbers of your peripheral devices"
    Write-Host "such as mice, keyboards, controllers, and other USB/HID devices."
    Write-Host ""
    Write-Host "This helps prevent hardware tracking in games and applications."
    Write-Host "=================================================================" -ForegroundColor Cyan
    
    # Check for backup and attempted files
    $hasBackup = Test-Path $backupFile
    $hasAttempted = Test-Path $attemptedFile
    
    Write-Host "`n[1] " -NoNewline -ForegroundColor Green
    Write-Host "Select Individual Devices" -ForegroundColor White
    
    Write-Host "[2] " -NoNewline -ForegroundColor Yellow
    Write-Host "View Current Devices" -ForegroundColor White
    
    if ($hasBackup) {
        Write-Host "[3] " -NoNewline -ForegroundColor Yellow
        Write-Host "View Saved Original Values" -ForegroundColor White
    }
    
    if ($hasAttempted) {
        Write-Host "[4] " -NoNewline -ForegroundColor Yellow
        Write-Host "View Attempted Changes" -ForegroundColor White
    }
    
    if ($hasBackup) {
        Write-Host "[5] " -NoNewline -ForegroundColor Red
        Write-Host "Restore Original Serial Numbers" -ForegroundColor White
    }
    
    Write-Host "[0] " -NoNewline -ForegroundColor Gray
    Write-Host "Exit" -ForegroundColor White
    
    Write-Host "`n=================================================================" -ForegroundColor Cyan
}

# Main script execution
do {
    Show-Menu
    
    $choice = Read-Host "`nEnter your choice"
    
    switch ($choice) {
        "1" {
            # Select Individual Devices
            Write-Host "`nScanning for peripheral devices with serial numbers..." -ForegroundColor Cyan
            $devices = Get-PeripheralDevices
            
            if ($devices.Count -eq 0) {
                Write-Host "`nNo devices with serial numbers found." -ForegroundColor Yellow
                Write-Host "This could mean that your devices don't expose serial numbers" -ForegroundColor Yellow
                Write-Host "or they may already be hidden." -ForegroundColor Yellow
                Read-Host "`nPress Enter to continue"
                continue
            }
            
            Write-Host "`nFound $($devices.Count) devices with serial numbers:" -ForegroundColor Cyan
            Show-DeviceList -Devices $devices -Title "Available Devices"
            
            Write-Host "`nSelect devices to hide serial numbers:" -ForegroundColor Cyan
            Write-Host "[0-9] Select a specific device by ID" -ForegroundColor Yellow
            Write-Host "[C] Cancel" -ForegroundColor Red
            
            $selection = Read-Host "`nEnter your selection"
            
            if ($selection -eq "C" -or $selection -eq "c") {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                continue
            }
            
            $selectedDevices = @()
            
            if ($selection -match "^\d+$" -and [int]$selection -ge 0 -and [int]$selection -lt $devices.Count) {
                $selectedDevices += $devices[[int]$selection]
                Write-Host "Selected device: $($devices[[int]$selection].Name)" -ForegroundColor Cyan
            }
            else {
                Write-Host "Invalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 2
                continue
            }
            
            # Save backup before making changes
            Write-Host "`nSaving backup of original values..." -ForegroundColor Cyan
            Save-Backup -Devices $selectedDevices
            
            # Protection options
            Write-Host "`nSelect protection methods:" -ForegroundColor Cyan
            Write-Host "[1] Remove serial number properties only" -ForegroundColor Yellow
            Write-Host "[2] Remove serial number properties AND deny read permissions (recommended)" -ForegroundColor Yellow
            
            $protectionLevel = Read-Host "`nEnter protection level (1 or 2)"
            
            $denyPermissions = $false
            if ($protectionLevel -eq "2") {
                $denyPermissions = $true
                Write-Host "Will apply maximum protection (remove properties + deny permissions)." -ForegroundColor Green
            } else {
                Write-Host "Will apply basic protection (remove properties only)." -ForegroundColor Yellow
            }
            
            # Confirm before proceeding
            $confirm = Read-Host "`nReady to hide serial numbers for the selected devices. Proceed? (Y/N)"
            
            if ($confirm -ne "Y" -and $confirm -ne "y") {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                continue
            }
            
            Write-Host "`nHiding device serial numbers..." -ForegroundColor Cyan
            Write-Host "-----------------------------------------------------------------------" -ForegroundColor Cyan
            
            $successful = 0
            $failed = 0
            $skipped = 0
            $processedDevices = @()
            
            foreach ($device in $selectedDevices) {
                Write-Host "Processing: $($device.Name)" -ForegroundColor Cyan
                
                # Get registry path for device
                $registryPath = Get-DeviceRegistryPath -DeviceID $device.DeviceID
                
                if ($null -eq $registryPath) {
                    Write-Host "  Registry path not found. Skipping..." -ForegroundColor Yellow
                    $skipped++
                    continue
                }
                
                # Hide serial number
                $success = Remove-DeviceSerialNumber -RegistryPath $registryPath -DeviceName $device.Name
                
                # Apply permissions deny if requested
                if ($success -and $denyPermissions) {
                    Write-Host "  Applying ACL deny permissions..." -ForegroundColor Yellow
                    $permSuccess = Set-RegistryPermissionsDeny -RegistryPath $registryPath -DeviceName $device.Name
                    
                    if (-not $permSuccess) {
                        Write-Host "  Warning: Serial number properties were modified but permissions could not be set." -ForegroundColor Yellow
                    }
                }
                
                # Add to processed devices list (for attempted changes file)
                $processedDevices += $device
                
                if ($success) {
                    $successful++
                } else {
                    $failed++
                }
                
                Write-Host "-----------------------------------------------------------------------" -ForegroundColor Cyan
            }
            
            # Save attempted changes
            Save-AttemptedChanges -Devices $processedDevices
            
            Write-Host "`nSerial number hiding operation complete." -ForegroundColor Cyan
            if ($skipped -gt 0) {
                Write-Host "Success: $successful, Failed: $failed, Skipped: $skipped" -ForegroundColor Yellow
            } else {
                Write-Host "Success: $successful, Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
            }
            
            Write-Host "`n=============================================================="-ForegroundColor Yellow
            Write-Host " A SYSTEM RESTART IS RECOMMENDED for changes to take effect " -ForegroundColor Yellow
            Write-Host " Please restart your computer when convenient.              " -ForegroundColor Yellow
            Write-Host "==============================================================" -ForegroundColor Yellow
            
            Read-Host "`nPress Enter to continue"
        }
        
        "2" {
            # View Current Devices
            Write-Host "`nScanning for peripheral devices with serial numbers..." -ForegroundColor Cyan
            $devices = Get-PeripheralDevices
            
            if ($devices.Count -eq 0) {
                Write-Host "`nNo devices with serial numbers found." -ForegroundColor Yellow
                Write-Host "This could mean that your devices don't expose serial numbers" -ForegroundColor Yellow
                Write-Host "or they may already be hidden." -ForegroundColor Yellow
            } else {
                Write-Host "`nFound $($devices.Count) devices with serial numbers:" -ForegroundColor Cyan
                Show-DeviceList -Devices $devices -Title "Current Devices"
            }
            
            Read-Host "`nPress Enter to continue"
        }
        
        "3" {
            # View Saved Original Values
            $backupData = Load-Backup
            if ($backupData -and $backupData.Devices) {
                Write-Host "`nBackup created on: $($backupData.Timestamp)" -ForegroundColor Cyan
                Show-DeviceList -Devices $backupData.Devices -Title "Saved Original Values"
            } else {
                Write-Host "`nNo backup data found." -ForegroundColor Yellow
            }
            
            Read-Host "`nPress Enter to continue"
        }
        
        "4" {
            # View Attempted Changes
            $attemptedData = Load-AttemptedChanges
            if ($attemptedData -and $attemptedData.Devices) {
                Write-Host "`nAttempted changes on: $($attemptedData.Timestamp)" -ForegroundColor Cyan
                Show-DeviceList -Devices $attemptedData.Devices -Title "Attempted Changes"
            } else {
                Write-Host "`nNo attempted changes data found." -ForegroundColor Yellow
            }
            
            Read-Host "`nPress Enter to continue"
        }
        
        "5" {
            # Restore Original Serial Numbers
            $backupData = Load-Backup
            if (-not $backupData) {
                Write-Host "`nNo backup data found to restore." -ForegroundColor Yellow
                Read-Host "`nPress Enter to continue"
                continue
            }
            
            Write-Host "`nBackup found from: $($backupData.Timestamp)" -ForegroundColor Cyan
            Show-DeviceList -Devices $backupData.Devices -Title "Devices to Restore"
            
            $confirm = Read-Host "`nReady to restore original serial numbers. Proceed? (Y/N)"
            
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                Restore-DeviceSerialNumbers -BackupData $backupData
                
                Write-Host "`n=============================================================="-ForegroundColor Yellow
                Write-Host " A SYSTEM RESTART IS RECOMMENDED for changes to take effect " -ForegroundColor Yellow
                Write-Host " Please restart your computer when convenient.              " -ForegroundColor Yellow
                Write-Host "==============================================================" -ForegroundColor Yellow
            } else {
                Write-Host "Restore cancelled." -ForegroundColor Yellow
            }
            
            Read-Host "`nPress Enter to continue"
        }
        
        "0" {
            Write-Host "`nExiting PrivacyFirst Peripheral Serial Number Hider..." -ForegroundColor Cyan
            break
        }
        
        default {
            Write-Host "`nInvalid choice. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true) 