param([string]$RemoteDir)

$command = "cd `"$RemoteDir`"; powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File run_installer.cmd"
echo "--- SCRIPT CURRENT DIR ---"
echo $PWD
echo "--- INVOKING COMMAND ---"
echo $command
echo "--- OUTPUT START ---"
Invoke-Expression $command
echo "--- OUTPUT END ---"
