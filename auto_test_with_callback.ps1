# Automated test with HTTP callback
# VM downloads from GitHub, runs test, posts results back

param(
    [string]$CallbackPort = 9000,
    [string]$GitHubUser = "christianshub",
    [string]$RepoName = "privacyfirst"
)

# Get local IP
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -like "192.168.*"} | Select-Object -First 1).IPAddress

Write-Host "=== PrivacyFirst Auto-Test with Callback ===" -ForegroundColor Cyan
Write-Host "Callback server: http://${localIP}:${CallbackPort}" -ForegroundColor Gray
Write-Host ""

# Start HTTP listener for callback
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:${CallbackPort}/")
$listener.Start()

Write-Host "[1/3] HTTP callback server started on port $CallbackPort" -ForegroundColor Green

# Generate the VM script with callback
$vmScript = @"
# Auto-test script for VM
`$dest = 'C:\PrivacyFirstTest'
`$githubUrl = 'https://raw.githubusercontent.com/$GitHubUser/$RepoName/main/x64/Release'
`$callbackUrl = 'http://${localIP}:${CallbackPort}/result'

`$report = "=== PrivacyFirst Test Report ===``n"
`$report += "Timestamp: `$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')``n"
`$report += "Hostname: `$env:COMPUTERNAME``n``n"

# Download files
`$report += "Downloading from GitHub...``n"
if (!(Test-Path `$dest)) { mkdir `$dest | Out-Null }

`$files = @('PrivacyFirst.exe','PrivacyFirst.dll','PrivacyCore.dll','PrivacyFirst.deps.json','PrivacyFirst.runtimeconfig.json')
`$downloaded = 0
foreach (`$f in `$files) {
    try {
        Invoke-WebRequest "`$githubUrl/`$f" -OutFile "`$dest\`$f" -UseBasicParsing
        `$report += "  OK: `$f``n"
        `$downloaded++
    } catch {
        `$report += "  FAIL: `$f``n"
    }
}

`$report += "``nDownloaded: `$downloaded/`$(`$files.Count) files``n``n"

# Capture system state
`$report += "System State:``n"
try {
    `$machineGuid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
    `$hwGuid = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001').HwProfileGuid
    `$report += "  MachineGuid: `$machineGuid``n"
    `$report += "  HwProfileGuid: `$hwGuid``n"
} catch {
    `$report += "  ERROR capturing state``n"
}

`$report += "``nFiles location: `$dest``n"
`$report += "``nTest complete! Run PrivacyFirst.exe to test manually.``n"

# Save locally
`$report | Out-File "`$dest\test_report.txt" -Encoding UTF8

# Send callback
try {
    Invoke-WebRequest -Uri `$callbackUrl -Method POST -Body `$report -UseBasicParsing | Out-Null
    Write-Host "Results sent to callback server" -ForegroundColor Green
} catch {
    Write-Host "Failed to send callback (server might not be running)" -ForegroundColor Yellow
}

Write-Host `$report
"@

# Save script
$vmScriptPath = ".\vm_auto_test.ps1"
$vmScript | Out-File $vmScriptPath -Encoding UTF8

Write-Host "[2/3] VM test script ready: $vmScriptPath" -ForegroundColor Green
Write-Host ""
Write-Host "Copy this script to the VM and run it, OR run this one-liner on the VM:" -ForegroundColor Cyan
Write-Host ""
Write-Host "irm http://${localIP}:${CallbackPort}/script | iex" -ForegroundColor White
Write-Host ""
Write-Host "[3/3] Waiting for callback from VM..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop listening" -ForegroundColor Gray
Write-Host ""

# Handle requests
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        if ($request.Url.PathAndQuery -eq "/script") {
            # Serve the script
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($vmScript)
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.OutputStream.Close()

            Write-Host "Script downloaded by VM" -ForegroundColor Cyan
        }
        elseif ($request.Url.PathAndQuery -eq "/result") {
            # Receive results
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $results = $reader.ReadToEnd()
            $reader.Close()

            $response.StatusCode = 200
            $response.OutputStream.Close()

            Write-Host "=== RESULTS RECEIVED FROM VM ===" -ForegroundColor Green
            Write-Host $results -ForegroundColor White
            Write-Host "================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "Test complete! Press Ctrl+C to stop server." -ForegroundColor Cyan

            # Optionally stop after receiving results
            # break
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
    Write-Host "`nCallback server stopped" -ForegroundColor Gray
}
