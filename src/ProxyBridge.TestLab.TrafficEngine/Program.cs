using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text.Json.Nodes;
using ProxyBridge.TestLab.TrafficEngine;

// Component host. It is intentionally not selected by the product runner until integration gates pass.
if (args.Length == 4 && args[0] == "--job" && args[2] == "--output")
{
    try
    {
        if (new FileInfo(args[1]).Length > 1024 * 1024) return 2;
        var job = JsonNode.Parse(await File.ReadAllBytesAsync(args[1])) as JsonObject ?? throw new InvalidDataException("TRAFFIC_JOB_INVALID");
        var result = await TransportWorker.Execute(job, CancellationToken.None);
        var target = Path.GetFullPath(args[3]); var temporary = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
        await File.WriteAllTextAsync(temporary, result.ToJsonString()); File.Move(temporary, target, overwrite: false);
        return result["complete"]!.GetValue<bool>() ? 0 : 1;
    }
    catch (Exception error) when (error is InvalidDataException or IOException or SocketException or InvalidOperationException or FormatException or System.Text.Json.JsonException or ArgumentException)
    { Console.Error.WriteLine("TRAFFIC_ENGINE_WORKER_FAILED"); return 2; }
}
if (args.Length != 2 || args[0] != "--config") return 2;
try
{
    var configuration = JsonNode.Parse(await File.ReadAllBytesAsync(args[1])) as JsonObject ?? throw new InvalidDataException("ENGINE_CONFIG_INVALID");
    var secret = Convert.FromHexString(configuration["secret"]!.GetValue<string>());
    var bind = IPAddress.Parse(configuration["bind"]!.GetValue<string>());
    if (secret.Length != 32 || !bind.Equals(IPAddress.Loopback)) throw new InvalidDataException("ENGINE_CONFIG_INVALID");
    var port = configuration["port"]!.GetValue<int>(); var stopPath = configuration["stop_path"]!.GetValue<string>();
    if (port is < 1024 or > 65535 || !Path.IsPathFullyQualified(stopPath)) throw new InvalidDataException("ENGINE_CONFIG_INVALID");
    var registry = new SessionRegistry(); var origin = new TransportOrigin(secret, registry, 2048);
    using var stopping = new CancellationTokenSource();
    Console.CancelKeyPress += (_, e) => { e.Cancel = true; stopping.Cancel(); };
    var workerOnly = configuration["worker_only"]?.GetValue<bool>() ?? false;
    var portMap = configuration["application_ports"] is JsonObject ports ? ports.ToDictionary(pair => pair.Key, pair => pair.Value!.GetValue<int>()) : new Dictionary<string, int>();
    if (portMap.Values.Any(value => value is < 1024 or > 65535)) throw new InvalidDataException("ENGINE_CONFIG_INVALID");
    var proxyPort = configuration["proxy_port"]?.GetValue<int>() ?? 0;
    if (proxyPort != 0 && (proxyPort is < 1024 or > 65535 || proxyPort == port)) throw new InvalidDataException("ENGINE_CONFIG_INVALID");
    var relay = !workerOnly && proxyPort != 0 ? new SocksRelay(secret, registry, port, portMap) : null;
    var pending = new ConcurrentDictionary<long, Task>(); long sequence = 0;
    var listeners = new List<TcpListener>(); var datagrams = new List<Socket>(); var tasks = new List<Task>();
    async Task WatchStop()
    {
        while (!stopping.IsCancellationRequested)
        {
            if (File.Exists(stopPath)) { stopping.Cancel(); return; }
            await Task.Delay(100, stopping.Token);
        }
    }
    async Task Accept(TcpListener listener, Func<Socket, CancellationToken, Task> handler)
    {
        while (!stopping.IsCancellationRequested)
        {
            var socket = await listener.AcceptSocketAsync(stopping.Token);
            var id = Interlocked.Increment(ref sequence); var task = handler(socket, stopping.Token);
            pending[id] = task;
            _ = task.ContinueWith(_ => { pending.TryRemove(id, out var ignored); }, TaskScheduler.Default);
        }
    }
    async Task DenyUnassociatedUdp(Socket socket)
    {
        var buffer = new byte[65535]; EndPoint any = new IPEndPoint(bind.AddressFamily == AddressFamily.InterNetwork ? IPAddress.Any : IPAddress.IPv6Any, 0);
        while (!stopping.IsCancellationRequested) await socket.ReceiveFromAsync(buffer, SocketFlags.None, any, stopping.Token);
    }
    void Listen(int number, Func<Socket, CancellationToken, Task> handler)
    { var listener = new TcpListener(bind, number); listener.Start(2048); listeners.Add(listener); tasks.Add(Accept(listener, handler)); }
    try
    {
        if (!workerOnly)
        {
            var udp = origin.BindUdp(bind, port); datagrams.Add(udp); tasks.Add(origin.Udp(udp, stopping.Token)); Listen(port, origin.Tcp);
            if (relay is not null)
            {
                Listen(proxyPort, relay.Tcp);
                var globalUdp = new Socket(bind.AddressFamily, SocketType.Dgram, ProtocolType.Udp); globalUdp.Bind(new IPEndPoint(bind, proxyPort)); datagrams.Add(globalUdp);
                // SOCKS UDP is accepted only on the authenticated association's advertised endpoint.
                tasks.Add(DenyUnassociatedUdp(globalUdp));
            }
        }
        var channel = new ControlChannel(secret, registry, origin, relay);
        tasks.Add(channel.Serve(stopping.Token));
        tasks.Add(WatchStop());
        Console.WriteLine($"TRAFFIC_ENGINE_READY origin={port} udp_buffer={origin.EffectiveReceiveBuffer} proxy={proxyPort} control={channel.Port} worker_only={workerOnly}");
        var first = await Task.WhenAny(tasks); await first;
    }
    catch (OperationCanceledException) when (stopping.IsCancellationRequested) { }
    finally
    {
        stopping.Cancel(); foreach (var listener in listeners) listener.Stop(); foreach (var socket in datagrams) socket.Dispose();
        try { await Task.WhenAll(tasks); } catch (OperationCanceledException) when (stopping.IsCancellationRequested) { }
        await Task.WhenAll(pending.Values).WaitAsync(TimeSpan.FromSeconds(5));
    }
    return 0;
}
catch (Exception error) when (error is InvalidDataException or IOException or SocketException or InvalidOperationException or FormatException or System.Text.Json.JsonException or ArgumentException or TimeoutException)
{
    Console.Error.WriteLine("TRAFFIC_ENGINE_COMPONENT_FAILED"); return 2;
}
