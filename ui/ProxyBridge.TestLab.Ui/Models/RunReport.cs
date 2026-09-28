using System.Text.Json;
using System.Text.Json.Serialization;

namespace ProxyBridge.TestLab.Ui.Models;

public sealed record StatusCount(
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("count")] int Count,
    [property: JsonPropertyName("run_mode")] string RunMode);

public sealed record CatalogCounts(
    [property: JsonPropertyName("declared")] int Declared,
    [property: JsonPropertyName("executable")] int Executable,
    [property: JsonPropertyName("declarative")] int Declarative,
    [property: JsonPropertyName("unsupported")] int Unsupported,
    [property: JsonPropertyName("selected")] int Selected,
    [property: JsonPropertyName("dry_run_records")] int DryRunRecords,
    [property: JsonPropertyName("mock_records")] int MockRecords,
    [property: JsonPropertyName("real_records")] int RealRecords);

public sealed record RunSummaryDocument(
    [property: JsonPropertyName("schema_version")] int SchemaVersion,
    [property: JsonPropertyName("run_mode")] string RunMode,
    [property: JsonPropertyName("execution_complete")] bool ExecutionComplete,
    [property: JsonPropertyName("product_verdict")] string ProductVerdict,
    [property: JsonPropertyName("catalog")] CatalogCounts Catalog,
    [property: JsonPropertyName("statuses")] IReadOnlyList<StatusCount> Statuses,
    [property: JsonPropertyName("fixture")] bool Fixture = false);

public sealed record RunListItem(
    string RunId,
    string RunMode,
    bool ExecutionComplete,
    string ProductVerdict,
    CatalogCounts Catalog,
    IReadOnlyList<StatusCount> Statuses,
    bool Fixture,
    DateTimeOffset UpdatedUtc);

public sealed record ResultRecord(
    [property: JsonPropertyName("run_mode")] string RunMode,
    [property: JsonPropertyName("scenario_id")] string ScenarioId,
    [property: JsonPropertyName("coverage_group")] string CoverageGroup,
    [property: JsonPropertyName("implementation_status")] string ImplementationStatus,
    [property: JsonPropertyName("selected")] bool Selected,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("reason")] string Reason,
    [property: JsonPropertyName("attempt")] int Attempt,
    [property: JsonPropertyName("duration_ms")] long DurationMs,
    [property: JsonPropertyName("reset_policy")] string ResetPolicy);

public sealed record EvidenceChannelView(string Name, string State, string Detail, string? ArtifactId);

public sealed record AssertionTimelineEntry(int Order, string Step, string State, string Detail);

public sealed record ScenarioExplanationView(
    string Category,
    string Summary,
    string WhatWasTested,
    string Expected,
    string Observed,
    string Why,
    string NextAction,
    string EvidenceBasis,
    IReadOnlyList<string> ProductErrors,
    IReadOnlyList<string> HarnessErrors,
    IReadOnlyList<string> MissingEvidence,
    IReadOnlyList<string> Contamination,
    IReadOnlyList<EvidenceChannelView> Channels,
    IReadOnlyList<AssertionTimelineEntry> Timeline);

public sealed record ScenarioResultDetail(
    ResultRecord Result,
    IReadOnlyDictionary<string, JsonElement> Evidence,
    ScenarioExplanationView Explanation);

public sealed record RunAuditExport(byte[] Content, string FileName);
