using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public static class UdpWorkload
{
    public static JsonElement? Resolve(string root, string? duration, string? load)
    {
        var common = BenchmarkWorkload.Resolve(root, duration, load);
        if (common is null) return null;
        var echoes = duration switch { "SHORT" => 128, "NORMAL" => 1500, _ => 6000 };
        var streams = load == "HIGH" ? 2 : 1;
        return JsonSerializer.SerializeToElement(new
        {
            method = "controlled-udp-workload-v1", duration, load, echo_count_per_stream = echoes,
            packet_count = (echoes + 100) * streams, warmup_per_stream = 100, streams,
            interval_ms = load == "HIGH" ? 10 : 20, message_bytes = 512,
            destination_mode = "SHARED", pair_count = 1, helper_log_flush_mode = "BUFFERED"
        });
    }
}
