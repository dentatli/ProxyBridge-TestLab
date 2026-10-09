using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed partial class TrafficRuntimeService
{
    private object? _run;
    private string? _activeDirectory;
    private Task? _execution;
    private static readonly JsonSerializerOptions Pretty = new() { WriteIndented = true };

    public async Task<object> StartAsync(TrafficRunRequest request)
    {
        if (!Administrator()) throw new InvalidOperationException("TRAFFIC_ADMINISTRATOR_REQUIRED");
        if (!request.DebuggerInactive) throw new InvalidOperationException("TRAFFIC_DEBUGGER_STATE_REQUIRED");
        var catalog = Catalog();
        var known = catalog.GetProperty("cases").EnumerateArray().Select(row => row.GetProperty("id").GetString()).ToHashSet();
        if (request.Cases is null || request.Cases.Length is < 1 or > 16 || request.Cases.Any(row => row is null || !known.Contains(row.Id) ||
            row.Duration is not ("SHORT" or "NORMAL" or "LONG") || row.Load is not ("LOW" or "HIGH")) ||
            request.Cases.Select(row => row.Id).Distinct().Count() != request.Cases.Length)
            throw new InvalidOperationException("TRAFFIC_CASE_SELECTION_INVALID");
        if (Estimate(request.Cases) > 300 && !request.AllowLongRun) throw new InvalidOperationException("TRAFFIC_LONG_RUN_CONFIRMATION_REQUIRED");
        if (!await _gate.WaitAsync(0, Token)) throw new InvalidOperationException("TRAFFIC_OPERATION_ACTIVE");
        try
        {
            var selected = await builds.RequestAsync(request.BuildId, Token);
            if (selected.Contract != "driver") throw new InvalidOperationException("TRAFFIC_DRIVER_ADAPTER_REQUIRED");
            AppStoragePaths.EnsureSecureDirectory(Root);
            var id = DateTimeOffset.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N");
            var directory = Path.Combine(Root, id);
            AppStoragePaths.EnsureSecureDirectory(directory);
            var attempt = new { id, state = "PREPARING", started_at_utc = DateTimeOffset.UtcNow, build_id = request.BuildId,
                cases = request.Cases, estimate_seconds = Estimate(request.Cases), complete = false, cleanup_verified = false };
            await WriteAsync(Path.Combine(directory, "attempt.json"), attempt);
            lock (_stateGate) { _run = attempt; _activeDirectory = directory; _checked = null; }
            _execution = Task.Run(async () =>
            {
                try { await ExecuteRunAsync(request, selected, directory, id); }
                catch (Exception)
                {
                    lock (_stateGate) { _run = new { id, state = "FAILED", complete = false, cleanup_verified = false, error = "TRAFFIC_RUN_OR_STORAGE_FAILED" }; _activeDirectory = null; _checked = null; }
                }
                finally { _gate.Release(); }
            });
            return attempt;
        }
        catch { _gate.Release(); throw; }
    }

    public object Stop()
    {
        string? directory;
        lock (_stateGate) directory = _activeDirectory;
        if (directory is null) throw new InvalidOperationException("TRAFFIC_NO_ACTIVE_RUN");
        File.WriteAllText(Path.Combine(directory, "cancel.requested"), "cancel\n");
        return new { state = "STOP_REQUESTED" };
    }

    public object History(int skip = 0, int take = 10)
    {
        skip = Math.Max(0, skip); take = Math.Clamp(take, 1, 25);
        if (!Directory.Exists(Root)) return new { items = Array.Empty<object>(), has_more = false, next_skip = 0 };
        var items = new List<JsonElement>();
        var directories = Directory.EnumerateDirectories(Root).Where(directory => File.Exists(Path.Combine(directory, "attempt.json"))).OrderDescending().ToArray();
        foreach (var directory in directories.Skip(skip).Take(take))
        {
            var path = Path.Combine(directory, "attempt.json");
            if (!File.Exists(path) || new FileInfo(path).Length > 64 * 1024 * 1024 || File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) continue;
            try
            {
                using var document = JsonDocument.Parse(File.ReadAllBytes(path));
                var row = document.RootElement.Clone();
                if (directory != _activeDirectory && row.GetProperty("state").GetString() is "PREPARING" or "RUNNING")
                {
                    var values = row.EnumerateObject().ToDictionary(property => property.Name, property => property.Value.Clone());
                    values["state"] = JsonSerializer.SerializeToElement("INTERRUPTED");
                    values["complete"] = JsonSerializer.SerializeToElement(false);
                    values["cleanup_verified"] = JsonSerializer.SerializeToElement(false);
                    row = JsonSerializer.SerializeToElement(values);
                }
                items.Add(row);
            }
            catch (JsonException) { }
        }
        return new { items, has_more = skip + take < directories.Length, next_skip = skip + take };
    }

    public object Comparison()
    {
        var latest = new Dictionary<string, object>(StringComparer.Ordinal);
        var barriers = new HashSet<string>(StringComparer.Ordinal);
        if (!Directory.Exists(Root)) return new { items = latest.Values };
        foreach (var directory in Directory.EnumerateDirectories(Root).OrderDescending())
        {
            var path = Path.Combine(directory, "attempt.json");
            if (!File.Exists(path) || new FileInfo(path).Length > 64 * 1024 * 1024 || File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) continue;
            try
            {
                using var document = JsonDocument.Parse(File.ReadAllBytes(path));
                var attempt = document.RootElement;
                if (!attempt.TryGetProperty("build_id", out var build) || !attempt.TryGetProperty("cases", out var cases)) continue;
                foreach (var choice in cases.EnumerateArray())
                {
                    string Value(string name) => (choice.TryGetProperty(name, out var lower) ? lower : choice.GetProperty(char.ToUpperInvariant(name[0]) + name[1..])).GetString()!;
                    var id = Value("id"); var duration = Value("duration"); var load = Value("load");
                    JsonElement? result = null;
                    if (attempt.TryGetProperty("results", out var results))
                        foreach (var row in results.EnumerateArray()) if (row.GetProperty("case_id").GetString() == id) { result = row.Clone(); break; }
                    var conditions = result is not null && result.Value.TryGetProperty("conditions", out var observed) ? observed : default;
                    var matching = conditions.ValueKind == JsonValueKind.Object && conditions.TryGetProperty("origin_physical_memory_bytes", out var memory) &&
                        memory.ValueKind == JsonValueKind.Number && conditions.TryGetProperty("local_runtime_sha256", out var identity) && identity.ValueKind == JsonValueKind.String ? conditions.EnumerateObject()
                        .Where(property => property.Name != "build_sha256").OrderBy(property => property.Name, StringComparer.Ordinal)
                        .ToDictionary(property => property.Name, property => property.Value.Clone()) : null;
                    var conditionId = matching is null ? "unverified" : Hash(JsonSerializer.SerializeToUtf8Bytes(matching));
                    var baseKey = $"{build.GetString()}|{id}|{duration}|{load}";
                    if (barriers.Contains(baseKey)) continue;
                    if (matching is null) barriers.Add(baseKey);
                    var key = $"{build.GetString()}|{id}|{duration}|{load}|{conditionId}";
                    if (latest.ContainsKey(key)) continue;
                    latest[key] = new { build_id = build.GetString(), case_id = id, duration, load, condition_id = conditionId,
                        attempt_id = attempt.GetProperty("id").GetString(), state = attempt.GetProperty("state").GetString(),
                        complete = result?.GetProperty("complete").GetBoolean() == true && attempt.GetProperty("state").GetString() is not ("PREPARING" or "RUNNING" or "INTERRUPTED"),
                        error = attempt.TryGetProperty("error", out var error) ? error.GetString() : null,
                        conditions = matching, result = ComparisonResult(result) };
                }
            }
            catch (Exception error) when (error is JsonException or IOException or KeyNotFoundException or InvalidOperationException) { }
        }
        return new { items = latest.Values };
    }

    private static object? ComparisonResult(JsonElement? result)
    {
        if (result is null) return null;
        var row = result.Value;
        var measurements = new List<object>();
        if (row.TryGetProperty("measurements", out var values))
            foreach (var measurement in values.EnumerateArray())
            {
                JsonElement? Field(string name) => measurement.TryGetProperty(name, out var value) ? value.Clone() : null;
                int? peak = null;
                if (measurement.TryGetProperty("stages", out var stages))
                    foreach (var stage in stages.EnumerateArray())
                        if (stage.TryGetProperty("tcp_active_peak", out var count) && count.ValueKind == JsonValueKind.Number && count.TryGetInt32(out var observed)) peak = Math.Max(peak ?? 0, observed);
                measurements.Add(new { mode = Field("mode"), complete = Field("complete"), route_verified = Field("route_verified"),
                    overall = Field("overall"), resources = Field("resources"), tcp_active_peak = peak });
            }
        return new { complete = row.GetProperty("complete").GetBoolean(),
            errors = row.TryGetProperty("errors", out var errors) ? errors.Clone() : JsonSerializer.SerializeToElement(Array.Empty<string>()), measurements };
    }

    public object Progress()
    {
        lock (_stateGate)
        {
            var path = _activeDirectory is null ? null : Path.Combine(_activeDirectory, "progress.json");
            JsonElement? progress = null;
            if (path is not null && File.Exists(path) && new FileInfo(path).Length < 16384)
                try { using var doc = JsonDocument.Parse(File.ReadAllBytes(path)); progress = doc.RootElement.Clone(); } catch (IOException) { } catch (JsonException) { }
            return new { run = _run, progress, active = _activeDirectory is not null };
        }
    }

    private async Task ExecuteRunAsync(TrafficRunRequest request, ProductSelectionRequest selection, string directory, string id)
    {
        string? error = null;
        JsonElement? final = null;
        try
        {
            final = await remote.WithTrafficContextAsync(async (target, paths, token) =>
            {
                var payload = BuildPayload(target, paths, "inspect");
                var readiness = await ExecuteAsync(target, paths, payload, token);
                if (readiness.GetProperty("state").GetString() != "READY") throw new InvalidOperationException("TRAFFIC_RUNTIME_SETUP_REQUIRED");
                var observed = await lab.InspectAsync(selection, token);
                if (!observed.GetProperty("files_observed").GetBoolean() || observed.GetProperty("status").GetString() == "UNSUPPORTED_BEFORE_4_0_0")
                    throw new InvalidOperationException("TRAFFIC_PRODUCT_FILES_OR_VERSION_UNSUPPORTED");
                var build = await lab.BindBuildAsync(selection, observed, token);
                if (build.Id != request.BuildId) throw new InvalidOperationException("TRAFFIC_BUILD_CHANGED");
                var python = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Python", "Python311", "python.exe");
                if (!File.Exists(python)) throw new InvalidOperationException("TRAFFIC_PYTHON_311_REQUIRED");
                var cli = Path.Combine(selection.InstallationDirectory, "ProxyBridge_CLI.exe");
                var driver = selection.DriverPath ?? Path.Combine(selection.InstallationDirectory, "ProxyBridgeDrv.sys");
                var hashes = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                foreach (var row in observed.GetProperty("components").EnumerateArray())
                {
                    var path = row.GetProperty("id").GetString() == "driver" ? driver : Path.Combine(selection.InstallationDirectory, row.GetProperty("file_name").GetString()!);
                    hashes[path] = row.GetProperty("sha256").GetString()!;
                }
                var sourceFiles = Directory.EnumerateFiles(Path.Combine(app.RepositoryRoot, "src", "trafficlab"), "*.py")
                    .Concat(new[] { "scripts/Invoke-TrafficLabRun.ps1", "scripts/Assert-TrafficLabIdle.ps1", "modules/InterceptionState.psm1",
                        "modules/ProcessAdapter.psm1", "src/pb_service_query.cs", "src/pb_loaded_drivers.cs", "config/traffic-workloads.json", "bin/pb_console_host.exe", "bin/pb_wfp_state.exe" }
                        .Select(path => Path.Combine(app.RepositoryRoot, path))).Append(python).Append(typeof(TrafficRuntimeService).Assembly.Location);
                foreach (var file in sourceFiles)
                {
                    if (!File.Exists(file) || File.GetAttributes(file).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("TRAFFIC_LOCAL_ARTIFACT_MISSING_OR_REPARSE_POINT");
                    hashes[file] = Hash(File.ReadAllBytes(file));
                }
                var localRuntimeHash = Hash(JsonSerializer.SerializeToUtf8Bytes(sourceFiles.Order(StringComparer.Ordinal)
                    .ToDictionary(path => Path.GetFileName(path), path => hashes[path], StringComparer.Ordinal)));
                var binding = new { schema_version = 1, id, build_id = build.Id, build_sha256 = build.BundleSha256,
                    local_runtime_sha256 = localRuntimeHash,
                    host = target.Host, port = 42501, control_port = 42503, proxy_port = 42502, secret = payload.Secret,
                    remote_bundle_sha256 = payload.Bundle, root = app.RepositoryRoot, cli, driver, driver_sha256 = hashes[driver],
                    console_host = Path.Combine(app.RepositoryRoot, "bin", "pb_console_host.exe"), python, source_hashes = hashes,
                    cancellation_path = Path.Combine(directory, "cancel.requested"), debugger_inactive = request.DebuggerInactive,
                    cases = request.Cases.Select(row => new { case_id = row.Id, duration = row.Duration, load = row.Load }).ToArray() };
                var bindingPath = Path.Combine(directory, "binding-private.json");
                await WriteAsync(bindingPath, binding);
                await WriteAsync(Path.Combine(directory, "attempt.json"), new { id, state = "RUNNING", build_id = build.Id,
                    build_sha256 = build.BundleSha256, started_at_utc = DateTimeOffset.UtcNow, cases = request.Cases,
                    complete = false, cleanup_verified = false, remote_bundle_sha256 = payload.Bundle });
                using (var running = JsonDocument.Parse(await File.ReadAllBytesAsync(Path.Combine(directory, "attempt.json"))))
                    lock (_stateGate) _run = running.RootElement.Clone();
                var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true,
                    WorkingDirectory = app.RepositoryRoot, RedirectStandardOutput = true, RedirectStandardError = true };
                foreach (var value in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(app.RepositoryRoot,
                    "scripts", "Invoke-TrafficLabRun.ps1"), "-BindingPath", bindingPath, "-OutputRoot", directory }) start.ArgumentList.Add(value);
                using var process = Process.Start(start) ?? throw new InvalidOperationException("TRAFFIC_RUNNER_START_FAILED");
                var stdout = DrainAsync(process.StandardOutput);
                var stderr = DrainAsync(process.StandardError);
                using var registration = token.Register(() => { try { File.WriteAllText(Path.Combine(directory, "cancel.requested"), "shutdown\n"); } catch (IOException) { } });
                try
                {
                    await process.WaitForExitAsync(CancellationToken.None);
                    await Task.WhenAll(stdout, stderr);
                    var attemptPath = Path.Combine(directory, "attempt.json");
                    using var document = JsonDocument.Parse(await File.ReadAllBytesAsync(attemptPath));
                    var value = document.RootElement.Clone();
                    if (value.GetProperty("state").GetString() == "RUNNING") throw new InvalidOperationException("TRAFFIC_RUNNER_REPORT_MISSING");
                    return value;
                }
                finally { File.Delete(bindingPath); }
            });
        }
        catch (Exception exception) when (exception is InvalidOperationException or IOException or UnauthorizedAccessException or OperationCanceledException or JsonException)
        {
            error = exception is InvalidOperationException && System.Text.RegularExpressions.Regex.IsMatch(exception.Message, "^[A-Z][A-Z0-9_]{0,100}$")
                ? exception.Message : "TRAFFIC_RUN_OR_STORAGE_FAILED";
        }
        if (final is null)
        {
            await WriteAsync(Path.Combine(directory, "attempt.json"), new { id, state = "FAILED", build_id = request.BuildId,
                cases = request.Cases, complete = false, cleanup_verified = false, error, completed_at_utc = DateTimeOffset.UtcNow });
            using var document = JsonDocument.Parse(await File.ReadAllBytesAsync(Path.Combine(directory, "attempt.json")));
            final = document.RootElement.Clone();
        }
        lock (_stateGate) { _run = final; _activeDirectory = null; _checked = null; _error = error; }
    }

    private static async Task DrainAsync(StreamReader stream)
    {
        var buffer = new char[4096];
        while (await stream.ReadAsync(buffer) != 0) { }
    }
    Task IHostedService.StartAsync(CancellationToken token) => Task.CompletedTask;
    async Task IHostedService.StopAsync(CancellationToken token)
    {
        Task? execution;
        lock (_stateGate)
        {
            execution = _execution;
            if (_activeDirectory is not null)
                try { File.WriteAllText(Path.Combine(_activeDirectory, "cancel.requested"), "shutdown\n"); } catch (IOException) { }
        }
        if (execution is not null)
            try { await execution.WaitAsync(TimeSpan.FromSeconds(90), CancellationToken.None); } catch (TimeoutException) { }
    }
    private static async Task WriteAsync(string path, object value)
    {
        var temporary = path + ".tmp";
        await File.WriteAllBytesAsync(temporary, JsonSerializer.SerializeToUtf8Bytes(value, Pretty));
        File.Move(temporary, path, true);
    }
    private static double Estimate(IEnumerable<TrafficCaseRequest> cases) => cases.Sum(row => row.Id == "soak"
        ? (row.Duration == "SHORT" ? 24 : row.Duration == "NORMAL" ? 48 : 72) * 3600d + 300
        : (row.Duration == "SHORT" ? 6 : row.Duration == "NORMAL" ? 30 : 120) * (row.Id switch
            { "tcp-multistream" or "loaded-rtt" or "flow-rate" or "mixed" or "three-modes" => 3, "tcp-connections" or "udp-connections" => 5,
                "udp-sweep" => 6, "stability" => 10, _ => 1 }) + 20);
}
