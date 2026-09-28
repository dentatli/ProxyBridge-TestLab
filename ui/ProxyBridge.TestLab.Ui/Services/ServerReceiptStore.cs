using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class ServerReceiptStore(AppStoragePaths paths, DpapiSecretProtector protector)
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true };
    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task<SignedServerReceipt> CreateAsync(
        string targetHash,
        IReadOnlyList<string> fingerprints,
        IReadOnlyDictionary<string, string> artifactHashes,
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            paths.EnsureSecureDirectories();
            var key = await LoadOrCreateKeyUnsafeAsync(cancellationToken);
            try
            {
                var issued = DateTimeOffset.UtcNow;
                var receipt = new ServerReadinessReceipt(
                    1,
                    Guid.NewGuid().ToString("N"),
                    targetHash,
                    fingerprints.Order(StringComparer.Ordinal).ToArray(),
                    new SortedDictionary<string, string>(artifactHashes.ToDictionary(item => item.Key, item => item.Value, StringComparer.Ordinal), StringComparer.Ordinal),
                    issued,
                    issued.AddHours(24));
                var signature = Sign(receipt, key);
                var signed = new SignedServerReceipt(receipt, signature);
                await WriteAtomicAsync(paths.ServerReceiptPath, JsonSerializer.Serialize(signed, JsonOptions) + Environment.NewLine, cancellationToken);
                return signed;
            }
            finally { CryptographicOperations.ZeroMemory(key); }
        }
        finally { _gate.Release(); }
    }

    public async Task<SignedServerReceipt?> LoadValidAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            try
            {
                if (!File.Exists(paths.ServerReceiptPath) || !File.Exists(paths.ReceiptKeyPath)) return null;
                var text = await File.ReadAllTextAsync(paths.ServerReceiptPath, cancellationToken);
                var signed = JsonSerializer.Deserialize<SignedServerReceipt>(text, JsonOptions);
                if (signed is null || signed.Receipt.SchemaVersion != 1) return null;
                var key = await LoadOrCreateKeyUnsafeAsync(cancellationToken);
                try
                {
                    if (key.Length != 32) return null;
                    var expected = Sign(signed.Receipt, key);
                    var left = Convert.FromBase64String(expected);
                    var right = Convert.FromBase64String(signed.Signature);
                    try { return CryptographicOperations.FixedTimeEquals(left, right) ? signed : null; }
                    finally { CryptographicOperations.ZeroMemory(left); CryptographicOperations.ZeroMemory(right); }
                }
                finally { CryptographicOperations.ZeroMemory(key); }
            }
            catch (JsonException) { return null; }
            catch (FormatException) { return null; }
            catch (CryptographicException) { return null; }
            catch (System.ComponentModel.Win32Exception) { return null; }
        }
        finally { _gate.Release(); }
    }

    private async Task<byte[]> LoadOrCreateKeyUnsafeAsync(CancellationToken cancellationToken)
    {
        if (File.Exists(paths.ReceiptKeyPath))
        {
            var envelope = await File.ReadAllTextAsync(paths.ReceiptKeyPath, cancellationToken);
            var ciphertext = Convert.FromBase64String(envelope.Trim());
            try { return protector.Unprotect(ciphertext); }
            finally { CryptographicOperations.ZeroMemory(ciphertext); }
        }

        var key = RandomNumberGenerator.GetBytes(32);
        var protectedKey = protector.Protect(key);
        try { await WriteAtomicAsync(paths.ReceiptKeyPath, Convert.ToBase64String(protectedKey) + Environment.NewLine, cancellationToken); }
        finally { CryptographicOperations.ZeroMemory(protectedKey); }
        return key;
    }

    private static string Sign(ServerReadinessReceipt receipt, byte[] key)
    {
        var canonical = JsonSerializer.SerializeToUtf8Bytes(receipt, JsonOptions);
        try { return Convert.ToBase64String(HMACSHA256.HashData(key, canonical)); }
        finally { CryptographicOperations.ZeroMemory(canonical); }
    }

    private static async Task WriteAtomicAsync(string path, string content, CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(path) ?? throw new InvalidOperationException("SERVER_RECEIPT_DIRECTORY_INVALID");
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

public sealed record ServerReadinessReceipt(
    int SchemaVersion,
    string ReceiptId,
    string TargetHash,
    IReadOnlyList<string> HostFingerprints,
    IReadOnlyDictionary<string, string> ArtifactSha256,
    DateTimeOffset IssuedUtc,
    DateTimeOffset ExpiresUtc);

public sealed record SignedServerReceipt(ServerReadinessReceipt Receipt, string Signature);
