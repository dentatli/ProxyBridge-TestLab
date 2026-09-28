using System.Text.Json.Nodes;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record DerivedRunCapabilitySnapshot(
    bool LocalBrowserRuntime,
    bool ServerBrowserOrigin,
    string LocalBrowserStatus,
    string ServerBrowserOriginStatus)
{
    public static DerivedRunCapabilitySnapshot Unavailable { get; } =
        new(false, false, "NOT_EVALUATED", "NOT_EVALUATED");

    public static DerivedRunCapabilitySnapshot Derive(
        LocalBrowserRuntimeStatus browser,
        ServerStatusView server)
    {
        ArgumentNullException.ThrowIfNull(browser);
        ArgumentNullException.ThrowIfNull(server);
        var browserReady = IsVerifiedAllowlistedBrowser(browser);
        var originReady = string.Equals(server.State, "READY", StringComparison.Ordinal);
        return new(
            browserReady,
            originReady,
            browserReady ? "READY" : browser.Status,
            originReady ? "READY" : server.State);
    }

    private static bool IsVerifiedAllowlistedBrowser(LocalBrowserRuntimeStatus browser)
    {
        if (!browser.Ready || !string.Equals(browser.Status, "READY", StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(browser.ExecutablePath) || string.IsNullOrWhiteSpace(browser.BrowserIdentity) ||
            string.IsNullOrWhiteSpace(browser.Version) || browser.Sha256 is not { Length: 64 } ||
            browser.Sha256.Any(character => !Uri.IsHexDigit(character))) return false;

        var expectedIdentity = Path.GetFileName(browser.ExecutablePath).ToLowerInvariant() switch
        {
            "msedge.exe" => "Microsoft Edge",
            "chrome.exe" => "Google Chrome",
            "chromium.exe" => "Chromium",
            _ => null
        };
        return string.Equals(browser.BrowserIdentity, expectedIdentity, StringComparison.Ordinal);
    }
}

public sealed class RuntimeCapabilityService(
    LocalArtifactService localArtifacts,
    ServerProvisioningService serverProvisioning)
{
    public async Task<DerivedRunCapabilitySnapshot> GetAsync(CancellationToken cancellationToken)
    {
        var browser = localArtifacts.GetBrowserRuntimeStatus();
        var server = await serverProvisioning.GetStatusAsync(cancellationToken);
        return DerivedRunCapabilitySnapshot.Derive(browser, server);
    }
}

public static class RunCapabilityReadiness
{
    public static IReadOnlyList<RunReadinessGate> Create(
        string mode,
        IReadOnlyList<CatalogScenario> selected,
        DerivedRunCapabilitySnapshot capabilities)
    {
        if (!string.Equals(mode, "real", StringComparison.OrdinalIgnoreCase)) return [];

        var needsBrowser = Requires(selected, "local_browser_runtime");
        var browserReady = !needsBrowser || capabilities.LocalBrowserRuntime;
        var needsOrigin = Requires(selected, "server_browser_origin");
        var originReady = !needsOrigin || capabilities.ServerBrowserOrigin;
        return
        [
            new RunReadinessGate(
                "local_browser_runtime",
                "Local browser runtime",
                browserReady,
                browserReady ? "READY" : "BLOCKED",
                !needsBrowser
                    ? "The selected tests do not require a local browser runtime."
                    : capabilities.LocalBrowserRuntime
                        ? "A supported browser image, version and integrity hash were verified automatically."
                        : "The selected tests require a verified Microsoft Edge, Google Chrome, or Chromium runtime.",
                browserReady ? null : "Install or repair a supported browser, then review this selection again."),
            new RunReadinessGate(
                "server_browser_origin",
                "Controlled browser origin",
                originReady,
                originReady ? "READY" : "BLOCKED",
                !needsOrigin
                    ? "The selected tests do not require the controlled browser origin."
                    : capabilities.ServerBrowserOrigin
                        ? "Server Setup currently reports the controlled browser origin ready."
                        : "The selected tests require the controlled browser origin, but Server Setup is not currently ready.",
                originReady ? null : "Open Server Setup and validate or provision the controlled browser origin."),
        ];
    }

    private static bool Requires(IEnumerable<CatalogScenario> selected, string capability) =>
        selected.Any(scenario => scenario.Requires.Contains(capability, StringComparer.OrdinalIgnoreCase));
}

public static class RunCapabilityDocument
{
    public static void Apply(
        JsonObject capabilities,
        CapabilitySettings settings,
        DerivedRunCapabilitySnapshot derived)
    {
        Set(capabilities, "ipv4", settings.Ipv4, "Disabled in Environment Setup");
        Set(capabilities, "ipv6", settings.Ipv6, "Disabled in Environment Setup");
        Set(capabilities, "tcp", settings.Tcp, "Disabled in Environment Setup");
        Set(capabilities, "udp", settings.Udp, "Disabled in Environment Setup");
        Set(capabilities, "connected_udp", settings.ConnectedUdp, "Disabled in Environment Setup");
        Set(capabilities, "unconnected_udp", settings.UnconnectedUdp, "Disabled in Environment Setup");
        Set(capabilities, "socks5", settings.Socks5, "Disabled in Environment Setup");
        Set(capabilities, "local_browser_runtime", derived.LocalBrowserRuntime,
            "No verified supported browser runtime is currently available.");
        Set(capabilities, "server_browser_origin", derived.ServerBrowserOrigin,
            "Server Setup does not currently report the controlled browser origin ready.");
    }

    private static void Set(JsonObject capabilities, string id, bool enabled, string disabledReason)
    {
        if (capabilities[id] is not JsonObject capability) return;
        capability["enabled"] = enabled;
        capability["reason"] = enabled ? "" : disabledReason;
    }
}
