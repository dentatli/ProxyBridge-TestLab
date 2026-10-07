using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record BenchmarkPlanRequest(string Mode, string Scenario, string? Duration = null, string? Load = null);
public sealed record BenchmarkTestRequest(string Scenario, string Duration, string Load);
public sealed record BenchmarkSuiteRequest(string Mode, string[] Scenarios, BenchmarkTestRequest[]? Tests = null);
public sealed record BenchmarkSuiteTest(string PlanId, string Scenario, string PlanSha256, int TotalRuns, string? Duration = null, string? Load = null);
public sealed record BenchmarkSuitePlan(string Id, string Mode, string Contract, string BuildId, string BuildName,
    string BundleSha256, BenchmarkSuiteTest[] Tests);

/// <summary>Prepares a frozen files-only plan; execution requires a separate explicit action.</summary>
public sealed class BenchmarkLaunchPlanService(AppPaths paths, BenchmarkLabService lab)
{
    private static readonly Dictionary<string, (string Controller, string Profile, string Minutes)> Scenarios = new()
    {
        ["tcp_transfer"] = ("Invoke-LocalTcpBenchmark.ps1", "SMOKE", "2–4"),
        ["tcp_rtt"] = ("Invoke-LocalTcpRtt.ps1", "SMOKE", "1–3"),
        ["tcp_rtt_three_modes"] = ("Invoke-LocalTcpRtt.ps1", "SMOKE", "2–4"),
        ["tcp_connections"] = ("Invoke-LocalTcpConnections.ps1", "SMOKE", "3–6"),
        ["tcp_loaded_rtt"] = ("Invoke-LocalTcpLoadedRtt.ps1", "SMOKE", "2–5"),
        ["udp_echo"] = ("Invoke-LocalUdpSoak.ps1", "MULTI_TARGET", "5–20")
    };

