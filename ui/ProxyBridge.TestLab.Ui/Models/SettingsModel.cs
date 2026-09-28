using System.Text.Json.Serialization;

namespace ProxyBridge.TestLab.Ui.Models;

public sealed class PublicSettings
{
    [JsonPropertyName("local_product")]
    public LocalProductSettings LocalProduct { get; set; } = new();

    [JsonPropertyName("proxy")]
    public ProxySettings Proxy { get; set; } = new();

    [JsonPropertyName("server_connection")]
    public ServerConnectionSettings ServerConnection { get; set; } = new();

    [JsonPropertyName("server_endpoint")]
    public ServerEndpointSettings ServerEndpoint { get; set; } = new();

    [JsonPropertyName("capabilities")]
    public CapabilitySettings Capabilities { get; set; } = new();

    [JsonPropertyName("timeouts")]
    public TimeoutSettings Timeouts { get; set; } = new();

    [JsonPropertyName("retention")]
    public RetentionSettings Retention { get; set; } = new();

    [JsonPropertyName("ui")]
    public UiSettings Ui { get; set; } = new();
}

public sealed class LocalProductSettings
{
    [JsonPropertyName("service_name")] public string ServiceName { get; set; } = "ProxyBridgeDrv";
}

public sealed class ProxySettings
{
    [JsonPropertyName("port")] public int Port { get; set; } = 10808;
    [JsonPropertyName("config_id")] public int ConfigId { get; set; } = 1;
}

public sealed class ServerConnectionSettings
{
    [JsonPropertyName("username")] public string Username { get; set; } = "";
    [JsonPropertyName("ssh_port")] public int SshPort { get; set; } = 22;
}

public sealed class ServerEndpointSettings
{
    [JsonPropertyName("port_a")] public int PortA { get; set; } = 41001;
    [JsonPropertyName("port_b")] public int PortB { get; set; } = 41002;
}

public sealed class CapabilitySettings
{
    [JsonPropertyName("ipv4")] public bool Ipv4 { get; set; } = true;
    [JsonPropertyName("ipv6")] public bool Ipv6 { get; set; }
    [JsonPropertyName("tcp")] public bool Tcp { get; set; } = true;
    [JsonPropertyName("udp")] public bool Udp { get; set; } = true;
    [JsonPropertyName("connected_udp")] public bool ConnectedUdp { get; set; } = true;
    [JsonPropertyName("unconnected_udp")] public bool UnconnectedUdp { get; set; } = true;
    [JsonPropertyName("socks5")] public bool Socks5 { get; set; } = true;
}

public sealed class TimeoutSettings
{
    [JsonPropertyName("operation_timeout_ms")] public int OperationTimeoutMs { get; set; } = 5000;
    [JsonPropertyName("cli_actual_path_timeout_ms")] public int CliActualPathTimeoutMs { get; set; } = 2000;
    [JsonPropertyName("client_process_exit_grace_ms")] public int ClientProcessExitGraceMs { get; set; } = 2000;
}

public sealed class RetentionSettings
{
    [JsonPropertyName("days")] public int Days { get; set; } = 30;
    [JsonPropertyName("max_runs")] public int MaxRuns { get; set; } = 100;
}

public sealed class UiSettings
{
    [JsonPropertyName("theme")] public string Theme { get; set; } = "dark";
}

public sealed class SettingsDocument
{
    [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } = 1;
    [JsonPropertyName("snapshot_id")] public string SnapshotId { get; set; } = "";
    [JsonPropertyName("settings")] public PublicSettings Settings { get; set; } = new();
}

public sealed class SettingsUpdateRequest
{
    [JsonPropertyName("settings")] public PublicSettings Settings { get; set; } = new();
    [JsonPropertyName("protected_values")] public Dictionary<string, string?> ProtectedValues { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    [JsonPropertyName("clear_protected")] public List<string> ClearProtected { get; set; } = [];
}

public sealed record SettingsFieldDefinition(
    string Id,
    string Section,
    string Name,
    string Label,
    string Type,
    bool Sensitive,
    bool Required,
    string Description,
    [property: JsonIgnore] string? EnvironmentKey = null,
    int? Minimum = null,
    int? Maximum = null);

public sealed record SettingsSectionDefinition(string Id, string Title, string Description);

public sealed record SettingsSchemaDocument(
    int SchemaVersion,
    IReadOnlyList<SettingsSectionDefinition> Sections,
    IReadOnlyList<SettingsFieldDefinition> Fields);

public sealed record FieldIssue(string Field, string Code, string Message);

public sealed record SettingsValidationResult(
    bool ValidForSave,
    bool Ready,
    IReadOnlyList<FieldIssue> InvalidFields,
    IReadOnlyList<FieldIssue> ReadinessIssues,
    IReadOnlyList<FieldIssue> Warnings);

public sealed record SettingsView(
    int SchemaVersion,
    PublicSettings Settings,
    IReadOnlyDictionary<string, bool> ProtectedPresence,
    SettingsValidationResult Validation,
    DateTimeOffset? UpdatedUtc);

public sealed record SettingsSnapshot(
    PublicSettings Settings,
    IReadOnlyDictionary<string, string> ProtectedValues,
    SettingsValidationResult Validation,
    DateTimeOffset? UpdatedUtc);
