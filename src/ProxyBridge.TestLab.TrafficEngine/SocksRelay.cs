using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json.Nodes;

namespace ProxyBridge.TestLab.TrafficEngine;

internal sealed class SocksRelay(byte[] secret, SessionRegistry registry, int originPort, IReadOnlyDictionary<string, int> applicationPorts)
{
    private readonly ConcurrentDictionary<IPEndPoint, ApplicationConnection> applications = [];
    private readonly ConcurrentDictionary<IPEndPoint, Association> associations = [];
    private int active;
    private int quicRouteCount;
    private readonly ConcurrentDictionary<string, long> failures = [];
    internal JsonObject Diagnostics() { var result = new JsonObject(); foreach (var pair in failures) result[pair.Key] = pair.Value; return result; }
    private void Failure(string code) => failures.AddOrUpdate(code, 1, (_, count) => count + 1);
    private bool ReserveQuic() { if (Interlocked.Increment(ref quicRouteCount) <= 2048) return true; Interlocked.Decrement(ref quicRouteCount); return false; }
    private void ReleaseQuic() => Interlocked.Decrement(ref quicRouteCount);
    internal int Active => Volatile.Read(ref active);
    internal int Associations => associations.Count;
    private sealed class ApplicationConnection(string username)
    { internal readonly Lock Sync = new(); internal string Username = username; internal ProxyCounters? Counters; }
    private sealed class Association(string username, IPAddress clientIp, int clientPort, Socket ingress, Socket egress, QuicAccounting quic)
    {
        internal readonly Lock Sync = new();
        internal readonly string Username = username;
        internal readonly IPAddress ClientIp = clientIp;
        internal readonly int ClientPort = clientPort;
        internal readonly Socket Ingress = ingress, Egress = egress;
        internal IPEndPoint? Client;
        internal string? Run;
        internal readonly QuicAccounting Quic = quic;
    }
    internal void ObserveApplication(string run, string flow, IPEndPoint peer)
    {
        if (!applications.TryGetValue(peer, out var application)) return;
        lock (application.Sync)
        {
            if (application.Counters is not null || !Belongs(run, application.Username)) throw new InvalidDataException("SOCKS_APPLICATION_IDENTITY_INVALID");
            application.Counters = registry.Get(run).Proxy; var counters = application.Counters;
            lock (counters.Sync) { counters.TcpFlows++; counters.TcpActive++; counters.Fingerprint(flow, TransportOrigin.Peer(peer), false); Sample(counters, flow, peer); }
        }
    }
    internal void ObserveQuic(string run, string flow, IPEndPoint peer, int port, byte[] originalCid)
    {
        if (!associations.TryGetValue(peer, out var association)) return;
        lock (association.Sync)
        {
            var route = association.Quic.Connection(port, originalCid);
            if (!Belongs(run, association.Username) || route is null || route.Counters is not null) throw new InvalidDataException("SOCKS_QUIC_IDENTITY_INVALID");
            var counters = registry.Get(run).Proxy;
            lock (counters.Sync)
            {
                if (counters.UdpFlows.Count >= 4096 || !counters.UdpFlows.Add(flow)) throw new InvalidDataException("SOCKS_QUIC_IDENTITY_INVALID");
                counters.UdpSent += route.Sent; counters.UdpReceived += route.Received; counters.Fingerprint(flow, TransportOrigin.Peer(peer), true);
            }
            route.Counters = counters;
        }
    }
    internal void ObserveQuicCid(IPEndPoint peer, int port, byte[] originalCid, byte[] cid, bool retired)
    {
        if (associations.TryGetValue(peer, out var association)) lock (association.Sync) association.Quic.ServerCid(port, originalCid, cid, retired);
    }
    private static bool Belongs(string run, string username) => run == username || run.StartsWith(username + ".", StringComparison.Ordinal);
    private static void Sample(ProxyCounters counters, string flow, IPEndPoint peer)
    { if (counters.Samples.Count < 256) counters.Samples.Add(new JsonObject { ["flow_id"] = flow, ["origin_peer"] = TransportOrigin.Peer(peer) }); }
    internal async Task Tcp(Socket socket, CancellationToken stopping)
    {
        using (socket)
        using (var stream = new ReadBufferedDuplexStream(new NetworkStream(socket, ownsSocket: false)))
        using (var deadline = CancellationTokenSource.CreateLinkedTokenSource(stopping))
        {
            if (Interlocked.Increment(ref active) > 2048) { Interlocked.Decrement(ref active); return; }
            Socket? upstream = null; ApplicationConnection? application = null; IPEndPoint? applicationPeer = null; ProxyCounters? counters = null;
            var phase = "greeting";
            try
            {
                socket.NoDelay = true; deadline.CancelAfter(TimeSpan.FromSeconds(10)); var token = deadline.Token;
                var prefix = new byte[2]; await stream.ReadExactlyAsync(prefix, token); var methods = new byte[prefix[1]]; await stream.ReadExactlyAsync(methods, token);
                if (prefix[0] != 5 || !methods.Contains((byte)2)) { await stream.WriteAsync(new byte[] { 5, 255 }, token); return; }
                await stream.WriteAsync(new byte[] { 5, 2 }, token); await stream.ReadExactlyAsync(prefix, token);
                phase = "authentication";
                var usernameBytes = new byte[prefix[1]]; await stream.ReadExactlyAsync(usernameBytes, token); var length = new byte[1]; await stream.ReadExactlyAsync(length, token);
                var password = new byte[length[0]]; await stream.ReadExactlyAsync(password, token); var username = Encoding.ASCII.GetString(usernameBytes);
                try
                {
                    if (prefix[0] != 1 || usernameBytes.Any(value => value > 127)) throw new InvalidDataException("SOCKS_AUTH_FAILED");
                    Wire.Id(new JsonObject { ["username"] = username }, "username");
                    Wire.Verify(secret, "socks:", Encoding.ASCII.GetString(password), usernameBytes);
                }
                catch (InvalidDataException) { Failure("authentication:rejected"); await stream.WriteAsync(new byte[] { 1, 1 }, token); return; }
                await stream.WriteAsync(new byte[] { 1, 0 }, token);
                phase = "request";
                var command = new byte[3]; await stream.ReadExactlyAsync(command, token); var destination = await ReadAddress(stream, token);
                if (command[0] != 5 || command[2] != 0 || command[1] is not (1 or 3)) throw new InvalidDataException("SOCKS_REQUEST_INVALID");
                if (command[1] == 3)
                {
                    deadline.CancelAfter(TimeSpan.FromSeconds(259260));
                    phase = "association";
                    await Associate(socket, stream, username, destination.Port, token); return;
                }
                if (!destination.Address.Equals(IPAddress.Loopback) || destination.Port != originPort && !applicationPorts.Values.Contains(destination.Port))
                { await stream.WriteAsync(new byte[] { 5, 2, 0, 1, 0, 0, 0, 0, 0, 0 }, token); return; }
                upstream = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
                phase = "upstream-connect";
                await upstream.ConnectAsync(new IPEndPoint(IPAddress.Loopback, destination.Port), token); var peer = (IPEndPoint)upstream.LocalEndPoint!;
                using var originStream = new ReadBufferedDuplexStream(new NetworkStream(upstream, ownsSocket: false));
                if (destination.Port == originPort)
                {
                    // Reply first, then inspect only the controlled transport preface.
                    await stream.WriteAsync(Wire.Join(new byte[] { 5, 0, 0 }, TransportWorker.Address(peer.Address, peer.Port)), token);
                    var request = await Wire.ReadJson(stream, token); var run = Wire.Id(request, "run_id"); var flow = Wire.Id(request, "flow_id");
                    if (!Belongs(run, username)) throw new InvalidDataException("SOCKS_SESSION_ID_INVALID");
                    counters = registry.Get(run).Proxy;
                    lock (counters.Sync) { counters.TcpFlows++; counters.TcpActive++; counters.Fingerprint(flow, TransportOrigin.Peer(peer), false); Sample(counters, flow, peer); }
                    await Wire.WriteJson(originStream, request, token); var seconds = request["seconds"]?.GetValue<double>() ?? .05;
                    if (!double.IsFinite(seconds) || seconds is < .05 or > 259200) throw new InvalidDataException("SOCKS_DURATION_INVALID");
                    deadline.CancelAfter(TimeSpan.FromSeconds(seconds + 30));
                }
                else
                {
                    application = new(username); applicationPeer = peer;
                    if (!applications.TryAdd(peer, application)) throw new InvalidDataException("SOCKS_PEER_COLLISION");
                    await stream.WriteAsync(Wire.Join(new byte[] { 5, 0, 0 }, TransportWorker.Address(peer.Address, peer.Port)), token);
                    deadline.CancelAfter(TimeSpan.FromSeconds(155));
                }
                async Task Pump(Stream source, Stream sink, Socket target)
                {
                    var buffer = new byte[65536];
                    while (true)
                    {
                        var read = await source.ReadAsync(buffer, token);
                        if (read == 0) { try { target.Shutdown(SocketShutdown.Send); } catch (SocketException) { } return; }
                        await sink.WriteAsync(buffer.AsMemory(0, read), token);
                    }
                }
                var outgoing = Pump(stream, originStream, upstream); var incoming = Pump(originStream, stream, socket);
                phase = "relay";
                var first = await Task.WhenAny(outgoing, incoming); if (first.IsFaulted || first.IsCanceled) deadline.Cancel();
                await Task.WhenAll(outgoing, incoming);
                if (application is not null) lock (application.Sync) counters = application.Counters;
                if (counters is not null) lock (counters.Sync) counters.TcpFinished++;
            }
            catch (Exception error) when (error is InvalidDataException or IOException or SocketException or OperationCanceledException or System.Text.Json.JsonException or InvalidOperationException or FormatException)
            {
                Failure(phase + ":" + (error is SocketException network ? network.SocketErrorCode.ToString() : error.GetType().Name));
                if (application is not null) lock (application.Sync) counters = application.Counters;
                if (counters is not null) lock (counters.Sync) counters.TcpErrors++;
            }
            finally
            {
                deadline.Cancel(); upstream?.Dispose();
                if (applicationPeer is not null) applications.TryRemove(applicationPeer, out _);
                if (application is not null) lock (application.Sync) counters = application.Counters;
                if (counters is not null) lock (counters.Sync) counters.TcpActive--;
                socket.Dispose();
                Interlocked.Decrement(ref active);
            }
        }
    }
    private async Task Associate(Socket control, Stream stream, string username, int clientPort, CancellationToken token)
    {
        var client = (IPEndPoint)control.RemoteEndPoint!; var local = (IPEndPoint)control.LocalEndPoint!;
        using var ingress = new Socket(local.AddressFamily, SocketType.Dgram, ProtocolType.Udp) { ReceiveBufferSize = 256 * 1024, SendBufferSize = 256 * 1024 };
        using var egress = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp) { ReceiveBufferSize = 256 * 1024, SendBufferSize = 256 * 1024 };
        ingress.Bind(new IPEndPoint(local.Address, 0)); egress.Bind(new IPEndPoint(IPAddress.Loopback, 0));
        var peer = (IPEndPoint)egress.LocalEndPoint!; var relay = (IPEndPoint)ingress.LocalEndPoint!;
        var association = new Association(username, client.Address, clientPort, ingress, egress, new QuicAccounting(ReserveQuic, ReleaseQuic));
        if (!associations.TryAdd(peer, association)) throw new InvalidDataException("SOCKS_ASSOCIATION_COLLISION");
        using var owned = CancellationTokenSource.CreateLinkedTokenSource(token); var tasks = new List<Task>();
        try
        {
            await stream.WriteAsync(Wire.Join(new byte[] { 5, 0, 0 }, TransportWorker.Address(relay.Address, relay.Port)), token);
            tasks.Add(Ingress(association, owned.Token)); tasks.Add(Egress(association, owned.Token));
            tasks.Add(stream.ReadAsync(new byte[1], owned.Token).AsTask());
            var first = await Task.WhenAny(tasks); await first;
        }
        finally
        {
            owned.Cancel(); associations.TryRemove(peer, out _);
            try { await Task.WhenAll(tasks); } catch (OperationCanceledException) when (owned.IsCancellationRequested) { }
            finally { lock (association.Sync) association.Quic.Clear(); }
        }
    }
    private async Task Ingress(Association association, CancellationToken token)
    {
        var bytes = new byte[65535]; EndPoint any = new IPEndPoint(IPAddress.Any, 0);
        while (!token.IsCancellationRequested)
        {
            var received = await association.Ingress.ReceiveFromAsync(bytes, SocketFlags.None, any, token); var client = (IPEndPoint)received.RemoteEndPoint;
            try
            {
                var packet = Decode(bytes, received.ReceivedBytes); string? run = null;
                if (!packet.Destination.Address.Equals(IPAddress.Loopback) || packet.Destination.Port != originPort && !applicationPorts.Where(pair => pair.Key is "dns-udp" or "quic" or "http3").Any(pair => pair.Value == packet.Destination.Port)) continue;
                lock (association.Sync)
                {
                    if (!client.Address.Equals(association.ClientIp) || association.Client is not null && !client.Equals(association.Client) || association.ClientPort != 0 && client.Port != association.ClientPort) continue;
                    association.Client = client;
                    if (IsQuic(packet.Destination.Port))
                    {
                        var route = association.Quic.Packet(packet.Destination.Port, packet.Payload, false);
                        if (route.Counters is not null) lock (route.Counters.Sync) route.Counters.UdpSent++;
                    }
                    else
                    {
                        var header = packet.Destination.Port == originPort ? TransportHeader(packet.Payload) : DnsHeader(packet.Payload);
                        run = Wire.Id(header, "run_id"); var flow = Wire.Id(header, "flow_id"); if (!Belongs(run, association.Username)) continue;
                        var counters = registry.Get(run).Proxy;
                        lock (counters.Sync)
                        {
                            if (!counters.UdpFlows.Contains(flow))
                            {
                                if (counters.UdpFlows.Count >= 4096) continue;
                                counters.UdpFlows.Add(flow); counters.Fingerprint(flow, TransportOrigin.Peer((IPEndPoint)association.Egress.LocalEndPoint!), true);
                            }
                            counters.UdpSent++;
                        }
                        association.Run = run;
                    }
                }
                await association.Egress.SendToAsync(packet.Payload, SocketFlags.None, new IPEndPoint(IPAddress.Loopback, packet.Destination.Port), token);
            }
            catch (Exception error) when (error is InvalidDataException or System.Text.Json.JsonException or InvalidOperationException or FormatException or ArgumentException or SocketException) { }
        }
    }
    private async Task Egress(Association association, CancellationToken token)
    {
        var bytes = new byte[65535]; EndPoint any = new IPEndPoint(IPAddress.Any, 0);
        while (!token.IsCancellationRequested)
        {
            var received = await association.Egress.ReceiveFromAsync(bytes, SocketFlags.None, any, token); var peer = (IPEndPoint)received.RemoteEndPoint;
            try
            {
                if (!peer.Address.Equals(IPAddress.Loopback) || peer.Port != originPort && !applicationPorts.Where(pair => pair.Key is "dns-udp" or "quic" or "http3").Any(pair => pair.Value == peer.Port)) continue;
                IPEndPoint? target;
                lock (association.Sync)
                {
                    target = association.Client; if (target is null) continue;
                    if (IsQuic(peer.Port))
                    {
                        var route = association.Quic.Packet(peer.Port, bytes.AsSpan(0, received.ReceivedBytes), true);
                        if (route.Counters is not null) lock (route.Counters.Sync) route.Counters.UdpReceived++;
                    }
                    else
                    {
                        var run = peer.Port == originPort ? Wire.Id(TransportHeader(bytes.AsSpan(0, received.ReceivedBytes)), "run_id") : association.Run;
                        if (run is null || !Belongs(run, association.Username)) continue;
                        var counters = registry.Get(run).Proxy; lock (counters.Sync) counters.UdpReceived++;
                    }
                }
                var packet = Wire.Join(new byte[] { 0, 0, 0 }, TransportWorker.Address(IPAddress.Loopback, peer.Port), bytes.AsMemory(0, received.ReceivedBytes));
                await association.Ingress.SendToAsync(packet, SocketFlags.None, target, token);
            }
            catch (Exception error) when (error is InvalidDataException or System.Text.Json.JsonException or InvalidOperationException or FormatException or ArgumentException or SocketException) { }
        }
    }
    private bool IsQuic(int port) => applicationPorts.Any(pair => pair.Value == port && pair.Key is "quic" or "http3");
    private static JsonObject TransportHeader(ReadOnlySpan<byte> payload)
    { var split = payload.IndexOf((byte)10); if (split is < 0 or > 2048) throw new InvalidDataException("SOCKS_DATAGRAM_INVALID"); return JsonNode.Parse(payload[..split]) as JsonObject ?? throw new InvalidDataException("SOCKS_DATAGRAM_INVALID"); }
    private static (IPEndPoint Destination, byte[] Payload) Decode(byte[] bytes, int length)
    {
        var packet = bytes.AsSpan(0, length); if (length < 10 || packet[0] != 0 || packet[1] != 0 || packet[2] != 0 || packet[3] is not (1 or 4)) throw new InvalidDataException("SOCKS_DATAGRAM_INVALID");
        var size = packet[3] == 1 ? 4 : 16; if (length < size + 6) throw new InvalidDataException("SOCKS_DATAGRAM_INVALID");
        return (new IPEndPoint(new IPAddress(packet.Slice(4, size)), BinaryPrimitives.ReadUInt16BigEndian(packet.Slice(4 + size, 2))), packet[(size + 6)..].ToArray());
    }
    private static async Task<IPEndPoint> ReadAddress(Stream stream, CancellationToken token)
    {
        var kind = new byte[1]; await stream.ReadExactlyAsync(kind, token); if (kind[0] is not (1 or 4)) throw new InvalidDataException("SOCKS_ADDRESS_INVALID");
        var bytes = new byte[kind[0] == 1 ? 6 : 18]; await stream.ReadExactlyAsync(bytes, token);
        return new IPEndPoint(new IPAddress(bytes.AsSpan(0, bytes.Length - 2)), BinaryPrimitives.ReadUInt16BigEndian(bytes.AsSpan(bytes.Length - 2)));
    }
    private JsonObject DnsHeader(ReadOnlySpan<byte> packet)
    {
        if (packet.Length is < 17 or > 512 || BinaryPrimitives.ReadUInt16BigEndian(packet[2..]) is not (0 or 256) ||
            !packet.Slice(4, 8).SequenceEqual(new byte[] { 0, 1, 0, 0, 0, 0, 0, 0 })) throw new InvalidDataException("APPLICATION_DNS_HEADER_INVALID");
        var labels = new List<string>(); var offset = 12;
        while (true)
        {
            if (offset >= packet.Length) throw new InvalidDataException("APPLICATION_DNS_NAME_INVALID");
            var size = packet[offset++]; if (size == 0) break;
            if (size > 63 || offset + size > packet.Length || labels.Count >= 7 || packet.Slice(offset, size).ContainsAnyInRange((byte)128, byte.MaxValue)) throw new InvalidDataException("APPLICATION_DNS_NAME_INVALID");
            labels.Add(Encoding.ASCII.GetString(packet.Slice(offset, size))); offset += size;
        }
        if (labels.Count != 7 || labels[5] != "pb" || labels[6] != "test" || !(packet[offset..].SequenceEqual(new byte[] { 0, 1, 0, 1 }) || packet[offset..].SequenceEqual(new byte[] { 0, 16, 0, 1 })))
            throw new InvalidDataException("APPLICATION_DNS_QUESTION_INVALID");
        var run = registry.FindTag(labels[0]) ?? throw new InvalidDataException("APPLICATION_DNS_SESSION_UNKNOWN");
        var sequence = long.Parse(labels[2], System.Globalization.NumberStyles.HexNumber, System.Globalization.CultureInfo.InvariantCulture);
        if (sequence is < 0 or >= (1L << 48)) throw new InvalidDataException("APPLICATION_SEQUENCE_INVALID");
        var name = $"{labels[0]}.{labels[1]}.{sequence:x}.pb.test";
        var digest = System.Security.Cryptography.SHA256.HashData(Wire.Json(new JsonObject { ["query_name"] = name, ["query_type"] = packet[offset + 1] == 16 ? "TXT" : "A" }));
        var header = new JsonObject { ["application"] = "dns", ["run_id"] = run, ["flow_id"] = labels[1], ["sequence"] = sequence, ["payload_sha256"] = Convert.ToHexStringLower(digest) };
        Wire.Id(header, "flow_id"); Wire.Verify(secret, "application-request:", labels[3] + labels[4], Wire.Json(header)); return header;
    }
}
