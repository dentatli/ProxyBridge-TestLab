using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public interface IRunSettingsProvider
{
    Task<SettingsView> GetViewAsync(CancellationToken cancellationToken);
}

public sealed class SettingsStore(AppStoragePaths paths, DpapiSecretProtector protector, LocalArtifactService localArtifacts) : IRunSettingsProvider
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };
    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task<SettingsSnapshot> LoadAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try { return await LoadUnsafeAsync(cancellationToken); }
        finally { _gate.Release(); }
    }

    public async Task<SettingsView> GetViewAsync(CancellationToken cancellationToken)
    {
        var snapshot = await LoadAsync(cancellationToken);
        return ToView(snapshot);
    }

    public async Task<SettingsValidationResult> ValidateAsync(SettingsUpdateRequest request, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var existing = await LoadUnsafeAsync(cancellationToken);
            var protectedValues = MergeProtected(existing.ProtectedValues, request);
            localArtifacts.ApplyDerivedDefaults(request.Settings, protectedValues);
            return SettingsSchema.Validate(request.Settings, protectedValues, localArtifacts);
        }
        finally { _gate.Release(); }
    }

    public async Task<SettingsView> SaveAsync(SettingsUpdateRequest request, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            paths.EnsureSecureDirectories();
            var existing = await LoadUnsafeAsync(cancellationToken);
            var protectedValues = MergeProtected(existing.ProtectedValues, request);
            localArtifacts.ApplyDerivedDefaults(request.Settings, protectedValues);
            var validation = SettingsSchema.Validate(request.Settings, protectedValues, localArtifacts);
            if (!validation.ValidForSave) throw new SettingsValidationException(validation);

            var snapshotId = Guid.NewGuid().ToString("N");
            var publicDocument = new SettingsDocument { SnapshotId = snapshotId, Settings = request.Settings };
            var publicJson = JsonSerializer.Serialize(publicDocument, JsonOptions) + Environment.NewLine;
            var secretJsonBytes = JsonSerializer.SerializeToUtf8Bytes(protectedValues, JsonOptions);
            byte[] ciphertext;
            try { ciphertext = protector.Protect(secretJsonBytes); }
            finally { CryptographicOperations.ZeroMemory(secretJsonBytes); }

            try
            {
                var envelope = JsonSerializer.Serialize(new SecretEnvelope(1, "DPAPI_CURRENT_USER", Convert.ToBase64String(ciphertext), snapshotId), JsonOptions) + Environment.NewLine;
                await WriteAtomicAsync(paths.ProtectedSettingsPath, envelope, cancellationToken);
                await WriteAtomicAsync(paths.PublicSettingsPath, publicJson, cancellationToken);
            }
            finally { CryptographicOperations.ZeroMemory(ciphertext); }

            var updated = File.GetLastWriteTimeUtc(paths.PublicSettingsPath);
            return ToView(new SettingsSnapshot(request.Settings, protectedValues, validation, updated));
        }
        finally { _gate.Release(); }
    }

    private async Task<SettingsSnapshot> LoadUnsafeAsync(CancellationToken cancellationToken)
    {
        paths.EnsureSecureDirectories();
        var publicSettings = new PublicSettings();
        var publicSnapshotId = "";
        DateTimeOffset? updatedUtc = null;
        if (File.Exists(paths.PublicSettingsPath))
        {
            await using var stream = File.OpenRead(paths.PublicSettingsPath);
            var document = await JsonSerializer.DeserializeAsync<SettingsDocument>(stream, JsonOptions, cancellationToken)
                ?? throw new InvalidOperationException("PUBLIC_SETTINGS_INVALID");
            if (document.SchemaVersion != 1) throw new InvalidOperationException("PUBLIC_SETTINGS_SCHEMA_UNSUPPORTED");
            publicSettings = document.Settings;
            publicSnapshotId = document.SnapshotId;
            updatedUtc = File.GetLastWriteTimeUtc(paths.PublicSettingsPath);
        }

        var protectedValues = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (File.Exists(paths.ProtectedSettingsPath))
        {
            var envelopeText = await File.ReadAllTextAsync(paths.ProtectedSettingsPath, cancellationToken);
            var envelope = JsonSerializer.Deserialize<SecretEnvelope>(envelopeText, JsonOptions)
                ?? throw new InvalidOperationException("PROTECTED_SETTINGS_INVALID");
            if (envelope.SchemaVersion != 1 || envelope.Protection != "DPAPI_CURRENT_USER") throw new InvalidOperationException("PROTECTED_SETTINGS_SCHEMA_UNSUPPORTED");
            if (!string.IsNullOrWhiteSpace(publicSnapshotId) || !string.IsNullOrWhiteSpace(envelope.SnapshotId))
            {
                if (!string.Equals(publicSnapshotId, envelope.SnapshotId, StringComparison.Ordinal)) throw new InvalidOperationException("SETTINGS_SNAPSHOT_MISMATCH");
            }
            var ciphertext = Convert.FromBase64String(envelope.Ciphertext);
            byte[] plaintext;
            try { plaintext = protector.Unprotect(ciphertext); }
            finally { CryptographicOperations.ZeroMemory(ciphertext); }
            try
            {
                var deserialized = JsonSerializer.Deserialize<Dictionary<string, string>>(plaintext, JsonOptions);
                protectedValues = deserialized is null
                    ? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                    : new Dictionary<string, string>(deserialized, StringComparer.OrdinalIgnoreCase);
            }
            finally { CryptographicOperations.ZeroMemory(plaintext); }

            if (string.IsNullOrWhiteSpace(publicSettings.ServerConnection.Username) &&
                protectedValues.TryGetValue("server_connection.username", out var legacyUsername))
            {
                publicSettings.ServerConnection.Username = legacyUsername;
            }
            protectedValues.Remove("server_connection.username");
            foreach (var key in protectedValues.Keys.ToArray())
            {
                if (!SettingsSchema.ProtectedFieldIds.Contains(key)) protectedValues.Remove(key);
            }
        }

        foreach (var item in localArtifacts.GetProtectedDefaults())
        {
            if (!protectedValues.ContainsKey(item.Key)) protectedValues[item.Key] = item.Value;
        }
        localArtifacts.ApplyDerivedDefaults(publicSettings, protectedValues);

        var validation = SettingsSchema.Validate(publicSettings, protectedValues, localArtifacts);
        return new SettingsSnapshot(publicSettings, protectedValues, validation, updatedUtc);
    }

    private static Dictionary<string, string> MergeProtected(IReadOnlyDictionary<string, string> existing, SettingsUpdateRequest request)
    {
        var merged = new Dictionary<string, string>(existing, StringComparer.OrdinalIgnoreCase);
        foreach (var key in request.ClearProtected)
        {
            if (!SettingsSchema.ProtectedFieldIds.Contains(key)) throw new InvalidOperationException("UNKNOWN_PROTECTED_FIELD");
            merged.Remove(key);
        }
        foreach (var item in request.ProtectedValues)
        {
            if (!SettingsSchema.ProtectedFieldIds.Contains(item.Key)) throw new InvalidOperationException("UNKNOWN_PROTECTED_FIELD");
            if (item.Value is not null) merged[item.Key] = item.Value;
        }
        return merged;
    }

    private static SettingsView ToView(SettingsSnapshot snapshot)
    {
        var presence = SettingsSchema.ProtectedFieldIds.ToDictionary(
            field => field,
            field => snapshot.ProtectedValues.TryGetValue(field, out var value) && !string.IsNullOrWhiteSpace(value),
            StringComparer.OrdinalIgnoreCase);
        return new SettingsView(1, snapshot.Settings, presence, snapshot.Validation, snapshot.UpdatedUtc);
    }

    private static async Task WriteAtomicAsync(string path, string content, CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(path) ?? throw new InvalidOperationException("SETTINGS_DIRECTORY_INVALID");
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            await File.WriteAllTextAsync(temporary, content, Utf8NoBom, cancellationToken);
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    private sealed record SecretEnvelope(int SchemaVersion, string Protection, string Ciphertext, string SnapshotId = "");
}

public sealed class SettingsValidationException(SettingsValidationResult validation) : Exception("SETTINGS_VALIDATION_FAILED")
{
    public SettingsValidationResult Validation { get; } = validation;
}
