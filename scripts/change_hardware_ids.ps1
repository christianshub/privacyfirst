# PrivacyFirst HWID Changer
# Script to read, change, and restore SMBIOS hardware identifiers

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
$amideExe = Join-Path $toolsDir "AMIDEWINx64.EXE"
$originalHwidsCache = Join-Path $toolsDir "original_hwids.json"
$backupHwidsCache = Join-Path $toolsDir "backup_hwids.json"
$attemptedChangesCache = Join-Path $toolsDir "attempted_changes.json"

# Check if AMIDE tool exists
if (-not (Test-Path $amideExe)) {
    Write-Host "ERROR: AMIDEWINx64.EXE not found at: $amideExe" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

# Function to get hardware ID
function Get-HardwareID {
    param([string]$Type)
    
    try {
        $output = & $amideExe "/$Type" 2>&1
        
        # Convert array to string if needed
        if ($output -is [array]) {
            $output = $output -join "`n"
        }
        
        $outputStr = $output.ToString().Trim()
        
        # Extract value from the last line that contains the result
        $lines = $outputStr -split "`n"
        foreach ($line in $lines) {
            if ($line -match 'Done\s+"([^"]+)"') {
                return $matches[1].Trim()
            }
        }
        
        return "No value found"
    }
    catch {
        return "Error: $_"
    }
}

# Function to generate random alphanumeric string
function Get-RandomAlphaNumeric {
    param([int]$Length)
    
    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $result = ""
    
    for ($i = 0; $i -lt $Length; $i++) {
        $result += $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)]
    }
    
    return $result
}

# Function to generate random hex string
function Get-RandomHexString {
    param([int]$Length)
    
    $chars = "0123456789ABCDEF"
    $result = ""
    
    for ($i = 0; $i -lt $Length; $i++) {
        $result += $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)]
    }
    
    return $result
}

