# PrivacyFirst System Cleaner
# Run as Administrator

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script requires Administrator privileges to work properly!" -ForegroundColor Red
    Write-Host "Please run the main Privacy First as Administrator." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to return to main menu..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    return
}

function Show-Progress {
    param (
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1
    )
    
    if ($PercentComplete -ge 0) {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    } else {
        # For older PowerShell versions, just show the activity without indeterminate
        Write-Progress -Activity $Activity -Status $Status -PercentComplete 0
    }
}

function Show-CleanerMenu {
    Clear-Host
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "                    PrivacyFirst System Cleaner                      " -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "This tool cleans various system traces and resets network settings"
    Write-Host "to help maintain privacy and resolve connectivity issues."
    Write-Host "=================================================================" -ForegroundColor Cyan
    
    Write-Host "`n[1] " -NoNewline -ForegroundColor Green
    Write-Host "Flush DNS Cache" -ForegroundColor White
    
    Write-Host "[2] " -NoNewline -ForegroundColor Yellow
    Write-Host "Reset TCP/IP Stack" -ForegroundColor White
    
    Write-Host "[3] " -NoNewline -ForegroundColor Yellow
    Write-Host "Reset Network Connection (Fix MAC privating)" -ForegroundColor White
    
    Write-Host "[4] " -NoNewline -ForegroundColor Yellow
    Write-Host "Unlink Xbox Account" -ForegroundColor White
    
    Write-Host "[5] " -NoNewline -ForegroundColor Yellow
    Write-Host "Unlink Discord Account" -ForegroundColor White
    
    Write-Host "[0] " -NoNewline -ForegroundColor Gray
    Write-Host "Return to Main Menu" -ForegroundColor White
    
    Write-Host "`n=================================================================" -ForegroundColor Cyan
}

function Clear-DNSCache {
    Write-Host "`nFlushing DNS Cache..." -ForegroundColor Cyan
    Show-Progress -Activity "Flushing DNS Cache" -Status "Clearing DNS resolver cache..."
    
    try {
        $result = ipconfig /flushdns 2>&1
        Write-Progress -Activity "Flushing DNS Cache" -Completed
        Write-Host "DNS Cache flushed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Progress -Activity "Flushing DNS Cache" -Completed
        Write-Host "Error flushing DNS cache: $_" -ForegroundColor Red
    }
}

function Reset-TCPStack {
    Write-Host "`nResetting TCP/IP Stack..." -ForegroundColor Cyan
    Show-Progress -Activity "Resetting TCP/IP Stack" -Status "Resetting network protocols..."
    
    try {
        # Step 1: Reset IP
        Show-Progress -Activity "Resetting TCP/IP Stack" -Status "Resetting IP configuration..." -PercentComplete 20
        netsh int ip reset | Out-Null
        
        # Step 2: Reset Winsock
        Show-Progress -Activity "Resetting TCP/IP Stack" -Status "Resetting Winsock catalog..." -PercentComplete 40
        netsh winsock reset | Out-Null
        
        # Step 3: Flush DNS
        Show-Progress -Activity "Resetting TCP/IP Stack" -Status "Flushing DNS cache..." -PercentComplete 60
        ipconfig /flushdns | Out-Null
        
        # Step 4: Release IP
        Show-Progress -Activity "Resetting TCP/IP Stack" -Status "Releasing current IP..." -PercentComplete 80
        ipconfig /release | Out-Null
        
        # Step 5: Renew IP
        Show-Progress -Activity "Resetting TCP/IP Stack" -Status "Renewing IP address..." -PercentComplete 100
        ipconfig /renew | Out-Null
        
        Write-Progress -Activity "Resetting TCP/IP Stack" -Completed
        Write-Host "TCP/IP Stack reset successfully!" -ForegroundColor Green
        Write-Host "NOTE: A system restart is recommended for these changes to take full effect." -ForegroundColor Yellow
    }
    catch {
        Write-Progress -Activity "Resetting TCP/IP Stack" -Completed
        Write-Host "Error resetting TCP/IP stack: $_" -ForegroundColor Red
    }
}

function Reset-NetworkConnection {
    Write-Host "`nResetting Network Connection (Fixing MAC privating Issues)..." -ForegroundColor Cyan
    Show-Progress -Activity "Resetting Network Connections" -Status "Scanning network adapters..."
    
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        $totalAdapters = $adapters.Count
        
        if ($totalAdapters -eq 0) {
            Write-Host "No active network adapters found." -ForegroundColor Yellow
            Write-Host "This is normal in some virtual environments or when no network is connected." -ForegroundColor Yellow
            Write-Host "Proceeding with network protocol reset only..." -ForegroundColor Cyan
        } else {
            Write-Host "Found $totalAdapters active network adapters" -ForegroundColor Yellow
            $currentAdapter = 0
            
            foreach ($adapter in $adapters) {
                $currentAdapter++
                $percentComplete = [math]::Round(($currentAdapter / $totalAdapters) * 100)
                
                Show-Progress -Activity "Resetting Network Connections" -Status "Resetting adapter: $($adapter.Name)" -PercentComplete $percentComplete
                Write-Host "Resetting adapter: $($adapter.Name)" -ForegroundColor Yellow
                
                Disable-NetAdapter -Name $adapter.Name -Confirm:$false
                Start-Sleep -Seconds 2
                Enable-NetAdapter -Name $adapter.Name -Confirm:$false
                Start-Sleep -Seconds 2
            }
        }
        
        Show-Progress -Activity "Resetting Network Connections" -Status "Resetting network protocols..."
        Write-Host "Resetting network protocols..." -ForegroundColor Yellow
        netsh int ip reset | Out-Null
        netsh winsock reset | Out-Null
        
        Write-Progress -Activity "Resetting Network Connections" -Completed
        Write-Host "Network connections reset successfully!" -ForegroundColor Green
        Write-Host "NOTE: If you previously privating your MAC address, you may need to reapply that change." -ForegroundColor Yellow
    }
    catch {
        Write-Progress -Activity "Resetting Network Connections" -Completed
        Write-Host "Error resetting network connections: $_" -ForegroundColor Red
    }
}

