using System.Diagnostics;
using System.Text;
using System.Text.Json;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public interface IRunCatalogProvider
{
    Task<IReadOnlyList<CatalogScenario>> GetAllAsync(CancellationToken cancellationToken);
}

public sealed class CatalogService(AppPaths paths) : IRunCatalogProvider
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly SemaphoreSlim _gate = new(1, 1);
    private IReadOnlyList<CatalogScenario>? _snapshot;
    private DateTime _snapshotStampUtc;

    public async Task<IReadOnlyList<CatalogScenario>> GetAllAsync(CancellationToken cancellationToken)
    {
        var currentStamp = GetCatalogStampUtc();
        if (_snapshot is not null && currentStamp == _snapshotStampUtc)
        {
            return _snapshot;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            currentStamp = GetCatalogStampUtc();
            if (_snapshot is not null && currentStamp == _snapshotStampUtc)
            {
                return _snapshot;
            }

            _snapshot = await ExportCatalogAsync(cancellationToken);
            _snapshotStampUtc = currentStamp;
            return _snapshot;
        }
        finally
        {
            _gate.Release();
        }
    }

    private DateTime GetCatalogStampUtc()
    {
        var files = Directory.EnumerateFiles(paths.ScenarioRoot, "*.json", SearchOption.AllDirectories)
            .Append(paths.KnownDefectsPath);
        return files.Select(File.GetLastWriteTimeUtc).DefaultIfEmpty(DateTime.MinValue).Max();
    }

    private async Task<IReadOnlyList<CatalogScenario>> ExportCatalogAsync(CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = new UTF8Encoding(false),
            StandardErrorEncoding = new UTF8Encoding(false)
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(paths.CatalogExportScript);
        startInfo.ArgumentList.Add("-ScenarioRoot");
        startInfo.ArgumentList.Add(paths.ScenarioRoot);
        startInfo.ArgumentList.Add("-KnownDefectsPath");
        startInfo.ArgumentList.Add(paths.KnownDefectsPath);

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("CATALOG_EXPORT_START_FAILED");
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var output = await outputTask;
        var error = await errorTask;

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"CATALOG_EXPORT_FAILED: {error.Trim()}");
        }

        var catalog = JsonSerializer.Deserialize<List<CatalogScenario>>(output, JsonOptions)
            ?? throw new InvalidOperationException("CATALOG_EXPORT_EMPTY");
        if (catalog.Count == 0 || catalog.Any(item => string.IsNullOrWhiteSpace(item.ScenarioId)))
        {
            throw new InvalidOperationException("CATALOG_EXPORT_INVALID");
        }

        return catalog.OrderBy(item => item.ScenarioId, StringComparer.OrdinalIgnoreCase).ToArray();
    }
}
