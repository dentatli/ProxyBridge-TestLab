using System.Text.Json.Nodes;

namespace ProxyBridge.TestLab.TrafficEngine;

internal sealed class Histogram
{
    private readonly SortedDictionary<int, long> bins = [];
    internal long Count { get; private set; }
    private double sum, maximum;
    internal void Add(double milliseconds)
    {
        if (!double.IsFinite(milliseconds) || milliseconds < 0) throw new InvalidDataException("TRAFFIC_TIMING_INVALID");
        var index = (int)Math.Ceiling(Math.Log(1 + milliseconds / .001) / Math.Log(1.01));
        bins[index] = bins.GetValueOrDefault(index) + 1; Count++; sum += milliseconds; maximum = Math.Max(maximum, milliseconds);
    }
    internal JsonObject View()
    {
        var buckets = new JsonObject(); foreach (var (key, count) in bins) buckets[key.ToString(System.Globalization.CultureInfo.InvariantCulture)] = count;
        var result = new JsonObject { ["count"] = Count, ["mean_ms"] = Count > 0 ? sum / Count : null,
            ["max_ms"] = Count > 0 ? maximum : null, ["method"] = "all-sample-log-histogram-upper-bound-1pct", ["bins"] = buckets, ["sum_ms"] = sum };
        foreach (var percentile in new[] { 50, 95, 99 })
        {
            double? value = null; long accumulated = 0; var target = (long)Math.Ceiling(Count * percentile / 100.0);
            if (Count > 0) foreach (var (index, count) in bins) { accumulated += count; if (accumulated >= target) { value = .001 * (Math.Pow(1.01, index) - 1); break; } }
            result[$"p{percentile}_ms"] = value;
        }
        return result;
    }
}
