using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json.Nodes;

namespace ProxyBridge.TestLab.TrafficEngine;

// Only live endurance jobs are retained. Histograms have bounded logarithmic bins.
internal sealed class EnduranceObservation : IDisposable
{
    private static readonly ConcurrentDictionary<string, EnduranceObservation> jobs = new();
    private readonly object sync = new();
    private readonly string id;
    private readonly Histogram latency = new();
    private readonly long started = Stopwatch.GetTimestamp();
    private long sent, received, invalid, lastReply;
    private EnduranceObservation(string id) { this.id = id; }
    internal static EnduranceObservation? Start(JsonObject job)
    {
        if(job["endurance"]?.GetValue<bool>() != true) return null;
        var id = job["run_id"]!.GetValue<string>();
        var observation = new EnduranceObservation(id);
        if(!jobs.TryAdd(id, observation)) throw new InvalidDataException("TRAFFIC_ENDURANCE_JOB_EXISTS");
        return observation;
    }
    internal static void Sent(JsonObject job) { if(jobs.TryGetValue(job["run_id"]!.GetValue<string>(),out var o)) lock(o.sync) o.sent++; }
    internal static void Reply(JsonObject job, double milliseconds)
    { if(jobs.TryGetValue(job["run_id"]!.GetValue<string>(),out var o)) lock(o.sync) { o.received++; o.lastReply=Stopwatch.GetTimestamp(); o.latency.Add(milliseconds); } }
    internal static void Invalid(JsonObject job) { if(jobs.TryGetValue(job["run_id"]!.GetValue<string>(),out var o)) lock(o.sync) o.invalid++; }
    internal static JsonObject Snapshot()
    {
        var result = new JsonObject();
        foreach(var pair in jobs) lock(pair.Value.sync)
        {
            var o=pair.Value;
            result[pair.Key]=new JsonObject { ["sent"]=o.sent,["received"]=o.received,["invalid"]=o.invalid,
                ["age_seconds"]=Stopwatch.GetElapsedTime(o.started).TotalSeconds,
                ["reply_age_seconds"]=Stopwatch.GetElapsedTime(o.lastReply==0?o.started:o.lastReply).TotalSeconds,["latency"]=o.latency.View() };
        }
        return result;
    }
    public void Dispose() { jobs.TryRemove(id,out _); }
}
