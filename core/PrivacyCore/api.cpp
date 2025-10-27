#include "api.h"
#include "operations/operations.h"
#include "storage/registry_storage.h"
#include "utils/utils.h"
#include <string>
#include <sstream>

// Global callbacks
static ProgressCallback g_progressCallback = nullptr;
static LogCallback g_logCallback = nullptr;

// Last error message
static std::string g_lastError;

// Helper function to log messages
void LogMessage(const char* message, int level = 0) {
    if (g_logCallback) {
        g_logCallback(message, level);
    }
}

// Helper function to report progress
void ReportProgress(const char* message, int progress) {
    if (g_progressCallback) {
        g_progressCallback(message, progress);
    }
}

// Helper to allocate string for return (caller must free with FreeString)
const char* AllocString(const std::string& str) {
    char* result = new char[str.length() + 1];
    strcpy_s(result, str.length() + 1, str.c_str());
    return result;
}

// Execute an operation
PRIVACY_API int Execute(int opId, const char* params) {
    try {
        g_lastError.clear();
        std::string parameters = params ? params : "";

        LogMessage("Executing operation...", 0);

        switch (opId) {
            case OP_CREATE_RESTORE_POINT:
                return Operations::CreateRestorePoint();

            case OP_UNINSTALL_GAME:
                return Operations::UninstallGame();

            case OP_CHANGE_REGISTRY_HWIDS:
                return Operations::ChangeRegistryHWIDs();

            case OP_SETUP_VPN:
                return Operations::SetupVPN(parameters.c_str());

            case OP_CHANGE_DISK_IDS:
                return Operations::ChangeDiskIDs();

            case OP_CHANGE_HARDWARE_IDS:
                return Operations::ChangeHardwareIDs();

            case OP_CHANGE_MAC_ADDRESS:
                return Operations::ChangeMACAddress();

            case OP_CHANGE_MONITOR_HWID:
                return Operations::ChangeMonitorHWID();

            case OP_HIDE_PERIPHERAL_SERIALS:
                return Operations::HidePeripheralSerials();

            case OP_PRIVACY_CLEANER:
                return Operations::PrivacyCleaner();

            default:
                g_lastError = "Invalid operation ID";
                return STATUS_INVALID_OPERATION;
        }
    }
    catch (const std::exception& ex) {
        g_lastError = ex.what();
        LogMessage(ex.what(), 2); // Error level
        return STATUS_FAILURE;
    }
}

// Restore an operation
PRIVACY_API int Restore(int opId) {
    try {
        g_lastError.clear();

        LogMessage("Restoring operation...", 0);

        switch (opId) {
            case OP_CHANGE_REGISTRY_HWIDS:
                return Operations::RestoreRegistryHWIDs();

            case OP_CHANGE_DISK_IDS:
                return Operations::RestoreDiskIDs();

            case OP_CHANGE_HARDWARE_IDS:
                return Operations::RestoreHardwareIDs();

            case OP_CHANGE_MAC_ADDRESS:
                return Operations::RestoreMACAddress();

            case OP_CHANGE_MONITOR_HWID:
                return Operations::RestoreMonitorHWID();

            case OP_HIDE_PERIPHERAL_SERIALS:
                return Operations::RestorePeripheralSerials();

            default:
                g_lastError = "Operation does not support restore or invalid operation ID";
                return STATUS_INVALID_OPERATION;
        }
    }
    catch (const std::exception& ex) {
        g_lastError = ex.what();
        LogMessage(ex.what(), 2);
        return STATUS_FAILURE;
    }
}

// Get current value for an operation
PRIVACY_API const char* GetCurrent(int opId) {
    try {
        std::string value = RegistryStorage::GetCurrentValue(opId);
        if (value.empty()) {
            return AllocString("-");
        }
        return AllocString(value);
    }
    catch (const std::exception& ex) {
        g_lastError = ex.what();
        return AllocString("-");
    }
}

// Get original value for an operation
PRIVACY_API const char* GetOriginal(int opId) {
    try {
        std::string value = RegistryStorage::GetOriginalValue(opId);
        if (value.empty()) {
            return AllocString("-");
        }
        return AllocString(value);
    }
    catch (const std::exception& ex) {
        g_lastError = ex.what();
        return AllocString("-");
    }
}

// Get status of an operation
PRIVACY_API int GetStatus(int opId) {
    try {
        return RegistryStorage::GetOperationStatus(opId);
    }
    catch (const std::exception&) {
        return STATUS_FAILURE;
    }
}

// Set progress callback
PRIVACY_API void SetProgressCallback(ProgressCallback callback) {
    g_progressCallback = callback;
}

// Set log callback
PRIVACY_API void SetLogCallback(LogCallback callback) {
    g_logCallback = callback;
}

// Execute multiple operations
PRIVACY_API int ExecuteMultiple(const int* opIds, int count, const char* params) {
    int failedCount = 0;

    for (int i = 0; i < count; i++) {
        ReportProgress("Executing operation...", (i * 100) / count);

        int result = Execute(opIds[i], params);
        if (result != STATUS_SUCCESS) {
            failedCount++;
        }
    }

    ReportProgress("Complete", 100);

    return (failedCount == 0) ? STATUS_SUCCESS : STATUS_FAILURE;
}

// Free allocated string
PRIVACY_API void FreeString(const char* str) {
    if (str) {
        delete[] str;
    }
}

// Get last error message
PRIVACY_API const char* GetLastErrorMessage() {
    return AllocString(g_lastError);
}

// Get DLL version
PRIVACY_API const char* GetDllVersion() {
    return AllocString("1.0.0");
}
