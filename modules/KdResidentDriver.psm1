Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Initialize-KdResidentDriverType {
    if ('PbKdResidentDevice' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class PbKdResidentDevice {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool DeviceIoControl(SafeFileHandle handle, uint code, IntPtr input, uint inputSize, IntPtr output, uint outputSize, out uint returned, IntPtr overlapped);
    public static SafeFileHandle Open() {
        var h = CreateFile(@"\\.\ProxyBridgeDrv", 0x40000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) { int error = Marshal.GetLastWin32Error(); h.Dispose(); throw new Win32Exception(error); }
        return h;
    }
    public static void Disable(SafeFileHandle handle) {
        uint returned;
        // CTL_CODE(FILE_DEVICE_UNKNOWN, 0x803, METHOD_BUFFERED, FILE_WRITE_DATA).
        if (!DeviceIoControl(handle, 0x22a00c, IntPtr.Zero, 0, IntPtr.Zero, 0, out returned, IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }
}
'@
}

function Open-KdResidentDriver {
    Initialize-KdResidentDriverType
    return [PbKdResidentDevice]::Open()
}

function Disable-KdResidentDriver {
    param([Parameter(Mandatory)]$Handle, [Parameter(Mandatory)][string]$SessionId,
          [Parameter(Mandatory)][ValidateSet('before','after')][string]$Phase)
    if ((Get-Service ProxyBridgeDrv).Status -ne 'Running') { throw 'KD_RESIDENT_SERVICE_NOT_RUNNING' }
    [PbKdResidentDevice]::Disable($Handle)
    if ((Get-Service ProxyBridgeDrv).Status -ne 'Running') { throw 'KD_RESIDENT_SERVICE_CHANGED_DURING_DISABLE' }
    return [ordered]@{schema_version=1;session_id=$SessionId;phase=$Phase;
        operation='PBDRV_IOCTL_DISABLE';ioctl='0x22a00c';device='\\.\ProxyBridgeDrv';
        completed=$true;service_state='Running';driver_unloaded=$false;
        enabled_flag_read_back=$false;claim='synchronous disable IOCTL completed; no independent flag readback';
        timestamp_utc=[DateTime]::UtcNow.ToString('o')}
}

Export-ModuleMember -Function Initialize-KdResidentDriverType,Open-KdResidentDriver,Disable-KdResidentDriver
