using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace ProxyBridge.TestLab.TrafficEngine;

internal static partial class Wire
{
    internal const int Chunk = 65536, HeaderLimit = 8192;
    [GeneratedRegex("^[a-zA-Z0-9_.-]{1,128}$", RegexOptions.CultureInvariant)]
    private static partial Regex IdPattern();
    internal static string Id(JsonObject value, string key)
    {
        var text = value[key]?.GetValue<string>() ?? "";
        if (!IdPattern().IsMatch(text)) throw new InvalidDataException("TRAFFIC_ID_INVALID");
        return text;
    }
    internal static readonly JsonSerializerOptions Options = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
    internal static byte[] Json(JsonNode value)
    {
        // This wire contains ASCII IDs, addresses and error codes. Preserve parsed numeric tokens.
        // Do not sign serializer-dependent Unicode/float representations silently.
        using var output = new MemoryStream();
        using (var writer = new Utf8JsonWriter(output, new() { Encoder = Options.Encoder })) WriteSorted(writer, value);
        var result = output.ToArray();
        if (result.Any(b => b > 127)) throw new InvalidDataException("TRAFFIC_WIRE_ASCII_REQUIRED");
        return result;
    }
    private static void WriteSorted(Utf8JsonWriter writer, JsonNode? node)
    {
        if (node is JsonObject obj)
        {
            writer.WriteStartObject();
            foreach (var pair in obj.OrderBy(pair => pair.Key, StringComparer.Ordinal)) { writer.WritePropertyName(pair.Key); WriteSorted(writer, pair.Value); }
            writer.WriteEndObject();
        }
        else if (node is JsonArray array) { writer.WriteStartArray(); foreach (var item in array) WriteSorted(writer, item); writer.WriteEndArray(); }
        else if (node is null) writer.WriteNullValue();
        else node.WriteTo(writer, Options);
    }
    internal static byte[] Join(params ReadOnlyMemory<byte>[] parts)
    {
        var result = new byte[parts.Sum(part => part.Length)]; var offset = 0;
        foreach (var part in parts) { part.Span.CopyTo(result.AsSpan(offset)); offset += part.Length; }
        return result;
    }
    internal static string Mac(byte[] secret, string label, params ReadOnlyMemory<byte>[] parts) =>
        Convert.ToHexStringLower(HMACSHA256.HashData(secret, Join([Encoding.ASCII.GetBytes(label), .. parts])));
    internal static void Verify(byte[] secret, string label, string? proof, params ReadOnlyMemory<byte>[] parts)
    {
        byte[] observed;
        try { observed = Convert.FromHexString(proof ?? ""); }
        catch (FormatException) { throw new InvalidDataException("TRAFFIC_AUTHENTICATION_FAILED"); }
        if (observed.Length != 32 || !CryptographicOperations.FixedTimeEquals(observed, Convert.FromHexString(Mac(secret, label, parts))))
            throw new InvalidDataException("TRAFFIC_AUTHENTICATION_FAILED");
    }
    internal static void Fill(Span<byte> buffer, ulong offset)
    { for (var i = 0; i < buffer.Length; i++) buffer[i] = (byte)(offset + (ulong)i); }
    internal static void Validate(ReadOnlySpan<byte> buffer, ulong offset)
    { for (var i = 0; i < buffer.Length; i++) if (buffer[i] != (byte)(offset + (ulong)i)) throw new InvalidDataException("TRAFFIC_DATA_MISMATCH"); }
    internal static byte[] Frame(ulong offset, int size)
    {
        if (size is < 0 or > Chunk) throw new InvalidDataException("TRAFFIC_FRAME_TOO_LARGE");
        var bytes = new byte[12]; BinaryPrimitives.WriteUInt64BigEndian(bytes, offset); BinaryPrimitives.WriteUInt32BigEndian(bytes.AsSpan(8), (uint)size); return bytes;
    }
    internal static async Task<(ulong Offset, int Size)> ReadFrame(Stream stream, CancellationToken token)
    {
        var header = new byte[12]; await stream.ReadExactlyAsync(header, token);
        var size = BinaryPrimitives.ReadUInt32BigEndian(header.AsSpan(8));
        if (size > Chunk) throw new InvalidDataException("TRAFFIC_FRAME_TOO_LARGE");
        return (BinaryPrimitives.ReadUInt64BigEndian(header), (int)size);
    }
    internal static async Task<JsonObject> ReadJson(Stream stream, CancellationToken token, int limit = HeaderLimit)
    {
        using var line = new MemoryStream(); var single = new byte[1];
        while (line.Length < limit)
        {
            await stream.ReadExactlyAsync(single, token);
            if (single[0] == 10) return JsonNode.Parse(line.ToArray()) as JsonObject ?? throw new InvalidDataException("TRAFFIC_HEADER_INVALID");
            line.WriteByte(single[0]);
        }
        throw new InvalidDataException("TRAFFIC_HEADER_INVALID");
    }
    internal static Task WriteJson(Stream stream, JsonObject value, CancellationToken token) => stream.WriteAsync(Join(Json(value), new byte[] { 10 }), token).AsTask();
    internal static string TakeProof(JsonObject value)
    { var proof = value["proof"]?.GetValue<string>() ?? ""; value.Remove("proof"); return proof; }
}
