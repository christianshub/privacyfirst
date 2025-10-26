@echo off
title Privacy First
echo.

:: Check for elevated privileges
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    echo Administrator privileges required!
    echo Requesting administrative privileges...
    echo.
    goto UACPrompt
) else (
    goto GotAdmin
)

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:GotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"

echo Running with Administrator privileges...
echo.

:: Check if PowerShell setup is needed
echo [System Check] Verifying PowerShell configuration...
call :CheckPowerShellSetup

if "%setupNeeded%"=="true" (
    echo.
    echo ===============================================
    echo          PowerShell Setup Required
    echo ===============================================
    echo.
    echo PrivacyFirst requires PowerShell scripts to be enabled
    echo for proper functionality. This is a one-time setup.
    echo.
    echo The following will be configured:
    echo   - PowerShell execution policy
    echo   - File unblocking
    echo   - Script associations
    echo.
    choice /C YN /M "Would you like to configure PowerShell now"
    
    if errorlevel 2 (
        echo.
        echo Setup declined. PrivacyFirst may not work properly.
        echo You can run 'Setup-PrivacyFirst.bat' manually later.
        echo.
        pause
        goto LaunchPrivacyFirst
    )
    
    echo.
    echo ===============================================
    echo          Configuring PowerShell...
    echo ===============================================
    call :SetupPowerShell
    
    if "%setupSuccess%"=="true" (
        echo.
        echo ===============================================
        echo            Setup Complete!
        echo ===============================================
        echo.
        echo PowerShell has been configured successfully.
        echo PrivacyFirst should now run without issues.
        echo.
        pause
    ) else (
        echo.
        echo ===============================================
        echo             Setup Warning
        echo ===============================================
        echo.
        echo Some setup steps may have failed, but PrivacyFirst
        echo will attempt to run anyway.
        echo.
        pause
    )
) else (
    echo [System Check] PowerShell configuration: OK
)

:LaunchPrivacyFirst
echo.
echo ===============================================
echo            Starting PrivacyFirst...
echo ===============================================
echo.
echo IMPORTANT: It is HIGHLY RECOMMENDED to create a system restore point
echo before making any changes (Option 0 in the main menu).
echo.
timeout /t 1 /nobreak >nul 2>&1
echo.

:: Try multiple methods to launch PowerShell script
powershell -ExecutionPolicy Bypass -Command "& '%~dp0tools\privacy.ps1'" 2>nul
if %errorlevel% neq 0 (
    echo Primary launch method failed, trying alternative...
    powershell -ExecutionPolicy Unrestricted -NoProfile -Command "& '%~dp0tools\privacy.ps1'" 2>nul
    if %errorlevel% neq 0 (
        echo.
        echo ===============================================
        echo              Launch Error
        echo ===============================================
        echo.
        echo PrivacyFirst failed to start. This might be due to:
        echo   - PowerShell execution policy restrictions
        echo   - Blocked files from internet download
        echo   - Antivirus interference
        echo.
        echo Troubleshooting options:
        echo   1. Run 'Setup-PrivacyFirst.bat' as Administrator
        echo   2. Temporarily disable antivirus
        echo   3. Check Windows Defender exclusions
        echo.
        pause
        exit /b 1
    )
)

echo.
echo ===============================================
echo             Session Complete
echo ===============================================
echo.
echo PrivacyFirst session has ended.
echo.
echo Press any key to exit...
pause > nul
exit /b 0

:: Function to check if PowerShell setup is needed
:CheckPowerShellSetup
set "setupNeeded=false"

:: Check execution policy for current user
for /f "tokens=*" %%i in ('powershell -Command "Get-ExecutionPolicy -Scope CurrentUser" 2^>nul') do (
    if /i not "%%i"=="Unrestricted" if /i not "%%i"=="RemoteSigned" if /i not "%%i"=="Bypass" (
        set "setupNeeded=true"
    )
)

:: Check for blocked files
powershell -Command "$blocked = Get-ChildItem -Path '%~dp0' -Recurse | Where-Object { $_.IsBlocked }; if ($blocked) { exit 1 } else { exit 0 }" >nul 2>&1
if %errorlevel% neq 0 (
    set "setupNeeded=true"
)

:: Test if we can actually run a simple PowerShell script
powershell -Command "Write-Host 'Test' | Out-Null" >nul 2>&1
if %errorlevel% neq 0 (
    set "setupNeeded=true"
)

goto :eof

:: Function to setup PowerShell
:SetupPowerShell
set "setupSuccess=true"

echo [1/4] Configuring PowerShell file associations...
reg add "HKCR\Applications\powershell.exe\shell\open\command" /ve /t REG_SZ /d "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -ExecutionPolicy unrestricted -File \"%%1\"" /f >nul 2>&1
if %errorlevel% neq 0 set "setupSuccess=false"

echo [2/4] Setting PowerShell execution policy (Current User)...
reg add "HKCU\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell" /v "ExecutionPolicy" /t REG_SZ /d "Unrestricted" /f >nul 2>&1
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser -Force" >nul 2>&1
if %errorlevel% neq 0 set "setupSuccess=false"

echo [3/4] Setting PowerShell execution policy (System-wide)...
reg add "HKLM\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell" /v "ExecutionPolicy" /t REG_SZ /d "Unrestricted" /f >nul 2>&1
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force" >nul 2>&1
:: Don't fail setup if system-wide policy fails (might not have permissions)

echo [4/4] Unblocking all files in PrivacyFirst directory...
powershell -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File" >nul 2>&1
if %errorlevel% neq 0 set "setupSuccess=false"

goto :eof 