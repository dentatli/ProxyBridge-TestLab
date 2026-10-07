using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record BenchmarkBuildRequest(string BuildId);
public sealed record BenchmarkBuildRenameRequest(string BuildId, string DisplayName);
public sealed record BenchmarkBuildEntry(string Id, string DisplayName, string Contract, string BundleSha256,
    DateTimeOffset ObservedAtUtc, ProductSelectionRequest Request);

/// <summary>User labels are separate from the inspected binary identity. Paths remain DPAPI protected.</summary>
public sealed class BenchmarkBuildCatalog(AppStoragePaths storage, DpapiSecretProtector protector)
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private string CatalogPath => Path.Combine(storage.ConfigRoot, "benchmark-builds.dpapi");

    public static string Label(string? name, string contract)
    {
        var value = string.IsNullOrWhiteSpace(name) ? contract == "v4.0.0" ? "4.0.0" : "driver" : name.Trim();
        if (value.Length > 64 || value.Any(char.IsControl)) throw new InvalidOperationException("INVALID_BUILD_NAME");
        return value;
    }

    public static string Identity(string contract, string bundle)
    {
        if (contract is not ("driver" or "v4.0.0") || bundle.Length != 64 || !bundle.All(char.IsAsciiHexDigit))
            throw new InvalidOperationException("INVALID_BUILD_IDENTITY");
        return "build-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(contract + ":" + bundle.ToUpperInvariant()))).ToLowerInvariant();
    }

    public async Task<BenchmarkBuildEntry> RememberAsync(ProductSelectionRequest request, JsonElement observation, CancellationToken token)
    {
        if (!observation.GetProperty("files_observed").GetBoolean() || observation.GetProperty("declared_contract").GetString() != request.Contract)
            throw new InvalidOperationException("BUILD_FILES_NOT_OBSERVED");
        var bundle = observation.GetProperty("bundle_sha256").GetString() ?? "";
        var id = Identity(request.Contract, bundle);
        await _gate.WaitAsync(token);
        try
        {
            var entries = await ReadAsync(token);
            var old = entries.SingleOrDefault(entry => entry.Id == id);
            var name = Label(request.DisplayName ?? old?.DisplayName, request.Contract);
            var entry = new BenchmarkBuildEntry(id, name, request.Contract, bundle,
                DateTimeOffset.Parse(observation.GetProperty("observed_at_utc").GetString()!), request with { DisplayName = name });
            entries.RemoveAll(item => item.Id == id);
            entries.Add(entry);
            if (entries.Count > 256) throw new InvalidOperationException("BUILD_CATALOG_LIMIT_REACHED");
            await WriteAsync(entries, token);
            return entry;
        }
        finally { _gate.Release(); }
    }

    public async Task<BenchmarkBuildEntry?> FindAsync(string contract, string bundle, CancellationToken token)
    {
        var id = Identity(contract, bundle);
        await _gate.WaitAsync(token);
        try { return (await ReadAsync(token)).SingleOrDefault(entry => entry.Id == id); }
        finally { _gate.Release(); }
    }

    public async Task<ProductSelectionRequest> RequestAsync(string id, CancellationToken token)
    {
        await _gate.WaitAsync(token);
        try
        {
            var entry = (await ReadAsync(token)).SingleOrDefault(item => item.Id == id)
                ?? throw new InvalidOperationException("BUILD_NOT_FOUND");
            return entry.Request with { DisplayName = entry.DisplayName };
        }
        finally { _gate.Release(); }
    }

    public async Task RenameAsync(string id, string name, CancellationToken token)
    {
        await _gate.WaitAsync(token);
        try
        {
            var entries = await ReadAsync(token);
            var index = entries.FindIndex(item => item.Id == id);
            if (index < 0) throw new InvalidOperationException("BUILD_NOT_FOUND");
            var entry = entries[index];
            var label = Label(name, entry.Contract);
            entries[index] = entry with { DisplayName = label, Request = entry.Request with { DisplayName = label } };
            await WriteAsync(entries, token);
        }
        finally { _gate.Release(); }
    }

    public async Task<object> PublicAsync(CancellationToken token)
    {
        await _gate.WaitAsync(token);
        try
        {
            var entries = await ReadAsync(token);
            return new { items = entries.OrderByDescending(entry => entry.ObservedAtUtc).Select(entry => new
            {
                id = entry.Id, display_name = entry.DisplayName, contract = entry.Contract == "v4.0.0" ? "4.0.0" : "driver",
                observed_at_utc = entry.ObservedAtUtc, saved_observation_only = true, runtime_ready = false
            }).ToArray() };
        }
        finally { _gate.Release(); }
    }

    public static JsonElement Attach(JsonElement observation, BenchmarkBuildEntry entry)
    {
        var values = observation.EnumerateObject().ToDictionary(property => property.Name, property => property.Value.Clone());
        values["build_id"] = JsonSerializer.SerializeToElement(entry.Id);
        values["display_name"] = JsonSerializer.SerializeToElement(entry.DisplayName);
        return JsonSerializer.SerializeToElement(values);
    }

    private async Task<List<BenchmarkBuildEntry>> ReadAsync(CancellationToken token)
    {
        AssertNoReparse(CatalogPath);
        if (!File.Exists(CatalogPath)) return [];
        if (new FileInfo(CatalogPath).Length > 1024 * 1024) throw new InvalidOperationException("BUILD_CATALOG_SIZE_LIMIT");
        var ciphertext = await File.ReadAllBytesAsync(CatalogPath, token);
        byte[] plaintext;
        try { plaintext = protector.Unprotect(ciphertext); }
        finally { CryptographicOperations.ZeroMemory(ciphertext); }
        try
        {
            var entries = JsonSerializer.Deserialize<List<BenchmarkBuildEntry>>(plaintext)
                ?? throw new InvalidOperationException("BUILD_CATALOG_INVALID");
            if (entries.Count > 256 || entries.Select(entry => entry.Id).Distinct().Count() != entries.Count)
                throw new InvalidOperationException("BUILD_CATALOG_INVALID");
            foreach (var entry in entries)
                if (entry.Id != Identity(entry.Contract, entry.BundleSha256) || entry.Request.Contract != entry.Contract ||
                    Label(entry.DisplayName, entry.Contract) != entry.DisplayName)
                    throw new InvalidOperationException("BUILD_CATALOG_INVALID");
            return entries;
        }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
    }

    private async Task WriteAsync(List<BenchmarkBuildEntry> entries, CancellationToken token)
    {
        storage.EnsureSecureDirectories();
        AssertNoReparse(CatalogPath);
        var temporary = CatalogPath + ".tmp";
        AssertNoReparse(temporary);
        var plaintext = JsonSerializer.SerializeToUtf8Bytes(entries);
        byte[] encrypted;
        try { encrypted = protector.Protect(plaintext); }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
        try
        {
            if (encrypted.Length > 1024 * 1024) throw new InvalidOperationException("BUILD_CATALOG_SIZE_LIMIT");
            await File.WriteAllBytesAsync(temporary, encrypted, token);
            File.Move(temporary, CatalogPath, overwrite: true);
        }
        finally { CryptographicOperations.ZeroMemory(encrypted); }
    }

    private static void AssertNoReparse(string path)
    {
        for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("BUILD_CATALOG_REPARSE_POINT");
    }
}
