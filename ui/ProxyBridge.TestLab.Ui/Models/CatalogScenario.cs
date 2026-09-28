using System.Text.Json.Serialization;

namespace ProxyBridge.TestLab.Ui.Models;

public sealed record KnownDefectView(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("policy")] string Policy,
    [property: JsonPropertyName("expected_status")] string ExpectedStatus,
    [property: JsonPropertyName("reason")] string Reason);

public sealed record CatalogScenario(
    [property: JsonPropertyName("scenario_id")] string ScenarioId,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("enabled")] bool Enabled,
    [property: JsonPropertyName("implementation_status")] string ImplementationStatus,
    [property: JsonPropertyName("implementation_reason")] string ImplementationReason,
    [property: JsonPropertyName("coverage_group")] string CoverageGroup,
    [property: JsonPropertyName("executor_kind")] string ExecutorKind,
    [property: JsonPropertyName("protocol_family")] string ProtocolFamily,
    [property: JsonPropertyName("evidence_profile_id")] string EvidenceProfileId,
    [property: JsonPropertyName("protocol")] string Protocol,
    [property: JsonPropertyName("family")] int Family,
    [property: JsonPropertyName("action")] string Action,
    [property: JsonPropertyName("socket_mode")] string SocketMode,
    [property: JsonPropertyName("independent")] bool Independent,
    [property: JsonPropertyName("reset_policy")] string ResetPolicy,
    [property: JsonPropertyName("known_defect")] KnownDefectView? KnownDefect,
    [property: JsonPropertyName("tags")] IReadOnlyList<string> Tags,
    [property: JsonPropertyName("requires")] IReadOnlyList<string> Requires,
    [property: JsonPropertyName("assertions")] IReadOnlyList<string> Assertions);
