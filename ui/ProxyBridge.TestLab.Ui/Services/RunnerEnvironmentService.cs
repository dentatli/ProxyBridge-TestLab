using System.Security.Cryptography;
using System.Text;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class RunnerEnvironmentService(AppStoragePaths paths, LocalArtifactService localArtifacts)
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);

    public async Task<RunnerInputLease> MaterializeAsync(SettingsSnapshot snapshot, string runId, CancellationToken cancellationToken)
    {
        if (!snapshot.Validation.Ready) throw new InvalidOperationException("RUNNER_INPUT_SETTINGS_NOT_READY");
        return await MaterializeCoreAsync(snapshot, runId, protocolOnly: false, cancellationToken);
    }

    public async Task<RunnerInputLease> MaterializeProtocolSmokeAsync(SettingsSnapshot snapshot, string runId, CancellationToken cancellationToken)
    {
        if (!localArtifacts.GetProtocolRuntimeStatus().Ready) throw new InvalidOperationException("PROTOCOL_RUNTIME_NOT_READY");
        return await MaterializeCoreAsync(snapshot, runId, protocolOnly: true, cancellationToken);
    }

    private async Task<RunnerInputLease> MaterializeCoreAsync(SettingsSnapshot snapshot, string runId, bool protocolOnly, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(runId) || runId.Any(character => !(char.IsLetterOrDigit(character) || character is '-' or '_' or '.')))
            throw new InvalidOperationException("RUNNER_INPUT_RUN_ID_INVALID");

        paths.EnsureSecureDirectories();
        var runRoot = Path.GetFullPath(Path.Combine(paths.RuntimeRoot, runId));
        var expectedPrefix = Path.GetFullPath(paths.RuntimeRoot) + Path.DirectorySeparatorChar;
        if (!runRoot.StartsWith(expectedPrefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("RUNNER_INPUT_PATH_INVALID");
        AppStoragePaths.EnsureSecureDirectory(runRoot);
        var lockPath = Path.Combine(runRoot, ".lease");
        FileStream? leaseStream = null;

        var values = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var field in SettingsSchema.Fields.Where(field => !string.IsNullOrWhiteSpace(field.EnvironmentKey)))
        {
            var value = field.Sensitive
                ? (snapshot.ProtectedValues.TryGetValue(field.Id, out var protectedValue) ? protectedValue : null)
                : SettingsSchema.GetPublicEnvironmentValue(snapshot.Settings, field.Id);
            if (!string.IsNullOrEmpty(value)) values[field.EnvironmentKey!] = value;
        }
        if (protocolOnly) localArtifacts.AddProtocolRunnerValues(snapshot, values);
        else localArtifacts.AddRunnerValues(snapshot, values);

        var content = string.Join(Environment.NewLine, values.Select(pair => $"{pair.Key}={pair.Value}")) + Environment.NewLine;
        var bytes = Utf8NoBom.GetBytes(content);
        var path = Path.Combine(runRoot, "input.env");
        try
        {
            leaseStream = new FileStream(lockPath, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None);
            await File.WriteAllBytesAsync(path, bytes, cancellationToken);
            CryptographicOperations.ZeroMemory(bytes);
            return new RunnerInputLease(path, runRoot, lockPath, leaseStream);
        }
        catch
        {
            CryptographicOperations.ZeroMemory(bytes);
            leaseStream?.Dispose();
            if (File.Exists(path)) File.Delete(path);
            if (File.Exists(lockPath)) File.Delete(lockPath);
            throw;
        }
    }
}

public sealed class RunnerInputLease : IAsyncDisposable
{
    private readonly string _runRoot;
    private readonly string _lockPath;
    private readonly FileStream _leaseStream;

    public RunnerInputLease(string path, string runRoot, string lockPath, FileStream leaseStream)
    {
        Path = path;
        RootPath = runRoot;
        _runRoot = runRoot;
        _lockPath = lockPath;
        _leaseStream = leaseStream;
    }

    public string Path { get; }
    public string RootPath { get; }

    public async ValueTask DisposeAsync()
    {
        await _leaseStream.DisposeAsync();
        try
        {
            if (File.Exists(Path)) File.Delete(Path);
            if (File.Exists(_lockPath)) File.Delete(_lockPath);
            if (Directory.Exists(_runRoot) && !Directory.EnumerateFileSystemEntries(_runRoot).Any()) Directory.Delete(_runRoot);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
