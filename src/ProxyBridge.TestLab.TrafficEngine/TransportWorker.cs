using System.Buffers.Binary;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace ProxyBridge.TestLab.TrafficEngine;

internal static partial class TransportWorker
{
    internal static async Task<JsonObject> Execute(JsonObject job, CancellationToken token)
    {
        var run = Wire.Id(job, "run_id"); var task = job["task"]?.GetValue<string>();
        var count = job["connections"]?.GetValue<int>() ?? 1; var seconds = job["seconds"]?.GetValue<double>() ?? double.NaN;
        if (task is not ("echo" or "hold" or "upload" or "download" or "duplex" or "udp" or "flow_rate") || job["application"] is not null ||
            count is < 1 or > 1024 || !double.IsFinite(seconds) || seconds is < .05 or > 259200 ||
            !IPAddress.TryParse(job["host"]?.GetValue<string>(), out _) || job["port"]?.GetValue<int>() is not (>= 1 and <= 65535) ||
            Convert.FromHexString(job["secret"]!.GetValue<string>()).Length != 32 || (job["message_bytes"]?.GetValue<int>() ?? 512) is < 1 or > 60000 ||
            (job["warmup_count"]?.GetValue<int>() ?? 100) is < 0 or > 100000)
            throw new InvalidDataException("TRAFFIC_JOB_INVALID");
        var started = Stopwatch.GetTimestamp();
        var echoRate = job["rate_exchanges_per_second"]?.GetValue<double>() ?? 0;
        if (!double.IsFinite(echoRate) || echoRate is < 0 or > 1000000) throw new InvalidDataException("TRAFFIC_RATE_INVALID");
        using var observation = EnduranceObservation.Start(job);
        var jobs = Enumerable.Range(0, count).Select(index => task == "udp" ? Udp(job, Guid.NewGuid().ToString(), token) :
            task == "flow_rate" ? Churn(job, index, token) : Tcp(job, task!, Guid.NewGuid().ToString(), token)).ToArray();
        var flows = await Task.WhenAll(jobs); var elapsed = Stopwatch.GetElapsedTime(started).TotalSeconds;
        var tcpFingerprint = new byte[32]; var udpFingerprint = new byte[32]; long tcpCompleted = 0;
        foreach (var flow in flows)
        {
            if (task == "flow_rate") { Xor(tcpFingerprint, Convert.FromHexString(flow["tcp_origin_fingerprint"]!.GetValue<string>())); tcpCompleted += flow["completed"]!.GetValue<long>(); }
            else if (task != "udp" && flow["complete"]?.GetValue<bool>() == true) { Xor(tcpFingerprint, Fingerprint(flow["flow_id"]!.GetValue<string>(), flow["peer_observed_by_origin"]!)); tcpCompleted++; }
            else if (task == "udp" && flow["received"]!.GetValue<long>() > 0) Xor(udpFingerprint, Fingerprint(flow["flow_id"]!.GetValue<string>(), flow["peer_observed_by_origin"]![0]!));
        }
        return new() { ["schema_version"] = 1, ["measurement_method"] = "controlled-traffic-v1", ["engine"] = "csharp-transport-v1", ["engine_pid"] = Environment.ProcessId, ["run_id"] = run,
            ["task"] = task, ["complete"] = flows.All(flow => flow["complete"]?.GetValue<bool>() == true), ["flows"] = new JsonArray(flows),
            ["elapsed_seconds"] = elapsed, ["tx_bytes"] = flows.Sum(flow => flow["tx_bytes"]?.GetValue<long>() ?? 0), ["rx_bytes"] = flows.Sum(flow => flow["rx_bytes"]?.GetValue<long>() ?? 0),
            ["product_route_confirmed"] = false, ["metric_scope"] = "controlled-worker-and-origin", ["tcp_origin_fingerprint"] = Convert.ToHexStringLower(tcpFingerprint),
            ["udp_origin_fingerprint"] = Convert.ToHexStringLower(udpFingerprint), ["successful_tcp_flows"] = tcpCompleted,
            ["rate_limit_bytes_per_second_per_flow"] = job["rate_bytes_per_second"]?.DeepClone() ?? JsonValue.Create(0),
            ["rate_limit_packets_per_second_per_flow"] = job["rate_packets_per_second"]?.DeepClone() ?? JsonValue.Create(1000) };
    }
    private static byte[] Fingerprint(string flow, JsonNode peer) => SHA256.HashData(Wire.Json(new JsonArray(flow, peer.DeepClone())));
    private static void Xor(byte[] target, byte[] source) { for (var i = 0; i < target.Length; i++) target[i] ^= source[i]; }
    private static async Task<(Socket Socket, Stream Stream, byte[] Context, JsonObject Ready)> Connect(JsonObject job, string task, string flow, CancellationToken token)
    {
        var address = IPAddress.Parse(job["host"]!.GetValue<string>()); var port = job["port"]!.GetValue<int>();
        var socket = new Socket(address.AddressFamily, SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
        try
        {
            if (job["test_proxy"] is JsonObject proxy) await Socks(socket, job, proxy, false, token);
            else await socket.ConnectAsync(new IPEndPoint(address, port), token);
            var stream = new ReadBufferedDuplexStream(new NetworkStream(socket, ownsSocket: false));
            var request = new JsonObject { ["version"] = 1, ["task"] = task, ["run_id"] = job["run_id"]!.DeepClone(), ["flow_id"] = flow,
                ["seconds"] = job["seconds"]!.DeepClone(), ["rate_bytes_per_second"] = job["rate_bytes_per_second"]?.DeepClone() ?? JsonValue.Create(0) };
            var raw = Wire.Json(request); await Wire.WriteJson(stream, request, token);
            var challenge = (await Wire.ReadJson(stream, token))["challenge"]?.GetValue<string>() ?? "";
            if (challenge.Length != 64 || !challenge.All(Uri.IsHexDigit)) throw new InvalidDataException("TRAFFIC_CHALLENGE_INVALID");
            var context = Wire.Join(Encoding.ASCII.GetBytes(challenge), raw); var secret = Convert.FromHexString(job["secret"]!.GetValue<string>());
            await Wire.WriteJson(stream, new() { ["proof"] = Wire.Mac(secret, "client:", context) }, token);
            var ready = await Wire.ReadJson(stream, token); Wire.Verify(secret, "server:", Wire.TakeProof(ready), context, Wire.Json(ready));
            if (ready["ready"]?.GetValue<bool>() != true || ready["flow_id"]?.GetValue<string>() != flow || ready["peer"] is not JsonArray { Count: 2 })
                throw new InvalidDataException("TRAFFIC_ORIGIN_IDENTITY_MISMATCH");
            return (socket, stream, context, ready);
        }
        catch { socket.Dispose(); throw; }
    }
    internal static async Task<IPEndPoint> Socks(Socket socket, JsonObject job, JsonObject proxy, bool udp, CancellationToken token, Action<string>? progress = null)
    {
        progress?.Invoke("proxy-connect");
        await socket.ConnectAsync(new IPEndPoint(IPAddress.Parse(proxy["host"]!.GetValue<string>()), proxy["port"]!.GetValue<int>()), token);
        using var stream = new ReadBufferedDuplexStream(new NetworkStream(socket, ownsSocket: false));
        progress?.Invoke("proxy-greeting");
        await stream.WriteAsync(new byte[] { 5, 1, 2 }, token); var response = new byte[2]; await stream.ReadExactlyAsync(response, token);
        if (!response.AsSpan().SequenceEqual(new byte[] { 5, 2 })) throw new InvalidDataException("SOCKS_AUTH_METHOD_REJECTED");
        var username = Encoding.ASCII.GetBytes(Wire.Id(proxy, "username"));
        var password = Encoding.ASCII.GetBytes(Wire.Mac(Convert.FromHexString(job["secret"]!.GetValue<string>()), "socks:", username));
        progress?.Invoke("proxy-authentication");
        await stream.WriteAsync(Wire.Join(new byte[] { 1, (byte)username.Length }, username, new byte[] { (byte)password.Length }, password), token);
        await stream.ReadExactlyAsync(response, token); if (!response.AsSpan().SequenceEqual(new byte[] { 1, 0 })) throw new InvalidDataException("SOCKS_AUTH_REJECTED");
        progress?.Invoke("proxy-association-reply");
        await stream.WriteAsync(Wire.Join(new byte[] { 5, (byte)(udp ? 3 : 1), 0 }, Address(udp ? IPAddress.Any : IPAddress.Parse(job["host"]!.GetValue<string>()), udp ? 0 : job["port"]!.GetValue<int>())), token);
        var prefix = new byte[4]; await stream.ReadExactlyAsync(prefix, token);
        if (prefix[0] != 5 || prefix[1] != 0 || prefix[2] != 0 || prefix[3] is not (1 or 4)) throw new InvalidDataException("SOCKS_REQUEST_REJECTED");
        var endpoint = new byte[prefix[3] == 1 ? 6 : 18]; await stream.ReadExactlyAsync(endpoint, token);
        return new IPEndPoint(new IPAddress(endpoint.AsSpan(0, endpoint.Length - 2)), BinaryPrimitives.ReadUInt16BigEndian(endpoint.AsSpan(endpoint.Length - 2)));
    }
    internal static byte[] Address(IPAddress address, int port)
    { var raw = address.GetAddressBytes(); var result = new byte[raw.Length + 3]; result[0] = (byte)(raw.Length == 4 ? 1 : 4); raw.CopyTo(result, 1); BinaryPrimitives.WriteUInt16BigEndian(result.AsSpan(result.Length - 2), (ushort)port); return result; }
    private static bool Cancelled(JsonObject job) => job["cancellation_path"] is JsonValue path && File.Exists(path.GetValue<string>());
    private static async Task Pace(long start, long units, double rate, JsonObject job, CancellationToken token)
    {
        if (rate <= 0) return;
        while (!Cancelled(job))
        {
            var delay = units / rate - Stopwatch.GetElapsedTime(start).TotalSeconds;
            if (delay <= 0) return;
            await Task.Delay(TimeSpan.FromSeconds(Math.Min(.2, delay)), token);
        }
        throw new OperationCanceledException("TRAFFIC_CANCELLED");
    }
    internal static async Task<JsonObject> Tcp(JsonObject job, string task, string flow, CancellationToken stopping, int exchangeLimit = 0)
    {
        await Task.Yield();
        var result = new JsonObject { ["flow_id"] = flow, ["task"] = task, ["complete"] = false, ["tx_bytes"] = 0L, ["rx_bytes"] = 0L, ["errors"] = new JsonArray() };
        var histogram = new Histogram(); var phase = "connect-and-authentication"; Socket? socket = null;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(stopping); deadline.CancelAfter(TimeSpan.FromSeconds(10));
        try
        {
            var connected = Stopwatch.GetTimestamp(); var connection = await Connect(job, task, flow, deadline.Token); socket = connection.Socket; using var stream = connection.Stream;
            result["connect_ms"] = Stopwatch.GetElapsedTime(connected).TotalMilliseconds;
            result["local"] = TransportOrigin.Peer((IPEndPoint)socket.LocalEndPoint!); result["peer_observed_by_origin"] = connection.Ready["peer"]!.DeepClone();
            phase = "workload"; var started = Stopwatch.GetTimestamp(); var seconds = job["seconds"]!.GetValue<double>(); deadline.CancelAfter(TimeSpan.FromSeconds(seconds + 20)); var token = deadline.Token;
            using var txHash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256); using var rxHash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            long sent = 0, received = 0;
            async Task Send()
            {
                var buffer = new byte[Wire.Chunk]; Wire.Fill(buffer, 0);
                while (Stopwatch.GetElapsedTime(started).TotalSeconds < seconds && !Cancelled(job))
                {
                    await stream.WriteAsync(Wire.Frame((ulong)sent, buffer.Length), token); await stream.WriteAsync(buffer, token); txHash.AppendData(buffer); sent += buffer.Length;
                    await Pace(started, sent, job["rate_bytes_per_second"]?.GetValue<double>() ?? 0, job, token);
                }
                await stream.WriteAsync(Wire.Frame((ulong)sent, 0), token);
            }
            async Task Receive()
            {
                var buffer = new byte[Wire.Chunk];
                while (!Cancelled(job))
                {
                    var header = await Wire.ReadFrame(stream, token);
                    if (header.Offset != (ulong)received) throw new InvalidDataException("TRAFFIC_DATA_OR_SEQUENCE_MISMATCH");
                    if (header.Size == 0) return;
                    await stream.ReadExactlyAsync(buffer.AsMemory(0, header.Size), token); Wire.Validate(buffer.AsSpan(0, header.Size), (ulong)received);
                    rxHash.AppendData(buffer, 0, header.Size); received += header.Size;
                }
                throw new OperationCanceledException("TRAFFIC_CANCELLED");
            }
            try
            {
                if (task is "echo" or "hold")
                {
                    var size = job["message_bytes"]?.GetValue<int>() ?? 512; var buffer = new byte[size]; var echoed = new byte[size]; var iteration = 0;
                    while ((exchangeLimit > 0 ? iteration < exchangeLimit : Stopwatch.GetElapsedTime(started).TotalSeconds < seconds) && !Cancelled(job))
                    {
                        Wire.Fill(buffer, (ulong)sent); var sample = Stopwatch.GetTimestamp();
                        using var exchange = job["endurance"]?.GetValue<bool>()==true ? CancellationTokenSource.CreateLinkedTokenSource(token) : null;
                        exchange?.CancelAfter(TimeSpan.FromSeconds(5));
                        var exchangeToken=exchange?.Token ?? token;
                        EnduranceObservation.Sent(job);
                        await stream.WriteAsync(Wire.Frame((ulong)sent, size), exchangeToken); await stream.WriteAsync(buffer, exchangeToken);
                        var header = await Wire.ReadFrame(stream, exchangeToken);
                        if (header.Offset != (ulong)sent || header.Size != size) throw new InvalidDataException("TRAFFIC_DATA_OR_SEQUENCE_MISMATCH");
                        await stream.ReadExactlyAsync(echoed, exchangeToken); var latency = Stopwatch.GetElapsedTime(sample).TotalMilliseconds;
                        if (!buffer.AsSpan().SequenceEqual(echoed)) throw new InvalidDataException("TRAFFIC_DATA_OR_SEQUENCE_MISMATCH");
                        EnduranceObservation.Reply(job, latency);
                        txHash.AppendData(buffer); rxHash.AppendData(echoed); sent += size; received += size;
                        if (iteration++ >= (job["warmup_count"]?.GetValue<int>() ?? 100)) histogram.Add(latency);
                        if (task == "hold") await Task.Delay(200, token);
                        else await Pace(started, iteration, job["rate_exchanges_per_second"]?.GetValue<double>() ?? 0, job, token);
                    }
                    if (exchangeLimit > 0 && iteration != exchangeLimit) throw new InvalidDataException("TRAFFIC_FIXED_EXCHANGE_INCOMPLETE");
                    result["exchange_count"] = iteration;
                    await stream.WriteAsync(Wire.Frame((ulong)sent, 0), token); var final = await Wire.ReadFrame(stream, token);
                    if (final.Offset != (ulong)sent || final.Size != 0) throw new InvalidDataException("TRAFFIC_TERMINATION_INVALID");
                }
                else if (task == "duplex")
                {
                    var sender = Send(); var receiver = Receive();
                    var first = await Task.WhenAny(sender, receiver); if (first.IsFaulted || first.IsCanceled) deadline.Cancel();
                    await Task.WhenAll(sender, receiver);
                }
                else if (task == "upload") await Send();
                else await Receive();
                phase = "origin-evidence";
                var observed = await Wire.ReadJson(stream, token, 131072); var proof = Wire.TakeProof(observed);
                Wire.Verify(Convert.FromHexString(job["secret"]!.GetValue<string>()), "result:", proof, connection.Context, Wire.Json(observed));
                observed["authentication"] = new JsonObject { ["method"] = "HMAC-SHA256", ["proof"] = proof, ["context_hex"] = Convert.ToHexStringLower(connection.Context) };
                result["origin_result"] = observed;
                if (observed["complete"]?.GetValue<bool>() != true || observed["flow_id"]?.GetValue<string>() != flow) throw new InvalidDataException("TRAFFIC_ORIGIN_INCOMPLETE");
                if (observed["rx_bytes"]?.GetValue<long>() != sent || observed["tx_bytes"]?.GetValue<long>() != received) throw new InvalidDataException("TRAFFIC_ORIGIN_BYTE_COUNTER_MISMATCH");
                if ((sent > 0 && observed["rx_sha256"]?.GetValue<string>() != Convert.ToHexStringLower(txHash.GetHashAndReset())) ||
                    (received > 0 && observed["tx_sha256"]?.GetValue<string>() != Convert.ToHexStringLower(rxHash.GetHashAndReset()))) throw new InvalidDataException("TRAFFIC_ORIGIN_HASH_MISMATCH");
                if (task == "echo" && histogram.Count == 0) throw new InvalidDataException("TRAFFIC_NO_LATENCY_SAMPLES_AFTER_WARMUP");
                var elapsed = Stopwatch.GetElapsedTime(started).TotalSeconds; result["elapsed_seconds"] = elapsed;
                result["tx_bytes_per_second"] = sent / elapsed; result["rx_bytes_per_second"] = received / elapsed; result["complete"] = !Cancelled(job) && !stopping.IsCancellationRequested;
            }
            finally { result["tx_bytes"] = sent; result["rx_bytes"] = received; }
        }
        catch (Exception error) when (error is InvalidDataException or IOException or SocketException or OperationCanceledException or System.Text.Json.JsonException or InvalidOperationException or FormatException)
        {
            result["failure_phase"] = phase; ((JsonArray)result["errors"]!).Add(error is InvalidDataException ? error.Message : "TCP_TRANSPORT_FAILED");
            if (error is SocketException socketError) { result["socket_errno"] = socketError.ErrorCode; result["socket_winerror"] = socketError.NativeErrorCode; }
        }
        finally { socket?.Dispose(); result["cancelled"] = Cancelled(job) || stopping.IsCancellationRequested; result["latency"] = histogram.View(); }
        return result;
    }
    private static async Task<JsonObject> Churn(JsonObject job, int worker, CancellationToken token)
    {
        var started = Stopwatch.GetTimestamp(); long offered = 0, completed = 0, failures = 0, tx = 0, rx = 0;
        var histogram = new Histogram(); var fingerprint = new byte[32]; var samples = new JsonArray(); var failed = new JsonArray();
        while (Stopwatch.GetElapsedTime(started).TotalSeconds < job["seconds"]!.GetValue<double>() && !Cancelled(job) && !token.IsCancellationRequested)
        {
            var shortJob = (JsonObject)job.DeepClone(); shortJob["seconds"] = 1.0; shortJob["warmup_count"] = 0; shortJob["message_bytes"] = 64; shortJob["rate_exchanges_per_second"] = 0.0;
            var flow = await Tcp(shortJob, "echo", $"{job["run_id"]!.GetValue<string>()}.{worker}.{offered}", token, exchangeLimit: 1); offered++;
            if (flow["complete"]?.GetValue<bool>() == true) { completed++; histogram.Add(flow["connect_ms"]!.GetValue<double>()); Xor(fingerprint, Fingerprint(flow["flow_id"]!.GetValue<string>(), flow["peer_observed_by_origin"]!)); }
            else { failures++; if (failed.Count < 8) failed.Add(flow.DeepClone()); }
            tx += flow["tx_bytes"]!.GetValue<long>(); rx += flow["rx_bytes"]!.GetValue<long>(); if (samples.Count < 64) samples.Add(flow);
            await Pace(started, offered, job["rate_flows_per_second"]?.GetValue<double>() ?? 0, job, token);
        }
        var elapsed = Stopwatch.GetElapsedTime(started).TotalSeconds;
        return new() { ["complete"] = failures == 0 && completed > 0 && !Cancelled(job) && !token.IsCancellationRequested,
            ["cancelled"] = Cancelled(job) || token.IsCancellationRequested, ["offered"] = offered, ["completed"] = completed, ["failures"] = failures,
            ["elapsed_seconds"] = elapsed, ["completed_flows_per_second"] = completed / elapsed, ["connection_and_authentication_ms"] = histogram.View(),
            ["tx_bytes"] = tx, ["rx_bytes"] = rx, ["tcp_origin_fingerprint"] = Convert.ToHexStringLower(fingerprint), ["route_samples"] = samples,
            ["failure_samples"] = failed, ["failure_samples_truncated"] = failures > failed.Count, ["verified_exchanges_per_flow"] = 1, ["payload_bytes_per_direction_per_flow"] = 64,
            ["errors"] = failures == 0 ? new JsonArray() : new JsonArray("CONNECTION_FAILURES_OBSERVED") };
    }
}
