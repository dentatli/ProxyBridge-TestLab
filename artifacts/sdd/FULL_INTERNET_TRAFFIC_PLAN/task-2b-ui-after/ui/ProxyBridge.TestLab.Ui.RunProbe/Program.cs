using System.IO.Compression;
using System.Text.Json.Nodes;
using ProxyBridge.TestLab.Ui.Hubs;
using ProxyBridge.TestLab.Ui.Models;
using ProxyBridge.TestLab.Ui.Services;

if (args.Length != 1) throw new InvalidOperationException("RUN_PROBE_ROOT_REQUIRED");
var root = Path.GetFullPath(args[0]);
Directory.CreateDirectory(root);
var paths = new AppStoragePaths(Path.Combine(root, "storage"));
var store = new RunJobStore(paths);
var confirmations = new RunConfirmationService();
var readiness = new FakeReadiness(confirmations);
var executor = new FakeExecutor();
var publisher = new FakePublisher();

var orphanTime = DateTimeOffset.UtcNow.AddMinutes(-2);
var orphan = new RunJobView(
    "job-orphan", "mock", "RUNNING", ["fixture-pass"], 1, 0, "fixture-pass", "RUNNING", 0, false, false, null, null,
    orphanTime, orphanTime, [new("RUNNING", orphanTime, "fixture orphan")], []);
await store.SaveAsync(orphan, CancellationToken.None);

