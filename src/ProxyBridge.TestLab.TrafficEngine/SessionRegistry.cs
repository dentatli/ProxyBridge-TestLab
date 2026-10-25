using System.Text.Json.Nodes;

namespace ProxyBridge.TestLab.TrafficEngine;

internal sealed class SessionRegistry
{
    private readonly Dictionary<string, Session> sessions = new(StringComparer.Ordinal);
    private readonly Lock sync = new();
    internal Session Get(string id)
    {
        lock (sync)
        {
            if (sessions.TryGetValue(id, out var found)) return found;
            if (sessions.Count >= 128)
            {
                var idle = sessions.FirstOrDefault(pair => pair.Value.Active == 0);
                if (idle.Key is null) throw new InvalidDataException("TRAFFIC_SESSION_LIMIT");
                sessions.Remove(idle.Key);
            }
            var value = new Session(); sessions.Add(id, value); return value;
        }
    }
    internal string? FindTag(string tag)
    {
        lock (sync) return sessions.Keys.FirstOrDefault(key => Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.ASCII.GetBytes(key)))[..32] == tag);
    }
}

internal sealed class Session
{
    internal readonly Lock Sync = new();
    internal long Accepted, Completed, Active, Errors, Peak, Rx, Tx, UdpReceived, UdpReplyErrors;
    internal readonly HashSet<string> UdpFlows = new(StringComparer.Ordinal);
    internal readonly List<JsonObject> Routes = [];
    internal readonly ProxyCounters Proxy = new();
    internal JsonObject Snapshot()
    {
        lock (Sync) return new() { ["accepted"] = Accepted, ["completed"] = Completed, ["active"] = Active, ["errors"] = Errors,
            ["tcp_active_peak"] = Peak, ["rx_bytes"] = Rx, ["tx_bytes"] = Tx, ["udp_received"] = UdpReceived,
            ["udp_reply_errors"] = UdpReplyErrors, ["udp_unique_flows"] = UdpFlows.Count,
            ["route_samples"] = new JsonArray(Routes.Select(row => row.DeepClone()).ToArray()) };
    }
}

internal sealed class ProxyCounters
{
    internal readonly Lock Sync = new();
    internal long TcpFlows, TcpFinished, TcpActive, TcpErrors, UdpSent, UdpReceived;
    internal readonly byte[] TcpFingerprint = new byte[32], UdpFingerprint = new byte[32];
    internal readonly HashSet<string> UdpFlows = [];
    internal readonly JsonArray Samples = [];
    internal void Fingerprint(string flow, JsonNode peer, bool udp)
    {
        var bytes = System.Security.Cryptography.SHA256.HashData(Wire.Json(new JsonArray(flow, peer.DeepClone())));
        var destination = udp ? UdpFingerprint : TcpFingerprint;
        for (var i = 0; i < bytes.Length; i++) destination[i] ^= bytes[i];
    }
    internal JsonObject Snapshot()
    {
        lock (Sync) return new() { ["tcp_flows"] = TcpFlows, ["tcp_finished"] = TcpFinished, ["tcp_active"] = TcpActive, ["tcp_errors"] = TcpErrors,
            ["tcp_origin_fingerprint"] = Convert.ToHexStringLower(TcpFingerprint), ["udp_sent"] = UdpSent, ["udp_received"] = UdpReceived,
            ["udp_flows"] = UdpFlows.Count, ["udp_origin_fingerprint"] = Convert.ToHexStringLower(UdpFingerprint), ["samples"] = Samples.DeepClone() };
    }
}
