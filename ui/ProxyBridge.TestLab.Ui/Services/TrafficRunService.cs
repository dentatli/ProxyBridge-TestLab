using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed partial class TrafficRuntimeService
{
    private object? _run;
    private JsonElement? _queuePresentation;
    private string? _activeDirectory;
    private Task? _execution;
    private static readonly JsonSerializerOptions Pretty = new() { WriteIndented = true };

    public async Task<object> StartAsync(TrafficRunRequest request)
    {
        // Retain the old request field for clients, but make verified continuation mandatory.
        request = request with { ContinueAfterFailure = true, AllowLongRun = true };
        if (request.Mode is not ("local" or "remote")) throw new InvalidOperationException("TRAFFIC_MODE_INVALID");
        if (request.Mode == "remote" && ApplyCheckpoint.Pending) throw new InvalidOperationException("TRAFFIC_APPLY_RECHECK_REQUIRED");
        if (!Administrator()) throw new InvalidOperationException("TRAFFIC_ADMINISTRATOR_REQUIRED");
        var catalog = Catalog();
        var known = catalog.GetProperty("cases").EnumerateArray().Select(row => row.GetProperty("id").GetString()).ToHashSet();
        if (request.Cases is null || request.Cases.Length < 1 || request.Cases.Length > known.Count || request.Cases.Any(row => row is null || !known.Contains(row.Id) ||
            row.Duration is not ("SHORT" or "NORMAL" or "LONG") || row.Load is not ("LOW" or "HIGH")) ||
            request.Cases.Select(row => row.Id).Distinct().Count() != request.Cases.Length)
            throw new InvalidOperationException("TRAFFIC_CASE_SELECTION_INVALID");
        var plan = OptimizeSelection(catalog, request.Cases);
        request = request with { Cases = plan.cases };
        if (request.Mode == "local") ValidateLocalFiles();
        if (!await _gate.WaitAsync(0, Token)) throw new InvalidOperationException("TRAFFIC_OPERATION_ACTIVE");
        try
        {
            var selected = await builds.RequestAsync(request.BuildId, Token);
            if (selected.Contract is not ("driver" or "v4.0.0")) throw new InvalidOperationException("TRAFFIC_PRODUCT_ADAPTER_REQUIRED");
            AppStoragePaths.EnsureSecureDirectory(Root);
            var id = DateTimeOffset.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N");
            var directory = Path.Combine(Root, id);
            AppStoragePaths.EnsureSecureDirectory(directory);
            var attempt = new { id, state = "PREPARING", started_at_utc = DateTimeOffset.UtcNow, build_id = request.BuildId,
                mode = request.Mode, cases = request.Cases, selection_optimization = plan, estimate_seconds = Estimate(request.Cases, request.ContinueAfterFailure),
                continue_after_failure = request.ContinueAfterFailure, complete = false, cleanup_verified = false };
            await WriteAsync(Path.Combine(directory, "attempt.json"), attempt);
            lock (_stateGate) { _run = attempt; _queuePresentation = null; _activeDirectory = directory; _checked = null; }
            _execution = Task.Run(async () =>
            {
                try { await ExecuteRunAsync(request, selected, directory, id, plan); }
                catch (Exception)
                {
                    lock (_stateGate) { _queuePresentation = ReadQueuePresentation(); _run = new { id, cases = request.Cases, selection_optimization = plan, mode = request.Mode, state = "FAILED", complete = false, cleanup_verified = false, error = "TRAFFIC_RUN_OR_STORAGE_FAILED" }; _activeDirectory = null; _checked = null; }
                }
                finally { _gate.Release(); }
            });
            return attempt;
        }
        catch { _gate.Release(); throw; }
    }

    internal sealed record TrafficCoverage(string case_id, string covered_by);
    internal sealed record TrafficSelectionPlan(TrafficCaseRequest[] requested_cases, TrafficCaseRequest[] cases, TrafficCoverage[] covered_cases);
    internal static TrafficSelectionPlan OptimizeSelection(JsonElement catalog, TrafficCaseRequest[] requested)
    {
        var coverage = catalog.GetProperty("cases").EnumerateArray().ToDictionary(
            row => row.GetProperty("id").GetString()!,
            row => row.TryGetProperty("covers", out var ids) ? ids.EnumerateArray().Select(id => id.GetString()!).ToHashSet() : new HashSet<string>());
        var covered = requested.Select(row => (Row: row, Parent: requested.FirstOrDefault(other => other.Id != row.Id &&
            other.Duration == row.Duration && other.Load == row.Load && coverage[other.Id].Contains(row.Id))))
            .Where(item => item.Parent is not null).Select(item => new TrafficCoverage(item.Row.Id, item.Parent!.Id)).ToArray();
        return new(requested, requested.Where(row => !covered.Any(item => item.case_id == row.Id)).ToArray(), covered);
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
        if (!Directory.Exists(Root)) return new { items = Array.Empty<object>(), has_more = false, next_skip = 0, unreadable_count = 0 };
        var items = new List<JsonElement>();
        var unreadable = 0;
        var directories = TrafficAttemptDirectories().ToArray();
        foreach (var directory in directories.Skip(skip).Take(take))
        {
            try
            {
                items.Add(ObserveAttemptActivity(ReadTrafficAttempt(directory), directory));
            }
            catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException or KeyNotFoundException or InvalidOperationException) { unreadable++; }
        }
        return new { items, has_more = skip + take < directories.Length, next_skip = skip + take, unreadable_count = unreadable };
    }

    public object Comparison()
    {
        var latest = new Dictionary<string, object>(StringComparer.Ordinal);
        var barriers = new HashSet<string>(StringComparer.Ordinal);
        var unreadable = 0;
        if (!Directory.Exists(Root)) return new { items = latest.Values.ToArray(), available = true, unreadable_count = 0, error = (string?)null };
        foreach (var directory in TrafficAttemptDirectories())
        {
            try
            {
                var attempt = ObserveAttemptActivity(ReadTrafficAttempt(directory), directory);
                if (!attempt.TryGetProperty("build_id", out var build) || !attempt.TryGetProperty("cases", out var cases)) continue;
                var runtimeMode = attempt.TryGetProperty("mode", out var attemptMode) ? attemptMode.GetString() ?? "remote" : "remote";
                foreach (var choice in cases.EnumerateArray())
                {
                    string Value(string name) => (choice.TryGetProperty(name, out var lower) ? lower : choice.GetProperty(char.ToUpperInvariant(name[0]) + name[1..])).GetString()!;
                    var id = Value("id"); var duration = Value("duration"); var load = Value("load");
                    JsonElement? result = null;
                    if (attempt.TryGetProperty("results", out var results))
                        foreach (var row in results.EnumerateArray()) if (row.GetProperty("case_id").GetString() == id) { result = row.Clone(); break; }
                    var conditions = result is not null && result.Value.TryGetProperty("conditions", out var observed) ? observed : default;
                    var localOrigin = conditions.ValueKind == JsonValueKind.Object && conditions.TryGetProperty("runtime_mode", out var mode) && mode.GetString() == "local";
                    var matching = conditions.ValueKind == JsonValueKind.Object && conditions.TryGetProperty("origin_physical_memory_bytes", out var memory) &&
                        memory.ValueKind == JsonValueKind.Number && conditions.TryGetProperty("local_runtime_sha256", out var identity) && identity.ValueKind == JsonValueKind.String ? conditions.EnumerateObject()
                        // Local PKI is fresh per attempt; retain its pins in full reports,
                        // but compare the verified source/host/mode rather than ephemeral keys.
                        .Where(property => property.Name != "build_sha256" && (!localOrigin || property.Name is not ("remote_bundle_sha256" or "application_tls_sha256" or "application_ssh_sha256"))).OrderBy(property => property.Name, StringComparer.Ordinal)
                        .ToDictionary(property => property.Name, property => property.Value.Clone()) : null;
                    var conditionId = matching is null ? "unverified" : Hash(JsonSerializer.SerializeToUtf8Bytes(matching));
                    var baseKey = $"{build.GetString()}|{id}|{duration}|{load}|{runtimeMode}";
                    if (barriers.Contains(baseKey)) continue;
                    if (matching is null) barriers.Add(baseKey);
                    var key = $"{build.GetString()}|{id}|{duration}|{load}|{runtimeMode}|{conditionId}";
                    if (latest.ContainsKey(key)) continue;
                    latest[key] = new { build_id = build.GetString(), case_id = id, duration, load, runtime_mode = runtimeMode, condition_id = conditionId,
                        attempt_id = attempt.GetProperty("id").GetString(), state = attempt.GetProperty("state").GetString(),
                        activity_observation = attempt.TryGetProperty("activity_observation", out var activity) ? activity.GetString() : null,
                        complete = result?.GetProperty("complete").GetBoolean() == true && attempt.GetProperty("state").GetString() is not ("PREPARING" or "RUNNING" or "INTERRUPTED"),
                        error = attempt.TryGetProperty("error", out var error) ? error.GetString() : null,
                        conditions = matching, result = ComparisonResult(result) };
                }
            }
            catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException or KeyNotFoundException or InvalidOperationException) { unreadable++; }
        }
        // An unreadable attempt cannot be assigned safely to a build/case. Do not
        // substitute any older success while that ambiguity remains.
        return new { items = unreadable == 0 ? latest.Values.ToArray() : Array.Empty<object>(),
            available = unreadable == 0, unreadable_count = unreadable,
            error = unreadable == 0 ? null : "TRAFFIC_COMPARISON_HISTORY_UNREADABLE" };
    }

    private IEnumerable<string> TrafficAttemptDirectories() => Directory.EnumerateDirectories(Root)
        .Where(directory => System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(directory),@"\A[0-9]{8}-[0-9]{6}-[a-f0-9]{32}\z") ||
            File.Exists(Path.Combine(directory,"attempt.json"))).OrderDescending();

    private JsonElement ObserveAttemptActivity(JsonElement row, string directory)
    {
        if (row.GetProperty("state").GetString() is not ("PREPARING" or "RUNNING")) return row;
        bool own;
        lock (_stateGate) own = string.Equals(directory, _activeDirectory, StringComparison.OrdinalIgnoreCase);
        var values = row.EnumerateObject().ToDictionary(property => property.Name, property => property.Value.Clone());
        values["activity_observation"] = JsonSerializer.SerializeToElement(own ? "THIS_CONTROLLER" : "UNCONFIRMED");
        if (!own)
        {
            // Another controller may still own the workload. Absence here proves neither interruption nor cleanup.
            values["complete"] = JsonSerializer.SerializeToElement(false);
            values["cleanup_verified"] = JsonSerializer.SerializeToElement(false);
        }
        return JsonSerializer.SerializeToElement(values);
    }

    private static JsonElement ReadTrafficAttempt(string directory)
    {
        var path = Path.Combine(directory,"attempt.json");
        if (File.GetAttributes(directory).HasFlag(FileAttributes.ReparsePoint) ||
            File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint))
            throw new InvalidOperationException("TRAFFIC_HISTORY_UNREADABLE");
        using var stream = new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
        if (stream.Length is <= 0 or > 64 * 1024 * 1024) throw new InvalidOperationException("TRAFFIC_HISTORY_UNREADABLE");
        using var document = JsonDocument.Parse(stream);
        var row = document.RootElement;
        if (row.ValueKind != JsonValueKind.Object || row.GetProperty("id").GetString()!=Path.GetFileName(directory) ||
            string.IsNullOrWhiteSpace(row.GetProperty("build_id").GetString()) ||
            row.GetProperty("state").GetString() is not ("PREPARING" or "RUNNING" or "COMPLETE" or "FAILED" or "CANCELLED" or "INTERRUPTED") ||
            row.GetProperty("complete").ValueKind is not (JsonValueKind.True or JsonValueKind.False) ||
            row.GetProperty("cases").ValueKind != JsonValueKind.Array || row.GetProperty("cases").GetArrayLength() is < 1 or > 256)
            throw new InvalidOperationException("TRAFFIC_HISTORY_UNREADABLE");
        var caseIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var choice in row.GetProperty("cases").EnumerateArray())
        {
            string? Value(string name) => (choice.TryGetProperty(name,out var lower)?lower:choice.GetProperty(char.ToUpperInvariant(name[0])+name[1..])).GetString();
            if (string.IsNullOrWhiteSpace(Value("id")) || !caseIds.Add(Value("id")!) ||
                Value("duration") is not ("SHORT" or "NORMAL" or "LONG") || Value("load") is not ("LOW" or "HIGH"))
                throw new InvalidOperationException("TRAFFIC_HISTORY_UNREADABLE");
        }
        foreach (var name in new[] { "results", "recovery_checks" })
            if (row.TryGetProperty(name,out var array) && array.ValueKind != JsonValueKind.Array)
                throw new InvalidOperationException("TRAFFIC_HISTORY_UNREADABLE");
        // A killed runner can leave individual reports but no final aggregate.
        // Recover only a read-time view; final capture/cleanup are still unverified.
        if (row.GetProperty("state").GetString() is "FAILED" or "INTERRUPTED" &&
            !row.TryGetProperty("results", out _) && row.TryGetProperty("error", out var failure) &&
            failure.GetString() is "TRAFFIC_RUNNER_REPORT_MISSING" or "TRAFFIC_RUN_OR_STORAGE_FAILED")
        {
            var partial = new List<JsonElement>();
            foreach (var choice in row.GetProperty("cases").EnumerateArray())
            {
                string? Choice(string name) => (choice.TryGetProperty(name,out var lower)?lower:choice.GetProperty(char.ToUpperInvariant(name[0])+name[1..])).GetString();
                var id = Choice("id")!;
                if (id.Length > 128 || id.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-')) continue;
                var reportPath = Path.Combine(directory, id + ".report.json");
                if (!File.Exists(reportPath) || File.GetAttributes(reportPath).HasFlag(FileAttributes.ReparsePoint)) continue;
                using var reportStream = new FileStream(reportPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                if (reportStream.Length is <= 0 or > 16 * 1024 * 1024) continue;
                using var report = JsonDocument.Parse(reportStream);
                var value = report.RootElement;
                if (value.GetProperty("case_id").GetString() != id || value.GetProperty("duration").GetString() != Choice("duration") ||
                    value.GetProperty("load").GetString() != Choice("load") || value.GetProperty("complete").ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                    continue;
                var item = value.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.Clone());
                item["workload_complete"] = value.GetProperty("complete").Clone();
                item["complete"] = JsonSerializer.SerializeToElement(false);
                item["cleanup_verified"] = JsonSerializer.SerializeToElement(false);
                item["recovered_partial"] = JsonSerializer.SerializeToElement(true);
                partial.Add(JsonSerializer.SerializeToElement(item));
            }
            var recovered = row.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.Clone());
            recovered["results"] = JsonSerializer.SerializeToElement(partial);
            recovered["recovered_partial_results"] = JsonSerializer.SerializeToElement(true);
            row = JsonSerializer.SerializeToElement(recovered);
        }
        if (row.TryGetProperty("results",out var results))
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var result in results.EnumerateArray())
            {
                var id = result.GetProperty("case_id").GetString();
                if (id is null || !caseIds.Contains(id) || !seen.Add(id) ||
                    result.GetProperty("complete").ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                    throw new InvalidOperationException("TRAFFIC_HISTORY_UNREADABLE");
                foreach (var name in new[] { "errors", "controls", "measurements" })
                    if (result.TryGetProperty(name,out var array) && array.ValueKind != JsonValueKind.Array)
                        throw new InvalidOperationException("TRAFFIC_HISTORY_UNREADABLE");
                if (result.TryGetProperty("measurements",out var measurements))
                    foreach (var measurement in measurements.EnumerateArray())
                        if (measurement.GetProperty("stages").ValueKind != JsonValueKind.Array)
                            throw new InvalidOperationException("TRAFFIC_HISTORY_UNREADABLE");
            }
        }
        return row.Clone();
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

    private JsonElement? ReadQueuePresentation()
    {
        if (_activeDirectory is null) return _queuePresentation;
        var path = Path.Combine(_activeDirectory, "queue-state.json");
        try
        {
            if (!File.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) return null;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length > 32768) return null;
            using var document = JsonDocument.Parse(stream, new JsonDocumentOptions { MaxDepth = 8 });
            _queuePresentation = document.RootElement.Clone();
            return _queuePresentation;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
        catch (JsonException) { return null; }
    }

    public object Progress()
    {
        lock (_stateGate)
        {
            var path = _activeDirectory is null ? null : Path.Combine(_activeDirectory, "progress.json");
            JsonElement? progress = null;
            if (path is not null && File.Exists(path) && new FileInfo(path).Length < 16384)
                try
                {
                    // Permit atomic replacement while retaining this read snapshot.
                    using var stream = new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
                    if (stream.Length < 16384)
                    {
                        using var doc = JsonDocument.Parse(stream,new JsonDocumentOptions { MaxDepth=16 });
                        progress = doc.RootElement.Clone();
                    }
                }
                catch (IOException) { }
                catch (JsonException) { }
            return new { run = _run, progress, queue = ReadQueuePresentation(), active = _activeDirectory is not null };
        }
    }

    private async Task ExecuteRunAsync(TrafficRunRequest request, ProductSelectionRequest selection, string directory, string id, TrafficSelectionPlan plan)
    {
        string? error = null;
        JsonElement? final = null;
        try
        {
            if (request.Mode == "local")
            {
                final = await WithLocalRuntimeAsync(directory, (payload, token) => ExecutePreparedRunAsync(request, selection, directory, id, "127.0.0.1", payload, token, plan));
                var value = System.Text.Json.Nodes.JsonNode.Parse(final.Value.GetRawText())!.AsObject();
                value["local_origin_cleanup_verified"] = true;
                await WriteAsync(Path.Combine(directory,"attempt.json"), value);
                final = JsonSerializer.SerializeToElement(value);
            }
            else
                final = await remote.WithTrafficContextAsync(async (target, paths, token) =>
                {
                    var payload = BuildPayload(target, paths, "inspect");
                    var readiness = await ExecuteAsync(target, paths, payload, token);
                    if (readiness.GetProperty("state").GetString() != "READY") throw new InvalidOperationException("TRAFFIC_RUNTIME_SETUP_REQUIRED");
                    return await ExecutePreparedRunAsync(request, selection, directory, id, target.Host, payload, token, plan);
                });
        }
        catch (Exception exception) when (exception is InvalidOperationException or IOException or UnauthorizedAccessException or OperationCanceledException or JsonException or System.ComponentModel.Win32Exception or TimeoutException)
        {
            error = exception is InvalidOperationException && System.Text.RegularExpressions.Regex.IsMatch(exception.Message, "^[A-Z][A-Z0-9_]{0,100}$")
                ? exception.Message : "TRAFFIC_RUN_OR_STORAGE_FAILED";
        }
        if (final is null)
        {
            await WriteAsync(Path.Combine(directory, "attempt.json"), new { id, state = "FAILED", build_id = request.BuildId,
                mode = request.Mode, cases = request.Cases, selection_optimization = plan, continue_after_failure = request.ContinueAfterFailure,
                complete = false, cleanup_verified = false, error, completed_at_utc = DateTimeOffset.UtcNow });
            using var document = JsonDocument.Parse(await File.ReadAllBytesAsync(Path.Combine(directory, "attempt.json")));
            final = document.RootElement.Clone();
        }
        lock (_stateGate) { _queuePresentation = ReadQueuePresentation(); _run = final; _activeDirectory = null; _checked = null; _error = error; }
    }

    private async Task<JsonElement> ExecutePreparedRunAsync(TrafficRunRequest request, ProductSelectionRequest selection,
        string directory, string id, string host, Payload payload, CancellationToken token, TrafficSelectionPlan plan)
    {
                var observed = await lab.InspectAsync(selection, token);
                if (!observed.GetProperty("files_observed").GetBoolean() || observed.GetProperty("status").GetString() == "UNSUPPORTED_BEFORE_4_0_0")
                    throw new InvalidOperationException("TRAFFIC_PRODUCT_FILES_OR_VERSION_UNSUPPORTED");
                if (!observed.TryGetProperty("adapter_id", out var adapter) || adapter.ValueKind != JsonValueKind.String) throw new InvalidOperationException("TRAFFIC_VERSION_METADATA_REQUIRED");
                var build = await lab.BindBuildAsync(selection, observed, token);
                if (build.Id != request.BuildId) throw new InvalidOperationException("TRAFFIC_BUILD_CHANGED");
                var python = LocalPythonRuntime.Resolve(app.RepositoryRoot);
                if (!File.Exists(python)) throw new InvalidOperationException("TRAFFIC_PYTHON_311_REQUIRED");
                var cli = Path.Combine(selection.InstallationDirectory, "ProxyBridge_CLI.exe");
                var core = Path.Combine(selection.InstallationDirectory, "ProxyBridgeCore.dll");
                var driver = selection.Contract == "driver" ? BenchmarkLabService.ResolveDriverPath(selection) : Path.Combine(selection.InstallationDirectory, "WinDivert64.sys");
                var hashes = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                foreach (var row in observed.GetProperty("components").EnumerateArray())
                {
                    var path = row.GetProperty("id").GetString() == "driver" ? driver : Path.Combine(selection.InstallationDirectory, row.GetProperty("file_name").GetString()!);
                    hashes[path] = row.GetProperty("sha256").GetString()!;
                }
                var sourceFiles = Directory.EnumerateFiles(Path.Combine(app.RepositoryRoot, "src", "trafficlab"), "*.py")
                    .Concat(new[] { "scripts/Invoke-TrafficLabRun.ps1", "scripts/Assert-TrafficLabIdle.ps1", "scripts/Assert-WinDivertTrafficIdle.ps1", "modules/InterceptionState.psm1",
                        "modules/ProcessAdapter.psm1", "src/pb_service_query.cs", "src/pb_loaded_drivers.cs", "config/traffic-workloads.json", "vendor/traffic-dependencies.lock.json",
                        "config/traffic-echo.proto", "config/product-cli-adapters.json", "bin/pb_console_host.exe", "bin/pb_wfp_state.exe" }
                        .Select(path => Path.Combine(app.RepositoryRoot, path))).Concat(TrafficDependencyFiles("win-x64")).Append(python).Append(typeof(TrafficRuntimeService).Assembly.Location);
                if (selection.Contract == "v4.0.0") sourceFiles = sourceFiles.Concat(new[] { "bin/tools/windivert-2.2.2/windivertctl.exe", "bin/tools/windivert-2.2.2/WinDivert.dll" }.Select(path => Path.Combine(app.RepositoryRoot, path)));
                if (request.Mode == "local") sourceFiles = sourceFiles.Concat(new[] {
                    Path.Combine(app.RepositoryRoot, "bin", "pb_core_host.exe"),
                    Path.Combine(app.RepositoryRoot, "scripts", "Set-TrafficWfpDevice.ps1"),
                    Path.Combine(app.RepositoryRoot, "scripts", "Initialize-LocalFirewall.ps1") });
                sourceFiles = sourceFiles.Select(Path.GetFullPath).ToArray();
                foreach (var file in sourceFiles)
                {
                    if (!File.Exists(file) || File.GetAttributes(file).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("TRAFFIC_LOCAL_ARTIFACT_MISSING_OR_REPARSE_POINT");
                    hashes[file] = Hash(File.ReadAllBytes(file));
                }
                var localRuntimeHash = Hash(JsonSerializer.SerializeToUtf8Bytes(sourceFiles.Order(StringComparer.Ordinal)
                    .ToDictionary(path => Path.GetFileName(path), path => hashes[path], StringComparer.Ordinal)));
                var binding = new { schema_version = 1, id, build_id = build.Id, build_sha256 = build.BundleSha256,
                    local_runtime_sha256 = localRuntimeHash, product_contract = selection.Contract, adapter_id = adapter.GetString(),
                    product_version = observed.GetProperty("product_version").GetString(),
                    host, runtime_mode = request.Mode, port = 42501, control_port = 42503, proxy_port = 42502, secret = payload.Secret,
                    execution_model = request.Mode == "local" ? "persistent-core-session-v1" : "independent-cli-v1",
                    core, core_host = Path.Combine(app.RepositoryRoot, "bin", "pb_core_host.exe"),
                    remote_bundle_sha256 = payload.Bundle, root = app.RepositoryRoot, cli, driver, driver_sha256 = hashes[driver],
                    console_host = Path.Combine(app.RepositoryRoot, "bin", "pb_console_host.exe"), python, source_hashes = hashes,
                    cancellation_path = Path.Combine(directory, "cancel.requested"),
                    continue_after_failure = request.ContinueAfterFailure,
                    cases = request.Cases.Select(row => new { case_id = row.Id, duration = row.Duration, load = row.Load }).ToArray() };
                var bindingPath = Path.Combine(directory, "binding-private.json");
                await WriteAsync(bindingPath, binding);
                await WriteAsync(Path.Combine(directory, "attempt.json"), new { id, state = "RUNNING", build_id = build.Id,
                    build_sha256 = build.BundleSha256, started_at_utc = DateTimeOffset.UtcNow, mode = request.Mode, cases = request.Cases, selection_optimization = plan,
                    complete = false, cleanup_verified = false, remote_bundle_sha256 = payload.Bundle,
                    continue_after_failure = request.ContinueAfterFailure });
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
    private double Estimate(IReadOnlyCollection<TrafficCaseRequest> cases, bool continueAfterFailure = false)
    {
        var payloadStages = Catalog().GetProperty("cases").EnumerateArray().ToDictionary(row=>row.GetProperty("id").GetString()!,row=>
        {
            if (!row.TryGetProperty("payload_sizes",out var sizes)) return 1;
            var count = sizes.GetArrayLength();
            if (count is < 1 or > 4) throw new InvalidOperationException("TRAFFIC_CATALOG_PAYLOAD_PROFILE_INVALID");
            return count;
        });
        return (continueAfterFailure ? Math.Max(0, cases.Count - 1) * 20 : 0) + cases.Sum(row => row.Id == "soak"
        ? (row.Duration == "SHORT" ? 24 : row.Duration == "NORMAL" ? 48 : 72) * 3600d + 300
        : (row.Duration == "SHORT" ? 6 : row.Duration == "NORMAL" ? 30 : 120) * (row.Id switch
            { "tcp-multistream" or "loaded-rtt" or "flow-rate" or "mixed" or "three-modes" => 3, "tcp-connections" or "udp-connections" => 5,
                "udp-sweep" => 6, "stability" => 10, _ => payloadStages.GetValueOrDefault(row.Id,1) }) + 20);
    }
}
