param(
    [string]$InstallerName = "PrivacyFirst-Setup.exe",
    [string]$InstallArguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART",
    [string]$InstallDirectory = "C:\Program Files\PrivacyFirst",
    [int]$LaunchWaitSeconds = 15
)

$ErrorActionPreference = 'Stop'
$logs = New-Object System.Collections.Generic.List[string]

function Add-Log([string]$Message) {
    $logs.Add([string]::Format("[{0}] {1}", (Get-Date -Format o), $Message))
}

$appProc = $null
$installProc = $null

$result = [ordered]@{
    InstallerPath       = $null
    InstallerExitCode   = $null
    InstallArgs         = $InstallArguments
    ApplicationPath     = $null
    ApplicationStarted  = $false
    ApplicationExitCode = $null
    ApplicationStdOut   = ""
    ApplicationStdErr   = ""
    StillRunning        = $false
    ExitCode            = $null
    StdOut              = ""
    StdErr              = ""
    Error               = $null
}

try {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $installerPath = Join-Path $scriptRoot $InstallerName
    $result.InstallerPath = $installerPath
    if (-not (Test-Path $installerPath)) {
        throw "Installer not found at $installerPath"
    }

    Add-Log "Starting installer $installerPath with arguments: $InstallArguments"
    $installProc = Start-Process -FilePath $installerPath -ArgumentList $InstallArguments -Wait -PassThru
    $result.InstallerExitCode = $installProc.ExitCode
    Add-Log "Installer completed with exit code $($installProc.ExitCode)"
    if ($installProc.ExitCode -ne 0) {
        throw "Installer exited with code $($installProc.ExitCode)"
    }

    $exePath = Join-Path $InstallDirectory "PrivacyFirst.exe"
    $result.ApplicationPath = $exePath
    if (-not (Test-Path $exePath)) {
        throw "Installed executable not found at $exePath"
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exePath
    $psi.WorkingDirectory = $InstallDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    Add-Log "Launching installed application $exePath"
    $appProc = [System.Diagnostics.Process]::Start($psi)
    $result.ApplicationStarted = $true

    Start-Sleep -Seconds ([Math]::Max(0, $LaunchWaitSeconds))

    $running = $false
    try {
        $running = -not $appProc.HasExited
    } catch {
        $running = $false
    }

    if ($running) {
        Add-Log "Application still running after wait; attempting graceful close."
        $null = $appProc.CloseMainWindow()
        Start-Sleep -Seconds 5
        try {
            $running = -not $appProc.HasExited
        } catch {
            $running = $false
        }
        if ($running) {
            Add-Log "Application still running; forcing termination."
            $appProc.Kill()
            $appProc.WaitForExit()
            $running = $false
        }
    }

    $stdout = ""
    $stderr = ""
    try { $stdout = $appProc.StandardOutput.ReadToEnd() } catch { }
    try { $stderr = $appProc.StandardError.ReadToEnd() } catch { }
    $result.ApplicationStdOut = $stdout
    $result.ApplicationStdErr = $stderr

    try {
        $appProc.WaitForExit()
        $result.ApplicationExitCode = $appProc.ExitCode
    } catch {
        $result.ApplicationExitCode = -1
    }

    $result.StillRunning = $running
    Add-Log "Application exit code: $($result.ApplicationExitCode)"
    $result.ExitCode = $result.ApplicationExitCode
    $result.StdOut = $result.ApplicationStdOut
    $result.StdErr = $result.ApplicationStdErr
}
catch {
    $result.Error = $_.Exception.Message
    Add-Log "Error occurred: $($result.Error)"
    if (-not $result.ExitCode) { $result.ExitCode = -1 }
    if (-not $result.StdErr) { $result.StdErr = $result.Error }
}
finally {
    if ($appProc) {
        try { $appProc.Dispose() } catch { }
    }
    $result.Logs = $logs
    $json = $result | ConvertTo-Json -Depth 6
    Write-Output $json
}
