#include "registry_storage.h"
#include "../utils/utils.h"
#include <sstream>

namespace RegistryStorage {

    // Get operation-specific registry key name
    std::wstring GetOperationKeyName(int operationId) {
        switch (operationId) {
            case 1: return L"RestorePoint";
            case 2: return L"GameUninstall";
            case 3: return L"RegistryHWID";
            case 4: return L"VPN";
            case 5: return L"DiskIDs";
            case 6: return L"SMBIOS";
            case 7: return L"MACAddress";
            case 8: return L"MonitorHWID";
            case 9: return L"Peripherals";
            case 10: return L"Cleaner";
            default: return L"Unknown";
        }
    }

    // Save original value
    bool SaveOriginalValue(int operationId, const std::string& key, const std::string& value) {
        std::wstring opKey = std::wstring(BASE_KEY) + L"\\" + GetOperationKeyName(operationId);
        std::wstring valueName = Utils::StringToWString(key.empty() ? "Original" : key + "_Original");
        return Utils::SetRegistryValue(HKEY_LOCAL_MACHINE, opKey, valueName, Utils::StringToWString(value));
    }

    // Save current value
    bool SaveCurrentValue(int operationId, const std::string& key, const std::string& value) {
        std::wstring opKey = std::wstring(BASE_KEY) + L"\\" + GetOperationKeyName(operationId);
        std::wstring valueName = Utils::StringToWString(key.empty() ? "Current" : key + "_Current");
        return Utils::SetRegistryValue(HKEY_LOCAL_MACHINE, opKey, valueName, Utils::StringToWString(value));
    }

    // Get original value
    std::string GetOriginalValue(int operationId, const std::string& key) {
        std::wstring opKey = std::wstring(BASE_KEY) + L"\\" + GetOperationKeyName(operationId);
        std::wstring valueName = Utils::StringToWString(key.empty() ? "Original" : key + "_Original");
        std::wstring value = Utils::GetRegistryValue(HKEY_LOCAL_MACHINE, opKey, valueName);
        return Utils::WStringToString(value);
    }

    // Get current value
    std::string GetCurrentValue(int operationId, const std::string& key) {
        std::wstring opKey = std::wstring(BASE_KEY) + L"\\" + GetOperationKeyName(operationId);
        std::wstring valueName = Utils::StringToWString(key.empty() ? "Current" : key + "_Current");
        std::wstring value = Utils::GetRegistryValue(HKEY_LOCAL_MACHINE, opKey, valueName);
        return Utils::WStringToString(value);
    }

    // Check if operation has been modified
    bool IsOperationModified(int operationId) {
        std::string original = GetOriginalValue(operationId);
        std::string current = GetCurrentValue(operationId);
        return !original.empty() && !current.empty() && (original != current);
    }

    // Get operation status
    int GetOperationStatus(int operationId) {
        std::string original = GetOriginalValue(operationId);

        if (original.empty()) {
            return 0; // Not modified / no backup
        }

        if (IsOperationModified(operationId)) {
            return 1; // Modified
        }

        return 2; // Has backup but restored
    }

    // Save setting
    bool SaveSetting(const std::string& name, const std::string& value) {
        std::wstring valueName = Utils::StringToWString(name);
        return Utils::SetRegistryValue(HKEY_LOCAL_MACHINE, SETTINGS_KEY, valueName, Utils::StringToWString(value));
    }

    // Get setting
    std::string GetSetting(const std::string& name, const std::string& defaultValue) {
        std::wstring valueName = Utils::StringToWString(name);
        std::wstring value = Utils::GetRegistryValue(HKEY_LOCAL_MACHINE, SETTINGS_KEY, valueName);

        if (value.empty()) {
            return defaultValue;
        }

        return Utils::WStringToString(value);
    }

    // Clear operation backup
    bool ClearOperationBackup(int operationId) {
        std::wstring opKey = std::wstring(BASE_KEY) + L"\\" + GetOperationKeyName(operationId);
        LONG result = RegDeleteTreeW(HKEY_LOCAL_MACHINE, opKey.c_str());
        return result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND;
    }

}
