using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Security.Cryptography;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record BenchmarkStartRequest(string PlanId);
public sealed record BenchmarkRunView(string PlanId, string Status, DateTimeOffset StartedAtUtc,
    DateTimeOffset UpdatedAtUtc, int CompletedRuns, int TotalRuns, string? CurrentMode,
    bool CancellationRequested, int? ExitCode, string? Reason, bool Terminal,
    string? CurrentDirection = null, string? Scenario = null, string? BuildId = null, string? BuildName = null, JsonElement? WorkloadPreset = null);
public sealed record BenchmarkSuiteItem(string PlanId, string Scenario, string Status, string? Duration = null, string? Load = null);
public sealed record BenchmarkSuiteView(string PlanId, string Status, DateTimeOffset StartedAtUtc,
    DateTimeOffset UpdatedAtUtc, BenchmarkSuiteItem[] Tests, int CompletedTests, int CurrentTest,
    bool CancellationRequested, bool Terminal, string BuildId, string BuildName, string? Reason = null);

/// <summary>Owns one explicit UI launch. Stop is cooperative; never kills the product/controller.</summary>
public sealed class BenchmarkRunService(AppPaths paths, BenchmarkLabService lab, RunCoordinator oldRuns) : IHostedService
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile BenchmarkRunView? _view;
    private Task? _execution;
    private volatile BenchmarkSuiteView? _suite;
    private Task? _suiteExecution;
    private string Root => Path.Combine(paths.RepositoryRoot, "artifacts", "benchmark-launch");
    private static bool ValidId(string? id) => id is not null && Regex.IsMatch(id, "^plan-[a-f0-9]{32}$", RegexOptions.CultureInvariant);
    private static bool IsAdmin()
    {
        if (!OperatingSystem.IsWindows()) return false;
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }
    public object State() => new { administrator = IsAdmin(), automatic_scenarios = new[] { "tcp_rtt", "tcp_transfer", "tcp_rtt_three_modes", "tcp_connections" }, run = _view, suite = _suite };
    public bool HasActiveRun => _view is { Terminal: false } || _suite is { Terminal: false };

    public Task StartAsync(CancellationToken cancellationToken)
    {
        // Never resume a controller after app restart. Retain interruption time for the cross-boot guard.
        if (!Directory.Exists(Root)) return Task.CompletedTask;
        foreach (var directory in Directory.EnumerateDirectories(Root, "suite-*-control"))
        {
            try
            {
                using var document = ReadJson(Path.Combine(directory, "job.json"));
                var saved = document.RootElement.Deserialize<BenchmarkSuiteView>(Json);
                if (saved is null || !ValidSuiteId(saved.PlanId) || Path.GetFileName(directory) != saved.PlanId + "-control") continue;
                if (!saved.Terminal)
                {
                    saved = saved with { Status = "INTERRUPTED", Terminal = true, Reason = "APP_RESTART_CLEANUP_NOT_CONFIRMED" };
                    SaveSuite(saved);
                    try
                    {
                        saved = saved with { Tests = RecordUnstartedTests(saved.Tests, saved.BuildId, saved.BuildName) };
                        SaveSuite(saved);
                    }
                    catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException) { }
                }
                if (_suite is null || saved.StartedAtUtc > _suite.StartedAtUtc) _suite = saved;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException) { }
        }
        foreach (var directory in Directory.EnumerateDirectories(Root, "plan-*-control").OrderDescending())
        {
            try
            {
                var file = Path.Combine(directory, "job.json");
                AssertLocal(file);
                if (!File.Exists(file) || new FileInfo(file).Length > 65536) continue;
                var saved = JsonSerializer.Deserialize<BenchmarkRunView>(File.ReadAllText(file), Json);
                if (saved is null || !ValidId(saved.PlanId) || Path.GetFileName(directory) != saved.PlanId + "-control") continue;
                if (!saved.Terminal)
                {
                    var cancel = Path.Combine(directory, "cancel.request");
                    AssertLocal(cancel);
                    File.WriteAllText(cancel, "stop-after-current-run\n");
                    saved = saved with { Status = "INTERRUPTED", Terminal = true, Reason = "APP_RESTART_CLEANUP_NOT_CONFIRMED" };
                    File.WriteAllText(file, JsonSerializer.Serialize(saved, Json));
                }
                if (_view is null || saved.StartedAtUtc > _view.StartedAtUtc) _view = saved;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException) { }
        }
        return Task.CompletedTask;
    }

    public async Task<BenchmarkRunView> LaunchAsync(string id, CancellationToken cancellationToken, string? suiteOwner = null)
    {
        if (!ValidId(id)) throw new InvalidOperationException("INVALID_PLAN");
        if (!IsAdmin()) throw new InvalidOperationException("ADMINISTRATOR_REQUIRED");
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (suiteOwner is not null && _suite is { CancellationRequested: true })
                throw new OperationCanceledException("SUITE_STOP_REQUESTED");
            if ((_suite is { Terminal: false } && _suite.PlanId != suiteOwner) ||
                _execution is { IsCompleted: false } || oldRuns.List().Any(job => job.Mode == "real" && !job.Terminal))
                throw new InvalidOperationException("REAL_RUN_ALREADY_ACTIVE");
            var planFile = Path.Combine(Root, id + ".json");
            AssertLocal(planFile);
            if (new FileInfo(planFile).Length > 65536) throw new InvalidOperationException("INVALID_PLAN");
            using var document = JsonDocument.Parse(await File.ReadAllTextAsync(planFile, cancellationToken));
            var plan = document.RootElement;
            var scenario = plan.GetProperty("scenario").GetString();
            if (plan.GetProperty("id").GetString() != id || plan.GetProperty("contract").GetString() != "driver" ||
                plan.GetProperty("mode").GetString() != "local" || scenario is not ("tcp_rtt" or "tcp_transfer" or "tcp_rtt_three_modes" or "tcp_connections") ||
                plan.GetProperty("profile").GetString() != "SMOKE") throw new InvalidOperationException("AUTOMATIC_SCENARIO_PENDING");
            if (plan.TryGetProperty("workload_preset", out var workload) && workload.ValueKind != JsonValueKind.Null)
            {
                JsonElement? expectedWorkload = scenario == "tcp_connections" ? ConnectionWorkload.Resolve(workload.GetProperty("duration").GetString(), workload.GetProperty("load").GetString()) : BenchmarkWorkload.Resolve(paths.RepositoryRoot, workload.GetProperty("duration").GetString(), workload.GetProperty("load").GetString());
                if (expectedWorkload is null || !BenchmarkWorkload.Matches(workload, expectedWorkload.Value)) throw new InvalidOperationException("INVALID_PLAN");
            }
            // The request selects only a server-created id. Recheck the current saved selection, not browser paths.
            var selection = await lab.ReadSavedRequestAsync(cancellationToken) ?? throw new InvalidOperationException("SELECTION_REQUIRED");
            var expected = Path.Combine(paths.RepositoryRoot, "artifacts", "product-builds", "driver-63be0eb-testlab-cli");
            if (selection.Contract != "driver" || !string.Equals(Path.GetFullPath(selection.InstallationDirectory).TrimEnd('\\', '/'), expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("SELECTION_CHANGED_PREPARE_AGAIN");
            if (!string.IsNullOrWhiteSpace(selection.DriverPath) && !string.Equals(Path.GetFullPath(selection.DriverPath), Path.Combine(expected, "ProxyBridgeDrv.sys"), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("SELECTION_CHANGED_PREPARE_AGAIN");
            var observation = await lab.InspectAsync(selection, cancellationToken);
            if (!observation.GetProperty("recognized_benchmark_files").GetBoolean() ||
                observation.GetProperty("bundle_sha256").GetString() != plan.GetProperty("bundle_sha256").GetString())
                throw new InvalidOperationException("SELECTION_CHANGED_PREPARE_AGAIN");
            string? buildId = null, buildName = null;
            if (plan.TryGetProperty("build_id", out var binding))
            {
                buildId = binding.GetString();
                if (buildId != BenchmarkBuildCatalog.Identity("driver", plan.GetProperty("bundle_sha256").GetString()!))
                    throw new InvalidOperationException("INVALID_PLAN");
                buildName = BenchmarkBuildCatalog.Label(plan.GetProperty("build_name_at_run").GetString(), "driver");
            }
            var directory = Control(id);
            AssertLocal(directory);
            if (Directory.Exists(directory) || Directory.Exists(Path.Combine(Root, id + "-run")))
                throw new InvalidOperationException("PLAN_ALREADY_USED_PREPARE_AGAIN");
            Directory.CreateDirectory(directory);
            var now = DateTimeOffset.UtcNow;
            _view = new(id, "STARTING", now, now, 0, scenario == "tcp_transfer" ? 4 : scenario == "tcp_rtt_three_modes" ? 3 : 2, null, false, null, null, false, Scenario: scenario, BuildId: buildId, BuildName: buildName,
                WorkloadPreset: plan.TryGetProperty("workload_preset", out var preset) && preset.ValueKind != JsonValueKind.Null ? preset.Clone() : null);
            Save(_view);
            _execution = Task.Run(() => ExecuteAsync(id));
            return _view;
        }
        finally { _gate.Release(); }
    }

    public async Task<BenchmarkRunView?> RequestStopAsync(CancellationToken cancellationToken, string? expectedId = null)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (_view is null || _view.Terminal) return _view;
            if (expectedId is not null && _view.PlanId != expectedId) throw new InvalidOperationException("RUN_CHANGED_REFRESH");
            var cancel = Path.Combine(Control(_view.PlanId), "cancel.request");
            AssertLocal(cancel);
            await File.WriteAllTextAsync(cancel, "stop-after-current-run\n", CancellationToken.None);
            _view = _view with { Status = "STOPPING", CancellationRequested = true, UpdatedAtUtc = DateTimeOffset.UtcNow };
            Save(_view);
            return _view;
        }
        finally { _gate.Release(); }
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_suite is { Terminal: false } suite) await RequestSuiteStopAsync(suite.PlanId, CancellationToken.None);
        if (_suiteExecution is not null) await _suiteExecution.WaitAsync(cancellationToken);
        await RequestStopAsync(CancellationToken.None);
        var execution = _execution;
        if (execution is not null) await execution.WaitAsync(cancellationToken);
    }

    private static bool ValidSuiteId(string? id) => id is not null && Regex.IsMatch(id, "^suite-[a-f0-9]{32}$", RegexOptions.CultureInvariant);

    public async Task<BenchmarkSuiteView> LaunchSuiteAsync(string id, CancellationToken token)
    {
        if (!ValidSuiteId(id)) throw new InvalidOperationException("INVALID_PLAN");
        if (!IsAdmin()) throw new InvalidOperationException("ADMINISTRATOR_REQUIRED");
        await _gate.WaitAsync(token);
        try
        {
            if (HasActiveRun || _execution is { IsCompleted: false } || _suiteExecution is { IsCompleted: false } ||
                oldRuns.List().Any(job => job.Mode == "real" && !job.Terminal)) throw new InvalidOperationException("REAL_RUN_ALREADY_ACTIVE");
            using var document = ReadJson(Path.Combine(Root, id + ".json"));
            var plan = document.RootElement.Deserialize<BenchmarkSuitePlan>(Json) ?? throw new InvalidOperationException("INVALID_PLAN");
            if (plan.Id != id || plan.Mode != "local" || plan.Contract != "driver" || plan.Tests is null ||
                plan.Tests.Length is < 1 or > 4 || plan.Tests.Select(item => item.Scenario).Distinct().Count() != plan.Tests.Length ||
                plan.BuildId != BenchmarkBuildCatalog.Identity("driver", plan.BundleSha256)) throw new InvalidOperationException("INVALID_PLAN");
            foreach (var test in plan.Tests)
            {
                if (!ValidId(test.PlanId) || test.Scenario is not ("tcp_rtt" or "tcp_transfer" or "tcp_rtt_three_modes" or "tcp_connections") ||
                    test.TotalRuns != (test.Scenario == "tcp_transfer" ? 4 : test.Scenario == "tcp_rtt_three_modes" ? 3 : 2)) throw new InvalidOperationException("INVALID_PLAN");
                var file = Path.Combine(Root, test.PlanId + ".json");
                using var child = ReadJson(file);
                JsonElement? expectedWorkload = test.Scenario == "tcp_connections" ? ConnectionWorkload.Resolve(test.Duration, test.Load) : BenchmarkWorkload.Resolve(paths.RepositoryRoot, test.Duration, test.Load);
                var childHasWorkload = child.RootElement.TryGetProperty("workload_preset", out var childWorkload) && childWorkload.ValueKind != JsonValueKind.Null;
                if (expectedWorkload is null ? childHasWorkload : !childHasWorkload || !BenchmarkWorkload.Matches(expectedWorkload.Value, childWorkload))
                    throw new InvalidOperationException("INVALID_PLAN");
                if (!string.Equals(Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(file))), test.PlanSha256, StringComparison.Ordinal) ||
                    child.RootElement.GetProperty("id").GetString() != test.PlanId ||
                    child.RootElement.GetProperty("scenario").GetString() != test.Scenario ||
                    child.RootElement.GetProperty("profile").GetString() != "SMOKE" ||
                    child.RootElement.GetProperty("bundle_sha256").GetString() != plan.BundleSha256 ||
                    child.RootElement.GetProperty("build_id").GetString() != plan.BuildId)
                    throw new InvalidOperationException("INVALID_PLAN");
                if (Directory.Exists(Control(test.PlanId)) || Directory.Exists(Path.Combine(Root, test.PlanId + "-run")))
                    throw new InvalidOperationException("PLAN_ALREADY_USED_PREPARE_AGAIN");
            }
            AssertLocal(Control(id));
            if (Directory.Exists(Control(id))) throw new InvalidOperationException("PLAN_ALREADY_USED_PREPARE_AGAIN");
            Directory.CreateDirectory(Control(id));
            var now = DateTimeOffset.UtcNow;
            _suite = new(id, "STARTING", now, now, plan.Tests.Select(test => new BenchmarkSuiteItem(test.PlanId, test.Scenario, "PENDING", test.Duration, test.Load)).ToArray(),
                0, 0, false, false, plan.BuildId, BenchmarkBuildCatalog.Label(plan.BuildName, "driver"));
            SaveSuite(_suite);
            _suiteExecution = Task.Run(() => ExecuteSuiteAsync(plan));
            return _suite;
        }
        finally { _gate.Release(); }
    }

    public async Task<BenchmarkSuiteView?> RequestSuiteStopAsync(string id, CancellationToken token)
    {
        await _gate.WaitAsync(token);
        try
        {
            if (_suite is null || _suite.PlanId != id) throw new InvalidOperationException("RUN_CHANGED_REFRESH");
            if (_suite.Terminal) return _suite;
            _suite = _suite with { CancellationRequested = true, Status = "STOPPING", UpdatedAtUtc = DateTimeOffset.UtcNow };
            SaveSuite(_suite);
            if (_view is { Terminal: false } child && _suite.Tests.Any(test => test.PlanId == child.PlanId))
            {
                var cancel = Path.Combine(Control(child.PlanId), "cancel.request");
                AssertLocal(cancel);
                await File.WriteAllTextAsync(cancel, "stop-after-current-run\n", CancellationToken.None);
                _view = child with { Status = "STOPPING", CancellationRequested = true, UpdatedAtUtc = DateTimeOffset.UtcNow };
                Save(_view);
            }
            return _suite;
        }
        finally { _gate.Release(); }
    }

    private async Task ExecuteSuiteAsync(BenchmarkSuitePlan plan)
    {
        string status = "COMPLETED";
        string? reason = null;
        try
        {
            for (var index = 0; index < plan.Tests.Length; index++)
            {
                await _gate.WaitAsync();
                try
                {
                    if (_suite!.CancellationRequested) { status = "CANCELLED"; break; }
                    _suite = _suite with { CurrentTest = index + 1, Status = "RUNNING", UpdatedAtUtc = DateTimeOffset.UtcNow };
                    SaveSuite(_suite);
                }
                finally { _gate.Release(); }
                var test = plan.Tests[index];
                var frozenPlan = Path.Combine(Root, test.PlanId + ".json");
                AssertLocal(frozenPlan);
                if (!string.Equals(Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(frozenPlan))), test.PlanSha256, StringComparison.Ordinal))
                    throw new InvalidOperationException("INVALID_PLAN");
                // LaunchAsync rechecks saved kit identity; the wrapper rechecks files, lease and runtime for each test.
                await LaunchAsync(test.PlanId, CancellationToken.None, plan.Id);
                // A stop may arrive between the queue check and child creation.
                if (_suite!.CancellationRequested) await RequestStopAsync(CancellationToken.None, test.PlanId);
                await _execution!;
                var outcome = _view!;
                await _gate.WaitAsync();
                try
                {
                    var items = _suite!.Tests.Select(item => item.PlanId == test.PlanId ? item with { Status = outcome.Status } : item).ToArray();
                    _suite = _suite with { Tests = items, CompletedTests = _suite.CompletedTests + (outcome.Status == "COMPLETED" ? 1 : 0), UpdatedAtUtc = DateTimeOffset.UtcNow };
                    SaveSuite(_suite);
                }
                finally { _gate.Release(); }
                if (outcome.Status != "COMPLETED") { status = outcome.Status == "CANCELLED" ? "CANCELLED" : "FAILED"; reason = outcome.Reason; break; }
            }
        }
        catch (OperationCanceledException) when (_suite is { CancellationRequested: true }) { status = "CANCELLED"; }
        catch (Exception) { status = "FAILED"; reason = "SUITE_LAUNCH_NOT_CONFIRMED"; }
        finally
        {
            await _gate.WaitAsync();
            try
            {
                var items = RecordUnstartedTests(_suite!.Tests, plan.BuildId, plan.BuildName);
                _suite = _suite with { Tests = items, Status = status, Reason = reason, Terminal = true, UpdatedAtUtc = DateTimeOffset.UtcNow };
                SaveSuite(_suite);
            }
            finally { _gate.Release(); }
        }
    }

    private void SaveSuite(BenchmarkSuiteView view)
    {
        var file = Path.Combine(Control(view.PlanId), "job.json");
        AssertLocal(file);
        AssertLocal(file + ".tmp");
        File.WriteAllText(file + ".tmp", JsonSerializer.Serialize(view, Json));
        File.Move(file + ".tmp", file, overwrite: true);
    }

    private BenchmarkSuiteItem[] RecordUnstartedTests(BenchmarkSuiteItem[] tests, string buildId, string buildName)
    {
        var items = tests.ToArray();
        for (var index = 0; index < items.Length; index++)
        {
            var item = items[index];
            if (!ValidId(item.PlanId) || item.Scenario is not ("tcp_rtt" or "tcp_transfer" or "tcp_rtt_three_modes" or "tcp_connections"))
                throw new InvalidOperationException("INVALID_PLAN");
            if (item.Status != "PENDING" || Directory.Exists(Control(item.PlanId))) continue;
            AssertLocal(Control(item.PlanId));
            Directory.CreateDirectory(Control(item.PlanId));
            var now = DateTimeOffset.UtcNow;
            Save(new(item.PlanId, "CANCELLED", now, now, 0, item.Scenario == "tcp_transfer" ? 4 : item.Scenario == "tcp_rtt_three_modes" ? 3 : 2, null, true, null,
                "SUITE_TEST_NOT_STARTED", true, Scenario: item.Scenario, BuildId: buildId, BuildName: buildName));
            items[index] = item with { Status = "CANCELLED" };
        }
        return items;
    }

    private async Task ExecuteAsync(string id)
    {
        Process? process = null;
        Task? stdout = null;
        Task? stderr = null;
        try
        {
            var info = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"))
            { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = paths.RepositoryRoot };
            foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                Path.Combine(paths.RepositoryRoot, "scripts", "Invoke-PlannedBenchmark.ps1"), "-PlanId", id, "-Phase", "Run" }) info.ArgumentList.Add(arg);
            process = Process.Start(info) ?? throw new InvalidOperationException("WRAPPER_NOT_STARTED");
            stdout = DrainAsync(process.StandardOutput.BaseStream, Path.Combine(Control(id), "wrapper-stdout.log"));
            stderr = DrainAsync(process.StandardError.BaseStream, Path.Combine(Control(id), "wrapper-stderr.log"));
            await UpdateAsync(id, state => state with { Status = state.CancellationRequested ? "STOPPING" : "RUNNING" });
            while (!process.HasExited)
            {
                var evidence = EvidenceDirectory(id);
                if (evidence is not null) ReadProgress(id, evidence);
                await Task.Delay(500);
            }
            await process.WaitForExitAsync();
            await Task.WhenAll(stdout, stderr);
            var finalEvidence = EvidenceDirectory(id);
            if (finalEvidence is not null) ReadProgress(id, finalEvidence);
            var outcome = ReadOutcome(finalEvidence, process.ExitCode);
            if (finalEvidence is null) outcome = ("FAILED", ReadPrecheckFailure(id));
            await UpdateAsync(id, state => state with { Status = outcome.Status, Reason = outcome.Reason,
                ExitCode = process.ExitCode, Terminal = true, CurrentMode = null, CurrentDirection = null });
        }
        catch (Exception)
        {
            // Do not kill an owned controller and bypass its cleanup, even if logging fails.
            if (process is not null && !process.HasExited) await process.WaitForExitAsync();
            if (stdout is not null && stderr is not null) { try { await Task.WhenAll(stdout, stderr); } catch { } }
            await UpdateAsync(id, state => state with { Status = "FAILED", Terminal = true, Reason = "WRAPPER_OR_EVIDENCE_NOT_CONFIRMED", CurrentMode = null, CurrentDirection = null });
        }
        finally { process?.Dispose(); }
    }

    private static async Task DrainAsync(Stream input, string file)
    {
        try
        {
            await using var output = new FileStream(file, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
            await input.CopyToAsync(output);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        { await input.CopyToAsync(Stream.Null); throw; }
    }

    private void ReadProgress(string id, string directory)
    {
        try
        {
            using var document = ReadJson(Path.Combine(directory, "comparison-manifest.json"));
            var runs = document.RootElement.GetProperty("runs").EnumerateArray().ToArray();
            var completed = runs.Count(run => run.GetProperty("status").GetString() == "COMPLETED");
            var current = runs.LastOrDefault(run => run.GetProperty("status").GetString() == "RUNNING");
            var mode = current.ValueKind == JsonValueKind.Undefined ? null : current.GetProperty("mode").GetString();
            var direction = current.ValueKind != JsonValueKind.Undefined && current.TryGetProperty("direction", out var value) ? value.GetString() : null;
            _gate.Wait();
            try { if (_view?.PlanId == id) { _view = _view with { CompletedRuns = completed, CurrentMode = mode is "OFF" or "PROXY" ? mode : null, CurrentDirection = direction is "push" or "pull" ? direction : null, UpdatedAtUtc = DateTimeOffset.UtcNow }; Save(_view); } }
            finally { _gate.Release(); }
        }
        catch (Exception error) when (error is IOException or JsonException or KeyNotFoundException or InvalidOperationException) { }
    }

    private string? EvidenceDirectory(string id)
    {
        try
        {
            using var receipt = ReadJson(Path.Combine(Root, id + "-run", "controller-process.json"));
            var path = Path.GetFullPath(receipt.RootElement.GetProperty("evidence_directory").GetString()!);
            var expectedRoot = Path.Combine(paths.RepositoryRoot, "artifacts", "local-route") + Path.DirectorySeparatorChar;
            var scenario = _view?.PlanId == id ? _view.Scenario ?? "tcp_rtt" : "tcp_rtt";
            if (!path.StartsWith(expectedRoot, StringComparison.OrdinalIgnoreCase) ||
                receipt.RootElement.GetProperty("scenario").GetString() != scenario ||
                !Path.GetFileName(path).StartsWith("lab-" + scenario + "-smoke-", StringComparison.Ordinal)) return null;
            AssertLocal(path);
            return path;
        }
        catch (Exception error) when (error is IOException or JsonException or KeyNotFoundException or InvalidOperationException or ArgumentException) { return null; }
    }

    private static (string Status, string? Reason) ReadOutcome(string? directory, int exit)
    {
        if (directory is null) return ("FAILED", "WRAPPER_PRECHECK_OR_START_FAILED");
        try
        {
            using var manifest = ReadJson(Path.Combine(directory, "comparison-manifest.json"));
            if (exit == 0 && manifest.RootElement.GetProperty("status").GetString() == "CANCELLED") return ("CANCELLED", null);
            if (exit != 0 || manifest.RootElement.GetProperty("status").GetString() != "COMPLETED") return ("FAILED", "WORKLOAD_OR_CLEANUP_FAILED");
            using var report = ReadJson(Path.Combine(directory, "comparison-report.json"));
            if (report.RootElement.GetProperty("status").GetString() != "LIMITED_COMPARISON" || report.RootElement.GetProperty("errors").GetArrayLength() != 0)
                return ("FAILED", "EVIDENCE_NOT_CONFIRMED");
            return ("COMPLETED", null);
        }
        catch (Exception error) when (error is IOException or JsonException or KeyNotFoundException or InvalidOperationException) { return ("FAILED", "EVIDENCE_NOT_CONFIRMED"); }
    }

    private string ReadPrecheckFailure(string id)
    {
        try
        {
            var file = Path.Combine(Control(id), "wrapper-stderr.log");
            AssertLocal(file);
            if (new FileInfo(file).Length > 262144) return "WRAPPER_PRECHECK_OR_START_FAILED";
            var text = File.ReadAllText(file);
            foreach (var reason in new[] { "LAB_REBOOT_REQUIRED_AFTER_RECORDED_4_0_0", "LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_RUN", "LAB_OTHER_REAL_RUN_ACTIVE_OR_LEASE_UNAVAILABLE" })
                if (text.Contains(reason, StringComparison.Ordinal)) return reason;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException) { }
        return "WRAPPER_PRECHECK_OR_START_FAILED";
    }

    private async Task UpdateAsync(string id, Func<BenchmarkRunView, BenchmarkRunView> update)
    {
        await _gate.WaitAsync();
        try { if (_view?.PlanId == id) { _view = update(_view) with { UpdatedAtUtc = DateTimeOffset.UtcNow }; Save(_view); } }
        finally { _gate.Release(); }
    }
    private string Control(string id) => Path.Combine(Root, id + "-control");
    private void Save(BenchmarkRunView view)
    {
        var file = Path.Combine(Control(view.PlanId), "job.json");
        File.WriteAllText(file + ".tmp", JsonSerializer.Serialize(view, Json));
        File.Move(file + ".tmp", file, overwrite: true);
    }
    private static JsonDocument ReadJson(string file)
    {
        AssertLocal(file);
        if (new FileInfo(file).Length > 65536) throw new InvalidOperationException("RUN_STATE_SIZE_LIMIT");
        return JsonDocument.Parse(File.ReadAllText(file));
    }
    private static void AssertLocal(string path)
    {
        for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("RUN_STATE_REPARSE_POINT");
    }
}
