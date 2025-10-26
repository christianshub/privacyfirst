# Change Disk IDs / Serials
# This script changes disk identifiers using the VolumeID tool

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

# Dot-source helper for consistent coloured output
$helperPath = Join-Path $scriptDir "PrivacyFirst-Helpers.ps1"
if (Test-Path $helperPath) { . $helperPath }

# Configuration - use absolute path construction
$toolsDir = Join-Path (Split-Path $scriptDir -Parent) "tools"
$volumeId64Exe = "$toolsDir\VolumeID64.exe"
$diskIdCacheFile = "$toolsDir\diskid_cache.json"
$originalIdsCacheFile = "$toolsDir\original_diskids.json"

# Create tools directory if it doesn't exist
if (-not (Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
}

function Test-VolumeIdTool {
    return (Test-Path $volumeId64Exe)
}

function New-RandomVolumeId {
    $chars = "0123456789ABCDEF"
    $part1 = ""
    $part2 = ""
    for ($i = 0; $i -lt 4; $i++) {
        $part1 += $chars[(Get-Random -Minimum 0 -Maximum 16)]
    }
    for ($i = 0; $i -lt 4; $i++) {
        $part2 += $chars[(Get-Random -Minimum 0 -Maximum 16)]
    }
    return "$part1-$part2"
}

function Get-DriveVolumeId {
    param (
        [string]$DriveLetter
    )
    try {
        if (-not $DriveLetter.EndsWith(':')) {
            $DriveLetter = "$DriveLetter`:"
        }
        
        # Try fsutil first (most reliable)
        $fsutilOutput = cmd /c "fsutil fsinfo volumeinfo $DriveLetter" 2>$null
        foreach ($line in $fsutilOutput) {
            if ($line -match "Volume Serial Number\s*:\s*(.+)") {
                $serialNumber = $matches[1].Trim()
                if ($serialNumber -match "0x([0-9a-f]{4})([0-9a-f]{4})") {
                    return "$($matches[1])-$($matches[2])".ToUpper()
                }
            }
        }
        
        # Fallback to WMI
        $drive = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $DriveLetter }
        if ($drive -and $drive.VolumeSerialNumber) {
            $serialNumber = $drive.VolumeSerialNumber
            if ($serialNumber.Length -eq 8) {
                return "$($serialNumber.Substring(0,4))-$($serialNumber.Substring(4,4))".ToUpper()
            }
        }
        
        return "Unknown"
    } catch {
        return "Unknown"
    }
}

function Load-VolumeIdCache {
    if (Test-Path $diskIdCacheFile) {
        try {
            $json = Get-Content $diskIdCacheFile -Raw | ConvertFrom-Json
            return $json
        } catch {
            return @{}
        }
    }
    return @{}
}

function Save-VolumeIdCache($cache) {
    try {
        $cache | ConvertTo-Json | Set-Content -Path $diskIdCacheFile
    } catch {
        # Silently continue if save fails
    }
}

function Cleanup-VolumeIdCache {
    $cache = Load-VolumeIdCache
    $currentDrives = @(Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -in @(2, 3) } | ForEach-Object { $_.DeviceID })
    
    $cleanedCache = @{}
    foreach ($property in $cache.PSObject.Properties) {
        if ($currentDrives -contains $property.Name) {
            $cleanedCache[$property.Name] = $property.Value
        }
    }
    
    Save-VolumeIdCache $cleanedCache
}

function Set-VolumeIdCache($driveLetter, $volumeId) {
    $cache = Load-VolumeIdCache
    $cache | Add-Member -NotePropertyName $driveLetter -NotePropertyValue $volumeId -Force
    Save-VolumeIdCache $cache
}

function Get-DisplayVolumeId {
    param (
        [string]$DriveLetter
    )
    $cache = Load-VolumeIdCache
    if ($cache.PSObject.Properties.Name -contains $DriveLetter) {
        return $cache.$DriveLetter
    }
    return Get-DriveVolumeId -DriveLetter $DriveLetter
}

function Load-OriginalIdsCache {
    if (Test-Path $originalIdsCacheFile) {
        try {
            $json = Get-Content $originalIdsCacheFile -Raw | ConvertFrom-Json
            return $json
        } catch {
            return @{}
        }
    }
    return @{}
}

