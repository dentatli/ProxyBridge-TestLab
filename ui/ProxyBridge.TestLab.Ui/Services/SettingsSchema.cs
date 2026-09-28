using System.Net;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public static partial class SettingsSchema
{
    public static readonly IReadOnlyList<SettingsSectionDefinition> Sections =
    [
        new("local_product", "Local ProxyBridge", "Standard installation paths are preconfigured and binary integrity is checked automatically."),
        new("proxy", "Proxy tests", "An existing SOCKS5 endpoint is required only to prove ProxyBridge PROXY routing."),
        new("server_connection", "Test server", "Private-key-only connection to the supported Debian or Ubuntu endpoint."),
        new("server_endpoint", "Test network", "Windows and server addresses. Listener ports and server evidence paths are managed automatically."),
        new("capabilities", "Test coverage", "Choose available address families and transports; unavailable scenarios are skipped, never reported as passed."),
        new("timeouts", "Timeouts", "Bounded operation and process lifecycle budgets."),
        new("retention", "Evidence retention", "Local evidence location and retention limits."),
        new("ui", "Interface", "Local presentation preferences.")
    ];

    public static readonly IReadOnlyList<SettingsFieldDefinition> Fields =
    [
        new("local_product.gui_path", "local_product", "gui_path", "ProxyBridge GUI path", "path", true, true, "Uses the standard Program Files path by default. Binary integrity is checked automatically.", "PB_PROXYBRIDGE_EXE"),
        new("local_product.cli_path", "local_product", "cli_path", "ProxyBridge CLI path", "path", true, true, "Uses the standard Program Files path by default. Binary integrity is checked automatically.", "PB_PROXYBRIDGE_CLI_EXE"),
        new("local_product.driver_path", "local_product", "driver_path", "Driver path", "path", true, true, "Uses the standard Windows drivers path by default. Binary integrity is checked automatically.", "PB_DRIVER_PATH"),
        new("local_product.service_name", "local_product", "service_name", "Driver service name", "text", false, true, "Exact Windows service name.", "PB_PROXYBRIDGE_SERVICE"),

        new("proxy.host", "proxy", "host", "SOCKS5 server", "host", true, true, "Host or IP of the existing SOCKS5 proxy used by PROXY tests.", "PB_SOCKS_HOST"),
        new("proxy.port", "proxy", "port", "SOCKS5 port", "port", false, true, "Existing SOCKS5 listener port. The default is 10808.", "PB_SOCKS_PORT", 1, 65535),
        new("proxy.config_id", "proxy", "config_id", "ProxyBridge proxy ID", "number", false, true, "ID written into generated test profiles. The default is 1.", "PB_SOCKS_PROXY_CONFIG_ID", 1, int.MaxValue),

        new("server_connection.host", "server_connection", "host", "Server host or IP", "host", true, true, "Routable Debian or Ubuntu test server.", "PB_SSH_HOST"),
        new("server_connection.username", "server_connection", "username", "SSH user", "text", false, true, "Private-key SSH account with non-interactive sudo. This is not stored as a secret.", "PB_SSH_USER"),
        new("server_connection.private_key_path", "server_connection", "private_key_path", "SSH private key path", "path", true, true, "Private key remains on this Windows account.", "PB_SSH_KEY"),
        new("server_connection.ssh_port", "server_connection", "ssh_port", "SSH port", "port", false, true, "SSH service port. The default is 22.", "PB_SSH_PORT", 1, 65535),

        new("server_endpoint.vm_ipv4", "server_endpoint", "vm_ipv4", "This Windows PC IPv4", "ipv4", true, true, "Source IPv4 used by this Windows tester to reach the Linux server.", "PB_VM_IPV4"),
        new("server_endpoint.vps_ipv4", "server_endpoint", "vps_ipv4", "Linux test server IPv4", "ipv4", true, true, "Automatically reuses the SSH host when it is an IPv4 address.", "PB_VPS_IPV4"),
        new("server_endpoint.vm_ipv6", "server_endpoint", "vm_ipv6", "Windows IPv6", "ipv6", true, false, "Required only when IPv6 capability is enabled.", "PB_VM_IPV6"),
        new("server_endpoint.vps_ipv6", "server_endpoint", "vps_ipv6", "Server IPv6", "ipv6", true, false, "Automatically reuses the SSH host when it is IPv6; required only when IPv6 is enabled.", "PB_VPS_IPV6"),
        new("server_endpoint.port_a", "server_endpoint", "port_a", "Managed listener port A", "port", false, true, "Automatic primary TCP/UDP endpoint port.", "PB_ENDPOINT_A_PORT", 1, 65535),
        new("server_endpoint.port_b", "server_endpoint", "port_b", "Managed listener port B", "port", false, true, "Automatic secondary TCP/UDP endpoint port.", "PB_ENDPOINT_B_PORT", 1, 65535),

        new("capabilities.ipv4", "capabilities", "ipv4", "IPv4", "boolean", false, false, "Enable IPv4 scenario selection."),
        new("capabilities.ipv6", "capabilities", "ipv6", "IPv6", "boolean", false, false, "Enable only after end-to-end IPv6 readiness."),
        new("capabilities.tcp", "capabilities", "tcp", "TCP", "boolean", false, false, "Enable TCP scenarios."),
        new("capabilities.udp", "capabilities", "udp", "UDP", "boolean", false, false, "Enable UDP scenarios."),
        new("capabilities.connected_udp", "capabilities", "connected_udp", "Connected UDP", "boolean", false, false, "Enable connected UDP scenarios."),
        new("capabilities.unconnected_udp", "capabilities", "unconnected_udp", "Unconnected UDP", "boolean", false, false, "Enable unconnected UDP scenarios."),
        new("capabilities.socks5", "capabilities", "socks5", "PROXY routing", "boolean", false, false, "Enable scenarios that require the configured SOCKS5 proxy."),

        new("timeouts.operation_timeout_ms", "timeouts", "operation_timeout_ms", "Operation timeout", "milliseconds", false, true, "Timeout passed to the traffic client.", null, 100, 600000),
        new("timeouts.cli_actual_path_timeout_ms", "timeouts", "cli_actual_path_timeout_ms", "CLI path probe timeout", "milliseconds", false, true, "Bounded MainModule path verification timeout.", null, 100, 60000),
        new("timeouts.client_process_exit_grace_ms", "timeouts", "client_process_exit_grace_ms", "Client exit grace", "milliseconds", false, true, "Additional process/log completion budget.", null, 1, 60000),

        new("retention.evidence_root", "retention", "evidence_root", "Evidence root", "path", true, true, "Private local directory for sanitized run evidence.", "PB_EVIDENCE_ROOT"),
        new("retention.days", "retention", "days", "Retention days", "number", false, true, "Requested evidence retention age.", null, 1, 3650),
        new("retention.max_runs", "retention", "max_runs", "Maximum runs", "number", false, true, "Requested retained-run count.", null, 1, 10000),
        new("ui.theme", "ui", "theme", "Theme", "choice", false, true, "Local interface theme.")
    ];

    public static SettingsSchemaDocument Document { get; } = new(1, Sections, Fields);
    public static IReadOnlySet<string> ProtectedFieldIds { get; } = Fields.Where(field => field.Sensitive).Select(field => field.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);

    public static SettingsValidationResult Validate(PublicSettings settings, IReadOnlyDictionary<string, string> protectedValues, LocalArtifactService? localArtifacts = null)
    {
        var invalid = new List<FieldIssue>();
        var readiness = new List<FieldIssue>();
        var warnings = new List<FieldIssue>();

        RequireText("local_product.service_name", "Driver service name", settings.LocalProduct.ServiceName, readiness);
        if (!string.IsNullOrWhiteSpace(settings.LocalProduct.ServiceName) && !ServiceNameRegex().IsMatch(settings.LocalProduct.ServiceName))
            invalid.Add(Issue("local_product.service_name", "INVALID_SERVICE_NAME", "Driver service name contains unsupported characters."));
        RequireText("server_connection.username", "SSH user", settings.ServerConnection.Username, readiness);
        if (!string.IsNullOrWhiteSpace(settings.ServerConnection.Username) &&
            (!UserNameRegex().IsMatch(settings.ServerConnection.Username) || ContainsControl(settings.ServerConnection.Username)))
            invalid.Add(Issue("server_connection.username", "INVALID_SSH_USER", "SSH user contains unsupported characters."));
        ValidateRange("proxy.port", "SOCKS port", settings.Proxy.Port, 1, 65535, invalid);
        ValidateRange("proxy.config_id", "Proxy configuration ID", settings.Proxy.ConfigId, 1, int.MaxValue, invalid);
        ValidateRange("server_connection.ssh_port", "SSH port", settings.ServerConnection.SshPort, 1, 65535, invalid);
        ValidateRange("server_endpoint.port_a", "Endpoint port A", settings.ServerEndpoint.PortA, 1, 65535, invalid);
        ValidateRange("server_endpoint.port_b", "Endpoint port B", settings.ServerEndpoint.PortB, 1, 65535, invalid);
        if (settings.ServerEndpoint.PortA == settings.ServerEndpoint.PortB)
            invalid.Add(Issue("server_endpoint.port_b", "DUPLICATE_ENDPOINT_PORT", "Endpoint ports A and B must differ."));
        ValidateRange("timeouts.operation_timeout_ms", "Operation timeout", settings.Timeouts.OperationTimeoutMs, 100, 600000, invalid);
        ValidateRange("timeouts.cli_actual_path_timeout_ms", "CLI path probe timeout", settings.Timeouts.CliActualPathTimeoutMs, 100, 60000, invalid);
        ValidateRange("timeouts.client_process_exit_grace_ms", "Client exit grace", settings.Timeouts.ClientProcessExitGraceMs, 1, 60000, invalid);
        ValidateRange("retention.days", "Retention days", settings.Retention.Days, 1, 3650, invalid);
        ValidateRange("retention.max_runs", "Maximum runs", settings.Retention.MaxRuns, 1, 10000, invalid);
        if (!string.Equals(settings.Ui.Theme, "dark", StringComparison.OrdinalIgnoreCase))
            invalid.Add(Issue("ui.theme", "UNSUPPORTED_THEME", "Only the dark theme is available in this milestone."));

        foreach (var field in Fields.Where(field => field.Sensitive))
        {
            protectedValues.TryGetValue(field.Id, out var value);
            if (!string.IsNullOrEmpty(value) && ContainsControl(value))
            {
                invalid.Add(Issue(field.Id, "CONTROL_CHARACTER", $"{field.Label} contains a prohibited control character."));
                continue;
            }

            var required = field.Required || (settings.Capabilities.Ipv6 && field.Id is "server_endpoint.vm_ipv6" or "server_endpoint.vps_ipv6") ||
                (settings.Capabilities.Socks5 && field.Id == "proxy.host");
            if (required && string.IsNullOrWhiteSpace(value))
            {
                readiness.Add(Issue(field.Id, "REQUIRED", $"{field.Label} is required."));
                continue;
            }
            if (string.IsNullOrWhiteSpace(value)) continue;

            switch (field.Type)
            {
                case "path":
                    if (!Path.IsPathFullyQualified(value)) invalid.Add(Issue(field.Id, "ABSOLUTE_PATH_REQUIRED", $"{field.Label} must be an absolute path."));
                    else if (field.Id != "retention.evidence_root" && !File.Exists(value)) readiness.Add(Issue(field.Id, "FILE_NOT_FOUND", $"{field.Label} was not found."));
                    break;
                case "remote-path":
                    if (!value.StartsWith("/", StringComparison.Ordinal)) invalid.Add(Issue(field.Id, "ABSOLUTE_REMOTE_PATH_REQUIRED", $"{field.Label} must be an absolute Linux path."));
                    break;
                case "host":
                    if (value.Any(char.IsWhiteSpace) || (Uri.CheckHostName(value) == UriHostNameType.Unknown && !IPAddress.TryParse(value, out _)))
                        invalid.Add(Issue(field.Id, "INVALID_HOST", $"{field.Label} is not a valid host or IP address."));
                    break;
                case "ipv4":
                    if (!IPAddress.TryParse(value, out var ipv4) || ipv4.AddressFamily != AddressFamily.InterNetwork)
                        invalid.Add(Issue(field.Id, "INVALID_IPV4", $"{field.Label} is not a valid IPv4 address."));
                    break;
                case "ipv6":
                    if (!IPAddress.TryParse(value, out var ipv6) || ipv6.AddressFamily != AddressFamily.InterNetworkV6)
                        invalid.Add(Issue(field.Id, "INVALID_IPV6", $"{field.Label} is not a valid IPv6 address."));
                    break;
            }
        }

        if (!settings.Capabilities.Ipv4 && !settings.Capabilities.Ipv6)
            readiness.Add(Issue("capabilities", "ADDRESS_FAMILY_REQUIRED", "At least one address family must be enabled."));
        if (!settings.Capabilities.Tcp && !settings.Capabilities.Udp)
            readiness.Add(Issue("capabilities", "PROTOCOL_REQUIRED", "At least one traffic protocol must be enabled."));
        if (!settings.Capabilities.Ipv6)
            warnings.Add(Issue("capabilities.ipv6", "CAPABILITY_DISABLED", "IPv6 scenarios will remain skipped."));
        localArtifacts?.AddValidationIssues(readiness);

        return new SettingsValidationResult(invalid.Count == 0, invalid.Count == 0 && readiness.Count == 0, invalid, readiness, warnings);
    }

    public static string? GetPublicEnvironmentValue(PublicSettings settings, string fieldId) => fieldId switch
    {
        "local_product.service_name" => settings.LocalProduct.ServiceName,
        "server_connection.username" => settings.ServerConnection.Username,
        "proxy.port" => settings.Proxy.Port.ToString(System.Globalization.CultureInfo.InvariantCulture),
        "proxy.config_id" => settings.Proxy.ConfigId.ToString(System.Globalization.CultureInfo.InvariantCulture),
        "server_connection.ssh_port" => settings.ServerConnection.SshPort.ToString(System.Globalization.CultureInfo.InvariantCulture),
        "server_endpoint.port_a" => settings.ServerEndpoint.PortA.ToString(System.Globalization.CultureInfo.InvariantCulture),
        "server_endpoint.port_b" => settings.ServerEndpoint.PortB.ToString(System.Globalization.CultureInfo.InvariantCulture),
        _ => null
    };

    private static void ValidateRange(string field, string label, int value, int minimum, int maximum, ICollection<FieldIssue> invalid)
    {
        if (value < minimum || value > maximum) invalid.Add(Issue(field, "OUT_OF_RANGE", $"{label} must be between {minimum} and {maximum}."));
    }

    private static void RequireText(string field, string label, string value, ICollection<FieldIssue> readiness)
    {
        if (string.IsNullOrWhiteSpace(value)) readiness.Add(Issue(field, "REQUIRED", $"{label} is required."));
    }

    private static bool ContainsControl(string value) => value.Any(character => character is '\0' or '\r' or '\n');
    private static FieldIssue Issue(string field, string code, string message) => new(field, code, message);

    [GeneratedRegex("^[A-Za-z0-9_.-]+$", RegexOptions.CultureInvariant)] private static partial Regex ServiceNameRegex();
    [GeneratedRegex("^[A-Za-z_][A-Za-z0-9_.-]{0,63}$", RegexOptions.CultureInvariant)] private static partial Regex UserNameRegex();
}
