using System.Text;
using System.Text.Json;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class RunJobStore(AppStoragePaths paths)
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };
    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task SaveAsync(RunJobView job, CancellationToken cancellationToken)
    {
        ValidateRunId(job.RunId);
        await _gate.WaitAsync(cancellationToken);
        try
        {
            paths.EnsureSecureDirectories();
            var path = Path.Combine(paths.JobsRoot, job.RunId + ".json");
            var temporary = Path.Combine(paths.JobsRoot, $".{job.RunId}.{Guid.NewGuid():N}.tmp");
            try
            {
                await File.WriteAllTextAsync(temporary, JsonSerializer.Serialize(job, JsonOptions) + Environment.NewLine, Utf8NoBom, cancellationToken);
                File.Move(temporary, path, true);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        finally { _gate.Release(); }
    }

    public async Task<IReadOnlyList<RunJobView>> LoadAllAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            paths.EnsureSecureDirectories();
            var jobs = new List<RunJobView>();
            foreach (var path in Directory.EnumerateFiles(paths.JobsRoot, "*.json", SearchOption.TopDirectoryOnly))
            {
                try
                {
                    await using var stream = File.OpenRead(path);
                    var job = await JsonSerializer.DeserializeAsync<RunJobView>(stream, JsonOptions, cancellationToken);
                    if (job is not null && Path.GetFileNameWithoutExtension(path).Equals(job.RunId, StringComparison.Ordinal)) jobs.Add(job);
                }
                catch (JsonException) { }
                catch (IOException) { }
            }
            return jobs.OrderByDescending(job => job.UpdatedUtc).ToArray();
        }
        finally { _gate.Release(); }
    }

    public static bool IsTerminal(string state) => state is "CANCELLED" or "COMPLETED" or "SAFETY_STOPPED" or "FAILED_TO_START";

    private static void ValidateRunId(string runId)
    {
        if (string.IsNullOrWhiteSpace(runId) || runId.Any(ch => !(char.IsLetterOrDigit(ch) || ch is '-' or '_' or '.')))
            throw new InvalidOperationException("RUN_ID_INVALID");
    }
}
