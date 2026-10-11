using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using ProxyBridge.TestLab.Ui.Services;

// Explicit acceptance helper: own scratch trust files, no settings/service/driver changes.
if (args.Length != 5) throw new InvalidOperationException("HOST PORT PRIVATE_KEY KNOWN_HOSTS SCRATCH_PARENT required");
var target = new ServerTarget(args[0], int.Parse(args[1]), "root", Path.GetFullPath(args[2]));
var trustedPath = Path.GetFullPath(args[3]);
var originalTrust = File.ReadAllBytes(trustedPath);
var originalKeyHash = SHA256.HashData(File.ReadAllBytes(target.PrivateKeyPath));
var scratch = Path.Combine(Path.GetFullPath(args[4]), "ssh-acceptance-" + Guid.NewGuid().ToString("N"));
var paths = new AppStoragePaths(scratch);
paths.EnsureSecureDirectories();
var transport = new OpenSshServerTransport(paths);
// Exercise the actual internal traffic transport, including its process timeout/cancel path.
var method = typeof(OpenSshServerTransport).GetMethod("ExecuteTrafficPythonAsync", BindingFlags.Instance | BindingFlags.NonPublic)
    ?? throw new InvalidOperationException("Traffic transport method missing");
const string script = "print('{\"state\":\"READY\"}')\n";
async Task<JsonElement> Execute(ServerTarget endpoint, CancellationToken token = default) =>
    await (Task<JsonElement>)method.Invoke(transport, [endpoint, script, token])!;
async Task Reject(string name, ServerTarget endpoint, string expected)
{
    try { await Execute(endpoint); }
    catch (InvalidOperationException error) when (error.Message == expected)
    {
        Console.WriteLine($"PASS {name}: {expected}");
        return;
    }
    throw new InvalidOperationException($"{name} did not reject with {expected}");
}
async Task Accept()
{
    if ((await Execute(target)).GetProperty("state").GetString() != "READY")
        throw new InvalidOperationException("SSH control response mismatch");
}
try
{
    await File.WriteAllBytesAsync(paths.KnownHostsPath, originalTrust);
    await Accept();
    Console.WriteLine("PASS correct-trust read-only SSH control");
    var publicKey = File.ReadAllText(target.PrivateKeyPath + ".pub").Split(' ', StringSplitOptions.RemoveEmptyEntries);
    if (publicKey.Length < 2 || publicKey[0] != "ssh-ed25519") throw new InvalidOperationException("Public key fixture requires Ed25519");
    var hostToken = target.Port == 22 ? target.Host : $"[{target.Host}]:{target.Port}";
    await File.WriteAllTextAsync(paths.KnownHostsPath, $"{hostToken} {publicKey[0]} {publicKey[1]}\n");
    await Reject("changed-host-key", target, "TRAFFIC_SSH_OPERATION_FAILED");
    File.Delete(paths.KnownHostsPath);
    await Reject("missing-trust", target, "TRAFFIC_SSH_TRUST_REQUIRED");
    await File.WriteAllBytesAsync(paths.KnownHostsPath, originalTrust);

    // Closed port and silent local TCP peer model failure without disabling the VM network.
    var closed = new TcpListener(IPAddress.Loopback, 0);
    closed.Start();
    var closedPort = ((IPEndPoint)closed.LocalEndpoint).Port;
    closed.Stop();
    await Reject("unreachable-endpoint", target with { Host = "127.0.0.1", Port = closedPort }, "TRAFFIC_SSH_OPERATION_FAILED");
    var silent = new TcpListener(IPAddress.Loopback, 0);
    silent.Start();
    try
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(1));
        var cancelled = false;
        try { await Execute(target with { Host = "127.0.0.1", Port = ((IPEndPoint)silent.LocalEndpoint).Port }, cancellation.Token); }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            Console.WriteLine("PASS cancelled-silent-peer: cancellation propagated");
            cancelled = true;
        }
        if (!cancelled) throw new InvalidOperationException("Silent SSH peer did not propagate cancellation");
    }
    finally { silent.Stop(); }
    await Accept();
    if (!File.ReadAllBytes(trustedPath).SequenceEqual(originalTrust) ||
        !SHA256.HashData(File.ReadAllBytes(target.PrivateKeyPath)).SequenceEqual(originalKeyHash))
        throw new InvalidOperationException("Existing SSH identity or trust changed");
    Console.WriteLine("PASS final-trust control; existing key and trust unchanged");
}
finally
{
    // Only this freshly created scratch tree is removed; no user source or evidence paths.
    if (Path.GetFileName(scratch).StartsWith("ssh-acceptance-", StringComparison.Ordinal) &&
        Path.GetDirectoryName(scratch) == Path.GetFullPath(args[4])) Directory.Delete(scratch, true);
}
