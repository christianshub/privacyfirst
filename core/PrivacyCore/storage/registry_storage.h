#pragma once

#include <string>
#include <Windows.h>

namespace RegistryStorage {
    // Base registry path for PrivacyFirst
    const wchar_t* const BASE_KEY = L"SOFTWARE\\PrivacyFirst\\Backups";
    const wchar_t* const SETTINGS_KEY = L"SOFTWARE\\PrivacyFirst\\Settings";

    // Storage functions
    bool SaveOriginalValue(int operationId, const std::string& key, const std::string& value);
    bool SaveCurrentValue(int operationId, const std::string& key, const std::string& value);
    std::string GetOriginalValue(int operationId, const std::string& key = "");
    std::string GetCurrentValue(int operationId, const std::string& key = "");

    // Operation status
    bool IsOperationModified(int operationId);
    int GetOperationStatus(int operationId);

    // Settings
    bool SaveSetting(const std::string& name, const std::string& value);
    std::string GetSetting(const std::string& name, const std::string& defaultValue = "");

    // Cleanup
    bool ClearOperationBackup(int operationId);

    // Helper to get operation name
    std::wstring GetOperationKeyName(int operationId);
}
