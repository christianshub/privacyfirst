# Privacy First tool - OpenVPN Setup with NordVPN
# This script helps set up OpenVPN with NordVPN configuration

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

# Get script directory with multiple fallback methods
$scriptDir = $null
if ($PSScriptRoot) {
    $scriptDir = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
} elseif ($MyInvocation.MyCommand.Definition) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
} else {
    $scriptDir = Get-Location
    Write-Warning "Could not determine script directory. Using current location: $scriptDir"
}

# Debug output for path resolution
Write-Host "Script directory: $scriptDir" -ForegroundColor Magenta

# Configuration - use absolute path construction with fallbacks
$projectRoot = $null
if ($scriptDir) {
    $projectRoot = Split-Path $scriptDir -Parent
} else {
    $projectRoot = Get-Location
}

Write-Host "Project root: $projectRoot" -ForegroundColor Magenta

# Try multiple methods to find the installer
$openVpnInstaller = $null
$possiblePaths = @(
    (Join-Path $projectRoot "tools" "OpenVPN-2.6.14-I001-amd64.msi"),
    (Join-Path (Get-Location) "tools" "OpenVPN-2.6.14-I001-amd64.msi"),
    (Join-Path (Split-Path (Get-Location) -Parent) "tools" "OpenVPN-2.6.14-I001-amd64.msi")
)

foreach ($path in $possiblePaths) {
    if ($path -and (Test-Path $path)) {
        $openVpnInstaller = $path
        break
    }
}

Write-Host "OpenVPN installer path: $openVpnInstaller" -ForegroundColor Magenta

$openVpnInstallPath = "${env:ProgramFiles}\OpenVPN"
$nordVpnApiUrl = "https://api.nordvpn.com/v1"
$nordVpnCredentialsUrl = "https://go.nordvpn.net/affiliate-link-here"

# Set up directories with fallbacks
if ($projectRoot) {
    $configsDir = Join-Path $projectRoot "configs"
    $nordVpnConfigDir = Join-Path $configsDir "nordvpn"
    $nordVpnTemplateFile = Join-Path $projectRoot "templates" "nordvpn_template.ovpn"
    $toolsDir = Join-Path $projectRoot "tools"
} else {
    $configsDir = Join-Path (Get-Location) "configs"
    $nordVpnConfigDir = Join-Path $configsDir "nordvpn"
    $nordVpnTemplateFile = Join-Path (Get-Location) "templates" "nordvpn_template.ovpn"
    $toolsDir = Join-Path (Get-Location) "tools"
}

# Try to find template file in multiple locations
if (-not (Test-Path $nordVpnTemplateFile)) {
    $templateSearchPaths = @(
        "templates\nordvpn_template.ovpn",
        "..\templates\nordvpn_template.ovpn",
        ".\templates\nordvpn_template.ovpn",
        (Join-Path (Get-Location) "templates\nordvpn_template.ovpn"),
        (Join-Path (Split-Path (Get-Location) -Parent) "templates\nordvpn_template.ovpn")
    )
    
    foreach ($path in $templateSearchPaths) {
        if (Test-Path $path) {
            $nordVpnTemplateFile = $path
            Write-Host "Found template file at: $nordVpnTemplateFile" -ForegroundColor Green
            break
        }
    }
}

# Create necessary directories
if (-not (Test-Path $configsDir)) {
    New-Item -ItemType Directory -Path $configsDir -Force | Out-Null
}

