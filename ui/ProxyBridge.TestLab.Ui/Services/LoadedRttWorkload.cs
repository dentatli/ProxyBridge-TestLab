using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public static class LoadedRttWorkload
{
    public static JsonElement? Resolve(string? duration, string? load)
    {
        if (duration is null && load is null) return null;
        if (duration is not ("SHORT" or "NORMAL" or "LONG") || load is not ("LOW" or "HIGH")) throw new InvalidOperationException("LAB_WORKLOAD_INVALID");
        var echoes = duration switch { "SHORT" => 128, "NORMAL" => 1500, _ => 6000 };
        var rate = load == "HIGH" ? 67108864L : 8388608L;
        var seconds = (int)Math.Ceiling((echoes + 100) * .02) + 20;
        return JsonSerializer.SerializeToElement(new { method = "controlled-loaded-rtt-v1", duration, load, echo_count = echoes,
            warmup_count = 100, message_bytes = 512, pause_ms = 20, rate_limit_bytes_per_s = rate,
            transfer_bytes = seconds * rate, nominal_transfer_seconds = seconds, pair_count = 1 });
    }
}
