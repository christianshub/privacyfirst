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
