using System.Text;
using ProxyBridge.TestLab.Ui.Models;
using ProxyBridge.TestLab.Ui.Services;

if (args.Length != 1) throw new InvalidOperationException("SECURITY_PROBE_ROOT_REQUIRED");
var root = Path.GetFullPath(args[0]);
Directory.CreateDirectory(root);
Directory.CreateDirectory(Path.Combine(root, "config"));
await File.WriteAllTextAsync(Path.Combine(root, "config", "server-protocol-ports.json"), """
    {
      "schema_version": 1,
      "ports": {
        "dns": 42053, "http": 42080, "tls": 42443, "https": 42444, "http2": 42445,
        "quic_http3": 42446, "websocket": 42447, "grpc": 42448, "webtransport": 42449,
        "ftp_control": 42121, "ftp_data_start": 42122, "ftp_data_end": 42131, "sftp": 42222,
        "smtp": 42225, "smtps": 42465, "imap": 42143, "imaps": 42993, "pop3": 42110,
        "pop3s": 42995, "mqtt": 42183, "mqtts": 42883, "amqp": 42572, "amqps": 42571,
        "ntp": 42132, "irc": 42667, "ircs": 42697, "stun_turn": 42378, "turn_tls": 42534,
        "realtime_start": 43000, "realtime_end": 43031, "multipeer": 42668, "failure_control": 42701,
        "negative_proxy": 42702, "impairment_control": 42703, "performance": 42501
      }
    }
    """);

var files = Path.Combine(root, "fixture-files");
Directory.CreateDirectory(files);
var guiPath = CreateFile("ProxyBridge.exe");
var cliPath = CreateFile("ProxyBridge_CLI.exe");
var driverPath = CreateFile("ProxyBridgeDrv.sys");
var clientDirectory = Path.Combine(root, "bin");
Directory.CreateDirectory(clientDirectory);
var clientPath = Path.Combine(clientDirectory, "pb_net_client.exe");
File.WriteAllText(clientPath, "fixture");
CreateProtocolBundle(root);
var keyPath = CreateFile("fixture_ed25519");
var evidenceRoot = Path.Combine(root, "evidence-private");
Directory.CreateDirectory(evidenceRoot);
var fixtureHost = "fixture-host.invalid";
var fixtureUser = "fixture-user";

var publicSettings = new PublicSettings
{
    LocalProduct = new LocalProductSettings
    {
        ServiceName = "ProxyBridgeDrv"
    },
    Proxy = new ProxySettings { Port = 10808, ConfigId = 1 },
    ServerConnection = new ServerConnectionSettings { Username = fixtureUser, SshPort = 22 },
    ServerEndpoint = new ServerEndpointSettings { PortA = 41001, PortB = 41002 },
    Capabilities = new CapabilitySettings { Ipv4 = true, Ipv6 = false, Tcp = true, Udp = true, ConnectedUdp = true, UnconnectedUdp = true, Socks5 = true },
    Timeouts = new TimeoutSettings { OperationTimeoutMs = 5000, CliActualPathTimeoutMs = 2000, ClientProcessExitGraceMs = 2000 },
    Retention = new RetentionSettings { Days = 30, MaxRuns = 100 },
    Ui = new UiSettings { Theme = "dark" }
};

var protectedValues = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase)
{
    ["local_product.gui_path"] = guiPath,
    ["local_product.cli_path"] = cliPath,
    ["local_product.driver_path"] = driverPath,
    ["proxy.host"] = "203.0.113.30",
    ["server_connection.host"] = fixtureHost,
    ["server_connection.private_key_path"] = keyPath,
    ["server_endpoint.vm_ipv4"] = "192.0.2.20",
    ["server_endpoint.vps_ipv4"] = "198.51.100.10",
    ["retention.evidence_root"] = evidenceRoot
};

var storagePaths = new AppStoragePaths(Path.Combine(root, "app-storage"));
var appPaths = new AppPaths(root);
var protector = new DpapiSecretProtector();
var certificateStore = new ProtocolCertificateStore(storagePaths, protector);
var portCatalog = new ServerProtocolPortCatalog(appPaths);
var localArtifacts = new LocalArtifactService(appPaths, storagePaths, portCatalog, certificateStore);
var store = new SettingsStore(storagePaths, protector, localArtifacts);
var request = new SettingsUpdateRequest { Settings = publicSettings, ProtectedValues = protectedValues };
var view = await store.SaveAsync(request, CancellationToken.None);
Require(view.Validation.Ready, "SAVED_SETTINGS_NOT_READY");
Require(protectedValues.Keys.All(key => view.ProtectedPresence.TryGetValue(key, out var present) && present), "PRESENCE_MAP_INVALID");

