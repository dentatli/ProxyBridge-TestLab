using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

internal sealed class TrafficRemoteOperationFailure(string code) : InvalidOperationException(code);

/// <summary>Durable uncertainty after dispatch; this is never a resumable installation plan.</summary>
internal sealed class TrafficApplyCheckpoint(string root)
{
    private string PendingPath => Path.Combine(root, "traffic-runtime-apply-pending.json");
    internal bool Pending => File.Exists(PendingPath);

    internal Lease Begin(string bundle, string binding)
    {
        Directory.CreateDirectory(root);
        FileStream stream;
        try { stream = new FileStream(PendingPath, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.Read); }
        catch (IOException) { throw new InvalidOperationException("TRAFFIC_APPLY_RECHECK_REQUIRED"); }
        try
        {
            Write(stream, new { operation_id = Guid.NewGuid().ToString("N"), bundle_sha256 = bundle,
                target_binding = binding, dispatched_at_utc = DateTimeOffset.UtcNow, outcome = "UNKNOWN" });
            return new Lease(this, stream);
        }
        catch { stream.Dispose(); throw; }
    }

    internal void ResolveInspection(string state, string bundle, string binding)
    {
        if (!Pending) return;
        FileStream stream;
        try { stream = new FileStream(PendingPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException) { throw new InvalidOperationException("TRAFFIC_OPERATION_ACTIVE"); }
        try
        {
            if (stream.Length > 4096) throw new InvalidOperationException("TRAFFIC_APPLY_TARGET_RECHECK_REQUIRED");
            JsonDocument document;
            try { document = JsonDocument.Parse(stream); }
            catch (JsonException) { throw new InvalidOperationException("TRAFFIC_APPLY_TARGET_RECHECK_REQUIRED"); }
            using (document)
                if (!document.RootElement.TryGetProperty("target_binding", out var target) || target.GetString() != binding)
                    throw new InvalidOperationException("TRAFFIC_APPLY_TARGET_RECHECK_REQUIRED");
            Finish(stream, new { outcome = "RECHECKED", inspected_state = state,
                inspected_bundle_sha256 = bundle, checked_at_utc = DateTimeOffset.UtcNow });
        }
        catch { stream.Dispose(); throw; }
    }

    private void Finish(FileStream stream, object outcome)
    {
        try
        {
            JsonElement? previous = null;
            if (stream.Length <= 4096)
            {
                try { stream.Position = 0; using var document = JsonDocument.Parse(stream); previous = document.RootElement.Clone(); }
                catch (JsonException) { /* An interrupted checkpoint still requires a fresh inspection. */ }
            }
            var archive = Path.Combine(root, "runtime-apply-evidence");
            Directory.CreateDirectory(archive);
            using var evidence = new FileStream(Path.Combine(archive, Guid.NewGuid().ToString("N") + ".json"),
                FileMode.CreateNew, FileAccess.Write, FileShare.Read);
            Write(evidence, new { pending = previous, resolution = outcome });
        }
        finally { stream.Dispose(); }
        File.Delete(PendingPath);
    }

    private static void Write(FileStream stream, object data)
    {
        stream.Position = 0; stream.SetLength(0);
        stream.Write(JsonSerializer.SerializeToUtf8Bytes(data));
        stream.Flush(true);
    }

    internal sealed class Lease(TrafficApplyCheckpoint owner, FileStream stream) : IDisposable
    {
        private bool closed;
        internal void Complete(string state, string? error = null)
        {
            closed = true;
            owner.Finish(stream, new { outcome = "RECEIVED", state, error, received_at_utc = DateTimeOffset.UtcNow });
        }
        public void Dispose() { if (!closed) { closed = true; stream.Dispose(); } }
    }
}
