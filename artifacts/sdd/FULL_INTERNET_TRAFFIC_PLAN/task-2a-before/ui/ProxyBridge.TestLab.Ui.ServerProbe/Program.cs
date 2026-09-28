using System.Text.Json;
using System.Text;
using ProxyBridge.TestLab.Ui.Models;
using ProxyBridge.TestLab.Ui.Services;

var files = "";
try
{
if (args.Length == 3 && args[0] == "--export-protocol-fixture")
{
    ExportProtocolFixture(Path.GetFullPath(args[1]), Path.GetFullPath(args[2]));
    Console.WriteLine("PROTOCOL_FIXTURE_READY");
    return;
}
if (args.Length != 1) throw new InvalidOperationException("SERVER_PROBE_ROOT_REQUIRED");
var root = Path.GetFullPath(args[0]);
Directory.CreateDirectory(root);
Directory.CreateDirectory(Path.Combine(root, "src"));
Directory.CreateDirectory(Path.Combine(root, "config"));
Directory.CreateDirectory(Path.Combine(root, "bin"));
CopyDependencyFixture(root);
await File.WriteAllTextAsync(Path.Combine(root, "src", "pb_net_endpoint.py"), "#!/usr/bin/env python3\nprint('fixture')\n");
Directory.CreateDirectory(Path.Combine(root, "src", "server_agent", "plugins"));
await File.WriteAllTextAsync(Path.Combine(root, "src", "server_agent", "pb_server_agent.py"), "#!/usr/bin/env python3\nprint('fixture-agent')\n");
await File.WriteAllTextAsync(Path.Combine(root, "src", "server_agent", "pb_protocol_server.py"), "#!/usr/bin/env python3\nprint('fixture-protocol-server')\n");
await File.WriteAllTextAsync(Path.Combine(root, "src", "server_agent", "standard_protocols.py"), "# fixture standard protocols\n");
await File.WriteAllTextAsync(Path.Combine(root, "src", "server_agent", "realtime_protocols.py"), "# fixture realtime protocols\n");
await File.WriteAllTextAsync(Path.Combine(root, "src", "server_agent", "failure_protocols.py"), "# fixture failure protocols\n");
await File.WriteAllTextAsync(Path.Combine(root, "src", "server_agent", "plugins", "catalog.json"), """
    {
      "schema_version": 1,
      "plugins": [
        { "id": "endpoint-core", "implementation_status": "IMPLEMENTED", "milestone": 8, "artifacts": ["pb_net_endpoint.py"], "capabilities": ["server_endpoint_core"] },
        { "id": "dns-authoritative", "implementation_status": "IMPLEMENTED", "milestone": 12, "artifacts": ["pb_protocol_server.py", "protocol-server-config.json"], "capabilities": ["server_python_protocols"] },
        { "id": "tls-origin", "implementation_status": "IMPLEMENTED", "milestone": 12, "artifacts": ["pb_protocol_server.py", "protocol-server-config.json", "tls/ca.pem", "tls/server-chain.pem", "tls/server.key.pem"], "capabilities": ["server_python_protocols", "server_tls_pki"] },
        { "id": "http-origin", "implementation_status": "IMPLEMENTED", "milestone": 12, "artifacts": ["pb_protocol_server.py", "protocol-server-config.json", "tls/ca.pem", "tls/server-chain.pem", "tls/server.key.pem"], "capabilities": ["server_python_protocols", "server_tls_pki"] }
        ,{ "id": "http2-origin", "implementation_status": "IMPLEMENTED", "milestone": 13, "artifacts": ["pb_protocol_server.py", "protocol-server-config.json", "tls/ca.pem", "tls/server-chain.pem", "tls/server.key.pem", "vendor/h2/__init__.py"], "capabilities": ["server_http2", "server_tls_pki"] }
        ,{ "id": "quic-origin", "implementation_status": "IMPLEMENTED", "milestone": 13, "artifacts": ["pb_protocol_server.py", "protocol-server-config.json", "tls/ca.pem", "tls/server-chain.pem", "tls/server.key.pem", "vendor/aioquic/__init__.py", "vendor/pylsqpack/__init__.py"], "capabilities": ["server_quic", "server_tls_pki"] }
        ,{ "id": "websocket-origin", "implementation_status": "IMPLEMENTED", "milestone": 13, "artifacts": ["pb_protocol_server.py", "protocol-server-config.json", "tls/ca.pem", "tls/server-chain.pem", "tls/server.key.pem"], "capabilities": ["server_python_protocols", "server_tls_pki"] }
        ,{ "id": "grpc-origin", "implementation_status": "IMPLEMENTED", "milestone": 13, "artifacts": ["pb_protocol_server.py", "protocol-server-config.json", "tls/ca.pem", "tls/server-chain.pem", "tls/server.key.pem", "vendor/h2/__init__.py"], "capabilities": ["server_http2", "server_tls_pki"] }
        ,{ "id": "webtransport-origin", "implementation_status": "IMPLEMENTED", "milestone": 13, "artifacts": ["pb_protocol_server.py", "protocol-server-config.json", "tls/ca.pem", "tls/server-chain.pem", "tls/server.key.pem", "vendor/aioquic/__init__.py", "vendor/pylsqpack/__init__.py"], "capabilities": ["server_quic", "server_tls_pki"] }
        ,{ "id": "file-transfer", "implementation_status": "IMPLEMENTED", "milestone": 14, "artifacts": ["pb_protocol_server.py", "standard_protocols.py", "protocol-server-config.json"], "capabilities": ["server_file_transfer"] }
        ,{ "id": "mail-suite", "implementation_status": "IMPLEMENTED", "milestone": 14, "artifacts": ["pb_protocol_server.py", "standard_protocols.py", "protocol-server-config.json"], "capabilities": ["server_mail"] }
        ,{ "id": "messaging-suite", "implementation_status": "IMPLEMENTED", "milestone": 14, "artifacts": ["pb_protocol_server.py", "standard_protocols.py", "protocol-server-config.json"], "capabilities": ["server_messaging"] }
        ,{ "id": "ntp-origin", "implementation_status": "IMPLEMENTED", "milestone": 14, "artifacts": ["pb_protocol_server.py", "standard_protocols.py", "protocol-server-config.json"], "capabilities": ["server_python_protocols"] }
        ,{ "id": "irc-origin", "implementation_status": "IMPLEMENTED", "milestone": 14, "artifacts": ["pb_protocol_server.py", "standard_protocols.py", "protocol-server-config.json"], "capabilities": ["server_python_protocols"] }
        ,{ "id": "multipeer-origin", "implementation_status": "IMPLEMENTED", "milestone": 14, "artifacts": ["pb_protocol_server.py", "standard_protocols.py", "protocol-server-config.json"], "capabilities": ["server_python_protocols"] }
        ,{ "id": "realtime-suite", "implementation_status": "IMPLEMENTED", "milestone": 15, "artifacts": ["pb_protocol_server.py", "realtime_protocols.py", "protocol-server-config.json", "vendor/cryptography/__init__.py"], "capabilities": ["server_realtime"] }
        ,{ "id": "failure-control", "implementation_status": "IMPLEMENTED", "milestone": 16, "artifacts": ["pb_protocol_server.py", "failure_protocols.py", "protocol-server-config.json"], "capabilities": ["control_failure_injection"] }
      ]
    }
    """);
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
await File.WriteAllTextAsync(Path.Combine(root, "bin", "pb_net_client.exe"), "fixture-client");

files = Path.Combine(root, "files");
Directory.CreateDirectory(files);
var gui = CreateFile("ProxyBridge.exe");
var cli = CreateFile("ProxyBridge_CLI.exe");
var driver = CreateFile("ProxyBridgeDrv.sys");
var key = CreateFile("fixture_ed25519");
var evidence = Path.Combine(root, "evidence");
Directory.CreateDirectory(evidence);

var settings = new PublicSettings
{
    LocalProduct = new LocalProductSettings { ServiceName = "ProxyBridgeDrv" },
    Proxy = new ProxySettings { Port = 10808, ConfigId = 1 },
    ServerConnection = new ServerConnectionSettings { Username = "fixture-user", SshPort = 22 },
    ServerEndpoint = new ServerEndpointSettings { PortA = 41001, PortB = 41002 },
    Capabilities = new CapabilitySettings { Ipv4 = true, Ipv6 = false, Tcp = true, Udp = true, ConnectedUdp = true, UnconnectedUdp = true, Socks5 = true },
    Timeouts = new TimeoutSettings(),
    Retention = new RetentionSettings(),
    Ui = new UiSettings()
};
var protectedValues = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase)
{
    ["local_product.gui_path"] = gui,
    ["local_product.cli_path"] = cli,
    ["local_product.driver_path"] = driver,
    ["proxy.host"] = "203.0.113.30",
    ["server_connection.host"] = "fixture-host.invalid",
    ["server_connection.private_key_path"] = key,
    ["server_endpoint.vm_ipv4"] = "192.0.2.20",
    ["server_endpoint.vps_ipv4"] = "198.51.100.10",
    ["retention.evidence_root"] = evidence
};

