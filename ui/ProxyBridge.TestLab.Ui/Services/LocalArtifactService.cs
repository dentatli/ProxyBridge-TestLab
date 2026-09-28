using System.Security.Cryptography;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record LocalProtocolRuntimeStatus(bool Ready, string Status, string Detail);
public sealed record BrowserFileVersionIdentity(string? ProductName, string? OriginalFilename, string? Version);
public sealed record LocalBrowserRuntimeStatus(
    bool Ready,
    string Status,
    string Detail,
    string? ExecutablePath,
    string? BrowserIdentity,
    string? Version,
    string? Sha256);

public interface ILocalRuntimeStatusProvider
{
    LocalProtocolRuntimeStatus GetProtocolRuntimeStatus();
}

public sealed class LocalArtifactService(
    AppPaths appPaths,
    AppStoragePaths storagePaths,
    ServerProtocolPortCatalog portCatalog,
    ProtocolCertificateStore certificateStore) : ILocalRuntimeStatusProvider
{
    public string ClientExecutablePath => Path.Combine(appPaths.RepositoryRoot, "bin", "pb_net_client.exe");
    public string ProtocolWorkerRoot => Path.Combine(appPaths.RepositoryRoot, "bin", "protocol-worker");
    public string ProtocolPythonPath => Path.Combine(ProtocolWorkerRoot, "runtime", "python", "python.exe");
    public string ProtocolWorkerEntrypointPath => Path.Combine(ProtocolWorkerRoot, "worker", "pb_protocol_worker.py");
    public string ProtocolWorkerManifestPath => Path.Combine(ProtocolWorkerRoot, "worker", "plugins", "manifest.json");
    public string ProtocolEvidenceContractPath => Path.Combine(ProtocolWorkerRoot, "config", "protocol-evidence-contract.json");

    public LocalBrowserRuntimeStatus GetBrowserRuntimeStatus() => DiscoverBrowserFromAllowlistedCandidates(GetBrowserCandidates());

    public static LocalBrowserRuntimeStatus DiscoverBrowserFromAllowlistedCandidates(
        IEnumerable<string> candidates,
        Func<string, BrowserFileVersionIdentity?>? readVersionIdentity = null)
    {
        ArgumentNullException.ThrowIfNull(candidates);
        readVersionIdentity ??= path =>
        {
            var info = FileVersionInfo.GetVersionInfo(path);
            return new BrowserFileVersionIdentity(info.ProductName, info.OriginalFilename, info.FileVersion);
        };
        var supported = new Dictionary<string, BrowserIdentityRule>(StringComparer.OrdinalIgnoreCase)
        {
            ["msedge.exe"] = new("Microsoft Edge", "Microsoft Edge", ["msedge.exe"]),
            ["chrome.exe"] = new("Google Chrome", "Google Chrome", ["chrome.exe"]),
            ["chromium.exe"] = new("Chromium", "Chromium", ["chromium.exe", "chrome.exe"])
        };
        var queryFailed = false;
        foreach (var candidate in candidates.Where(path => !string.IsNullOrWhiteSpace(path)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                var fullPath = Path.GetFullPath(candidate);
                var fileName = Path.GetFileName(fullPath);
                if (!supported.TryGetValue(fileName, out var rule) || !File.Exists(fullPath)) continue;
                if ((File.GetAttributes(fullPath) & FileAttributes.ReparsePoint) != 0) continue;
                var identity = readVersionIdentity(fullPath);
                var originalName = Path.GetFileName(identity?.OriginalFilename);
                if (identity is null || string.IsNullOrWhiteSpace(identity.Version) ||
                    !string.Equals(identity.ProductName, rule.ProductName, StringComparison.OrdinalIgnoreCase) ||
                    !rule.OriginalFileNames.Contains(originalName, StringComparer.OrdinalIgnoreCase)) continue;
                return new LocalBrowserRuntimeStatus(
                    true,
                    "READY",
                    $"{rule.DisplayName} was discovered automatically and its file-version identity and integrity were verified.",
                    fullPath,
                    rule.DisplayName,
                    identity.Version,
                    ComputeSha256(fullPath));
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException or CryptographicException)
            {
                queryFailed = true;
            }
        }
        return new LocalBrowserRuntimeStatus(
            false,
            queryFailed ? "QUERY_FAILED" : "NOT_FOUND",
            queryFailed
                ? "A supported browser candidate could not be verified."
                : "No supported Microsoft Edge, Google Chrome, or Chromium installation was found.",
            null,
            null,
            null,
            null);
    }

    private static IEnumerable<string> GetBrowserCandidates()
    {
        static string Candidate(Environment.SpecialFolder folder, params string[] parts)
        {
            var root = Environment.GetFolderPath(folder);
            return string.IsNullOrWhiteSpace(root) ? string.Empty : Path.Combine([root, .. parts]);
        }

        yield return Candidate(Environment.SpecialFolder.ProgramFilesX86, "Microsoft", "Edge", "Application", "msedge.exe");
        yield return Candidate(Environment.SpecialFolder.ProgramFiles, "Microsoft", "Edge", "Application", "msedge.exe");
        yield return Candidate(Environment.SpecialFolder.ProgramFiles, "Google", "Chrome", "Application", "chrome.exe");
        yield return Candidate(Environment.SpecialFolder.ProgramFilesX86, "Google", "Chrome", "Application", "chrome.exe");
        yield return Candidate(Environment.SpecialFolder.LocalApplicationData, "Microsoft", "Edge", "Application", "msedge.exe");
        yield return Candidate(Environment.SpecialFolder.LocalApplicationData, "Google", "Chrome", "Application", "chrome.exe");
        yield return Candidate(Environment.SpecialFolder.ProgramFiles, "Chromium", "Application", "chromium.exe");
    }

    public IReadOnlyDictionary<string, string> GetProtectedDefaults()
    {
        var defaults = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["local_product.gui_path"] = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "ProxyBridge", "ProxyBridge.exe"),
            ["local_product.cli_path"] = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "ProxyBridge", "ProxyBridge_CLI.exe"),
            ["local_product.driver_path"] = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System), "drivers", "ProxyBridgeDrv.sys"),
            ["retention.evidence_root"] = Path.Combine(storagePaths.Root, "evidence")
        };

        var defaultKey = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ssh", "id_ed25519");
        if (File.Exists(defaultKey)) defaults["server_connection.private_key_path"] = defaultKey;
        return defaults;
    }

    public void AddValidationIssues(ICollection<FieldIssue> readiness)
    {
        if (!File.Exists(ClientExecutablePath))
        {
            readiness.Add(new FieldIssue(
                "local_client",
                "CLIENT_NOT_FOUND",
                "The bundled traffic client is missing. Build or restore bin\\pb_net_client.exe before running tests."));
        }
    }

    public void ApplyDerivedDefaults(PublicSettings settings, IDictionary<string, string> protectedValues)
    {
        if (!protectedValues.TryGetValue("server_connection.host", out var host) || !IPAddress.TryParse(host, out var address)) return;
        var field = address.AddressFamily == AddressFamily.InterNetwork
            ? "server_endpoint.vps_ipv4"
            : address.AddressFamily == AddressFamily.InterNetworkV6 ? "server_endpoint.vps_ipv6" : null;
        if (field is not null && !protectedValues.ContainsKey(field)) protectedValues[field] = address.ToString();
    }

    public void AddRunnerValues(SettingsSnapshot snapshot, IDictionary<string, string> values)
    {
        AddVerifiedArtifact(snapshot, "local_product.gui_path", "PB_PROXYBRIDGE_EXE", "PB_EXPECTED_PROXYBRIDGE_EXE_SHA256", values);
        AddVerifiedArtifact(snapshot, "local_product.cli_path", "PB_PROXYBRIDGE_CLI_EXE", "PB_EXPECTED_PROXYBRIDGE_CLI_SHA256", values);
        AddVerifiedArtifact(snapshot, "local_product.driver_path", "PB_DRIVER_PATH", "PB_EXPECTED_DRIVER_SHA256", values);

        if (!File.Exists(ClientExecutablePath)) throw new InvalidOperationException("AUTOMATIC_CLIENT_NOT_FOUND");
        values["PB_CLIENT_EXE"] = Path.GetFullPath(ClientExecutablePath);
        values["PB_EXPECTED_CLIENT_SHA256"] = ComputeSha256(ClientExecutablePath);
        AddProtocolRunnerValues(snapshot, values);
    }

    public void AddProtocolRunnerValues(SettingsSnapshot snapshot, IDictionary<string, string> values)
    {
        values["PB_VPS_SERVER_LOG"] = "/var/log/proxybridge-testlab/server.jsonl";
        values["PB_VPS_PROTOCOL_LOG"] = "/var/log/proxybridge-testlab/protocols.jsonl";
        values["PB_SSH_KNOWN_HOSTS"] = Path.GetFullPath(storagePaths.KnownHostsPath);
        values["PB_PROTOCOL_DNS_PORT"] = portCatalog["dns"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_HTTP_PORT"] = portCatalog["http"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_TLS_PORT"] = portCatalog["tls"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_HTTPS_PORT"] = portCatalog["https"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_HTTP2_PORT"] = portCatalog["http2"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_QUIC_HTTP3_PORT"] = portCatalog["quic_http3"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_WEBSOCKET_PORT"] = portCatalog["websocket"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_GRPC_PORT"] = portCatalog["grpc"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_WEBTRANSPORT_PORT"] = portCatalog["webtransport"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_FTP_PORT"] = portCatalog["ftp_control"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_SFTP_PORT"] = portCatalog["sftp"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_SMTP_PORT"] = portCatalog["smtp"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_SMTPS_PORT"] = portCatalog["smtps"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_IMAP_PORT"] = portCatalog["imap"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_IMAPS_PORT"] = portCatalog["imaps"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_POP3_PORT"] = portCatalog["pop3"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_POP3S_PORT"] = portCatalog["pop3s"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_MQTT_PORT"] = portCatalog["mqtt"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_MQTTS_PORT"] = portCatalog["mqtts"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_AMQP_PORT"] = portCatalog["amqp"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_AMQPS_PORT"] = portCatalog["amqps"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_NTP_PORT"] = portCatalog["ntp"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_IRC_PORT"] = portCatalog["irc"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_IRCS_PORT"] = portCatalog["ircs"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_MULTIPEER_PORT"] = portCatalog["multipeer"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_STUN_TURN_PORT"] = portCatalog["stun_turn"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_RTP_MEDIA_PORT"] = portCatalog["realtime_start"].ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_RECEIVE_ONLY_PORT"] = (portCatalog["realtime_start"] + 1).ToString(System.Globalization.CultureInfo.InvariantCulture);
        values["PB_PROTOCOL_FAILURE_CONTROL_PORT"] = portCatalog["failure_control"].ToString(System.Globalization.CultureInfo.InvariantCulture);

        var protocolStatus = GetProtocolRuntimeStatus();
        if (protocolStatus.Ready)
        {
            _ = certificateStore.GetOrCreate();
            values["PB_PROTOCOL_PYTHON_EXE"] = Path.GetFullPath(ProtocolPythonPath);
            values["PB_EXPECTED_PROTOCOL_PYTHON_SHA256"] = ComputeSha256(ProtocolPythonPath);
            values["PB_PROTOCOL_WORKER_ENTRYPOINT"] = Path.GetFullPath(ProtocolWorkerEntrypointPath);
            values["PB_EXPECTED_PROTOCOL_WORKER_SHA256"] = ComputeSha256(ProtocolWorkerEntrypointPath);
            values["PB_PROTOCOL_WORKER_MANIFEST"] = Path.GetFullPath(ProtocolWorkerManifestPath);
            values["PB_EXPECTED_PROTOCOL_MANIFEST_SHA256"] = ComputeSha256(ProtocolWorkerManifestPath);
            values["PB_PROTOCOL_EVIDENCE_CONTRACT"] = Path.GetFullPath(ProtocolEvidenceContractPath);
            values["PB_EXPECTED_PROTOCOL_EVIDENCE_CONTRACT_SHA256"] = ComputeSha256(ProtocolEvidenceContractPath);
            values["PB_PROTOCOL_CA_PEM"] = Path.GetFullPath(storagePaths.ProtocolCaPemPath);
            values["PB_EXPECTED_PROTOCOL_CA_SHA256"] = ComputeSha256(storagePaths.ProtocolCaPemPath);
            values["PB_PROTOCOL_WORKER_APPLICATION_BASENAME"] = Path.GetFileName(ProtocolPythonPath);
            values["PB_PROTOCOL_WORKER_APPLICATION_FULLPATH"] = Path.GetFullPath(ProtocolPythonPath);
        }
        var browserStatus = GetBrowserRuntimeStatus();
        if (browserStatus.Ready)
        {
            var browserPath = browserStatus.ExecutablePath!;
            values["PB_BROWSER_EXE"] = browserPath;
            values["PB_EXPECTED_BROWSER_SHA256"] = browserStatus.Sha256!;
            values["PB_BROWSER_APPLICATION_BASENAME"] = Path.GetFileName(browserPath)
                ?? throw new InvalidOperationException("AUTOMATIC_BROWSER_BASENAME_MISSING");
            values["PB_BROWSER_APPLICATION_FULLPATH"] = browserPath;
            values["PB_BROWSER_VERSION"] = browserStatus.Version!;
        }
    }

    public LocalProtocolRuntimeStatus GetProtocolRuntimeStatus()
    {
        var required = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["runtime/python/python.exe"] = ProtocolPythonPath,
            ["worker/pb_protocol_worker.py"] = ProtocolWorkerEntrypointPath,
            ["worker/plugins/manifest.json"] = ProtocolWorkerManifestPath,
            ["config/protocol-evidence-contract.json"] = ProtocolEvidenceContractPath,
            ["BUNDLE-MANIFEST.json"] = Path.Combine(ProtocolWorkerRoot, "BUNDLE-MANIFEST.json"),
            ["SHA256SUMS.txt"] = Path.Combine(ProtocolWorkerRoot, "SHA256SUMS.txt")
        };
        var missing = required.Where(item => !File.Exists(item.Value)).Select(item => item.Key).ToArray();
        if (missing.Length != 0)
            return new LocalProtocolRuntimeStatus(false, "MISSING", "The packaged protocol runtime is incomplete: " + string.Join(", ", missing));

        try
        {
            VerifyProtocolBundle(required.Keys);
            return new LocalProtocolRuntimeStatus(true, "READY", "The bundled x64 protocol runtime and every declared file hash are verified.");
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException or CryptographicException or InvalidOperationException or KeyNotFoundException or FormatException)
        {
            return new LocalProtocolRuntimeStatus(false, "INTEGRITY_FAILED", "The packaged protocol runtime failed its manifest or SHA-256 integrity check.");
        }
    }

    private void VerifyProtocolBundle(IEnumerable<string> requiredRelativePaths)
    {
        var root = Path.GetFullPath(ProtocolWorkerRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var manifestPath = Path.Combine(ProtocolWorkerRoot, "BUNDLE-MANIFEST.json");
        using (var document = JsonDocument.Parse(File.ReadAllBytes(manifestPath)))
        {
            var manifest = document.RootElement;
            if (manifest.ValueKind != JsonValueKind.Object ||
                manifest.GetProperty("schema_version").GetInt32() != 1 ||
                manifest.GetProperty("runtime_id").GetString() != "proxybridge-protocol-worker" ||
                manifest.GetProperty("architecture").GetString() != "x64" ||
                manifest.GetProperty("entrypoint").GetString() != "worker/pb_protocol_worker.py" ||
                manifest.GetProperty("plugin_manifest").GetString() != "worker/plugins/manifest.json" ||
                !manifest.GetProperty("self_test_passed").GetBoolean() ||
                manifest.GetProperty("network_installation_allowed").GetBoolean())
                throw new InvalidOperationException("PROTOCOL_BUNDLE_MANIFEST_INVALID");
        }

        var sumsPath = Path.Combine(ProtocolWorkerRoot, "SHA256SUMS.txt");
        var sumsBytes = File.ReadAllBytes(sumsPath);
        if (sumsBytes.Length >= 3 && sumsBytes[0] == 0xEF && sumsBytes[1] == 0xBB && sumsBytes[2] == 0xBF)
            throw new InvalidOperationException("PROTOCOL_BUNDLE_SUMS_BOM_FORBIDDEN");
        var declared = new HashSet<string>(StringComparer.Ordinal);
        foreach (var rawLine in System.Text.Encoding.UTF8.GetString(sumsBytes).Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            if (rawLine.Length < 67 || rawLine[64] != ' ' || rawLine[65] != ' ')
                throw new InvalidOperationException("PROTOCOL_BUNDLE_SUMS_FORMAT_INVALID");
            var expected = rawLine[..64];
            if (expected.Any(character => !Uri.IsHexDigit(character)))
                throw new InvalidOperationException("PROTOCOL_BUNDLE_SUMS_HASH_INVALID");
            var relative = rawLine[66..];
            if (string.IsNullOrWhiteSpace(relative) || Path.IsPathRooted(relative) || relative.Contains('\\') ||
                relative.Split('/').Any(segment => segment is "" or "." or "..") || !declared.Add(relative))
                throw new InvalidOperationException("PROTOCOL_BUNDLE_SUMS_PATH_INVALID");
            var candidate = Path.GetFullPath(Path.Combine(ProtocolWorkerRoot, relative.Replace('/', Path.DirectorySeparatorChar)));
            if (!candidate.StartsWith(root, StringComparison.OrdinalIgnoreCase) || !File.Exists(candidate) ||
                (File.GetAttributes(candidate) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("PROTOCOL_BUNDLE_FILE_INVALID");
            if (!string.Equals(ComputeSha256(candidate), expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("PROTOCOL_BUNDLE_HASH_MISMATCH");
        }
        foreach (var required in requiredRelativePaths.Where(path => path != "SHA256SUMS.txt"))
        {
            if (!declared.Contains(required)) throw new InvalidOperationException("PROTOCOL_BUNDLE_REQUIRED_SUM_MISSING");
        }
    }

    private static void AddVerifiedArtifact(
        SettingsSnapshot snapshot,
        string fieldId,
        string pathKey,
        string hashKey,
        IDictionary<string, string> values)
    {
        if (!snapshot.ProtectedValues.TryGetValue(fieldId, out var path) || string.IsNullOrWhiteSpace(path))
            throw new InvalidOperationException($"AUTOMATIC_HASH_PATH_MISSING_{pathKey}");
        if (!File.Exists(path)) throw new InvalidOperationException($"AUTOMATIC_HASH_FILE_MISSING_{pathKey}");
        values[pathKey] = Path.GetFullPath(path);
        values[hashKey] = ComputeSha256(path);
    }

    public static string ComputeSha256(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    private sealed record BrowserIdentityRule(
        string DisplayName,
        string ProductName,
        IReadOnlyList<string> OriginalFileNames);
}
