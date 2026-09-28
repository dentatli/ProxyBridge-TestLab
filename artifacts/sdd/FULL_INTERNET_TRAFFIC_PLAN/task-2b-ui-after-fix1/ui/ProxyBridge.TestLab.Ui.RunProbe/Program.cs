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
    var spoofedBrowser = LocalArtifactService.DiscoverBrowserFromAllowlistedCandidates([browserCandidate]);
    Require(!spoofedBrowser.Ready && spoofedBrowser.Status == "NOT_FOUND", "RENAMED_NON_BROWSER_IMAGE_WAS_ACCEPTED");
    var discoveredBrowser = LocalArtifactService.DiscoverBrowserFromAllowlistedCandidates(
        [browserCandidate],
        _ => new BrowserFileVersionIdentity("Microsoft Edge", "msedge.exe", "123.0.0.0"));
    Require(discoveredBrowser.Ready && discoveredBrowser.Status == "READY", "AUTOMATIC_BROWSER_DISCOVERY_FAILED");
    Require(discoveredBrowser.ExecutablePath == Path.GetFullPath(browserCandidate), "AUTOMATIC_BROWSER_PATH_NOT_NORMALIZED");
    Require(discoveredBrowser.BrowserIdentity == "Microsoft Edge", "AUTOMATIC_BROWSER_IDENTITY_INVALID");
    Require(discoveredBrowser.Sha256 is { Length: 64 }, "AUTOMATIC_BROWSER_HASH_MISSING");
    var missingBrowser = LocalArtifactService.DiscoverBrowserFromAllowlistedCandidates([Path.Combine(browserFixtureRoot, "missing", "chrome.exe")]);
    Require(!missingBrowser.Ready && missingBrowser.Status == "NOT_FOUND" && missingBrowser.ExecutablePath is null, "MISSING_BROWSER_NOT_GATED");
    var readyServer = new ServerStatusView("READY", "Ready fixture.", true, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddMinutes(5), []);
    var staleServer = readyServer with { State = "STALE", Message = "Stale fixture." };
    var readyCapabilities = DerivedRunCapabilitySnapshot.Derive(discoveredBrowser, readyServer);
    Require(readyCapabilities.LocalBrowserRuntime && readyCapabilities.ServerReady && readyCapabilities.ServerBrowserOrigin, "DERIVED_BROWSER_CAPABILITIES_NOT_ENABLED");
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

    var nonBrowserScenario = Scenario("native-tcp", ["ipv4", "tcp"]);
    var nonBrowserGates = RunCapabilityReadiness.Create("real", [nonBrowserScenario], DerivedRunCapabilitySnapshot.Unavailable);
    Require(nonBrowserGates.All(gate => gate.Passed), "NON_BROWSER_SELECTION_WAS_CAPABILITY_BLOCKED");
    Require(RunCapabilityReadiness.Create("mock", [browserScenario], DerivedRunCapabilitySnapshot.Unavailable).Count == 0, "FIXTURE_MODE_WAS_BROWSER_CAPABILITY_GATED");

    var readySettings = new SettingsView(
        1,
        new PublicSettings(),
        new Dictionary<string, bool>(),
        new SettingsValidationResult(true, true, [], [], []),
        null);
    var separatedServerCapabilities = new DerivedRunCapabilitySnapshot(false, true, false, "NOT_FOUND", "READY");
    var integratedReadiness = new RunReadinessService(
        new StubRunCatalog([nonBrowserScenario, browserScenario]),
        new StubRunSettings(readySettings),
        new StubLocalRuntimeStatus(new LocalProtocolRuntimeStatus(true, "READY", "Fixture protocol runtime.")),
        new StubRuntimeCapabilities(separatedServerCapabilities),
        new StubImmutablePreflight(new ImmutablePreflightResult(true, "READY", "Fixture preflight.", DateTimeOffset.UtcNow.AddMinutes(1), false)),
        confirmations);
    var nonBrowserPreparation = await integratedReadiness.PrepareAsync(
        new RunCreateRequest("real", [nonBrowserScenario.ScenarioId]), false, CancellationToken.None);
    Require(nonBrowserPreparation.CanStart, "NON_BROWSER_REAL_SELECTION_DID_NOT_START_WITH_GENERIC_SERVER_READY");
    Require(nonBrowserPreparation.Gates.Single(gate => gate.Id == "server").Passed, "GENERIC_SERVER_GATE_DID_NOT_USE_SERVER_READY");
    Require(nonBrowserPreparation.Gates.Single(gate => gate.Id == "server_browser_origin").Passed, "NON_BROWSER_SELECTION_WAS_INDEPENDENTLY_ORIGIN_BLOCKED");
    var browserPreparation = await integratedReadiness.PrepareAsync(
        new RunCreateRequest("real", [browserScenario.ScenarioId]), false, CancellationToken.None);
    Require(!browserPreparation.CanStart &&
            !browserPreparation.Gates.Single(gate => gate.Id == "local_browser_runtime").Passed &&
            !browserPreparation.Gates.Single(gate => gate.Id == "server_browser_origin").Passed,
        "BROWSER_REQUIREMENTS_DID_NOT_BLOCK_INTEGRATED_READINESS");

    var mockSettings = new StubRunSettings(readySettings);
    var mockLocalRuntime = new StubLocalRuntimeStatus(new LocalProtocolRuntimeStatus(false, "MISSING", "Unavailable fixture dependency."));
    var mockRuntimeCapabilities = new StubRuntimeCapabilities(DerivedRunCapabilitySnapshot.Unavailable);
    var mockPreflight = new StubImmutablePreflight(new ImmutablePreflightResult(false, "FAILED", "Must not be called.", null, false));
    var mockReadiness = new RunReadinessService(
        new StubRunCatalog([browserScenario]), mockSettings, mockLocalRuntime, mockRuntimeCapabilities, mockPreflight, confirmations);
    var mockPreparation = await mockReadiness.PrepareAsync(
        new RunCreateRequest("mock", [browserScenario.ScenarioId]), false, CancellationToken.None);
    Require(mockPreparation.CanStart, "BROWSER_FIXTURE_PREVIEW_WAS_READINESS_BLOCKED");
    Require(mockSettings.Calls == 0 && mockLocalRuntime.Calls == 0 && mockRuntimeCapabilities.Calls == 0 && mockPreflight.Calls == 0,
        "BROWSER_FIXTURE_PREVIEW_TOUCHED_REAL_RUNTIME_READINESS");

    var repositoryPaths = new AppPaths(AppPaths.Discover(null));
    var capabilityDocument = JsonNode.Parse(await File.ReadAllTextAsync(repositoryPaths.CapabilitiesPath))?.AsObject()
        ?? throw new InvalidOperationException("CAPABILITY_DOCUMENT_FIXTURE_INVALID");
    var capabilityEntries = capabilityDocument["capabilities"]?.AsObject()
        ?? throw new InvalidOperationException("CAPABILITY_DOCUMENT_SECTION_MISSING");
    RunCapabilityDocument.Apply(capabilityEntries, new CapabilitySettings(), readyCapabilities);
    Require(capabilityEntries["local_browser_runtime"]?["enabled"]?.GetValue<bool>() == true, "LOCAL_BROWSER_CAPABILITY_DOCUMENT_NOT_DERIVED");
    Require(capabilityEntries["server_browser_origin"]?["enabled"]?.GetValue<bool>() == true, "SERVER_BROWSER_ORIGIN_DOCUMENT_NOT_DERIVED");
    var fixtureCapabilitiesPath = Path.Combine(root, "fixture-capabilities.json");
    var fixtureCapabilitySource = new StubRuntimeCapabilities(DerivedRunCapabilitySnapshot.Unavailable);
    var capabilityFiles = new RunCapabilityFileService(repositoryPaths, fixtureCapabilitySource);
    await capabilityFiles.WriteForExecutionAsync("mock", new CapabilitySettings(), fixtureCapabilitiesPath, CancellationToken.None);
    var fixtureCapabilityDocument = JsonNode.Parse(await File.ReadAllTextAsync(fixtureCapabilitiesPath))?.AsObject()
        ?? throw new InvalidOperationException("FIXTURE_CAPABILITY_DOCUMENT_INVALID");
    var fixtureCapabilityEntries = fixtureCapabilityDocument["capabilities"]?.AsObject()
        ?? throw new InvalidOperationException("FIXTURE_CAPABILITY_SECTION_MISSING");
    Require(fixtureCapabilityEntries["local_browser_runtime"]?["enabled"]?.GetValue<bool>() == true &&
            fixtureCapabilityEntries["server_browser_origin"]?["enabled"]?.GetValue<bool>() == true,
        "BROWSER_FIXTURE_EXECUTION_CAPABILITIES_DISABLED");
    Require(fixtureCapabilitySource.Calls == 0, "FIXTURE_CAPABILITY_FILE_QUERIED_REAL_RUNTIME_STATE");

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

