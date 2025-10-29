# Orchestrates a full callback-based test run against a Proxmox VM.
# Steps:
#   1. Roll back the VM to a known snapshot (optional)
#   2. Start the VM and wait for the guest agent
#   3. Launch the callback server locally
#   4. Execute the VM auto-test script via the Proxmox guest agent
#   5. Wait for results posted back to the callback server
#   6. Optionally shut the VM down when complete
param(
    [string]$ProxmoxHost = "192.168.0.130",
    [string]$ProxmoxUser = "root@pam",
    [string]$ProxmoxPassword = "",
    [string]$NodeName = "",
    [string]$VMID = "102",
    [string]$SnapshotName = "baseline",
    [int]$CallbackPort = 9900,
    [string]$VMIPAddress = "",
    [string]$VMUser = "",
    [string]$VMPassword = "",
    [int]$WinRMPort = 5985,
    [switch]$UseWinRM,
    [switch]$SkipSnapshot,
    [switch]$ShutdownVM
)

$ErrorActionPreference = "Stop"

function Write-Section([string]$text, [ConsoleColor]$color = [ConsoleColor]::Cyan) {
    Write-Host ""
    Write-Host $text -ForegroundColor $color
}

function Get-LocalLanIp {
    $ip = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" -or $_.IPAddress -like "172.16.*" } |
        Select-Object -First 1 -ExpandProperty IPAddress

    if (-not $ip) {
        throw "Unable to determine LAN IPv4 address. Ensure you are on the same network as the Proxmox host."
    }

    return $ip
}

function Initialize-ProxmoxApi {
    param(
        [string]$Host,
        [string]$User,
        [string]$Password
    )

    # Allow self-signed certificates
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint,
        X509Certificate certificate,
        WebRequest request,
        int certificateProblem) {
        return true;
    }
}
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $authUri = "https://$Host:8006/api2/json/access/ticket"
    $body = @{
        username = $User
        password = $Password
    }

    $response = Invoke-RestMethod -Method Post -Uri $authUri -Body $body -ErrorAction Stop
    return @{
        Ticket = $response.data.ticket
        CSRF = $response.data.CSRFPreventionToken
    }
}

function Invoke-ProxmoxRequest {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Body = $null
    )

    $uri = "https://$script:ProxmoxHost:8006/api2/json$Path"
    $headers = @{
        Cookie = "PVEAuthCookie=$($script:ProxmoxTicket)"
    }

    if ($Method -ne "GET") {
        $headers.CSRFPreventionToken = $script:ProxmoxCSRF
    }

    if ($Body) {
        $json = $Body | ConvertTo-Json -Depth 10
    }

    if ($Method -eq "GET") {
        return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
    }

    Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $json -ContentType "application/json" -ErrorAction Stop
}

# Initialize globals for optional WinRM usage
$script:VmSession = $null
$script:VmCredential = $null