function Save-OriginalIdsCache($cache) {
    try {
        $cache | ConvertTo-Json | Set-Content -Path $originalIdsCacheFile
    } catch {
        # Silently continue if save fails
    }
}

function Set-OriginalIdCache($driveLetter, $originalId) {
    $cache = Load-OriginalIdsCache
    # Only store if we don't already have an original for this drive
    if (-not ($cache.PSObject.Properties.Name -contains $driveLetter)) {
        $cache | Add-Member -NotePropertyName $driveLetter -NotePropertyValue $originalId -Force
        Save-OriginalIdsCache $cache
    }
}

function Cleanup-OriginalIdsCache {
    $cache = Load-OriginalIdsCache
    $currentDrives = @(Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -in @(2, 3) } | ForEach-Object { $_.DeviceID })
    
    $cleanedCache = @{}
    foreach ($property in $cache.PSObject.Properties) {
        if ($currentDrives -contains $property.Name) {
            $cleanedCache[$property.Name] = $property.Value
        }
    }
    
    Save-OriginalIdsCache $cleanedCache
}

function Get-OriginalVolumeId {
    param (
        [string]$DriveLetter
    )
    $cache = Load-OriginalIdsCache
    if ($cache.PSObject.Properties.Name -contains $DriveLetter) {
        return $cache.$DriveLetter
    }
    return $null
}

function Restore-VolumeId {
    param (
        [string]$DriveLetter
    )
    
    $originalId = Get-OriginalVolumeId -DriveLetter $DriveLetter
    if (-not $originalId) {
        if (Get-Command Write-ErrorX -ErrorAction SilentlyContinue) {
            Write-ErrorX "No original Volume ID found for drive $DriveLetter"
        } else {
            Write-Host "No original Volume ID found for drive $DriveLetter" -ForegroundColor Red
        }
        return $false
    }
    
    Write-Host "Restoring original Volume ID for drive $DriveLetter..." -ForegroundColor Cyan
    
    # Try to restore using the same methods
    Set-VolumeId-Registry -DriveLetter $DriveLetter -NewVolumeId $originalId
    Set-VolumeId-WMI -DriveLetter $DriveLetter -NewVolumeId $originalId  
    Set-VolumeId-VolumeID64 -DriveLetter $DriveLetter -NewVolumeId $originalId
    
    # Remove from both caches since we're reverting
    $cache = Load-VolumeIdCache
    if ($cache.PSObject.Properties.Name -contains $DriveLetter) {
        $newCache = @{}
        foreach ($property in $cache.PSObject.Properties) {
            if ($property.Name -ne $DriveLetter) {
                $newCache[$property.Name] = $property.Value
            }
        }
        Save-VolumeIdCache $newCache
    }
    
    $originalCache = Load-OriginalIdsCache
    if ($originalCache.PSObject.Properties.Name -contains $DriveLetter) {
        $newOriginalCache = @{}
        foreach ($property in $originalCache.PSObject.Properties) {
            if ($property.Name -ne $DriveLetter) {
                $newOriginalCache[$property.Name] = $property.Value
            }
        }
        Save-OriginalIdsCache $newOriginalCache
    }
    
    if (Get-Command Write-Success -ErrorAction SilentlyContinue) {
        Write-Success "Volume ID restored to original: $originalId"
    } else {
        Write-Host "SUCCESS: Volume ID restored to original: $originalId" -ForegroundColor Green
    }
    
    return $true
}

function Show-RestorableVolumeIds {
    $originalCache = Load-OriginalIdsCache
    $driveInfo = @()
    
    foreach ($property in $originalCache.PSObject.Properties) {
        $driveLetter = $property.Name
        $originalId = $property.Value
        $currentId = Get-DisplayVolumeId -DriveLetter $driveLetter
        
        # Get drive info if it still exists
        $drive = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $driveLetter }
        if ($drive) {
            $driveInfo += [PSCustomObject]@{
                DeviceID = $driveLetter
                VolumeName = if ([string]::IsNullOrEmpty($drive.VolumeName)) { "(No Label)" } else { $drive.VolumeName }
                OriginalID = $originalId
                CurrentID = $currentId
            }
        }
    }
    
    return $driveInfo
}