    public async Task<object> PrepareAsync(BenchmarkPlanRequest request, CancellationToken cancellationToken)
    {
        if (request.Mode is not ("local" or "remote") || string.IsNullOrWhiteSpace(request.Scenario) || !Scenarios.TryGetValue(request.Scenario, out var scenario))
            return Blocked("INVALID_SCENARIO");
        if (request.Mode == "remote") return Blocked("REMOTE_CONTROLLER_PENDING");
        var workload = request.Scenario == "tcp_connections" ? ConnectionWorkload.Resolve(request.Duration, request.Load) : BenchmarkWorkload.Resolve(paths.RepositoryRoot, request.Duration, request.Load);
        if (workload is not null && request.Scenario is not ("tcp_rtt" or "tcp_rtt_three_modes" or "tcp_transfer" or "tcp_connections")) return Blocked("LAB_WORKLOAD_INVALID");
        var minutes = workload is null ? scenario.Minutes : request.Duration switch
        {
            "LONG" => request.Scenario == "tcp_rtt_three_modes" ? "8–15" : "6–12",
            "NORMAL" => request.Scenario == "tcp_rtt_three_modes" ? "4–7" : "3–6",
            _ => request.Scenario == "tcp_rtt_three_modes" ? "2–4" : "1–4"
        };
        if (request.Scenario == "tcp_connections") minutes = request.Duration == "LONG" ? "15–25" : request.Duration == "NORMAL" ? "5–10" : "3–6";
        var selection = await lab.ReadSavedRequestAsync(cancellationToken);
        if (selection is null) return Blocked("SELECTION_REQUIRED");
        var observation = await lab.InspectAsync(selection, cancellationToken);
        if (!observation.GetProperty("files_observed").GetBoolean()) return Blocked("SELECTED_FILES_CHANGED");
        if (!observation.GetProperty("recognized_benchmark_files").GetBoolean()) return Blocked("COMPATIBILITY_PENDING");
        if (selection.Contract != "driver") return Blocked("LEGACY_REBOOT_PREFLIGHT_REQUIRED");

        // A copied kit is not sufficient: existing controllers bind receipts and configured absolute paths.
        var kit = Path.Combine(paths.RepositoryRoot, "artifacts", "product-builds", "driver-63be0eb-testlab-cli");
        var driver = Path.Combine(kit, "ProxyBridgeDrv.sys");
        if (!string.Equals(Path.GetFullPath(selection.InstallationDirectory).TrimEnd('\\', '/'), kit, StringComparison.OrdinalIgnoreCase) ||
            (!string.IsNullOrWhiteSpace(selection.DriverPath) && !string.Equals(Path.GetFullPath(selection.DriverPath), driver, StringComparison.OrdinalIgnoreCase)))
            return Blocked("RELOCATED_KIT_PENDING");

        var script = Path.Combine(paths.RepositoryRoot, "scripts", scenario.Controller);
        var entry = Path.Combine(paths.RepositoryRoot, "scripts", "Invoke-PlannedBenchmark.ps1");
        var host = Path.Combine(paths.RepositoryRoot, "scripts", "Invoke-BenchmarkControllerHost.ps1");
        var env = Path.Combine(kit, "product.env");
        var root = Path.Combine(paths.RepositoryRoot, "artifacts", "benchmark-launch");
        foreach (var path in new[] { script, entry, host, env, root }) AssertNoReparse(path);
        var id = "plan-" + Guid.NewGuid().ToString("N");
        var build = await lab.BindBuildAsync(selection, observation, cancellationToken);
        var plan = new
        {
            schema_version = 1, id, contract = "driver", mode = request.Mode, scenario = request.Scenario,
            profile = scenario.Profile, controller_file = scenario.Controller,
            controller_sha256 = Hash(script), entry_sha256 = Hash(entry), host_sha256 = Hash(host), env_sha256 = Hash(env),
            bundle_sha256 = observation.GetProperty("bundle_sha256").GetString(),
            build_id = build.Id, build_name_at_run = build.DisplayName,
            created_at_utc = DateTimeOffset.UtcNow, preparation_scope = "files-on-disk", runtime_ready = false
            ,workload_preset = workload, workload_catalog_sha256 = workload is null || request.Scenario == "tcp_connections" ? null : Hash(Path.Combine(paths.RepositoryRoot, "config", "benchmark-workloads.json")),
            workload_module_sha256 = workload is null ? null : Hash(Path.Combine(paths.RepositoryRoot, "modules", request.Scenario == "tcp_connections" ? "ConnectionLoad.psm1" : "BenchmarkWorkload.psm1")),
            connection_proxy_sha256 = request.Scenario == "tcp_connections" ? Hash(Path.Combine(paths.RepositoryRoot, "src", "pb_controlled_tcp_proxy.py")) : null,
            connection_report_sha256 = request.Scenario == "tcp_connections" ? Hash(Path.Combine(paths.RepositoryRoot, "src", "pb_tcp_connections_report.py")) : null
        };
        Directory.CreateDirectory(root);
        await using (var file = new FileStream(Path.Combine(root, id + ".json"), FileMode.CreateNew, FileAccess.Write, FileShare.None))
            await JsonSerializer.SerializeAsync(file, plan, cancellationToken: cancellationToken);
        await ValidatePlanAsync(entry, id, cancellationToken);
        // Single quotes prevent interpolation of paths in PowerShell, including $ and backticks.
        var command = "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File '" + entry.Replace("'", "''") +
                      "' -PlanId '" + id + "' -Phase Run";
        return new
        {
            status = "PLAN_PREPARED", plan_id = id, contract = "driver", scenario = request.Scenario,
            profile = workload is null ? scenario.Profile : "WORKLOAD", workload_preset = workload, estimated_minutes = minutes, command,
            build_id = build.Id, build_name = build.DisplayName,
            runtime_ready = false, product_started = false, traffic_generated = false,
            controller_checks_required = true, gui_launch_supported = request.Scenario is "tcp_rtt" or "tcp_transfer" or "tcp_rtt_three_modes" or "tcp_connections"
        };
    }

