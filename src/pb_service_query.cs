using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace ProxyBridge.TestLab {
    public sealed class DriverServiceRecord {
        public bool Exists;
        public uint State;
        public uint ServiceType;
        public string BinaryPath = "";
    }
    // Read-only SCM queries. No CreateService, StartService or device IOCTL.
    public static class DriverServiceQuery {
        [StructLayout(LayoutKind.Sequential)]
        private struct Config {
            public uint Type, StartType, ErrorControl;
            public IntPtr BinaryPath, Group;
            public uint Tag;
            public IntPtr Dependencies, Account, DisplayName;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct Status {
            public uint Type, State, Accepted, Win32Exit, SpecificExit, Checkpoint, WaitHint, Pid, Flags;
        }
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern IntPtr OpenSCManagerW(string machine, string database, uint access);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern IntPtr OpenServiceW(IntPtr manager, string name, uint access);
        [DllImport("advapi32.dll", SetLastError=true)]
        private static extern bool CloseServiceHandle(IntPtr handle);
        [DllImport("advapi32.dll", SetLastError=true)]
        private static extern bool QueryServiceConfigW(IntPtr service, IntPtr buffer, uint size, out uint needed);
        [DllImport("advapi32.dll", SetLastError=true)]
        private static extern bool QueryServiceStatusEx(IntPtr service, int level, out Status status, uint size, out uint needed);

        public static DriverServiceRecord Read(string name) {
            IntPtr manager = OpenSCManagerW(null, null, 1); // SC_MANAGER_CONNECT
            if (manager == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr service = IntPtr.Zero, buffer = IntPtr.Zero;
            try {
                service = OpenServiceW(manager, name, 5); // QUERY_CONFIG | QUERY_STATUS
                if (service == IntPtr.Zero) {
                    int error = Marshal.GetLastWin32Error();
                    if (error == 1060) return new DriverServiceRecord();
                    throw new Win32Exception(error);
                }
                uint needed;
                QueryServiceConfigW(service, IntPtr.Zero, 0, out needed);
                int queryError = Marshal.GetLastWin32Error();
                if (queryError != 122 || needed < Marshal.SizeOf(typeof(Config)) || needed > 8192)
                    throw new Win32Exception(queryError);
                buffer = Marshal.AllocHGlobal((int)needed);
                if (!QueryServiceConfigW(service, buffer, needed, out needed)) throw new Win32Exception(Marshal.GetLastWin32Error());
                Config config = (Config)Marshal.PtrToStructure(buffer, typeof(Config));
                Status status;
                if (!QueryServiceStatusEx(service, 0, out status, (uint)Marshal.SizeOf(typeof(Status)), out needed))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                return new DriverServiceRecord { Exists=true, State=status.State, ServiceType=config.Type,
                    BinaryPath=Marshal.PtrToStringUni(config.BinaryPath) ?? "" };
            } finally {
                if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer);
                if (service != IntPtr.Zero) CloseServiceHandle(service);
                CloseServiceHandle(manager);
            }
        }
    }
}
