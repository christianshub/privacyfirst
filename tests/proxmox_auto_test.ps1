# Fully automated test using Proxmox guest agent
param(
    [string]$ProxmoxHost = "192.168.0.130",
    [string]$ProxmoxPassword = "hellokityt123",
    [string]$VMID = "102",
    [string]$GitHubUser = "christianshub",
    [string]$RepoName = "privacyfirst"
)

Write-Host "=== PrivacyFirst Proxmox Automated Test ===" -ForegroundColor Cyan

# The PowerShell script that will run ON the VM
$vmTestScript = @'
$dest = 'C:\PrivacyFirstTest'
$url = 'https://raw.githubusercontent.com/christianshub/privacyfirst/main/x64/Release'

if (!(Test-Path $dest)) { mkdir $dest | Out-Null }

Write-Output "Downloading files..."
$files = @('PrivacyFirst.exe','PrivacyFirst.dll','PrivacyCore.dll','PrivacyFirst.deps.json','PrivacyFirst.runtimeconfig.json')
foreach ($f in $files) {
    try {
        Invoke-WebRequest "$url/$f" -OutFile "$dest\$f" -UseBasicParsing
        Write-Output "  OK: $f"
    } catch {
        Write-Output "  FAIL: $f - $($_.Exception.Message)"
    }
}

Write-Output "`nCapturing system state..."
$machineGuid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
$hwGuid = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001').HwProfileGuid

Write-Output "MachineGuid: $machineGuid"
Write-Output "HwProfileGuid: $hwGuid"
Write-Output "`nFiles ready at: $dest"
Write-Output "Test complete!"
'@

# Base64 encode the script to pass through SSH safely
$bytes = [System.Text.Encoding]::Unicode.GetBytes($vmTestScript)
$encodedScript = [Convert]::ToBase64String($bytes)

Write-Host "[1/4] Checking VM status..." -ForegroundColor Yellow
$status = ssh root@$ProxmoxHost "qm status $VMID" 2>$null | Select-String "status:" | ForEach-Object { $_ -replace ".*status:\s*", "" }

if ($status -ne "running") {
    Write-Host "  Starting VM..." -ForegroundColor Cyan
    ssh root@$ProxmoxHost "qm start $VMID" | Out-Null
    Write-Host "  Waiting 60 seconds for boot..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
}
else {
    Write-Host "  VM is running" -ForegroundColor Green
}

Write-Host "`n[2/4] Executing test script on VM via Proxmox..." -ForegroundColor Yellow

# Execute PowerShell on the VM through Proxmox guest agent
$command = "qm guest exec $VMID -- powershell.exe -NoProfile -EncodedCommand $encodedScript"

try {
    Write-Host "  Sending command to VM..." -ForegroundColor Gray
    $result = ssh root@$ProxmoxHost $command 2>&1

    if ($result -match "pid") {
        Write-Host "  Command sent successfully!" -ForegroundColor Green
        Write-Host "  Waiting for execution (10 seconds)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10

        # Try to get output
        Write-Host "`n[3/4] Retrieving results..." -ForegroundColor Yellow

        # Read the test results file from VM
        $outputCmd = "qm guest exec $VMID -- powershell.exe -Command ""Get-Content C:\PrivacyFirstTest\test_results.txt 2>&1"""
        $output = ssh root@$ProxmoxHost $outputCmd 2>&1

        Write-Host "`n[4/4] Test Results:" -ForegroundColor Cyan
        Write-Host $output -ForegroundColor White
    }
    else {
        Write-Host "  Failed to execute on VM" -ForegroundColor Red
        Write-Host "  Response: $result" -ForegroundColor Gray
    }
}
catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Alternative: Manual Execution ===" -ForegroundColor Yellow
Write-Host "If automated execution failed, run this on the VM:" -ForegroundColor Gray
Write-Host "  irm https://raw.githubusercontent.com/$GitHubUser/$RepoName/main/download_and_run.ps1 | iex" -ForegroundColor White
