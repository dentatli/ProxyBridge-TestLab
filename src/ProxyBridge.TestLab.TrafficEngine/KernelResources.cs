using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Reflection.PortableExecutable;
using System.Text.Json.Nodes;
using Microsoft.Diagnostics.Tracing;
using Microsoft.Diagnostics.Tracing.Parsers;
using Microsoft.Diagnostics.Tracing.Parsers.Kernel;
using Microsoft.Diagnostics.Tracing.Session;

namespace ProxyBridge.TestLab.TrafficEngine;

// Observations only: exclusive sampled driver instructions and global tagged pool.
// They overlap process/kernel accounting and must never be added to process CPU.
internal sealed class KernelResources : IDisposable
{
    private readonly object gate = new(), lifecycle = new();
    private int expectedSize, expectedTimestamp;
    private uint expectedChecksum;
    private bool cleanupUnverified;
    private TraceEventSession? session;
    private ETWTraceEventSource? source;
    private Task? reader;
    private string? name, error, driver, hash;
    private string[] tags = [];
    private long interval;
    private bool intervalChanged, mapped, identityMismatch;
    private ulong imageBase, imageSize;
    private readonly List<Window> windows = [];
    private Window? current;
    private long totalSamples;
    private int poolQueries, poolErrors;
    private sealed class Window(string id, string phase)
    {
        public string Id = id, Phase = phase;
        public long Start = Stopwatch.GetTimestamp(), End, Samples, DpcSamples, IsrSamples, AllSamples;
        public int PoolSamples;
        public long? PagedFirst, NonPagedFirst, PagedLast, NonPagedLast, PagedPeak, NonPagedPeak;
    }
    internal bool Active => session is not null || cleanupUnverified;

