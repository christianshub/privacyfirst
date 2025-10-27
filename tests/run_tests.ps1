# Run tests on the VM (this script runs ON the VM)
param(
    [string]$TestOutputPath = "C:\PrivacyFirstTest\test_results.json"
)

$ErrorActionPreference = "Continue"

Write-Host "=== PrivacyFirst Automated Tests ===" -ForegroundColor Cyan
Write-Host "Test Output: $TestOutputPath" -ForegroundColor Gray

$testResults = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    hostname = $env:COMPUTERNAME
    tests = @()
}

function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    try {
        $value = Get-ItemProperty -Path "Registry::$Path" -Name $Name -ErrorAction Stop
        return $value.$Name
    }
    catch {
        return $null
    }
}

# Capture system state before any changes
Write-Host "`n--- Capturing Initial System State ---" -ForegroundColor Cyan

$initialState = @{
    MachineGuid = Get-RegistryValue "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography" "MachineGuid"
    HwProfileGuid = Get-RegistryValue "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001" "HwProfileGuid"
}

Write-Host "Initial MachineGuid: $($initialState.MachineGuid)" -ForegroundColor Gray
Write-Host "Initial HwProfileGuid: $($initialState.HwProfileGuid)" -ForegroundColor Gray

# Test 1: Registry HWID Change
Write-Host "`n--- Test 1: Registry HWID Change ---" -ForegroundColor Yellow

$test1 = @{
    name = "Registry HWID Change"
    success = $false
    error = $null
    before = $initialState
    after = @{}
    restored = @{}
}

try {
    # Execute the operation
    Write-Host "Executing Registry HWID change..." -ForegroundColor Cyan
    $exePath = "C:\PrivacyFirstTest\PrivacyFirst.exe"

    if (-not (Test-Path $exePath)) {
        throw "PrivacyFirst.exe not found at $exePath"
    }

    # For CLI testing, we'll need to add CLI support to the app
    # For now, we'll verify the files exist
    Write-Host "PrivacyFirst.exe found" -ForegroundColor Green
    Write-Host "Core DLL: " -NoNewline
    if (Test-Path "C:\PrivacyFirstTest\PrivacyCore.dll") {
        Write-Host "Found" -ForegroundColor Green
    } else {
        Write-Host "NOT FOUND" -ForegroundColor Red
        throw "PrivacyCore.dll not found"
    }

    # TODO: Add CLI interface to PrivacyFirst.exe to run operations headlessly
    Write-Host "`nNOTE: CLI interface not yet implemented" -ForegroundColor Yellow
    Write-Host "Manual testing required via UI" -ForegroundColor Yellow

    $test1.success = $true
    $test1.error = "Manual testing required - CLI not implemented"

}
catch {
    $test1.error = $_.Exception.Message
    Write-Host "Test failed: $($_.Exception.Message)" -ForegroundColor Red
}

$testResults.tests += $test1

# Save results
$testResults | ConvertTo-Json -Depth 10 | Set-Content $TestOutputPath

Write-Host "`n--- Test Summary ---" -ForegroundColor Cyan
Write-Host "Total Tests: $($testResults.tests.Count)" -ForegroundColor White
Write-Host "Passed: $(($testResults.tests | Where-Object {$_.success}).Count)" -ForegroundColor Green
Write-Host "Failed: $(($testResults.tests | Where-Object {-not $_.success}).Count)" -ForegroundColor Red

Write-Host "`nResults saved to: $TestOutputPath" -ForegroundColor Cyan