# Function to set hardware ID
function Set-HardwareID {
    param([string]$Type, [string]$Value)
    
    try {
        Write-Host "Setting $Type to: $Value" -ForegroundColor Yellow
        $output = & $amideExe "/$Type" $Value 2>&1
        
        # Convert array to string if needed
        if ($output -is [array]) {
            $output = $output -join "`n"
        }
        
        $outputStr = $output.ToString().Trim()
        
        # Check for success indicators
        if ($outputStr -match "Successfully" -or $outputStr -match "complete" -or $outputStr -match "finish" -or $outputStr -match "done") {
            Write-Host "SUCCESS: $Type successfully changed" -ForegroundColor Green
            return $true
        } else {
            Write-Host "FAILED: Failed to change $Type" -ForegroundColor Red
            Write-Host "Output: $outputStr" -ForegroundColor Gray
            return $false
        }
    }
    catch {
        Write-Host "ERROR: Error changing $Type - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to convert UUID to correct format for AMIDE tool
function Convert-UUIDFormat {
    param([string]$UUID)
    
    # Remove 'h' suffix if present
    if ($UUID.EndsWith('h')) {
        $UUID = $UUID.Substring(0, $UUID.Length - 1)
    }
    
    # If it's 32 characters, take first 16
    if ($UUID.Length -eq 32) {
        $UUID = $UUID.Substring(0, 16)
    }
    
    # If it's longer than 16, truncate to 16
    if ($UUID.Length -gt 16) {
        $UUID = $UUID.Substring(0, 16)
    }
    
    # If it's shorter than 16, pad with zeros
    while ($UUID.Length -lt 16) {
        $UUID = $UUID + "0"
    }
    
    return $UUID
}

# Function to generate new hardware IDs
function Generate-NewHardwareIDs {
    $ids = @{}
    
    # Get current values to determine lengths
    $currentCS = Get-HardwareID -Type "CS"
    $currentSS = Get-HardwareID -Type "SS"
    
    # 1. CS (Chassis Serial) - Random uppercase alphanumeric with same length as original
    $csLength = $currentCS.Length
    if ($csLength -lt 4) { $csLength = 20 } # Default if unable to detect
    $ids["CS"] = Get-RandomAlphaNumeric -Length $csLength
    
    # 2. BS (Baseboard Serial) - 8 hex digits
    $ids["BS"] = Get-RandomHexString -Length 8
    
    # 3. PSN (Product Serial Number) - "MS-" + 4 uppercase alphanumeric
    $ids["PSN"] = "MS-" + (Get-RandomAlphaNumeric -Length 4)
    
    # 4. SS (System Serial) - Random uppercase alphanumeric with same length as original
    $ssLength = $currentSS.Length
    if ($ssLength -lt 4) { $ssLength = 20 } # Default if unable to detect
    $ids["SS"] = Get-RandomAlphaNumeric -Length $ssLength
    
    # 5. SU (UUID) - 16-character hex string (confirmed working format)
    $ids["SU"] = Get-RandomHexString -Length 16
    
    return $ids
}

# Function to save backup hardware IDs
function Save-BackupHwids {
    param($hwids)
    
    try {
        $hwidsWithTimestamp = @{
            HardwareIDs = $hwids
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $hwidsWithTimestamp | ConvertTo-Json -Depth 3 | Set-Content $backupHwidsCache
        return $true
    }
    catch {
        return $false
    }
}

# Function to save attempted changes
function Save-AttemptedChanges {
    param($changes)
    
    try {
        $changesWithTimestamp = @{
            AttemptedChanges = $changes
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $changesWithTimestamp | ConvertTo-Json -Depth 3 | Set-Content $attemptedChangesCache
        return $true
    }
    catch {
        return $false
    }
}

# Function to load backup hardware IDs
function Load-BackupHwids {
    if (Test-Path $backupHwidsCache) {
        try {
            $content = Get-Content $backupHwidsCache -Raw | ConvertFrom-Json
            return $content
        }
        catch {
            return $null
        }
    }
    return $null
}

# Function to load attempted changes
function Load-AttemptedChanges {
    if (Test-Path $attemptedChangesCache) {
        try {
            $content = Get-Content $attemptedChangesCache -Raw | ConvertFrom-Json
            return $content
        }
        catch {
            return $null
        }
    }
    return $null
}

# Function to save original hardware IDs
function Save-OriginalHwids {
    param($hwids)
    
    try {
        $hwidsWithTimestamp = @{
            HardwareIDs = $hwids
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $hwidsWithTimestamp | ConvertTo-Json -Depth 3 | Set-Content $originalHwidsCache
        Write-Host "Original hardware IDs saved successfully!" -ForegroundColor Green
        Write-Host "Backup location: $originalHwidsCache" -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "Error saving original hardware IDs: $_" -ForegroundColor Red
        return $false
    }
}

# Function to load original hardware IDs
function Load-OriginalHwids {
    if (Test-Path $originalHwidsCache) {
        try {
            $content = Get-Content $originalHwidsCache -Raw | ConvertFrom-Json
            return $content
        }
        catch {
            Write-Host "Error reading original HWIDs cache: $_" -ForegroundColor Red
            return $null
        }
    }
    return $null
}

# Function to show menu
function Show-Menu {
    Clear-Host
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "    PrivacyFirst HWID Changer" -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Change All Hardware IDs" -ForegroundColor Green
    Write-Host "2. View Current Hardware IDs" -ForegroundColor Yellow
    Write-Host "3. Save Current Values as Original" -ForegroundColor Yellow
    Write-Host "4. View Saved Original Values" -ForegroundColor Yellow
    Write-Host "5. Restore Original Hardware IDs" -ForegroundColor Green
    Write-Host "0. Exit" -ForegroundColor Red
    Write-Host ""
}

# Function to display hardware IDs
function Show-HardwareIDs {
    Write-Host "Reading Hardware IDs..." -ForegroundColor Yellow
    Write-Host ""

    # Check if there are backup files indicating previous failures
    $backupData = Load-BackupHwids
    $attemptedData = Load-AttemptedChanges
    
    $cs = Get-HardwareID -Type "CS"
    $bs = Get-HardwareID -Type "BS"
    $psn = Get-HardwareID -Type "PSN"
    $ss = Get-HardwareID -Type "SS"
    $su = Get-HardwareID -Type "SU"
    
    # If we have attempted changes and the current value matches the backup, show attempted value
    if ($backupData -and $attemptedData) {
        if ($cs -eq $backupData.HardwareIDs.CS -and $attemptedData.AttemptedChanges.CS) {
            $cs = $attemptedData.AttemptedChanges.CS
        }
        if ($bs -eq $backupData.HardwareIDs.BS -and $attemptedData.AttemptedChanges.BS) {
            $bs = $attemptedData.AttemptedChanges.BS
        }
        if ($psn -eq $backupData.HardwareIDs.PSN -and $attemptedData.AttemptedChanges.PSN) {
            $psn = $attemptedData.AttemptedChanges.PSN
        }
        if ($ss -eq $backupData.HardwareIDs.SS -and $attemptedData.AttemptedChanges.SS) {
            $ss = $attemptedData.AttemptedChanges.SS
        }
        if ($su -eq $backupData.HardwareIDs.SU -and $attemptedData.AttemptedChanges.SU) {
            $su = $attemptedData.AttemptedChanges.SU
        }
    }

    Write-Host "Chassis Serial (CS):" -ForegroundColor Green
    Write-Host $cs -ForegroundColor White
    Write-Host ""

    Write-Host "Baseboard Serial (BS):" -ForegroundColor Green
    Write-Host $bs -ForegroundColor White
    Write-Host ""

    Write-Host "Product Serial Number (PSN):" -ForegroundColor Green
    Write-Host $psn -ForegroundColor White
    Write-Host ""

    Write-Host "System Serial (SS):" -ForegroundColor Green
    Write-Host $ss -ForegroundColor White
    Write-Host ""

    Write-Host "System UUID (SU):" -ForegroundColor Green
    Write-Host $su -ForegroundColor White
    Write-Host ""

    return @{
        CS = $cs
        BS = $bs
        PSN = $psn
        SS = $ss
        SU = $su
    }
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
            Write-Host "    Change All Hardware IDs" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            # Check if we have original values backed up
            $originalBackup = Load-OriginalHwids
            if (-not $originalBackup) {
                Write-Host "WARNING: No original values have been saved!" -ForegroundColor Red
                Write-Host "It is HIGHLY RECOMMENDED to save current values first (Option 2)." -ForegroundColor Yellow
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
            Write-Host "Current Hardware IDs:" -ForegroundColor Yellow
            $currentHwids = Show-HardwareIDs
            
            # Generate new values
            Write-Host "Generating new random hardware IDs..." -ForegroundColor Yellow
            $newIds = Generate-NewHardwareIDs
            
            Write-Host ""
            Write-Host "New Hardware IDs to be applied:" -ForegroundColor Cyan
            Write-Host "Chassis Serial (CS): $($newIds['CS'])" -ForegroundColor Magenta
            Write-Host "Baseboard Serial (BS): $($newIds['BS'])" -ForegroundColor Magenta
            Write-Host "Product Serial Number (PSN): $($newIds['PSN'])" -ForegroundColor Magenta
            Write-Host "System Serial (SS): $($newIds['SS'])" -ForegroundColor Magenta
            Write-Host "System UUID (SU): $($newIds['SU'])" -ForegroundColor Magenta
            Write-Host ""
            
            # Final confirmation
            Write-Host "WARNING: This will permanently change your hardware IDs!" -ForegroundColor Red
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
                $attemptedChanges = @{}
                
                # Change each hardware ID
                if (Set-HardwareID -Type "CS" -Value $newIds['CS']) { $successful++ } else { $failed++; $attemptedChanges["CS"] = $newIds['CS'] }
                if (Set-HardwareID -Type "BS" -Value $newIds['BS']) { $successful++ } else { $failed++; $attemptedChanges["BS"] = $newIds['BS'] }
                if (Set-HardwareID -Type "PSN" -Value $newIds['PSN']) { $successful++ } else { $failed++; $attemptedChanges["PSN"] = $newIds['PSN'] }
                if (Set-HardwareID -Type "SS" -Value $newIds['SS']) { $successful++ } else { $failed++; $attemptedChanges["SS"] = $newIds['SS'] }
                if (Set-HardwareID -Type "SU" -Value $newIds['SU']) { $successful++ } else { $failed++; $attemptedChanges["SU"] = $newIds['SU'] }
                
                Write-Host ""
                Write-Host "Hardware ID changes complete!" -ForegroundColor Cyan
                Write-Host "Success: $successful, Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
                
                if ($failed -gt 0) {
                    Write-Host ""
                    Write-Host "Some hardware IDs failed to change. Attempting to save backup and attempted changes." -ForegroundColor Yellow
                    if (Save-BackupHwids -hwids $currentHwids) {
                        Write-Host "Backup of current hardware IDs saved to: $backupHwidsCache" -ForegroundColor Green
                    } else {
                        Write-Host "Failed to save current hardware IDs to backup: $_" -ForegroundColor Red
                    }
                    if (Save-AttemptedChanges -changes $attemptedChanges) {
                        Write-Host "Attempted changes saved to: $attemptedChangesCache" -ForegroundColor Green
                    } else {
                        Write-Host "Failed to save attempted changes: $_" -ForegroundColor Red
                    }
                }
                
                if ($successful -gt 0) {
                    Write-Host ""
                    Write-Host "A system restart is recommended for changes to fully take effect." -ForegroundColor Yellow
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
            Write-Host "    Current Hardware IDs" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            $currentHwids = Show-HardwareIDs
            
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "Hardware ID reading complete!" -ForegroundColor Green
            Write-Host "====================================" -ForegroundColor Cyan
            
            Read-Host "Press Enter to continue"
        }
        "3" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Save Current Values as Original" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            Write-Host "Reading current hardware IDs..." -ForegroundColor Yellow
            $currentHwids = Show-HardwareIDs
            
            Write-Host ""
            Write-Host "Do you want to save these values as the original/backup values? (Y/N): " -NoNewline -ForegroundColor Yellow
            $confirm = Read-Host
            
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                if (Save-OriginalHwids -hwids $currentHwids) {
                    Write-Host ""
                    Write-Host "Original values saved successfully!" -ForegroundColor Green
                    Write-Host "You can now safely change hardware IDs and restore these values later." -ForegroundColor Yellow
                }
            } else {
                Write-Host ""
                Write-Host "Operation cancelled." -ForegroundColor Yellow
            }
            
            Read-Host "Press Enter to continue"
        }
        "4" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Saved Original Values" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            $originalBackup = Load-OriginalHwids
            $backupData = Load-BackupHwids
            $attemptedData = Load-AttemptedChanges
            
            if ($originalBackup) {
                Write-Host "Original Backup (Manual Save):" -ForegroundColor Cyan
                Write-Host "Backup Date: $($originalBackup.Timestamp)" -ForegroundColor Gray
                Write-Host ""
                
                Write-Host "Original Chassis Serial (CS):" -ForegroundColor Green
                Write-Host $originalBackup.HardwareIDs.CS -ForegroundColor White
                Write-Host ""
                
                Write-Host "Original Baseboard Serial (BS):" -ForegroundColor Green
                Write-Host $originalBackup.HardwareIDs.BS -ForegroundColor White
                Write-Host ""
                
                Write-Host "Original Product Serial Number (PSN):" -ForegroundColor Green
                Write-Host $originalBackup.HardwareIDs.PSN -ForegroundColor White
                Write-Host ""
                
                Write-Host "Original System Serial (SS):" -ForegroundColor Green
                Write-Host $originalBackup.HardwareIDs.SS -ForegroundColor White
                Write-Host ""
                
                Write-Host "Original System UUID (SU):" -ForegroundColor Green
                Write-Host $originalBackup.HardwareIDs.SU -ForegroundColor White
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
                
                Write-Host "Backup Chassis Serial (CS):" -ForegroundColor Green
                Write-Host $backupData.HardwareIDs.CS -ForegroundColor White
                Write-Host ""
                
                Write-Host "Backup Baseboard Serial (BS):" -ForegroundColor Green
                Write-Host $backupData.HardwareIDs.BS -ForegroundColor White
                Write-Host ""
                
                Write-Host "Backup Product Serial Number (PSN):" -ForegroundColor Green
                Write-Host $backupData.HardwareIDs.PSN -ForegroundColor White
                Write-Host ""
                
                Write-Host "Backup System Serial (SS):" -ForegroundColor Green
                Write-Host $backupData.HardwareIDs.SS -ForegroundColor White
                Write-Host ""
                
                Write-Host "Backup System UUID (SU):" -ForegroundColor Green
                Write-Host $backupData.HardwareIDs.SU -ForegroundColor White
                Write-Host ""
                
                Write-Host "Attempted Changes:" -ForegroundColor Yellow
                Write-Host "Attempt Date: $($attemptedData.Timestamp)" -ForegroundColor Gray
                Write-Host ""
                
                foreach ($key in $attemptedData.AttemptedChanges.PSObject.Properties.Name) {
                    Write-Host "Attempted $key : $($attemptedData.AttemptedChanges.$key)" -ForegroundColor Magenta
                }
            }
            
            if (-not $originalBackup -and -not $backupData) {
                Write-Host "No original values have been saved yet." -ForegroundColor Yellow
                Write-Host "Use option 3 to save current values as original." -ForegroundColor Yellow
            }
            
            Read-Host "Press Enter to continue"
        }
        "5" {
            Clear-Host
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host "    Restore Original Hardware IDs" -ForegroundColor Cyan
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""
            
            # Load original values
            $originalBackup = Load-OriginalHwids
            if (-not $originalBackup) {
                Write-Host "ERROR: No original values found!" -ForegroundColor Red
                Write-Host "No backup file exists. Cannot restore original values." -ForegroundColor Yellow
                Write-Host "Use option 2 to save current values as original first." -ForegroundColor Yellow
                Read-Host "Press Enter to continue"
                continue
            }
            
            # Show current values
            Write-Host "Current Hardware IDs:" -ForegroundColor Yellow
            $currentHwids = Show-HardwareIDs
            
            Write-Host ""
            Write-Host "Original Hardware IDs (to restore):" -ForegroundColor Cyan
            Write-Host "Backup Date: $($originalBackup.Timestamp)" -ForegroundColor Gray
            Write-Host "Chassis Serial (CS): $($originalBackup.HardwareIDs.CS)" -ForegroundColor Green
            Write-Host "Baseboard Serial (BS): $($originalBackup.HardwareIDs.BS)" -ForegroundColor Green
            Write-Host "Product Serial Number (PSN): $($originalBackup.HardwareIDs.PSN)" -ForegroundColor Green
            Write-Host "System Serial (SS): $($originalBackup.HardwareIDs.SS)" -ForegroundColor Green
            Write-Host "System UUID (SU): $($originalBackup.HardwareIDs.SU)" -ForegroundColor Green
            Write-Host ""
            
            # Check if already restored
            $alreadyRestored = $true
            foreach ($key in $currentHwids.Keys) {
                if ($originalBackup.HardwareIDs.$key -ne $currentHwids[$key]) {
                    $alreadyRestored = $false
                    break
                }
            }
            
            if ($alreadyRestored) {
                Write-Host "Hardware IDs are already set to their original values." -ForegroundColor Green
                Write-Host "Do you want to remove the backup file? (Y/N): " -NoNewline -ForegroundColor Yellow
                $removeBackup = Read-Host
                if ($removeBackup -eq "Y" -or $removeBackup -eq "y") {
                    try {
                        Remove-Item $originalHwidsCache -Force
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
            Write-Host "Do you want to restore the original hardware IDs? (Y/N): " -NoNewline -ForegroundColor Yellow
            $confirm = Read-Host
            
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                Write-Host ""
                Write-Host "Restoring original hardware IDs..." -ForegroundColor Cyan
                Write-Host "====================================" -ForegroundColor Cyan
                
                $successful = 0
                $failed = 0
                
                # Restore each hardware ID
                if (Set-HardwareID -Type "CS" -Value $originalBackup.HardwareIDs.CS) { $successful++ } else { $failed++ }
                if (Set-HardwareID -Type "BS" -Value $originalBackup.HardwareIDs.BS) { $successful++ } else { $failed++ }
                if (Set-HardwareID -Type "PSN" -Value $originalBackup.HardwareIDs.PSN) { $successful++ } else { $failed++ }
                if (Set-HardwareID -Type "SS" -Value $originalBackup.HardwareIDs.SS) { $successful++ } else { $failed++ }
                if (Set-HardwareID -Type "SU" -Value (Convert-UUIDFormat $originalBackup.HardwareIDs.SU)) { $successful++ } else { $failed++ }
                
                Write-Host ""
                Write-Host "Hardware ID restoration complete!" -ForegroundColor Cyan
                Write-Host "Success: $successful, Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
                
                if ($successful -gt 0) {
                    Write-Host ""
                    Write-Host "A system restart is recommended for changes to fully take effect." -ForegroundColor Yellow
                    
                    # Ask if user wants to remove backup
                    Write-Host ""
                    Write-Host "Do you want to remove the backup file now that values are restored? (Y/N): " -NoNewline -ForegroundColor Yellow
                    $removeBackup = Read-Host
                    if ($removeBackup -eq "Y" -or $removeBackup -eq "y") {
                        try {
                            Remove-Item $originalHwidsCache -Force
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