var coordinator = new RunCoordinator(readiness, confirmations, executor, store, publisher);
await coordinator.StartAsync(CancellationToken.None);
try
{
    Require(coordinator.Get("job-orphan")?.State == "FAILED_TO_START", "ORPHAN_WAS_RESUMED");
    Require(coordinator.Get("job-orphan")?.TerminalReason == "CONTROLLER_RESTART_INTERRUPTED", "ORPHAN_REASON_INVALID");

    var productJob = await QueueRealAsync(coordinator, ["fixture-pass", "fixture-product-fail", "fixture-after-failure"]);
    var secondJob = await QueueRealAsync(coordinator, ["fixture-pass-2"]);
    productJob = await WaitTerminalAsync(coordinator, productJob.RunId);
    secondJob = await WaitTerminalAsync(coordinator, secondJob.RunId);
    Require(productJob.State == "COMPLETED" && secondJob.State == "COMPLETED", "REAL_QUEUE_DID_NOT_COMPLETE");
    Require(executor.MaxConcurrentReal == 1, "REAL_RUN_LEASE_NOT_EXCLUSIVE");
    Require(productJob.Scenarios.Any(item => item.Status == "FAIL_PRODUCT"), "PRODUCT_FAILURE_FIXTURE_MISSING");
    Require(productJob.Scenarios.Any(item => item.ScenarioId == "fixture-after-failure" && item.Status == "PASS"), "PRODUCT_FAILURE_STOPPED_CHAIN");

    var recoveryPreparation = await coordinator.PrepareAsync(new RunCreateRequest("mock", ["recover-once"]), CancellationToken.None);
    var recoveryJob = await coordinator.QueueAsync(new RunCreateRequest("mock", recoveryPreparation.ScenarioIds), CancellationToken.None);
    recoveryJob = await WaitTerminalAsync(coordinator, recoveryJob.RunId);
    Require(recoveryJob.State == "COMPLETED" && recoveryJob.RecoveryAttempts == 1, "BOUNDED_RECOVERY_INVALID");

    var cancelPreparation = await coordinator.PrepareAsync(new RunCreateRequest("mock", ["cancel-me", "never-start"]), CancellationToken.None);
    var cancelJob = await coordinator.QueueAsync(new RunCreateRequest("mock", cancelPreparation.ScenarioIds), CancellationToken.None);
    await WaitStateAsync(coordinator, cancelJob.RunId, "RUNNING");
    await coordinator.CancelAsync(cancelJob.RunId, CancellationToken.None);
    cancelJob = await WaitTerminalAsync(coordinator, cancelJob.RunId);
    Require(cancelJob.State == "CANCELLED" && cancelJob.CancellationRequested, "COOPERATIVE_CANCEL_INVALID");

    var noncePreparation = await coordinator.PrepareAsync(new RunCreateRequest("real", ["nonce-test"]), CancellationToken.None);
    Require(!string.IsNullOrWhiteSpace(noncePreparation.ConfirmationNonce), "REAL_NONCE_MISSING");
    var nonce = noncePreparation.ConfirmationNonce;
    Require(confirmations.Consume(nonce, "real", ["nonce-test"]), "REAL_NONCE_FIRST_USE_FAILED");
    Require(!confirmations.Consume(nonce, "real", ["nonce-test"]), "REAL_NONCE_REUSED");
    var mismatched = confirmations.Issue("real", ["nonce-test"]);
    Require(!confirmations.Consume(mismatched.Nonce, "real", ["different-test"]), "REAL_NONCE_SELECTION_NOT_BOUND");

    Require(RunContinuationPolicy.Decide("FAIL_PRODUCT", true, false, true) == RunContinuationAction.Continue, "PRODUCT_CONTINUATION_INVALID");
    Require(RunContinuationPolicy.Decide("FAIL_HARNESS", true, false, true) == RunContinuationAction.RecoverOnce, "HARNESS_RECOVERY_INVALID");
    Require(RunContinuationPolicy.Decide("FAIL_HARNESS", true, true, true) == RunContinuationAction.SafetyStop, "RECOVERY_NOT_BOUNDED");
    Require(RunContinuationPolicy.Decide("PASS", true, false, false) == RunContinuationAction.SafetyStop, "UNCLEAN_STATE_DID_NOT_STOP");
    Require(publisher.Events.Count > 0, "RUN_PROGRESS_NOT_PUBLISHED");

    var receiptAuthority = new ImmutablePreflightReceiptAuthority();
    var receiptTime = DateTimeOffset.UtcNow;
    var immutableReceipt = receiptAuthority.Issue("selection-and-input-digest", receiptTime);
    Require(receiptAuthority.Validate(immutableReceipt, "selection-and-input-digest", receiptTime.AddSeconds(1)), "IMMUTABLE_RECEIPT_REJECTED");
    Require(!receiptAuthority.Validate(immutableReceipt, "different-digest", receiptTime.AddSeconds(1)), "IMMUTABLE_RECEIPT_NOT_SELECTION_BOUND");
    var tamperedReceipt = immutableReceipt with { Signature = new string('0', immutableReceipt.Signature.Length) };
    Require(!receiptAuthority.Validate(tamperedReceipt, "selection-and-input-digest", receiptTime.AddSeconds(1)), "IMMUTABLE_RECEIPT_TAMPER_ACCEPTED");
    var malformedReceipt = immutableReceipt with { Signature = "not-hex" };
    Require(!receiptAuthority.Validate(malformedReceipt, "selection-and-input-digest", receiptTime.AddSeconds(1)), "IMMUTABLE_RECEIPT_MALFORMED_SIGNATURE_ACCEPTED");
    Require(!receiptAuthority.Validate(immutableReceipt, "selection-and-input-digest", immutableReceipt.ExpiresUtc.AddSeconds(1)), "IMMUTABLE_RECEIPT_EXPIRY_IGNORED");

    var browserFixtureRoot = Path.Combine(root, "browser-discovery");
    Directory.CreateDirectory(browserFixtureRoot);
    var browserCandidate = Path.Combine(browserFixtureRoot, "msedge.exe");
    File.Copy(Environment.ProcessPath ?? throw new InvalidOperationException("PROCESS_PATH_MISSING"), browserCandidate);
    var discoveredBrowser = LocalArtifactService.DiscoverBrowserFromAllowlistedCandidates([browserCandidate]);
    Require(discoveredBrowser.Ready && discoveredBrowser.Status == "READY", "AUTOMATIC_BROWSER_DISCOVERY_FAILED");
    Require(discoveredBrowser.ExecutablePath == Path.GetFullPath(browserCandidate), "AUTOMATIC_BROWSER_PATH_NOT_NORMALIZED");
    Require(discoveredBrowser.BrowserIdentity == "Microsoft Edge", "AUTOMATIC_BROWSER_IDENTITY_INVALID");
    Require(discoveredBrowser.Sha256 is { Length: 64 }, "AUTOMATIC_BROWSER_HASH_MISSING");
    var missingBrowser = LocalArtifactService.DiscoverBrowserFromAllowlistedCandidates([Path.Combine(browserFixtureRoot, "missing", "chrome.exe")]);
    Require(!missingBrowser.Ready && missingBrowser.Status == "NOT_FOUND" && missingBrowser.ExecutablePath is null, "MISSING_BROWSER_NOT_GATED");
    var wrongName = Path.Combine(browserFixtureRoot, "arbitrary.exe");
    File.Copy(Environment.ProcessPath!, wrongName);
    var rejectedBrowser = LocalArtifactService.DiscoverBrowserFromAllowlistedCandidates([wrongName]);
    Require(!rejectedBrowser.Ready && rejectedBrowser.Status == "NOT_FOUND", "NON_BROWSER_IMAGE_WAS_ACCEPTED");

    var readyServer = new ServerStatusView("READY", "Ready fixture.", true, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddMinutes(5), []);
    var staleServer = readyServer with { State = "STALE", Message = "Stale fixture." };
    var readyCapabilities = DerivedRunCapabilitySnapshot.Derive(discoveredBrowser, readyServer);
    Require(readyCapabilities.LocalBrowserRuntime && readyCapabilities.ServerBrowserOrigin, "DERIVED_BROWSER_CAPABILITIES_NOT_ENABLED");
    var missingBrowserCapabilities = DerivedRunCapabilitySnapshot.Derive(missingBrowser, readyServer);
    Require(!missingBrowserCapabilities.LocalBrowserRuntime && missingBrowserCapabilities.ServerBrowserOrigin, "MISSING_BROWSER_DID_NOT_DISABLE_ONLY_LOCAL_CAPABILITY");
    var staleServerCapabilities = DerivedRunCapabilitySnapshot.Derive(discoveredBrowser, staleServer);
    Require(staleServerCapabilities.LocalBrowserRuntime && !staleServerCapabilities.ServerBrowserOrigin, "STALE_SERVER_ORIGIN_NOT_DISABLED");

    var browserScenario = Scenario("browser-required", ["local_browser_runtime", "server_browser_origin"]);
    var missingBrowserGates = RunCapabilityReadiness.Create("real", [browserScenario], missingBrowserCapabilities);
    var localBrowserGate = missingBrowserGates.Single(gate => gate.Id == "local_browser_runtime");
    Require(!localBrowserGate.Passed && localBrowserGate.Remediation?.Contains("browser", StringComparison.OrdinalIgnoreCase) == true, "REQUIRED_BROWSER_NOT_BLOCKED_WITH_REMEDIATION");
    var staleServerGates = RunCapabilityReadiness.Create("real", [browserScenario], staleServerCapabilities);
    var browserOriginGate = staleServerGates.Single(gate => gate.Id == "server_browser_origin");
    Require(!browserOriginGate.Passed && browserOriginGate.Remediation?.Contains("Server Setup", StringComparison.Ordinal) == true, "REQUIRED_BROWSER_ORIGIN_NOT_BLOCKED_WITH_REMEDIATION");
    Require(!string.Join(' ', missingBrowserGates.Concat(staleServerGates).SelectMany(gate => new[] { gate.Detail, gate.Remediation ?? "" }))
        .Contains(browserCandidate, StringComparison.OrdinalIgnoreCase), "PUBLIC_BROWSER_GATE_LEAKED_PATH");
    Require(!string.Join(' ', missingBrowserGates.Concat(staleServerGates).SelectMany(gate => new[] { gate.Detail, gate.Remediation ?? "" }))
        .Contains(discoveredBrowser.Sha256!, StringComparison.OrdinalIgnoreCase), "PUBLIC_BROWSER_GATE_LEAKED_HASH");

    var nonBrowserGates = RunCapabilityReadiness.Create("real", [Scenario("native-tcp", ["ipv4", "tcp"])], DerivedRunCapabilitySnapshot.Unavailable);
    Require(nonBrowserGates.All(gate => gate.Passed), "NON_BROWSER_SELECTION_WAS_CAPABILITY_BLOCKED");
    Require(RunCapabilityReadiness.Create("mock", [browserScenario], DerivedRunCapabilitySnapshot.Unavailable).Count == 0, "FIXTURE_MODE_WAS_BROWSER_CAPABILITY_GATED");

    var repositoryPaths = new AppPaths(AppPaths.Discover(null));
    var capabilityDocument = JsonNode.Parse(await File.ReadAllTextAsync(repositoryPaths.CapabilitiesPath))?.AsObject()
        ?? throw new InvalidOperationException("CAPABILITY_DOCUMENT_FIXTURE_INVALID");
    var capabilityEntries = capabilityDocument["capabilities"]?.AsObject()
        ?? throw new InvalidOperationException("CAPABILITY_DOCUMENT_SECTION_MISSING");
    RunCapabilityDocument.Apply(capabilityEntries, new CapabilitySettings(), readyCapabilities);
    Require(capabilityEntries["local_browser_runtime"]?["enabled"]?.GetValue<bool>() == true, "LOCAL_BROWSER_CAPABILITY_DOCUMENT_NOT_DERIVED");
    Require(capabilityEntries["server_browser_origin"]?["enabled"]?.GetValue<bool>() == true, "SERVER_BROWSER_ORIGIN_DOCUMENT_NOT_DERIVED");
    RunCapabilityDocument.Apply(capabilityEntries, new CapabilitySettings(), DerivedRunCapabilitySnapshot.Unavailable);
    Require(capabilityEntries["local_browser_runtime"]?["enabled"]?.GetValue<bool>() == false &&
            capabilityEntries["server_browser_origin"]?["enabled"]?.GetValue<bool>() == false,
        "UNAVAILABLE_BROWSER_CAPABILITIES_NOT_WRITTEN_FAIL_CLOSED");

    var catalogService = new CatalogService(repositoryPaths);
    var reportService = new RunReportService(repositoryPaths, paths, catalogService);
    var productDetail = await reportService.GetScenarioAsync("mock-ui-preview", "udp-ipv4-connected-proxy", CancellationToken.None)
        ?? throw new InvalidOperationException("FIXTURE_RESULT_DETAIL_MISSING");
    Require(productDetail.Explanation.Category == "PRODUCT", "PRODUCT_EXPLANATION_CATEGORY_INVALID");
    Require(productDetail.Explanation.ProductErrors.Contains("fail:udp_response_source"), "PRODUCT_ERROR_SEPARATION_INVALID");
    Require(productDetail.Explanation.HarnessErrors.Count == 0, "HARNESS_ERROR_FALSE_POSITIVE");
    Require(productDetail.Explanation.Expected.Contains("PROXY", StringComparison.Ordinal), "EXPECTED_VIEW_MISSING_ACTION");
    Require(productDetail.Explanation.Timeline.Count == 8, "ASSERTION_TIMELINE_INCOMPLETE");
    var passDetail = await reportService.GetScenarioAsync("mock-ui-preview", "tcp-ipv4-direct", CancellationToken.None);
    Require(passDetail?.Explanation.Category == "PASS", "PASS_EXPLANATION_INVALID");

    var audit = await reportService.CreateAuditExportAsync("mock-ui-preview", CancellationToken.None)
        ?? throw new InvalidOperationException("SANITIZED_AUDIT_EXPORT_MISSING");
    Require(audit.Content.Length > 0, "SANITIZED_AUDIT_EXPORT_EMPTY");
    using (var memory = new MemoryStream(audit.Content))
    using (var archive = new ZipArchive(memory, ZipArchiveMode.Read))
    {
        var names = archive.Entries.Select(entry => entry.FullName).ToArray();
        Require(names.Contains("CODEX_AUDIT_REPORT.md") && names.Contains("MANIFEST.json") && names.Contains("SHA256SUMS.txt"), "AUDIT_CONTROL_FILES_MISSING");
        Require(names.All(name => !name.Contains(".env", StringComparison.OrdinalIgnoreCase) && !name.Contains("pbprofile", StringComparison.OrdinalIgnoreCase) && !name.Contains("transcript", StringComparison.OrdinalIgnoreCase) && !name.Contains("generated-profiles", StringComparison.OrdinalIgnoreCase)), "PRIVATE_ARTIFACT_EXPORTED");
        Require(names.Any(name => name.EndsWith("assertion-result.json", StringComparison.Ordinal)), "SANITIZED_ASSERTION_NOT_EXPORTED");
    }
}
finally
{
    await coordinator.StopAsync(CancellationToken.None);
    coordinator.Dispose();
}

