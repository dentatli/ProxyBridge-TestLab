using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ProxyBridge.TestLab.Ui.Services;

internal static partial class ServerDependencyBundle
{
    private const long MaximumExpandedBytes = 256L * 1024 * 1024;
    private const long MaximumEntryBytes = 64L * 1024 * 1024;

    public static void AddLockedLinuxRuntime(AppPaths paths, IDictionary<string, byte[]> runtimeFiles)
    {
        var lockPath = Path.Combine(paths.RepositoryRoot, "vendor", "protocol-dependencies.lock.json");
        var wheelRoot = Path.Combine(paths.RepositoryRoot, "vendor", "wheelhouse", "linux-x64");
        if (!File.Exists(lockPath) || !Directory.Exists(wheelRoot))
            throw new InvalidOperationException("SERVER_DEPENDENCY_BUNDLE_MISSING");
        if (File.GetAttributes(lockPath).HasFlag(FileAttributes.ReparsePoint) || File.GetAttributes(wheelRoot).HasFlag(FileAttributes.ReparsePoint))
            throw new InvalidOperationException("SERVER_DEPENDENCY_REPARSE_POINT_REFUSED");

        var lockBytes = File.ReadAllBytes(lockPath);
        using var document = JsonDocument.Parse(lockBytes, new JsonDocumentOptions { AllowTrailingCommas = false, CommentHandling = JsonCommentHandling.Disallow });
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || root.GetProperty("schema_version").GetInt32() != 1 ||
            root.GetProperty("network_installation_allowed").GetBoolean() ||
            root.GetProperty("dependency_set").GetString() != "protocol-quic-1")
            throw new InvalidOperationException("SERVER_DEPENDENCY_LOCK_INVALID");
        var packageCount = root.GetProperty("packages").GetArrayLength();
        var artifacts = root.GetProperty("artifacts").EnumerateArray()
            .Where(item => item.GetProperty("platform").GetString() == "linux-x64")
            .Select(item => new
            {
                File = item.GetProperty("file").GetString() ?? "",
                Sha256 = item.GetProperty("sha256").GetString() ?? "",
                Bytes = item.GetProperty("bytes").GetInt64()
            })
            .OrderBy(item => item.File, StringComparer.Ordinal)
            .ToArray();
        if (packageCount <= 0 || artifacts.Length != packageCount || artifacts.Select(item => item.File).Distinct(StringComparer.Ordinal).Count() != artifacts.Length)
            throw new InvalidOperationException("SERVER_DEPENDENCY_LOCK_INCOMPLETE");
        var actualFiles = Directory.EnumerateFiles(wheelRoot, "*", SearchOption.TopDirectoryOnly).Select(Path.GetFileName).Order(StringComparer.Ordinal).ToArray();
        if (!actualFiles.SequenceEqual(artifacts.Select(item => item.File), StringComparer.Ordinal))
            throw new InvalidOperationException("SERVER_DEPENDENCY_WHEEL_SET_MISMATCH");

        long expandedBytes = 0;
        foreach (var artifact in artifacts)
        {
            if (!SafeWheelName().IsMatch(artifact.File) || !LowerSha256().IsMatch(artifact.Sha256) || artifact.Bytes <= 0)
                throw new InvalidOperationException("SERVER_DEPENDENCY_ARTIFACT_INVALID");
            var wheelPath = Path.GetFullPath(Path.Combine(wheelRoot, artifact.File));
            var wheelPrefix = Path.GetFullPath(wheelRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (!wheelPath.StartsWith(wheelPrefix, StringComparison.OrdinalIgnoreCase) || !File.Exists(wheelPath) ||
                File.GetAttributes(wheelPath).HasFlag(FileAttributes.ReparsePoint))
                throw new InvalidOperationException("SERVER_DEPENDENCY_WHEEL_INVALID");
            var bytes = File.ReadAllBytes(wheelPath);
            if (bytes.LongLength != artifact.Bytes || !string.Equals(Convert.ToHexString(SHA256.HashData(bytes)), artifact.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("SERVER_DEPENDENCY_WHEEL_HASH_MISMATCH");
            using var stream = new MemoryStream(bytes, writable: false);
            using var archive = new ZipArchive(stream, ZipArchiveMode.Read, leaveOpen: false);
            foreach (var entry in archive.Entries)
            {
                var relative = entry.FullName;
                var directoryEntry = relative.EndsWith('/');
                var normalizedRelative = directoryEntry ? relative.TrimEnd('/') : relative;
                var segments = normalizedRelative.Split('/');
                var unixType = ((long)entry.ExternalAttributes >> 16) & 0xF000;
                if (string.IsNullOrWhiteSpace(normalizedRelative) || relative.Contains('\\') || relative.StartsWith('/') ||
                    segments.Any(segment => segment is "" or "." or "..") || unixType == 0xA000 ||
                    relative.EndsWith(".pth", StringComparison.OrdinalIgnoreCase) ||
                    relative.EndsWith(".pyc", StringComparison.OrdinalIgnoreCase) ||
                    relative.EndsWith(".pyo", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("SERVER_DEPENDENCY_WHEEL_ENTRY_INVALID");
                if (directoryEntry) continue;
                if (entry.Length < 0 || entry.Length > MaximumEntryBytes || (expandedBytes += entry.Length) > MaximumExpandedBytes)
                    throw new InvalidOperationException("SERVER_DEPENDENCY_EXPANDED_SIZE_LIMIT");
                var runtimePath = "vendor/" + relative;
                if (!runtimeFiles.TryAdd(runtimePath, ReadEntry(entry)))
                    throw new InvalidOperationException("SERVER_DEPENDENCY_WHEEL_ENTRY_COLLISION");
            }
        }
        if (!runtimeFiles.ContainsKey("vendor/aioquic/__init__.py") || !runtimeFiles.ContainsKey("vendor/h2/__init__.py") ||
            !runtimeFiles.ContainsKey("vendor/pylsqpack/__init__.py"))
            throw new InvalidOperationException("SERVER_DEPENDENCY_REQUIRED_PACKAGE_MISSING");
        if (!runtimeFiles.TryAdd("vendor/protocol-dependencies.lock.json", lockBytes))
            throw new InvalidOperationException("SERVER_DEPENDENCY_LOCK_COLLISION");
    }

    private static byte[] ReadEntry(ZipArchiveEntry entry)
    {
        using var input = entry.Open();
        using var output = new MemoryStream(checked((int)entry.Length));
        input.CopyTo(output);
        if (output.Length != entry.Length) throw new InvalidOperationException("SERVER_DEPENDENCY_WHEEL_ENTRY_TRUNCATED");
        return output.ToArray();
    }

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._+-]*\\.whl$", RegexOptions.CultureInvariant)]
    private static partial Regex SafeWheelName();

    [GeneratedRegex("^[a-f0-9]{64}$", RegexOptions.CultureInvariant)]
    private static partial Regex LowerSha256();
}
