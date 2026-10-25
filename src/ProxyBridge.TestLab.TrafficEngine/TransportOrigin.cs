using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace ProxyBridge.TestLab.TrafficEngine;

internal sealed class TransportOrigin(byte[] secret, SessionRegistry registry, int maximumConnections)
{
    internal const int DatagramBuffer = 4 * 1024 * 1024;
    private int active;
    internal int Active => Volatile.Read(ref active);
    internal int EffectiveReceiveBuffer { get; private set; }

    internal async Task Tcp(Socket socket, CancellationToken stopping)
    {
        using (socket)
        using (var stream = new ReadBufferedDuplexStream(new NetworkStream(socket, ownsSocket: false)))
        using (var deadline = CancellationTokenSource.CreateLinkedTokenSource(stopping))
        {
            if (Interlocked.Increment(ref active) > maximumConnections) { Interlocked.Decrement(ref active); return; }
            Session? session = null; var admitted = false;
            try
            {
                socket.NoDelay = true; deadline.CancelAfter(TimeSpan.FromSeconds(10));
                var token = deadline.Token;
                var request = await Wire.ReadJson(stream, token);
                var run = Wire.Id(request, "run_id"); var flow = Wire.Id(request, "flow_id");
                var task = request["task"]?.GetValue<string>(); var seconds = request["seconds"]?.GetValue<double>() ?? double.NaN;
                var rate = request["rate_bytes_per_second"]?.GetValue<double>() ?? 0;
                if (request["version"]?.GetValue<int>() != 1 || task is not ("echo" or "hold" or "upload" or "download" or "duplex") ||
                    !double.IsFinite(seconds) || seconds is < .05 or > 259200 || !double.IsFinite(rate) || rate is < 0 or > 1e10 || request.ContainsKey("metrics_keepalive"))
                    throw new InvalidDataException("TRAFFIC_REQUEST_INVALID");
                var raw = Wire.Json(request); var challenge = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32));
                var context = Wire.Join(Encoding.ASCII.GetBytes(challenge), raw);
                await Wire.WriteJson(stream, new() { ["challenge"] = challenge }, token);
                var authentication = await Wire.ReadJson(stream, token, 256);
                Wire.Verify(secret, "client:", authentication["proof"]?.GetValue<string>(), context);
                var peer = (IPEndPoint)socket.RemoteEndPoint!;
                var ready = new JsonObject { ["ready"] = true, ["flow_id"] = flow, ["peer"] = Peer(peer), ["version"] = 1 };
                ready["proof"] = Wire.Mac(secret, "server:", context, Wire.Json(ready));
                await Wire.WriteJson(stream, ready, token);
                session = registry.Get(run);
                lock (session.Sync)
                {
                    session.Accepted++; session.Active++; session.Peak = Math.Max(session.Peak, session.Active); admitted = true;
                    if (session.Routes.Count < 256) session.Routes.Add(new() { ["flow_id"] = flow, ["peer"] = Peer(peer) });
                }
                deadline.CancelAfter(TimeSpan.FromSeconds(seconds + 20));
                var started = Stopwatch.GetTimestamp();
                var transfer = new Transfer(session);
                await Exchange(stream, task, seconds, rate, transfer, token);
                lock (session.Sync) session.Completed++;
                var result = new JsonObject { ["complete"] = true, ["flow_id"] = flow,
                    ["elapsed_seconds"] = Math.Round(Stopwatch.GetElapsedTime(started).TotalSeconds, 6),
                    ["rx_bytes"] = transfer.Rx, ["tx_bytes"] = transfer.Tx,
                    ["rx_sha256"] = transfer.RxHash, ["tx_sha256"] = transfer.TxHash };
                result["proof"] = Wire.Mac(secret, "result:", context, Wire.Json(result));
                await Wire.WriteJson(stream, result, token);
            }
            catch (Exception error) when (error is InvalidDataException or IOException or SocketException or OperationCanceledException or System.Text.Json.JsonException or InvalidOperationException or FormatException or OverflowException)
            { if (session is not null) lock (session.Sync) session.Errors++; }
            finally { if (admitted) lock (session!.Sync) session.Active--; socket.Dispose(); Interlocked.Decrement(ref active); }
        }
    }
    private sealed class Transfer(Session session)
    {
        internal long Rx, Tx;
        internal string? RxHash, TxHash;
        internal void Received(int count) { Rx += count; lock (session.Sync) session.Rx += count; }
        internal void Sent(int count) { Tx += count; lock (session.Sync) session.Tx += count; }
    }
    private static async Task Exchange(Stream stream, string task, double seconds, double rate, Transfer transfer, CancellationToken token)
    {
        using var pair = CancellationTokenSource.CreateLinkedTokenSource(token);
        token = pair.Token;
        var started = Stopwatch.GetTimestamp();
        async Task Receive(bool echo)
        {
            var buffer = new byte[Wire.Chunk]; ulong offset = 0; using var digest = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            while (true)
            {
                var header = await Wire.ReadFrame(stream, token);
                if (header.Offset != offset) throw new InvalidDataException("TRAFFIC_SEQUENCE_INVALID");
                if (header.Size == 0) break;
                await stream.ReadExactlyAsync(buffer.AsMemory(0, header.Size), token);
                Wire.Validate(buffer.AsSpan(0, header.Size), offset); digest.AppendData(buffer, 0, header.Size);
                transfer.Received(header.Size);
                if (echo)
                {
                    await stream.WriteAsync(Wire.Frame(offset, header.Size), token);
                    await stream.WriteAsync(buffer.AsMemory(0, header.Size), token); transfer.Sent(header.Size);
                }
                offset += (uint)header.Size;
            }
            transfer.RxHash = Convert.ToHexStringLower(digest.GetHashAndReset());
            if (echo) { await stream.WriteAsync(Wire.Frame(offset, 0), token); transfer.TxHash = transfer.RxHash; }
        }
        async Task Send()
        {
            var buffer = new byte[Wire.Chunk]; Wire.Fill(buffer, 0); ulong offset = 0;
            using var digest = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            while (Stopwatch.GetElapsedTime(started).TotalSeconds < seconds)
            {
                await stream.WriteAsync(Wire.Frame(offset, buffer.Length), token); await stream.WriteAsync(buffer, token);
                digest.AppendData(buffer); offset += (uint)buffer.Length; transfer.Sent(buffer.Length);
                if (rate > 0)
                {
                    var delay = offset / rate - Stopwatch.GetElapsedTime(started).TotalSeconds;
                    if (delay > 0) await Task.Delay(TimeSpan.FromSeconds(Math.Min(delay, .2)), token);
                }
            }
            await stream.WriteAsync(Wire.Frame(offset, 0), token); transfer.TxHash = Convert.ToHexStringLower(digest.GetHashAndReset());
        }
        if (task is "echo" or "hold") await Receive(true);
        else if (task == "upload") await Receive(false);
        else if (task == "download") await Send();
        else
        {
            var receiver = Receive(false); var sender = Send();
            var first = await Task.WhenAny(receiver, sender); if (first.IsFaulted || first.IsCanceled) pair.Cancel();
            await Task.WhenAll(receiver, sender);
        }
    }
    internal Socket BindUdp(IPAddress bind, int port)
    {
        var socket = new Socket(bind.AddressFamily, SocketType.Dgram, ProtocolType.Udp);
        try
        {
            socket.ReceiveBufferSize = DatagramBuffer; socket.SendBufferSize = DatagramBuffer;
            if (socket.ReceiveBufferSize < DatagramBuffer) throw new InvalidDataException("TRAFFIC_ORIGIN_UDP_RECEIVE_BUFFER_INSUFFICIENT");
            EffectiveReceiveBuffer = socket.ReceiveBufferSize; socket.Bind(new IPEndPoint(bind, port)); return socket;
        }
        catch { socket.Dispose(); throw; }
    }
    internal async Task Udp(Socket socket, CancellationToken token)
    {
        var buffer = new byte[65535]; EndPoint source = new IPEndPoint(socket.AddressFamily == AddressFamily.InterNetwork ? IPAddress.Any : IPAddress.IPv6Any, 0);
        while (!token.IsCancellationRequested)
        {
            SocketReceiveFromResult received;
            try { received = await socket.ReceiveFromAsync(buffer, SocketFlags.None, source, token); }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { break; }
            try
            {
                var packet = Reply(buffer.AsSpan(0, received.ReceivedBytes), (IPEndPoint)received.RemoteEndPoint, out var session, out var payloadBytes);
                try { await socket.SendToAsync(packet, SocketFlags.None, received.RemoteEndPoint, token); lock (session.Sync) session.Tx += payloadBytes; }
                catch (SocketException) { lock (session.Sync) session.UdpReplyErrors++; }
            }
            catch (Exception error) when (error is InvalidDataException or IOException or System.Text.Json.JsonException or InvalidOperationException or FormatException or OverflowException or ArgumentException)
            { /* Invalid traffic never causes a reply or terminates the shared receiver. */ }
        }
    }
    internal byte[] Reply(ReadOnlySpan<byte> packet, IPEndPoint peer, out Session session, out int payloadBytes)
    {
        var split = packet.IndexOf((byte)10);
        if (split is < 0 or > 2048 || packet.Length - split - 1 > 60000) throw new InvalidDataException("TRAFFIC_DATAGRAM_INVALID");
        var request = JsonNode.Parse(packet[..split]) as JsonObject ?? throw new InvalidDataException("TRAFFIC_DATAGRAM_INVALID");
        var proof = Wire.TakeProof(request); var run = Wire.Id(request, "run_id"); var flow = Wire.Id(request, "flow_id");
        if (request["version"]?.GetValue<int>() != 1 || request["sequence"] is not JsonValue sequenceValue || !sequenceValue.TryGetValue<long>(out var sequence) || sequence < 0)
            throw new InvalidDataException("TRAFFIC_DATAGRAM_INVALID");
        var payload = packet[(split + 1)..];
        Wire.Verify(secret, "udp-client:", proof, Wire.Json(request), payload.ToArray());
        Wire.Validate(payload, unchecked((ulong)sequence * (ulong)payload.Length));
        session = registry.Get(run); payloadBytes = payload.Length;
        lock (session.Sync)
        {
            if (!session.UdpFlows.Contains(flow) && session.UdpFlows.Count >= 4096) throw new InvalidDataException("TRAFFIC_UDP_FLOW_LIMIT");
            session.UdpFlows.Add(flow); session.UdpReceived++; session.Rx += payload.Length;
        }
        request["peer"] = Peer(peer);
        request["proof"] = Wire.Mac(secret, "udp-server:", Wire.Json(request), payload.ToArray());
        return Wire.Join(Wire.Json(request), new byte[] { 10 }, payload.ToArray());
    }
    internal static JsonArray Peer(IPEndPoint peer) => [peer.Address.ToString(), peer.Port];
}