# Prompt for password if missing
if (-not $ProxmoxPassword) {
    $ProxmoxPassword = Read-Host -Prompt "Enter Proxmox password for $ProxmoxUser" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ProxmoxPassword)
    try {
        $ProxmoxPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

# Resolve repo paths
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$repoRoot = Split-Path -Path $scriptDir -Parent
$callbackScript = Join-Path $repoRoot "auto_test_with_callback.ps1"
$vmScriptPath = Join-Path $repoRoot "vm_auto_test.ps1"
$resultsDirectory = Join-Path $repoRoot "callback_results"

if (-not (Test-Path $callbackScript)) {
    throw "Cannot find auto_test_with_callback.ps1 at $callbackScript"
}

if (-not (Test-Path $vmScriptPath)) {
    throw "Cannot find vm_auto_test.ps1 at $vmScriptPath"
}

if (-not (Test-Path $resultsDirectory)) {
    New-Item -ItemType Directory -Path $resultsDirectory | Out-Null
}

Write-Host "=== PrivacyFirst Proxmox Callback Orchestrator ===" -ForegroundColor Cyan
Write-Host "Proxmox:  $ProxmoxHost" -ForegroundColor Gray
Write-Host "VM ID:    $VMID" -ForegroundColor Gray
Write-Host "Snapshot: $SnapshotName" -ForegroundColor Gray
Write-Host "Callback: http://$(Get-LocalLanIp):$CallbackPort" -ForegroundColor Gray

# Authenticate with Proxmox API
Write-Section "[1/8] Authenticating with Proxmox..."
$authTokens = Initialize-ProxmoxApi -Host $ProxmoxHost -User $ProxmoxUser -Password $ProxmoxPassword
$script:ProxmoxTicket = $authTokens.Ticket
$script:ProxmoxCSRF = $authTokens.CSRF

if ([string]::IsNullOrWhiteSpace($NodeName)) {
    $nodes = Invoke-ProxmoxRequest -Method Get -Path "/nodes"
    $NodeName = $nodes.data[0].node
    Write-Host "Detected node: $NodeName" -ForegroundColor Gray
}
else {
    Write-Host "Using node: $NodeName" -ForegroundColor Gray
}

# Step 2: Roll back snapshot if requested
if (-not $SkipSnapshot) {
    Write-Section "[2/8] Rolling back snapshot '$SnapshotName'..."
    try {
        Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/snapshot/$SnapshotName/rollback" | Out-Null
        Write-Host "Snapshot rollback queued" -ForegroundColor Green
    }
    catch {
        Write-Host "Snapshot rollback failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
else {
    Write-Section "[2/8] Skipping snapshot rollback (--SkipSnapshot)"
}

# Step 3: Start VM
Write-Section "[3/8] Ensuring VM is running..."
$statusResponse = Invoke-ProxmoxRequest -Method Get -Path "/nodes/$NodeName/qemu/$VMID/status/current"
$currentStatus = $statusResponse.data.status

if ($currentStatus -ne "running") {
    Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/status/start" | Out-Null
    Write-Host "VM start requested, waiting for boot..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
}
else {
    Write-Host "VM already running" -ForegroundColor Green
}

# Wait for running status
for ($i = 0; $i -lt 12; $i++) {
    $currentStatus = (Invoke-ProxmoxRequest -Method Get -Path "/nodes/$NodeName/qemu/$VMID/status/current").data.status
    if ($currentStatus -eq "running") { break }
    Start-Sleep -Seconds 10
}

if ($currentStatus -ne "running") {
    throw "VM failed to reach running state."
}

Write-Host "VM status: running" -ForegroundColor Green

# Step 4: Determine remote execution method
$executionMethod = "GuestAgent"
$agentReady = $false

if (-not $UseWinRM) {
    Write-Section "[4/8] Waiting for QEMU guest agent..."
    for ($i = 0; $i -lt 30; $i++) {
        try {
            Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/agent/ping" | Out-Null
            $agentReady = $true
            break
        }
        catch {
            Start-Sleep -Seconds 5
        }
    }

    if ($agentReady) {
        Write-Host "Guest agent is responsive" -ForegroundColor Green
    }
    else {
        Write-Host "Guest agent not responding." -ForegroundColor Yellow
    }
}

if ($UseWinRM -or -not $agentReady) {
    if (-not $VMIPAddress) {
        throw "Guest agent unavailable. Provide -VMIPAddress and credentials or use -UseWinRM."
    }
    if (-not $VMUser) {
        throw "Guest agent unavailable. Provide -VMUser for WinRM execution."
    }
    if (-not $VMPassword) {
        $VMPassword = Read-Host -Prompt "Enter password for $VMUser on $VMIPAddress" -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($VMPassword)
        try {
            $VMPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    }

    $executionMethod = "WinRM"
    Write-Section "[4/8] Preparing WinRM connection..."

    Write-Host "Waiting for TCP $WinRMPort on $VMIPAddress ..." -ForegroundColor Yellow
    $portReady = $false
    for ($i = 0; $i -lt 24; $i++) {
        try {
            $tcp = Test-NetConnection -ComputerName $VMIPAddress -Port $WinRMPort -WarningAction SilentlyContinue
            if ($tcp.TcpTestSucceeded) {
                $portReady = $true
                break
            }
        }
        catch { }
        Start-Sleep -Seconds 5
    }

    if (-not $portReady) {
        throw "Cannot reach WinRM port $WinRMPort on $VMIPAddress. Ensure the VM is reachable and WinRM is enabled."
    }

    $script:VmCredential = New-Object System.Management.Automation.PSCredential(
        $VMUser,
        (ConvertTo-SecureString $VMPassword -AsPlainText -Force)
    )

    $session = $null
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $session = New-PSSession -ComputerName $VMIPAddress -Credential $script:VmCredential -Authentication Negotiate -ErrorAction Stop
            break
        }
        catch {
            Start-Sleep -Seconds 5
        }
    }

    if (-not $session) {
        throw "Unable to establish WinRM session to $VMIPAddress with supplied credentials."
    }

    Write-Host "WinRM session established" -ForegroundColor Green
    $script:VmSession = $session
}

# Step 5: Start callback server
Write-Section "[5/8] Starting callback server..."
$localIP = Get-LocalLanIp
$callbackJob = Start-Job -Name "PrivacyFirstCallback" -ScriptBlock {
    param($repoRoot, $port)
    Set-Location $repoRoot
    powershell -ExecutionPolicy Bypass -File ".\auto_test_with_callback.ps1" -CallbackPort $port | Out-String
} -ArgumentList $repoRoot, $CallbackPort

Start-Sleep -Seconds 2

# Ensure listener is ready
$listenerReady = $false
$callbackUrl = "http://$localIP:$CallbackPort/script"
for ($i = 0; $i -lt 20; $i++) {
    if ($callbackJob.State -eq "Failed") {
        $err = Receive-Job -Job $callbackJob -ErrorAction SilentlyContinue
        throw "Callback server failed to start: $err"
    }
    try {
        Invoke-WebRequest -Uri $callbackUrl -Method Get -UseBasicParsing | Out-Null
        $listenerReady = $true
        break
    }
    catch {
        Start-Sleep -Seconds 1
    }
}

if (-not $listenerReady) {
    Stop-Job $callbackJob -Force | Out-Null
    throw "Callback server did not become ready on port $CallbackPort."
}

Write-Host "Callback server listening at http://$localIP:$CallbackPort/" -ForegroundColor Green

# Step 6: Execute VM auto test via guest agent
Write-Section "[6/8] Triggering VM auto-test via guest agent..."
$callbackUri = "http://$localIP:$CallbackPort/script"
$execPid = $null
$commandComplete = $false
$resultFile = $null
$rawFile = $null
$waitStart = Get-Date
$existingFiles = @{}
Get-ChildItem -Path $resultsDirectory -File -ErrorAction SilentlyContinue | ForEach-Object { $existingFiles[$_.FullName] = $true }

if ($executionMethod -eq "GuestAgent") {
    $invokeCommand = "irm $callbackUri | iex"
    $execBody = @{
        command = "powershell.exe"
        args    = @(
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-Command", $invokeCommand
        )
    }

    $execResponse = Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/agent/exec" -Body $execBody
    $execPid = $execResponse.data.pid
    Write-Host "Guest exec PID: $execPid" -ForegroundColor Gray
}
else {
    Write-Host "Invoking remote command over WinRM..." -ForegroundColor Yellow
    try {
        Invoke-Command -Session $script:VmSession -ScriptBlock {
            param($url)
            $invoke = "irm $url | iex"
            powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command $invoke
        } -ArgumentList $callbackUri
        $commandComplete = $true
        Write-Host "WinRM command completed" -ForegroundColor Green
    }
    catch {
        throw "WinRM execution failed: $($_.Exception.Message)"
    }
}

Write-Section "[7/8] Waiting for VM results..."
for ($i = 0; $i -lt 60; $i++) {
    if ($executionMethod -eq "GuestAgent" -and $execPid) {
        $statusPath = "/nodes/$NodeName/qemu/$VMID/agent/exec-status?pid=$execPid"
        $execStatus = Invoke-ProxmoxRequest -Method Get -Path $statusPath
        if ($execStatus.data.exited -eq $true) {
            $commandComplete = $true
        }
    }

    $latest = Get-ChildItem -Path $resultsDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { -not $existingFiles.ContainsKey($_.FullName) -and $_.LastWriteTime -gt $waitStart.AddSeconds(-5) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        if ($latest.Extension -eq ".json") {
            $resultFile = $latest
        }
        else {
            $rawFile = $latest
        }
    }

    if ($commandComplete -and $resultFile) { break }
    Start-Sleep -Seconds 5
}

if (-not $commandComplete) {
    Write-Host "Warning: remote command still running or status unavailable." -ForegroundColor Yellow
}

if (-not $resultFile) {
    Write-Host "Warning: no callback JSON detected in $resultsDirectory" -ForegroundColor Yellow
}
else {
    Write-Host "Result file: $($resultFile.FullName)" -ForegroundColor Green
}

# Step 8: Optional shutdown
if ($ShutdownVM) {
    Write-Section "[8/8] Shutting down VM..."
    try {
        Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/status/shutdown" | Out-Null
        Write-Host "Shutdown requested" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to shut down VM: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
else {
    Write-Section "[8/8] Leaving VM running (use -ShutdownVM to stop automatically)."
}

# Close WinRM session if opened
if ($script:VmSession) {
    Remove-PSSession -Session $script:VmSession -ErrorAction SilentlyContinue
    $script:VmSession = $null
}

# Gather callback logs/output
$callbackOutput = Receive-Job -Job $callbackJob -Keep
Stop-Job -Job $callbackJob -Force | Out-Null
Remove-Job -Job $callbackJob | Out-Null

Write-Section "=== Run Summary ===" ([ConsoleColor]::Cyan)
Write-Host "Callback port:   $CallbackPort" -ForegroundColor Gray
Write-Host "Result JSON:     $(if ($resultFile) { $resultFile.FullName } else { 'not found' })" -ForegroundColor Gray
Write-Host "Raw callback:    $(if ($rawFile) { $rawFile.FullName } else { 'not captured' })" -ForegroundColor Gray
Write-Host ""
Write-Host "Callback server output:" -ForegroundColor White
if ($callbackOutput) {
    $callbackOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}
else {
    Write-Host "  (no output captured)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Proxmox callback orchestration complete." -ForegroundColor Green