    internal JsonObject Start(string path, string expectedHash) { lock(lifecycle) return StartCore(path,expectedHash); }
    private JsonObject StartCore(string path, string expectedHash)
    {
        if (Active) throw new InvalidOperationException("TRAFFIC_KERNEL_SESSION_ALREADY_ACTIVE");
        error = null; mapped = identityMismatch = intervalChanged = false; imageBase = imageSize = 0;
        windows.Clear(); current = null; totalSamples = 0; poolQueries = poolErrors = 0;
        driver = Path.GetFullPath(path);
        var bytes = File.ReadAllBytes(driver);
        hash = Convert.ToHexStringLower(SHA256.HashData(bytes));
        if (!string.Equals(hash, expectedHash, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("TRAFFIC_KERNEL_BINARY_CHANGED");
        using(var pe = new PEReader(new MemoryStream(bytes))) { expectedSize=pe.PEHeaders.PEHeader!.SizeOfImage; expectedTimestamp=pe.PEHeaders.CoffHeader.TimeDateStamp; expectedChecksum=pe.PEHeaders.PEHeader.CheckSum; }
        tags = Path.GetFileName(driver).ToLowerInvariant() switch
        {
            "proxybridgedrv.sys" => ["PBfp", "PbDu"],
            "windivert64.sys" => ["WDiv"],
            _ => []
        };
        if (tags.Length == 0 || tags.Any(t => bytes.AsSpan().IndexOf(Encoding.ASCII.GetBytes(t)) < 0))
            return new() { ["available"] = false, ["error"] = "TAG_PROFILE_UNVERIFIED" };
        name = "ProxyBridge-TestLab-" + Guid.NewGuid().ToString("N");
        try
        {
            interval = QueryInterval();
            // TraceEvent sets this global interval. Preserve its existing value,
            // and invalidate observations if another recorder changes it later.
            session = new TraceEventSession(name, TraceEventSessionOptions.Create | TraceEventSessionOptions.NoRestartOnCreate)
            { StopOnDispose = true, BufferSizeMB = 16, CpuSampleIntervalMSec = interval / 10000f };
            session.EnableKernelProvider(KernelTraceEventParser.Keywords.Profile | KernelTraceEventParser.Keywords.ImageLoad | KernelTraceEventParser.Keywords.Process | KernelTraceEventParser.Keywords.Thread);
            source = session.Source;
            source.Kernel.ImageGroup += Image;
            source.Kernel.PerfInfoSample += Sample;
            source.Kernel.PerfInfoSetInterval += e => { if (e.SampleSource == 0 && e.NewInterval != interval) intervalChanged = true; };
            reader = Task.Factory.StartNew(() => source.Process(), CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            session.Flush();
            // Image rundown is consumed before the first workload window starts.
            var deadline = Stopwatch.StartNew();
            while (!mapped && !reader.IsCompleted && deadline.Elapsed.TotalSeconds < 3) Thread.Sleep(20);
            return new() { ["available"] = true, ["method"] = "exclusive-ip-and-tagged-pool-v1", ["module_observed"] = mapped,
                ["sampling_interval_100ns"] = interval, ["session"] = name };
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            error = "KERNEL_START_" + ex.GetType().Name + ":" + ex.Message[..Math.Min(ex.Message.Length,200)];
            var cleanup = Stop();
            return new() { ["available"] = false, ["error"] = error, ["cleanup_verified"] = cleanup["cleanup_verified"]?.DeepClone() };
        }
    }

    private void Image(ImageLoadTraceData e)
    {
        if (e.ImageSize <= 0 || !string.Equals(Path.GetFileName(e.FileName), Path.GetFileName(driver), StringComparison.OrdinalIgnoreCase)) return;
        lock (gate)
        {
            if(e.Opcode==TraceEventOpcode.Stop) { identityMismatch=true; return; }
            if(e.Version<2 || e.ImageSize!=expectedSize || e.TimeDateStamp!=expectedTimestamp || unchecked((uint)e.ImageChecksum)!=expectedChecksum) { identityMismatch=true; return; }
            if (mapped && imageBase != e.ImageBase) identityMismatch = true;
            imageBase = e.ImageBase; imageSize = (ulong)e.ImageSize; mapped = true;
        }
    }
    private void Sample(SampledProfileTraceData e)
    {
        lock (gate)
        {
            totalSamples++;
            #pragma warning disable CS0618 // Raw QPC is intentional: phase boundaries use the same Windows Stopwatch clock.
            var qpc = e.TimeStampQPC;
#pragma warning restore CS0618
            var w = windows.LastOrDefault(w => qpc >= w.Start && (w.End == 0 || qpc < w.End));
            if (w is null) return;
            w.AllSamples++;
            if (!mapped || e.InstructionPointer < imageBase || e.InstructionPointer - imageBase >= imageSize) return;
            w.Samples++; if (e.ExecutingDPC) w.DpcSamples++; if (e.ExecutingISR) w.IsrSamples++;
        }
    }

    internal JsonObject Begin(string id, string phase)
    {
        lock (gate)
        {
            if (current is not null || session is null) throw new InvalidOperationException("TRAFFIC_KERNEL_PHASE_INVALID");
            current = new Window(id, phase); windows.Add(current);
        }
        Poll();
        return new() { ["available"] = true };
    }
    internal JsonObject End()
    {
        Poll();
        lock (gate) { if (current is not null) { current.End = Stopwatch.GetTimestamp(); current = null; } }
        return new() { ["available"] = true };
    }
    internal JsonObject Poll()
    {
        try
        {
            var pool = ReadPool(tags); Interlocked.Increment(ref poolQueries);
            lock (gate)
            {
                if (current is not null)
                {
                    var w = current; w.PoolSamples++;
                    w.PagedFirst ??= pool.Paged; w.NonPagedFirst ??= pool.NonPaged;
                    w.PagedLast = pool.Paged; w.NonPagedLast = pool.NonPaged;
                    w.PagedPeak = Math.Max(w.PagedPeak ?? 0, pool.Paged); w.NonPagedPeak = Math.Max(w.NonPagedPeak ?? 0, pool.NonPaged);
                }
            }
            return new() { ["available"] = true, ["paged_bytes"] = pool.Paged, ["nonpaged_bytes"] = pool.NonPaged };
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            Interlocked.Increment(ref poolErrors);
            return new() { ["available"] = false, ["error"] = "POOL_QUERY_" + ex.GetType().Name + ":" + ex.Message };
        }
    }

    internal JsonObject Stop() { lock(lifecycle) return StopCore(); }
    private JsonObject StopCore()
    {
        var owned = session;
        if (owned is null) return new() { ["available"] = false, ["error"] = error ?? "NOT_STARTED", ["cleanup_verified"] = !cleanupUnverified };
        End(); int lost = -1; bool drained = false, cleanup = false;
        try
        {
            owned.Flush(); lost = owned.EventsLost;
            owned.Stop();
            drained = reader is not null && reader.Wait(TimeSpan.FromSeconds(5)) && !reader.IsFaulted;
            if (source is not null) lost = Math.Max(lost, source.EventsLost);
            if (QueryInterval() != interval) intervalChanged = true;
        }
        catch (Exception ex) when (ex is not OutOfMemoryException) { error = "KERNEL_STOP_" + ex.GetType().Name + ":" + ex.Message[..Math.Min(ex.Message.Length,200)]; }
        finally
        {
            owned.Dispose(); session = null;
            cleanup = !TraceEventSession.GetActiveSessionNames().Contains(name); cleanupUnverified = !cleanup;
        }
        var cpuValid = drained && lost == 0 && mapped && !identityMismatch && !intervalChanged;
        var rows = new JsonArray();
        lock (gate)
        {
            foreach (var w in windows)
            {
                var cpuState = !cpuValid ? "UNVERIFIED" : w.Samples < 30 ? "INSUFFICIENT_SAMPLES" : "MEASURED";
                rows.Add(new JsonObject { ["id"] = w.Id, ["phase"] = w.Phase, ["cpu_state"] = cpuState,
                    ["sample_count"] = w.Samples, ["all_sample_count"] = w.AllSamples, ["dpc_samples"] = w.DpcSamples, ["isr_samples"] = w.IsrSamples,
                    ["driver_cpu_seconds_estimate"] = cpuState == "MEASURED" ? w.Samples * interval / 10000000.0 : null,
                    ["pool_state"] = mapped && !identityMismatch && poolErrors == 0 && w.PoolSamples > 0 ? "TAGGED_GLOBAL" : "UNVERIFIED",
                    ["paged_first"] = w.PagedFirst, ["paged_last"] = w.PagedLast, ["paged_peak_observed"] = w.PagedPeak,
                    ["nonpaged_first"] = w.NonPagedFirst, ["nonpaged_last"] = w.NonPagedLast, ["nonpaged_peak_observed"] = w.NonPagedPeak,
                    ["pool_samples"] = w.PoolSamples, ["qpc_start"] = w.Start, ["qpc_end"] = w.End });
            }
        }
        return new() { ["available"] = true, ["method"] = "exclusive-ip-and-tagged-pool-v1", ["cleanup_verified"] = cleanup,
            ["driver_sha256"] = hash, ["driver_name"] = Path.GetFileName(driver), ["tags"] = new JsonArray(tags.Select(t => JsonValue.Create(t)).ToArray()),
            ["qpc_frequency"] = Stopwatch.Frequency, ["logical_cpus"] = Environment.ProcessorCount, ["minimum_cpu_samples"] = 30,
            ["sampling_interval_100ns"] = interval, ["interval_changed"] = intervalChanged, ["module_observed"] = mapped,
            ["module_ambiguous"] = identityMismatch, ["events_lost"] = lost, ["consumer_drained"] = drained, ["total_samples"] = totalSamples,
            ["pool_queries"] = poolQueries, ["pool_query_errors"] = poolErrors, ["error"] = error, ["phases"] = rows,
            ["cpu_scope"] = "exclusive-driver-IP; sampled-estimate; overlaps-process-CPU; never-add",
            ["pool_scope"] = "system-wide-selected-tags; allocations-not-resident-RAM; sampled-high-water; shared-framework-excluded",
            ["full_driver_attribution"] = false, ["ranking_verified"] = false };
    }
    public void Dispose() { if (Active) Stop(); source?.Dispose(); }

    [StructLayout(LayoutKind.Sequential)] private struct ProfileInterval { public uint Source, Interval; }
    [DllImport("advapi32.dll")] private static extern uint TraceQueryInformation(ulong handle, int infoClass, ref ProfileInterval info, int length, out int returned);
    private static long QueryInterval()
    {
        var info = new ProfileInterval(); var status = TraceQueryInformation(0, 5, ref info, 8, out _);
        if (status != 0 || info.Interval is < 100 or > 10000000) throw new InvalidOperationException("SAMPLING_INTERVAL_UNVERIFIED_" + status);
        return info.Interval;
    }
    [DllImport("ntdll.dll")] private static extern int NtQuerySystemInformation(int infoClass, IntPtr buffer, int length, out int returned);
    private static (long Paged, long NonPaged) ReadPool(string[] wanted)
    {
        var size = 1024 * 1024;
        while (size <= 16 * 1024 * 1024)
        {
            var buffer = Marshal.AllocHGlobal(size);
            try
            {
                var status = NtQuerySystemInformation(22, buffer, size, out var needed);
                if (status == unchecked((int)0xC0000004)) { size = Math.Max(size * 2, needed + 4096); continue; }
                if (status != 0) throw new InvalidOperationException("POOL_QUERY_STATUS_" + status.ToString("X8"));
                var count = Marshal.ReadInt32(buffer);
                // SYSTEM_POOLTAG_INFORMATION: x64 array alignment8, SYSTEM_POOLTAG size40.
                if (!Environment.Is64BitProcess || count < 0 || count > (size - 8) / 40) throw new InvalidDataException("POOL_LAYOUT_INVALID");
                long paged = 0, nonpaged = 0;
                for (var i = 0; i < count; i++)
                {
                    var entry = IntPtr.Add(buffer, 8 + i * 40); var tag = new byte[4]; Marshal.Copy(entry, tag, 0, 4);
                    if (!wanted.Contains(Encoding.ASCII.GetString(tag))) continue;
                    var p = Marshal.ReadInt64(entry, 16); var n = Marshal.ReadInt64(entry, 32);
                    if (p < 0 || n < 0) throw new InvalidDataException("POOL_VALUE_INVALID");
                    paged = checked(paged + p); nonpaged = checked(nonpaged + n);
                }
                return (paged, nonpaged);
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        throw new InvalidDataException("POOL_BUFFER_LIMIT");
    }
}

