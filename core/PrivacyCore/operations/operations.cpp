#include "operations.h"
#include "../storage/registry_storage.h"
#include "../utils/utils.h"
#include "../api.h"
#include <Windows.h>
#include <SrRestorePtApi.h>

#pragma comment(lib, "SrClient.lib")

namespace Operations {

    // ============================================================================
    // Operation 1: Create System Restore Point
    // ============================================================================
    int CreateRestorePoint() {
        try {
            Utils::LogInfo("Creating system restore point...");

            RESTOREPOINTINFOW restorePointInfo = { 0 };
            restorePointInfo.dwEventType = BEGIN_SYSTEM_CHANGE;
            restorePointInfo.dwRestorePtType = MODIFY_SETTINGS;
            wcscpy_s(restorePointInfo.szDescription, L"PrivacyFirst - Before Privacy Changes");

            STATEMGRSTATUS smgrStatus = { 0 };

            BOOL result = SRSetRestorePointW(&restorePointInfo, &smgrStatus);

            if (result && smgrStatus.nStatus == ERROR_SUCCESS) {
                Utils::LogInfo("System restore point created successfully");
                return STATUS_SUCCESS;
            }
            else {
                Utils::LogError("Failed to create restore point. Status: " + std::to_string(smgrStatus.nStatus));
                return STATUS_FAILURE;
            }
        }
        catch (const std::exception& ex) {
            Utils::LogError(std::string("Exception creating restore point: ") + ex.what());
            return STATUS_FAILURE;
        }
    }

    // ============================================================================
    // Operation 2: Uninstall Game
    // ============================================================================
    int UninstallGame() {
        try {
            Utils::LogInfo("Launching Revo Uninstaller...");

            std::wstring revoPath = Utils::GetToolPath(L"RevoUninstaller.exe");
            if (revoPath.empty()) {
                Utils::LogError("RevoUninstaller.exe not found in tools directory");
                return STATUS_FAILURE;
            }

            int result = Utils::ExecuteProcess(revoPath, L"", false); // Don't wait

            if (result >= 0) {
                Utils::LogInfo("Revo Uninstaller launched");
                return STATUS_SUCCESS;
            }
            else {
                Utils::LogError("Failed to launch Revo Uninstaller");
                return STATUS_FAILURE;
            }
        }
        catch (const std::exception& ex) {
            Utils::LogError(std::string("Exception launching uninstaller: ") + ex.what());
            return STATUS_FAILURE;
        }
    }

    // ============================================================================
    // Operation 3: Change Registry HWIDs (FULLY IMPLEMENTED)
    // ============================================================================
    int ChangeRegistryHWIDs() {
        try {
            Utils::LogInfo("Changing Registry HWIDs...");

            // Registry keys to modify
            const wchar_t* MACHINE_GUID_KEY = L"SOFTWARE\\Microsoft\\Cryptography";
            const wchar_t* MACHINE_GUID_VALUE = L"MachineGuid";

            const wchar_t* HWPROFILE_GUID_KEY = L"SYSTEM\\CurrentControlSet\\Control\\IDConfigDB\\Hardware Profiles\\0001";
            const wchar_t* HWPROFILE_GUID_VALUE = L"HwProfileGuid";

            // Get original values
            std::wstring originalMachineGuid = Utils::GetRegistryValue(HKEY_LOCAL_MACHINE, MACHINE_GUID_KEY, MACHINE_GUID_VALUE);
            std::wstring originalHwProfileGuid = Utils::GetRegistryValue(HKEY_LOCAL_MACHINE, HWPROFILE_GUID_KEY, HWPROFILE_GUID_VALUE);

            if (originalMachineGuid.empty() || originalHwProfileGuid.empty()) {
                Utils::LogError("Failed to read original HWID values from registry");
                return STATUS_FAILURE;
            }

            // Save originals
            RegistryStorage::SaveOriginalValue(3, "MachineGuid", Utils::WStringToString(originalMachineGuid));
            RegistryStorage::SaveOriginalValue(3, "HwProfileGuid", Utils::WStringToString(originalHwProfileGuid));

            // Generate new GUIDs
            std::string newMachineGuid = Utils::GenerateGUID();
            std::string newHwProfileGuid = Utils::GenerateGUID();

            Utils::LogInfo("New MachineGuid: " + newMachineGuid);
            Utils::LogInfo("New HwProfileGuid: " + newHwProfileGuid);

            // Set new values
            bool success1 = Utils::SetRegistryValue(HKEY_LOCAL_MACHINE, MACHINE_GUID_KEY, MACHINE_GUID_VALUE,
                Utils::StringToWString(newMachineGuid));
            bool success2 = Utils::SetRegistryValue(HKEY_LOCAL_MACHINE, HWPROFILE_GUID_KEY, HWPROFILE_GUID_VALUE,
                Utils::StringToWString(newHwProfileGuid));

            if (!success1 || !success2) {
                Utils::LogError("Failed to write new HWID values to registry");
                return STATUS_FAILURE;
            }

            // Save current values
            RegistryStorage::SaveCurrentValue(3, "MachineGuid", newMachineGuid);
            RegistryStorage::SaveCurrentValue(3, "HwProfileGuid", newHwProfileGuid);

            Utils::LogInfo("Registry HWIDs changed successfully");
            return STATUS_SUCCESS;
        }
        catch (const std::exception& ex) {
            Utils::LogError(std::string("Exception changing registry HWIDs: ") + ex.what());
            return STATUS_FAILURE;
        }
    }