Console.WriteLine("PASS: offline safe run orchestration");

static async Task<RunJobView> QueueRealAsync(RunCoordinator coordinator, IReadOnlyList<string> scenarios)
{
    var preparation = await coordinator.PrepareAsync(new RunCreateRequest("real", scenarios), CancellationToken.None);
    Require(preparation.CanStart && !string.IsNullOrWhiteSpace(preparation.ConfirmationNonce), "REAL_PREPARATION_FAILED");
    return await coordinator.QueueAsync(new RunCreateRequest("real", scenarios, preparation.ConfirmationNonce), CancellationToken.None);
}

static async Task<RunJobView> WaitTerminalAsync(RunCoordinator coordinator, string runId)
{
    for (var attempt = 0; attempt < 240; attempt++)
    {
        var job = coordinator.Get(runId) ?? throw new InvalidOperationException("JOB_DISAPPEARED");
        if (job.Terminal) return job;
        await Task.Delay(25);
    }
    throw new InvalidOperationException("JOB_TERMINAL_TIMEOUT");
}

static async Task WaitStateAsync(RunCoordinator coordinator, string runId, string state)
{
    for (var attempt = 0; attempt < 160; attempt++)
    {
        if (coordinator.Get(runId)?.State == state) return;
        await Task.Delay(25);
    }
    throw new InvalidOperationException("JOB_STATE_TIMEOUT");
}

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

