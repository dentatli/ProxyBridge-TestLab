using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace ProxyBridge.TestLab {
    // Documented PSAPI observation only. Does not open a driver or change its state.
    public static class LoadedDriverQuery {
        [StructLayout(LayoutKind.Sequential)] private struct Luid { public uint Low; public int High; }
        [StructLayout(LayoutKind.Sequential)] private struct Privileges { public uint Count; public Luid Id; public uint Attributes; }
        [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool CloseHandle(IntPtr handle);
        [DllImport("advapi32.dll", SetLastError=true)] private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool LookupPrivilegeValueW(string system, string name, out Luid id);
        [DllImport("advapi32.dll", SetLastError=true)] private static extern bool AdjustTokenPrivileges(IntPtr token, bool disable, ref Privileges state, uint size, out Privileges previous, out uint needed);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool K32EnumDeviceDrivers([Out] IntPtr[] bases, uint bytes, out uint needed);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern uint K32GetDeviceDriverBaseNameW(IntPtr address, StringBuilder name, uint size);

        public static string[] GetNames() {
            IntPtr token = IntPtr.Zero;
            Privileges previous = new Privileges();
            bool adjusted = false;
            try {
                // Windows 11 24H2+ can return success with all-null addresses otherwise.
                if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) throw new Win32Exception();
                Luid id;
                if (!LookupPrivilegeValueW(null, "SeDebugPrivilege", out id)) throw new Win32Exception();
                Privileges enable = new Privileges { Count=1, Id=id, Attributes=2 };
                uint needed;
                if (!AdjustTokenPrivileges(token, false, ref enable, (uint)Marshal.SizeOf(typeof(Privileges)), out previous, out needed)) throw new Win32Exception();
                int error = Marshal.GetLastWin32Error();
                if (error != 0) throw new Win32Exception(error);
                adjusted = true;
                IntPtr[] bases = new IntPtr[4096];
                if (!K32EnumDeviceDrivers(bases, (uint)(bases.Length * IntPtr.Size), out needed)) throw new Win32Exception();
                if (needed == 0 || needed > bases.Length * IntPtr.Size || needed % IntPtr.Size != 0)
                    throw new InvalidOperationException("DRIVER_ENUMERATION_SIZE_INVALID");
                string[] names = new string[needed / IntPtr.Size];
                for (int i=0; i<names.Length; i++) {
                    if (bases[i] == IntPtr.Zero) throw new InvalidOperationException("DRIVER_ENUMERATION_VISIBILITY_INCOMPLETE");
                    StringBuilder name = new StringBuilder(512);
                    uint count = K32GetDeviceDriverBaseNameW(bases[i], name, (uint)name.Capacity);
                    if (count == 0 || count >= name.Capacity - 1) throw new InvalidOperationException("DRIVER_NAME_QUERY_INCOMPLETE");
                    names[i] = name.ToString();
                }
                Array.Sort(names, StringComparer.OrdinalIgnoreCase);
                return names;
            }
            finally {
                try {
                    if (adjusted) {
                        Privileges ignored; uint size;
                        if (!AdjustTokenPrivileges(token, false, ref previous, (uint)Marshal.SizeOf(typeof(Privileges)), out ignored, out size))
                            throw new Win32Exception();
                    }
                }
                finally { if (token != IntPtr.Zero) CloseHandle(token); }
            }
        }
    }
}