var storage = new AppStoragePaths(Path.Combine(root, "storage"));
var appPaths = new AppPaths(root);
var protector = new DpapiSecretProtector();
var certificateStore = new ProtocolCertificateStore(storage, protector);
var portCatalog = new ServerProtocolPortCatalog(appPaths);
var localArtifacts = new LocalArtifactService(appPaths, storage, portCatalog, certificateStore);
var store = new SettingsStore(storage, protector, localArtifacts);
var view = await store.SaveAsync(new SettingsUpdateRequest { Settings = settings, ProtectedValues = protectedValues }, CancellationToken.None);
Require(view.Validation.Ready, "FIXTURE_SETTINGS_NOT_READY");
Require(!SettingsSchema.Fields.Any(field => field.Id.Contains("sha256", StringComparison.OrdinalIgnoreCase) || field.Type == "hash"), "HASH_FIELD_EXPOSED");
Require(!SettingsSchema.Fields.Any(field => field.Id.StartsWith("local_client.", StringComparison.Ordinal)), "CLIENT_FIELD_EXPOSED");
var userField = SettingsSchema.Fields.Single(field => field.Id == "server_connection.username");
Require(!userField.Sensitive, "SSH_USER_MUST_BE_PUBLIC");
var snapshot = await store.LoadAsync(CancellationToken.None);
var runnerEnvironment = new RunnerEnvironmentService(storage, localArtifacts);
string runnerInputPath;
await using (var lease = await runnerEnvironment.MaterializeAsync(snapshot, "server-probe", CancellationToken.None))
{
    runnerInputPath = lease.Path;
    var runnerInput = await File.ReadAllTextAsync(lease.Path);
    Require(runnerInput.Contains("PB_CLIENT_EXE=" + Path.Combine(root, "bin", "pb_net_client.exe"), StringComparison.Ordinal), "AUTOMATIC_CLIENT_PATH_MISSING");
    foreach (var name in new[] { "PB_EXPECTED_CLIENT_SHA256", "PB_EXPECTED_PROXYBRIDGE_EXE_SHA256", "PB_EXPECTED_PROXYBRIDGE_CLI_SHA256", "PB_EXPECTED_DRIVER_SHA256" })
    {
        var line = runnerInput.Split(["\r\n", "\n"], StringSplitOptions.RemoveEmptyEntries).Single(item => item.StartsWith(name + "=", StringComparison.Ordinal));
        Require(line[(name.Length + 1)..].Length == 64, "AUTOMATIC_HASH_MISSING_" + name);
    }
}
Require(!File.Exists(runnerInputPath), "RUNNER_INPUT_NOT_REMOVED");

