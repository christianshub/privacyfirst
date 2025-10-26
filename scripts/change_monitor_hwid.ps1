# PrivacyFirst Monitor HWID Changer
# Professional script to change, backup, and restore monitor hardware identifiers

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

# Get script directory
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }

# Set paths
$toolsDir = Join-Path (Split-Path $scriptDir -Parent) "tools"
$originalMonitorsCache = Join-Path $toolsDir "original_monitors.json"
$backupMonitorsCache = Join-Path $toolsDir "backup_monitors.json"
$attemptedMonitorsCache = Join-Path $toolsDir "attempted_monitors.json"

# Function to generate random hex string
function New-RandomHexString {
    param([int]$Length)
    
    $chars = "0123456789ABCDEF"
    $result = ""
    
    for ($i = 0; $i -lt $Length; $i++) {
        $result += $chars[(Get-Random -Minimum 0 -Maximum 16)]
    }
    
    return $result
}

# Function to get monitor registry paths
function Get-MonitorRegistryPaths {
    $monitorPaths = @()
    
    try {
        # Get all monitor registry keys
        $monitorKeys = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY" -ErrorAction SilentlyContinue
        
        foreach ($monitorKey in $monitorKeys) {
            $subKeys = Get-ChildItem $monitorKey.PSPath -ErrorAction SilentlyContinue
            
            foreach ($subKey in $subKeys) {
                $deviceParams = "$($subKey.PSPath)\Device Parameters"
                if (Test-Path $deviceParams) {
                    $monitorPaths += [PSCustomObject]@{
                        Path = $deviceParams
                        DisplayName = $subKey.PSChildName
                    }
                }
            }
        }
    }
    catch {
        Write-Host "Error getting monitor registry paths: $_" -ForegroundColor Red
    }
    
    return $monitorPaths
}

# Function to get EDID data
function Get-EdidData {
    param([string]$RegistryPath)
    
    try {
        $edid = (Get-ItemProperty -Path $RegistryPath -Name "EDID" -ErrorAction SilentlyContinue).EDID
        return $edid
    }
    catch {
        return $null
    }
}

# Function to update EDID data
function Update-EdidData {
    param([byte[]]$OriginalEdid)
    
    if ($null -eq $OriginalEdid -or $OriginalEdid.Length -eq 0) {
        return $null
    }
    
    try {
        # Make a copy of the EDID
        $newEDID = $OriginalEdid.Clone()
        
        # Create a new random serial number
        $newSerial1 = [byte](Get-Random -Minimum 0 -Maximum 256)
        $newSerial2 = [byte](Get-Random -Minimum 0 -Maximum 256)
        $newSerial3 = [byte](Get-Random -Minimum 0 -Maximum 256)
        $newSerial4 = [byte](Get-Random -Minimum 0 -Maximum 256)
        
        # Store old serial for display
        $oldSerial = "0x{0:X2}{1:X2}{2:X2}{3:X2}" -f $OriginalEdid[12], $OriginalEdid[13], $OriginalEdid[14], $OriginalEdid[15]
        $newSerialHex = "0x{0:X2}{1:X2}{2:X2}{3:X2}" -f $newSerial1, $newSerial2, $newSerial3, $newSerial4
        
        # Modify serial number (bytes 12-15)
        $newEDID[12] = $newSerial1
        $newEDID[13] = $newSerial2
        $newEDID[14] = $newSerial3
        $newEDID[15] = $newSerial4
        
        # Recalculate checksum (byte 127)
        $sum = 0
        for ($i = 0; $i -lt 127; $i++) {
            $sum += $newEDID[$i]
        }
        $newEDID[127] = [byte]((256 - ($sum % 256)) % 256)
        
        return [PSCustomObject]@{
            EdidData = $newEDID
            OldSerial = $oldSerial
            NewSerial = $newSerialHex
        }
    }
    catch {
        Write-Host "Error modifying EDID: $_" -ForegroundColor Red
        return $null
    }
}

