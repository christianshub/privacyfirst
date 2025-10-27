# Master test orchestrator for Proxmox testing
param(
    [string]$ProxmoxHost = "192.168.0.130",
    [string]$VMID = "102",
    [string]$SnapshotName = "baseline",
    [string]$VMIPAddress = "",  # Will prompt if not provided
    [string]$VMPassword = "",   # Will prompt if not provided
    [switch]$SkipBuild = $false,
    [switch]$SkipRollback = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=== PrivacyFirst Proxmox Test Orchestrator ===" -ForegroundColor Cyan
Write-Host "Proxmox Host: $ProxmoxHost" -ForegroundColor Gray
Write-Host "VM ID: $VMID" -ForegroundColor Gray
Write-Host "Snapshot: $SnapshotName" -ForegroundColor Gray
Write-Host ""

$startTime = Get-Date

# Step 1: Rollback VM to clean snapshot
if (-not $SkipRollback) {
    Write-Host "[1/7] Rolling back VM to snapshot '$SnapshotName'..." -ForegroundColor Yellow
    try {
        ssh root@$ProxmoxHost "qm rollback $VMID $SnapshotName" 2>&1 | Out-Null
        Write-Host "Rollback complete" -ForegroundColor Green
        Start-Sleep -Seconds 3
    }
    catch {
        Write-Host "Warning: Rollback failed or snapshot doesn't exist yet" -ForegroundColor Yellow
        Write-Host "Continuing anyway..." -ForegroundColor Gray
    }
}
else {
    Write-Host "[1/7] Skipping rollback (--SkipRollback specified)" -ForegroundColor Gray
}

# Step 2: Start VM
Write-Host "`n[2/7] Starting test VM..." -ForegroundColor Yellow
$vmStatus = ssh root@$ProxmoxHost "qm status $VMID" 2>$null | Select-String "status:" | ForEach-Object { $_ -replace ".*status:\s*", "" }

if ($vmStatus -ne "running") {
    ssh root@$ProxmoxHost "qm start $VMID" 2>&1 | Out-Null
    Write-Host "VM started, waiting for boot (60 seconds)..." -ForegroundColor Cyan
    Start-Sleep -Seconds 60
}
else {
    Write-Host "VM already running" -ForegroundColor Green
}

# Step 3: Build PrivacyFirst
if (-not $SkipBuild) {
    Write-Host "`n[3/7] Building PrivacyFirst..." -ForegroundColor Yellow
    Push-Location "c:\repos\privacyfirst"

    try {
        # Build C++ DLL
        Write-Host "Building C++ core..." -ForegroundColor Cyan
        & powershell.exe -ExecutionPolicy Bypass -File build.ps1 2>&1 | Out-Null

        # Build C# UI
        Write-Host "Building C# UI..." -ForegroundColor Cyan
        & dotnet build ui/PrivacyFirst.UI/PrivacyFirst.UI.csproj -c Release --nologo -v:quiet

        Write-Host "Build complete" -ForegroundColor Green
    }
    catch {
        Write-Host "Build failed: $($_.Exception.Message)" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host "[3/7] Skipping build (--SkipBuild specified)" -ForegroundColor Gray
}

# Step 4: Deploy to VM
Write-Host "`n[4/7] Deploying to test VM..." -ForegroundColor Yellow

$deployParams = @{
    ProxmoxHost = $ProxmoxHost
    ProxmoxVMID = $VMID
}

if (-not [string]::IsNullOrEmpty($VMIPAddress)) {
    $deployParams.VMHostname = $VMIPAddress
}

if (-not [string]::IsNullOrEmpty($VMPassword)) {
    $deployParams.VMPassword = $VMPassword
}

try {
    & ".\deploy_to_vm.ps1" @deployParams
}
catch {
    Write-Host "Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 5: Run tests on VM
Write-Host "`n[5/7] Running tests on VM..." -ForegroundColor Yellow
Write-Host "NOTE: Automated testing requires CLI interface (not yet implemented)" -ForegroundColor Yellow
Write-Host "Manual testing via RDP recommended for now" -ForegroundColor Cyan

if (-not [string]::IsNullOrEmpty($VMIPAddress)) {
    Write-Host "`nTo test manually:" -ForegroundColor Cyan
    Write-Host "  1. RDP to $VMIPAddress" -ForegroundColor White
    Write-Host "  2. Navigate to C:\PrivacyFirstTest\" -ForegroundColor White
    Write-Host "  3. Run PrivacyFirst.exe as Administrator" -ForegroundColor White
    Write-Host "  4. Test the Registry HWID operation" -ForegroundColor White
}

# Step 6: Results
Write-Host "`n[6/7] Test results..." -ForegroundColor Yellow
Write-Host "Manual verification required" -ForegroundColor Gray

# Step 7: Cleanup
Write-Host "`n[7/7] Test complete!" -ForegroundColor Green

$elapsed = (Get-Date) - $startTime
Write-Host "`nTotal time: $($elapsed.ToString('mm\:ss'))" -ForegroundColor Cyan

Write-Host "`n--- Next Steps ---" -ForegroundColor Yellow
Write-Host "1. Test the application manually on the VM" -ForegroundColor White
Write-Host "2. When done, rollback the VM with:" -ForegroundColor White
Write-Host "   ssh root@$ProxmoxHost 'qm shutdown $VMID && qm rollback $VMID $SnapshotName && qm start $VMID'" -ForegroundColor Gray
Write-Host ""
