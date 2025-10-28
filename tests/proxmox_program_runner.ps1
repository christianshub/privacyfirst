# Proxmox automation pipeline:
#  1. Roll back VM snapshot (optional)
#  2. Boot VM 102 and wait for QEMU guest agent
#  3. Serve local build artifacts over HTTP
#  4. Download & execute program inside the VM via the guest agent
#  5. Collect stdout/exit code and optionally shut the VM down
param(
    [string]$ProxmoxHost = "192.168.0.130",
    [string]$ProxmoxUser = "root@pam",
    [string]$ProxmoxPassword = "",
    [string]$NodeName = "",
    [string]$VMID = "102",
    [string]$SnapshotName = "baseline",
    [string]$BuildOutputPath = "c:\repos\privacyfirst\x64\Release",
    [string[]]$Files = @(
        "PrivacyFirst.exe",
        "PrivacyFirst.dll",
        "PrivacyCore.dll",
        "PrivacyFirst.deps.json",
        "PrivacyFirst.runtimeconfig.json"
    ),
    [string]$Executable = "PrivacyFirst.exe",
    [string]$Arguments = "",
    [string]$RemoteWorkingDirectory = "C:\PrivacyFirstPipeline",
    [int]$HttpPort = 9910,
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
        Where-Object {
            $_.IPAddress -like "192.168.*" -or
            $_.IPAddress -like "10.*" -or
            $_.IPAddress -like "172.16.*"
        } |
        Select-Object -First 1 -ExpandProperty IPAddress

    if (-not $ip) {
        throw "Unable to determine LAN IPv4 address. Ensure you are on the same network as the Proxmox host."

    return $ip
}

function Initialize-ProxmoxApi {
    param(
        [string]$PveHost,
        [string]$PveUser,
        [string]$PvePassword
    )

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
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    Write-Host ("Authenticating to Proxmox at {0}" -f $PveHost) -ForegroundColor DarkGray

    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $authUri = "https://${PveHost}:8006/api2/json/access/ticket"
    $response = Invoke-RestMethod -Method Post -Uri $authUri -Body @{
        username = $PveUser
        password = $PvePassword
    } -WebSession $session

    $cookie = New-Object System.Net.Cookie("PVEAuthCookie", $response.data.ticket, "/", $PveHost)
    $session.Cookies.Add($cookie)

    return @{
        Ticket = $response.data.ticket
        CSRF   = $response.data.CSRFPreventionToken
        Session = $session
}

function Invoke-ProxmoxRequest {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null
    )

    $uri = "https://${script:ProxmoxHost}:8006/api2/json$Path"

    $headers = @{}

    if ($Method -ne "GET") {
        $headers.CSRFPreventionToken = $script:ProxmoxCSRF

    $params = @{
        Method      = $Method
        Uri         = $uri
        WebSession  = $script:ProxmoxSession
        ErrorAction = 'Stop'

    if ($headers.Count -gt 0) {
        $params.Headers = $headers

    if ($Body) {
        if ($Body -is [string]) {
            $params.Body = $Body
            $params.ContentType = "application/json"
        }
        else {
            $params.Body = $Body
        }

    Invoke-RestMethod @params
}

function Wait-ForGuestAgent {
    param(
        [string]$Node,
        [string]$VMID,
        [int]$Attempts = 30,
        [int]$DelaySeconds = 5
    )

    for ($i = 0; $i -lt $Attempts; $i++) {
        try {
            Invoke-ProxmoxRequest -Method Post -Path "/nodes/$Node/qemu/$VMID/agent/ping" | Out-Null
            return $true
        }
        catch {
            Start-Sleep -Seconds $DelaySeconds
        }

    return $false
}

function Wait-ProxmoxTask {
    param(
        [string]$Node,
        [string]$Upid,
        [int]$TimeoutSeconds = 600
    )

    if (-not $Upid) {
        return

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $status = Invoke-ProxmoxRequest -Method Get -Path "/nodes/$Node/tasks/$Upid/status"
        $state = $status.data.status
        $exit = $status.data.exitstatus

        if ($state -eq "stopped" -or $state -eq "OK" -or $state -eq "ok") {
            if ($exit -and $exit -ne "OK") {
                throw "Proxmox task $Upid exited with status $exit"
            }
            return
        }

        if ($state -eq "running" -or $state -eq "queued") {
            Start-Sleep -Seconds 5
            continue
        }

        if ($exit -and $exit -ne "OK") {
            throw "Proxmox task $Upid exited with status $exit"
        }

        Start-Sleep -Seconds 5

    throw "Proxmox task $Upid did not complete within $TimeoutSeconds seconds."
}

function Initialize-WinRMSession {
    param(
        [string]$IpAddress,
        [string]$Username,
        [string]$Password,
        [int]$Port = 5985
    )

    Write-Section "[4/8] Preparing WinRM connection..."
    Write-Host ("Waiting for TCP port {0} on {1} ..." -f $Port, $IpAddress) -ForegroundColor Yellow

    $portReady = $false
    for ($i = 0; $i -lt 24; $i++) {
        try {
            $tcp = Test-NetConnection -ComputerName $IpAddress -Port $Port -WarningAction SilentlyContinue
            if ($tcp.TcpTestSucceeded) {
                $portReady = $true
                break
            }
        }
        catch { }
        Start-Sleep -Seconds 5

    if (-not $portReady) {
        throw "Cannot reach WinRM port $Port on $IpAddress. Ensure the VM is reachable and WinRM is enabled."

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($Username, $securePassword)

    $session = $null
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $session = New-PSSession -ComputerName $IpAddress -Credential $cred -Authentication Negotiate -ErrorAction Stop
            break
        }
        catch {
            Start-Sleep -Seconds 5
        }

    if (-not $session) {
        throw "Unable to establish WinRM session to $IpAddress with supplied credentials."

    Write-Host "WinRM session established" -ForegroundColor Green
    return $session
}

# Prompt for Proxmox password if omitted
if (-not $ProxmoxPassword) {
    $ProxmoxPassword = Read-Host -Prompt "Enter Proxmox password for $ProxmoxUser" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ProxmoxPassword)
    try {
        $ProxmoxPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

if (-not (Test-Path $BuildOutputPath)) {
    throw "Build output path not found: $BuildOutputPath"
}

$script:ProxmoxHost = $ProxmoxHost

Write-Host "=== PrivacyFirst Proxmox Program Runner ===" -ForegroundColor Cyan
Write-Host "Proxmox:  $ProxmoxHost" -ForegroundColor Gray
Write-Host "VM ID:    $VMID" -ForegroundColor Gray
Write-Host "Snapshot: $SnapshotName" -ForegroundColor Gray
Write-Host "Artifacts: $BuildOutputPath" -ForegroundColor Gray
Write-Host "Executable: $Executable $Arguments" -ForegroundColor Gray

# Authenticate & resolve node
Write-Section "[1/8] Authenticating with Proxmox..."
$authTokens = Initialize-ProxmoxApi -PveHost $ProxmoxHost -PveUser $ProxmoxUser -PvePassword $ProxmoxPassword
$script:ProxmoxTicket = $authTokens.Ticket
$script:ProxmoxCSRF = $authTokens.CSRF
$script:ProxmoxSession = $authTokens.Session

if ([string]::IsNullOrWhiteSpace($NodeName)) {
    $nodeResponse = Invoke-ProxmoxRequest -Method Get -Path "/nodes"
    $NodeName = $nodeResponse.data[0].node
    Write-Host "Detected node: $NodeName" -ForegroundColor Gray
}
else {
    Write-Host "Using node: $NodeName" -ForegroundColor Gray
}

# Optional snapshot rollback
if (-not $SkipSnapshot) {
    Write-Section "[2/8] Rolling back snapshot '$SnapshotName'..."
    try {
        $rollbackResponse = Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/snapshot/$SnapshotName/rollback"
        Write-Host "Snapshot rollback queued" -ForegroundColor Green
        if ($rollbackResponse.data) {
            Wait-ProxmoxTask -Node $NodeName -Upid $rollbackResponse.data
            Write-Host "Snapshot rollback completed" -ForegroundColor Green
        }
    catch {
        Write-Host "Snapshot rollback failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
else {
    Write-Section "[2/8] Skipping snapshot rollback (--SkipSnapshot)"
}

# Start VM if needed
Write-Section "[3/8] Ensuring VM is running..."
$vmStatus = (Invoke-ProxmoxRequest -Method Get -Path "/nodes/$NodeName/qemu/$VMID/status/current").data.status
if ($vmStatus -ne "running") {
    Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/status/start" | Out-Null
    Write-Host "VM start requested, waiting for boot..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
}
else {
    Write-Host "VM already running" -ForegroundColor Green
}

# Confirm running state
for ($i = 0; $i -lt 24; $i++) {
    $vmStatus = (Invoke-ProxmoxRequest -Method Get -Path "/nodes/$NodeName/qemu/$VMID/status/current").data.status
    if ($vmStatus -eq "running") { break }
    Start-Sleep -Seconds 5
}

if ($vmStatus -ne "running") {
    throw "VM failed to reach running state."
}

$executionMethod = "GuestAgent"
$winRMSession = $null

if ($UseWinRM) {
    if (-not $VMIPAddress) {
        throw "WinRM requested but -VMIPAddress was not provided."
    if (-not $VMUser) {
        throw "WinRM requested but -VMUser was not provided."
    if (-not $VMPassword) {
        $VMPassword = Read-Host -Prompt "Enter VM password for $VMUser" -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($VMPassword)
        try {
            $VMPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }

    $winRMSession = Initialize-WinRMSession -IpAddress $VMIPAddress -Username $VMUser -Password $VMPassword -Port $WinRMPort
    $executionMethod = "WinRM"
}
else {
    # Wait for QEMU guest agent
    Write-Section "[4/8] Waiting for QEMU guest agent..."
    if (-not (Wait-ForGuestAgent -Node $NodeName -VMID $VMID)) {
        throw "Guest agent not responding. Ensure qemu-guest-agent service is running inside the VM."
    Write-Host "Guest agent is responsive" -ForegroundColor Green
}

# Start HTTP server to serve artifacts
Write-Section "[5/8] Starting local HTTP artifact server..."
$localIP = Get-LocalLanIp

$serveJob = Start-Job -ScriptBlock {
    param($path, $port, $bind)
    Set-Location $path
    python -m http.server $port --bind $bind
} -ArgumentList $BuildOutputPath, $HttpPort, $localIP

Start-Sleep -Seconds 2

$httpReady = $false
$probeUri = ("http://{0}:{1}/" -f $localIP, $HttpPort)
for ($i = 0; $i -lt 10; $i++) {
    if ($serveJob.State -eq "Failed") {
        $err = Receive-Job -Job $serveJob -ErrorAction SilentlyContinue
        throw "Artifact server failed to start: $err"

    try {
        Invoke-WebRequest -Uri $probeUri -Method Get -UseBasicParsing | Out-Null
        $httpReady = $true
        break
    catch {
        Start-Sleep -Seconds 1
}

if (-not $httpReady) {
    Stop-Job -Job $serveJob -Force | Out-Null
    Remove-Job -Job $serveJob | Out-Null
    throw "Artifact server not reachable on $probeUri"
}

Write-Host ("Serving {0} at {1}" -f $BuildOutputPath, $probeUri) -ForegroundColor Green

# Construct VM-side script
$config = @{
    BaseUrl      = ("http://{0}:{1}" -f $localIP, $HttpPort)
    Destination  = $RemoteWorkingDirectory
    Files        = $Files
    Executable   = $Executable
    Arguments    = $Arguments
    StdOutFile   = "stdout.txt"
    StdErrFile   = "stderr.txt"
}

$configJson = $config | ConvertTo-Json -Depth 10
$configBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($configJson))

$vmScript = @"
`$cfgJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$configBase64"))
`$cfg = `$cfgJson | ConvertFrom-Json

`$ErrorActionPreference = 'Stop'

if (-not (Test-Path `$cfg.Destination)) {
    New-Item -ItemType Directory -Path `$cfg.Destination -Force | Out-Null
}

foreach (`$file in `$cfg.Files) {
    `$uri = "`$(`$cfg.BaseUrl)/`$file"
    Invoke-WebRequest -Uri `$uri -OutFile (Join-Path `$cfg.Destination `$file) -UseBasicParsing -ErrorAction Stop
}

`$exePath = Join-Path `$cfg.Destination `$cfg.Executable
if (-not (Test-Path `$exePath)) {
    throw "Executable not found: `$exePath"
}

`$stdoutPath = Join-Path `$cfg.Destination `$cfg.StdOutFile
`$stderrPath = Join-Path `$cfg.Destination `$cfg.StdErrFile

if (Test-Path `$stdoutPath) { Remove-Item `$stdoutPath -Force }
if (Test-Path `$stderrPath) { Remove-Item `$stderrPath -Force }

`$startInfo = @{
    FilePath = `$exePath
    PassThru = `$true
    Wait = `$true
    NoNewWindow = `$true
    RedirectStandardOutput = `$stdoutPath
    RedirectStandardError = `$stderrPath
}

if (-not [string]::IsNullOrWhiteSpace(`$cfg.Arguments)) {
    `$startInfo.ArgumentList = `$cfg.Arguments
}

`$proc = Start-Process @startInfo

`$stdout = if (Test-Path `$stdoutPath) { Get-Content `$stdoutPath -Raw } else { "" }
`$stderr = if (Test-Path `$stderrPath) { Get-Content `$stderrPath -Raw } else { "" }

[PSCustomObject]@{
    StdOut = `$stdout
    StdErr = `$stderr
    ExitCode = `$proc.ExitCode
    Executable = `$exePath
    Arguments = `$cfg.Arguments
} | ConvertTo-Json -Depth 5
"@

$vmScriptEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($vmScript))

Write-Section "[6/8] Executing program inside VM..."
$resultJson = $null
$exitCode = $null
$stdOut = ""
$stdErr = ""
$commandComplete = $false
$execPid = $null
$execArguments = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-EncodedCommand", $vmScriptEncoded
)

if ($executionMethod -eq "GuestAgent") {
    $queryArgs = $execArguments | ForEach-Object { "extra-args%5B%5D=" + [Uri]::EscapeDataString(# Proxmox automation pipeline:
#  1. Roll back VM snapshot (optional)
#  2. Boot VM 102 and wait for QEMU guest agent
#  3. Serve local build artifacts over HTTP
#  4. Download & execute program inside the VM via the guest agent
#  5. Collect stdout/exit code and optionally shut the VM down
param(
    [string]$ProxmoxHost = "192.168.0.130",
    [string]$ProxmoxUser = "root@pam",
    [string]$ProxmoxPassword = "",
    [string]$NodeName = "",
    [string]$VMID = "102",
    [string]$SnapshotName = "baseline",
    [string]$BuildOutputPath = "c:\repos\privacyfirst\x64\Release",
    [string[]]$Files = @(
        "PrivacyFirst.exe",
        "PrivacyFirst.dll",
        "PrivacyCore.dll",
        "PrivacyFirst.deps.json",
        "PrivacyFirst.runtimeconfig.json"
    ),
    [string]$Executable = "PrivacyFirst.exe",
    [string]$Arguments = "",
    [string]$RemoteWorkingDirectory = "C:\PrivacyFirstPipeline",
    [int]$HttpPort = 9910,
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
        Where-Object {
            $_.IPAddress -like "192.168.*" -or
            $_.IPAddress -like "10.*" -or
            $_.IPAddress -like "172.16.*"
        } |
        Select-Object -First 1 -ExpandProperty IPAddress

    if (-not $ip) {
        throw "Unable to determine LAN IPv4 address. Ensure you are on the same network as the Proxmox host."

    return $ip
}

function Initialize-ProxmoxApi {
    param(
        [string]$PveHost,
        [string]$PveUser,
        [string]$PvePassword
    )

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
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    Write-Host ("Authenticating to Proxmox at {0}" -f $PveHost) -ForegroundColor DarkGray

    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $authUri = "https://${PveHost}:8006/api2/json/access/ticket"
    $response = Invoke-RestMethod -Method Post -Uri $authUri -Body @{
        username = $PveUser
        password = $PvePassword
    } -WebSession $session

    $cookie = New-Object System.Net.Cookie("PVEAuthCookie", $response.data.ticket, "/", $PveHost)
    $session.Cookies.Add($cookie)

    return @{
        Ticket = $response.data.ticket
        CSRF   = $response.data.CSRFPreventionToken
        Session = $session
}

function Invoke-ProxmoxRequest {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null
    )

    $uri = "https://${script:ProxmoxHost}:8006/api2/json$Path"

    $headers = @{}

    if ($Method -ne "GET") {
        $headers.CSRFPreventionToken = $script:ProxmoxCSRF

    $params = @{
        Method      = $Method
        Uri         = $uri
        WebSession  = $script:ProxmoxSession
        ErrorAction = 'Stop'

    if ($headers.Count -gt 0) {
        $params.Headers = $headers

    if ($Body) {
        if ($Body -is [string]) {
            $params.Body = $Body
            $params.ContentType = "application/json"
        }
        else {
            $params.Body = $Body
        }

    Invoke-RestMethod @params
}

function Wait-ForGuestAgent {
    param(
        [string]$Node,
        [string]$VMID,
        [int]$Attempts = 30,
        [int]$DelaySeconds = 5
    )

    for ($i = 0; $i -lt $Attempts; $i++) {
        try {
            Invoke-ProxmoxRequest -Method Post -Path "/nodes/$Node/qemu/$VMID/agent/ping" | Out-Null
            return $true
        }
        catch {
            Start-Sleep -Seconds $DelaySeconds
        }

    return $false
}

function Wait-ProxmoxTask {
    param(
        [string]$Node,
        [string]$Upid,
        [int]$TimeoutSeconds = 600
    )

    if (-not $Upid) {
        return

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $status = Invoke-ProxmoxRequest -Method Get -Path "/nodes/$Node/tasks/$Upid/status"
        $state = $status.data.status
        $exit = $status.data.exitstatus

        if ($state -eq "stopped" -or $state -eq "OK" -or $state -eq "ok") {
            if ($exit -and $exit -ne "OK") {
                throw "Proxmox task $Upid exited with status $exit"
            }
            return
        }

        if ($state -eq "running" -or $state -eq "queued") {
            Start-Sleep -Seconds 5
            continue
        }

        if ($exit -and $exit -ne "OK") {
            throw "Proxmox task $Upid exited with status $exit"
        }

        Start-Sleep -Seconds 5

    throw "Proxmox task $Upid did not complete within $TimeoutSeconds seconds."
}

function Initialize-WinRMSession {
    param(
        [string]$IpAddress,
        [string]$Username,
        [string]$Password,
        [int]$Port = 5985
    )

    Write-Section "[4/8] Preparing WinRM connection..."
    Write-Host ("Waiting for TCP port {0} on {1} ..." -f $Port, $IpAddress) -ForegroundColor Yellow

    $portReady = $false
    for ($i = 0; $i -lt 24; $i++) {
        try {
            $tcp = Test-NetConnection -ComputerName $IpAddress -Port $Port -WarningAction SilentlyContinue
            if ($tcp.TcpTestSucceeded) {
                $portReady = $true
                break
            }
        }
        catch { }
        Start-Sleep -Seconds 5

    if (-not $portReady) {
        throw "Cannot reach WinRM port $Port on $IpAddress. Ensure the VM is reachable and WinRM is enabled."

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($Username, $securePassword)

    $session = $null
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $session = New-PSSession -ComputerName $IpAddress -Credential $cred -Authentication Negotiate -ErrorAction Stop
            break
        }
        catch {
            Start-Sleep -Seconds 5
        }

    if (-not $session) {
        throw "Unable to establish WinRM session to $IpAddress with supplied credentials."

    Write-Host "WinRM session established" -ForegroundColor Green
    return $session
}

# Prompt for Proxmox password if omitted
if (-not $ProxmoxPassword) {
    $ProxmoxPassword = Read-Host -Prompt "Enter Proxmox password for $ProxmoxUser" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ProxmoxPassword)
    try {
        $ProxmoxPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

if (-not (Test-Path $BuildOutputPath)) {
    throw "Build output path not found: $BuildOutputPath"
}

$script:ProxmoxHost = $ProxmoxHost

Write-Host "=== PrivacyFirst Proxmox Program Runner ===" -ForegroundColor Cyan
Write-Host "Proxmox:  $ProxmoxHost" -ForegroundColor Gray
Write-Host "VM ID:    $VMID" -ForegroundColor Gray
Write-Host "Snapshot: $SnapshotName" -ForegroundColor Gray
Write-Host "Artifacts: $BuildOutputPath" -ForegroundColor Gray
Write-Host "Executable: $Executable $Arguments" -ForegroundColor Gray

# Authenticate & resolve node
Write-Section "[1/8] Authenticating with Proxmox..."
$authTokens = Initialize-ProxmoxApi -PveHost $ProxmoxHost -PveUser $ProxmoxUser -PvePassword $ProxmoxPassword
$script:ProxmoxTicket = $authTokens.Ticket
$script:ProxmoxCSRF = $authTokens.CSRF
$script:ProxmoxSession = $authTokens.Session

if ([string]::IsNullOrWhiteSpace($NodeName)) {
    $nodeResponse = Invoke-ProxmoxRequest -Method Get -Path "/nodes"
    $NodeName = $nodeResponse.data[0].node
    Write-Host "Detected node: $NodeName" -ForegroundColor Gray
}
else {
    Write-Host "Using node: $NodeName" -ForegroundColor Gray
}

# Optional snapshot rollback
if (-not $SkipSnapshot) {
    Write-Section "[2/8] Rolling back snapshot '$SnapshotName'..."
    try {
        $rollbackResponse = Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/snapshot/$SnapshotName/rollback"
        Write-Host "Snapshot rollback queued" -ForegroundColor Green
        if ($rollbackResponse.data) {
            Wait-ProxmoxTask -Node $NodeName -Upid $rollbackResponse.data
            Write-Host "Snapshot rollback completed" -ForegroundColor Green
        }
    catch {
        Write-Host "Snapshot rollback failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
else {
    Write-Section "[2/8] Skipping snapshot rollback (--SkipSnapshot)"
}

# Start VM if needed
Write-Section "[3/8] Ensuring VM is running..."
$vmStatus = (Invoke-ProxmoxRequest -Method Get -Path "/nodes/$NodeName/qemu/$VMID/status/current").data.status
if ($vmStatus -ne "running") {
    Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/status/start" | Out-Null
    Write-Host "VM start requested, waiting for boot..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
}
else {
    Write-Host "VM already running" -ForegroundColor Green
}

# Confirm running state
for ($i = 0; $i -lt 24; $i++) {
    $vmStatus = (Invoke-ProxmoxRequest -Method Get -Path "/nodes/$NodeName/qemu/$VMID/status/current").data.status
    if ($vmStatus -eq "running") { break }
    Start-Sleep -Seconds 5
}

if ($vmStatus -ne "running") {
    throw "VM failed to reach running state."
}

$executionMethod = "GuestAgent"
$winRMSession = $null

if ($UseWinRM) {
    if (-not $VMIPAddress) {
        throw "WinRM requested but -VMIPAddress was not provided."
    if (-not $VMUser) {
        throw "WinRM requested but -VMUser was not provided."
    if (-not $VMPassword) {
        $VMPassword = Read-Host -Prompt "Enter VM password for $VMUser" -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($VMPassword)
        try {
            $VMPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }

    $winRMSession = Initialize-WinRMSession -IpAddress $VMIPAddress -Username $VMUser -Password $VMPassword -Port $WinRMPort
    $executionMethod = "WinRM"
}
else {
    # Wait for QEMU guest agent
    Write-Section "[4/8] Waiting for QEMU guest agent..."
    if (-not (Wait-ForGuestAgent -Node $NodeName -VMID $VMID)) {
        throw "Guest agent not responding. Ensure qemu-guest-agent service is running inside the VM."
    Write-Host "Guest agent is responsive" -ForegroundColor Green
}

# Start HTTP server to serve artifacts
Write-Section "[5/8] Starting local HTTP artifact server..."
$localIP = Get-LocalLanIp

$serveJob = Start-Job -ScriptBlock {
    param($path, $port, $bind)
    Set-Location $path
    python -m http.server $port --bind $bind
} -ArgumentList $BuildOutputPath, $HttpPort, $localIP

Start-Sleep -Seconds 2

$httpReady = $false
$probeUri = ("http://{0}:{1}/" -f $localIP, $HttpPort)
for ($i = 0; $i -lt 10; $i++) {
    if ($serveJob.State -eq "Failed") {
        $err = Receive-Job -Job $serveJob -ErrorAction SilentlyContinue
        throw "Artifact server failed to start: $err"

    try {
        Invoke-WebRequest -Uri $probeUri -Method Get -UseBasicParsing | Out-Null
        $httpReady = $true
        break
    catch {
        Start-Sleep -Seconds 1
}

if (-not $httpReady) {
    Stop-Job -Job $serveJob -Force | Out-Null
    Remove-Job -Job $serveJob | Out-Null
    throw "Artifact server not reachable on $probeUri"
}

Write-Host ("Serving {0} at {1}" -f $BuildOutputPath, $probeUri) -ForegroundColor Green

# Construct VM-side script
$config = @{
    BaseUrl      = ("http://{0}:{1}" -f $localIP, $HttpPort)
    Destination  = $RemoteWorkingDirectory
    Files        = $Files
    Executable   = $Executable
    Arguments    = $Arguments
    StdOutFile   = "stdout.txt"
    StdErrFile   = "stderr.txt"
}

$configJson = $config | ConvertTo-Json -Depth 10
$configBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($configJson))

$vmScript = @"
`$cfgJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$configBase64"))
`$cfg = `$cfgJson | ConvertFrom-Json

`$ErrorActionPreference = 'Stop'

if (-not (Test-Path `$cfg.Destination)) {
    New-Item -ItemType Directory -Path `$cfg.Destination -Force | Out-Null
}

foreach (`$file in `$cfg.Files) {
    `$uri = "`$(`$cfg.BaseUrl)/`$file"
    Invoke-WebRequest -Uri `$uri -OutFile (Join-Path `$cfg.Destination `$file) -UseBasicParsing -ErrorAction Stop
}

`$exePath = Join-Path `$cfg.Destination `$cfg.Executable
if (-not (Test-Path `$exePath)) {
    throw "Executable not found: `$exePath"
}

`$stdoutPath = Join-Path `$cfg.Destination `$cfg.StdOutFile
`$stderrPath = Join-Path `$cfg.Destination `$cfg.StdErrFile

if (Test-Path `$stdoutPath) { Remove-Item `$stdoutPath -Force }
if (Test-Path `$stderrPath) { Remove-Item `$stderrPath -Force }

`$startInfo = @{
    FilePath = `$exePath
    PassThru = `$true
    Wait = `$true
    NoNewWindow = `$true
    RedirectStandardOutput = `$stdoutPath
    RedirectStandardError = `$stderrPath
}

if (-not [string]::IsNullOrWhiteSpace(`$cfg.Arguments)) {
    `$startInfo.ArgumentList = `$cfg.Arguments
}

`$proc = Start-Process @startInfo

`$stdout = if (Test-Path `$stdoutPath) { Get-Content `$stdoutPath -Raw } else { "" }
`$stderr = if (Test-Path `$stderrPath) { Get-Content `$stderrPath -Raw } else { "" }

[PSCustomObject]@{
    StdOut = `$stdout
    StdErr = `$stderr
    ExitCode = `$proc.ExitCode
    Executable = `$exePath
    Arguments = `$cfg.Arguments
} | ConvertTo-Json -Depth 5
"@

$vmScriptEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($vmScript))

Write-Section "[6/8] Executing program inside VM..."
$resultJson = $null
$exitCode = $null
$stdOut = ""
$stdErr = ""
$commandComplete = $false
$execPid = $null
$execArguments = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-EncodedCommand", $vmScriptEncoded
)

if ($executionMethod -eq "GuestAgent") {
    $queryArgs = $execArguments | ForEach-Object { "extra-args%5B%5D=" + [Uri]::EscapeDataString($_) }
    $queryString = $queryArgs -join "&"
    $execPath = "/nodes/$NodeName/qemu/$VMID/agent/exec?command=powershell.exe"
    if ($queryString) {
        $execPath += "&$queryString"
    }

    $execResponse = Invoke-ProxmoxRequest -Method Post -Path $execPath
    $execPid = $execResponse.data.pid
    Write-Host "Guest exec PID: $execPid" -ForegroundColor Gray

    Write-Section "[7/8] Waiting for execution result..."
    $queryString = $queryArgs -join "&"
    $execPath = "/nodes/$NodeName/qemu/$VMID/agent/exec?command=powershell.exe"
    if ($queryString) {
    if ($queryString) {
        $execPath += "&$queryString"
    }
    $execResponse = Invoke-ProxmoxRequest -Method Post -Path $execPath
    $execPid = $execResponse.data.pid
    Write-Host "Guest exec PID: $execPid" -ForegroundColor Gray

    Write-Section "[7/8] Waiting for execution result..."

    for ($i = 0; $i -lt 60; $i++) {
        $status = Invoke-ProxmoxRequest -Method Get -Path "/nodes/$NodeName/qemu/$VMID/agent/exec-status?pid=$execPid"
        if ($status.data.exited -eq $true) {
            $exitCode = $status.data.exitcode
            $commandComplete = $true

            if ($status.data."out-data") {
                $stdOut = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($status.data."out-data"))
            }
            if ($status.data."err-data") {
                $stdErr = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($status.data."err-data"))
            }

            break
        }

        Start-Sleep -Seconds 3
}
else {
    Write-Section "[7/8] Collecting execution result..."
    try {
        $remoteOutput = Invoke-Command -Session $winRMSession -ScriptBlock {
            param($encoded)
            powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
        } -ArgumentList $vmScriptEncoded

        $commandComplete = $true
        if ($remoteOutput) {
            $stdOut = ($remoteOutput | Out-String).Trim()
            if ($stdOut) {
                try {
                    $resultJson = $stdOut | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    # keep raw stdout only
                }
            }
        }
    catch {
        throw "WinRM execution failed: $($_.Exception.Message)"
}

if ($serveJob) {
    Stop-Job -Job $serveJob -Force -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $serveJob -ErrorAction SilentlyContinue
}

if ($exitCode -ne $null) {
    Write-Host "Exit code: $exitCode" -ForegroundColor Gray
}
elseif ($commandComplete) {
    Write-Host "Warning: execution completed but exit code was not reported." -ForegroundColor Yellow
}
else {
    Write-Host "Warning: exec-status did not report completion within timeout." -ForegroundColor Yellow
}

if ($stdOut) {
    try {
        $resultJson = $stdOut | ConvertFrom-Json -ErrorAction Stop
        if ($resultJson -and $resultJson.PSObject.Properties.Name -contains "ExitCode") {
            $exitCode = $resultJson.ExitCode
        }
    catch {
        Write-Host "STDOUT (non-JSON):" -ForegroundColor Yellow
        Write-Host $stdOut -ForegroundColor DarkGray
}

if ($stdErr) {
    Write-Host "STDERR:" -ForegroundColor Yellow
    Write-Host $stdErr -ForegroundColor DarkGray
}

# Close WinRM session if opened
if ($winRMSession) {
    Remove-PSSession -Session $winRMSession -ErrorAction SilentlyContinue
    $winRMSession = $null
}

# Optional shutdown
if ($ShutdownVM) {
    Write-Section "[8/8] Shutting down VM..."
    try {
        Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/status/shutdown" | Out-Null
        Write-Host "Shutdown requested" -ForegroundColor Green
    catch {
        Write-Host "Failed to shut down VM: $($_.Exception.Message)" -ForegroundColor Yellow
}
else {
    Write-Section "[8/8] Leaving VM running (use -ShutdownVM to stop automatically)."
}

Write-Section "=== Execution Summary ===" ([ConsoleColor]::Cyan)
Write-Host "Executable: $Executable" -ForegroundColor Gray
Write-Host "Arguments:  $Arguments" -ForegroundColor Gray
$resolvedExit = if ($resultJson -and $resultJson.PSObject.Properties.Name -contains "ExitCode") {
    $resultJson.ExitCode
}
elseif ($exitCode -ne $null) {
    $exitCode
}
else {
    "unknown"
}
Write-Host ("Exit code:  {0}" -f $resolvedExit) -ForegroundColor Gray

if ($resultJson -and $resultJson.StdOut) {
    Write-Host "`nCaptured STDOUT:" -ForegroundColor White
    Write-Host $resultJson.StdOut -ForegroundColor DarkGray
}

if ($resultJson -and $resultJson.StdErr) {
    Write-Host "`nCaptured STDERR:" -ForegroundColor Yellow
    Write-Host $resultJson.StdErr -ForegroundColor DarkGray
}

Write-Host "`nPipeline complete." -ForegroundColor Green

if ($resultJson) {
    return $resultJson
}

return [PSCustomObject]@{
    StdOut     = $stdOut
    StdErr     = $stdErr
    ExitCode   = $exitCode
    Executable = $Executable
    Arguments  = $Arguments
}
) }
    $queryString = $queryArgs -join "&"
    $execPath = "/nodes/$NodeName/qemu/$VMID/agent/exec?command=powershell.exe"
    if ($queryString) {
        $execPath += "&$queryString"
    }

    $execResponse = Invoke-ProxmoxRequest -Method Post -Path $execPath
    $execPid = $execResponse.data.pid
    Write-Host "Guest exec PID: $execPid" -ForegroundColor Gray

    Write-Section "[7/8] Waiting for execution result..."
    for ($i = 0; $i -lt 60; $i++) {
        $status = Invoke-ProxmoxRequest -Method Get -Path "/nodes/$NodeName/qemu/$VMID/agent/exec-status?pid=$execPid"
        if ($status.data.exited -eq $true) {
            $exitCode = $status.data.exitcode
            $commandComplete = $true

            if ($status.data."out-data") {
                $stdOut = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($status.data."out-data"))
            }
            if ($status.data."err-data") {
                $stdErr = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($status.data."err-data"))
            }

            break
        }

        Start-Sleep -Seconds 3
    }
}
else {

    Write-Section "[7/8] Collecting execution result..."
    try {
        $remoteOutput = Invoke-Command -Session $winRMSession -ScriptBlock {
            param($encoded)
            powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
        } -ArgumentList $vmScriptEncoded

        $commandComplete = $true
        if ($remoteOutput) {
            $stdOut = ($remoteOutput | Out-String).Trim()
            if ($stdOut) {
                try {
                    $resultJson = $stdOut | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    # keep raw stdout only
                }
            }
        }
    catch {
        throw "WinRM execution failed: $($_.Exception.Message)"
}

if ($serveJob) {
    Stop-Job -Job $serveJob -Force -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $serveJob -ErrorAction SilentlyContinue
}

if ($exitCode -ne $null) {
    Write-Host "Exit code: $exitCode" -ForegroundColor Gray
}
elseif ($commandComplete) {
    Write-Host "Warning: execution completed but exit code was not reported." -ForegroundColor Yellow
}
else {
    Write-Host "Warning: exec-status did not report completion within timeout." -ForegroundColor Yellow
}

if ($stdOut) {
    try {
        $resultJson = $stdOut | ConvertFrom-Json -ErrorAction Stop
        if ($resultJson -and $resultJson.PSObject.Properties.Name -contains "ExitCode") {
            $exitCode = $resultJson.ExitCode
        }
    catch {
        Write-Host "STDOUT (non-JSON):" -ForegroundColor Yellow
        Write-Host $stdOut -ForegroundColor DarkGray
}

if ($stdErr) {
    Write-Host "STDERR:" -ForegroundColor Yellow
    Write-Host $stdErr -ForegroundColor DarkGray
}

# Close WinRM session if opened
if ($winRMSession) {
    Remove-PSSession -Session $winRMSession -ErrorAction SilentlyContinue
    $winRMSession = $null
}

# Optional shutdown
if ($ShutdownVM) {
    Write-Section "[8/8] Shutting down VM..."
    try {
        Invoke-ProxmoxRequest -Method Post -Path "/nodes/$NodeName/qemu/$VMID/status/shutdown" | Out-Null
        Write-Host "Shutdown requested" -ForegroundColor Green
    catch {
        Write-Host "Failed to shut down VM: $($_.Exception.Message)" -ForegroundColor Yellow
}
else {
    Write-Section "[8/8] Leaving VM running (use -ShutdownVM to stop automatically)."
}

Write-Section "=== Execution Summary ===" ([ConsoleColor]::Cyan)
Write-Host "Executable: $Executable" -ForegroundColor Gray
Write-Host "Arguments:  $Arguments" -ForegroundColor Gray
$resolvedExit = if ($resultJson -and $resultJson.PSObject.Properties.Name -contains "ExitCode") {
    $resultJson.ExitCode
}
elseif ($exitCode -ne $null) {
    $exitCode
}
else {
    "unknown"
}
Write-Host ("Exit code:  {0}" -f $resolvedExit) -ForegroundColor Gray

if ($resultJson -and $resultJson.StdOut) {
    Write-Host "`nCaptured STDOUT:" -ForegroundColor White
    Write-Host $resultJson.StdOut -ForegroundColor DarkGray
}

if ($resultJson -and $resultJson.StdErr) {
    Write-Host "`nCaptured STDERR:" -ForegroundColor Yellow
    Write-Host $resultJson.StdErr -ForegroundColor DarkGray
}

Write-Host "`nPipeline complete." -ForegroundColor Green

if ($resultJson) {
    return $resultJson
}

return [PSCustomObject]@{
    StdOut     = $stdOut
    StdErr     = $stdErr
    ExitCode   = $exitCode
    Executable = $Executable
    Arguments  = $Arguments
}