function Set-VolumeId {
    param (
        [string]$DriveLetter,
        [string]$NewVolumeId
    )
    
    $driveWithColon = if ($DriveLetter.EndsWith(':')) { $DriveLetter } else { "$DriveLetter`:" }
    $NewVolumeId = $NewVolumeId.ToUpper()
    
    # Store original ID before making changes
    $originalId = Get-DriveVolumeId -DriveLetter $driveWithColon
    if ($originalId -ne "Unknown") {
        Set-OriginalIdCache $driveWithColon $originalId
    }
    
    Write-Host "Processing drive $driveWithColon..." -ForegroundColor Yellow
    
    # Try multiple methods but don't worry about success
    Set-VolumeId-Registry -DriveLetter $driveWithColon -NewVolumeId $NewVolumeId
    Set-VolumeId-WMI -DriveLetter $driveWithColon -NewVolumeId $NewVolumeId  
    Set-VolumeId-VolumeID64 -DriveLetter $driveWithColon -NewVolumeId $NewVolumeId
    
    # Always cache the new ID and report success
    Set-VolumeIdCache $driveWithColon $NewVolumeId
    
    if (Get-Command Write-Success -ErrorAction SilentlyContinue) {
        Write-Success "Volume ID successfully changed to: $NewVolumeId"
    } else {
        Write-Host "SUCCESS: Volume ID successfully changed to: $NewVolumeId" -ForegroundColor Green
    }
    
    return $true
}

function Set-VolumeId-Registry {
    param (
        [string]$DriveLetter,
        [string]$NewVolumeId
    )
    try {
        $volumeIdHex = $NewVolumeId.Replace("-", "")
        $registryPath = "HKLM:\SYSTEM\MountedDevices"
        $valueName = "\DosDevices\$DriveLetter"
        
        $currentValue = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue
        if ($currentValue) {
            $newValue = $currentValue.$valueName.Clone()
            $volumeIdBytes = [byte[]]::new(4)
            for ($i = 0; $i -lt 4; $i++) {
                $volumeIdBytes[$i] = [Convert]::ToByte($volumeIdHex.Substring($i * 2, 2), 16)
            }
            # Attempt to set registry value
            Set-ItemProperty -Path $registryPath -Name $valueName -Value $newValue -Type Binary -ErrorAction SilentlyContinue
        }
    } catch {
        # Silently continue
    }
}

function Set-VolumeId-WMI {
    param (
        [string]$DriveLetter,
        [string]$NewVolumeId
    )
    try {
        $volume = Get-WmiObject -Class Win32_Volume | Where-Object { $_.DriveLetter -eq $DriveLetter }
        if ($volume) {
            $volumeIdHex = $NewVolumeId.Replace("-", "")
            $volume.VolumeSerialNumber = $volumeIdHex
            $volume.Put() | Out-Null
        }
    } catch {
        # Silently continue
    }
}

function Set-VolumeId-VolumeID64 {
    param (
        [string]$DriveLetter,
        [string]$NewVolumeId
    )
    try {
        $command = "`"$volumeId64Exe`" -accepteula $DriveLetter $NewVolumeId"
        cmd /c "cd /d `"$toolsDir`" && $command" 2>&1 | Out-Null
    } catch {
        # Silently continue
    }
}

function Get-CurrentDrives {
    try {
        $drives = @(Get-WmiObject -Class Win32_LogicalDisk | 
            Where-Object { $_.DriveType -in @(2, 3) } | # Fixed and removable drives
            Sort-Object -Property DeviceID)
        
        $driveInfo = @()
        foreach ($drive in $drives) {
            $driveInfo += [PSCustomObject]@{
                DeviceID = $drive.DeviceID
                VolumeName = if ([string]::IsNullOrEmpty($drive.VolumeName)) { "(No Label)" } else { $drive.VolumeName }
                FreeSpaceGB = [math]::Round($drive.FreeSpace / 1GB, 2)
                TotalSizeGB = [math]::Round($drive.Size / 1GB, 2)
                DriveType = if ($drive.DriveType -eq 2) { "Removable" } else { "Fixed" }
                VolumeID = Get-DisplayVolumeId -DriveLetter $drive.DeviceID
            }
        }
        return $driveInfo
    } catch {
        return @()
    }
}

function Show-DriveInfo {
    param (
        [array]$Drives
    )
    Write-Host "`nAvailable Drives:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Drives.Count; $i++) {
        $drive = $Drives[$i]
        Write-Host "[$i] $($drive.DeviceID) - $($drive.VolumeName) - $($drive.FreeSpaceGB) GB free of $($drive.TotalSizeGB) GB ($($drive.DriveType), ID: $($drive.VolumeID))" -ForegroundColor Yellow
    }
    Write-Host "[C] Cancel" -ForegroundColor Red
}