function Remove-XboxAccount {
    Write-Host "`nUnlinking Xbox Account..." -ForegroundColor Cyan
    Show-Progress -Activity "Unlinking Xbox Account" -Status "Scanning Xbox registry data..."
    
    try {
        $paths = @(
            "HKCU:\Software\Microsoft\XboxLive",
            "HKCU:\Software\Microsoft\Xbox"
        )
        
        $totalPaths = $paths.Count
        $currentPath = 0
        
        foreach ($path in $paths) {
            $currentPath++
            $percentComplete = [math]::Round(($currentPath / $totalPaths) * 50)
            
            if (Test-Path $path) {
                Show-Progress -Activity "Unlinking Xbox Account" -Status "Removing registry data: $path" -PercentComplete $percentComplete
                Write-Host "Removing Xbox data from: $path" -ForegroundColor Yellow
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        Show-Progress -Activity "Unlinking Xbox Account" -Status "Cleaning Xbox app data..."
        
        $xboxAppData = "$env:LOCALAPPDATA\Packages\Microsoft.XboxApp*"
        $xboxIdentityAppData = "$env:LOCALAPPDATA\Packages\Microsoft.XboxIdentityProvider*"
        
        if (Test-Path $xboxAppData) {
            Show-Progress -Activity "Unlinking Xbox Account" -Status "Cleaning Xbox app cache..." -PercentComplete 75
            Write-Host "Cleaning Xbox app data..." -ForegroundColor Yellow
            Get-ChildItem -Path $xboxAppData -Directory | ForEach-Object {
                Remove-Item -Path "$($_.FullName)\LocalCache" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$($_.FullName)\Settings" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        if (Test-Path $xboxIdentityAppData) {
            Show-Progress -Activity "Unlinking Xbox Account" -Status "Cleaning Xbox identity data..." -PercentComplete 90
            Write-Host "Cleaning Xbox identity provider data..." -ForegroundColor Yellow
            Get-ChildItem -Path $xboxIdentityAppData -Directory | ForEach-Object {
                Remove-Item -Path "$($_.FullName)\AC" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$($_.FullName)\LocalCache" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Progress -Activity "Unlinking Xbox Account" -Completed
        Write-Host "Xbox account unlinked successfully!" -ForegroundColor Green
        Write-Host "NOTE: You may need to sign in again with Xbox services. Your Microsoft account remains intact." -ForegroundColor Yellow
    }
    catch {
        Write-Progress -Activity "Unlinking Xbox Account" -Completed
        Write-Host "Error unlinking Xbox account: $_" -ForegroundColor Red
    }
}

function Remove-DiscordAccount {
    Write-Host "`nUnlinking Discord Account..." -ForegroundColor Cyan
    Show-Progress -Activity "Unlinking Discord Account" -Status "Scanning Discord data locations..."
    
    try {
        $discordPaths = @(
            "$env:APPDATA\Discord",
            "$env:LOCALAPPDATA\Discord"
        )
        
        $totalPaths = $discordPaths.Count
        $currentPath = 0
        
        foreach ($path in $discordPaths) {
            $currentPath++
            $percentComplete = [math]::Round(($currentPath / $totalPaths) * 100)
            
            if (Test-Path $path) {
                Show-Progress -Activity "Unlinking Discord Account" -Status "Cleaning Discord data: $path" -PercentComplete $percentComplete
                Write-Host "Cleaning Discord app data at: $path" -ForegroundColor Yellow
                Remove-Item -Path "$path\Local Storage" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$path\Cache" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$path\Code Cache" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$path\Session Storage" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Progress -Activity "Unlinking Discord Account" -Completed
        Write-Host "Discord account unlinked successfully!" -ForegroundColor Green
        Write-Host "NOTE: Discord will ask you to log in again the next time you launch it." -ForegroundColor Yellow
    }
    catch {
        Write-Progress -Activity "Unlinking Discord Account" -Completed
        Write-Host "Error unlinking Discord account: $_" -ForegroundColor Red
    }
}

function Start-PrivacyFirstCleaner {
    $continue = $true
    while ($continue) {
        Show-CleanerMenu
        
        $option = Read-Host "`nEnter your choice"
        
        switch ($option) {
            "1" { 
                Clear-DNSCache
                Read-Host "`nPress Enter to continue"
            }
            "2" { 
                Reset-TCPStack
                Read-Host "`nPress Enter to continue"
            }
            "3" { 
                Reset-NetworkConnection
                Read-Host "`nPress Enter to continue"
            }
            "4" { 
                Remove-XboxAccount
                Read-Host "`nPress Enter to continue"
            }
            "5" { 
                Remove-DiscordAccount
                Read-Host "`nPress Enter to continue"
            }
            "0" {
                Write-Host "`nReturning to main menu..." -ForegroundColor Cyan
                $continue = $false
                return
            }
            default {
                Write-Host "`nInvalid option. Please try again." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Start the cleaner
Start-PrivacyFirstCleaner
