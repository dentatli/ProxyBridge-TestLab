using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record TrafficRuntimeApplyRequest(string PlanId);
public sealed record TrafficCaseRequest(string Id, string Duration, string Load);
public sealed record TrafficRunRequest(string BuildId, TrafficCaseRequest[] Cases, bool DebuggerInactive, bool AllowLongRun = false, bool ContinueAfterFailure = false);
public sealed record TrafficRuntimePlan(string PlanId, string BundleSha256, string[] Files, int[] TcpPorts, int[] UdpPorts,
    string UbuntuVersion, DateTimeOffset ExpiresUtc, string State);

/// <summary>Independent traffic runtime; existing protocol service and frozen diagnostic kits remain separate.</summary>
public sealed partial class TrafficRuntimeService(AppPaths app, AppStoragePaths storage, DpapiSecretProtector protector,
    RemoteUbuntuService remote, BenchmarkBuildCatalog builds, BenchmarkLabService lab, IHostApplicationLifetime lifetime) : IHostedService
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private TrafficRuntimePlan? _plan;
    private string? _binding;
    private string _state = "VALIDATION_REQUIRED";
    private string? _error;
    private DateTimeOffset? _checked;
    private bool _applyInFlight;
    private readonly object _stateGate = new();
    private CancellationToken Token => lifetime.ApplicationStopping;
    internal string Root => Path.Combine(storage.Root, "traffic-lab");
    private TrafficApplyCheckpoint ApplyCheckpoint => new(Root);

    public JsonElement Catalog()
    {
        using var document = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(app.RepositoryRoot, "config", "traffic-workloads.json")));
        return document.RootElement.Clone();
    }

    public object State()
    {
        lock (_stateGate) return new { state = ApplyCheckpoint.Pending ? (_applyInFlight ? "APPLYING" : "APPLY_UNKNOWN") :
                _checked is null || DateTimeOffset.UtcNow - _checked > TimeSpan.FromMinutes(2) ? "VALIDATION_REQUIRED" : _state,
            error = ApplyCheckpoint.Pending && !_applyInFlight ? "TRAFFIC_APPLY_OUTCOME_UNKNOWN" : _error,
            plan = ApplyCheckpoint.Pending ? null : _plan, checkedAtUtc = _checked, run = _run, busy = _gate.CurrentCount == 0,
            administrator = Administrator(), supports_safe_continuation = true };
    }

    private static bool Administrator()
    {
        if (!OperatingSystem.IsWindows()) return false;
        using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
        return new System.Security.Principal.WindowsPrincipal(identity).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
    }

    public async Task<TrafficRuntimePlan> PlanAsync()
    {
        if (!await _gate.WaitAsync(0, Token)) throw new InvalidOperationException("TRAFFIC_OPERATION_ACTIVE");
        try
        {
            return await remote.WithTrafficContextAsync(async (target, paths, token) =>
            {
                var payload = BuildPayload(target, paths, "inspect");
                var observed = await ExecuteAsync(target, paths, payload, token);
                ApplyCheckpoint.ResolveInspection(observed.GetProperty("state").GetString()!,payload.Bundle,TargetIdentity(target,paths));
                var plan = new TrafficRuntimePlan(Guid.NewGuid().ToString("N"), payload.Bundle,
                    payload.Hashes.Keys.Order(StringComparer.Ordinal).ToArray(), [42501,42502,42503,42511,42512,42513,42514,42515,42516,42517,42518,42519,42522,42523,42524,42525,42526,42527,42528,42529,42530,42531,42532,42533,42535], [42501,42502,42515,42520,42521], "22.04",
                    DateTimeOffset.UtcNow.AddMinutes(10), observed.GetProperty("state").GetString()!);
                lock (_stateGate) { _plan = plan; _binding = Binding(target,paths); _state = plan.State; _checked = DateTimeOffset.UtcNow; _error = null; }
                return plan;
            });
        }
        catch (Exception) { lock (_stateGate) { _plan = null; _checked = null; } throw; }
        finally { _gate.Release(); }
    }

    public async Task<object> ApplyAsync(TrafficRuntimeApplyRequest request)
    {
        if (!await _gate.WaitAsync(0, Token)) throw new InvalidOperationException("TRAFFIC_OPERATION_ACTIVE");
        try
        {
            return await remote.WithTrafficContextAsync<object>(async (target, paths, token) =>
            {
                TrafficRuntimePlan? plan;
                string? binding;
                lock (_stateGate) { plan = _plan; binding = _binding; _plan = null; _binding = null; _checked = null; }
                var payload = BuildPayload(target, paths, "apply");
                if (plan is null || plan.PlanId != request.PlanId || plan.ExpiresUtc < DateTimeOffset.UtcNow ||
                    binding != Binding(target,paths) || payload.Bundle != plan.BundleSha256)
                    throw new InvalidOperationException("TRAFFIC_PLAN_STALE");
                using var checkpoint = ApplyCheckpoint.Begin(payload.Bundle,TargetIdentity(target,paths));
                lock (_stateGate) _applyInFlight = true;
                JsonElement observed;
                try
                {
                    observed = await ExecuteAsync(target, paths, payload, token);
                    checkpoint.Complete(observed.GetProperty("state").GetString()!);
                }
                catch (TrafficRemoteOperationFailure error) { checkpoint.Complete("ERROR",error.Message); throw; }
                lock (_stateGate) { _state = observed.GetProperty("state").GetString()!; _checked = DateTimeOffset.UtcNow; _plan = null; _error = null; }
                return observed;
            });
        }
        catch (Exception error) { lock (_stateGate) { _plan = null; _binding = null; _checked = null;
            _error = System.Text.RegularExpressions.Regex.IsMatch(error.Message,@"\ATRAFFIC_[A-Z0-9_]+\z") ? error.Message : null; } throw; }
        finally { lock (_stateGate) _applyInFlight = false; _gate.Release(); }
    }

    private Payload BuildPayload(ServerTarget target, AppStoragePaths paths, string action)
    {
        if (!System.Net.IPAddress.TryParse(target.Host, out var address) || address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork)
            throw new InvalidOperationException("TRAFFIC_VERIFIED_IPV4_TARGET_REQUIRED");
        paths.EnsureSecureDirectories();
        var secretPath = Path.Combine(paths.ConfigRoot, "traffic-secret.dpapi");
        byte[] secret;
        if (File.Exists(secretPath)) secret = protector.Unprotect(File.ReadAllBytes(secretPath));
        else
        {
            secret = RandomNumberGenerator.GetBytes(32);
            var encrypted = protector.Protect(secret);
            try { using var file = new FileStream(secretPath, FileMode.CreateNew, FileAccess.Write, FileShare.None); file.Write(encrypted); }
            finally { CryptographicOperations.ZeroMemory(encrypted); }
        }
        if (secret.Length != 32) throw new InvalidOperationException("TRAFFIC_SECRET_INVALID");
        try
        {
            var files = new SortedDictionary<string, string>(StringComparer.Ordinal);
            var hashes = new SortedDictionary<string, string>(StringComparer.Ordinal);
            var source = Path.Combine(app.RepositoryRoot, "src", "trafficlab");
            foreach (var file in Directory.EnumerateFiles(source, "*.py").Order(StringComparer.Ordinal))
            {
                if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0) throw new InvalidOperationException("TRAFFIC_SOURCE_REPARSE_POINT");
                var name = "trafficlab/" + Path.GetFileName(file);
                var bytes = File.ReadAllBytes(file);
                files[name] = Convert.ToBase64String(bytes);
                hashes[name] = Hash(bytes);
            }
            var catalog = File.ReadAllBytes(Path.Combine(app.RepositoryRoot, "config", "traffic-workloads.json"));
            files["traffic-workloads.json"] = Convert.ToBase64String(catalog);
            hashes["traffic-workloads.json"] = Hash(catalog);
            var dependencyLock = File.ReadAllBytes(Path.Combine(app.RepositoryRoot, "vendor", "traffic-dependencies.lock.json"));
            files["traffic-dependencies.lock.json"] = Convert.ToBase64String(dependencyLock);
            hashes["traffic-dependencies.lock.json"] = Hash(dependencyLock);
            foreach (var file in TrafficDependencyFiles("linux-x64"))
            {
                var bytes = File.ReadAllBytes(file);
                var name = "wheels/" + Path.GetFileName(file);
                files[name] = Convert.ToBase64String(bytes);
                hashes[name] = Hash(bytes);
            }
            var configuration = JsonSerializer.SerializeToUtf8Bytes(new { secret = Convert.ToHexString(secret).ToLowerInvariant(), bind = "0.0.0.0",
                port = 42501, proxy_port = 42502, control_port = 42503, max_connections = 2048, origin_addresses = new[] { target.Host, "127.0.0.1" },
                application_ports = new Dictionary<string,int> { ["http"] = 42511, ["tls"] = 42512, ["https"] = 42513,
                    ["websocket"] = 42514, ["websocket-tls"] = 42532, ["dns-tcp"] = 42515, ["dns-udp"] = 42515,
                    ["dns-tls"] = 42533, ["dns-https"] = 42535,
                    ["ssh"] = 42516, ["sftp"] = 42517, ["http2"] = 42518, ["grpc"] = 42519, ["quic"] = 42520, ["http3"] = 42521,
                    ["smtp"] = 42522, ["smtps"] = 42523, ["imap"] = 42524, ["imaps"] = 42525, ["mqtt"] = 42526, ["mqtts"] = 42527,
                    ["pop3"] = 42528, ["pop3s"] = 42529, ["amqp"] = 42530, ["amqps"] = 42531 },
                tls_certificate_file = "pki/server.pem", tls_key_file = "pki/server.key", tls_ca_file = "pki/ca.pem", ssh_host_key_file = "pki/ssh_host.key" });
            var configHash = Hash(configuration);
            var bundle = Hash(JsonSerializer.SerializeToUtf8Bytes(new { hashes, configHash, target = PayloadBinding(target) }));
            return new(bundle, hashes, files, Convert.ToBase64String(configuration), configHash, Convert.ToHexString(secret).ToLowerInvariant(), action);
        }
        finally { CryptographicOperations.ZeroMemory(secret); }
    }

    private IEnumerable<string> TrafficDependencyFiles(string platform)
    {
        using var document = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(app.RepositoryRoot, "vendor", "traffic-dependencies.lock.json")));
        var data = document.RootElement;
        if (data.GetProperty("schema_version").GetInt32() != 1 || data.GetProperty("network_installation_allowed").GetBoolean())
            throw new InvalidOperationException("TRAFFIC_DEPENDENCY_LOCK_INVALID");
        var artifacts = data.GetProperty("artifacts").EnumerateArray().Where(row => row.GetProperty("platform").GetString() == platform).ToArray();
        if (artifacts.Length != data.GetProperty("packages").GetArrayLength()) throw new InvalidOperationException("TRAFFIC_DEPENDENCY_SET_INCOMPLETE");
        foreach (var row in artifacts)
        {
            var name = row.GetProperty("file").GetString()!;
            if (!System.Text.RegularExpressions.Regex.IsMatch(name, @"\A[A-Za-z0-9_.-]+\.whl\z")) throw new InvalidOperationException("TRAFFIC_DEPENDENCY_NAME_INVALID");
            var path = Path.Combine(app.RepositoryRoot, "vendor", "traffic-wheelhouse", platform, name);
            if (!File.Exists(path) || File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint) || new FileInfo(path).Length != row.GetProperty("bytes").GetInt64() ||
                Hash(File.ReadAllBytes(path)) != row.GetProperty("sha256").GetString()) throw new InvalidOperationException("TRAFFIC_DEPENDENCY_HASH_MISMATCH");
            yield return path;
        }
    }

    private async Task<JsonElement> ExecuteAsync(ServerTarget target, AppStoragePaths paths, Payload payload, CancellationToken token)
    {
        var encoded = Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(new { action = payload.Action, bundle_sha256 = payload.Bundle,
            hashes = payload.Hashes, sources = payload.Sources, configuration = payload.Configuration, config_sha256 = payload.ConfigHash }));
        var source = payload.Sources["trafficlab/deploy.py"];
        var script = $"import base64,json\nexec(compile(base64.b64decode('{source}'),'traffic-deploy','exec'))\nprint(json.dumps(invoke(json.loads(base64.b64decode('{encoded}')))),flush=True)\n";
        return await new OpenSshServerTransport(paths).ExecuteTrafficPythonAsync(target, script, token);
    }

    private static string TargetIdentity(ServerTarget target,AppStoragePaths paths) =>
        Hash(Encoding.UTF8.GetBytes($"{target.Host}\n{target.Port}\n{Hash(File.ReadAllBytes(paths.KnownHostsPath))}"));
    private static string Binding(ServerTarget target,AppStoragePaths paths) =>
        Hash(Encoding.UTF8.GetBytes($"{TargetIdentity(target,paths)}\n{target.PrivateKeyPath}"));
    private static string PayloadBinding(ServerTarget target) => Hash(Encoding.UTF8.GetBytes($"{target.Host}\n{target.Port}\n{target.PrivateKeyPath}"));
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private sealed record Payload(string Bundle, SortedDictionary<string,string> Hashes, SortedDictionary<string,string> Sources,
        string Configuration, string ConfigHash, string Secret, string Action);
}