var fake = new FakeServerTransport();
var trustStore = new ServerTrustStore(storage);
var receiptStore = new ServerReceiptStore(storage, protector);
var builder = new ServerArtifactBuilder(appPaths, certificateStore, portCatalog);
var service = new ServerProvisioningService(store, trustStore, receiptStore, builder, fake);

var initial = await service.GetStatusAsync(CancellationToken.None);
Require(initial.State == "NEEDS_HOST_TRUST", "INITIAL_TRUST_GATE_MISSING");
var first = await service.ValidateAsync(new ServerValidationRequest(), CancellationToken.None);
Require(first.State == "NEEDS_HOST_TRUST" && first.TrustToken is not null, "FIRST_TRUST_NOT_REQUIRED");
Require(fake.DiscoverCount == 0, "DISCOVERY_BEFORE_TRUST");

var wrongToken = await service.ValidateAsync(new ServerValidationRequest("wrong", true), CancellationToken.None);
Require(wrongToken.State == "NEEDS_HOST_TRUST" && fake.DiscoverCount == 0, "INVALID_TRUST_TOKEN_ACCEPTED");
var trusted = await service.ValidateAsync(new ServerValidationRequest(wrongToken.TrustToken, true), CancellationToken.None);
Require(trusted.State == "PLAN_READY", "TRUSTED_DISCOVERY_NOT_PLAN_READY");
Require(fake.DiscoverCount == 1, "DISCOVERY_COUNT_AFTER_TRUST");