var publicText = await File.ReadAllTextAsync(storagePaths.PublicSettingsPath);
var protectedText = await File.ReadAllTextAsync(storagePaths.ProtectedSettingsPath);
Require(!publicText.Contains(fixtureHost, StringComparison.Ordinal), "SECRET_IN_PUBLIC_SETTINGS");
Require(publicText.Contains(fixtureUser, StringComparison.Ordinal), "SSH_USER_NOT_PUBLIC");
Require(!protectedText.Contains(fixtureHost, StringComparison.Ordinal) && !protectedText.Contains(fixtureUser, StringComparison.Ordinal), "PLAINTEXT_IN_PROTECTED_SETTINGS");
Require(protectedText.Contains("DPAPI_CURRENT_USER", StringComparison.Ordinal), "DPAPI_ENVELOPE_MISSING");

var snapshot = await store.LoadAsync(CancellationToken.None);
Require(snapshot.ProtectedValues["server_connection.host"] == fixtureHost, "DPAPI_ROUNDTRIP_FAILED");
var runnerEnvironment = new RunnerEnvironmentService(storagePaths, localArtifacts);
string leasePath;
await using (var lease = await runnerEnvironment.MaterializeAsync(snapshot, "fixture-run", CancellationToken.None))
{
    leasePath = lease.Path;
    var bytes = await File.ReadAllBytesAsync(lease.Path);
    Require(bytes.Length > 3 && !(bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF), "RUNNER_INPUT_HAS_UTF8_BOM");
    var text = Encoding.UTF8.GetString(bytes);
    Require(text.Contains("PB_SSH_HOST=" + fixtureHost, StringComparison.Ordinal), "RUNNER_INPUT_MAPPING_FAILED");
    Require(text.Contains("PB_CLIENT_EXE=" + clientPath, StringComparison.Ordinal), "AUTOMATIC_CLIENT_MAPPING_FAILED");
    Require(text.Contains("PB_EXPECTED_CLIENT_SHA256=", StringComparison.Ordinal), "AUTOMATIC_CLIENT_HASH_MISSING");
    Require(text.Contains("PB_PROTOCOL_PYTHON_EXE=", StringComparison.Ordinal), "AUTOMATIC_PROTOCOL_RUNTIME_MAPPING_FAILED");
    Require(text.Contains("PB_EXPECTED_PROTOCOL_EVIDENCE_CONTRACT_SHA256=", StringComparison.Ordinal), "AUTOMATIC_PROTOCOL_CONTRACT_HASH_MISSING");
    Require(text.Contains("PB_PROTOCOL_CA_PEM=", StringComparison.Ordinal), "AUTOMATIC_PROTOCOL_CA_MAPPING_FAILED");
    Require(!text.Contains("local_product.gui_path", StringComparison.Ordinal), "RUNNER_INPUT_EXPOSES_UI_FIELD_ID");
    Array.Clear(bytes);
}
Require(!File.Exists(leasePath), "RUNNER_INPUT_NOT_DELETED");
Require(localArtifacts.GetProtocolRuntimeStatus().Ready, "PROTOCOL_RUNTIME_INTEGRITY_NOT_READY");
File.AppendAllText(localArtifacts.ProtocolWorkerEntrypointPath, "tampered");
Require(!localArtifacts.GetProtocolRuntimeStatus().Ready && localArtifacts.GetProtocolRuntimeStatus().Status == "INTEGRITY_FAILED", "PROTOCOL_RUNTIME_TAMPER_NOT_REJECTED");

Console.WriteLine("PASS: UI settings security probe");
return;

string CreateFile(string name)
{
    var path = Path.Combine(files, name);
    File.WriteAllText(path, "fixture");
    return path;
}

static void Require(bool condition, string error)
{
    if (!condition) throw new InvalidOperationException(error);
}

static void CreateProtocolBundle(string repositoryRoot)
{
    var bundle = Path.Combine(repositoryRoot, "bin", "protocol-worker");
    var files = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["runtime/python/python.exe"] = "fixture-python",
        ["worker/pb_protocol_worker.py"] = "print('fixture')\n",
        ["worker/plugins/manifest.json"] = "{\"schema_version\":1,\"plugins\":[]}",
        ["config/protocol-evidence-contract.json"] = "{\"schema_version\":1}",
        ["BUNDLE-MANIFEST.json"] = "{\"schema_version\":1,\"runtime_id\":\"proxybridge-protocol-worker\",\"python_version\":\"3.11\",\"architecture\":\"x64\",\"entrypoint\":\"worker/pb_protocol_worker.py\",\"plugin_manifest\":\"worker/plugins/manifest.json\",\"self_test_passed\":true,\"network_installation_allowed\":false}"
    };
    foreach (var item in files)
    {
        var path = Path.Combine(bundle, item.Key.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, item.Value, new UTF8Encoding(false));
    }
    var sums = files.Keys.Order(StringComparer.Ordinal).Select(relative =>
    {
        var path = Path.Combine(bundle, relative.Replace('/', Path.DirectorySeparatorChar));
        return LocalArtifactService.ComputeSha256(path) + "  " + relative;
    });
    File.WriteAllText(Path.Combine(bundle, "SHA256SUMS.txt"), string.Join("\n", sums) + "\n", new UTF8Encoding(false));
}
