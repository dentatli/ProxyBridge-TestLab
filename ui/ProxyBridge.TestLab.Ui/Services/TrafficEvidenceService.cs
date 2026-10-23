using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed partial class TrafficRuntimeService
{
    private (string Directory, JsonElement Attempt, JsonElement Case) EvidenceCase(string id, string caseId)
    {
        if (!Regex.IsMatch(id, @"\A[0-9]{8}-[0-9]{6}-[a-f0-9]{32}\z") ||
            !Regex.IsMatch(caseId, @"\A[a-z0-9][a-z0-9-]{0,79}\z"))
            throw new InvalidOperationException("TRAFFIC_EVIDENCE_SELECTION_INVALID");
        var directory = Path.Combine(Root, id);
        var attempt = ReadTrafficAttempt(directory);
        if (attempt.TryGetProperty("results", out var results))
            foreach (var row in results.EnumerateArray())
                if (row.GetProperty("case_id").GetString() == caseId) return (directory, attempt, row.Clone());
        throw new InvalidOperationException("TRAFFIC_CASE_REPORT_MISSING");
    }

    private static IEnumerable<string> EvidenceNames(string directory, string caseId)
    {
        // Fixed allowlist; never enumerate profiles, bindings, keys, DPAPI archives or arbitrary paths.
        var names = new[] { "session.console.jsonl", caseId + ".report.json" }
            .Concat(new[] { "OFF-control", "UNRULED-control", "OFF", "UNRULED", "SOCKS5" }
                .SelectMany(mode => new[] { $"{caseId}.{mode}.console.jsonl", $"{caseId}.{mode}.raw.json", $"{caseId}.{mode}.raw.json.stages.jsonl" }));
        return names.Where(name => File.Exists(Path.Combine(directory, name)));
    }

    public object CaseEvidence(string id, string caseId)
    {
        var evidence = EvidenceCase(id, caseId);
        var logs = EvidenceNames(evidence.Directory, caseId).Select(name =>
        {
            var file = new FileInfo(Path.Combine(evidence.Directory, name));
            if (file.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("TRAFFIC_EVIDENCE_FILE_INVALID");
            return new { name, bytes = file.Length, kind = name.EndsWith(".console.jsonl", StringComparison.Ordinal) ? "product" : "report" };
        }).ToArray();
        return new { attempt_id = id, case_id = caseId, report = evidence.Case, logs };
    }

    public object EvidenceLog(string id, string caseId, string name, long offset = 0)
    {
        var evidence = EvidenceCase(id, caseId);
        if (!EvidenceNames(evidence.Directory, caseId).Contains(name, StringComparer.Ordinal))
            throw new InvalidOperationException("TRAFFIC_EVIDENCE_FILE_INVALID");
        var path = Path.Combine(evidence.Directory, name);
        if (File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("TRAFFIC_EVIDENCE_FILE_INVALID");
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (offset < 0 || offset > stream.Length) throw new InvalidOperationException("TRAFFIC_EVIDENCE_SELECTION_INVALID");
        if (offset > 0 && name.EndsWith(".console.jsonl", StringComparison.Ordinal))
        {
            stream.Position = offset - 1;
            if (stream.ReadByte() != '\n') throw new InvalidOperationException("TRAFFIC_EVIDENCE_SELECTION_INVALID");
        }
        stream.Position = offset;
        const int limit = 256 * 1024;
        var bytes = new byte[(int)Math.Min(stream.Length - offset, limit)];
        stream.ReadExactly(bytes);
        if (name.EndsWith(".console.jsonl", StringComparison.Ordinal) && offset + bytes.Length < stream.Length)
        {
            var boundary = Array.LastIndexOf(bytes, (byte)'\n');
            if (boundary < 0) throw new InvalidOperationException("TRAFFIC_EVIDENCE_LOG_INVALID");
            Array.Resize(ref bytes, boundary + 1);
        }
        var text = Encoding.UTF8.GetString(bytes);
        var hasMore = offset + bytes.Length < stream.Length;
        if (name.EndsWith(".console.jsonl", StringComparison.Ordinal))
        {
            var output = new StringBuilder();
            var lines = text.Split('\n');
            // A bounded prefix may end inside a JSONL record; do not decode that fragment.
            foreach (var line in lines)
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                using var record = JsonDocument.Parse(line);
                byte[] data;
                try { data = Convert.FromBase64String(record.RootElement.GetProperty("data_base64").GetString()!); }
                catch (FormatException) { throw new InvalidOperationException("TRAFFIC_EVIDENCE_LOG_INVALID"); }
                output.Append('[').Append(record.RootElement.GetProperty("stream").GetString()).Append("] ")
                    .Append(Encoding.UTF8.GetString(data));
            }
            text = Regex.Replace(output.ToString(), @"\x1b\[[0-?]*[ -/]*[@-~]", "");
            text = Regex.Replace(text, @"(?m)^\[stdout\] PB_LOG\t((?:[0-9a-f]{2})+)\r?$",
                match => "[ProxyBridge] " + Encoding.UTF8.GetString(Convert.FromHexString(match.Groups[1].Value)));
        }
        // Plain text only; HTML/terminal content is never executed by the viewer.
        return new { name, text, total_bytes = stream.Length, preview_bytes = bytes.Length, offset,
            next_offset = offset + bytes.Length, has_more = hasMore, truncated = hasMore || offset > 0, preview_limit_bytes = limit };
    }
}