var plan = await service.CreatePlanAsync(CancellationToken.None);
Require(plan.State == "PLAN_READY", "INSTALL_PLAN_STATE");
Require(plan.ArtifactSha256.Count > 10 && plan.ArtifactSha256.ContainsKey("vendor/aioquic/__init__.py") && plan.ArtifactSha256.ContainsKey("vendor/h2/__init__.py") && plan.Steps.Count == 5, "INSTALL_PLAN_INCOMPLETE");
Require(plan.ArtifactBundleId.Length == 64 && plan.ProtocolPlugins.Count == 17 && plan.ProtocolPlugins.Contains("quic-origin", StringComparer.Ordinal) && plan.ProtocolPlugins.Contains("multipeer-origin", StringComparer.Ordinal) && plan.ProtocolPlugins.Contains("realtime-suite", StringComparer.Ordinal) && plan.ProtocolPlugins.Contains("failure-control", StringComparer.Ordinal), "PLUGIN_BUNDLE_PLAN_INCOMPLETE");
var planJson = JsonSerializer.Serialize(plan);
Require(!planJson.Contains("fixture-host.invalid", StringComparison.Ordinal) && !planJson.Contains("fixture_ed25519", StringComparison.Ordinal), "PLAN_EXPOSES_PRIVATE_VALUE");
Require(!planJson.Contains("server.key.pem", StringComparison.Ordinal) && !planJson.Contains("PRIVATE KEY", StringComparison.Ordinal), "PLAN_EXPOSES_PROTOCOL_PRIVATE_KEY");
await RequireThrowsAsync(() => service.ApplyAsync(new ServerApplyRequest(plan.PlanId, false), false, CancellationToken.None), "SERVER_PLAN_CONFIRMATION_REQUIRED");
var applied = await service.ApplyAsync(new ServerApplyRequest(plan.PlanId, true), false, CancellationToken.None);
Require(applied.State == "READY" && applied.Applied && fake.ApplyCount == 1, "CONFIRMED_APPLY_FAILED");
Require(fake.ObservedUnitText.Contains("IPAddressDeny=any", StringComparison.Ordinal) &&
    fake.ObservedUnitText.Contains("IPAddressAllow=198.51.100.44", StringComparison.Ordinal) &&
    fake.ObservedUnitText.Contains("IPAddressAllow=203.0.113.30", StringComparison.Ordinal), "ENDPOINT_SOURCE_SCOPE_MISSING");
