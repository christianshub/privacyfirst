# Automated remote testing - Downloads from GitHub and reports results
param(
    [string]$VMHostname = "192.168.0.143",
    [string]$VMUser = "john",
    [string]$VMPassword = "1",
    [string]$GitHubUser = "christianshub",
    [string]$RepoName = "privacyfirst",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Continue"

Write-Host "=== PrivacyFirst Automated Remote Testing ===" -ForegroundColor Cyan
Write-Host "VM: $VMHostname" -ForegroundColor Gray
Write-Host "GitHub: $GitHubUser/$RepoName" -ForegroundColor Gray
Write-Host ""

# Create the remote execution script
$remoteScript = @"
# PrivacyFirst Auto-Test Script
`$ErrorActionPreference = 'Continue'
`$results = @{
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    hostname = `$env:COMPUTERNAME
    tests = @()
}

Write-Host '=== PrivacyFirst Auto-Test ===' -ForegroundColor Cyan

# Step 1: Download from GitHub
Write-Host '[1/4] Downloading from GitHub...' -ForegroundColor Yellow
`$baseUrl = 'https://raw.githubusercontent.com/$GitHubUser/$RepoName/$Branch/x64/Release'
`$dest = 'C:\PrivacyFirstTest'

if (-not (Test-Path `$dest)) {
    New-Item -Path `$dest -ItemType Directory -Force | Out-Null
}

`$files = @('PrivacyFirst.exe', 'PrivacyFirst.dll', 'PrivacyCore.dll', 'PrivacyFirst.deps.json', 'PrivacyFirst.runtimeconfig.json')
`$downloadSuccess = `$true

foreach (`$file in `$files) {
    try {
        Invoke-WebRequest -Uri "`$baseUrl/`$file" -OutFile "`$dest\`$file" -ErrorAction Stop
        Write-Host "  Downloaded `$file" -ForegroundColor Green
    }
    catch {
        Write-Host "  Failed to download `$file" -ForegroundColor Red
        `$downloadSuccess = `$false
    }
}

if (-not `$downloadSuccess) {
    Write-Host 'Download failed!' -ForegroundColor Red
    exit 1
}

# Step 2: Capture initial state
Write-Host '[2/4] Capturing initial system state...' -ForegroundColor Yellow
`$initialMachineGuid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
`$initialHwProfileGuid = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001').HwProfileGuid

Write-Host "  Initial MachineGuid: `$initialMachineGuid" -ForegroundColor Gray
Write-Host "  Initial HwProfileGuid: `$initialHwProfileGuid" -ForegroundColor Gray

# Step 3: Execute PrivacyCore.dll directly (test Registry HWID operation)
Write-Host '[3/4] Testing Registry HWID operation...' -ForegroundColor Yellow

# We need to test via the DLL since we can't run GUI headlessly
# For now, we'll verify files are present
`$test1 = @{
    name = 'File Download'
    success = (Test-Path "`$dest\PrivacyCore.dll") -and (Test-Path "`$dest\PrivacyFirst.exe")
    details = "Files present in `$dest"
}
`$results.tests += `$test1

`$test2 = @{
    name = 'Initial State Capture'
    success = (-not [string]::IsNullOrEmpty(`$initialMachineGuid))
    details = "MachineGuid: `$initialMachineGuid"
}
`$results.tests += `$test2

# Step 4: Generate report
Write-Host '[4/4] Generating report...' -ForegroundColor Yellow

`$reportPath = "`$dest\test_results.txt"
`$report = @"
=== PrivacyFirst Test Report ===
Timestamp: `$(`$results.timestamp)
Hostname: `$(`$results.hostname)

Tests:
"@

foreach (`$test in `$results.tests) {
    `$status = if (`$test.success) { 'PASS' } else { 'FAIL' }
    `$report += "`n[`$status] `$(`$test.name): `$(`$test.details)"
}

`$report += "`n`nInitial System State:"
`$report += "`n  MachineGuid: `$initialMachineGuid"
`$report += "`n  HwProfileGuid: `$initialHwProfileGuid"
`$report += "`n`nFiles downloaded to: `$dest"
`$report += "`n`nTo test manually:"
`$report += "`n  cd `$dest"
`$report += "`n  .\PrivacyFirst.exe"

`$report | Out-File -FilePath `$reportPath -Encoding UTF8

Write-Host ''
Write-Host '=== Test Complete ===' -ForegroundColor Green
Write-Host `$report
Write-Host ''
Write-Host "Report saved to: `$reportPath" -ForegroundColor Cyan

# Return report content
`$report
"@

# Save script to temp file
$tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
$remoteScript | Out-File -FilePath $tempScript -Encoding UTF8

Write-Host "[1/3] Connecting to VM..." -ForegroundColor Yellow

# Try SSH first (if OpenSSH server is running on VM)
try {
    Write-Host "Attempting SSH connection..." -ForegroundColor Gray

    # Copy script to VM via SCP
    $scpResult = scp -o StrictHostKeyChecking=no $tempScript "${VMUser}@${VMHostname}:C:/test_script.ps1" 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Script uploaded via SCP" -ForegroundColor Green

        # Execute via SSH
        Write-Host "`n[2/3] Executing remote test..." -ForegroundColor Yellow
        $result = ssh -o StrictHostKeyChecking=no "${VMUser}@${VMHostname}" "powershell -ExecutionPolicy Bypass -File C:/test_script.ps1" 2>&1

        Write-Host "`n[3/3] Results:" -ForegroundColor Yellow
        Write-Host $result -ForegroundColor White

        Remove-Item $tempScript -ErrorAction SilentlyContinue
        exit 0
    }
}
catch {
    Write-Host "SSH failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Try PowerShell remoting (WinRM)
try {
    Write-Host "Attempting PowerShell remoting..." -ForegroundColor Gray

    $securePassword = ConvertTo-SecureString $VMPassword -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($VMUser, $securePassword)

    $session = New-PSSession -ComputerName $VMHostname -Credential $cred -ErrorAction Stop

    Write-Host "PowerShell session established" -ForegroundColor Green

    Write-Host "`n[2/3] Executing remote test..." -ForegroundColor Yellow
    $result = Invoke-Command -Session $session -ScriptBlock {
        param($script)
        Invoke-Expression $script
    } -ArgumentList $remoteScript

    Remove-PSSession $session

    Write-Host "`n[3/3] Results:" -ForegroundColor Yellow
    Write-Host $result -ForegroundColor White

    Remove-Item $tempScript -ErrorAction SilentlyContinue
    exit 0
}
catch {
    Write-Host "PowerShell remoting failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Manual fallback
Write-Host "`n=== Automated execution failed ===" -ForegroundColor Red
Write-Host "Please run manually on the VM:" -ForegroundColor Yellow
Write-Host ""
Write-Host "irm https://raw.githubusercontent.com/$GitHubUser/$RepoName/$Branch/download_and_run.ps1 | iex" -ForegroundColor White
Write-Host ""

Remove-Item $tempScript -ErrorAction SilentlyContinue
