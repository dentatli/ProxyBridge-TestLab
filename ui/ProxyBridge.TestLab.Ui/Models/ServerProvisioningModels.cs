using System.Text.Json.Serialization;

namespace ProxyBridge.TestLab.Ui.Models;

public sealed record ServerValidationRequest(
    [property: JsonPropertyName("trust_token")] string? TrustToken = null,
    [property: JsonPropertyName("confirm_host_trust")] bool ConfirmHostTrust = false,
    [property: JsonPropertyName("replace_changed_host_key")] bool ReplaceChangedHostKey = false);

public sealed record ServerApplyRequest(
    [property: JsonPropertyName("plan_id")] string PlanId,
    [property: JsonPropertyName("confirmed")] bool Confirmed);

public sealed record ServerStatusView(
    string State,
    string Message,
    bool ConfigurationComplete,
    bool HostTrusted,
    bool ReceiptCurrent,
    DateTimeOffset? LastVerifiedUtc,
    DateTimeOffset? ReceiptExpiresUtc,
    IReadOnlyList<string> Remediation);

public sealed record ServerValidationView(
    string State,
    string Message,
    IReadOnlyList<string> Fingerprints,
    string? TrustToken,
    bool HostKeyChanged,
    ServerDiscoveryView? Discovery,
    IReadOnlyList<string> Remediation);

public sealed record ServerDiscoveryView(
    string OperatingSystem,
    string Version,
    string Architecture,
    bool Systemd,
    bool NonInteractiveSudo,
    bool Python3,
    string PythonVersion,
    bool PythonCompatible,
    long AvailableDiskKb,
    string ServiceState,
    string FirewallAdapter,
    bool DirectEgressObserved,
    bool ProtocolPluginsReady,
    int ProtocolPluginCount,
    IReadOnlyList<int> ConflictingTcpPorts,
    IReadOnlyList<int> ConflictingUdpPorts);

public sealed record ServerPlanStep(
    int Order,
    string Operation,
    string Description,
    bool MutatesServer,
    string Rollback);

public sealed record ServerPlanView(
    string PlanId,
    DateTimeOffset CreatedUtc,
    DateTimeOffset ExpiresUtc,
    string State,
    string Target,
    IReadOnlyList<string> Packages,
    IReadOnlyList<string> Paths,
    IReadOnlyList<int> TcpPorts,
    IReadOnlyList<int> UdpPorts,
    IReadOnlyDictionary<string, string> ArtifactSha256,
    string ArtifactBundleId,
    IReadOnlyList<string> ProtocolPlugins,
    IReadOnlyList<string> Commands,
    IReadOnlyList<ServerPlanStep> Steps,
    IReadOnlyList<string> Warnings);

public sealed record ServerApplyView(
    string State,
    string Message,
    bool Applied,
    bool RollbackAttempted,
    bool RollbackSucceeded,
    DateTimeOffset? VerifiedUtc,
    DateTimeOffset? ReceiptExpiresUtc);

public sealed record ServerMetricsView(
    string State,
    string ServiceState,
    string ServiceSubstate,
    long MainPid,
    long RestartCount,
    long MemoryBytes,
    long CpuUsageNanoseconds,
    long EvidenceBytes,
    long EvidenceRecords,
    long EndpointErrors,
    long AvailableDiskKb,
    IReadOnlyList<string> RecentSanitizedMessages,
    DateTimeOffset CollectedUtc);

public sealed record ServerProtocolSmokeScenarioView(
    string ScenarioId,
    string Status,
    int ClientRecords,
    int ServerRecords,
    bool IdentitiesMatched,
    bool PayloadHashMatched);

public sealed record ServerProtocolSmokeView(
    string State,
    string Message,
    int ScenarioCount,
    int Passed,
    int Failed,
    IReadOnlyList<ServerProtocolSmokeScenarioView> Results);
