using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record RunExecutionContext(string RunId, string Mode, IReadOnlyList<string> ScenarioIds, int Attempt);

public interface IRunExecutor
{
    Task<RunExecutionResult> ExecuteAsync(
        RunExecutionContext context,
        Func<RunExecutionProgress, Task> progress,
        CancellationToken cancellationToken);
}

public sealed class PowerShellRunExecutor(
    AppPaths appPaths,
    AppStoragePaths storagePaths,
    SettingsStore settingsStore,
    RunnerEnvironmentService runnerEnvironment,
    RuntimeCapabilityService runtimeCapabilities) : IRunExecutor
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);

    public async Task<RunExecutionResult> ExecuteAsync(
        RunExecutionContext context,
        Func<RunExecutionProgress, Task> progress,
        CancellationToken cancellationToken)
    {
        var runtimeRoot = GetChildPath(storagePaths.RuntimeRoot, context.RunId);
        var evidenceRoot = GetChildPath(storagePaths.EvidenceRoot, context.RunId);
        AppStoragePaths.EnsureSecureDirectory(runtimeRoot);
        AppStoragePaths.EnsureSecureDirectory(evidenceRoot);
        var cancellationPath = Path.Combine(runtimeRoot, "cancel.requested");
        var suitePath = Path.Combine(runtimeRoot, "suite.json");
        var capabilitiesPath = Path.Combine(runtimeRoot, "capabilities.json");
        if (File.Exists(cancellationPath)) File.Delete(cancellationPath);

        var settings = await settingsStore.LoadAsync(CancellationToken.None);
        var derivedCapabilities = context.Mode == "real"
            ? await runtimeCapabilities.GetAsync(CancellationToken.None)
            : DerivedRunCapabilitySnapshot.Unavailable;
        await WriteSuiteAsync(context.Mode, context.ScenarioIds, suitePath);
        await WriteCapabilitiesAsync(settings.Settings.Capabilities, derivedCapabilities, capabilitiesPath);

        RunnerInputLease? inputLease = null;
        try
        {
            var environmentPath = appPaths.FixtureEnvironmentPath;
            if (context.Mode == "real")
            {
                inputLease = await runnerEnvironment.MaterializeAsync(settings, context.RunId, CancellationToken.None);
                environmentPath = inputLease.Path;
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                WorkingDirectory = appPaths.RepositoryRoot,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Utf8NoBom,
                StandardErrorEncoding = Utf8NoBom
            };
            foreach (var argument in new[]
            {
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", appPaths.RunnerPath,
                "-EnvPath", environmentPath,
                "-CapabilitiesPath", capabilitiesPath,
                "-SuitePath", suitePath,
                "-KnownDefectsPath", appPaths.KnownDefectsPath,
                "-ClientContractPath", appPaths.ClientContractPath,
                "-RuntimeConfigPath", appPaths.RuntimeConfigPath,
                "-ScenarioRoot", appPaths.ScenarioRoot,
                "-MockFixtureRoot", appPaths.MockFixtureRoot,
                "-OutputRoot", evidenceRoot,
                "-CancellationPath", cancellationPath,
                context.Mode == "real" ? "-AllowProductRuntime" : "-MockRuntime"
            }) startInfo.ArgumentList.Add(argument);
            if (context.Mode == "real") startInfo.ArgumentList.Add("-PrepareRuntimeEnvironment");

            Process process;
            try { process = Process.Start(startInfo) ?? throw new InvalidOperationException("RUNNER_START_RETURNED_NULL"); }
            catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                return new RunExecutionResult(false, null, false, false, true, "The PowerShell runner could not be started.");
            }

            using (process)
            {
                var stdout = process.StandardOutput.ReadToEndAsync();
                var stderr = process.StandardError.ReadToEndAsync();
                var cancellationWritten = false;
                IReadOnlyList<RunScenarioProgress> lastScenarios = [];
                while (!process.HasExited)
                {
                    if (cancellationToken.IsCancellationRequested && !cancellationWritten)
                    {
                        await File.WriteAllTextAsync(cancellationPath, "cancel\n", Utf8NoBom, CancellationToken.None);
                        cancellationWritten = true;
                    }
                    lastScenarios = await ReadScenarioProgressAsync(evidenceRoot, context.ScenarioIds);
                    var current = context.ScenarioIds.FirstOrDefault(id => lastScenarios.All(item => !item.ScenarioId.Equals(id, StringComparison.OrdinalIgnoreCase)));
                    await progress(new RunExecutionProgress(
                        cancellationWritten ? "CANCELLING" : "RUNNING",
                        current,
                        lastScenarios,
                        cancellationWritten ? "Cancellation is queued; the current bounded runner operation will clean up first." : "The authoritative runner is evaluating the selected scenario contract."));
                    await Task.Delay(200, CancellationToken.None);
                }
                await process.WaitForExitAsync(CancellationToken.None);
                _ = await stdout;
                _ = await stderr;

                lastScenarios = await ReadScenarioProgressAsync(evidenceRoot, context.ScenarioIds);
                await progress(new RunExecutionProgress("FINALIZING", null, lastScenarios, "The controller is validating the generated report."));
                var runRoot = FindNewestRunRoot(evidenceRoot);
                var summaryExists = runRoot is not null && File.Exists(Path.Combine(runRoot, "summary.json"));
                var evidenceRunId = summaryExists ? Path.GetFileName(runRoot) : null;
                var contaminated = lastScenarios.Any(item => item.Status == "CONTAMINATED");
                var recoverable = !summaryExists && !Directory.EnumerateFiles(evidenceRoot, "results.jsonl", SearchOption.AllDirectories).Any();
                return new RunExecutionResult(
                    summaryExists,
                    evidenceRunId,
                    cancellationWritten,
                    contaminated,
                    recoverable,
                    summaryExists
                        ? process.ExitCode == 0 ? "The runner completed and produced a validated report." : "The runner produced evidence and reported one or more failures."
                        : "The runner ended before a complete evidence report was produced.");
            }
        }
        finally
        {
            if (inputLease is not null) await inputLease.DisposeAsync();
        }
    }

    private async Task WriteSuiteAsync(string mode, IReadOnlyList<string> scenarioIds, string destination)
    {
        var source = mode == "real" ? appPaths.RealSuitePath : appPaths.MockSuitePath;
        var root = JsonNode.Parse(await File.ReadAllTextAsync(source))?.AsObject() ?? throw new InvalidOperationException("RUN_SUITE_INVALID");
        var selection = root["selection"]?.AsObject() ?? throw new InvalidOperationException("RUN_SUITE_SELECTION_INVALID");
        selection["include_tags"] = new JsonArray();
        selection["exclude_tags"] = new JsonArray();
        selection["exclude_scenario_ids"] = new JsonArray();
        selection["include_scenario_ids"] = new JsonArray(scenarioIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray());
        if (mode == "mock")
        {
            var execution = root["execution"]?.AsObject() ?? throw new InvalidOperationException("RUN_SUITE_EXECUTION_INVALID");
            execution["stop_on_harness_failure"] = false;
            execution["stop_on_infrastructure_failure"] = false;
        }
        await File.WriteAllTextAsync(destination, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine, Utf8NoBom);
    }

    private async Task WriteCapabilitiesAsync(
        CapabilitySettings settings,
        DerivedRunCapabilitySnapshot derivedCapabilities,
        string destination)
    {
        var root = JsonNode.Parse(await File.ReadAllTextAsync(appPaths.CapabilitiesPath))?.AsObject() ?? throw new InvalidOperationException("RUN_CAPABILITIES_INVALID");
        var capabilities = root["capabilities"]?.AsObject() ?? throw new InvalidOperationException("RUN_CAPABILITIES_SECTION_INVALID");
        RunCapabilityDocument.Apply(capabilities, settings, derivedCapabilities);
        await File.WriteAllTextAsync(destination, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine, Utf8NoBom);
    }

    private static async Task<IReadOnlyList<RunScenarioProgress>> ReadScenarioProgressAsync(string evidenceRoot, IReadOnlyList<string> requested)
    {
        var runRoot = FindNewestRunRoot(evidenceRoot);
        var resultsPath = runRoot is null ? null : Path.Combine(runRoot, "results.jsonl");
        if (resultsPath is null || !File.Exists(resultsPath)) return [];
        var byId = new Dictionary<string, RunScenarioProgress>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var stream = new FileStream(resultsPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(stream, Encoding.UTF8, true);
            while (await reader.ReadLineAsync() is { } line)
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                var scenarioId = root.GetProperty("scenario_id").GetString() ?? "";
                if (!requested.Contains(scenarioId, StringComparer.OrdinalIgnoreCase)) continue;
                var status = root.GetProperty("status").GetString() ?? "UNKNOWN";
                var selected = root.TryGetProperty("selected", out var selectedValue) && selectedValue.GetBoolean();
                var reason = root.TryGetProperty("reason", out var reasonValue) ? reasonValue.GetString() ?? "" : "";
                long? duration = root.TryGetProperty("duration_ms", out var durationValue) ? durationValue.GetInt64() : null;
                byId[scenarioId] = new RunScenarioProgress(scenarioId, selected ? "EXECUTED" : "SKIPPED", status, reason, duration);
            }
        }
        catch (IOException) { }
        catch (JsonException) { }
        return requested.Where(byId.ContainsKey).Select(id => byId[id]).ToArray();
    }

    private static string? FindNewestRunRoot(string evidenceRoot) => Directory.Exists(evidenceRoot)
        ? Directory.EnumerateDirectories(evidenceRoot, "*", SearchOption.TopDirectoryOnly)
            .Where(path => (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0)
            .OrderByDescending(Directory.GetLastWriteTimeUtc)
            .FirstOrDefault()
        : null;

    private static string GetChildPath(string root, string child)
    {
        if (string.IsNullOrWhiteSpace(child) || child.Any(ch => !(char.IsLetterOrDigit(ch) || ch is '-' or '_' or '.')))
            throw new InvalidOperationException("RUN_ID_INVALID");
        var full = Path.GetFullPath(Path.Combine(root, child));
        var prefix = Path.GetFullPath(root) + Path.DirectorySeparatorChar;
        if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("RUN_PATH_INVALID");
        return full;
    }
}
