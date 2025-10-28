# Requires elevation.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AutoLogonUser,

    [Parameter(Mandatory = $false)]
    [SecureString]$AutoLogonPassword,

    [string]$AutoLogonDomain = $env:COMPUTERNAME,

    [switch]$EnableWinRM
)

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function ConvertTo-PlainText {
    param([SecureString]$SecureString)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Ensure-Administrator {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "This script must be run from an elevated PowerShell session."
    }
}

function Ensure-AutoLogon {
    param(
        [string]$User,
        [SecureString]$Password,
        [string]$Domain
    )

    Write-Section "Configuring Auto-Logon"

    if (-not $Password) {
        $Password = Read-Host -Prompt "Enter password for $Domain\$User" -AsSecureString
    }

    $plainPassword = ConvertTo-PlainText -SecureString $Password

    $winlogonKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $winlogonKey -Name "AutoAdminLogon" -Value "1" -Type String
    Set-ItemProperty -Path $winlogonKey -Name "DefaultUserName" -Value $User -Type String
    Set-ItemProperty -Path $winlogonKey -Name "DefaultPassword" -Value $plainPassword -Type String
    Set-ItemProperty -Path $winlogonKey -Name "DefaultDomainName" -Value $Domain -Type String

    Write-Host "Auto-logon configured for $Domain\$User" -ForegroundColor Green
    Write-Host "NOTE: The password is stored in plain text under $winlogonKey." -ForegroundColor Yellow
}

function Ensure-OpenSSHServer {
    Write-Section "Installing OpenSSH Server"

    $capabilityName = "OpenSSH.Server~~~~0.0.1.0"
    $capability = Get-WindowsCapability -Online -Name $capabilityName
    if ($capability.State -ne "Installed") {
        Write-Host "Installing $capabilityName ..." -ForegroundColor Yellow
        Add-WindowsCapability -Online -Name $capabilityName | Out-Null
    }
    else {
        Write-Host "OpenSSH Server already installed." -ForegroundColor Green
    }

    Write-Section "Configuring sshd service"
    Set-Service -Name "sshd" -StartupType Automatic
    if ((Get-Service -Name "sshd").Status -ne "Running") {
        Start-Service -Name "sshd"
    }
    Write-Host "sshd service is running and set to Automatic." -ForegroundColor Green

    Write-Section "Configuring firewall rule for SSH"
    $ruleName = "OpenSSH-Server-In-TCP"
    $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($rule) {
        if ($rule.Enabled -ne "True") {
            Enable-NetFirewallRule -Name $ruleName
        }
    }
    else {
        New-NetFirewallRule -Name $ruleName `
            -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22 | Out-Null
    }
    Write-Host "Firewall rule for SSH ensured." -ForegroundColor Green
}

function Ensure-WinRM {
    Write-Section "Configuring WinRM"
    Enable-PSRemoting -Force
    winrm set winrm/config/service @{AllowUnencrypted="true"} | Out-Null
    winrm set winrm/config/service/auth @{Basic="true"} | Out-Null
    Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -Enabled True | Out-Null
    Write-Host "WinRM configured (allow unencrypted/basic auth, firewall rule enabled)." -ForegroundColor Green
}

try {
    Ensure-Administrator

    Ensure-AutoLogon -User $AutoLogonUser -Password $AutoLogonPassword -Domain $AutoLogonDomain
    Ensure-OpenSSHServer

    if ($EnableWinRM) {
        Ensure-WinRM
    }

    Write-Section "Configuration completed"
    Write-Host "Reboot the VM to verify auto-logon and SSH availability." -ForegroundColor Cyan
}
catch {
    Write-Error $_
    exit 1
}
