using System.Text.Json;
using System.Text.Json.Nodes;

namespace ProxyBridge.TestLab.Ui.Services;

public static class BenchmarkWorkload
{
    public static JsonElement? Resolve(string root, string? duration, string? load)
    {
        if (duration is null && load is null) return null;
        if (duration is not ("SHORT" or "NORMAL" or "LONG") || load is not ("LOW" or "HIGH"))
            throw new InvalidOperationException("LAB_WORKLOAD_INVALID");
        var file = Path.Combine(root, "config", "benchmark-workloads.json");
        for (var path = file; path is not null; path = Path.GetDirectoryName(path))
            if ((File.Exists(path) || Directory.Exists(path)) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("LAB_WORKLOAD_INVALID");
        if (new FileInfo(file).Length > 65536) throw new InvalidOperationException("LAB_WORKLOAD_INVALID");
        using var document = JsonDocument.Parse(File.ReadAllText(file));
        var catalog = document.RootElement;
        if (catalog.GetProperty("schema_version").GetInt32() != 1 || catalog.GetProperty("method").GetString() != "controlled-workload-v1")
            throw new InvalidOperationException("LAB_WORKLOAD_INVALID");
        var d = catalog.GetProperty("durations").GetProperty(duration);
        var l = catalog.GetProperty("loads").GetProperty(load);
        var rate = l.GetProperty("rate_limit_bytes_per_s").GetInt64();
        var expectedSeconds = duration switch { "SHORT" => 8, "NORMAL" => 32, _ => 120 };
        var expectedEchoes = duration switch { "SHORT" => 128, "NORMAL" => 1500, _ => 6000 };
        if (d.GetProperty("transfer_seconds").GetInt32() != expectedSeconds || d.GetProperty("rtt_low_echoes").GetInt32() != expectedEchoes ||
            d.GetProperty("rtt_high_echoes").GetInt32() != expectedEchoes * 2 || rate != (load == "LOW" ? 8388608 : 67108864) ||
            l.GetProperty("pause_ms").GetInt32() != (load == "LOW" ? 20 : 10) || catalog.GetProperty("rtt_warmup_count").GetInt32() != 1000 ||
            catalog.GetProperty("rtt_message_bytes").GetInt32() != 512 || catalog.GetProperty("connections").GetInt32() != 1 || catalog.GetProperty("native_timeout_ms").GetInt32() != 600000)
            throw new InvalidOperationException("LAB_WORKLOAD_INVALID");
        return JsonSerializer.SerializeToElement(new
        {
            method = "controlled-workload-v1", duration, load,
            transfer_bytes = checked(d.GetProperty("transfer_seconds").GetInt64() * rate),
            rate_limit_bytes_per_s = rate, nominal_transfer_seconds = d.GetProperty("transfer_seconds").GetInt32(),
            echo_count = d.GetProperty(load == "LOW" ? "rtt_low_echoes" : "rtt_high_echoes").GetInt32(),
            warmup_count = catalog.GetProperty("rtt_warmup_count").GetInt32(),
            message_bytes = catalog.GetProperty("rtt_message_bytes").GetInt32(), pause_ms = l.GetProperty("pause_ms").GetInt32(),
            connections = catalog.GetProperty("connections").GetInt32(), native_timeout_ms = catalog.GetProperty("native_timeout_ms").GetInt32()
        });
    }

    public static bool Matches(JsonElement left, JsonElement right) =>
        JsonNode.DeepEquals(JsonNode.Parse(left.GetRawText()), JsonNode.Parse(right.GetRawText()));
}
