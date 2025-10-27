using System;
using System.Runtime.InteropServices;

namespace PrivacyFirst.UI
{
    public static class NativeMethods
    {
        private const string DllName = "PrivacyCore.dll";

        // Callbacks
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        public delegate void ProgressCallback([MarshalAs(UnmanagedType.LPStr)] string message, int progress);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        public delegate void LogCallback([MarshalAs(UnmanagedType.LPStr)] string message, int level);

        // Core API functions
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int Execute(int opId, [MarshalAs(UnmanagedType.LPStr)] string? params_);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int Restore(int opId);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr GetCurrent(int opId);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr GetOriginal(int opId);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int GetStatus(int opId);

        // Callbacks
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void SetProgressCallback(ProgressCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void SetLogCallback(LogCallback callback);

        // Batch operations
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ExecuteMultiple(int[] opIds, int count, [MarshalAs(UnmanagedType.LPStr)] string? params_);

        // Memory management
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void FreeString(IntPtr str);

        // Utility
        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr GetLastErrorMessage();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr GetDllVersion();

        // Helper to convert IntPtr to string and free memory
        public static string? PtrToStringAndFree(IntPtr ptr)
        {
            if (ptr == IntPtr.Zero)
                return null;

            string? result = Marshal.PtrToStringAnsi(ptr);
            FreeString(ptr);
            return result;
        }
    }
}
