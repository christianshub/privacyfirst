#pragma once

#ifdef PRIVACYCORE_EXPORTS
#define PRIVACY_API __declspec(dllexport)
#else
#define PRIVACY_API __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Operation IDs (not directly exposed, used internally)
typedef enum {
    OP_CREATE_RESTORE_POINT = 1,
    OP_UNINSTALL_GAME = 2,
    OP_CHANGE_REGISTRY_HWIDS = 3,
    OP_SETUP_VPN = 4,
    OP_CHANGE_DISK_IDS = 5,
    OP_CHANGE_HARDWARE_IDS = 6,
    OP_CHANGE_MAC_ADDRESS = 7,
    OP_CHANGE_MONITOR_HWID = 8,
    OP_HIDE_PERIPHERAL_SERIALS = 9,
    OP_PRIVACY_CLEANER = 10
} OperationId;

// Status codes
typedef enum {
    STATUS_SUCCESS = 0,
    STATUS_FAILURE = 1,
    STATUS_NOT_IMPLEMENTED = 2,
    STATUS_NO_BACKUP = 3,
    STATUS_INVALID_OPERATION = 4
} StatusCode;

// Callbacks for progress and logging
typedef void (*ProgressCallback)(const char* message, int progress);
typedef void (*LogCallback)(const char* message, int level);

// Core API functions
PRIVACY_API int Execute(int opId, const char* params);
PRIVACY_API int Restore(int opId);
PRIVACY_API const char* GetCurrent(int opId);
PRIVACY_API const char* GetOriginal(int opId);
PRIVACY_API int GetStatus(int opId);

// Callback registration
PRIVACY_API void SetProgressCallback(ProgressCallback callback);
PRIVACY_API void SetLogCallback(LogCallback callback);

// Batch operations
PRIVACY_API int ExecuteMultiple(const int* opIds, int count, const char* params);

// Memory management
PRIVACY_API void FreeString(const char* str);

// Utility functions
PRIVACY_API const char* GetLastErrorMessage();
PRIVACY_API const char* GetDllVersion();

#ifdef __cplusplus
}
#endif
