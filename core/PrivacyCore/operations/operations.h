#pragma once

#include <string>

namespace Operations {
    // Operation 1: Create System Restore Point
    int CreateRestorePoint();

    // Operation 2: Uninstall Game (launches Revo Uninstaller)
    int UninstallGame();

    // Operation 3: Change Registry HWIDs
    int ChangeRegistryHWIDs();
    int RestoreRegistryHWIDs();

    // Operation 4: Setup VPN
    int SetupVPN(const char* params);

    // Operation 5: Change Disk IDs
    int ChangeDiskIDs();
    int RestoreDiskIDs();

    // Operation 6: Change Hardware IDs (SMBIOS)
    int ChangeHardwareIDs();
    int RestoreHardwareIDs();

    // Operation 7: Change MAC Address
    int ChangeMACAddress();
    int RestoreMACAddress();

    // Operation 8: Change Monitor HWID
    int ChangeMonitorHWID();
    int RestoreMonitorHWID();

    // Operation 9: Hide Peripheral Serials
    int HidePeripheralSerials();
    int RestorePeripheralSerials();

    // Operation 10: Privacy Cleaner
    int PrivacyCleaner();
}
