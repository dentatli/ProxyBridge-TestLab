using Microsoft.Win32;
using System.Security.Cryptography;
using System.Text;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record InstalledProductRequest(string Id, string? DisplayName = null);

public sealed partial class BenchmarkLabService
{
    private sealed record Installation(string Id, string Label, string Folder, string Driver);

    private static Installation[] FindInstallations()
    {
        var candidates = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                     Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                     Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs") })
            if (!string.IsNullOrEmpty(root)) candidates.Add(Path.Combine(root, "ProxyBridge"));
        foreach (var hive in new[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser })
        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            try
            {
                using var baseKey = RegistryKey.OpenBaseKey(hive, view);
                using var uninstall = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall");
                foreach (var name in uninstall?.GetSubKeyNames() ?? [])
                {
                    using var entry = uninstall!.OpenSubKey(name);
                    if (entry?.GetValue("DisplayName") is string label && label.StartsWith("ProxyBridge", StringComparison.OrdinalIgnoreCase) &&
                        entry.GetValue("InstallLocation") is string location && IsLocalPath(location)) candidates.Add(location);
                }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
        }
        try
        {
            // Driver installation configuration is a discovery hint, never runtime readiness.
            var driver = ResolveDriverPath(new(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32"), "driver", null));
            var folder = Path.GetDirectoryName(driver);
            if (!string.IsNullOrEmpty(folder)) candidates.Add(folder);
        }
        catch (Exception error) when (error is InvalidOperationException or IOException or UnauthorizedAccessException) { }
        var result = new List<Installation>();
        foreach (var folder in candidates.Order(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                if (!IsLocalPath(folder) || !File.Exists(Path.Combine(folder, "ProxyBridge_CLI.exe")) || !File.Exists(Path.Combine(folder, "ProxyBridgeCore.dll"))) continue;
                var full = Path.GetFullPath(folder).TrimEnd('\\', '/');
                var driver = ResolveDriverPath(new(full, "driver", null));
                if (!File.Exists(driver)) continue;
                AssertNoReparse(full); AssertNoReparse(driver);
                var id = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(full.ToUpperInvariant() + "\n" + driver.ToUpperInvariant())));
                result.Add(new(id, "ProxyBridge · " + Path.GetFileName(full), full, driver));
            }
            catch (Exception error) when (error is InvalidOperationException or IOException or UnauthorizedAccessException or ArgumentException) { }
        }
        return result.ToArray();
    }

    public object DiscoverInstalled() => new { items = FindInstallations().Select(item => new { item.Id, item.Label }), scope = "installation-files", runtime_verified = false };

    public async Task<System.Text.Json.JsonElement> SelectInstalledAsync(InstalledProductRequest request, CancellationToken token)
    {
        var item = FindInstallations().SingleOrDefault(item => item.Id == request.Id) ?? throw new InvalidOperationException("INSTALLATION_NOT_FOUND");
        return await SelectAsync(new(item.Folder, "driver", item.Driver, request.DisplayName ?? "ProxyBridge"), token);
    }
}