Require(fake.ObservedUnitText.Contains("pb_server_agent.py --self-test", StringComparison.Ordinal), "PLUGIN_SELF_TEST_NOT_IN_SERVICE_GATE");
Require(fake.ObservedUnitText.Contains("pb_protocol_server.py --self-test", StringComparison.Ordinal) && fake.ObservedUnitText.Contains("pb_server_agent.py --serve", StringComparison.Ordinal), "PROTOCOL_SERVICE_LIFECYCLE_NOT_GATED");
Require(fake.ObservedRuntimeFiles.Contains("pb_server_agent.py") && fake.ObservedRuntimeFiles.Contains("pb_protocol_server.py") && fake.ObservedRuntimeFiles.Contains("realtime_protocols.py") && fake.ObservedRuntimeFiles.Contains("failure_protocols.py") && fake.ObservedRuntimeFiles.Contains("server-plugin-manifest.json") && fake.ObservedRuntimeFiles.Contains("vendor/aioquic/__init__.py"), "PLUGIN_RUNTIME_FILES_NOT_APPLIED");
Require((await service.GetStatusAsync(CancellationToken.None)).State == "READY", "SIGNED_RECEIPT_NOT_READY");
Require((await service.GetMetricsAsync(CancellationToken.None)).State == "COLLECTED", "METRICS_NOT_COLLECTED");

fake.HostKey = new HostKeyObservation(["fixture-host.invalid ssh-ed25519 Zml4dHVyZS1rZXktMg=="], ["ssh-ed25519 SHA256:changed"]);
var changed = await service.ValidateAsync(new ServerValidationRequest(), CancellationToken.None);
Require(changed.State == "NEEDS_HOST_TRUST" && changed.HostKeyChanged, "CHANGED_HOST_KEY_NOT_BLOCKED");
var notReplaced = await service.ValidateAsync(new ServerValidationRequest(changed.TrustToken, true, false), CancellationToken.None);
Require(notReplaced.State == "NEEDS_HOST_TRUST", "CHANGED_HOST_KEY_REPLACED_WITHOUT_EXPLICIT_CONFIRMATION");
var replaced = await service.ValidateAsync(new ServerValidationRequest(notReplaced.TrustToken, true, true), CancellationToken.None);
Require(replaced.State == "READY", "EXPLICIT_HOST_KEY_REPLACEMENT_FAILED");

var validReceipt = await receiptStore.LoadValidAsync(CancellationToken.None);
Require(validReceipt is not null, "SIGNED_RECEIPT_MISSING");
var receiptText = await File.ReadAllTextAsync(storage.ServerReceiptPath);
await File.WriteAllTextAsync(storage.ServerReceiptPath, receiptText.Replace(validReceipt!.Receipt.ReceiptId, new string('0', validReceipt.Receipt.ReceiptId.Length), StringComparison.Ordinal));
Require(await receiptStore.LoadValidAsync(CancellationToken.None) is null, "TAMPERED_RECEIPT_ACCEPTED");

fake.Discovery = fake.Discovery with { OsId = "centos", OsVersion = "9" };
var unsupported = await service.ValidateAsync(new ServerValidationRequest(), CancellationToken.None);
Require(unsupported.State == "UNSUPPORTED", "UNSUPPORTED_OS_ACCEPTED");
Require(fake.ApplyCount == 1, "UNSUPPORTED_OS_MUTATED_SERVER");

fake.Discovery = fake.Discovery with { OsId = "debian", OsVersion = "12" };
fake.ClearInstallation();
fake.FailApply = true;
var failurePlan = await service.CreatePlanAsync(CancellationToken.None);
var failure = await service.ApplyAsync(new ServerApplyRequest(failurePlan.PlanId, true), false, CancellationToken.None);
Require(failure.State == "REPAIR_REQUIRED" && failure.RollbackAttempted && failure.RollbackSucceeded, "APPLY_FAILURE_ROLLBACK_NOT_REPORTED");

