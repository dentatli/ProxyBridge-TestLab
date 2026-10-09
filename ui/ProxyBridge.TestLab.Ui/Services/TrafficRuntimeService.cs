using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record TrafficRuntimeApplyRequest(string PlanId);
public sealed record TrafficCaseRequest(string Id, string Duration, string Load);
public sealed record TrafficRunRequest(string BuildId, TrafficCaseRequest[] Cases, bool DebuggerInactive, bool AllowLongRun = false);
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
    private readonly object _stateGate = new();
    private CancellationToken Token => lifetime.ApplicationStopping;
    internal string Root => Path.Combine(storage.Root, "traffic-lab");

    public JsonElement Catalog()
    {
        using var document = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(app.RepositoryRoot, "config", "traffic-workloads.json")));
        return document.RootElement.Clone();
    }

    public object State()
    {
        lock (_stateGate) return new { state = _checked is null || DateTimeOffset.UtcNow - _checked > TimeSpan.FromMinutes(2) ? "VALIDATION_REQUIRED" : _state,
            error = _error, plan = _plan, checkedAtUtc = _checked, run = _run, busy = _gate.CurrentCount == 0,
            administrator = Administrator() };
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
                var plan = new TrafficRuntimePlan(Guid.NewGuid().ToString("N"), payload.Bundle,
                    payload.Hashes.Keys.Order(StringComparer.Ordinal).ToArray(), [42501,42502,42503], [42501,42502], "22.04",
                    DateTimeOffset.UtcNow.AddMinutes(10), observed.GetProperty("state").GetString()!);
                lock (_stateGate) { _plan = plan; _binding = Binding(target); _state = plan.State; _checked = DateTimeOffset.UtcNow; _error = null; }
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
                lock (_stateGate) plan = _plan;
                var payload = BuildPayload(target, paths, "apply");
                if (plan is null || plan.PlanId != request.PlanId || plan.ExpiresUtc < DateTimeOffset.UtcNow ||
                    _binding != Binding(target) || payload.Bundle != plan.BundleSha256)
                    throw new InvalidOperationException("TRAFFIC_PLAN_STALE");
                var observed = await ExecuteAsync(target, paths, payload, token);
                lock (_stateGate) { _state = observed.GetProperty("state").GetString()!; _checked = DateTimeOffset.UtcNow; _plan = null; _error = null; }
                return observed;
            });
        }
        catch (Exception) { lock (_stateGate) { _checked = null; } throw; }
        finally { _gate.Release(); }
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
            var configuration = JsonSerializer.SerializeToUtf8Bytes(new { secret = Convert.ToHexString(secret).ToLowerInvariant(), bind = "0.0.0.0",
                port = 42501, proxy_port = 42502, control_port = 42503, max_connections = 2048, origin_addresses = new[] { target.Host, "127.0.0.1" } });
            var configHash = Hash(configuration);
            var bundle = Hash(JsonSerializer.SerializeToUtf8Bytes(new { hashes, configHash, target = Binding(target) }));
            return new(bundle, hashes, files, Convert.ToBase64String(configuration), configHash, Convert.ToHexString(secret).ToLowerInvariant(), action);
        }
        finally { CryptographicOperations.ZeroMemory(secret); }
    }

    private async Task<JsonElement> ExecuteAsync(ServerTarget target, AppStoragePaths paths, Payload payload, CancellationToken token)
    {
        var encoded = Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(new { action = payload.Action, bundle_sha256 = payload.Bundle,
            hashes = payload.Hashes, sources = payload.Sources, configuration = payload.Configuration, config_sha256 = payload.ConfigHash }));
        var source = payload.Sources["trafficlab/deploy.py"];
        var script = $"import base64,json\nexec(compile(base64.b64decode('{source}'),'traffic-deploy','exec'))\nprint(json.dumps(invoke(json.loads(base64.b64decode('{encoded}')))),flush=True)\n";
        return await new OpenSshServerTransport(paths).ExecuteTrafficPythonAsync(target, script, token);
    }

    private static string Binding(ServerTarget target) => Hash(Encoding.UTF8.GetBytes($"{target.Host}\n{target.Port}\n{target.PrivateKeyPath}"));
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private sealed record Payload(string Bundle, SortedDictionary<string,string> Hashes, SortedDictionary<string,string> Sources,
        string Configuration, string ConfigHash, string Secret, string Action);
}
