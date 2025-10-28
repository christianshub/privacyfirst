# PrivacyFirst - Privacy Protection Tool

A Windows privacy tool that modifies hardware identifiers and system information to enhance anonymity.

## Architecture

- **C++ Core DLL** (`PrivacyCore.dll`) - Backend operations
- **C# WPF UI** (`PrivacyFirst.exe`) - User interface (.NET 8)
- **Registry Storage** - Backup/restore system (no files)

## Current Status

### ✅ Implemented (Working)
1. **Create Restore Point** - System restore point creation
2. **Registry HWIDs** - Change MachineGuid and HwProfileGuid
   - Full implementation with backup/restore

### 🚧 Not Yet Implemented (Stubbed)
3. Uninstall Game (Revo Uninstaller)
4. VPN Setup (OpenVPN + NordVPN)
5. Disk IDs (VolumeID tool)
6. Hardware IDs/SMBIOS (AMIDEWIN tool)
7. MAC Address spoofing
8. Monitor HWID modification
9. Hide Peripheral Serials
10. Privacy Cleaner (temp files, logs, DNS, browser data)

## Building

### Build C++ Core:
```bash
cd c:\repos\privacyfirst
powershell -ExecutionPolicy Bypass -File build.ps1
```

### Build C# UI:
```bash
dotnet build ui/PrivacyFirst.UI/PrivacyFirst.UI.csproj -c Release
```

### Build Everything:
```bash
msbuild PrivacyFirst.sln /p:Configuration=Release /p:Platform=x64
```

### Build Installer (self-contained + Inno Setup)
```powershell
pwsh scripts/build_installer.ps1 -Configuration Release -Version 1.0.0
```
Outputs:
- Self-contained publish: `publish\win-x64\PrivacyFirst.exe`
- Installer: `dist\PrivacyFirst-Setup.exe` (requires Inno Setup 6)

## Testing on Proxmox

### Prerequisites:
- Proxmox server at 192.168.0.130
- Windows 11 VM (VMID 101) - template
- Test VM (VMID 102) - cloned from 101

### Quick Test Workflow:
```powershell
cd c:\repos\privacyfirst\tests

# Full automated test
.\orchestrator.ps1 -VMIPAddress "192.168.0.X" -VMPassword "yourpassword"

# Or manual steps:
.\deploy_to_vm.ps1 -VMHostname "192.168.0.X"  # Deploy to VM
# Then RDP to VM and test manually
```

### Callback-Based VM Testing:
```powershell
# 1. On the dev machine, start the callback server
cd c:\repos\privacyfirst
.\auto_test_with_callback.ps1 -CallbackPort 9000

# 2. On the VM (elevated PowerShell), download and execute the scripted test
irm http://DEV-IP:9000/script | iex
```

The host console will show download progress, save detailed results under `callback_results\`, and print a test summary once the VM posts back.

### Fully Automated Proxmox Run:
```powershell
# From the repo root, orchestrate rollback → callback → guest exec
cd c:\repos\privacyfirst
.\tests\proxmox_callback_orchestrator.ps1 `
    -ProxmoxHost 192.168.0.130 `
    -ProxmoxUser root@pam `
    -ProxmoxPassword 'hellokitty123' `
    -VMID 102 `
    -SnapshotName baseline `
    -CallbackPort 9900 `
    -UseWinRM `
    -VMIPAddress 192.168.0.143 `
    -VMUser john `
    -VMPassword '1' `
    -ShutdownVM
```

This script uses the Proxmox API to roll the VM back to the specified snapshot, start it, host the callback server, execute the VM auto-test (via the QEMU guest agent when available, or WinRM when `-UseWinRM` and credentials are supplied), wait for `callback_results\` to populate, and optionally shut the VM down.

### Program Runner Pipeline (Guest Agent):
```powershell
cd c:\repos\privacyfirst
.\tests\proxmox_program_runner.ps1 `
    -ProxmoxHost 192.168.0.130 `
    -ProxmoxUser root@pam `
    -ProxmoxPassword 'hellokitty123' `
    -VMID 102 `
    -SnapshotName baseline `
    -BuildOutputPath .\x64\Release `
    -Executable PrivacyFirst.exe `
    -Arguments '' `
    -ShutdownVM
```

This pipeline uses the QEMU guest agent to roll back VM 102, serve the local Release binaries via HTTP, download & execute them inside the VM, capture stdout/exit code, and shut the VM down when complete. Adjust `Files`, `Executable`, and `Arguments` as needed for different binaries.

### Rollback VM:
```bash
ssh root@192.168.0.130 "qm shutdown 102 && qm rollback 102 baseline && qm start 102"
```

## Project Structure

```
privacyfirst/
├── core/PrivacyCore/          # C++ DLL
│   ├── api.cpp/h              # Exported API
│   ├── operations/            # 10 privacy operations
│   ├── storage/               # Registry backup system
│   └── utils/                 # Helpers (GUID, process, registry)
├── ui/PrivacyFirst.UI/        # C# WPF
│   ├── MainWindow.xaml        # UI layout
│   ├── NativeMethods.cs       # P/Invoke bindings
│   └── OperationItem.cs       # Data model
├── tests/                     # Proxmox test scripts
│   ├── deploy_to_vm.ps1       # Deploy to test VM
│   ├── run_tests.ps1          # Run tests on VM
│   └── orchestrator.ps1       # Master test runner
├── tools/                     # External tools
│   ├── AMIDEWINx64.EXE        # SMBIOS modifier
│   ├── VolumeID64.exe         # Disk ID changer
│   ├── RevoUninstaller.exe    # Uninstaller
│   └── OpenVPN-*.msi          # VPN installer
├── templates/                 # VPN config templates
└── x64/Release/               # Build output
```

## Registry Storage

Backups stored in: `HKLM\SOFTWARE\PrivacyFirst\Backups\`

Each operation has:
- `OperationName\*_Original` - Original value
- `OperationName\*_Current` - Current value

Settings stored in: `HKLM\SOFTWARE\PrivacyFirst\Settings\`

## TODO List

### High Priority:
- [ ] Implement remaining 8 operations
- [ ] Add CLI interface for headless testing
- [ ] Create Settings dialog (VPN credentials, tool paths)
- [ ] Add confirmation dialogs before destructive operations

### Medium Priority:
- [ ] Implement NordVPN affiliate link integration
- [ ] Add dry-run/preview mode
- [ ] Detailed logging to file
- [ ] System compatibility checks

### Low Priority:
- [ ] Add encryption to registry storage (DPAPI)
- [ ] Code signing for core.dll
- [ ] Application icon
- [ ] Installer

## Security Note

⚠️ **WARNING**: This tool makes system-level changes. Always:
1. Create a system restore point before use
2. Test on a VM first
3. Have backups of important data
4. Understand each operation before running it

## License

[TODO: Add license]

## Contact

[TODO: Add contact info]
