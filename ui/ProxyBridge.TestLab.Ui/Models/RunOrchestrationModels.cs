using System.Text.Json.Serialization;

namespace ProxyBridge.TestLab.Ui.Models;

public sealed record RunCreateRequest(
    [property: JsonPropertyName("mode")] string Mode,
    [property: JsonPropertyName("scenario_ids")] IReadOnlyList<string> ScenarioIds,
    [property: JsonPropertyName("confirmation_nonce")] string? ConfirmationNonce = null);

public sealed record RunReadinessGate(
    string Id,
    string Label,
    bool Passed,
    string Status,
    string Detail,
    string? Remediation = null);

public sealed record RunPreparationView(
    string Mode,
    IReadOnlyList<string> ScenarioIds,
    int SelectedCount,
    bool CanStart,
    IReadOnlyList<RunReadinessGate> Gates,
    string? ConfirmationNonce,
    DateTimeOffset? ConfirmationExpiresUtc,
    IReadOnlyList<string> Warnings);

public sealed record RunStateTransition(string State, DateTimeOffset TimestampUtc, string Detail);

public sealed record RunScenarioProgress(
    string ScenarioId,
    string ExecutionDisposition,
    string? Status,
    string Detail,
    long? DurationMs = null);

public sealed record RunJobView(
    string RunId,
    string Mode,
    string State,
    IReadOnlyList<string> ScenarioIds,
    int SelectedCount,
    int CompletedCount,
    string? CurrentScenarioId,
    string CurrentPhase,
    int RecoveryAttempts,
    bool CancellationRequested,
    bool Terminal,
    string? TerminalReason,
    string? EvidenceRunId,
    DateTimeOffset CreatedUtc,
    DateTimeOffset UpdatedUtc,
    IReadOnlyList<RunStateTransition> Transitions,
    IReadOnlyList<RunScenarioProgress> Scenarios);

public sealed record RunExecutionProgress(
    string Phase,
    string? CurrentScenarioId,
    IReadOnlyList<RunScenarioProgress> Scenarios,
    string Detail);

public sealed record RunExecutionResult(
    bool EvidenceComplete,
    string? EvidenceRunId,
    bool CancellationObserved,
    bool SafetyStopped,
    bool RecoverableStartFailure,
    string Detail);
