# PrivacyFirst automated testing with HTTP callback
# Starts a lightweight callback server, serves a VM script, and captures posted test results

param(
    [int]$CallbackPort = 9000,
    [string]$GitHubUser = "christianshub",
    [string]$RepoName = "privacyfirst",
    [string]$Branch = "main",
    [string]$ResultsDirectory = ".\callback_results"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-LocalLanIp {
    $ip = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" -or $_.IPAddress -like "172.16.*" } |
        Select-Object -First 1 -ExpandProperty IPAddress

    if (-not $ip) {
        throw "Unable to determine LAN IPv4 address. Please specify manually or ensure you are connected to the VM network."
    }

    return $ip
}

function Ensure-Directory($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

function Get-SafeFileName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "unknown"
    }

    return ($Name -replace '[^a-zA-Z0-9\.\-_]', "_")
}

$localIP = Get-LocalLanIp
Ensure-Directory -path $ResultsDirectory

Write-Host "=== PrivacyFirst Auto-Test with Callback ===" -ForegroundColor Cyan
Write-Host "Local callback URL: http://${localIP}:${CallbackPort}" -ForegroundColor Gray
Write-Host "Results directory:  $ResultsDirectory" -ForegroundColor Gray
Write-Host ""

# Prepare HTTP listener
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://+:${CallbackPort}/")

try {
    $listener.Start()
}
catch {
    throw "Failed to start HTTP listener on port $CallbackPort. Run PowerShell as Administrator or free the port. Error: $($_.Exception.Message)"
}

Write-Host "[1/4] HTTP callback server started on port $CallbackPort" -ForegroundColor Green
# Generate the VM execution script
$vmScript = @"
# Auto-test script downloaded from the developer machine
`$ErrorActionPreference = 'Continue'

`$dest = 'C:\PrivacyFirstTest'
`$repoUser = '$GitHubUser'
`$repoName = '$RepoName'
`$repoBranch = '$Branch'
`$downloadBase = 'https://raw.githubusercontent.com/$GitHubUser/$RepoName/$Branch/x64/Release'
`$callbackUrl = 'http://${localIP}:${CallbackPort}/result'

Write-Host '=== PrivacyFirst VM Auto-Test ===' -ForegroundColor Cyan
Write-Host "Repository: `$repoUser/`$repoName (`$repoBranch)" -ForegroundColor Gray
Write-Host "Artifact source: `$downloadBase" -ForegroundColor Gray

if (-not (Test-Path `$dest)) {
    New-Item -ItemType Directory -Path `$dest -Force | Out-Null
    Write-Host "Created directory `$dest" -ForegroundColor Yellow
}

`$files = @('PrivacyFirst.exe','PrivacyFirst.dll','PrivacyCore.dll','PrivacyFirst.deps.json','PrivacyFirst.runtimeconfig.json')
`$downloads = @()

Write-Host "`n[1/4] Downloading artifacts..." -ForegroundColor Yellow
foreach (`$file in `$files) {
    `$entry = [ordered]@{
        file = `$file
        success = `$false
        error = `$null
    }

    try {
        Invoke-WebRequest -Uri "`$downloadBase/`$file" -OutFile (Join-Path `$dest `$file) -UseBasicParsing -ErrorAction Stop
        `$entry.success = `$true
        Write-Host "  [OK] `$file" -ForegroundColor Green
    }
    catch {
        `$entry.error = `$_.Exception.Message
        Write-Host "  [FAIL] `$file - `$(`$entry.error)" -ForegroundColor Red
    }

    `$downloads += `$entry
}