    public async Task<object> PrepareSuiteAsync(BenchmarkSuiteRequest request, CancellationToken token)
    {
        if (request.Scenarios is null || request.Scenarios.Length is < 1 or > 4 ||
            request.Scenarios.Distinct(StringComparer.Ordinal).Count() != request.Scenarios.Length ||
            request.Scenarios.Any(item => item is not ("tcp_rtt" or "tcp_transfer" or "tcp_rtt_three_modes" or "tcp_connections")) ||
            (request.Tests is not null && (request.Tests.Any(test => test is null) || request.Tests.Length != request.Scenarios.Length ||
                !request.Tests.Select(test => test.Scenario).Order().SequenceEqual(request.Scenarios.Order()))))
            return Blocked("SUITE_SELECTION_INVALID");
        // A fixed order makes the selection repeatable; it is not a new measurement method.
        var tests = new List<BenchmarkSuiteTest>();
        string? buildId = null, buildName = null, bundle = null;
        var minutes = 0;
        var minimumMinutes = 0;
        foreach (var scenario in new[] { "tcp_rtt", "tcp_transfer", "tcp_rtt_three_modes", "tcp_connections" }.Where(request.Scenarios.Contains))
        {
            var choice = request.Tests?.Single(test => test.Scenario == scenario);
            var prepared = JsonSerializer.SerializeToElement(await PrepareAsync(new(request.Mode, scenario, choice?.Duration, choice?.Load), token));
            if (prepared.GetProperty("status").GetString() != "PLAN_PREPARED") return prepared;
            var id = prepared.GetProperty("plan_id").GetString()!;
            var file = Path.Combine(paths.RepositoryRoot, "artifacts", "benchmark-launch", id + ".json");
            using var document = JsonDocument.Parse(await File.ReadAllTextAsync(file, token));
            var data = document.RootElement;
            var currentBundle = data.GetProperty("bundle_sha256").GetString()!;
            if (bundle is not null && bundle != currentBundle) return Blocked("SELECTED_FILES_CHANGED");
            bundle = currentBundle;
            buildId = prepared.GetProperty("build_id").GetString()!;
            buildName ??= prepared.GetProperty("build_name").GetString()!;
            tests.Add(new(id, scenario, Hash(file), scenario == "tcp_transfer" ? 4 : scenario == "tcp_rtt_three_modes" ? 3 : 2, choice?.Duration, choice?.Load));
            var estimate = prepared.GetProperty("estimated_minutes").GetString()!.Split('–');
            minimumMinutes += int.Parse(estimate[0], System.Globalization.CultureInfo.InvariantCulture);
            minutes += int.Parse(estimate[1], System.Globalization.CultureInfo.InvariantCulture);
        }
        var suiteId = "suite-" + Guid.NewGuid().ToString("N");
        var plan = new BenchmarkSuitePlan(suiteId, "local", "driver", buildId!, buildName!, bundle!, tests.ToArray());
        var suiteFile = Path.Combine(paths.RepositoryRoot, "artifacts", "benchmark-launch", suiteId + ".json");
        AssertNoReparse(suiteFile);
        await using (var file = new FileStream(suiteFile, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            await JsonSerializer.SerializeAsync(file, plan, new JsonSerializerOptions(JsonSerializerDefaults.Web), token);
        return new
        {
            status = "PLAN_PREPARED", plan_id = suiteId, suite = true, tests = plan.Tests, profile = request.Tests is null ? "SMOKE" : "WORKLOAD",
            build_id = buildId, build_name = buildName, estimated_minutes = $"{minimumMinutes}–{minutes}",
            gui_launch_supported = true, runtime_ready = false, product_started = false, traffic_generated = false,
            controller_checks_required = true
        };
    }

    private static object Blocked(string reason) => new
    {
        status = "PLAN_BLOCKED", reason, runtime_ready = false, product_started = false,
        traffic_generated = false, gui_launch_supported = false
    };

    private static string Hash(string path) => Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(path)));
    private static async Task ValidatePlanAsync(string entry, string id, CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "powershell.exe"))
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
        };
        foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", entry, "-PlanId", id, "-Phase", "Inspect" })
            start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("PLAN_INSPECTOR_NOT_STARTED");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(30));
        var output = process.StandardOutput.ReadToEndAsync(deadline.Token);
        var errors = process.StandardError.ReadToEndAsync(deadline.Token);
        try
        {
            await process.WaitForExitAsync(deadline.Token);
            using var document = JsonDocument.Parse(await output);
            if (process.ExitCode != 0 || !string.IsNullOrEmpty(await errors) ||
                document.RootElement.GetProperty("status").GetString() != "PLAN_FILES_VALIDATED")
                throw new InvalidOperationException("PLAN_FILES_NOT_VALIDATED");
        }
        catch
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            try { await Task.WhenAll(output, errors); } catch (OperationCanceledException) { }
            throw;
        }
    }
    private static void AssertNoReparse(string path)
    {
        for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("LAUNCH_REPARSE_POINT_NOT_SUPPORTED");
    }
}
