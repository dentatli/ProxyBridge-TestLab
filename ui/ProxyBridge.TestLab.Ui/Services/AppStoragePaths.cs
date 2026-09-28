using System.Security.AccessControl;
using System.Security.Principal;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class AppStoragePaths
{
    public AppStoragePaths(string root)
    {
        Root = Path.GetFullPath(root);
        ConfigRoot = Path.Combine(Root, "config");
        RuntimeRoot = Path.Combine(Root, "runtime");
        EvidenceRoot = Path.Combine(Root, "evidence");
        JobsRoot = Path.Combine(Root, "jobs");
        KnownHostsRoot = Path.Combine(Root, "known-hosts");
        PublicSettingsPath = Path.Combine(ConfigRoot, "settings.json");
        ProtectedSettingsPath = Path.Combine(ConfigRoot, "secrets.dpapi");
        KnownHostsPath = Path.Combine(KnownHostsRoot, "known_hosts");
        ServerTrustPath = Path.Combine(ConfigRoot, "server-trust.json");
        ServerReceiptPath = Path.Combine(ConfigRoot, "server-readiness.json");
        ReceiptKeyPath = Path.Combine(ConfigRoot, "receipt-key.dpapi");
        ProtocolCertificatePath = Path.Combine(ConfigRoot, "protocol-server-certificate.dpapi");
        ProtocolCaPath = Path.Combine(ConfigRoot, "protocol-ca.cer");
        ProtocolCaPemPath = Path.Combine(ConfigRoot, "protocol-ca.pem");
    }

    public string Root { get; }
    public string ConfigRoot { get; }
    public string RuntimeRoot { get; }
    public string EvidenceRoot { get; }
    public string JobsRoot { get; }
    public string KnownHostsRoot { get; }
    public string PublicSettingsPath { get; }
    public string ProtectedSettingsPath { get; }
    public string KnownHostsPath { get; }
    public string ServerTrustPath { get; }
    public string ServerReceiptPath { get; }
    public string ReceiptKeyPath { get; }
    public string ProtocolCertificatePath { get; }
    public string ProtocolCaPath { get; }
    public string ProtocolCaPemPath { get; }

    public void EnsureSecureDirectories()
    {
        EnsureSecureDirectory(Root);
        EnsureSecureDirectory(ConfigRoot);
        EnsureSecureDirectory(RuntimeRoot);
        EnsureSecureDirectory(EvidenceRoot);
        EnsureSecureDirectory(JobsRoot);
        EnsureSecureDirectory(KnownHostsRoot);
    }

    public void ScavengeStaleRuntimeDirectories()
    {
        EnsureSecureDirectories();
        var runtimePrefix = Path.GetFullPath(RuntimeRoot) + Path.DirectorySeparatorChar;
        foreach (var directoryPath in Directory.EnumerateDirectories(RuntimeRoot, "*", SearchOption.TopDirectoryOnly))
        {
            var full = Path.GetFullPath(directoryPath);
            if (!full.StartsWith(runtimePrefix, StringComparison.OrdinalIgnoreCase)) continue;
            var attributes = File.GetAttributes(full);
            if ((attributes & FileAttributes.ReparsePoint) != 0) continue;
            var lockPath = Path.Combine(full, ".lease");
            FileStream? probe = null;
            try
            {
                probe = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
                probe.Dispose();
                probe = null;
                Directory.Delete(full, recursive: true);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            finally { probe?.Dispose(); }
        }
    }

    public static string GetDefaultRoot() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ProxyBridge-TestLab");

    public static void EnsureSecureDirectory(string path)
    {
        var directory = Directory.CreateDirectory(path);
        if (!OperatingSystem.IsWindows()) return;
        var identity = WindowsIdentity.GetCurrent().User ?? throw new InvalidOperationException("CURRENT_USER_SID_UNAVAILABLE");
        var system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        var security = new DirectorySecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.AddAccessRule(new FileSystemAccessRule(identity, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        security.AddAccessRule(new FileSystemAccessRule(system, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        directory.SetAccessControl(security);
    }
}
