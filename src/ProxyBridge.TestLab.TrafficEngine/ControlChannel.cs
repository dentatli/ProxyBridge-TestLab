using System.Collections.Concurrent;
using System.Net.Sockets;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace ProxyBridge.TestLab.TrafficEngine;

internal sealed class ControlChannel(byte[] secret, SessionRegistry sessions, TransportOrigin origin, SocksRelay? relay, KernelResources kernel)
{
    private readonly ConcurrentDictionary<long, Task> pending = [];
    private readonly HashSet<string> seen = [];
    private readonly Queue<string> replay = [];
    private readonly Lock replayLock = new();
    private long sequence;
    private int activeJobs;
    private readonly TcpListener listener = new(IPAddress.Loopback, 0);
    internal int Port => ((IPEndPoint)listener.LocalEndpoint).Port;
    internal async Task Serve(CancellationToken stopping)
    {
        listener.Start(64);
        try
        {
            while (!stopping.IsCancellationRequested)
            {
                var socket = await listener.AcceptSocketAsync(stopping);
                if (pending.Count >= 64) { socket.Dispose(); continue; }
                socket.NoDelay = true;
                var id = Interlocked.Increment(ref sequence); var task = Request(socket, stopping); pending[id] = task;
                _ = task.ContinueWith(_ => pending.TryRemove(id, out var ignored), TaskScheduler.Default);
            }
        }
        finally { listener.Stop(); await Task.WhenAll(pending.Values).WaitAsync(TimeSpan.FromSeconds(5)); }
    }
    private async Task Request(Socket socket, CancellationToken stopping)
    {
        using (socket)
        using (var deadline = CancellationTokenSource.CreateLinkedTokenSource(stopping))
        {
            try
            {
                deadline.CancelAfter(TimeSpan.FromSeconds(10));
                using var stream = new ReadBufferedDuplexStream(new NetworkStream(socket, ownsSocket:false));
                var envelope = await Wire.ReadJson(stream, deadline.Token, 2 * 1024 * 1024); var nonce = envelope["nonce"]?.GetValue<string>() ?? "";
                if (nonce.Length != 32 || !nonce.All(Uri.IsHexDigit)) throw new InvalidDataException("ENGINE_CONTROL_NONCE_INVALID");
                var body = Convert.FromBase64String(envelope["body"]?.GetValue<string>() ?? throw new InvalidDataException("ENGINE_CONTROL_INVALID")); if (body.Length > 1024 * 1024) throw new InvalidDataException("ENGINE_CONTROL_LIMIT");
                Wire.Verify(secret, "engine-control-request:", envelope["proof"]?.GetValue<string>(), Encoding.ASCII.GetBytes(nonce), body);
                lock (replayLock)
                {
                    if (!seen.Add(nonce)) throw new InvalidDataException("ENGINE_CONTROL_REPLAY");
                    replay.Enqueue(nonce); if (replay.Count > 4096) seen.Remove(replay.Dequeue());
                }
                var request = JsonNode.Parse(body) as JsonObject ?? throw new InvalidDataException("ENGINE_CONTROL_INVALID");
                JsonObject response;
                if (request["operation"]?.GetValue<string>() == "worker")
                {
                    var job = request["job"] as JsonObject ?? throw new InvalidDataException("TRAFFIC_JOB_INVALID");
                    if (!CryptographicOperations.FixedTimeEquals(Convert.FromHexString(job["secret"]?.GetValue<string>() ?? ""), secret) || !IPAddress.TryParse(job["host"]?.GetValue<string>(), out var workerAddress) || !workerAddress.Equals(IPAddress.Loopback)) throw new InvalidDataException("TRAFFIC_JOB_INVALID");
                    var seconds = job["seconds"]?.GetValue<double>() ?? double.NaN; if (!double.IsFinite(seconds) || seconds is < .05 or > 259200) throw new InvalidDataException("TRAFFIC_JOB_INVALID");
                    deadline.CancelAfter(TimeSpan.FromSeconds(seconds + 25));
                    Interlocked.Increment(ref activeJobs);
                    try { response = await TransportWorker.Execute(job, deadline.Token); }
                    finally { Interlocked.Decrement(ref activeJobs); }
                }
                else response = Observe(request);
                var raw = Encoding.UTF8.GetBytes(response.ToJsonString());
                if (raw.Length > 16 * 1024 * 1024) throw new InvalidDataException("ENGINE_CONTROL_RESULT_LIMIT");
                await Wire.WriteJson(stream, new() { ["nonce"] = nonce, ["body"] = Convert.ToBase64String(raw),
                    ["proof"] = Wire.Mac(secret, "engine-control-response:", Encoding.ASCII.GetBytes(nonce), raw) }, deadline.Token);
            }
            catch (Exception error) when (error is InvalidDataException or IOException or OperationCanceledException or InvalidOperationException or System.Text.Json.JsonException or FormatException or ArgumentException)
            { /* A failed authenticated control request has no usable response and never becomes evidence. */ }
        }
    }
    private JsonObject Observe(JsonObject request)
    {
        var operation = request["operation"]?.GetValue<string>(); var run = Wire.Id(request, "run_id");
        if (operation == "kernel-start") return kernel.Start(request["driver"]!.GetValue<string>(), request["driver_sha256"]!.GetValue<string>());
        if (operation == "kernel-begin") return kernel.Begin(Wire.Id(request,"phase_id"), Wire.Id(request,"phase"));
        if (operation == "kernel-end") return kernel.End();
        if (operation == "kernel-poll") return kernel.Poll();
        if (operation == "kernel-stop") return kernel.Stop();
        if (operation == "snapshot")
        {
            var session = sessions.Get(run); var result = session.Snapshot(); result["proxy"] = session.Proxy.Snapshot();
            result["origin_udp_receive_buffer"] = new JsonObject { ["requested_bytes"] = TransportOrigin.DatagramBuffer, ["effective_bytes"] = origin.EffectiveReceiveBuffer };
            result["native_origin_connections"] = origin.Active; result["proxy_connections"] = relay?.Active ?? 0;
            result["worker_jobs_active"] = Volatile.Read(ref activeJobs); result["kernel_session_active"] = kernel.Active;
            result["proxy_udp_associations"] = relay?.Associations ?? 0; result["proxy_tcp_connections"] = (relay?.Active ?? 0) - (relay?.Associations ?? 0);
            result["relay_diagnostics"] = relay?.Diagnostics(); result["native_pid"] = Environment.ProcessId; result["engine"] = "csharp-transport-v1"; return result;
        }
        if (relay is null) throw new InvalidDataException("ENGINE_RELAY_UNAVAILABLE");
        var peer = request["peer"] as JsonArray ?? throw new InvalidDataException("ENGINE_PEER_INVALID");
        if (peer.Count != 2 || !IPAddress.TryParse(peer[0]?.GetValue<string>(), out var address) || !IPAddress.IsLoopback(address) || peer[1]?.GetValue<int>() is not (>= 1 and <= 65535)) throw new InvalidDataException("ENGINE_PEER_INVALID");
        var endpoint = new IPEndPoint(address, peer[1]!.GetValue<int>());
        if (operation == "application") relay.ObserveApplication(run, Wire.Id(request, "flow_id"), endpoint);
        else if (operation == "quic") relay.ObserveQuic(run, Wire.Id(request, "flow_id"), endpoint, request["port"]!.GetValue<int>(), Convert.FromHexString(request["original_cid"]!.GetValue<string>()));
        else if (operation == "quic_cid") relay.ObserveQuicCid(endpoint, request["port"]!.GetValue<int>(), Convert.FromHexString(request["original_cid"]!.GetValue<string>()), Convert.FromHexString(request["cid"]!.GetValue<string>()), request["retired"]!.GetValue<bool>());
        else throw new InvalidDataException("ENGINE_CONTROL_OPERATION_INVALID");
        return new() { ["complete"] = true };
    }
}