Console.WriteLine("PASS: offline server provisioning state machine");
}
catch (Exception exception)
{
    Console.Error.WriteLine("SERVER_PROBE_FAILED: " + exception.GetType().Name + ": " + exception.Message);
    Console.Error.WriteLine(exception.StackTrace);
    Environment.ExitCode = 1;
}
return;

static void ExportProtocolFixture(string repositoryRoot, string outputRoot)
{
    if (!Directory.Exists(repositoryRoot) || Directory.Exists(outputRoot))
        throw new InvalidOperationException("PROTOCOL_FIXTURE_PATH_INVALID");
    Directory.CreateDirectory(outputRoot);
    var appPaths = new AppPaths(repositoryRoot);
    var storage = new AppStoragePaths(Path.Combine(outputRoot, ".storage"));
    var protector = new DpapiSecretProtector();
    var certificates = new ProtocolCertificateStore(storage, protector);
    var ports = new ServerProtocolPortCatalog(appPaths);
    var builder = new ServerArtifactBuilder(appPaths, certificates, ports);
    var settings = new PublicSettings
    {
        ServerEndpoint = new ServerEndpointSettings { PortA = 41001, PortB = 41002 },
        Capabilities = new CapabilitySettings { Ipv4 = true, Ipv6 = false, Tcp = true, Udp = true }
    };
    var bundle = builder.Build(settings, ["127.0.0.1"]);
    foreach (var relative in bundle.RuntimeFiles.Keys.Where(relative =>
        relative is "pb_protocol_server.py" or "standard_protocols.py" or "realtime_protocols.py" or "failure_protocols.py" or "protocol-server-config.json" or "tls/ca.pem" or "tls/server-chain.pem" or "tls/server.key.pem"))
    {
        var target = Path.Combine(outputRoot, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        File.WriteAllBytes(target, bundle.RuntimeFiles[relative]);
    }
    var windowsVendor = Path.Combine(repositoryRoot, "bin", "protocol-worker", "worker", "_vendor");
    if (!Directory.Exists(windowsVendor)) throw new InvalidOperationException("PROTOCOL_FIXTURE_WINDOWS_VENDOR_MISSING");
    foreach (var source in Directory.EnumerateFiles(windowsVendor, "*", SearchOption.AllDirectories))
    {
        var relative = Path.GetRelativePath(windowsVendor, source);
        var target = Path.Combine(outputRoot, "vendor", relative);
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        File.Copy(source, target, overwrite: false);
    }
}

static void CopyDependencyFixture(string fixtureRoot)
{
    var current = new DirectoryInfo(AppContext.BaseDirectory);
    while (current is not null && !File.Exists(Path.Combine(current.FullName, "vendor", "protocol-dependencies.lock.json")))
        current = current.Parent;
    if (current is null) throw new InvalidOperationException("PROBE_REPOSITORY_ROOT_NOT_FOUND");
    var sourceRoot = Path.Combine(current.FullName, "vendor");
    var targetRoot = Path.Combine(fixtureRoot, "vendor");
    Directory.CreateDirectory(Path.Combine(targetRoot, "wheelhouse", "linux-x64"));
    File.Copy(Path.Combine(sourceRoot, "protocol-dependencies.lock.json"), Path.Combine(targetRoot, "protocol-dependencies.lock.json"));
    foreach (var source in Directory.EnumerateFiles(Path.Combine(sourceRoot, "wheelhouse", "linux-x64"), "*", SearchOption.TopDirectoryOnly))
        File.Copy(source, Path.Combine(targetRoot, "wheelhouse", "linux-x64", Path.GetFileName(source)));
}

string CreateFile(string name)
{
    var path = Path.Combine(files, name);
    File.WriteAllText(path, "fixture");
    return path;
}

static void Require(bool condition, string code)
{
    if (!condition) throw new InvalidOperationException(code);
}

static async Task RequireThrowsAsync(Func<Task> action, string code)
{
    try { await action(); }
    catch (ServerOperationException exception) when (exception.Message == code) { return; }
    throw new InvalidOperationException("EXPECTED_" + code);
}

public sealed class FakeServerTransport : IServerTransport
{
    private IReadOnlyDictionary<string, string> _activeHashes = new Dictionary<string, string>();
    public HostKeyObservation HostKey { get; set; } = new(["fixture-host.invalid ssh-ed25519 Zml4dHVyZS1rZXktMQ=="], ["ssh-ed25519 SHA256:fixture"]);
    public ServerDiscoveryData Discovery { get; set; } = new("debian", "12", "x86_64", true, true, true, "3.11", true, 1048576, false, false, false, "", "", "", false, 0, [], [], "198.51.100.44", "none");
    public int DiscoverCount { get; private set; }
    public int ApplyCount { get; private set; }
    public bool FailApply { get; set; }
    public string ObservedUnitText { get; private set; } = "";
    public IReadOnlySet<string> ObservedRuntimeFiles { get; private set; } = new HashSet<string>();

    public void ClearInstallation() => _activeHashes = new Dictionary<string, string>();

    public Task<HostKeyObservation> ScanHostKeysAsync(ServerTarget target, CancellationToken cancellationToken) => Task.FromResult(HostKey);

    public Task<ServerDiscoveryData> DiscoverAsync(ServerTarget target, ServerPortSet ports, CancellationToken cancellationToken)
    {
        DiscoverCount++;
        var current = _activeHashes.Count == 0 ? Discovery : Discovery with
        {
            ServiceExists = true,
            ServiceActive = true,
            ServiceEnabled = true,
            EndpointSha256 = _activeHashes["pb_net_endpoint.py"],
            UnitSha256 = _activeHashes["proxybridge-testlab-endpoint.service"],
            PluginManifestSha256 = _activeHashes["server-plugin-manifest.json"],
            PluginSelfTestPassed = true,
            PluginCount = 17
        };
        return Task.FromResult(current);
    }

    public Task<ServerApplyData> ApplyAsync(ServerTarget target, string planId, PublicSettings settings, ServerArtifactBundle artifacts, bool installPython, CancellationToken cancellationToken)
    {
        ApplyCount++;
        ObservedUnitText = Encoding.UTF8.GetString(artifacts.Unit);
        ObservedRuntimeFiles = artifacts.RuntimeFiles.Keys.ToHashSet(StringComparer.Ordinal);
        if (FailApply) return Task.FromResult(new ServerApplyData(false, true, true, "FAKE_APPLY_FAILED"));
        _activeHashes = artifacts.Hashes;
        return Task.FromResult(new ServerApplyData(true, false, true, ""));
    }

    public Task<ServerVerificationData> VerifyAsync(ServerTarget target, ServerPortSet ports, CancellationToken cancellationToken)
    {
        var ready = _activeHashes.Count > 0;
        return Task.FromResult(new ServerVerificationData(ready,
            ready ? _activeHashes["pb_net_endpoint.py"] : "",
            ready ? _activeHashes["proxybridge-testlab-endpoint.service"] : "",
            ready ? _activeHashes["server-plugin-manifest.json"] : "",
            ready, ready ? 17 : 0, ready, ready, ready, ready ? "" : "NOT_INSTALLED"));
    }

    public Task<ServerMetricsView> GetMetricsAsync(ServerTarget target, CancellationToken cancellationToken) => Task.FromResult(
        new ServerMetricsView("COLLECTED", "active", "running", 42, 0, 1048576, 123456, 2048, 4, 0, 1048576, ["No recent warnings."], DateTimeOffset.UtcNow));
}
