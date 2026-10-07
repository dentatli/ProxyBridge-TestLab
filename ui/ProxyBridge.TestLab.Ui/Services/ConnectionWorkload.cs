using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public static class ConnectionWorkload
{
    public static JsonElement Resolve(string? duration, string? load)
    {
        duration ??= "SHORT";
        load ??= "LOW";
        if (duration is not ("SHORT" or "NORMAL" or "LONG") || load is not ("LOW" or "HIGH"))
            throw new InvalidOperationException("LAB_WORKLOAD_INVALID");
        return JsonSerializer.SerializeToElement(new
        {
            method = "tcp-connection-load-v1", duration, load,
            levels = load == "HIGH" ? new[] { 64, 256, 640 } : new[] { 8, 32, 64 },
            hold_seconds = duration == "LONG" ? 120 : duration == "NORMAL" ? 32 : 8,
            reference_connections = 4, reference_seconds = 8, rate_per_connection_bytes_per_s = 65536,
            native_timeout_ms = 600000, proxy_event_loop = "ProactorEventLoop",
            minimum_available_bytes = load == "HIGH" ? 2147483648L : 536870912L
        });
    }
}
