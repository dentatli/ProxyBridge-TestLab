using System.Text.Json;
using System.Text.RegularExpressions;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record ServerPortSet(IReadOnlyList<int> TcpPorts, IReadOnlyList<int> UdpPorts);

public sealed partial class ServerProtocolPortCatalog(AppPaths paths)
{
    private static readonly string[] RequiredNames =
    [
        "dns", "http", "tls", "https", "http2", "quic_http3", "websocket", "grpc", "webtransport",
        "ftp_control", "ftp_data_start", "ftp_data_end", "sftp", "smtp", "smtps", "imap", "imaps",
        "pop3", "pop3s", "mqtt", "mqtts", "amqp", "amqps", "ntp", "irc", "ircs", "stun_turn",
        "turn_tls", "realtime_start", "realtime_end", "multipeer", "failure_control", "negative_proxy",
        "negative_proxy_unavailable", "impairment_control", "performance"
    ];

    private readonly Lazy<IReadOnlyDictionary<string, int>> _ports = new(() => Load(paths));

    public int this[string name] => _ports.Value.TryGetValue(name, out var port)
        ? port
        : throw new InvalidOperationException("SERVER_PROTOCOL_PORT_UNKNOWN");

    public ServerPortSet GetRequiredPorts(IEnumerable<string> implementedPlugins, int endpointPortA, int endpointPortB)
    {
        ValidatePort(endpointPortA);
        ValidatePort(endpointPortB);
        var tcp = new HashSet<int>();
        var udp = new HashSet<int>();
        foreach (var plugin in implementedPlugins.Distinct(StringComparer.Ordinal))
        {
            switch (plugin)
            {
                case "endpoint-core":
                    Add(tcp, endpointPortA, endpointPortB);
                    Add(udp, endpointPortA, endpointPortB);
                    break;
                case "dns-authoritative": Add(tcp, this["dns"]); Add(udp, this["dns"]); break;
                case "dns-encrypted": Add(tcp, this["tls"], this["https"]); break;
                case "tls-origin": Add(tcp, this["tls"]); break;
                case "http-origin": Add(tcp, this["http"], this["https"]); break;
                case "http2-origin": Add(tcp, this["http2"]); break;
                case "quic-origin": Add(udp, this["quic_http3"]); break;
                case "websocket-origin": Add(tcp, this["websocket"]); break;
                case "grpc-origin": Add(tcp, this["grpc"]); break;
                case "webtransport-origin": Add(udp, this["webtransport"]); break;
                case "file-transfer":
                    Add(tcp, this["ftp_control"], this["sftp"]);
                    AddRange(tcp, this["ftp_data_start"], this["ftp_data_end"]);
                    break;
                case "mail-suite": Add(tcp, this["smtp"], this["smtps"], this["imap"], this["imaps"], this["pop3"], this["pop3s"]); break;
                case "messaging-suite": Add(tcp, this["mqtt"], this["mqtts"], this["amqp"], this["amqps"]); break;
                case "ntp-origin": Add(udp, this["ntp"]); break;
                case "irc-origin": Add(tcp, this["irc"], this["ircs"]); break;
                case "multipeer-origin": Add(tcp, this["multipeer"]); break;
                case "realtime-suite":
                    Add(tcp, this["stun_turn"], this["turn_tls"]);
                    Add(udp, this["stun_turn"]);
                    AddRange(udp, this["realtime_start"], this["realtime_end"]);
                    break;
                case "failure-control": Add(tcp, this["failure_control"]); break;
                case "negative-proxy": Add(tcp, this["negative_proxy"]); break;
                case "performance-origin": Add(tcp, this["performance"]); Add(udp, this["performance"]); break;
            }
        }
        return new ServerPortSet(tcp.Order().ToArray(), udp.Order().ToArray());
    }

    private static IReadOnlyDictionary<string, int> Load(AppPaths paths)
    {
        var path = Path.Combine(paths.RepositoryRoot, "config", "server-protocol-ports.json");
        if (!File.Exists(path)) throw new InvalidOperationException("SERVER_PROTOCOL_PORT_CATALOG_MISSING");
        using var document = JsonDocument.Parse(File.ReadAllBytes(path), new JsonDocumentOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow
        });
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("schema_version", out var schema) || schema.GetInt32() != 1 ||
            !root.TryGetProperty("ports", out var portsElement) || portsElement.ValueKind != JsonValueKind.Object)
            throw new InvalidOperationException("SERVER_PROTOCOL_PORT_CATALOG_SCHEMA_UNSUPPORTED");
        var ports = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var property in portsElement.EnumerateObject())
        {
            if (!SafeNameRegex().IsMatch(property.Name) || property.Value.ValueKind != JsonValueKind.Number || !property.Value.TryGetInt32(out var value))
                throw new InvalidOperationException("SERVER_PROTOCOL_PORT_ENTRY_INVALID");
            ValidatePort(value);
            if (!ports.TryAdd(property.Name, value)) throw new InvalidOperationException("SERVER_PROTOCOL_PORT_DUPLICATE_NAME");
        }
        if (!RequiredNames.All(ports.ContainsKey) || ports.Count != RequiredNames.Length)
            throw new InvalidOperationException("SERVER_PROTOCOL_PORT_CATALOG_INCOMPLETE");
        ValidateRange(ports, "ftp_data_start", "ftp_data_end");
        ValidateRange(ports, "realtime_start", "realtime_end");
        var allocated = new HashSet<int>();
        foreach (var item in ports.Where(item => item.Key is not ("ftp_data_start" or "ftp_data_end" or "realtime_start" or "realtime_end")))
            if (!allocated.Add(item.Value)) throw new InvalidOperationException("SERVER_PROTOCOL_PORT_OVERLAP");
        AddRangeChecked(allocated, ports["ftp_data_start"], ports["ftp_data_end"]);
        AddRangeChecked(allocated, ports["realtime_start"], ports["realtime_end"]);
        return ports;
    }

    private static void ValidateRange(IReadOnlyDictionary<string, int> ports, string start, string end)
    {
        if (ports[start] > ports[end] || ports[end] - ports[start] > 128)
            throw new InvalidOperationException("SERVER_PROTOCOL_PORT_RANGE_INVALID");
    }

    private static void AddRangeChecked(HashSet<int> target, int start, int end)
    {
        for (var value = start; value <= end; value++)
            if (!target.Add(value)) throw new InvalidOperationException("SERVER_PROTOCOL_PORT_OVERLAP");
    }

    private static void Add(HashSet<int> target, params int[] values)
    {
        foreach (var value in values) target.Add(value);
    }

    private static void AddRange(HashSet<int> target, int start, int end)
    {
        for (var value = start; value <= end; value++) target.Add(value);
    }

    private static void ValidatePort(int port)
    {
        if (port is < 1 or > 65535) throw new InvalidOperationException("SERVER_PROTOCOL_PORT_INVALID");
    }

    [GeneratedRegex("^[a-z][a-z0-9_]{0,63}$", RegexOptions.CultureInvariant)]
    private static partial Regex SafeNameRegex();
}