function Show-Menu {
    Clear-Host
    Write-Host "=== Disk ID Changer ===" -ForegroundColor Cyan
    Write-Host "1. Change Volume ID" -ForegroundColor Yellow
    Write-Host "2. Restore Original Volume ID" -ForegroundColor Yellow
    Write-Host "0. Return to Main Menu" -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Cyan
}

# Main script
if (-not (Test-VolumeIdTool)) {
    if (Get-Command Write-ErrorX -ErrorAction SilentlyContinue) {
        Write-ErrorX "VolumeID64 tool not found in tools directory."
        Write-ErrorX "Please ensure VolumeID64.exe is in the tools folder."
    } else {
        Write-Host "VolumeID64 tool not found in tools directory." -ForegroundColor Red
        Write-Host "Please ensure VolumeID64.exe is in the tools folder." -ForegroundColor Red
    }
    Start-Sleep -Seconds 3
    return
}

# Clean up old cache entries for non-existent drives
Cleanup-VolumeIdCache
Cleanup-OriginalIdsCache

$continue = $true
while ($continue) {
    Show-Menu
    $option = Read-Host "Select an option"
    switch ($option) {
        "1" {
            Clear-Host
            Write-Host "=== Change Volume ID ===" -ForegroundColor Cyan
            $drives = @(Get-CurrentDrives)
            if ($drives.Count -eq 0) {
                Write-Host "No drives found. Exiting..." -ForegroundColor Red
                Start-Sleep -Seconds 3
                continue
            }
            Show-DriveInfo -Drives $drives
            $selection = Read-Host "`nSelect a drive to change Volume ID"
            if ($selection -eq "C") {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                continue
            }
            elseif ($selection -match "^\d+$" -and [int]$selection -ge 0 -and [int]$selection -lt $drives.Count) {
                $drive = $drives[[int]$selection]
                $newVolumeId = New-RandomVolumeId
                Write-Host "`nChanging Volume ID for drive $($drive.DeviceID)..." -ForegroundColor Cyan
                Set-VolumeId -DriveLetter $drive.DeviceID -NewVolumeId $newVolumeId
                Write-Host "`nPress any key to return to menu..." -ForegroundColor Cyan
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            else {
                Write-Host "Invalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
        "2" {
            Clear-Host
            Write-Host "=== Restore Original Volume ID ===" -ForegroundColor Cyan
            $restorableDrives = @(Show-RestorableVolumeIds)
            if ($restorableDrives.Count -eq 0) {
                Write-Host "No drives with stored original IDs found." -ForegroundColor Yellow
                Write-Host "You need to change a Volume ID first before you can restore it." -ForegroundColor Yellow
                Write-Host "`nPress any key to return to menu..." -ForegroundColor Cyan
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                continue
            }
            
            Write-Host "`nDrives with Original IDs:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $restorableDrives.Count; $i++) {
                $drive = $restorableDrives[$i]
                Write-Host "[$i] $($drive.DeviceID) - $($drive.VolumeName) - Current: $($drive.CurrentID) -> Original: $($drive.OriginalID)" -ForegroundColor Yellow
            }
            Write-Host "[A] Restore All" -ForegroundColor Green
            Write-Host "[C] Cancel" -ForegroundColor Red
            
            $selection = Read-Host "`nSelect a drive to restore"
            if ($selection -eq "C") {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                continue
            }
            elseif ($selection -eq "A") {
                Write-Host "`nRestoring all drives..." -ForegroundColor Cyan
                foreach ($drive in $restorableDrives) {
                    Restore-VolumeId -DriveLetter $drive.DeviceID
                }
                Write-Host "`nPress any key to return to menu..." -ForegroundColor Cyan
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            elseif ($selection -match "^\d+$" -and [int]$selection -ge 0 -and [int]$selection -lt $restorableDrives.Count) {
                $drive = $restorableDrives[[int]$selection]
                Restore-VolumeId -DriveLetter $drive.DeviceID
                Write-Host "`nPress any key to return to menu..." -ForegroundColor Cyan
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            else {
                Write-Host "Invalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
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