# Function to set monitor EDID
function Set-MonitorEdid {
    param([string]$RegistryPath, [byte[]]$NewEdid, [string]$DisplayName)
    
    try {
        Set-ItemProperty -Path $RegistryPath -Name "EDID" -Value $NewEdid
        Write-Host "SUCCESS: EDID updated for $DisplayName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "FAILED: Error updating EDID for $DisplayName - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to get monitor info from WMI
function Get-MonitorInfo {
    $monitorInfo = @()
    
    try {
        # Get WMI monitor info
        $wmiMonitors = Get-WmiObject WmiMonitorID -Namespace root\wmi
        
        foreach ($monitor in $wmiMonitors) {
            # Convert binary data to readable strings
            $manufacturerName = [System.Text.Encoding]::ASCII.GetString($monitor.ManufacturerName -ne 0)
            $productCodeID = [System.Text.Encoding]::ASCII.GetString($monitor.ProductCodeID -ne 0)
            $serialNumberID = [System.Text.Encoding]::ASCII.GetString($monitor.SerialNumberID -ne 0)
            $userFriendlyName = $monitor.UserFriendlyName -ne 0
            
            if ($userFriendlyName) {
                $userFriendlyName = [System.Text.Encoding]::ASCII.GetString($userFriendlyName)
            }
            else {
                $userFriendlyName = "Unknown"
            }
            
            $monitorInfo += [PSCustomObject]@{
                Manufacturer = $manufacturerName
                ProductCode = $productCodeID
                SerialNumber = $serialNumberID
                FriendlyName = $userFriendlyName
            }
        }
    }
    catch {
        Write-Host "Error getting monitor info from WMI: $_" -ForegroundColor Red
    }
    
    return $monitorInfo
}

# Function to save original monitor data
function Save-OriginalMonitors {
    param($monitors)
    
    try {
        $monitorsWithTimestamp = @{
            Monitors = $monitors
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $monitorsWithTimestamp | ConvertTo-Json -Depth 3 | Set-Content $originalMonitorsCache
        Write-Host "Original monitor data saved successfully!" -ForegroundColor Green
        Write-Host "Backup location: $originalMonitorsCache" -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "Error saving original monitor data: $_" -ForegroundColor Red
        return $false
    }
}

# Function to save backup monitor data
function Save-BackupMonitors {
    param($monitors)
    
    try {
        $monitorsWithTimestamp = @{
            Monitors = $monitors
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $monitorsWithTimestamp | ConvertTo-Json -Depth 3 | Set-Content $backupMonitorsCache
        return $true
    }
    catch {
        return $false
    }
}

# Function to save attempted monitor changes
function Save-AttemptedMonitors {
    param($changes)
    
    try {
        $changesWithTimestamp = @{
            AttemptedChanges = $changes
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $changesWithTimestamp | ConvertTo-Json -Depth 3 | Set-Content $attemptedMonitorsCache
        return $true
    }
    catch {
        return $false
    }
}

# Function to load original monitor data
function Load-OriginalMonitors {
    if (Test-Path $originalMonitorsCache) {
        try {
            $content = Get-Content $originalMonitorsCache -Raw | ConvertFrom-Json
            return $content
        }
        catch {
            Write-Host "Error reading original monitors cache: $_" -ForegroundColor Red
            return $null
        }
    }
    return $null
}

# Function to load backup monitor data
function Load-BackupMonitors {
    if (Test-Path $backupMonitorsCache) {
        try {
            $content = Get-Content $backupMonitorsCache -Raw | ConvertFrom-Json
            return $content
        }
        catch {
            return $null
        }
    }
    return $null
}

# Function to load attempted monitor changes
function Load-AttemptedMonitors {
    if (Test-Path $attemptedMonitorsCache) {
        try {
            $content = Get-Content $attemptedMonitorsCache -Raw | ConvertFrom-Json
            return $content
        }
        catch {
            return $null
        }
    }
    return $null
}

# Function to show menu
function Show-Menu {
    Clear-Host
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "    PrivacyFirst Monitor HWID Changer" -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Change All Monitor HWIDs" -ForegroundColor Green
    Write-Host "2. Change Individual Monitor" -ForegroundColor Green
    Write-Host "3. View Current Monitor Info" -ForegroundColor Yellow
    Write-Host "4. Save Current Values as Original" -ForegroundColor Yellow
    Write-Host "5. View Saved Original Values" -ForegroundColor Yellow
    Write-Host "6. Restore Original Monitor HWIDs" -ForegroundColor Green
    Write-Host "0. Exit" -ForegroundColor Red
    Write-Host ""
}

# Function to display monitor information
function Show-MonitorInfo {
    Write-Host "Reading Monitor Information..." -ForegroundColor Yellow
    Write-Host ""
    
    # Check if there are backup files indicating previous failures
    $backupData = Load-BackupMonitors
    $attemptedData = Load-AttemptedMonitors
    
    # Get current monitor info from WMI
    $monitorInfo = Get-MonitorInfo
    
    if ($monitorInfo.Count -eq 0) {
        Write-Host "No monitor information found through WMI." -ForegroundColor Yellow
        return @{}
    }
    
    Write-Host "Current Monitor Information:" -ForegroundColor Cyan
    Write-Host "----------------------------------------------------" -ForegroundColor Cyan
    
    $monitorData = @{}
    
    for ($i = 0; $i -lt $monitorInfo.Count; $i++) {
        $monitor = $monitorInfo[$i]
        
        # If we have attempted changes and this monitor was changed, show attempted values
        if ($backupData -and $attemptedData) {
            $attemptedMonitor = $attemptedData.AttemptedChanges | Where-Object { $_.Index -eq $i }
            if ($attemptedMonitor) {
                $monitor.SerialNumber = $attemptedMonitor.NewSerial
            }
        }
        
        $monitorData[$i] = $monitor
        
        Write-Host "Monitor $($i + 1):" -ForegroundColor Yellow
        Write-Host "  Manufacturer: $($monitor.Manufacturer)" -ForegroundColor White
        Write-Host "  Product Code: $($monitor.ProductCode)" -ForegroundColor White
        Write-Host "  Serial Number: $($monitor.SerialNumber)" -ForegroundColor White
        Write-Host "  Friendly Name: $($monitor.FriendlyName)" -ForegroundColor White
        Write-Host "----------------------------------------------------" -ForegroundColor Cyan
    }
    
    return $monitorData
}

# Function to get friendly monitor names
function Get-FriendlyMonitorNames {
    $monitorPaths = Get-MonitorRegistryPaths
    $monitorInfo = Get-MonitorInfo
    
    $friendlyNames = @{}
    
    # Try to match registry entries with WMI info
    for ($i = 0; $i -lt $monitorPaths.Count; $i++) {
        $monitor = $monitorPaths[$i]
        $friendlyName = $monitor.DisplayName  # Default to registry name
        
        # Try to find matching WMI monitor
        if ($monitorInfo.Count -gt 0) {
            # Use the monitor index if available, otherwise try to match by other criteria
            if ($i -lt $monitorInfo.Count) {
                $wmiMonitor = $monitorInfo[$i]
                if ($wmiMonitor.FriendlyName -and $wmiMonitor.FriendlyName -ne "Unknown") {
                    $friendlyName = $wmiMonitor.FriendlyName
                } elseif ($wmiMonitor.Manufacturer -and $wmiMonitor.ProductCode) {
                    $friendlyName = "$($wmiMonitor.Manufacturer) $($wmiMonitor.ProductCode)"
                } elseif ($wmiMonitor.Manufacturer) {
                    $friendlyName = "$($wmiMonitor.Manufacturer) Monitor"
                }
            }
        }
        
        $friendlyNames[$i] = $friendlyName
    }
    
    return $friendlyNames
}

# Function to display monitor registry entries
function Show-MonitorRegistryEntries {
    Write-Host "Reading Monitor Registry Entries..." -ForegroundColor Yellow
    Write-Host ""
    
    $monitorPaths = Get-MonitorRegistryPaths
    
    if ($monitorPaths.Count -eq 0) {
        Write-Host "No monitor registry entries found." -ForegroundColor Red
        return @()
    }
    
    # Get friendly names
    $friendlyNames = Get-FriendlyMonitorNames
    
    Write-Host "Available Monitors:" -ForegroundColor Cyan
    Write-Host "----------------------------------------------------" -ForegroundColor Cyan
    Write-Host " ID | Monitor Name                                 " -ForegroundColor Cyan
    Write-Host "----------------------------------------------------" -ForegroundColor Cyan
    
    $monitorData = @{}
    
    for ($i = 0; $i -lt $monitorPaths.Count; $i++) {
        $monitor = $monitorPaths[$i]
        $monitorData[$i] = $monitor
        $friendlyName = $friendlyNames[$i]
        
        # Truncate name if too long
        if ($friendlyName.Length -gt 35) {
            $friendlyName = $friendlyName.Substring(0, 32) + "..."
        }
        
        Write-Host (" {0,2} | {1}" -f $i, $friendlyName.PadRight(35))
    }
    
    Write-Host "----------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
    
    return $monitorData
}

# Main program loop
$continue = $true
while ($continue) {
    Show-Menu
    $choice = Read-Host "Select an option"
    
    switch ($choice) {
        "1" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Change All Monitor HWIDs" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            # Check if we have original values backed up
            $originalBackup = Load-OriginalMonitors
            if (-not $originalBackup) {
                Write-Host "WARNING: No original values have been saved!" -ForegroundColor Red
                Write-Host "It is HIGHLY RECOMMENDED to save current values first (Option 4)." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Do you want to continue anyway? (Y/N): " -NoNewline -ForegroundColor Yellow
                $continueAnyway = Read-Host
                if ($continueAnyway -ne "Y" -and $continueAnyway -ne "y") {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    Read-Host "Press Enter to continue"
                    continue
                }
            }
            
            # Get monitor registry paths
            $monitorPaths = Get-MonitorRegistryPaths
            
            if ($monitorPaths.Count -eq 0) {
                Write-Host "No monitor registry entries found." -ForegroundColor Red
                Read-Host "Press Enter to continue"
                continue
            }
            
            Write-Host "Found $($monitorPaths.Count) monitor registry entries." -ForegroundColor Cyan
            Write-Host ""
            
            # Show current monitor info
            Write-Host "Current Monitor Information:" -ForegroundColor Yellow
            $currentMonitors = Show-MonitorInfo
            
            # Generate new serial numbers
            Write-Host "Generating new random serial numbers..." -ForegroundColor Yellow
            $newSerials = @{}
            $attemptedChanges = @{}
            
            for ($i = 0; $i -lt $monitorPaths.Count; $i++) {
                $newSerial = "0x" + (New-RandomHexString -Length 8)
                $newSerials[$i] = $newSerial
                $attemptedChanges[$i] = @{
                    Index = $i
                    DisplayName = $monitorPaths[$i].DisplayName
                    NewSerial = $newSerial
                }
            }
            
            Write-Host ""
            Write-Host "New Serial Numbers to be applied:" -ForegroundColor Cyan
            foreach ($key in $newSerials.Keys) {
                Write-Host "$($monitorPaths[$key].DisplayName): $($newSerials[$key])" -ForegroundColor Magenta
            }
            Write-Host ""
            
            # Final confirmation
            Write-Host "WARNING: This will permanently change your monitor HWIDs!" -ForegroundColor Red
            Write-Host "Make sure you have saved the original values first." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Do you want to proceed with these changes? (Y/N): " -NoNewline -ForegroundColor Red
            $confirm = Read-Host
            
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                Write-Host ""
                Write-Host "Applying changes..." -ForegroundColor Cyan
                Write-Host "====================================" -ForegroundColor Cyan
                
                $successful = 0
                $failed = 0
                $failedChanges = @{}
                
                # Change each monitor HWID
                foreach ($key in $newSerials.Keys) {
                    $monitor = $monitorPaths[$key]
                    Write-Host "Processing: $($monitor.DisplayName)" -ForegroundColor Yellow
                    
                    # Get current EDID
                    $currentEDID = Get-EdidData -RegistryPath $monitor.Path
                    
                    if ($null -eq $currentEDID) {
                        Write-Host "  No EDID data found. Skipping..." -ForegroundColor Yellow
                        $failed++
                        $failedChanges[$key] = $attemptedChanges[$key]
                        continue
                    }
                    
                    # Modify EDID
                    $result = Update-EdidData -OriginalEdid $currentEDID
                    
                    if ($null -eq $result) {
                        Write-Host "  Failed to modify EDID data. Skipping..." -ForegroundColor Red
                        $failed++
                        $failedChanges[$key] = $attemptedChanges[$key]
                        continue
                    }
                    
                    Write-Host "  Old Serial: $($result.OldSerial)" -ForegroundColor Gray
                    Write-Host "  New Serial: $($result.NewSerial)" -ForegroundColor Green
                    
                    # Update EDID
                    if (Set-MonitorEdid -RegistryPath $monitor.Path -NewEdid $result.EdidData -DisplayName $monitor.DisplayName) {
                        $successful++
                    } else {
                        $failed++
                        $failedChanges[$key] = $attemptedChanges[$key]
                    }
                    
                    Write-Host ""
                }
                
                Write-Host "Monitor HWID changes complete!" -ForegroundColor Cyan
                Write-Host "Success: $successful, Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
                
                if ($failed -gt 0) {
                    Write-Host ""
                    Write-Host "Some monitor HWIDs failed to change. Attempting to save backup and attempted changes." -ForegroundColor Yellow
                    
                    # Save current values as backup
                    $currentValues = @()
                    foreach ($monitor in $monitorPaths) {
                        $currentValues += @{
                            Path = $monitor.Path
                            DisplayName = $monitor.DisplayName
                        }
                    }
                    
                    if (Save-BackupMonitors -monitors $currentValues) {
                        Write-Host "Backup of current monitor data saved." -ForegroundColor Green
                    }
                    if (Save-AttemptedMonitors -changes $failedChanges) {
                        Write-Host "Attempted changes saved." -ForegroundColor Green
                    }
                }
                
                if ($successful -gt 0) {
                    Write-Host ""
                    Write-Host "==============================================================" -ForegroundColor Yellow
                    Write-Host " A SYSTEM RESTART IS REQUIRED for changes to take effect!  " -ForegroundColor Yellow
                    Write-Host " Please restart your computer when convenient.              " -ForegroundColor Yellow
                    Write-Host "==============================================================" -ForegroundColor Yellow
                }
            } else {
                Write-Host ""
                Write-Host "Operation cancelled. No changes were made." -ForegroundColor Yellow
            }
            
            Read-Host "Press Enter to continue"
        }
        "2" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Change Individual Monitor" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            # Get monitor registry paths
            $monitorPaths = Get-MonitorRegistryPaths
            
            if ($monitorPaths.Count -eq 0) {
                Write-Host "No monitor registry entries found." -ForegroundColor Red
                Read-Host "Press Enter to continue"
                continue
            }
            
            # Show monitor selection
            Write-Host "Available Monitors:" -ForegroundColor Yellow
            $monitorData = Show-MonitorRegistryEntries
            
            # Get user selection
            Write-Host "Enter the ID number of the monitor to change (0-$($monitorPaths.Count - 1)): " -NoNewline -ForegroundColor Yellow
            $selection = Read-Host
            
            if ($selection -match "^\d+$" -and [int]$selection -ge 0 -and [int]$selection -lt $monitorPaths.Count) {
                $selectedMonitor = $monitorPaths[[int]$selection]
                
                Write-Host ""
                Write-Host "Selected monitor: $($selectedMonitor.DisplayName)" -ForegroundColor Cyan
                
                # Get current EDID
                $currentEDID = Get-EdidData -RegistryPath $selectedMonitor.Path
                
                if ($null -eq $currentEDID) {
                    Write-Host "No EDID data found for this monitor." -ForegroundColor Red
                    Read-Host "Press Enter to continue"
                    continue
                }
                
                # Generate new serial number
                $newSerial = "0x" + (New-RandomHexString -Length 8)
                Write-Host "New Serial: $newSerial" -ForegroundColor Green
                
                Write-Host ""
                Write-Host "Do you want to change the HWID for $($selectedMonitor.DisplayName)? (Y/N): " -NoNewline -ForegroundColor Yellow
                $confirm = Read-Host
                
                if ($confirm -eq "Y" -or $confirm -eq "y") {
                    Write-Host ""
                    Write-Host "Changing monitor HWID..." -ForegroundColor Cyan
                    Write-Host "====================================" -ForegroundColor Cyan
                    
                    # Modify EDID
                    $result = Update-EdidData -OriginalEdid $currentEDID
                    
                    if ($null -eq $result) {
                        Write-Host "Failed to modify EDID data." -ForegroundColor Red
                    } else {
                        Write-Host "Old Serial: $($result.OldSerial)" -ForegroundColor Gray
                        Write-Host "New Serial: $($result.NewSerial)" -ForegroundColor Green
                        
                        # Update EDID
                        if (Set-MonitorEdid -RegistryPath $selectedMonitor.Path -NewEdid $result.EdidData -DisplayName $selectedMonitor.DisplayName) {
                            Write-Host ""
                            Write-Host "Monitor HWID change completed successfully!" -ForegroundColor Green
                            Write-Host ""
                            Write-Host "==============================================================" -ForegroundColor Yellow
                            Write-Host " A SYSTEM RESTART IS REQUIRED for changes to take effect!  " -ForegroundColor Yellow
                            Write-Host " Please restart your computer when convenient.              " -ForegroundColor Yellow
                            Write-Host "==============================================================" -ForegroundColor Yellow
                        } else {
                            Write-Host ""
                            Write-Host "Monitor HWID change failed." -ForegroundColor Red
                        }
                    }
                } else {
                    Write-Host ""
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                }
            } else {
                Write-Host ""
                Write-Host "Invalid selection. Please enter a valid monitor ID." -ForegroundColor Red
            }
            
            Read-Host "Press Enter to continue"
        }
        "3" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Current Monitor Information" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            $currentMonitors = Show-MonitorInfo
            
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "Monitor information reading complete!" -ForegroundColor Green
            Write-Host "====================================" -ForegroundColor Cyan
            
            Read-Host "Press Enter to continue"
        }
        "4" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Save Current Values as Original" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            Write-Host "Reading current monitor data..." -ForegroundColor Yellow
            $monitorPaths = Get-MonitorRegistryPaths
            
            if ($monitorPaths.Count -eq 0) {
                Write-Host "No monitor registry entries found." -ForegroundColor Red
                Read-Host "Press Enter to continue"
                continue
            }
            
            # Convert to saveable format
            $saveableMonitors = @()
            foreach ($monitor in $monitorPaths) {
                $currentEDID = Get-EdidData -RegistryPath $monitor.Path
                $saveableMonitors += @{
                    Path = $monitor.Path
                    DisplayName = $monitor.DisplayName
                    EDID = $currentEDID
                }
            }
            
            Write-Host ""
            Write-Host "Do you want to save these values as the original/backup values? (Y/N): " -NoNewline -ForegroundColor Yellow
            $confirm = Read-Host
            
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                if (Save-OriginalMonitors -monitors $saveableMonitors) {
                    Write-Host ""
                    Write-Host "Original values saved successfully!" -ForegroundColor Green
                    Write-Host "You can now safely change monitor HWIDs and restore these values later." -ForegroundColor Yellow
                }
            } else {
                Write-Host ""
                Write-Host "Operation cancelled." -ForegroundColor Yellow
            }
            
            Read-Host "Press Enter to continue"
        }
        "5" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Saved Original Values" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            $originalBackup = Load-OriginalMonitors
            $backupData = Load-BackupMonitors
            $attemptedData = Load-AttemptedMonitors
            
            if ($originalBackup) {
                Write-Host "Original Backup (Manual Save):" -ForegroundColor Cyan
                Write-Host "Backup Date: $($originalBackup.Timestamp)" -ForegroundColor Gray
                Write-Host ""
                
                foreach ($monitor in $originalBackup.Monitors) {
                    Write-Host "$($monitor.DisplayName): EDID data saved" -ForegroundColor Green
                }
                Write-Host ""
            }
            
            if ($backupData -and $attemptedData) {
                if ($originalBackup) {
                    Write-Host "====================================" -ForegroundColor Cyan
                    Write-Host ""
                }
                
                Write-Host "Failure Backup (Auto-Saved):" -ForegroundColor Cyan
                Write-Host "Backup Date: $($backupData.Timestamp)" -ForegroundColor Gray
                Write-Host ""
                
                foreach ($monitor in $backupData.Monitors) {
                    Write-Host "$($monitor.DisplayName): Registry path saved" -ForegroundColor Green
                }
                Write-Host ""
                
                Write-Host "Attempted Changes:" -ForegroundColor Yellow
                Write-Host "Attempt Date: $($attemptedData.Timestamp)" -ForegroundColor Gray
                Write-Host ""
                
                foreach ($key in $attemptedData.AttemptedChanges.PSObject.Properties.Name) {
                    $attempted = $attemptedData.AttemptedChanges.$key
                    Write-Host "$($attempted.DisplayName): $($attempted.NewSerial)" -ForegroundColor Magenta
                }
            }
            
            if (-not $originalBackup -and -not $backupData) {
                Write-Host "No original values have been saved yet." -ForegroundColor Yellow
                Write-Host "Use option 4 to save current values as original." -ForegroundColor Yellow
            }
            
            Read-Host "Press Enter to continue"
        }
        "6" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Restore Original Monitor HWIDs" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            # Load original values
            $originalBackup = Load-OriginalMonitors
            if (-not $originalBackup) {
                Write-Host "ERROR: No original values found!" -ForegroundColor Red
                Write-Host "No backup file exists. Cannot restore original values." -ForegroundColor Yellow
                Write-Host "Use option 4 to save current values as original first." -ForegroundColor Yellow
                Read-Host "Press Enter to continue"
                continue
            }
            
            Write-Host "Original Monitor Data (to restore):" -ForegroundColor Cyan
            Write-Host "Backup Date: $($originalBackup.Timestamp)" -ForegroundColor Gray
            Write-Host ""
            
            foreach ($monitor in $originalBackup.Monitors) {
                Write-Host "$($monitor.DisplayName): EDID data available" -ForegroundColor Green
            }
            Write-Host ""
            
            # Final confirmation
            Write-Host "Do you want to restore the original monitor HWIDs? (Y/N): " -NoNewline -ForegroundColor Yellow
            $confirm = Read-Host
            
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                Write-Host ""
                Write-Host "Restoring original monitor HWIDs..." -ForegroundColor Cyan
                Write-Host "====================================" -ForegroundColor Cyan
                
                $successful = 0
                $failed = 0
                
                # Restore each monitor HWID
                foreach ($monitor in $originalBackup.Monitors) {
                    if ($monitor.EDID) {
                        Write-Host "Restoring: $($monitor.DisplayName)" -ForegroundColor Yellow
                        
                        if (Set-MonitorEdid -RegistryPath $monitor.Path -NewEdid $monitor.EDID -DisplayName $monitor.DisplayName) {
                            $successful++
                        } else {
                            $failed++
                        }
                    } else {
                        Write-Host "WARNING: No EDID data for $($monitor.DisplayName)" -ForegroundColor Yellow
                        $failed++
                    }
                }
                
                Write-Host ""
                Write-Host "Monitor HWID restoration complete!" -ForegroundColor Cyan
                Write-Host "Success: $successful, Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
                
                if ($successful -gt 0) {
                    Write-Host ""
                    Write-Host "==============================================================" -ForegroundColor Yellow
                    Write-Host " A SYSTEM RESTART IS REQUIRED for changes to take effect!  " -ForegroundColor Yellow
                    Write-Host " Please restart your computer when convenient.              " -ForegroundColor Yellow
                    Write-Host "==============================================================" -ForegroundColor Yellow
                    
                    # Ask if user wants to remove backup
                    Write-Host ""
                    Write-Host "Do you want to remove the backup file now that values are restored? (Y/N): " -NoNewline -ForegroundColor Yellow
                    $removeBackup = Read-Host
                    if ($removeBackup -eq "Y" -or $removeBackup -eq "y") {
                        try {
                            Remove-Item $originalMonitorsCache -Force
                            Write-Host "Backup file removed successfully." -ForegroundColor Green
                        }
                        catch {
                            Write-Host "Error removing backup file: $_" -ForegroundColor Red
                        }
                    }
                }
            } else {
                Write-Host ""
                Write-Host "Operation cancelled. No changes were made." -ForegroundColor Yellow
            }
            
            Read-Host "Press Enter to continue"
        }
        "0" {
            $continue = $false
        }
        default {
            Write-Host "Invalid option. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} 