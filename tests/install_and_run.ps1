param(
    [string]$InstallerName = "PrivacyFirst-Setup.exe",
    [string]$InstallArguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART",
    [string]$InstallDirectory = "C:\Program Files\PrivacyFirst",
    [int]$ApplicationStabilizationSeconds = 15,
    [int]$InstallTimeoutSeconds = 900,
    [int]$InstallPollSeconds = 5,
    [int]$ApplicationCloseTimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$logs = New-Object System.Collections.Generic.List[string]

function Add-Log([string]$Message) {
    $timestamped = "[{0}] {1}" -f (Get-Date -Format o), $Message
    $logs.Add($timestamped)
    Write-Output $timestamped
}

function Wait-ForProcessCompletion {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory)]
        [int]$PollSeconds,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $start = Get-Date
    $timedOut = $false
    while (-not $Process.HasExited) {
        Start-Sleep -Seconds $PollSeconds
        $elapsed = (Get-Date) - $start
        Add-Log ("{0} running... {1:n0}s elapsed" -f $Label, $elapsed.TotalSeconds)
        if ($elapsed.TotalSeconds -ge $TimeoutSeconds) {
            Add-Log ("{0} exceeded timeout ({1}s); attempting termination" -f $Label, $TimeoutSeconds)
            try { $Process.Kill() } catch { Add-Log ("Failed to kill {0}: {1}" -f $Label, $_.Exception.Message) }
            $timedOut = $true
            break
        }
    }

    try {
        $Process.WaitForExit()
    } catch {
        Add-Log ("WaitForExit on {0} threw: {1}" -f $Label, $_.Exception.Message)
    }

    return [PSCustomObject]@{
        TimedOut = $timedOut
        ElapsedSeconds = ((Get-Date) - $start).TotalSeconds
    }
}

$appProc = $null
$installProc = $null

$result = [ordered]@{
    InstallerPath               = $null
    InstallerExitCode           = $null
    InstallArgs                 = $InstallArguments
    InstallerTimedOut           = $false
    InstallerElapsedSeconds     = $null
    ApplicationPath             = $null
    ApplicationStarted          = $false
    ApplicationExitCode         = $null
    ApplicationStdOut           = ""
    ApplicationStdErr           = ""
    StillRunning                = $false
    ExitCode                    = $null
    StdOut                      = ""
    StdErr                      = ""
    Error                       = $null
}

try {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $installerPath = Join-Path $scriptRoot $InstallerName
    $result.InstallerPath = $installerPath
    if (-not (Test-Path $installerPath)) {
        throw "Installer not found at $installerPath"
    }

    Add-Log "Starting installer $installerPath with arguments: $InstallArguments"
    $installProc = Start-Process -FilePath $installerPath -ArgumentList $InstallArguments -PassThru
    $installWait = Wait-ForProcessCompletion -Process $installProc -TimeoutSeconds $InstallTimeoutSeconds -PollSeconds $InstallPollSeconds -Label "Installer"
    $result.InstallerTimedOut = $installWait.TimedOut
    $result.InstallerElapsedSeconds = [math]::Round($installWait.ElapsedSeconds, 2)
    $result.InstallerExitCode = $installProc.ExitCode
    Add-Log ("Installer completed (exit {0}, elapsed {1}s, timedOut={2})" -f $installProc.ExitCode, $result.InstallerElapsedSeconds, $result.InstallerTimedOut)

    if ($result.InstallerTimedOut) {
        throw "Installer exceeded timeout (${InstallTimeoutSeconds}s)"
    }

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

    Add-Log ("Waiting {0}s for application to produce output..." -f $ApplicationStabilizationSeconds)
    Start-Sleep -Seconds ([Math]::Max(0, $ApplicationStabilizationSeconds))

    $running = $false
    try {
        $running = -not $appProc.HasExited
    } catch {
        Add-Log ("Checking HasExited failed: {0}" -f $_.Exception.Message)
        $running = $false
    }

    if ($running) {
        Add-Log "Application still running after stabilization; attempting graceful close."
        try {
            $null = $appProc.CloseMainWindow()
        } catch {
            Add-Log ("CloseMainWindow failed: {0}" -f $_.Exception.Message)
        }

        $closeStart = Get-Date
        while (-not $appProc.HasExited) {
            Start-Sleep -Seconds 5
            if (((Get-Date) - $closeStart).TotalSeconds -ge $ApplicationCloseTimeoutSeconds) {
                Add-Log ("Application failed to exit within {0}s; killing process." -f $ApplicationCloseTimeoutSeconds)
                try { $appProc.Kill() } catch { Add-Log ("Kill failed: {0}" -f $_.Exception.Message) }
                break
            }
        }
    }

    $stdout = ""
    $stderr = ""
    try { $stdout = $appProc.StandardOutput.ReadToEnd() } catch { Add-Log ("Reading stdout failed: {0}" -f $_.Exception.Message) }
    try { $stderr = $appProc.StandardError.ReadToEnd() } catch { Add-Log ("Reading stderr failed: {0}" -f $_.Exception.Message) }
    $result.ApplicationStdOut = $stdout
    $result.ApplicationStdErr = $stderr

    try {
        $appProc.WaitForExit()
        $result.ApplicationExitCode = $appProc.ExitCode
    } catch {
        Add-Log ("WaitForExit on application failed: {0}" -f $_.Exception.Message)
        $result.ApplicationExitCode = -1
    }

    $result.StillRunning = $false
    Add-Log ("Application exit code: {0}" -f $result.ApplicationExitCode)
    $result.ExitCode = $result.ApplicationExitCode
    $result.StdOut = $result.ApplicationStdOut
    $result.StdErr = $result.ApplicationStdErr
}
catch {
    $result.Error = $_.Exception.Message
    Add-Log ("Error occurred: {0}" -f $result.Error)
    if ($result.ExitCode -eq $null) { $result.ExitCode = -1 }
    if (-not $result.StdErr) { $result.StdErr = $result.Error }
}
finally {
    if ($appProc) {
        try { $appProc.Dispose() } catch { }
    }
    if ($installProc) {
        try { $installProc.Dispose() } catch { }
    }

    $result.Logs = $logs
    $json = $result | ConvertTo-Json -Depth 6
    Write-Output $json
}
