using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public interface IRunReadinessService
{
    Task<RunPreparationView> PrepareAsync(RunCreateRequest request, bool realRunActive, CancellationToken cancellationToken);
}

public sealed class RunReadinessService(
    IRunCatalogProvider catalogService,
    IRunSettingsProvider settingsStore,
    ILocalRuntimeStatusProvider localArtifacts,
    IRuntimeCapabilityService runtimeCapabilities,
    IRunImmutablePreflightService immutablePreflight,
    RunConfirmationService confirmations) : IRunReadinessService
{
    private static readonly HashSet<string> AllowedModes = new(StringComparer.OrdinalIgnoreCase) { "mock", "real" };

    public async Task<RunPreparationView> PrepareAsync(
        RunCreateRequest request,
        bool realRunActive,
        CancellationToken cancellationToken)
    {
        var mode = (request.Mode ?? "").Trim().ToLowerInvariant();
        var warnings = new List<string>();
        var gates = new List<RunReadinessGate>();
        if (!AllowedModes.Contains(mode))
        {
            gates.Add(new("mode", "Execution mode", false, "BLOCKED", "The requested execution mode is not supported.", "Choose Fixture preview or Real traffic."));
            return new RunPreparationView(mode, [], 0, false, gates, null, null, warnings);
        }

        var requested = (request.ScenarioIds ?? [])
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var catalog = await catalogService.GetAllAsync(cancellationToken);
        var byId = catalog.ToDictionary(item => item.ScenarioId, StringComparer.OrdinalIgnoreCase);
        var unknown = requested.Where(id => !byId.ContainsKey(id)).ToArray();
        var selectionValid = requested.Length is > 0 and <= 200 && unknown.Length == 0;
        gates.Add(new(
            "selection",
            "Scenario selection",
            selectionValid,
            selectionValid ? "READY" : "BLOCKED",
            selectionValid ? $"{requested.Length} known scenario(s) selected." : "The selection is empty, too large, or contains unknown IDs.",
            selectionValid ? null : "Select between 1 and 200 catalog scenarios."));

        var selected = requested.Where(byId.ContainsKey).Select(id => byId[id]).ToArray();
        var disabled = selected.Where(item => !item.Enabled).Select(item => item.ScenarioId).ToArray();
        var unsupported = selected.Where(item => item.ImplementationStatus == "UNSUPPORTED_PRODUCT_SCOPE").Select(item => item.ScenarioId).ToArray();
        var nonExecutable = selected.Where(item => item.ImplementationStatus != "EXECUTABLE").Select(item => item.ScenarioId).ToArray();
        var contractReady = disabled.Length == 0 && unsupported.Length == 0 && nonExecutable.Length == 0;
        gates.Add(new(
            "contracts",
            "Evidence contracts",
            contractReady,
            contractReady ? "READY" : "BLOCKED",
            contractReady ? "Every selected test has a compatible runner contract." : "One or more selected tests cannot execute in this mode.",
            contractReady ? null : "Select executable traffic tests. System checks are enforced automatically; capability-gated and unsupported entries are inventory only."));

        if (mode == "mock")
        {
            gates.Add(new("isolation", "Fixture isolation", true, "READY", "Fixture evidence is evaluated by the runner without ProxyBridge, SSH, or network access."));
            warnings.Add("Fixture results validate TestLab orchestration only and never claim product coverage.");
            return new RunPreparationView(mode, requested, requested.Length, selectionValid && contractReady, gates, null, null, warnings);
        }

        var settings = await settingsStore.GetViewAsync(cancellationToken);
        gates.Add(new(
            "configuration",
            "Environment Setup",
            settings.Validation.Ready,
            settings.Validation.Ready ? "READY" : "BLOCKED",
            settings.Validation.Ready ? "Saved local configuration is complete." : "Required local or protected settings are incomplete.",
            settings.Validation.Ready ? null : "Complete Environment Setup in the UI."));

        var needsProtocolRuntime = selected.Any(item => item.ExecutorKind.Equals("protocol-worker", StringComparison.OrdinalIgnoreCase));
        var protocolRuntime = localArtifacts.GetProtocolRuntimeStatus();
        var protocolRuntimeReady = !needsProtocolRuntime || protocolRuntime.Ready;
        gates.Add(new(
            "protocol_runtime",
            "Protocol worker runtime",
            protocolRuntimeReady,
            protocolRuntimeReady ? "READY" : "BLOCKED",
            needsProtocolRuntime ? protocolRuntime.Detail : "The selected tests use only the native traffic client.",
            protocolRuntimeReady ? null : "Install or repair the packaged protocol worker runtime before starting these tests."));

        var derivedCapabilities = await runtimeCapabilities.GetAsync(cancellationToken);
        var capabilityGates = RunCapabilityReadiness.Create(mode, selected, derivedCapabilities);
        gates.AddRange(capabilityGates);
        var selectedCapabilitiesReady = capabilityGates.All(gate => gate.Passed);
        var serverReady = derivedCapabilities.ServerReady;
        gates.Add(new(
            "server",
            "Server Setup",
            serverReady,
            serverReady ? "READY" : "BLOCKED",
            serverReady ? "The configured endpoint is provisioned and currently verified." : "The configured endpoint is not currently ready.",
            serverReady ? null : "Open Server Setup and validate or provision the Debian/Ubuntu endpoint."));
        gates.Add(new(
            "exclusive_lease",
            "Exclusive real-run lease",
            !realRunActive,
            realRunActive ? "BLOCKED" : "READY",
            realRunActive ? "Another real run is active." : "No other real run owns the controller lease.",
            realRunActive ? "Wait for the current real run to finish or cancel it." : null));
        var prerequisiteReady = selectionValid && contractReady && settings.Validation.Ready && protocolRuntimeReady && selectedCapabilitiesReady && serverReady && !realRunActive;
        var preflight = prerequisiteReady
            ? await immutablePreflight.VerifyAsync(requested, string.IsNullOrWhiteSpace(request.ConfirmationNonce), derivedCapabilities, cancellationToken)
            : new ImmutablePreflightResult(false, "PREREQUISITES_REQUIRED", "Complete the preceding readiness gates before immutable preflight.", null, false);
        gates.Add(new(
            "immutable_preflight",
            "Fresh immutable preflight",
            preflight.Passed,
            preflight.Status,
            preflight.Detail,
            preflight.Passed ? null : "Review the exact real run again after correcting the reported readiness condition."));

        var canStart = prerequisiteReady && preflight.Passed;
        string? nonce = null;
        DateTimeOffset? expires = preflight.ExpiresUtc;
        if (canStart)
        {
            (nonce, var confirmationExpires) = confirmations.Issue(mode, requested);
            expires = expires is null || confirmationExpires < expires ? confirmationExpires : expires;
        }
        warnings.Add("Review performs bounded product-state, endpoint, proxy and direct-baseline checks. It does not execute a selected scenario.");
        return new RunPreparationView(mode, requested, requested.Length, canStart, gates, nonce, expires, warnings);
    }
}
