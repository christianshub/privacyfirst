#include "utils.h"
#include <sstream>
#include <iomanip>
#include <random>
#include <comdef.h>
#include <Rpc.h>
#include <iostream>

#pragma comment(lib, "Rpcrt4.lib")

namespace Utils {

    // Convert string to wstring
    std::wstring StringToWString(const std::string& str) {
        if (str.empty()) return std::wstring();
        int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
        std::wstring wstrTo(size_needed, 0);
        MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
        return wstrTo;
    }

    // Convert wstring to string
    std::string WStringToString(const std::wstring& wstr) {
        if (wstr.empty()) return std::string();
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), NULL, 0, NULL, NULL);
        std::string strTo(size_needed, 0);
        WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), &strTo[0], size_needed, NULL, NULL);
        return strTo;
    }

    // Generate a new GUID
    std::string GenerateGUID() {
        UUID uuid;
        UuidCreate(&uuid);

        unsigned char* str;
        UuidToStringA(&uuid, &str);

        std::string guid_str((char*)str);
        RpcStringFreeA(&str);

        // Format as {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}
        std::transform(guid_str.begin(), guid_str.end(), guid_str.begin(), ::toupper);
        return "{" + guid_str + "}";
    }

    // Generate random hex string
    std::string GenerateRandomHex(int length) {
        static const char hex_chars[] = "0123456789ABCDEF";
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> dis(0, 15);

        std::string result;
        result.reserve(length);
        for (int i = 0; i < length; i++) {
            result += hex_chars[dis(gen)];
        }
        return result;
    }

    // Execute a process
    int ExecuteProcess(const std::wstring& exePath, const std::wstring& args, bool waitForExit) {
        STARTUPINFOW si = { sizeof(STARTUPINFOW) };
        PROCESS_INFORMATION pi = { 0 };

        si.dwFlags = STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;

        std::wstring cmdLine = L"\"" + exePath + L"\" " + args;
        wchar_t* cmdLineBuf = new wchar_t[cmdLine.length() + 1];
        wcscpy_s(cmdLineBuf, cmdLine.length() + 1, cmdLine.c_str());

        BOOL success = CreateProcessW(
            NULL,
            cmdLineBuf,
            NULL,
            NULL,
            FALSE,
            CREATE_NO_WINDOW,
            NULL,
            NULL,
            &si,
            &pi
        );

        delete[] cmdLineBuf;

        if (!success) {
            return -1;
        }

        if (waitForExit) {
            WaitForSingleObject(pi.hProcess, INFINITE);

            DWORD exitCode = 0;
            GetExitCodeProcess(pi.hProcess, &exitCode);

            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);

            return exitCode;
        }

        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);

        return 0;
    }

    // Execute process and capture output
    std::string ExecuteProcessWithOutput(const std::wstring& exePath, const std::wstring& args) {
        SECURITY_ATTRIBUTES sa = { sizeof(SECURITY_ATTRIBUTES), NULL, TRUE };
        HANDLE hReadPipe, hWritePipe;

        if (!CreatePipe(&hReadPipe, &hWritePipe, &sa, 0)) {
            return "";
        }

        STARTUPINFOW si = { sizeof(STARTUPINFOW) };
        si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
        si.hStdOutput = hWritePipe;
        si.hStdError = hWritePipe;
        si.wShowWindow = SW_HIDE;

        PROCESS_INFORMATION pi = { 0 };

        std::wstring cmdLine = L"\"" + exePath + L"\" " + args;
        wchar_t* cmdLineBuf = new wchar_t[cmdLine.length() + 1];
        wcscpy_s(cmdLineBuf, cmdLine.length() + 1, cmdLine.c_str());

        BOOL success = CreateProcessW(
            NULL,
            cmdLineBuf,
            NULL,
            NULL,
            TRUE,
            CREATE_NO_WINDOW,
            NULL,
            NULL,
            &si,
            &pi
        );

        delete[] cmdLineBuf;

        if (!success) {
            CloseHandle(hReadPipe);
            CloseHandle(hWritePipe);
            return "";
        }

        CloseHandle(hWritePipe);

        std::string output;
        char buffer[4096];
        DWORD bytesRead;

        while (ReadFile(hReadPipe, buffer, sizeof(buffer) - 1, &bytesRead, NULL) && bytesRead > 0) {
            buffer[bytesRead] = '\0';
            output += buffer;
        }

        WaitForSingleObject(pi.hProcess, INFINITE);

        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        CloseHandle(hReadPipe);

        return output;
    }

    // Set registry value
    bool SetRegistryValue(HKEY hKeyRoot, const std::wstring& subKey, const std::wstring& valueName, const std::wstring& value) {
        HKEY hKey;
        LONG result = RegCreateKeyExW(hKeyRoot, subKey.c_str(), 0, NULL, 0, KEY_WRITE, NULL, &hKey, NULL);

        if (result != ERROR_SUCCESS) {
            return false;
        }

        result = RegSetValueExW(hKey, valueName.c_str(), 0, REG_SZ,
            (const BYTE*)value.c_str(), (DWORD)((value.length() + 1) * sizeof(wchar_t)));

        RegCloseKey(hKey);

        return result == ERROR_SUCCESS;
    }

    // Get registry value
    std::wstring GetRegistryValue(HKEY hKeyRoot, const std::wstring& subKey, const std::wstring& valueName) {
        HKEY hKey;
        LONG result = RegOpenKeyExW(hKeyRoot, subKey.c_str(), 0, KEY_READ, &hKey);

        if (result != ERROR_SUCCESS) {
            return L"";
        }

        wchar_t buffer[1024];
        DWORD bufferSize = sizeof(buffer);
        DWORD type;

        result = RegQueryValueExW(hKey, valueName.c_str(), NULL, &type, (LPBYTE)buffer, &bufferSize);

        RegCloseKey(hKey);

        if (result == ERROR_SUCCESS && type == REG_SZ) {
            return std::wstring(buffer);
        }

        return L"";
    }

    // Delete registry value
    bool DeleteRegistryValue(HKEY hKeyRoot, const std::wstring& subKey, const std::wstring& valueName) {
        HKEY hKey;
        LONG result = RegOpenKeyExW(hKeyRoot, subKey.c_str(), 0, KEY_WRITE, &hKey);

        if (result != ERROR_SUCCESS) {
            return false;
        }

        result = RegDeleteValueW(hKey, valueName.c_str());
        RegCloseKey(hKey);

        return result == ERROR_SUCCESS;
    }

    // Check if file exists
    bool FileExists(const std::wstring& path) {
        DWORD attrib = GetFileAttributesW(path.c_str());
        return (attrib != INVALID_FILE_ATTRIBUTES && !(attrib & FILE_ATTRIBUTE_DIRECTORY));
    }

    // Check if directory exists
    bool DirectoryExists(const std::wstring& path) {
        DWORD attrib = GetFileAttributesW(path.c_str());
        return (attrib != INVALID_FILE_ATTRIBUTES && (attrib & FILE_ATTRIBUTE_DIRECTORY));
    }

    // Get module path
    std::wstring GetModulePath() {
        wchar_t path[MAX_PATH];
        GetModuleFileNameW(NULL, path, MAX_PATH);

        std::wstring fullPath(path);
        size_t lastSlash = fullPath.find_last_of(L"\\/");
        if (lastSlash != std::wstring::npos) {
            return fullPath.substr(0, lastSlash);
        }

        return fullPath;
    }

    // Get tool path
    std::wstring GetToolPath(const std::wstring& toolName) {
        std::wstring modulePath = GetModulePath();

        // Try relative to exe
        std::wstring toolPath = modulePath + L"\\" + toolName;
        if (FileExists(toolPath)) {
            return toolPath;
        }

        // Try in tools subfolder
        toolPath = modulePath + L"\\tools\\" + toolName;
        if (FileExists(toolPath)) {
            return toolPath;
        }

        // Try parent directory tools folder
        size_t lastSlash = modulePath.find_last_of(L"\\/");
        if (lastSlash != std::wstring::npos) {
            std::wstring parentPath = modulePath.substr(0, lastSlash);
            toolPath = parentPath + L"\\tools\\" + toolName;
            if (FileExists(toolPath)) {
                return toolPath;
            }
        }

        return L"";
    }

    // Get last error as string
    std::string GetLastErrorAsString() {
        DWORD errorMessageID = ::GetLastError();
        if (errorMessageID == 0) {
            return "";
        }

        LPSTR messageBuffer = nullptr;
        size_t size = FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            NULL, errorMessageID, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), (LPSTR)&messageBuffer, 0, NULL);

        std::string message(messageBuffer, size);
        LocalFree(messageBuffer);

        return message;
    }

    // Log error
    void LogError(const std::string& message) {
        OutputDebugStringA(("[ERROR] " + message).c_str());
    }

    // Log info
    void LogInfo(const std::string& message) {
        OutputDebugStringA(("[INFO] " + message).c_str());
    }

}
