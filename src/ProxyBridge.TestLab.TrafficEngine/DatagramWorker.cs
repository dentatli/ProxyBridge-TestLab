using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text.Json.Nodes;

namespace ProxyBridge.TestLab.TrafficEngine;

internal static partial class TransportWorker
{
    private sealed class DatagramState
    {
        internal readonly Lock Sync = new();
        internal readonly Dictionary<long, long> Pending = [];
        internal readonly Queue<(long Sequence, long Stamp)> Expiry = [];
        internal readonly HashSet<long> Seen = [];
        internal readonly Queue<long> Replay = [];
        internal readonly JsonArray Peers = [];
        internal readonly HashSet<string> Errors = [];
        internal readonly Dictionary<string, long> InvalidReasons = [];
        internal readonly Histogram Latency = new();
        internal long Sent, Received, Duplicates, Reordered, Invalid, Expired, SendErrors, LastSequence = -1, UnexpectedSources;
        internal JsonObject? FirstMismatch;
        internal void Expire(long now)
        {
            while (Expiry.TryPeek(out var item) && Stopwatch.GetElapsedTime(item.Stamp, now).TotalSeconds > 2)
            { Expiry.Dequeue(); if (Pending.Remove(item.Sequence)) Expired++; }
        }
    }
    private static async Task<JsonObject> Udp(JsonObject job, string flow, CancellationToken stopping)
    {
        await Task.Yield();
        var state = new DatagramState(); var address = IPAddress.Parse(job["host"]!.GetValue<string>());
        var destination = new IPEndPoint(address, job["port"]!.GetValue<int>()); var prefix = Array.Empty<byte>(); Socket? control = null;
        var secret = Convert.FromHexString(job["secret"]!.GetValue<string>()); var seconds = job["seconds"]!.GetValue<double>();
        var rate = job["rate_packets_per_second"]?.GetValue<double>() ?? 1000;
        if (!double.IsFinite(rate) || rate is < 0 or > 1000000) throw new InvalidDataException("TRAFFIC_RATE_INVALID");
        var size = job["message_bytes"]?.GetValue<int>() ?? 512; var connected = job["udp_connected"]?.GetValue<bool>() ?? true;
        var started = Stopwatch.GetTimestamp();
        var phase = "proxy-association";
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(stopping);
        try
        {
            if (job["test_proxy"] is JsonObject proxy)
            {
                control = new Socket(address.AddressFamily, SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
                using var setup = CancellationTokenSource.CreateLinkedTokenSource(stopping); setup.CancelAfter(TimeSpan.FromSeconds(10));
                destination = await Socks(control, job, proxy, true, setup.Token, progress => phase = progress);
                prefix = Wire.Join(new byte[] { 0, 0, 0 }, Address(address, job["port"]!.GetValue<int>()));
            }
            using var socket = new Socket(destination.AddressFamily, SocketType.Dgram, ProtocolType.Udp) { ReceiveBufferSize = TransportOrigin.DatagramBuffer };
            if (socket.ReceiveBufferSize < TransportOrigin.DatagramBuffer) throw new InvalidDataException("TRAFFIC_WORKER_UDP_RECEIVE_BUFFER_INSUFFICIENT");
            if (connected) await socket.ConnectAsync(destination, stopping); else socket.Bind(new IPEndPoint(address.AddressFamily == AddressFamily.InterNetwork ? IPAddress.Any : IPAddress.IPv6Any, 0));
            started = Stopwatch.GetTimestamp(); deadline.CancelAfter(TimeSpan.FromSeconds(seconds + 2.1));
            phase = "workload";
            async Task Send()
            {
                long sequence = 0; double nextSend = 0;
                while (Stopwatch.GetElapsedTime(started).TotalSeconds < seconds && !Cancelled(job) && !stopping.IsCancellationRequested)
                {
                    var now = Stopwatch.GetTimestamp(); bool full;
                    lock (state.Sync) { state.Expire(now); full = state.Pending.Count >= 8192; }
                    if (full) { await Task.Delay(1, deadline.Token); continue; }
                    var payload = new byte[size]; Wire.Fill(payload, unchecked((ulong)sequence * (ulong)size));
                    var request = new JsonObject { ["version"] = 1, ["run_id"] = job["run_id"]!.DeepClone(), ["flow_id"] = flow, ["sequence"] = sequence };
                    request["proof"] = Wire.Mac(secret, "udp-client:", Wire.Json(request), payload);
                    var packet = Wire.Join(prefix, Wire.Json(request), new byte[] { 10 }, payload); var stamp = Stopwatch.GetTimestamp();
                    lock (state.Sync) { state.Pending.Add(sequence, stamp); state.Expiry.Enqueue((sequence, stamp)); }
                    try
                    {
                        var count = connected ? await socket.SendAsync(packet, SocketFlags.None, deadline.Token) : await socket.SendToAsync(packet, SocketFlags.None, destination, deadline.Token);
                        if (count != packet.Length) throw new SocketException((int)SocketError.MessageSize);
                        lock (state.Sync) state.Sent++;
                    }
                    catch (SocketException) { lock (state.Sync) { state.Pending.Remove(sequence); state.SendErrors++; } }
                    sequence++;
                    if ((sequence & 31) == 0) await Task.Yield();
                    // One schedule per flow; send cadence never catches up with a burst after a stall.
                    if (rate > 0)
                    {
                        var elapsed = Stopwatch.GetElapsedTime(started).TotalSeconds;
                        nextSend = Math.Max(nextSend + 1 / rate, Stopwatch.GetElapsedTime(started, now).TotalSeconds);
                        var delay = nextSend - elapsed;
                        if (delay > 0) await Task.Delay(TimeSpan.FromSeconds(delay), deadline.Token);
                    }
                }
            }
            async Task Receive()
            {
                var buffer = new byte[65535]; EndPoint any = new IPEndPoint(destination.AddressFamily == AddressFamily.InterNetwork ? IPAddress.Any : IPAddress.IPv6Any, 0);
                while (!deadline.IsCancellationRequested && !Cancelled(job))
                {
                    var read = await socket.ReceiveFromAsync(buffer, SocketFlags.None, any, deadline.Token); var now = Stopwatch.GetTimestamp();
                    if (!read.RemoteEndPoint.Equals(destination))
                    {
                        lock (state.Sync)
                        {
                            state.UnexpectedSources++; state.Errors.Add("TRAFFIC_UDP_SOURCE_INVALID");
                            state.FirstMismatch ??= new() { ["expected"] = TransportOrigin.Peer(destination), ["actual"] = TransportOrigin.Peer((IPEndPoint)read.RemoteEndPoint), ["phase"] = "udp-response" };
                        }
                        continue;
                    }
                    try
                    {
                        var reply = ReadDatagram(buffer, read.ReceivedBytes, prefix.Length > 0, address, job["port"]!.GetValue<int>());
                        var response = reply.Header; var proof = Wire.TakeProof(response);
                        Wire.Verify(secret, "udp-server:", proof, Wire.Json(response), reply.Payload);
                        if (response["run_id"]?.GetValue<string>() != job["run_id"]!.GetValue<string>()) throw new InvalidDataException("TRAFFIC_DATAGRAM_RUN_MISMATCH");
                        if (response["flow_id"]?.GetValue<string>() != flow) throw new InvalidDataException("TRAFFIC_DATAGRAM_FLOW_MISMATCH");
                        if (response["sequence"] is not JsonValue value || !value.TryGetValue<long>(out var sequence) || sequence < 0 || reply.Payload.Length != size)
                            throw new InvalidDataException("TRAFFIC_DATAGRAM_MALFORMED");
                        try { Wire.Validate(reply.Payload, unchecked((ulong)sequence * (ulong)size)); }
                        catch (InvalidDataException) { throw new InvalidDataException("TRAFFIC_DATAGRAM_PAYLOAD_MISMATCH"); }
                        if (response["peer"] is not JsonArray { Count: 2 }) throw new InvalidDataException("TRAFFIC_DATAGRAM_MALFORMED");
                        lock (state.Sync)
                        {
                            state.Expire(now);
                            if (state.Seen.Contains(sequence)) state.Duplicates++;
                            else if (state.Pending.Remove(sequence, out var stamp))
                            {
                                state.Received++; state.Latency.Add(Stopwatch.GetElapsedTime(stamp, now).TotalMilliseconds);
                                if (sequence < state.LastSequence) state.Reordered++; state.LastSequence = Math.Max(sequence, state.LastSequence);
                                state.Seen.Add(sequence); state.Replay.Enqueue(sequence); if (state.Replay.Count > 16384) state.Seen.Remove(state.Replay.Dequeue());
                                if (state.Peers.Count < 16) state.Peers.Add(response["peer"]!.DeepClone());
                            }
                            else state.Expired++;
                        }
                    }
                    catch (Exception error) when (error is InvalidDataException or System.Text.Json.JsonException or InvalidOperationException or FormatException or OverflowException or ArgumentException)
                    {
                        var code = error is InvalidDataException && error.Message is "TRAFFIC_AUTHENTICATION_FAILED" or "TRAFFIC_DATAGRAM_RUN_MISMATCH" or "TRAFFIC_DATAGRAM_FLOW_MISMATCH" or "TRAFFIC_DATAGRAM_PAYLOAD_MISMATCH" ? error.Message : "TRAFFIC_DATAGRAM_MALFORMED";
                        lock (state.Sync) { state.Invalid++; state.InvalidReasons[code] = state.InvalidReasons.GetValueOrDefault(code) + 1; }
                    }
                }
            }
            var receiver = Receive();
            try
            {
                await Send();
                while (!deadline.IsCancellationRequested && !Cancelled(job))
                {
                    lock (state.Sync) { state.Expire(Stopwatch.GetTimestamp()); if (state.Pending.Count == 0) break; }
                    if (receiver.IsCompleted) await receiver;
                    await Task.Delay(1, deadline.Token);
                }
            }
            finally
            {
                deadline.Cancel();
                try { await receiver; } catch (OperationCanceledException) when (deadline.IsCancellationRequested) { }
            }
        }
        catch (OperationCanceledException) when (phase == "workload" && deadline.IsCancellationRequested && !stopping.IsCancellationRequested && !Cancelled(job)) { /* Measured drain deadline; losses remain losses. */ }
        catch (Exception error) when (error is InvalidDataException or IOException or SocketException or OperationCanceledException or System.Text.Json.JsonException or InvalidOperationException or FormatException)
        { lock (state.Sync) state.Errors.Add(error is InvalidDataException ? error.Message : phase.StartsWith("proxy-", StringComparison.Ordinal) ? "SOCKS_UDP_ASSOCIATION_FAILED" : "UDP_TRANSPORT_FAILED"); }
        finally { control?.Dispose(); }
        var elapsedSeconds = Stopwatch.GetElapsedTime(started).TotalSeconds; var reasons = new JsonObject(); foreach (var (key, count) in state.InvalidReasons) reasons[key] = count;
        return new() { ["flow_id"] = flow, ["sent"] = state.Sent, ["received"] = state.Received, ["duplicates"] = state.Duplicates,
            ["reordered"] = state.Reordered, ["invalid"] = state.Invalid, ["expired"] = state.Expired, ["send_errors"] = state.SendErrors,
            ["errors"] = new JsonArray(state.Errors.Select(code => JsonValue.Create(code)).ToArray()), ["invalid_reasons"] = reasons,
            ["elapsed_seconds"] = elapsedSeconds, ["loss"] = state.Sent - state.Received,
            ["loss_fraction"] = state.Sent > 0 ? (double)(state.Sent - state.Received) / state.Sent : null,
            ["loss_definition"] = "authenticated-replies-not-received-within-2s-deadline", ["achieved_send_packets_per_second"] = state.Sent / seconds,
            ["received_packets_per_second"] = state.Received / elapsedSeconds, ["peer_observed_by_origin"] = state.Peers,
            ["latency"] = state.Latency.View(), ["unexpected_source_packets"] = state.UnexpectedSources, ["first_source_mismatch"] = state.FirstMismatch,
            ["complete"] = !Cancelled(job) && !stopping.IsCancellationRequested && state.Errors.Count == 0 && state.Invalid == 0 && state.Received > 0,
            ["failure_phase"] = state.Errors.Count > 0 ? phase : null,
            ["cancelled"] = Cancelled(job) || stopping.IsCancellationRequested };
    }
    private static (JsonObject Header, byte[] Payload) ReadDatagram(byte[] bytes, int length, bool socks, IPAddress origin, int port)
    {
        var packet = bytes.AsSpan(0, length);
        if (socks)
        {
            if (packet.Length < 10 || packet[0] != 0 || packet[1] != 0 || packet[2] != 0 || packet[3] is not (1 or 4)) throw new InvalidDataException("SOCKS_DATAGRAM_INVALID");
            var addressSize = packet[3] == 1 ? 4 : 16; if (packet.Length < addressSize + 6) throw new InvalidDataException("SOCKS_DATAGRAM_INVALID");
            if (!new IPAddress(packet.Slice(4, addressSize)).Equals(origin) || System.Buffers.Binary.BinaryPrimitives.ReadUInt16BigEndian(packet.Slice(addressSize + 4, 2)) != port)
                throw new InvalidDataException("SOCKS_DATAGRAM_INVALID");
            packet = packet[(addressSize + 6)..];
        }
        var split = packet.IndexOf((byte)10); if (split is < 0 or > 2048) throw new InvalidDataException("TRAFFIC_DATAGRAM_MALFORMED");
        return (JsonNode.Parse(packet[..split]) as JsonObject ?? throw new InvalidDataException("TRAFFIC_DATAGRAM_MALFORMED"), packet[(split + 1)..].ToArray());
    }
}
