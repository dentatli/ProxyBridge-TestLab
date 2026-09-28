using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class ServerTrustStore(AppStoragePaths paths)
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true };
    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task<ServerTrustRecord?> LoadAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (!File.Exists(paths.ServerTrustPath)) return null;
            await using var stream = File.OpenRead(paths.ServerTrustPath);
            var record = await JsonSerializer.DeserializeAsync<ServerTrustRecord>(stream, JsonOptions, cancellationToken);
            if (record is null || record.SchemaVersion != 1 || record.KnownHostLines.Count == 0)
                throw new InvalidOperationException("SERVER_TRUST_RECORD_INVALID");
            if (!File.Exists(paths.KnownHostsPath)) return null;
            var activeLines = (await File.ReadAllLinesAsync(paths.KnownHostsPath, cancellationToken))
                .Where(line => !string.IsNullOrWhiteSpace(line)).OrderBy(line => line, StringComparer.Ordinal);
            if (!activeLines.SequenceEqual(record.KnownHostLines.OrderBy(line => line, StringComparer.Ordinal), StringComparer.Ordinal)) return null;
            return record;
        }
        finally { _gate.Release(); }
    }

    public async Task SaveAsync(string targetHash, HostKeyObservation observation, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            paths.EnsureSecureDirectories();
            var record = new ServerTrustRecord(1, targetHash, observation.Fingerprints, observation.KnownHostLines, DateTimeOffset.UtcNow);
            var json = JsonSerializer.Serialize(record, JsonOptions) + Environment.NewLine;
            await WriteAtomicAsync(paths.ServerTrustPath, json, cancellationToken);
            await WriteAtomicAsync(paths.KnownHostsPath, string.Join("\n", observation.KnownHostLines) + "\n", cancellationToken);
        }
        finally { _gate.Release(); }
    }

    public static string ComputeTargetHash(ServerTarget target)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes($"{target.Host.ToLowerInvariant()}\n{target.Port}\n{target.Username}"));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    public static bool Matches(ServerTrustRecord record, string targetHash, HostKeyObservation observation) =>
        string.Equals(record.TargetHash, targetHash, StringComparison.Ordinal) &&
        record.KnownHostLines.Order(StringComparer.Ordinal).SequenceEqual(observation.KnownHostLines.Order(StringComparer.Ordinal), StringComparer.Ordinal);

    private static async Task WriteAtomicAsync(string path, string content, CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(path) ?? throw new InvalidOperationException("SERVER_TRUST_DIRECTORY_INVALID");
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            await File.WriteAllTextAsync(temporary, content, Utf8NoBom, cancellationToken);
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

public sealed record ServerTrustRecord(
    int SchemaVersion,
    string TargetHash,
    IReadOnlyList<string> Fingerprints,
    IReadOnlyList<string> KnownHostLines,
    DateTimeOffset TrustedUtc);
