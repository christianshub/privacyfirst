#pragma once

#include <string>
#include <Windows.h>

namespace Utils {
    // String utilities
    std::wstring StringToWString(const std::string& str);
    std::string WStringToString(const std::wstring& wstr);
    std::string GenerateGUID();
    std::string GenerateRandomHex(int length);

    // Process execution
    int ExecuteProcess(const std::wstring& exePath, const std::wstring& args, bool waitForExit = true);
    std::string ExecuteProcessWithOutput(const std::wstring& exePath, const std::wstring& args);

    // Registry helpers
    bool SetRegistryValue(HKEY hKeyRoot, const std::wstring& subKey, const std::wstring& valueName, const std::wstring& value);
    std::wstring GetRegistryValue(HKEY hKeyRoot, const std::wstring& subKey, const std::wstring& valueName);
    bool DeleteRegistryValue(HKEY hKeyRoot, const std::wstring& subKey, const std::wstring& valueName);

    // File system helpers
    bool FileExists(const std::wstring& path);
    bool DirectoryExists(const std::wstring& path);
    std::wstring GetModulePath();
    std::wstring GetToolPath(const std::wstring& toolName);

    // Error handling
    std::string GetLastErrorAsString();
    void LogError(const std::string& message);
    void LogInfo(const std::string& message);
}
