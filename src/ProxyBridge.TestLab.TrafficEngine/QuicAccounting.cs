using System.Buffers.Binary;
using System.Diagnostics;

namespace ProxyBridge.TestLab.TrafficEngine;

// Public QUIC v1 connection IDs only. The decrypted origin authenticates run/flow binding.
internal sealed class QuicAccounting(Func<bool> reserve, Action release)
{
    internal sealed class Route(int port, string original)
    {
        internal readonly int Port = port;
        internal readonly string Original = original;
        internal readonly HashSet<string> ServerIds = [], ClientIds = [];
        internal ProxyCounters? Counters;
        internal long Sent, Received, Touched = Stopwatch.GetTimestamp();
    }
    private readonly Dictionary<(int, string), Route> routes = [], outgoing = [], incoming = [];
    private long swept = Stopwatch.GetTimestamp();
    internal Route? Connection(int port, byte[] original) => routes.GetValueOrDefault((port, Convert.ToHexStringLower(original)));
    private void Remove(Route route)
    {
        if (!routes.Remove((route.Port, route.Original))) return;
        foreach (var id in route.ServerIds) outgoing.Remove((route.Port, id));
        foreach (var id in route.ClientIds) incoming.Remove((route.Port, id));
        release();
    }
    internal void Clear() { foreach (var route in routes.Values.ToArray()) Remove(route); }
    private static void Alias(Dictionary<(int, string), Route> table, Route route, string cid, HashSet<string> ids)
    {
        if (cid.Length is < 2 or > 40) throw new InvalidDataException("SOCKS_QUIC_CID_INVALID");
        if (table.TryGetValue((route.Port, cid), out var other) && !ReferenceEquals(other, route)) throw new InvalidDataException("SOCKS_QUIC_CID_COLLISION");
        if (!ids.Contains(cid) && ids.Count >= 32) throw new InvalidDataException("SOCKS_QUIC_CID_LIMIT");
        ids.Add(cid); table[(route.Port, cid)] = route;
    }
    internal Route Packet(int port, ReadOnlySpan<byte> bytes, bool reply)
    {
        if (bytes.Length < 9 || (bytes[0] & 0x40) == 0) throw new InvalidDataException("SOCKS_QUIC_HEADER_INVALID");
        string destination, source = ""; var initial = false;
        if ((bytes[0] & 0x80) != 0)
        {
            if (bytes.Length < 7 || BinaryPrimitives.ReadUInt32BigEndian(bytes[1..]) != 1) throw new InvalidDataException("SOCKS_QUIC_VERSION_UNSUPPORTED");
            var destinationSize = bytes[5]; var sourceIndex = 6 + destinationSize;
            if (destinationSize is < 1 or > 20 || sourceIndex >= bytes.Length) throw new InvalidDataException("SOCKS_QUIC_CID_INVALID");
            var sourceSize = bytes[sourceIndex]; if (sourceSize > 20 || sourceIndex + 1 + sourceSize > bytes.Length) throw new InvalidDataException("SOCKS_QUIC_CID_INVALID");
            destination = Convert.ToHexStringLower(bytes.Slice(6, destinationSize)); source = Convert.ToHexStringLower(bytes.Slice(sourceIndex + 1, sourceSize));
            initial = (bytes[0] & 0x30) == 0;
        }
        else destination = Convert.ToHexStringLower(bytes.Slice(1, 8));
        var now = Stopwatch.GetTimestamp();
        if (Stopwatch.GetElapsedTime(swept, now).TotalSeconds >= 1)
        { foreach (var stale in routes.Values.Where(route => Stopwatch.GetElapsedTime(route.Touched, now).TotalSeconds > 30).ToArray()) Remove(stale); swept = now; }
        var table = reply ? incoming : outgoing; var other = reply ? outgoing : incoming;
        var route = table.GetValueOrDefault((port, destination)); if (route is null && source.Length > 0) route = other.GetValueOrDefault((port, source));
        if (route is null)
        {
            if (reply || !initial || source.Length == 0 || !reserve()) throw new InvalidDataException("SOCKS_QUIC_CONNECTION_UNKNOWN_OR_LIMIT");
            route = new(port, destination); routes.Add((port, destination), route);
        }
        Alias(table, route, destination, reply ? route.ClientIds : route.ServerIds);
        if (source.Length > 0) Alias(other, route, source, reply ? route.ServerIds : route.ClientIds);
        route.Touched = now; if (reply) route.Received++; else route.Sent++; return route;
    }
    internal void ServerCid(int port, byte[] original, byte[] cid, bool retired)
    {
        var route = Connection(port, original); if (route is null) return;
        var text = Convert.ToHexStringLower(cid);
        if (retired) { route.ServerIds.Remove(text); outgoing.Remove((port, text)); }
        else Alias(outgoing, route, text, route.ServerIds);
    }
}
