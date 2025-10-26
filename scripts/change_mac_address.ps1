# PrivacyFirst MAC Address Changer
# Professional script to change, backup, and restore MAC addresses

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
$originalMacsCache = Join-Path $toolsDir "original_macs.json"
$backupMacsCache = Join-Path $toolsDir "backup_macs.json"
$attemptedMacsCache = Join-Path $toolsDir "attempted_macs.json"

# Function to generate random MAC address
function New-RandomMacAddress {
    # First byte must have second-least-significant bit set to 0 (locally administered bit)
    # and least-significant bit set to 0 (unicast bit)
    $firstByte = "02"
    
    # Generate 5 random bytes
    $randomBytes = 2..6 | ForEach-Object { "{0:X2}" -f (Get-Random -Minimum 0 -Maximum 255) }
    
    # Combine to form MAC address
    return "$firstByte-$($randomBytes -join '-')"
}

# Function to get all network adapters
function Get-NetworkAdapters {
    try {
        return Get-NetAdapter | Sort-Object Name
    }
    catch {
        Write-Host "Error getting network adapters: $_" -ForegroundColor Red
        return @()
    }
}

# Function to save original MAC addresses
function Save-OriginalMacs {
    param($macs)
    
    try {
        $macsWithTimestamp = @{
            MACAddresses = $macs
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $macsWithTimestamp | ConvertTo-Json -Depth 3 | Set-Content $originalMacsCache
        Write-Host "Original MAC addresses saved successfully!" -ForegroundColor Green
        Write-Host "Backup location: $originalMacsCache" -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "Error saving original MAC addresses: $_" -ForegroundColor Red
        return $false
    }
}

# Function to save backup MAC addresses (for failed changes)
function Save-BackupMacs {
    param($macs)
    
    try {
        $macsWithTimestamp = @{
            MACAddresses = $macs
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $macsWithTimestamp | ConvertTo-Json -Depth 3 | Set-Content $backupMacsCache
        return $true
    }
    catch {
        return $false
    }
}

# Function to save attempted MAC changes
function Save-AttemptedMacs {
    param($macs)
    
    try {
        $macsWithTimestamp = @{
            AttemptedMACs = $macs
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $macsWithTimestamp | ConvertTo-Json -Depth 3 | Set-Content $attemptedMacsCache
        return $true
    }
    catch {
        return $false
    }
}

# Function to load original MAC addresses
function Load-OriginalMacs {
    if (Test-Path $originalMacsCache) {
        try {
            $content = Get-Content $originalMacsCache -Raw | ConvertFrom-Json
            return $content
        }
        catch {
            Write-Host "Error reading original MACs cache: $_" -ForegroundColor Red
            return $null
        }
    }
    return $null
}

# Function to load backup MAC addresses
function Load-BackupMacs {
    if (Test-Path $backupMacsCache) {
        try {
            $content = Get-Content $backupMacsCache -Raw | ConvertFrom-Json
            return $content
        }
        catch {
            return $null
        }
    }
    return $null
}

# Function to load attempted MAC changes
function Load-AttemptedMacs {
    if (Test-Path $attemptedMacsCache) {
        try {
            $content = Get-Content $attemptedMacsCache -Raw | ConvertFrom-Json
            return $content
        }
        catch {
            return $null
        }
    }
    return $null
}

# Function to set MAC address
function Set-MacAddress {
    param($adapter, $newMacAddress)
    
    try {
        $oldMacAddress = $adapter.MacAddress
        $adapterName = $adapter.Name
        $adapterStatus = $adapter.Status
        
        Write-Host "Setting MAC address for $adapterName..." -ForegroundColor Yellow
        
        # Check adapter type for better handling
        $isVirtual = $adapterName -match "OpenVPN|TAP|Wintun|Virtual|VMware|Hyper-V|Loopback"
        $isWiFi = $adapterName -match "Wi-Fi|Wireless|802\.11|WLAN"
        
        if ($isVirtual) {
            Write-Host "WARNING: $adapterName appears to be a virtual adapter." -ForegroundColor Yellow
            Write-Host "Virtual adapters may not support MAC address changes." -ForegroundColor Yellow
        }
        
        if ($isWiFi) {
            Write-Host "INFO: $adapterName is a Wi-Fi adapter." -ForegroundColor Cyan
            Write-Host "Wi-Fi adapters may have additional restrictions for MAC changes." -ForegroundColor Cyan
        }
        
        # Try multiple methods for Wi-Fi adapters
        $success = $false
        
        # Method 1: Standard Set-NetAdapter approach
        try {
            # Disable adapter if it's up
            if ($adapterStatus -eq "Up") {
                Write-Host "Disabling adapter $adapterName..." -ForegroundColor Gray
                Disable-NetAdapter -Name $adapterName -Confirm:$false
                Start-Sleep -Seconds 2
            }
            
            # Set MAC address
            Write-Host "Attempting to set MAC address..." -ForegroundColor Gray
            Set-NetAdapter -Name $adapterName -MacAddress $newMacAddress.Replace("-", "") -Confirm:$false
            Start-Sleep -Seconds 2
            
            # Enable adapter if it was up before
            if ($adapterStatus -eq "Up") {
                Write-Host "Re-enabling adapter $adapterName..." -ForegroundColor Gray
                Enable-NetAdapter -Name $adapterName -Confirm:$false
                Start-Sleep -Seconds 3
            }
            
            $success = $true
        }
        catch {
            Write-Host "Method 1 failed: $($_.Exception.Message)" -ForegroundColor Yellow
            
            # Method 2: Try with registry modification for Wi-Fi
            if ($isWiFi) {
                try {
                    Write-Host "Trying alternative method for Wi-Fi adapter..." -ForegroundColor Yellow
                    
                    # Get adapter registry path
                    $adapterKey = Get-NetAdapter -Name $adapterName | Get-NetAdapterAdvancedProperty | Where-Object { $_.DisplayName -eq "Network Address" }
                    if ($adapterKey) {
                        $regPath = $adapterKey.RegistryKeyword
                        $regValue = $newMacAddress.Replace("-", "")
                        
                        # Set registry value
                        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\*" -Name $regPath -Value $regValue -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                        
                        # Disable and re-enable adapter
                        if ($adapterStatus -eq "Up") {
                            Disable-NetAdapter -Name $adapterName -Confirm:$false
                            Start-Sleep -Seconds 2
                            Enable-NetAdapter -Name $adapterName -Confirm:$false
                            Start-Sleep -Seconds 3
                        }
                        
                        $success = $true
                    }
                }
                catch {
                    Write-Host "Method 2 also failed: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
        
        # Verify the change
        Start-Sleep -Seconds 3  # Give more time for changes to take effect
        $updatedAdapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
        
        if ($updatedAdapter) {
            $actualMac = $updatedAdapter.MacAddress
            $expectedMac = $newMacAddress.Replace("-", "")
            
            # Normalize both MAC addresses for comparison (remove any formatting)
            $normalizedExpected = $expectedMac -replace '[^0-9A-Fa-f]', ''
            $normalizedActual = $actualMac -replace '[^0-9A-Fa-f]', ''
            
            if ($normalizedExpected -eq $normalizedActual) {
                Write-Host "SUCCESS: MAC address changed for $adapterName" -ForegroundColor Green
                Write-Host "  From: $oldMacAddress" -ForegroundColor Gray
                Write-Host "  To:   $newMacAddress" -ForegroundColor Gray
                return $true
            } else {
                # For virtual adapters, be more lenient
                if ($isVirtual) {
                    Write-Host "PARTIAL: MAC address may have changed for $adapterName (virtual adapter)" -ForegroundColor Yellow
                    Write-Host "  Expected: $newMacAddress" -ForegroundColor Gray
                    Write-Host "  Actual:   $actualMac" -ForegroundColor Gray
                    Write-Host "  Note: Virtual adapters may not fully support MAC changes" -ForegroundColor Gray
                    return $true  # Consider it successful for virtual adapters
                } else {
                    Write-Host "FAILED: MAC address verification failed for $adapterName" -ForegroundColor Red
                    Write-Host "  Expected: $newMacAddress" -ForegroundColor Gray
                    Write-Host "  Actual:   $actualMac" -ForegroundColor Gray
                    
                    # Provide additional information for Wi-Fi adapters
                    if ($isWiFi) {
                        Write-Host ""
                        Write-Host "Wi-Fi MAC address change failed. This is common for many Wi-Fi adapters." -ForegroundColor Yellow
                        Write-Host "Possible reasons:" -ForegroundColor Yellow
                        Write-Host "  - Driver restrictions" -ForegroundColor Gray
                        Write-Host "  - Hardware limitations" -ForegroundColor Gray
                        Write-Host "  - Manufacturer restrictions" -ForegroundColor Gray
                        Write-Host ""
                        Write-Host "Recommendation: Use the Ethernet adapter for MAC privating instead." -ForegroundColor Cyan
                        Write-Host "Most Ethernet adapters support MAC address changes more reliably." -ForegroundColor Cyan
                    }
                    
                    return $false
                }
            }
        } else {
            Write-Host "WARNING: Could not verify MAC address change for $adapterName" -ForegroundColor Yellow
            return $true  # Assume success if we can't verify
        }
    }
    catch {
        Write-Host "ERROR: Failed to change MAC address for $($adapter.Name) - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to show menu
function Show-Menu {
    Clear-Host
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "    PrivacyFirst MAC Address Changer" -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Change All MAC Addresses" -ForegroundColor Green
    Write-Host "2. Change Individual Adapter" -ForegroundColor Green
    Write-Host "3. View Current MAC Addresses" -ForegroundColor Yellow
    Write-Host "4. Save Current Values as Original" -ForegroundColor Yellow
    Write-Host "5. View Saved Original Values" -ForegroundColor Yellow
    Write-Host "6. Restore Original MAC Addresses" -ForegroundColor Green
    Write-Host "0. Exit" -ForegroundColor Red
    Write-Host ""
}

# Function to display MAC addresses
function Show-MacAddresses {
    Write-Host "Reading MAC Addresses..." -ForegroundColor Yellow
    Write-Host ""
    
    # Check if there are backup files indicating previous failures
    $backupData = Load-BackupMacs
    $attemptedData = Load-AttemptedMacs
    
    $adapters = Get-NetworkAdapters
    if ($adapters.Count -eq 0) {
        Write-Host "No network adapters found on this system." -ForegroundColor Red
        return @{}
    }
    
    Write-Host "Network Adapters:" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------------" -ForegroundColor Cyan
    Write-Host " ID | Adapter Name                | Status | MAC Address   " -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------------" -ForegroundColor Cyan
    
    $adapterData = @{}
    
    for ($i = 0; $i -lt $adapters.Count; $i++) {
        $adapter = $adapters[$i]
        $status = $adapter.Status
        $statusColor = if ($status -eq "Up") { "Green" } else { "Yellow" }
        $macAddress = $adapter.MacAddress
        
        # If we have attempted changes and the current value matches the backup, show attempted value
        if ($backupData -and $attemptedData) {
            $backupMac = $backupData.MACAddresses | Where-Object { $_.Name -eq $adapter.Name }
            $attemptedMac = $attemptedData.AttemptedMACs | Where-Object { $_.Name -eq $adapter.Name }
            if ($backupMac -and $attemptedMac -and $macAddress -eq $backupMac.MacAddress) {
                $macAddress = $attemptedMac.NewMacAddress
            }
        }
        
        $adapterData[$i] = @{
            Name = $adapter.Name
            Status = $status
            MacAddress = $macAddress
            OriginalAdapter = $adapter
        }
        
        Write-Host (" {0,2} | {1,-25} | " -f $i, $adapter.Name) -NoNewline
        Write-Host ("{0,-6}" -f $status) -ForegroundColor $statusColor -NoNewline
        Write-Host (" | {0}" -f $macAddress)
    }
    
    Write-Host "-----------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
    
    return $adapterData
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
            Write-Host "    Change All MAC Addresses" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            # Check if we have original values backed up
            $originalBackup = Load-OriginalMacs
            if (-not $originalBackup) {
                Write-Host "WARNING: No original values have been saved!" -ForegroundColor Red
                Write-Host "It is HIGHLY RECOMMENDED to save current values first (Option 3)." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Do you want to continue anyway? (Y/N): " -NoNewline -ForegroundColor Yellow
                $continueAnyway = Read-Host
                if ($continueAnyway -ne "Y" -and $continueAnyway -ne "y") {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    Read-Host "Press Enter to continue"
                    continue
                }
            }
            
            # Show current values
            Write-Host "Current MAC Addresses:" -ForegroundColor Yellow
            $currentMacs = Show-MacAddresses
            
            if ($currentMacs.Count -eq 0) {
                Read-Host "Press Enter to continue"
                continue
            }
            
            # Generate new MAC addresses
            Write-Host "Generating new random MAC addresses..." -ForegroundColor Yellow
            $newMacs = @{}
            $attemptedChanges = @{}
            
            foreach ($key in $currentMacs.Keys) {
                $adapter = $currentMacs[$key]
                $newMac = New-RandomMacAddress
                $newMacs[$key] = $newMac
                $attemptedChanges[$adapter.Name] = @{
                    Name = $adapter.Name
                    OldMacAddress = $adapter.MacAddress
                    NewMacAddress = $newMac
                }
            }
            
            Write-Host ""
            Write-Host "New MAC Addresses to be applied:" -ForegroundColor Cyan
            foreach ($key in $newMacs.Keys) {
                $adapter = $currentMacs[$key]
                Write-Host "$($adapter.Name): $($newMacs[$key])" -ForegroundColor Magenta
            }
            Write-Host ""
            
            # Final confirmation
            Write-Host "WARNING: This will permanently change your MAC addresses!" -ForegroundColor Red
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
                
                # Change each MAC address
                foreach ($key in $newMacs.Keys) {
                    $adapter = $currentMacs[$key].OriginalAdapter
                    $newMac = $newMacs[$key]
                    
                    if (Set-MacAddress -adapter $adapter -newMacAddress $newMac) {
                        $successful++
                    } else {
                        $failed++
                        $failedChanges[$adapter.Name] = $attemptedChanges[$adapter.Name]
                    }
                }
                
                Write-Host ""
                Write-Host "MAC address changes complete!" -ForegroundColor Cyan
                Write-Host "Success: $successful, Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
                
                if ($failed -gt 0) {
                    Write-Host ""
                    Write-Host "Some MAC addresses failed to change. Attempting to save backup and attempted changes." -ForegroundColor Yellow
                    
                    # Save current values as backup
                    $currentValues = @()
                    foreach ($key in $currentMacs.Keys) {
                        $adapter = $currentMacs[$key]
                        $currentValues += @{
                            Name = $adapter.Name
                            MacAddress = $adapter.OriginalAdapter.MacAddress
                            Status = $adapter.Status
                        }
                    }
                    
                    if (Save-BackupMacs -macs $currentValues) {
                        Write-Host "Backup of current MAC addresses saved." -ForegroundColor Green
                    }
                    if (Save-AttemptedMacs -macs $failedChanges) {
                        Write-Host "Attempted changes saved." -ForegroundColor Green
                    }
                }
                
                if ($successful -gt 0) {
                    Write-Host ""
                    Write-Host "A network restart may be required for changes to fully take effect." -ForegroundColor Yellow
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
            Write-Host "    Change Individual Adapter" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            # Show current MAC addresses
            Write-Host "Current MAC Addresses:" -ForegroundColor Yellow
            $currentMacs = Show-MacAddresses
            
            if ($currentMacs.Count -eq 0) {
                Read-Host "Press Enter to continue"
                continue
            }
            
            # Get user selection
            Write-Host ""
            Write-Host "Enter the ID number of the adapter to change (0-$($currentMacs.Count - 1)): " -NoNewline -ForegroundColor Yellow
            $selection = Read-Host
            
            if ($selection -match "^\d+$" -and [int]$selection -ge 0 -and [int]$selection -lt $currentMacs.Count) {
                $selectedAdapter = $currentMacs[[int]$selection]
                $adapter = $selectedAdapter.OriginalAdapter
                
                Write-Host ""
                Write-Host "Selected adapter: $($adapter.Name)" -ForegroundColor Cyan
                Write-Host "Current MAC: $($adapter.MacAddress)" -ForegroundColor Yellow
                Write-Host "Status: $($adapter.Status)" -ForegroundColor Yellow
                
                # Generate new MAC address
                $newMacAddress = New-RandomMacAddress
                Write-Host "New MAC: $newMacAddress" -ForegroundColor Green
                
                Write-Host ""
                Write-Host "Do you want to change the MAC address for $($adapter.Name)? (Y/N): " -NoNewline -ForegroundColor Yellow
                $confirm = Read-Host
                
                if ($confirm -eq "Y" -or $confirm -eq "y") {
                    Write-Host ""
                    Write-Host "Changing MAC address..." -ForegroundColor Cyan
                    Write-Host "====================================" -ForegroundColor Cyan
                    
                    if (Set-MacAddress -adapter $adapter -newMacAddress $newMacAddress) {
                        Write-Host ""
                        Write-Host "MAC address change completed successfully!" -ForegroundColor Green
                    } else {
                        Write-Host ""
                        Write-Host "MAC address change failed." -ForegroundColor Red
                    }
                } else {
                    Write-Host ""
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                }
            } else {
                Write-Host ""
                Write-Host "Invalid selection. Please enter a valid adapter ID." -ForegroundColor Red
            }
            
            Read-Host "Press Enter to continue"
        }
        "3" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Current MAC Addresses" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            $currentMacs = Show-MacAddresses
            
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "MAC address reading complete!" -ForegroundColor Green
            Write-Host "====================================" -ForegroundColor Cyan
            
            Read-Host "Press Enter to continue"
        }
                "4" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Save Current Values as Original" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            Write-Host "Reading current MAC addresses..." -ForegroundColor Yellow
            $currentMacs = Show-MacAddresses
            
            if ($currentMacs.Count -eq 0) {
                Read-Host "Press Enter to continue"
                continue
            }
            
            # Convert to saveable format
            $saveableMacs = @()
            foreach ($key in $currentMacs.Keys) {
                $adapter = $currentMacs[$key]
                $saveableMacs += @{
                    Name = $adapter.Name
                    MacAddress = $adapter.MacAddress
                    Status = $adapter.Status
                }
            }
            
            Write-Host ""
            Write-Host "Do you want to save these values as the original/backup values? (Y/N): " -NoNewline -ForegroundColor Yellow
            $confirm = Read-Host
            
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                if (Save-OriginalMacs -macs $saveableMacs) {
                    Write-Host ""
                    Write-Host "Original values saved successfully!" -ForegroundColor Green
                    Write-Host "You can now safely change MAC addresses and restore these values later." -ForegroundColor Yellow
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
            
            $originalBackup = Load-OriginalMacs
            $backupData = Load-BackupMacs
            $attemptedData = Load-AttemptedMacs
            
            if ($originalBackup) {
                Write-Host "Original Backup (Manual Save):" -ForegroundColor Cyan
                Write-Host "Backup Date: $($originalBackup.Timestamp)" -ForegroundColor Gray
                Write-Host ""
                
                foreach ($mac in $originalBackup.MACAddresses) {
                    Write-Host "$($mac.Name): $($mac.MacAddress)" -ForegroundColor Green
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
                
                foreach ($mac in $backupData.MACAddresses) {
                    Write-Host "$($mac.Name): $($mac.MacAddress)" -ForegroundColor Green
                }
                Write-Host ""
                
                Write-Host "Attempted Changes:" -ForegroundColor Yellow
                Write-Host "Attempt Date: $($attemptedData.Timestamp)" -ForegroundColor Gray
                Write-Host ""
                
                foreach ($key in $attemptedData.AttemptedMACs.PSObject.Properties.Name) {
                    $attempted = $attemptedData.AttemptedMACs.$key
                    Write-Host "$($attempted.Name): $($attempted.NewMacAddress)" -ForegroundColor Magenta
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
            Write-Host "    Restore Original MAC Addresses" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            # Load original values
            $originalBackup = Load-OriginalMacs
            if (-not $originalBackup) {
                Write-Host "ERROR: No original values found!" -ForegroundColor Red
                Write-Host "No backup file exists. Cannot restore original values." -ForegroundColor Yellow
                Write-Host "Use option 4 to save current values as original first." -ForegroundColor Yellow
                Read-Host "Press Enter to continue"
                continue
            }
            
            # Show current values
            Write-Host "Current MAC Addresses:" -ForegroundColor Yellow
            $currentMacs = Show-MacAddresses
            
            Write-Host ""
            Write-Host "Original MAC Addresses (to restore):" -ForegroundColor Cyan
            Write-Host "Backup Date: $($originalBackup.Timestamp)" -ForegroundColor Gray
            Write-Host ""
            
            foreach ($mac in $originalBackup.MACAddresses) {
                Write-Host "$($mac.Name): $($mac.MacAddress)" -ForegroundColor Green
            }
            Write-Host ""
            
            # Check if already restored
            $alreadyRestored = $true
            foreach ($mac in $originalBackup.MACAddresses) {
                $currentMac = $currentMacs.Values | Where-Object { $_.Name -eq $mac.Name }
                if ($currentMac -and $currentMac.MacAddress -ne $mac.MacAddress) {
                    $alreadyRestored = $false
                    break
                }
            }
            
            if ($alreadyRestored) {
                Write-Host "MAC addresses are already set to their original values." -ForegroundColor Green
                Write-Host "Do you want to remove the backup file? (Y/N): " -NoNewline -ForegroundColor Yellow
                $removeBackup = Read-Host
                if ($removeBackup -eq "Y" -or $removeBackup -eq "y") {
                    try {
                        Remove-Item $originalMacsCache -Force
                        Write-Host "Backup file removed successfully." -ForegroundColor Green
                    }
                    catch {
                        Write-Host "Error removing backup file: $_" -ForegroundColor Red
                    }
                }
                Read-Host "Press Enter to continue"
                continue
            }
            
            # Final confirmation
            Write-Host "Do you want to restore the original MAC addresses? (Y/N): " -NoNewline -ForegroundColor Yellow
            $confirm = Read-Host
            
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                Write-Host ""
                Write-Host "Restoring original MAC addresses..." -ForegroundColor Cyan
                Write-Host "====================================" -ForegroundColor Cyan
                
                $successful = 0
                $failed = 0
                
                # Restore each MAC address
                foreach ($mac in $originalBackup.MACAddresses) {
                    $adapter = Get-NetAdapter -Name $mac.Name -ErrorAction SilentlyContinue
                    if ($adapter) {
                        if (Set-MacAddress -adapter $adapter -newMacAddress $mac.MacAddress) {
                            $successful++
                        } else {
                            $failed++
                        }
                    } else {
                        Write-Host "WARNING: Adapter '$($mac.Name)' not found." -ForegroundColor Yellow
                        $failed++
                    }
                }
                
                Write-Host ""
                Write-Host "MAC address restoration complete!" -ForegroundColor Cyan
                Write-Host "Success: $successful, Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
                
                if ($successful -gt 0) {
                    Write-Host ""
                    Write-Host "A network restart may be required for changes to fully take effect." -ForegroundColor Yellow
                    
                    # Ask if user wants to remove backup
                    Write-Host ""
                    Write-Host "Do you want to remove the backup file now that values are restored? (Y/N): " -NoNewline -ForegroundColor Yellow
                    $removeBackup = Read-Host
                    if ($removeBackup -eq "Y" -or $removeBackup -eq "y") {
                        try {
                            Remove-Item $originalMacsCache -Force
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