function Get-RegistryValue {
    param(
        [string]`$Path,
        [string]`$Name
    )

    try {
        (Get-ItemProperty -Path "Registry::`$Path" -Name `$Name -ErrorAction Stop).`$Name
    }
    catch {
        `$null
    }
}

Write-Host "`n[2/4] Capturing registry state..." -ForegroundColor Yellow
`$initialState = [ordered]@{
    MachineGuid = Get-RegistryValue "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography" "MachineGuid"
    HwProfileGuid = Get-RegistryValue "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001" "HwProfileGuid"
}

Write-Host "  MachineGuid: `$(`$initialState.MachineGuid)" -ForegroundColor Gray
Write-Host "  HwProfileGuid: `$(`$initialState.HwProfileGuid)" -ForegroundColor Gray

Write-Host "`n[3/4] Building test results..." -ForegroundColor Yellow
`$tests = @()

`$tests += [ordered]@{
    name = 'Artifact Download'
    success = ((`$downloads | Where-Object { -not `$_.success }).Count -eq 0)
    details = `$downloads
}

`$tests += [ordered]@{
    name = 'Registry State Captured'
    success = (-not [string]::IsNullOrEmpty(`$initialState.MachineGuid))
    details = `$initialState
}

`$resultsObject = [ordered]@{
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    hostname = `$env:COMPUTERNAME
    repo = "`$repoUser/`$repoName"
    branch = `$repoBranch
    downloadPath = `$dest
    downloads = `$downloads
    tests = `$tests
    initialState = `$initialState
}

`$reportBuilder = New-Object System.Text.StringBuilder
[void]`$reportBuilder.AppendLine('=== PrivacyFirst Automated Test Report ===')
[void]`$reportBuilder.AppendLine("Timestamp: `$(`$resultsObject.timestamp)")
[void]`$reportBuilder.AppendLine("Hostname: `$(`$resultsObject.hostname)")
[void]`$reportBuilder.AppendLine("Repository: `$repoUser/`$repoName (`$repoBranch)")
[void]`$reportBuilder.AppendLine('')
[void]`$reportBuilder.AppendLine('Downloads:')
foreach (`$download in `$downloads) {
    `$status = if (`$download.success) { 'OK' } else { 'FAIL' }
    [void]`$reportBuilder.AppendLine("  [`$status] `$(`$download.file)")
    if (-not `$download.success -and `$download.error) {
        [void]`$reportBuilder.AppendLine("         -> `$(`$download.error)")
    }
}
[void]`$reportBuilder.AppendLine('')
[void]`$reportBuilder.AppendLine('Initial Registry State:')
[void]`$reportBuilder.AppendLine("  MachineGuid: `$(`$initialState.MachineGuid)")
[void]`$reportBuilder.AppendLine("  HwProfileGuid: `$(`$initialState.HwProfileGuid)")
[void]`$reportBuilder.AppendLine('')
[void]`$reportBuilder.AppendLine('Tests:')
foreach (`$test in `$tests) {
    `$status = if (`$test.success) { 'PASS' } else { 'FAIL' }
    [void]`$reportBuilder.AppendLine("  [`$status] `$(`$test.name)")
}

`$reportText = `$reportBuilder.ToString()
`$reportPath = Join-Path `$dest 'test_report.txt'
`$jsonPath = Join-Path `$dest 'test_results.json'

Write-Host "`n[4/4] Saving results..." -ForegroundColor Yellow
`$reportText | Out-File -FilePath `$reportPath -Encoding UTF8
`$resultsObject | ConvertTo-Json -Depth 10 | Out-File -FilePath `$jsonPath -Encoding UTF8

Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host `$reportText
Write-Host "Report saved to: `$reportPath" -ForegroundColor Gray
Write-Host "JSON results saved to: `$jsonPath" -ForegroundColor Gray

Write-Host "`nSending callback to `$callbackUrl..." -ForegroundColor Yellow
`$payload = @{
    report = `$reportText
    results = `$resultsObject
} | ConvertTo-Json -Depth 10

try {
    Invoke-WebRequest -Uri `$callbackUrl -Method Post -ContentType 'application/json' -Body `$payload -UseBasicParsing | Out-Null
    Write-Host 'Results sent to callback server' -ForegroundColor Green
}
catch {
    Write-Host "Failed to send callback: `$(`$_.Exception.Message)" -ForegroundColor Yellow
}
"@
# Persist the generated script for reference / offline transfer
$vmScriptPath = Join-Path (Get-Location) "vm_auto_test.ps1"
$vmScript | Out-File -FilePath $vmScriptPath -Encoding UTF8

Write-Host "[2/4] VM test script written to: $vmScriptPath" -ForegroundColor Green
Write-Host ""
Write-Host "To run on the VM, execute the following in an elevated PowerShell prompt:" -ForegroundColor Cyan
Write-Host "  irm http://${localIP}:${CallbackPort}/script | iex" -ForegroundColor White
Write-Host ""
Write-Host "[3/4] Waiting for VM to download script and post results..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop the callback server after testing." -ForegroundColor Gray
Write-Host ""

function Send-Response {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$Body,
        [int]$StatusCode = 200,
        [string]$ContentType = "text/plain"
    )

    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.AbsolutePath.ToLowerInvariant()
        $method = $request.HttpMethod.ToUpperInvariant()

        if ($path -eq "/script" -and $method -eq "GET") {
            Send-Response -Response $response -Body $vmScript -ContentType "text/plain"
            Write-Host "[VM] Script downloaded (${($request.RemoteEndPoint)})" -ForegroundColor Cyan
            continue
        }

        if ($path -eq "/result" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $payload = $reader.ReadToEnd()
            $reader.Close()

            Send-Response -Response $response -Body "OK" -ContentType "text/plain"

            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $rawFile = Join-Path $ResultsDirectory "$timestamp-raw.json"
            $payload | Out-File -FilePath $rawFile -Encoding UTF8

            $parsed = $null
            try {
                $parsed = $payload | ConvertFrom-Json -Depth 10
            }
            catch {
                Write-Host "[VM] Received callback but failed to parse JSON: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host $payload
                Write-Host ""
                continue
            }

            $results = $parsed.results
            $reportText = $parsed.report
            $hostName = Get-SafeFileName ($results.hostname)
            $jsonFile = Join-Path $ResultsDirectory "$timestamp-$hostName.json"
            $txtFile = Join-Path $ResultsDirectory "$timestamp-$hostName-report.txt"

            $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -Encoding UTF8
            if ($reportText) {
                $reportText | Out-File -FilePath $txtFile -Encoding UTF8
            }

            $tests = @()
            if ($results.tests -is [System.Collections.IEnumerable]) {
                $tests = @($results.tests)
            }

            $pass = ($tests | Where-Object { $_.success }).Count
            $fail = ($tests | Where-Object { -not $_.success }).Count

            Write-Host ""
            Write-Host "=== RESULTS RECEIVED FROM VM ===" -ForegroundColor Green
            Write-Host "Host:        $($results.hostname)" -ForegroundColor White
            Write-Host "Timestamp:   $($results.timestamp)" -ForegroundColor White
            Write-Host "Repo:        $($results.repo) [$($results.branch)]" -ForegroundColor White
            Write-Host "Downloads:   $(($results.downloads | Measure-Object).Count) files" -ForegroundColor White
            Write-Host "Tests:       $pass passed / $fail failed" -ForegroundColor White
            Write-Host ""
            if ($reportText) {
                Write-Host $reportText -ForegroundColor Gray
            }
            Write-Host ""
            Write-Host "Saved JSON:   $jsonFile" -ForegroundColor Gray
            Write-Host "Saved report: $txtFile" -ForegroundColor Gray
            Write-Host "================================" -ForegroundColor Green
            Write-Host ""
            continue
        }

        Send-Response -Response $response -Body "Not Found" -StatusCode 404
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
    Write-Host "`nCallback server stopped" -ForegroundColor Gray
}
