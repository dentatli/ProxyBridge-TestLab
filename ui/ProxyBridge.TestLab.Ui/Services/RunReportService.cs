using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class RunReportService(AppPaths paths, AppStoragePaths storagePaths, CatalogService catalogService)
{
    private const long MaxAuditBytes = 50L * 1024 * 1024;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private static readonly HashSet<string> AllowedScenarioEvidence = new(StringComparer.OrdinalIgnoreCase)
    {
        "assertion-result.json",
        "assertions.json",
        "client-result.json",
        "proxybridge-evidence.json",
        "vps-evidence.json",
        "profile-validation.json",
        "post-run-cleanup.json",
        "rule-plan.json",
        "client-plan.json",
        "reset-plan.json",
        "cli-lifecycle.json",
        "vps-collection-result.json",
        "evidence-completeness.json"
    };

    private static readonly HashSet<string> AllowedRunEvidence = new(StringComparer.OrdinalIgnoreCase)
    {
        "summary.json", "results.jsonl", "failures.jsonl", "skipped.jsonl", "selection.jsonl",
        "summary.csv", "coverage.json", "attempt-aggregates.json", "immutable-preflight.json", "direct-baseline-result.json",
        "environment-preparation-result.json"
    };

    public async Task<IReadOnlyList<RunListItem>> ListAsync(CancellationToken cancellationToken)
    {
        var runs = new List<RunListItem>();
        foreach (var location in FindRunLocations())
        {
            var summary = await ReadJsonAsync<RunSummaryDocument>(location.SummaryPath, cancellationToken);
            if (summary is null || summary.SchemaVersion != 1)
            {
                continue;
            }

            runs.Add(new RunListItem(
                location.RunId,
                summary.RunMode,
                summary.ExecutionComplete,
                summary.ProductVerdict,
                summary.Catalog,
                summary.Statuses,
                summary.Fixture || location.IsFixture,
                File.GetLastWriteTimeUtc(location.SummaryPath)));
        }

        return runs.OrderByDescending(run => run.UpdatedUtc).ThenBy(run => run.RunId, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    public async Task<(RunListItem Run, IReadOnlyList<ResultRecord> Results)?> GetAsync(
        string runId,
        CancellationToken cancellationToken)
    {
        var location = FindRunLocations().FirstOrDefault(item =>
            string.Equals(item.RunId, runId, StringComparison.OrdinalIgnoreCase));
        if (location is null)
        {
            return null;
        }

        var summary = await ReadJsonAsync<RunSummaryDocument>(location.SummaryPath, cancellationToken);
        if (summary is null || summary.SchemaVersion != 1)
        {
            return null;
        }

        var listItem = new RunListItem(
            location.RunId,
            summary.RunMode,
            summary.ExecutionComplete,
            summary.ProductVerdict,
            summary.Catalog,
            summary.Statuses,
            summary.Fixture || location.IsFixture,
            File.GetLastWriteTimeUtc(location.SummaryPath));

        var results = await ReadJsonLinesAsync<ResultRecord>(Path.Combine(location.Root, "results.jsonl"), cancellationToken);
        return (listItem, results);
    }

    public async Task<ScenarioResultDetail?> GetScenarioAsync(
        string runId,
        string scenarioId,
        CancellationToken cancellationToken)
    {
        var run = await GetAsync(runId, cancellationToken);
        if (run is null)
        {
            return null;
        }

        var result = run.Value.Results.FirstOrDefault(item =>
            string.Equals(item.ScenarioId, scenarioId, StringComparison.OrdinalIgnoreCase));
        if (result is null)
        {
            return null;
        }

        var location = FindRunLocations().First(item =>
            string.Equals(item.RunId, runId, StringComparison.OrdinalIgnoreCase));
        var scenarioRoot = Path.GetFullPath(Path.Combine(location.Root, "scenarios", scenarioId));
        var expectedPrefix = Path.GetFullPath(Path.Combine(location.Root, "scenarios")) + Path.DirectorySeparatorChar;
        var evidence = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        if (scenarioRoot.StartsWith(expectedPrefix, StringComparison.OrdinalIgnoreCase) && Directory.Exists(scenarioRoot) &&
            (File.GetAttributes(scenarioRoot) & FileAttributes.ReparsePoint) == 0)
        {
            foreach (var file in Directory.EnumerateFiles(scenarioRoot, "*.json", SearchOption.TopDirectoryOnly))
            {
                var name = Path.GetFileName(file);
                if (!AllowedScenarioEvidence.Contains(name) || (File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0)
                {
                    continue;
                }

                await using var stream = File.OpenRead(file);
                using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
                evidence[name] = document.RootElement.Clone();
            }
        }

        var catalog = await catalogService.GetAllAsync(cancellationToken);
        var scenario = catalog.FirstOrDefault(item => item.ScenarioId.Equals(scenarioId, StringComparison.OrdinalIgnoreCase));
        return new ScenarioResultDetail(result, evidence, BuildExplanation(result, evidence, scenario));
    }

    public async Task<RunAuditExport?> CreateAuditExportAsync(string runId, CancellationToken cancellationToken)
    {
        var location = FindRunLocations().FirstOrDefault(item => string.Equals(item.RunId, runId, StringComparison.OrdinalIgnoreCase));
        if (location is null) return null;
        var run = await GetAsync(runId, cancellationToken);
        if (run is null) return null;

        using var output = new MemoryStream();
        using (var archive = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true, entryNameEncoding: Encoding.UTF8))
        {
            var checksums = new SortedDictionary<string, string>(StringComparer.Ordinal);
            var included = new List<string>();
            long includedBytes = 0;
            foreach (var name in AllowedRunEvidence.Order(StringComparer.Ordinal))
            {
                var path = Path.Combine(location.Root, name);
                if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0)
                    includedBytes += AddFile(archive, path, name, checksums, included, MaxAuditBytes - includedBytes);
            }
            var scenariosRoot = Path.Combine(location.Root, "scenarios");
            if (Directory.Exists(scenariosRoot) && (File.GetAttributes(scenariosRoot) & FileAttributes.ReparsePoint) == 0)
            {
                foreach (var directory in Directory.EnumerateDirectories(scenariosRoot, "*", SearchOption.TopDirectoryOnly))
                {
                    if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0) continue;
                    var scenarioId = Path.GetFileName(directory);
                    if (scenarioId.Any(ch => !(char.IsLetterOrDigit(ch) || ch is '-' or '_' or '.'))) continue;
                    foreach (var name in AllowedScenarioEvidence.Order(StringComparer.Ordinal))
                    {
                        var path = Path.Combine(directory, name);
                        if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0)
                            includedBytes += AddFile(archive, path, $"scenarios/{scenarioId}/{name}", checksums, included, MaxAuditBytes - includedBytes);
                    }
                }
            }

            var reportText = BuildAuditReport(run.Value.Run, run.Value.Results);
            AddBytes(archive, "CODEX_AUDIT_REPORT.md", Encoding.UTF8.GetBytes(reportText), checksums, included);
            var manifest = JsonSerializer.Serialize(new
            {
                schema_version = 1,
                run_id = runId,
                source = location.IsFixture ? "PUBLIC_FIXTURE" : "SANITIZED_RUN_EVIDENCE",
                included,
                excluded = new[] { ".env and compatibility inputs", "generated profiles", "credentials and protected settings", "raw transcript", "arbitrary evidence files" }
            }, new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine;
            AddBytes(archive, "MANIFEST.json", Encoding.UTF8.GetBytes(manifest), checksums, included);
            var sums = string.Join("\n", checksums.Select(item => $"{item.Value}  {item.Key}")) + "\n";
            var entry = archive.CreateEntry("SHA256SUMS.txt", CompressionLevel.Optimal);
            using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false));
            writer.Write(sums);
        }
        return new RunAuditExport(output.ToArray(), $"ProxyBridge-TestLab-{runId}-Audit.zip");
    }

    private static ScenarioExplanationView BuildExplanation(
        ResultRecord result,
        IReadOnlyDictionary<string, JsonElement> evidence,
        CatalogScenario? scenario)
    {
        var assertion = evidence.TryGetValue("assertions.json", out var current)
            ? current
            : evidence.TryGetValue("assertion-result.json", out var fixture) ? fixture : default;
        var hasAssertion = assertion.ValueKind == JsonValueKind.Object;
        var outcome = hasAssertion && assertion.TryGetProperty("outcome", out var outcomeValue) ? outcomeValue.GetString() ?? result.Status : result.Status;
        var basis = hasAssertion && assertion.TryGetProperty("evidence_basis", out var basisValue) ? basisValue.GetString() ?? "NOT_RECORDED" : "NOT_RECORDED";
        var productErrors = ReadStringArray(assertion, "product_errors");
        var harnessErrors = ReadStringArray(assertion, "harness_errors");
        var missing = ReadStringArray(assertion, "missing_evidence");
        var contamination = ReadStringArray(assertion, "contamination");
        var category = result.Status switch
        {
            "PASS" or "MOCK_PASS" => "PASS",
            "FAIL_PRODUCT" or "EXPECTED_FAIL" or "MOCK_EXPECTED_FAIL" => "PRODUCT",
            "FAIL_HARNESS" or "FAIL_INFRASTRUCTURE" => "HARNESS",
            "CONTAMINATED" => "SAFETY",
            "HOLD_AMBIGUOUS" or "MOCK_HOLD" => "INCOMPLETE_EVIDENCE",
            _ when result.Status.StartsWith("SKIPPED", StringComparison.Ordinal) || result.Status is "NOT_IMPLEMENTED" or "UNSUPPORTED_PRODUCT_SCOPE" => "NOT_EXECUTED",
            _ => "INFORMATIONAL"
        };
        var what = scenario is null
            ? $"Scenario {result.ScenarioId} in coverage group {result.CoverageGroup}."
            : $"{scenario.Title} The selected contract covers {scenario.Protocol} IPv{scenario.Family}, {scenario.SocketMode} sockets, and the {scenario.Action} action.";
        var expected = scenario is null
            ? "The expected behavior is defined by the recorded runner plan."
            : $"Expected action: {scenario.Action}. Required assertions: {(scenario.Assertions.Count == 0 ? "none recorded" : string.Join(", ", scenario.Assertions))}.";
        var observed = hasAssertion
            ? $"The assertion record reported {outcome} using evidence basis {basis}."
            : $"No structured assertion artifact was available. The result record reported: {result.Reason}";
        var why = category switch
        {
            "PASS" => "All mandatory evidence evaluated by the runner satisfied the recorded assertion contract.",
            "PRODUCT" => productErrors.Count > 0 ? "Canonical product-path contradictions: " + string.Join("; ", productErrors) : result.Reason,
            "HARNESS" => harnessErrors.Count > 0 ? "Harness or infrastructure errors: " + string.Join("; ", harnessErrors) : result.Reason,
            "SAFETY" => contamination.Count > 0 ? "Unsafe shared-state evidence: " + string.Join("; ", contamination) : result.Reason,
            "INCOMPLETE_EVIDENCE" => missing.Count > 0 ? "Mandatory evidence was incomplete: " + string.Join("; ", missing) : result.Reason,
            _ => result.Reason
        };
        var nextAction = category switch
        {
            "PASS" => "No corrective action is indicated by this recorded result.",
            "PRODUCT" => result.Status.Contains("EXPECTED", StringComparison.Ordinal) ? "Compare the signature with the mapped known defect before product changes." : "Review the product errors and correlated route evidence.",
            "HARNESS" => "Correct the harness or infrastructure condition, prove shared state clean, then rerun this scenario.",
            "SAFETY" => "Do not continue. Restore and independently verify a clean product environment first.",
            "INCOMPLETE_EVIDENCE" => "Restore the missing evidence channel; do not convert this result into a product verdict.",
            "NOT_EXECUTED" => "Review the recorded implementation, capability, selection, or safety-stop reason.",
            _ => "Review the structured evidence and runner reason."
        };
        var channels = new[]
        {
            Channel("Client lifecycle", evidence, "client-result.json"),
            Channel("ProxyBridge route", evidence, "proxybridge-evidence.json"),
            Channel("Endpoint payload", evidence, "vps-evidence.json"),
            Channel("Assertions", evidence, evidence.ContainsKey("assertions.json") ? "assertions.json" : "assertion-result.json"),
            Channel("Post-run cleanup", evidence, "post-run-cleanup.json")
        };
        var timelineNames = new[]
        {
            ("Profile validation", "profile-validation.json"), ("Rule plan", "rule-plan.json"),
            ("Client plan", "client-plan.json"), ("Client result", "client-result.json"),
            ("Route evidence", "proxybridge-evidence.json"), ("Endpoint evidence", "vps-evidence.json"),
            ("Assertion", evidence.ContainsKey("assertions.json") ? "assertions.json" : "assertion-result.json"),
            ("Cleanup", "post-run-cleanup.json")
        };
        var timeline = timelineNames.Select((item, index) => new AssertionTimelineEntry(
            index + 1, item.Item1, evidence.ContainsKey(item.Item2) ? "RECORDED" : "NOT_RECORDED",
            evidence.ContainsKey(item.Item2) ? $"Sanitized artifact {item.Item2} is present." : "No allowed artifact was present in this report view.")).ToArray();
        return new ScenarioExplanationView(
            category,
            $"{result.ScenarioId} finished as {result.Status}.",
            what,
            expected,
            observed,
            why,
            nextAction,
            basis,
            productErrors,
            harnessErrors,
            missing,
            contamination,
            channels,
            timeline);
    }

    private static EvidenceChannelView Channel(string name, IReadOnlyDictionary<string, JsonElement> evidence, string artifact) =>
        evidence.ContainsKey(artifact)
            ? new(name, "RECORDED", "A sanitized structured artifact is available.", artifact)
            : new(name, "NOT_RECORDED", "No allowed structured artifact is available in this report.", null);

    private static IReadOnlyList<string> ReadStringArray(JsonElement value, string name)
    {
        if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty(name, out var property) || property.ValueKind != JsonValueKind.Array) return [];
        return property.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString() ?? "").Where(item => item.Length > 0).ToArray();
    }

    private static string BuildAuditReport(RunListItem run, IReadOnlyList<ResultRecord> results)
    {
        var builder = new StringBuilder();
        builder.AppendLine("# ProxyBridge TestLab sanitized run audit").AppendLine();
        builder.AppendLine($"- Run ID: `{run.RunId}`");
        builder.AppendLine($"- Mode: `{run.RunMode}`");
        builder.AppendLine($"- Execution complete: `{run.ExecutionComplete.ToString().ToLowerInvariant()}`");
        builder.AppendLine($"- Product verdict: `{run.ProductVerdict}`");
        builder.AppendLine($"- Selected scenarios: `{run.Catalog.Selected}`").AppendLine();
        builder.AppendLine("## Scenario results").AppendLine();
        foreach (var result in results.Where(item => item.Selected))
            builder.AppendLine($"- `{result.ScenarioId}` — **{result.Status}** — {result.Reason.Replace("\r", " ").Replace("\n", " ")}");
        builder.AppendLine().AppendLine("This export contains only the explicit sanitized allowlist in `MANIFEST.json`. It excludes compatibility inputs, generated profiles, credentials, raw transcripts and arbitrary files.");
        return builder.ToString();
    }

    private static long AddFile(ZipArchive archive, string path, string entryName, IDictionary<string, string> checksums, ICollection<string> included, long remainingBytes)
    {
        var info = new FileInfo(path);
        if (info.Length > 10 * 1024 * 1024 || info.Length > remainingBytes) return 0;
        AddBytes(archive, entryName, File.ReadAllBytes(path), checksums, included);
        return info.Length;
    }

    private static void AddBytes(ZipArchive archive, string entryName, byte[] bytes, IDictionary<string, string> checksums, ICollection<string> included)
    {
        var normalized = entryName.Replace('\\', '/');
        var entry = archive.CreateEntry(normalized, CompressionLevel.Optimal);
        using (var stream = entry.Open()) stream.Write(bytes);
        checksums[normalized] = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        included.Add(normalized);
    }

    private IReadOnlyList<RunLocation> FindRunLocations()
    {
        var locations = new Dictionary<string, RunLocation>(StringComparer.OrdinalIgnoreCase);
        foreach (var evidenceRoot in paths.EvidenceRoots.Prepend(storagePaths.EvidenceRoot))
        {
            if (!Directory.Exists(evidenceRoot))
            {
                continue;
            }

            var rootFull = Path.GetFullPath(evidenceRoot) + Path.DirectorySeparatorChar;
            var enumeration = new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint };
            foreach (var summaryPath in Directory.EnumerateFiles(evidenceRoot, "summary.json", enumeration))
            {
                var runRoot = Path.GetDirectoryName(summaryPath)!;
                var runRootFull = Path.GetFullPath(runRoot);
                if (!runRootFull.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var baseId = Path.GetFileName(runRootFull);
                if (string.IsNullOrWhiteSpace(baseId) || baseId.Any(ch => !(char.IsLetterOrDigit(ch) || ch is '-' or '_' or '.')))
                {
                    continue;
                }

                var isFixture = evidenceRoot.Contains(Path.Combine("tests", "fixtures"), StringComparison.OrdinalIgnoreCase);
                var id = locations.ContainsKey(baseId) ? $"{(isFixture ? "fixture" : "evidence")}-{baseId}" : baseId;
                locations[id] = new RunLocation(id, runRootFull, summaryPath, isFixture);
            }
        }

        return locations.Values.ToArray();
    }

    private static async Task<T?> ReadJsonAsync<T>(string path, CancellationToken cancellationToken)
    {
        await using var stream = File.OpenRead(path);
        return await JsonSerializer.DeserializeAsync<T>(stream, JsonOptions, cancellationToken);
    }

    private static async Task<IReadOnlyList<T>> ReadJsonLinesAsync<T>(string path, CancellationToken cancellationToken)
    {
        var values = new List<T>();
        if (!File.Exists(path))
        {
            return values;
        }

        using var reader = new StreamReader(path);
        while (await reader.ReadLineAsync(cancellationToken) is { } line)
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var value = JsonSerializer.Deserialize<T>(line, JsonOptions);
            if (value is not null)
            {
                values.Add(value);
            }
        }

        return values;
    }

    private sealed record RunLocation(string RunId, string Root, string SummaryPath, bool IsFixture);
}
