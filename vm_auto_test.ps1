# Auto-test script downloaded from the developer machine
$ErrorActionPreference = 'Continue'

$dest = 'C:\PrivacyFirstTest'
$repoUser = 'christianshub'
$repoName = 'privacyfirst'
$repoBranch = 'main'
$downloadBase = 'https://raw.githubusercontent.com/christianshub/privacyfirst/main/x64/Release'
$callbackUrl = 'http://192.168.0.137:9050/result'

Write-Host '=== PrivacyFirst VM Auto-Test ===' -ForegroundColor Cyan
Write-Host "Repository: $repoUser/$repoName ($repoBranch)" -ForegroundColor Gray
Write-Host "Artifact source: $downloadBase" -ForegroundColor Gray

if (-not (Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Write-Host "Created directory $dest" -ForegroundColor Yellow
}

$files = @('PrivacyFirst.exe','PrivacyFirst.dll','PrivacyCore.dll','PrivacyFirst.deps.json','PrivacyFirst.runtimeconfig.json')
$downloads = @()

Write-Host "
[1/4] Downloading artifacts..." -ForegroundColor Yellow
foreach ($file in $files) {
    $entry = [ordered]@{
        file = $file
        success = $false
        error = $null
    }

    try {
        Invoke-WebRequest -Uri "$downloadBase/$file" -OutFile (Join-Path $dest $file) -UseBasicParsing -ErrorAction Stop
        $entry.success = $true
        Write-Host "  [OK] $file" -ForegroundColor Green
    }
    catch {
        $entry.error = $_.Exception.Message
        Write-Host "  [FAIL] $file - $($entry.error)" -ForegroundColor Red
    }

    $downloads += $entry
}

function Get-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        (Get-ItemProperty -Path "Registry::$Path" -Name $Name -ErrorAction Stop).$Name
    }
    catch {
        $null
    }
}

Write-Host "
[2/4] Capturing registry state..." -ForegroundColor Yellow
$initialState = [ordered]@{
    MachineGuid = Get-RegistryValue "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography" "MachineGuid"
    HwProfileGuid = Get-RegistryValue "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001" "HwProfileGuid"
}

Write-Host "  MachineGuid: $($initialState.MachineGuid)" -ForegroundColor Gray
Write-Host "  HwProfileGuid: $($initialState.HwProfileGuid)" -ForegroundColor Gray

Write-Host "
[3/4] Building test results..." -ForegroundColor Yellow
$tests = @()

$tests += [ordered]@{
    name = 'Artifact Download'
    success = (($downloads | Where-Object { -not $_.success }).Count -eq 0)
    details = $downloads
}

$tests += [ordered]@{
    name = 'Registry State Captured'
    success = (-not [string]::IsNullOrEmpty($initialState.MachineGuid))
    details = $initialState
}

$resultsObject = [ordered]@{
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    hostname = $env:COMPUTERNAME
    repo = "$repoUser/$repoName"
    branch = $repoBranch
    downloadPath = $dest
    downloads = $downloads
    tests = $tests
    initialState = $initialState
}

$reportBuilder = New-Object System.Text.StringBuilder
[void]$reportBuilder.AppendLine('=== PrivacyFirst Automated Test Report ===')
[void]$reportBuilder.AppendLine("Timestamp: $($resultsObject.timestamp)")
[void]$reportBuilder.AppendLine("Hostname: $($resultsObject.hostname)")
[void]$reportBuilder.AppendLine("Repository: $repoUser/$repoName ($repoBranch)")
[void]$reportBuilder.AppendLine('')
[void]$reportBuilder.AppendLine('Downloads:')
foreach ($download in $downloads) {
    $status = if ($download.success) { 'OK' } else { 'FAIL' }
    [void]$reportBuilder.AppendLine("  [$status] $($download.file)")
    if (-not $download.success -and $download.error) {
        [void]$reportBuilder.AppendLine("         -> $($download.error)")
    }
}
[void]$reportBuilder.AppendLine('')
[void]$reportBuilder.AppendLine('Initial Registry State:')
[void]$reportBuilder.AppendLine("  MachineGuid: $($initialState.MachineGuid)")
[void]$reportBuilder.AppendLine("  HwProfileGuid: $($initialState.HwProfileGuid)")
[void]$reportBuilder.AppendLine('')
[void]$reportBuilder.AppendLine('Tests:')
foreach ($test in $tests) {
    $status = if ($test.success) { 'PASS' } else { 'FAIL' }
    [void]$reportBuilder.AppendLine("  [$status] $($test.name)")
}

$reportText = $reportBuilder.ToString()
$reportPath = Join-Path $dest 'test_report.txt'
$jsonPath = Join-Path $dest 'test_results.json'

Write-Host "
[4/4] Saving results..." -ForegroundColor Yellow
$reportText | Out-File -FilePath $reportPath -Encoding UTF8
$resultsObject | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host "
=== Test Summary ===" -ForegroundColor Cyan
Write-Host $reportText
Write-Host "Report saved to: $reportPath" -ForegroundColor Gray
Write-Host "JSON results saved to: $jsonPath" -ForegroundColor Gray

Write-Host "
Sending callback to $callbackUrl..." -ForegroundColor Yellow
$payload = @{
    report = $reportText
    results = $resultsObject
} | ConvertTo-Json -Depth 10

try {
    Invoke-WebRequest -Uri $callbackUrl -Method Post -ContentType 'application/json' -Body $payload -UseBasicParsing | Out-Null
    Write-Host 'Results sent to callback server' -ForegroundColor Green
}
catch {
    Write-Host "Failed to send callback: $($_.Exception.Message)" -ForegroundColor Yellow
}