static CatalogScenario Scenario(string id, IReadOnlyList<string> requires) => new(
    id, id, true, "EXECUTABLE", "Fixture executable.", "fixture", "native", "", "", "TCP", 4,
    "DIRECT", "connected", true, "none", null, [], requires, []);

sealed class FakeReadiness(RunConfirmationService confirmations) : IRunReadinessService
{
    public Task<RunPreparationView> PrepareAsync(RunCreateRequest request, bool realRunActive, CancellationToken cancellationToken)
    {
        var mode = request.Mode.Trim().ToLowerInvariant();
        var scenarios = request.ScenarioIds.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        string? nonce = null;
        DateTimeOffset? expires = null;
        if (mode == "real") (nonce, expires) = confirmations.Issue(mode, scenarios);
        return Task.FromResult(new RunPreparationView(
            mode, scenarios, scenarios.Length, scenarios.Length > 0,
            [new("fixture", "Fixture readiness", true, "READY", "Offline fake readiness passed.")], nonce, expires, []));
    }
}

sealed class FakeExecutor : IRunExecutor
{
    private int _activeReal;
    public int MaxConcurrentReal { get; private set; }

    public async Task<RunExecutionResult> ExecuteAsync(RunExecutionContext context, Func<RunExecutionProgress, Task> progress, CancellationToken cancellationToken)
    {
        if (context.Mode == "real")
        {
            var active = Interlocked.Increment(ref _activeReal);
            MaxConcurrentReal = Math.Max(MaxConcurrentReal, active);
        }
        try
        {
            if (context.ScenarioIds.Contains("recover-once") && context.Attempt == 0)
                return new(false, null, false, false, true, "Fixture start failure before evidence.");
            if (context.ScenarioIds.Contains("cancel-me"))
            {
                while (!cancellationToken.IsCancellationRequested) await Task.Delay(20);
                await progress(new("CANCELLING", "cancel-me", [], "Fixture cooperative cleanup."));
                return new(false, null, true, false, false, "Fixture cancellation observed after cleanup.");
            }

            var values = new List<RunScenarioProgress>();
            foreach (var id in context.ScenarioIds)
            {
                var status = id.Contains("product-fail", StringComparison.Ordinal) ? "FAIL_PRODUCT" : "PASS";
                values.Add(new(id, "EXECUTED", status, status == "PASS" ? "Fixture passed." : "Fixture product contradiction.", 1));
                await progress(new("RUNNING", id, values.ToArray(), "Fixture progress."));
                await Task.Delay(30);
            }
            return new(true, null, false, false, false, "Fixture execution complete.");
        }
        finally
        {
            if (context.Mode == "real") Interlocked.Decrement(ref _activeReal);
        }
    }
}

sealed class FakePublisher : IRunEventPublisher
{
    public List<RunJobView> Events { get; } = [];
    public Task PublishAsync(RunJobView job, CancellationToken cancellationToken)
    {
        lock (Events) Events.Add(job);
        return Task.CompletedTask;
    }
}