sealed class StubRunCatalog(IReadOnlyList<CatalogScenario> scenarios) : IRunCatalogProvider
{
    public Task<IReadOnlyList<CatalogScenario>> GetAllAsync(CancellationToken cancellationToken) => Task.FromResult(scenarios);
}

sealed class StubRunSettings(SettingsView view) : IRunSettingsProvider
{
    public int Calls { get; private set; }
    public Task<SettingsView> GetViewAsync(CancellationToken cancellationToken)
    {
        Calls++;
        return Task.FromResult(view);
    }
}

sealed class StubLocalRuntimeStatus(LocalProtocolRuntimeStatus status) : ILocalRuntimeStatusProvider
{
    public int Calls { get; private set; }
    public LocalProtocolRuntimeStatus GetProtocolRuntimeStatus()
    {
        Calls++;
        return status;
    }
}

sealed class StubRuntimeCapabilities(DerivedRunCapabilitySnapshot snapshot) : IRuntimeCapabilityService
{
    public int Calls { get; private set; }
    public Task<DerivedRunCapabilitySnapshot> GetAsync(CancellationToken cancellationToken)
    {
        Calls++;
        return Task.FromResult(snapshot);
    }
}

sealed class StubImmutablePreflight(ImmutablePreflightResult result) : IRunImmutablePreflightService
{
    public int Calls { get; private set; }
    public Task<ImmutablePreflightResult> VerifyAsync(
        IReadOnlyList<string> scenarioIds,
        bool executeIfNeeded,
        DerivedRunCapabilitySnapshot derivedCapabilities,
        CancellationToken cancellationToken)
    {
        Calls++;
        return Task.FromResult(result);
    }
}
