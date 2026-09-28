using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class DpapiSecretProtector
{
    private const uint CryptprotectUiForbidden = 0x1;
    private static readonly byte[] OptionalEntropy = Encoding.UTF8.GetBytes("ProxyBridge-TestLab/settings/v1");

    public byte[] Protect(byte[] plaintext) => Transform(plaintext, protect: true);
    public byte[] Unprotect(byte[] ciphertext) => Transform(ciphertext, protect: false);

    private static byte[] Transform(byte[] input, bool protect)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("DPAPI_CURRENT_USER_REQUIRES_WINDOWS");
        var inputBlob = AllocateBlob(input);
        var entropyBlob = AllocateBlob(OptionalEntropy);
        DataBlob outputBlob = default;
        try
        {
            var succeeded = protect
                ? CryptProtectData(ref inputBlob, "ProxyBridge-TestLab settings", ref entropyBlob, IntPtr.Zero, IntPtr.Zero, CryptprotectUiForbidden, out outputBlob)
                : CryptUnprotectData(ref inputBlob, IntPtr.Zero, ref entropyBlob, IntPtr.Zero, IntPtr.Zero, CryptprotectUiForbidden, out outputBlob);
            if (!succeeded) throw new Win32Exception(Marshal.GetLastWin32Error(), protect ? "DPAPI_PROTECT_FAILED" : "DPAPI_UNPROTECT_FAILED");

            var output = new byte[outputBlob.Length];
            Marshal.Copy(outputBlob.Data, output, 0, output.Length);
            return output;
        }
        finally
        {
            FreePrivateBlob(ref inputBlob);
            FreePrivateBlob(ref entropyBlob);
            if (outputBlob.Data != IntPtr.Zero) LocalFree(outputBlob.Data);
        }
    }

    private static DataBlob AllocateBlob(byte[] data)
    {
        var pointer = Marshal.AllocHGlobal(data.Length);
        Marshal.Copy(data, 0, pointer, data.Length);
        return new DataBlob { Length = data.Length, Data = pointer };
    }

    private static void FreePrivateBlob(ref DataBlob blob)
    {
        if (blob.Data == IntPtr.Zero) return;
        for (var index = 0; index < blob.Length; index++) Marshal.WriteByte(blob.Data, index, 0);
        Marshal.FreeHGlobal(blob.Data);
        blob = default;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DataBlob
    {
        public int Length;
        public IntPtr Data;
    }

    [DllImport("Crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptProtectData(ref DataBlob dataIn, string description, ref DataBlob optionalEntropy, IntPtr reserved, IntPtr prompt, uint flags, out DataBlob dataOut);

    [DllImport("Crypt32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptUnprotectData(ref DataBlob dataIn, IntPtr description, ref DataBlob optionalEntropy, IntPtr reserved, IntPtr prompt, uint flags, out DataBlob dataOut);

    [DllImport("Kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);
}