if (-not (Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
}

# Dot-source helper for consistent coloured output
$helperPath = $null
if ($scriptDir) {
    $helperPath = Join-Path $scriptDir "PrivacyFirst-Helpers.ps1"
} else {
    $helperPath = Join-Path (Get-Location) "PrivacyFirst-Helpers.ps1"
}

if (Test-Path $helperPath) { . $helperPath }

function Check-OpenVpnInstalled {
    return (Test-Path $openVpnInstallPath)
}

function Install-OpenVpn {
    try {
        Write-Host "Installing OpenVPN automatically..." -ForegroundColor Cyan
        
        # Run the installer directly with visible UI to ensure it works properly
        $process = Start-Process -FilePath $openVpnInstaller -Wait -PassThru
        
        # Give it a moment to finish registration
        Write-Host "Finalizing installation..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        
        if (Check-OpenVpnInstalled) {
            Write-Host "OpenVPN installed successfully!" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "OpenVPN installation not detected." -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "Error running OpenVPN installer: $_" -ForegroundColor Red
        return $false
    }
}

function Get-NordVpnCountries {
    try {
        Write-Host "Fetching available countries from NordVPN..." -ForegroundColor Cyan
        
        # Use TLS 1.2 for the web request
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Create WebClient
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Privacy First")
        
        # Get countries from API
        $countriesJson = $webClient.DownloadString("$nordVpnApiUrl/servers/countries")
        $countries = ConvertFrom-Json $countriesJson | Sort-Object -Property name
        
        Write-Host "Countries fetched successfully!" -ForegroundColor Green
        return $countries
    }
    catch {
        Write-Host "Error fetching countries from NordVPN API: $_" -ForegroundColor Red
        
        # Return a fallback list of common countries as a backup
        Write-Host "Using fallback country list..." -ForegroundColor Yellow
        $fallbackCountries = @(
            @{id = 1; name = "United States"; code = "US"},
            @{id = 2; name = "Canada"; code = "CA"},
            @{id = 3; name = "United Kingdom"; code = "GB"},
            @{id = 4; name = "Germany"; code = "DE"},
            @{id = 5; name = "Netherlands"; code = "NL"},
            @{id = 6; name = "Sweden"; code = "SE"},
            @{id = 7; name = "France"; code = "FR"},
            @{id = 8; name = "Switzerland"; code = "CH"},
            @{id = 9; name = "Singapore"; code = "SG"},
            @{id = 10; name = "Australia"; code = "AU"}
        )
        return $fallbackCountries
    }
}

function Get-NordVpnServers {
    param (
        [int]$CountryId
    )
    
    try {
        Write-Host "Fetching servers for the selected country..." -ForegroundColor Cyan
        
        # Use TLS 1.2 for the web request
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Create WebClient
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Privacy First")
        
        # Get servers from API
        $serversJson = $webClient.DownloadString("$nordVpnApiUrl/servers?filters[country_id]=$CountryId&filters[servers_technologies][identifier]=openvpn_udp")
        $servers = ConvertFrom-Json $serversJson | Sort-Object -Property load  # Sort by lowest load first
        
        Write-Host "Servers fetched successfully!" -ForegroundColor Green
        return $servers
    }
    catch {
        Write-Host "Error fetching servers from NordVPN API: $_" -ForegroundColor Red
        return @()
    }
}

function Create-CustomConfig {
    param (
        [string]$ServerName
    )
    
    # --- BEGIN PrivacyFirst Fix: Ensure CA certificate and TLS-auth key are always embedded ---
    # Static NordVPN CA certificate used for OpenVPN connections
    $caCertBlock = @"
-----BEGIN CERTIFICATE-----
MIIFCjCCAvKgAwIBAgIBATANBgkqhkiG9w0BAQ0FADA5MQswCQYDVQQGEwJQQTEQ
MA4GA1UEChMHTm9yZFZQTjEYMBYGA1UEAxMPTm9yZFZQTiBSb290IENBMB4XDTE2
MDEwMTAwMDAwMFoXDTM1MTIzMTIzNTk1OVowOTELMAkGA1UEBhMCUEExEDAOBgNV
BAoTB05vcmRWUE4xGDAWBgNVBAMTD05vcmRWUE4gUm9vdCBDQTCCAiIwDQYJKoZI
hvcNAQEBBQADggIPADCCAgoCggIBAMkr/BYhyo0F2upsIMXwC6QvkZps3NN2/eQF
kfQIS1gql0aejsKsEnmY0Kaon8uZCTXPsRH1gQNgg5D2gixdd1mJUvV3dE3y9FJr
XMoDkXdCGBodvKJyU6lcfEVF6/UxHcbBguZK9UtRHS9eJYm3rpL/5huQMCppX7kU
eQ8dpCwd3iKITqwd1ZudDqsWaU0vqzC2H55IyaZ/5/TnCk31Q1UP6BksbbuRcwOV
skEDsm6YoWDnn/IIzGOYnFJRzQH5jTz3j1QBvRIuQuBuvUkfhx1FEwhwZigrcxXu
MP+QgM54kezgziJUaZcOM2zF3lvrwMvXDMfNeIoJABv9ljw969xQ8czQCU5lMVmA
37ltv5Ec9U5hZuwk/9QO1Z+d/r6Jx0mlurS8gnCAKJgwa3kyZw6e4FZ8mYL4vpRR
hPdvRTWCMJkeB4yBHyhxUmTRgJHm6YR3D6hcFAc9cQcTEl/I60tMdz33G6m0O42s
Qt/+AR3YCY/RusWVBJB/qNS94EtNtj8iaebCQW1jHAhvGmFILVR9lzD0EzWKHkvy
WEjmUVRgCDd6Ne3eFRNS73gdv/C3l5boYySeu4exkEYVxVRn8DhCxs0MnkMHWFK6
MyzXCCn+JnWFDYPfDKHvpff/kLDobtPBf+Lbch5wQy9quY27xaj0XwLyjOltpiST
LWae/Q4vAgMBAAGjHTAbMAwGA1UdEwQFMAMBAf8wCwYDVR0PBAQDAgEGMA0GCSqG
SIb3DQEBDQUAA4ICAQC9fUL2sZPxIN2mD32VeNySTgZlCEdVmlq471o/bDMP4B8g
nQesFRtXY2ZCjs50Jm73B2LViL9qlREmI6vE5IC8IsRBJSV4ce1WYxyXro5rmVg/
k6a10rlsbK/eg//GHoJxDdXDOokLUSnxt7gk3QKpX6eCdh67p0PuWm/7WUJQxH2S
DxsT9vB/iZriTIEe/ILoOQF0Aqp7AgNCcLcLAmbxXQkXYCCSB35Vp06u+eTWjG0/
pyS5V14stGtw+fA0DJp5ZJV4eqJ5LqxMlYvEZ/qKTEdoCeaXv2QEmN6dVqjDoTAo
k0t5u4YRXzEVCfXAC3ocplNdtCA72wjFJcSbfif4BSC8bDACTXtnPC7nD0VndZLp
+RiNLeiENhk0oTC+UVdSc+n2nJOzkCK0vYu0Ads4JGIB7g8IB3z2t9ICmsWrgnhd
NdcOe15BincrGA8avQ1cWXsfIKEjbrnEuEk9b5jel6NfHtPKoHc9mDpRdNPISeVa
wDBM1mJChneHt59Nh8Gah74+TM1jBsw4fhJPvoc7Atcg740JErb904mZfkIEmojC
VPhBHVQ9LHBAdM8qFI2kRK0IynOmAZhexlP/aT/kpEsEPyaZQlnBn3An1CRz8h0S
PApL8PytggYKeQmRhl499+6jLxcZ2IegLfqq41dzIjwHwTMplg+1pKIOVojpWA==
-----END CERTIFICATE-----
"@

    # Static TLS-auth key used by NordVPN (2048-bit)
    $taKeyBlock = @"
#
# 2048 bit OpenVPN static key
#
-----BEGIN OpenVPN Static key V1-----
e685bdaf659a25a200e2b9e39e51ff03
0fc72cf1ce07232bd8b2be5e6c670143
f51e937e670eee09d4f2ea5a6e4e6996
5db852c275351b86fc4ca892d78ae002
d6f70d029bd79c4d1c26cf14e9588033
cf639f8a74809f29f72b9d58f9b8f5fe
fc7938eade40e9fed6cb92184abb2cc1
0eb1a296df243b251df0643d53724cdb
5a92a1d6cb817804c4a9319b57d53be5
80815bcfcb2df55018cc83fc43bc7ff8
2d51f9b88364776ee9d12fc85cc7ea5b
9741c4f598c485316db066d52db4540e
212e1518a9bd4828219e24b20d88f598
a196c9de96012090e333519ae18d3509
9427e7b372d348d352dc4c85e18cd4b9
3f8a56ddb2e64eb67adfc9b337157ff4
-----END OpenVPN Static key V1-----
"@
    # --- END PrivacyFirst Fix ---

    try {
        # Check if template file exists
        if (-not $nordVpnTemplateFile -or -not (Test-Path $nordVpnTemplateFile)) {
            Write-Host "Template file not found. Creating default NordVPN template..." -ForegroundColor Yellow
            
            # Create optimized template without certificate download
            $defaultTemplate = @"
client
dev tun
proto udp
remote $ServerName 1194
remote-random
nobind

# Force ALL traffic through the VPN
redirect-gateway def1

# Performance & reliability
tun-mtu 1500
mssfix 1450
ping 15
ping-restart 60
reneg-sec 0
comp-lzo no
setenv CLIENT_CERT 0

# Security
auth-user-pass
auth SHA512
cipher AES-256-CBC
data-ciphers AES-256-GCM:AES-256-CBC:AES-128-GCM
remote-cert-tls server

verb 3
pull
fast-io

<ca>
# NordVPN CA certificate will be added automatically
</ca>
key-direction 1
<tls-auth>
# NordVPN TLS auth key will be added automatically
</tls-auth>
"@
            
            $templateContent = $defaultTemplate
        } else {
            # Read template content
            $templateContent = Get-Content -Path $nordVpnTemplateFile -Raw
        }
        
        # Verify placeholder exists or create a simple replacement
        if ($templateContent -match 'us8361\.nordvpn\.com') {
            # Replace server name placeholders
            $configContent = $templateContent -replace 'us8361\.nordvpn\.com', $ServerName
        } else {
            # If no placeholder found, create a proper NordVPN config
            Write-Host "No placeholder found in template. Creating proper NordVPN configuration..." -ForegroundColor Yellow
            
            $configContent = @"
client
dev tun
proto udp
remote $ServerName 1194
remote-random
nobind

redirect-gateway def1

tun-mtu 1500
mssfix 1450
ping 15
ping-restart 60
reneg-sec 0
comp-lzo no
setenv CLIENT_CERT 0

auth-user-pass
auth SHA512
cipher AES-256-CBC
data-ciphers AES-256-GCM:AES-256-CBC:AES-128-GCM
remote-cert-tls server

verb 3
pull
fast-io

<ca>
# NordVPN CA certificate will be added automatically
</ca>
key-direction 1
<tls-auth>
# NordVPN TLS auth key will be added automatically
</tls-auth>
"@
        }
        
        # Ensure CA certificate and TLS-auth key are present (handles default template case)
        if ($configContent -notmatch "-----BEGIN CERTIFICATE-----") {
            $configContent = $configContent -replace '(?s)<ca>.*?</ca>', "<ca>`n$caCertBlock`n</ca>"
        }
        if ($configContent -notmatch "-----BEGIN OpenVPN Static key V1-----") {
            $configContent = $configContent -replace '(?s)<tls-auth>.*?</tls-auth>', "<tls-auth>`n$taKeyBlock`n</tls-auth>"
        }
        
        # Clean up older template lines that break full-tunnel routing
        $configContent = $configContent -replace '(?m)^\s*route-nopull.*\r?\n?', ''
        $configContent = $configContent -replace '(?m)^\s*route\s+.*\r?\n?', ''

        # Ensure redirect-gateway is present for full-tunnel
        if ($configContent -notmatch 'redirect-gateway') {
            $configContent = $configContent + "`nredirect-gateway def1"
        }

        # Add data-ciphers line if missing (suppresses deprecation warning)
        if ($configContent -notmatch 'data-ciphers') {
            $configContent = $configContent + "`ndata-ciphers AES-256-GCM:AES-256-CBC:AES-128-GCM"
        }

        # Save to config file
        $configFilePath = "$configsDir\custom_$ServerName.ovpn"
        Set-Content -Path $configFilePath -Value $configContent
        
        Write-Host "Custom configuration created: $configFilePath" -ForegroundColor Green
        Write-Host "Configuration created successfully." -ForegroundColor Green
        
        return $configFilePath
    }
    catch {
        Write-Host "Error creating custom configuration: $_" -ForegroundColor Red
        return $null
    }
}

function Import-ConfigToOpenVpn {
    param (
        [string]$ConfigFilePath
    )
    
    try {
        # Copy the configuration file to OpenVPN config directory
        $openVpnConfigDir = "$openVpnInstallPath\config"
        $destinationPath = "$openVpnConfigDir\$(Split-Path $ConfigFilePath -Leaf)"
        
        Copy-Item -Path $ConfigFilePath -Destination $destinationPath -Force
        
        Write-Host "Configuration imported to OpenVPN: $destinationPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error importing configuration to OpenVPN: $_" -ForegroundColor Red
        return $false
    }
}

function Launch-OpenVpn {
    param(
        [string]$ConfigBaseName
    )
    try {
        $openVpnGui = "$openVpnInstallPath\bin\openvpn-gui.exe"
        
        if (Test-Path $openVpnGui) {
            if ($ConfigBaseName) {
                Write-Host "Launching OpenVPN GUI and auto-connecting to $ConfigBaseName..." -ForegroundColor Cyan
                
                # Start OpenVPN GUI with auto-connect
                $process = Start-Process -FilePath $openVpnGui -ArgumentList '--command','connect',$ConfigBaseName -PassThru
                
                # Wait a moment for the GUI to start
                Start-Sleep -Seconds 2
                
                # Try to focus/bring OpenVPN GUI to foreground
                try {
                    # Get OpenVPN GUI window and bring it to front
                    $openVpnWindow = Get-Process | Where-Object { $_.ProcessName -eq "openvpn-gui" } | Select-Object -First 1
                    if ($openVpnWindow) {
                        Add-Type -TypeDefinition @"
                        using System;
                        using System.Runtime.InteropServices;
                        public class Win32 {
                            [DllImport("user32.dll")]
                            [return: MarshalAs(UnmanagedType.Bool)]
                            public static extern bool SetForegroundWindow(IntPtr hWnd);
                            
                            [DllImport("user32.dll")]
                            public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
                        }
"@
                        
                        # Try to bring window to front
                        $hwnd = $openVpnWindow.MainWindowHandle
                        if ($hwnd -ne [IntPtr]::Zero) {
                            [Win32]::ShowWindow($hwnd, 9) # SW_RESTORE
                            [Win32]::SetForegroundWindow($hwnd)
                            Write-Host "OpenVPN GUI brought to foreground." -ForegroundColor Green
                        }
                    }
                }
                catch {
                    Write-Host "Note: Could not automatically focus OpenVPN GUI. Please manually bring it to front." -ForegroundColor Yellow
                }
                
                return $true
            } else {
                Write-Host "Launching OpenVPN GUI..." -ForegroundColor Cyan
                Start-Process -FilePath $openVpnGui
                return $true
            }
        }
        else {
            Write-Host "OpenVPN GUI not found at: $openVpnGui" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "Error launching OpenVPN GUI: $_" -ForegroundColor Red
        return $false
    }
}

function Open-NordVpnCredentialsPage {
    try {
        Write-Host "Opening NordVPN service credentials page..." -ForegroundColor Cyan
        Start-Process $nordVpnCredentialsUrl
        return $true
    }
    catch {
        Write-Host "Error opening NordVPN credentials page: $_" -ForegroundColor Red
        return $false
    }
}

# Main script
Clear-Host
Write-Host "=== Privacy First - VPN Setup ===" -ForegroundColor Cyan

# Open NordVPN credentials page first
Open-NordVpnCredentialsPage
Write-Host "`nIMPORTANT: From the opened page, go to Dashboard > Manual Setup > Service Credentials" -ForegroundColor Yellow
Write-Host "Save your Service Username and Password - you'll need them to connect to the VPN later" -ForegroundColor Yellow
Write-Host "NOTE: Service account is different from your NordVPN account" -ForegroundColor Yellow
Write-Host "TIP: For direct access to service credentials, use this link: https://my.nordaccount.com/dashboard/nordvpn/manual-configuration/service-credentials/" -ForegroundColor Green

# Initialize the continue flag
$continueToServerSelection = $false

# Check if OpenVPN is installed
if (Check-OpenVpnInstalled) {
    Write-Host "`nOpenVPN is already installed." -ForegroundColor Green
    $continueToServerSelection = $true
} else {
    Write-Host "`nOpenVPN is not installed." -ForegroundColor Yellow
    
    # Check if the installer path is valid
    if ($openVpnInstaller -and (Test-Path $openVpnInstaller)) {
        Write-Host "OpenVPN installer found at: $openVpnInstaller" -ForegroundColor Green
        Write-Host "Installing now..." -ForegroundColor Green
        
        # Install OpenVPN
        if (Install-OpenVpn) {
            Write-Host "OpenVPN is now ready to use." -ForegroundColor Green
            Write-Host "---------------------------------------------" -ForegroundColor Cyan
            Write-Host "Press Enter to proceed with VPN server setup" -ForegroundColor Yellow
            $null = Read-Host
            $continueToServerSelection = $true
        } else {
            Write-Host "OpenVPN installation failed." -ForegroundColor Red
            $response = Read-Host "Do you want to continue without OpenVPN installed? (Y/N)"
            if ($response -eq "Y" -or $response -eq "y") {
                $continueToServerSelection = $true
            } else {
                Write-Host "Exiting VPN setup..." -ForegroundColor Red
                Start-Sleep -Seconds 3
            }
        }
    } else {
        Write-Host "OpenVPN installer not found at expected location." -ForegroundColor Red
        
        # Try to find the installer in common locations
        Write-Host "Searching for OpenVPN installer in alternative locations..." -ForegroundColor Yellow
        
        # Get current directory and try multiple paths
        $currentDir = Get-Location
        $alternativePaths = @(
            "tools\OpenVPN-2.6.14-I001-amd64.msi",
            "..\tools\OpenVPN-2.6.14-I001-amd64.msi",
            ".\tools\OpenVPN-2.6.14-I001-amd64.msi",
            "$currentDir\tools\OpenVPN-2.6.14-I001-amd64.msi",
            "$currentDir\..\tools\OpenVPN-2.6.14-I001-amd64.msi",
            "$scriptDir\..\tools\OpenVPN-2.6.14-I001-amd64.msi",
            "$projectRoot\tools\OpenVPN-2.6.14-I001-amd64.msi"
        )
        
        # Also try to find it in the current directory structure
        $searchPaths = @(
            "C:\Users\hJlsa90213Aa1\Downloads\PrivacyFirst Final 1\PrivacyFirst Final\tools\OpenVPN-2.6.14-I001-amd64.msi",
            "C:\Users\hJlsa90213Aa1\Downloads\PrivacyFirst Final\tools\OpenVPN-2.6.14-I001-amd64.msi",
            "C:\Users\hJlsa90213Aa1\Desktop\PrivacyFirst Final\tools\OpenVPN-2.6.14-I001-amd64.msi"
        )
        
        $alternativePaths += $searchPaths
        
        $foundInstaller = $null
        foreach ($path in $alternativePaths) {
            if ($path -and (Test-Path $path)) {
                $foundInstaller = $path
                Write-Host "Found installer at: $foundInstaller" -ForegroundColor Green
                break
            }
        }
        
        if ($foundInstaller) {
            Write-Host "Using found installer: $foundInstaller" -ForegroundColor Green
            $openVpnInstaller = $foundInstaller
            
            # Install OpenVPN
            if (Install-OpenVpn) {
                Write-Host "OpenVPN is now ready to use." -ForegroundColor Green
                Write-Host "---------------------------------------------" -ForegroundColor Cyan
                Write-Host "Press Enter to proceed with VPN server setup" -ForegroundColor Yellow
                $null = Read-Host
                $continueToServerSelection = $true
            } else {
                Write-Host "OpenVPN installation failed." -ForegroundColor Red
                $response = Read-Host "Do you want to continue without OpenVPN installed? (Y/N)"
                if ($response -eq "Y" -or $response -eq "y") {
                    $continueToServerSelection = $true
                } else {
                    Write-Host "Exiting VPN setup..." -ForegroundColor Red
                    Start-Sleep -Seconds 3
                }
            }
        } else {
            Write-Host "OpenVPN installer not found in any location." -ForegroundColor Red
            Write-Host "Please ensure the OpenVPN installer is in the tools folder." -ForegroundColor Yellow
            Write-Host "Expected file: OpenVPN-2.6.14-I001-amd64.msi" -ForegroundColor Yellow
            $response = Read-Host "Do you want to continue without OpenVPN installed? (Y/N)"
            if ($response -eq "Y" -or $response -eq "y") {
                $continueToServerSelection = $true
            } else {
                Write-Host "Exiting VPN setup..." -ForegroundColor Red
                Start-Sleep -Seconds 3
            }
        }
    }
}

# Only proceed to server selection if OpenVPN is installed or user chose to continue
if ($continueToServerSelection) {
    # Get available countries
    Write-Host "`n=== VPN Server Selection ===" -ForegroundColor Cyan
    Write-Host "Now let's choose a VPN server to connect to." -ForegroundColor Yellow
    
    $countries = Get-NordVpnCountries
    
    if ($null -eq $countries -or $countries.Count -eq 0) {
        Write-Host "No countries available. Exiting..." -ForegroundColor Red
        Start-Sleep -Seconds 3
        return
    }
    
    # Display available countries
    Write-Host "`nAvailable Countries:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $countries.Count; $i++) {
        Write-Host "[$i] $($countries[$i].name)" -ForegroundColor Yellow
    }
    
    # Get country selection
    $countryIndex = Read-Host "`nSelect a country by number"
    if (-not ($countryIndex -match '^\d+$') -or [int]$countryIndex -lt 0 -or [int]$countryIndex -ge $countries.Count) {
        Write-Host "Invalid selection. Exiting..." -ForegroundColor Red
        Start-Sleep -Seconds 3
        return
    }
    
    $selectedCountry = $countries[[int]$countryIndex]
    Write-Host "Selected country: $($selectedCountry.name)" -ForegroundColor Green
    
    # Get servers for the selected country
    $servers = Get-NordVpnServers -CountryId $selectedCountry.id
    
    if ($null -eq $servers -or $servers.Count -eq 0) {
        Write-Host "No servers found for the selected country. Exiting..." -ForegroundColor Red
        Start-Sleep -Seconds 3
        return
    }
    
    # Display available servers (up to 20)
    Write-Host "`nAvailable Servers for $($selectedCountry.name):" -ForegroundColor Cyan
    $serverLimit = [Math]::Min($servers.Count, 20)
    for ($i = 0; $i -lt $serverLimit; $i++) {
        $s = $servers[$i]
        $serverName = $s.hostname
        $load = $s.load
        Write-Host "[$i] $serverName (load: $load`%)" -ForegroundColor Yellow
    }
    Write-Host "[L] Lowest-load server (recommended)" -ForegroundColor Yellow
    Write-Host "[R] Random server" -ForegroundColor Yellow
    
    # Get server selection
    $serverSelection = Read-Host "`nSelect a server by number, 'L' for lowest load, or 'R' for random"
    
    if ($serverSelection -eq "L" -or $serverSelection -eq "l") {
        $selectedServer = $servers[0]
        $selectedServerName = $selectedServer.hostname
        Write-Host "Selected lowest-load server: $selectedServerName (load: $($selectedServer.load)%)" -ForegroundColor Green
    }
    elseif ($serverSelection -eq "R" -or $serverSelection -eq "r") {
        $selectedServer = $servers | Get-Random
        $selectedServerName = $selectedServer.hostname
        Write-Host "Selected random server: $selectedServerName" -ForegroundColor Green
    }
    elseif ($serverSelection -match '^\d+$' -and [int]$serverSelection -ge 0 -and [int]$serverSelection -lt $serverLimit) {
        $selectedServer = $servers[[int]$serverSelection]
        $selectedServerName = $selectedServer.hostname
        Write-Host "Selected server: $selectedServerName" -ForegroundColor Green
    }
    else {
        Write-Host "Invalid selection. Exiting..." -ForegroundColor Red
        Start-Sleep -Seconds 3
        return
    }
    
    # Create custom configuration for the selected server
    $configFilePath = Create-CustomConfig -ServerName $selectedServerName
    
    if ($null -eq $configFilePath) {
        Write-Host "Failed to create custom configuration. Exiting..." -ForegroundColor Red
        Start-Sleep -Seconds 3
        return
    }
    
    # Import configuration to OpenVPN if installed
    if (Check-OpenVpnInstalled) {
        # Import configuration to OpenVPN
        if (Import-ConfigToOpenVpn -ConfigFilePath $configFilePath) {
            $configBaseName = [System.IO.Path]::GetFileNameWithoutExtension($configFilePath)
            # Launch OpenVPN GUI and auto-connect
            Launch-OpenVpn -ConfigBaseName $configBaseName
            
            Write-Host "`nOpenVPN setup complete. The client is attempting to connect automatically." -ForegroundColor Cyan
            Write-Host "If prompted, enter your NordVPN Service Credentials." -ForegroundColor Yellow
            Write-Host "If not, go to your task bar, right-click on OpenVPN, choose the config you just created, and click connect. Enter your service details." -ForegroundColor Yellow
            Write-Host "If it still doesn't work, go and check the READ ME FILE." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "`nConfiguration created at: $configFilePath" -ForegroundColor Cyan
        Write-Host "Please install OpenVPN and manually import this configuration file." -ForegroundColor Yellow
    }
}

Write-Host "`nPress any key to return to the main menu..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') 