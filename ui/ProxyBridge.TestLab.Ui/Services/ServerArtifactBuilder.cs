using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class ServerArtifactBuilder(
    AppPaths paths,
    ProtocolCertificateStore certificateStore,
    ServerProtocolPortCatalog portCatalog)
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);

    public ServerPortSet GetRequiredPorts(PublicSettings settings)
    {
        var catalog = ServerPluginCatalog.Load(ReadPublicFile("src", "server_agent", "plugins", "catalog.json"));
        return portCatalog.GetRequiredPorts(catalog.Implemented.Select(plugin => plugin.Id), settings.ServerEndpoint.PortA, settings.ServerEndpoint.PortB);
    }

    public ServerArtifactBundle Build(PublicSettings settings, IEnumerable<string>? allowedSources = null)
    {
        var certificates = certificateStore.GetOrCreate();
        var protocolConfig = JsonSerializer.SerializeToUtf8Bytes(new
        {
            schema_version = 1,
            bind_ipv4 = "0.0.0.0",
            bind_ipv6 = settings.Capabilities.Ipv6 ? "::" : "",
            jsonl_log = "/var/log/proxybridge-testlab/protocols.jsonl",
            dns = new
            {
                port = portCatalog["dns"],
                zone = "probe.test.",
                answer_ipv4 = "192.0.2.123",
                answer_ipv6 = "2001:db8::123"
            },
            http = new { port = portCatalog["http"] },
            tls = new
            {
                port = portCatalog["tls"],
                certificate = "tls/server-chain.pem",
                private_key = "tls/server.key.pem",
                ca_certificate = "tls/ca.pem",
                certificate_sha256 = certificates.ServerCertificateSha256
            },
            https = new { port = portCatalog["https"] },
            http2 = new { port = portCatalog["http2"] },
            quic_http3 = new { port = portCatalog["quic_http3"] },
            websocket = new { port = portCatalog["websocket"] },
            grpc = new { port = portCatalog["grpc"] },
            webtransport = new { port = portCatalog["webtransport"] }
            ,ftp = new { port = portCatalog["ftp_control"] }
            ,ftp_data = new { port = portCatalog["ftp_data_start"] }
            ,smtp = new { port = portCatalog["smtp"] }
            ,smtps = new { port = portCatalog["smtps"] }
            ,imap = new { port = portCatalog["imap"] }
            ,imaps = new { port = portCatalog["imaps"] }
            ,pop3 = new { port = portCatalog["pop3"] }
            ,pop3s = new { port = portCatalog["pop3s"] }
            ,mqtt = new { port = portCatalog["mqtt"] }
            ,mqtts = new { port = portCatalog["mqtts"] }
            ,amqp = new { port = portCatalog["amqp"] }
            ,amqps = new { port = portCatalog["amqps"] }
            ,ntp = new { port = portCatalog["ntp"] }
            ,irc = new { port = portCatalog["irc"] }
            ,ircs = new { port = portCatalog["ircs"] }
            ,multipeer = new { port = portCatalog["multipeer"] }
            ,stun_turn = new { port = portCatalog["stun_turn"] }
            ,rtp_media = new { port = portCatalog["realtime_start"] }
            ,receive_only = new { port = portCatalog["realtime_start"] + 1 }
            ,failure_control = new { port = portCatalog["failure_control"] }
            ,negative_proxy = new
            {
                enabled = false,
                identity = "testlab-isolated-negative-socks5-v1",
                auth_port = portCatalog["negative_proxy"],
                unavailable_port = portCatalog["negative_proxy_unavailable"]
            }
        }, new JsonSerializerOptions { WriteIndented = true });
        var runtimeFiles = new SortedDictionary<string, byte[]>(StringComparer.Ordinal)
        {
            ["pb_net_endpoint.py"] = ReadPublicFile("src", "pb_net_endpoint.py"),
            ["pb_server_agent.py"] = ReadPublicFile("src", "server_agent", "pb_server_agent.py"),
            ["pb_protocol_server.py"] = ReadPublicFile("src", "server_agent", "pb_protocol_server.py"),
            ["browser_origin.py"] = ReadPublicFile("src", "server_agent", "browser_origin.py"),
            ["standard_protocols.py"] = ReadPublicFile("src", "server_agent", "standard_protocols.py"),
            ["realtime_protocols.py"] = ReadPublicFile("src", "server_agent", "realtime_protocols.py"),
            ["failure_protocols.py"] = ReadPublicFile("src", "server_agent", "failure_protocols.py"),
            ["negative_proxy.py"] = ReadPublicFile("src", "server_agent", "negative_proxy.py"),
            ["plugins/catalog.json"] = ReadPublicFile("src", "server_agent", "plugins", "catalog.json"),
            ["protocol-server-config.json"] = protocolConfig,
            ["tls/ca.pem"] = certificates.CaCertificatePem,
            ["tls/server-chain.pem"] = certificates.ServerCertificateChainPem,
            ["tls/server.key.pem"] = certificates.ServerPrivateKeyPem
        };
        ServerDependencyBundle.AddLockedLinuxRuntime(paths, runtimeFiles);
        var catalog = ServerPluginCatalog.Load(runtimeFiles["plugins/catalog.json"]);
        var portSet = portCatalog.GetRequiredPorts(catalog.Implemented.Select(plugin => plugin.Id), settings.ServerEndpoint.PortA, settings.ServerEndpoint.PortB);
        var preManifestHashes = runtimeFiles.ToDictionary(item => item.Key, item => Hash(item.Value), StringComparer.Ordinal);
        runtimeFiles["server-plugin-manifest.json"] = catalog.BuildInstalledManifest(preManifestHashes);

        var ipv6 = settings.Capabilities.Ipv6 ? " --bind-ipv6 ::" : "";
        var sourceDirectives = (allowedSources ?? [])
            .Select(source => IPAddress.TryParse(source, out var address) ? address.ToString() : throw new InvalidOperationException("ENDPOINT_ALLOWED_SOURCE_INVALID"))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(source => source, StringComparer.Ordinal)
            .Select(source => $"IPAddressAllow={source}");
        var sourcePolicy = string.Join("\n", new[] { "IPAddressDeny=any", "IPAddressAllow=localhost" }.Concat(sourceDirectives));
        var unit = Utf8NoBom.GetBytes($$"""
            [Unit]
            Description=ProxyBridge TestLab versioned protocol endpoint
            After=network-online.target
            Wants=network-online.target

            [Service]
            Type=simple
            User=proxybridge-testlab
            Group=proxybridge-testlab
            WorkingDirectory=/opt/proxybridge-testlab/current
            ExecStartPre=/usr/bin/python3 -B /opt/proxybridge-testlab/current/pb_server_agent.py --self-test --manifest /opt/proxybridge-testlab/current/server-plugin-manifest.json
            ExecStartPre=/usr/bin/python3 -B /opt/proxybridge-testlab/current/pb_protocol_server.py --self-test --config /opt/proxybridge-testlab/current/protocol-server-config.json
            ExecStart=/usr/bin/python3 -B /opt/proxybridge-testlab/current/pb_server_agent.py --serve --manifest /opt/proxybridge-testlab/current/server-plugin-manifest.json --endpoint-log /var/log/proxybridge-testlab/server.jsonl --protocol-config /opt/proxybridge-testlab/current/protocol-server-config.json --bind-ipv4 0.0.0.0{{ipv6}} --endpoint-a-port {{settings.ServerEndpoint.PortA}} --endpoint-b-port {{settings.ServerEndpoint.PortB}}
            Restart=on-failure
            RestartSec=2
            NoNewPrivileges=true
            PrivateTmp=true
            ProtectSystem=strict
            ProtectHome=true
            ReadWritePaths=/var/log/proxybridge-testlab
            {{sourcePolicy}}

            [Install]
            WantedBy=multi-user.target
            """.Replace("\r\n", "\n", StringComparison.Ordinal) + "\n");
        var logrotate = Utf8NoBom.GetBytes("""
            /var/log/proxybridge-testlab/server.jsonl /var/log/proxybridge-testlab/protocols.jsonl {
                daily
                rotate 7
                size 20M
                missingok
                notifempty
                compress
                copytruncate
                su proxybridge-testlab proxybridge-testlab
            }
            """.Replace("\r\n", "\n", StringComparison.Ordinal) + "\n");

        var hashes = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var item in runtimeFiles) hashes[item.Key] = Hash(item.Value);
        hashes["proxybridge-testlab-endpoint.service"] = Hash(unit);
        hashes["proxybridge-testlab"] = Hash(logrotate);
        var bundleIdentity = Utf8NoBom.GetBytes(string.Join("\n", hashes.Select(item => $"{item.Key}={item.Value}")) + "\n");
        var bundleId = Hash(bundleIdentity);
        return new ServerArtifactBundle(runtimeFiles, unit, logrotate, hashes, bundleId,
            catalog.Implemented.Select(plugin => plugin.Id).Order(StringComparer.Ordinal).ToArray(), portSet,
            new HashSet<string>(["tls/server.key.pem"], StringComparer.Ordinal));
    }

    private byte[] ReadPublicFile(params string[] segments)
    {
        var path = segments.Aggregate(paths.RepositoryRoot, Path.Combine);
        if (!File.Exists(path)) throw new InvalidOperationException("ENDPOINT_ARTIFACT_MISSING");
        var item = new FileInfo(path);
        if (item.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("ENDPOINT_ARTIFACT_REPARSE_POINT_REFUSED");
        return File.ReadAllBytes(path);
    }

    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
}

public sealed record ServerArtifactBundle(
    IReadOnlyDictionary<string, byte[]> RuntimeFiles,
    byte[] Unit,
    byte[] Logrotate,
    IReadOnlyDictionary<string, string> Hashes,
    string BundleId,
    IReadOnlyList<string> ImplementedPlugins,
    ServerPortSet Ports,
    IReadOnlySet<string> SensitiveRuntimeFiles)
{
    public byte[] Endpoint => RuntimeFiles["pb_net_endpoint.py"];
    public byte[] Agent => RuntimeFiles["pb_server_agent.py"];
    public byte[] PluginManifest => RuntimeFiles["server-plugin-manifest.json"];
    public IReadOnlyDictionary<string, string> PublicHashes => Hashes
        .Where(item => !SensitiveRuntimeFiles.Contains(item.Key))
        .ToDictionary(item => item.Key, item => item.Value, StringComparer.Ordinal);
}