    int RestoreRegistryHWIDs() {
        try {
            Utils::LogInfo("Restoring Registry HWIDs...");

            // Get original values
            std::string originalMachineGuid = RegistryStorage::GetOriginalValue(3, "MachineGuid");
            std::string originalHwProfileGuid = RegistryStorage::GetOriginalValue(3, "HwProfileGuid");

            if (originalMachineGuid.empty() || originalHwProfileGuid.empty()) {
                Utils::LogError("No backup found for Registry HWIDs");
                return STATUS_NO_BACKUP;
            }

            // Restore values
            const wchar_t* MACHINE_GUID_KEY = L"SOFTWARE\\Microsoft\\Cryptography";
            const wchar_t* MACHINE_GUID_VALUE = L"MachineGuid";
            const wchar_t* HWPROFILE_GUID_KEY = L"SYSTEM\\CurrentControlSet\\Control\\IDConfigDB\\Hardware Profiles\\0001";
            const wchar_t* HWPROFILE_GUID_VALUE = L"HwProfileGuid";

            bool success1 = Utils::SetRegistryValue(HKEY_LOCAL_MACHINE, MACHINE_GUID_KEY, MACHINE_GUID_VALUE,
                Utils::StringToWString(originalMachineGuid));
            bool success2 = Utils::SetRegistryValue(HKEY_LOCAL_MACHINE, HWPROFILE_GUID_KEY, HWPROFILE_GUID_VALUE,
                Utils::StringToWString(originalHwProfileGuid));

            if (!success1 || !success2) {
                Utils::LogError("Failed to restore HWID values to registry");
                return STATUS_FAILURE;
            }

            // Update current values to match original
            RegistryStorage::SaveCurrentValue(3, "MachineGuid", originalMachineGuid);
            RegistryStorage::SaveCurrentValue(3, "HwProfileGuid", originalHwProfileGuid);

            Utils::LogInfo("Registry HWIDs restored successfully");
            return STATUS_SUCCESS;
        }
        catch (const std::exception& ex) {
            Utils::LogError(std::string("Exception restoring registry HWIDs: ") + ex.what());
            return STATUS_FAILURE;
        }
    }

    // ============================================================================
    // Operation 4: Setup VPN (STUB - TODO)
    // ============================================================================
    int SetupVPN(const char* params) {
        Utils::LogInfo("VPN Setup - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    // ============================================================================
    // Operation 5: Change Disk IDs (STUB - TODO)
    // ============================================================================
    int ChangeDiskIDs() {
        Utils::LogInfo("Change Disk IDs - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    int RestoreDiskIDs() {
        Utils::LogInfo("Restore Disk IDs - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    // ============================================================================
    // Operation 6: Change Hardware IDs / SMBIOS (STUB - TODO)
    // ============================================================================
    int ChangeHardwareIDs() {
        Utils::LogInfo("Change Hardware IDs - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    int RestoreHardwareIDs() {
        Utils::LogInfo("Restore Hardware IDs - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    // ============================================================================
    // Operation 7: Change MAC Address (STUB - TODO)
    // ============================================================================
    int ChangeMACAddress() {
        Utils::LogInfo("Change MAC Address - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    int RestoreMACAddress() {
        Utils::LogInfo("Restore MAC Address - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    // ============================================================================
    // Operation 8: Change Monitor HWID (STUB - TODO)
    // ============================================================================
    int ChangeMonitorHWID() {
        Utils::LogInfo("Change Monitor HWID - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    int RestoreMonitorHWID() {
        Utils::LogInfo("Restore Monitor HWID - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    // ============================================================================
    // Operation 9: Hide Peripheral Serials (STUB - TODO)
    // ============================================================================
    int HidePeripheralSerials() {
        Utils::LogInfo("Hide Peripheral Serials - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    int RestorePeripheralSerials() {
        Utils::LogInfo("Restore Peripheral Serials - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

    // ============================================================================
    // Operation 10: Privacy Cleaner (STUB - TODO)
    // ============================================================================
    int PrivacyCleaner() {
        Utils::LogInfo("Privacy Cleaner - NOT YET IMPLEMENTED");
        return STATUS_NOT_IMPLEMENTED;
    }

}
