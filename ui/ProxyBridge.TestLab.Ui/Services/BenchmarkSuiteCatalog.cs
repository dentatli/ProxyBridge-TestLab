using System.Text.Json;
using System.Text.RegularExpressions;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record BenchmarkSuiteSaveRequest(string? Id, string Name, string Mode, BenchmarkTestRequest[] Tests);
public sealed record BenchmarkSuiteCatalogRequest(string Id);
public sealed record BenchmarkSuiteTemplate(string Id, string Name, string Mode, BenchmarkTestRequest[] Tests,
    DateTimeOffset CreatedAtUtc, DateTimeOffset UpdatedAtUtc);

/// <summary>Reusable choices only. A template never grants readiness or reuses a frozen launch plan.</summary>
public sealed class BenchmarkSuiteCatalog(AppStoragePaths storage, AppPaths app)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static readonly string[] Scenarios = ["tcp_rtt", "tcp_transfer", "tcp_rtt_three_modes", "tcp_connections"];
    private string[] TrafficScenarios
    {
        get
        {
            using var document = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(app.RepositoryRoot, "config", "traffic-workloads.json")));
            return document.RootElement.GetProperty("cases").EnumerateArray().Select(row => row.GetProperty("id").GetString()!).ToArray();
        }
    }
    private readonly SemaphoreSlim _gate = new(1, 1);
    private string CatalogPath => Path.Combine(storage.ConfigRoot, "benchmark-suites.json");
    private sealed record Catalog(int SchemaVersion, List<BenchmarkSuiteTemplate> Items);

    private static bool ValidId(string? id) => id is not null && Regex.IsMatch(id, "^preset-[a-f0-9]{32}$", RegexOptions.CultureInvariant);

    private static string Name(string? name)
    {
        var value = name?.Trim();
        if (string.IsNullOrEmpty(value) || value.Length > 64 || value.Any(char.IsControl))
            throw new InvalidOperationException("SUITE_NAME_INVALID");
        return value;
    }

    private void Validate(string mode, BenchmarkTestRequest[]? tests)
    {
        var remoteCases = TrafficScenarios;
        var traffic = tests?.Any(test => test is not null && remoteCases.Contains(test.Scenario)) == true;
        var allowed = traffic && mode == "remote" ? remoteCases : Scenarios;
        if (mode is not ("local" or "remote") || tests is null || tests.Length < 1 || tests.Length > allowed.Length ||
            tests.Any(test => test is null || !allowed.Contains(test.Scenario) ||
                test.Duration is not ("SHORT" or "NORMAL" or "LONG") || test.Load is not ("LOW" or "HIGH")) ||
            tests.Select(test => test.Scenario).Distinct(StringComparer.Ordinal).Count() != tests.Length)
            throw new InvalidOperationException("SUITE_SELECTION_INVALID");
    }

    public async Task<BenchmarkSuiteTemplate[]> ListAsync(CancellationToken token)
    {
        await _gate.WaitAsync(token);
        try { return (await ReadAsync(token)).OrderByDescending(item => item.UpdatedAtUtc).ThenBy(item => item.Id).ToArray(); }
        finally { _gate.Release(); }
    }

    public async Task<BenchmarkSuiteTemplate> SaveAsync(BenchmarkSuiteSaveRequest request, CancellationToken token)
    {
        var name = Name(request.Name);
        Validate(request.Mode, request.Tests);
        if (request.Id is not null && !ValidId(request.Id)) throw new InvalidOperationException("SUITE_NOT_FOUND");
        await _gate.WaitAsync(token);
        try
        {
            AssertLocal(CatalogPath);
            AppStoragePaths.EnsureSecureDirectory(storage.ConfigRoot);
            // Serialize writers from separate UI processes sharing this user's configuration.
            AssertLocal(CatalogPath + ".lock");
            using var lease = new FileStream(CatalogPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var items = await ReadAsync(token);
            var old = request.Id is null ? null : items.SingleOrDefault(item => item.Id == request.Id)
                ?? throw new InvalidOperationException("SUITE_NOT_FOUND");
            if (items.Any(item => item.Id != request.Id && string.Equals(item.Name, name, StringComparison.OrdinalIgnoreCase)))
                throw new InvalidOperationException("SUITE_NAME_EXISTS");
            if (old is null && items.Count >= 100) throw new InvalidOperationException("SUITE_CATALOG_LIMIT_REACHED");
            var now = DateTimeOffset.UtcNow;
            var entry = new BenchmarkSuiteTemplate(old?.Id ?? "preset-" + Guid.NewGuid().ToString("N"), name, request.Mode,
                request.Tests.OrderBy(test => Array.IndexOf(Scenarios.Concat(TrafficScenarios).ToArray(), test.Scenario)).ToArray(), old?.CreatedAtUtc ?? now, now);
            items.RemoveAll(item => item.Id == entry.Id);
            items.Add(entry);
            await WriteAsync(items, token);
            return entry;
        }
        finally { _gate.Release(); }
    }

    public async Task DeleteAsync(string id, CancellationToken token)
    {
        if (!ValidId(id)) throw new InvalidOperationException("SUITE_NOT_FOUND");
        await _gate.WaitAsync(token);
        try
        {
            AssertLocal(CatalogPath);
            AppStoragePaths.EnsureSecureDirectory(storage.ConfigRoot);
            AssertLocal(CatalogPath + ".lock");
            using var lease = new FileStream(CatalogPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var items = await ReadAsync(token);
            if (items.RemoveAll(item => item.Id == id) != 1) throw new InvalidOperationException("SUITE_NOT_FOUND");
            await WriteAsync(items, token);
        }
        finally { _gate.Release(); }
    }

    private async Task<List<BenchmarkSuiteTemplate>> ReadAsync(CancellationToken token)
    {
        AssertLocal(CatalogPath);
        if (!File.Exists(CatalogPath)) return [];
        if (new FileInfo(CatalogPath).Length > 262144) throw new InvalidOperationException("SUITE_CATALOG_UNAVAILABLE");
        await using var file = new FileStream(CatalogPath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        var catalog = await JsonSerializer.DeserializeAsync<Catalog>(file, Json, token);
        if (catalog is null || catalog.SchemaVersion != 1 || catalog.Items is null || catalog.Items.Count > 100 ||
            catalog.Items.Any(item => item is null || !ValidId(item.Id) || item.UpdatedAtUtc < item.CreatedAtUtc) ||
            catalog.Items.Select(item => item.Id).Distinct(StringComparer.Ordinal).Count() != catalog.Items.Count ||
            catalog.Items.Select(item => item.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != catalog.Items.Count)
            throw new InvalidOperationException("SUITE_CATALOG_UNAVAILABLE");
        foreach (var item in catalog.Items) { _ = Name(item.Name); Validate(item.Mode, item.Tests); }
        return catalog.Items;
    }

    private async Task WriteAsync(List<BenchmarkSuiteTemplate> items, CancellationToken token)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new Catalog(1, items), Json);
        if (bytes.Length > 262144) throw new InvalidOperationException("SUITE_CATALOG_LIMIT_REACHED");
        var temporary = CatalogPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            await using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                await file.WriteAsync(bytes, token);
            token.ThrowIfCancellationRequested();
            AssertLocal(CatalogPath);
            File.Move(temporary, CatalogPath, overwrite: true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private static void AssertLocal(string path)
    {
        for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("SUITE_CATALOG_UNAVAILABLE");
    }
}
