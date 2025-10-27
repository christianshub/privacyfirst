# Deploy PrivacyFirst to Proxmox test VM (Alternative method using PSSession)
param(
    [string]$ProxmoxHost = "192.168.0.130",
    [string]$ProxmoxVMID = "102",
    [string]$VMUser = "john",
    [string]$VMPassword = "1",
    [string]$VMHostname = "192.168.0.143"
)

$ErrorActionPreference = "Stop"

Write-Host "=== PrivacyFirst VM Deployment ===" -ForegroundColor Cyan

# Build path
$buildPath = "c:\repos\privacyfirst\x64\Release"
if (-not (Test-Path $buildPath)) {
    Write-Host "Build path not found: $buildPath" -ForegroundColor Red
    Write-Host "Please build the solution first." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n[1/3] Checking VM status..." -ForegroundColor Yellow
$vmStatus = ssh root@$ProxmoxHost "qm status $ProxmoxVMID" 2>$null | Select-String "status:" | ForEach-Object { $_ -replace ".*status:\s*", "" }

if ($vmStatus -ne "running") {
    Write-Host "Starting VM $ProxmoxVMID..." -ForegroundColor Cyan
    ssh root@$ProxmoxHost "qm start $ProxmoxVMID" | Out-Null
    Write-Host "Waiting for VM to boot (60 seconds)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
}
else {
    Write-Host "VM is already running" -ForegroundColor Green
}

Write-Host "Using VM IP: $VMHostname" -ForegroundColor Green

# Try PSSession first (requires WinRM enabled)
Write-Host "`n[2/3] Attempting PowerShell remoting..." -ForegroundColor Yellow

try {
    $securePassword = ConvertTo-SecureString $VMPassword -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($VMUser, $securePassword)

    # Test connection
    $session = New-PSSession -ComputerName $VMHostname -Credential $cred -ErrorAction Stop

    Write-Host "PowerShell remoting successful!" -ForegroundColor Green

    # Create directory on remote
    Invoke-Command -Session $session -ScriptBlock {
        if (-not (Test-Path "C:\PrivacyFirstTest")) {
            New-Item -Path "C:\PrivacyFirstTest" -ItemType Directory -Force | Out-Null
        }
    }

    # Copy files
    Write-Host "Copying files via PSSession..." -ForegroundColor Cyan
    Copy-Item -Path "$buildPath\*" -Destination "C:\PrivacyFirstTest\" -ToSession $session -Recurse -Force

    Remove-PSSession $session

    Write-Host "`n[3/3] Deployment complete!" -ForegroundColor Green
    Write-Host "Files deployed to: C:\PrivacyFirstTest\" -ForegroundColor Cyan
    exit 0
}
catch {
    Write-Host "PowerShell remoting failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Fallback: Try network path with admin share
Write-Host "`n[2/3] Attempting network share..." -ForegroundColor Yellow

try {
    $remotePath = "\\$VMHostname\C$\PrivacyFirstTest"

    # Test if we can access the path
    if (Test-Path $remotePath) {
        Write-Host "Network path accessible!" -ForegroundColor Green
    }
    else {
        Write-Host "Creating remote directory..." -ForegroundColor Gray
        New-Item -Path $remotePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    # Copy files
    Write-Host "Copying files via network share..." -ForegroundColor Cyan
    Copy-Item -Path "$buildPath\*" -Destination $remotePath -Recurse -Force

    Write-Host "`n[3/3] Deployment complete!" -ForegroundColor Green
    Write-Host "Files deployed to: $remotePath" -ForegroundColor Cyan
    exit 0
}
catch {
    Write-Host "Network share failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Final fallback: Manual instructions
Write-Host "`n=== Automated deployment failed ===" -ForegroundColor Red
Write-Host "`nPlease deploy manually:" -ForegroundColor Yellow
Write-Host "1. RDP to $VMHostname (user: $VMUser, password: $VMPassword)" -ForegroundColor White
Write-Host "2. Create folder: C:\PrivacyFirstTest" -ForegroundColor White
Write-Host "3. Copy files from: $buildPath" -ForegroundColor White
Write-Host "   To: C:\PrivacyFirstTest\" -ForegroundColor White
Write-Host ""
Write-Host "Or run this on the VM as Administrator:" -ForegroundColor Cyan
Write-Host "New-Item -Path C:\PrivacyFirstTest -ItemType Directory -Force" -ForegroundColor Gray
Write-Host ""

exit 1
