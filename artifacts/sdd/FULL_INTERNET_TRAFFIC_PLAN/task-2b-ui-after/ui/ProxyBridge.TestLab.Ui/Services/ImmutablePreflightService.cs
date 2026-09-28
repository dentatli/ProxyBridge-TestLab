using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record ImmutablePreflightResult(bool Passed, string Status, string Detail, DateTimeOffset? ExpiresUtc, bool Cached);

public interface IRunImmutablePreflightService
{
    Task<ImmutablePreflightResult> VerifyAsync(
        IReadOnlyList<string> scenarioIds,
        bool executeIfNeeded,
        DerivedRunCapabilitySnapshot derivedCapabilities,
        CancellationToken cancellationToken);
}

public sealed record SignedImmutablePreflightReceipt(string ContractDigest, DateTimeOffset IssuedUtc, DateTimeOffset ExpiresUtc, string Signature);

public sealed class ImmutablePreflightReceiptAuthority
{
    private readonly byte[] _key = RandomNumberGenerator.GetBytes(32);

    public SignedImmutablePreflightReceipt Issue(string digest, DateTimeOffset now)
    {
        var expires = now.AddMinutes(2);
        return new(digest, now, expires, Sign(digest, now, expires));
    }

    public bool Validate(SignedImmutablePreflightReceipt? receipt, string digest, DateTimeOffset now)
    {
        if (receipt is null || receipt.ExpiresUtc <= now || !string.Equals(receipt.ContractDigest, digest, StringComparison.Ordinal)) return false;
        try
        {
            var expected = Convert.FromHexString(Sign(receipt.ContractDigest, receipt.IssuedUtc, receipt.ExpiresUtc));
            var supplied = Convert.FromHexString(receipt.Signature);
            return expected.Length == supplied.Length && CryptographicOperations.FixedTimeEquals(expected, supplied);
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private string Sign(string digest, DateTimeOffset issued, DateTimeOffset expires)
    {
        var canonical = $"{digest}\n{issued:O}\n{expires:O}";
        return Convert.ToHexString(HMACSHA256.HashData(_key, Encoding.UTF8.GetBytes(canonical))).ToLowerInvariant();
    }
}

public sealed class PowerShellImmutablePreflightService(
    AppPaths appPaths,
    SettingsStore settingsStore,
    RunnerEnvironmentService runnerEnvironment) : IRunImmutablePreflightService
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly ImmutablePreflightReceiptAuthority _authority = new();
    private SignedImmutablePreflightReceipt? _receipt;

    public async Task<ImmutablePreflightResult> VerifyAsync(
        IReadOnlyList<string> scenarioIds,
        bool executeIfNeeded,
        DerivedRunCapabilitySnapshot derivedCapabilities,
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var snapshot = await settingsStore.LoadAsync(cancellationToken);
            if (!snapshot.Validation.Ready) return new(false, "SETTINGS_NOT_READY", "Environment Setup is incomplete.", null, false);
            var workId = $"preflight-{Guid.NewGuid():N}";
            await using var input = await runnerEnvironment.MaterializeAsync(snapshot, workId, cancellationToken);
            var digest = ComputeContractDigest(scenarioIds, input.Path);
            var now = DateTimeOffset.UtcNow;
            if (_authority.Validate(_receipt, digest, now))
                return new(true, "READY", "The signed immutable preflight receipt is current for this exact selection.", _receipt!.ExpiresUtc, true);
            if (!executeIfNeeded)
                return new(false, "REVIEW_REQUIRED", "The reviewed immutable preflight receipt expired or no longer matches this selection.", null, false);

            var suitePath = Path.Combine(input.RootPath, "suite.json");
            var capabilitiesPath = Path.Combine(input.RootPath, "capabilities.json");
            var evidenceRoot = Path.Combine(input.RootPath, "evidence");
            await WriteSuiteAsync(scenarioIds, suitePath, cancellationToken);
            await WriteCapabilitiesAsync(snapshot.Settings.Capabilities, derivedCapabilities, capabilitiesPath, cancellationToken);
            Directory.CreateDirectory(evidenceRoot);
            try
            {
                var passed = await ExecuteRunnerPreflightAsync(input.Path, suitePath, capabilitiesPath, evidenceRoot, cancellationToken);
                if (!passed)
                    return new(false, "FAILED", "Immutable preflight failed. Recheck local binaries, clean product state, endpoint ports, proxy reachability and the direct baseline.", null, false);
                _receipt = _authority.Issue(digest, DateTimeOffset.UtcNow);
                return new(true, "READY", "Exact local hashes, shared state, endpoint channels, proxy reachability and direct baseline passed.", _receipt.ExpiresUtc, false);
            }
            finally
            {
                if (Directory.Exists(evidenceRoot)) Directory.Delete(evidenceRoot, recursive: true);
                if (File.Exists(suitePath)) File.Delete(suitePath);
                if (File.Exists(capabilitiesPath)) File.Delete(capabilitiesPath);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return new(false, "FAILED", "Immutable preflight could not complete. No real scenario was started.", null, false);
        }
        finally { _gate.Release(); }
    }

    private async Task<bool> ExecuteRunnerPreflightAsync(
        string environmentPath,
        string suitePath,
        string capabilitiesPath,
        string evidenceRoot,
        CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            WorkingDirectory = appPaths.RepositoryRoot,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Utf8NoBom,
            StandardErrorEncoding = Utf8NoBom
        };
        foreach (var argument in new[]
        {
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", appPaths.RunnerPath,
            "-EnvPath", environmentPath, "-CapabilitiesPath", capabilitiesPath, "-SuitePath", suitePath,
            "-KnownDefectsPath", appPaths.KnownDefectsPath, "-ClientContractPath", appPaths.ClientContractPath,
            "-RuntimeConfigPath", appPaths.RuntimeConfigPath, "-ScenarioRoot", appPaths.ScenarioRoot,
            "-MockFixtureRoot", appPaths.MockFixtureRoot, "-OutputRoot", evidenceRoot,
            "-AllowProductRuntime", "-PrepareRuntimeEnvironment", "-PreflightOnly"
        }) startInfo.ArgumentList.Add(argument);

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("PREFLIGHT_START_RETURNED_NULL");
        var stdout = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderr = process.StandardError.ReadToEndAsync(cancellationToken);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(3));
        try { await process.WaitForExitAsync(timeout.Token); }
        catch (OperationCanceledException)
        {
            if (!process.HasExited) process.Kill();
            await process.WaitForExitAsync(CancellationToken.None);
            _ = await stdout;
            _ = await stderr;
            return false;
        }
        _ = await stdout;
        _ = await stderr;
        if (process.ExitCode != 0) return false;

        var runRoot = Directory.EnumerateDirectories(evidenceRoot, "*", SearchOption.TopDirectoryOnly)
            .Where(path => (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0)
            .OrderByDescending(Directory.GetLastWriteTimeUtc)
            .FirstOrDefault();
        if (runRoot is null) return false;
        return ReadAllPassed(Path.Combine(runRoot, "immutable-preflight.json")) &&
               ReadBoolean(Path.Combine(runRoot, "environment-preparation-result.json"), "prepared") &&
               ReadBoolean(Path.Combine(runRoot, "direct-baseline-result.json"), "passed");
    }

    private string ComputeContractDigest(IReadOnlyList<string> scenarioIds, string environmentPath)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        void AddText(string value) => hash.AppendData(Encoding.UTF8.GetBytes(value));
        foreach (var scenario in scenarioIds.Order(StringComparer.OrdinalIgnoreCase)) AddText($"scenario:{scenario}\n");
        hash.AppendData(File.ReadAllBytes(environmentPath));
        var roots = new[] { appPaths.ScenarioRoot, Path.Combine(appPaths.RepositoryRoot, "modules"), Path.Combine(appPaths.RepositoryRoot, "config") };
        var files = roots.SelectMany(root => Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
            .Append(appPaths.RunnerPath)
            .Where(path => (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0)
            .Order(StringComparer.OrdinalIgnoreCase);
        foreach (var path in files)
        {
            AddText(Path.GetRelativePath(appPaths.RepositoryRoot, path).Replace('\\', '/') + "\n");
            hash.AppendData(File.ReadAllBytes(path));
        }
        return Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant();
    }

    private async Task WriteSuiteAsync(IReadOnlyList<string> scenarioIds, string destination, CancellationToken cancellationToken)
    {
        var root = JsonNode.Parse(await File.ReadAllTextAsync(appPaths.RealSuitePath, cancellationToken))?.AsObject()
            ?? throw new InvalidOperationException("PREFLIGHT_SUITE_INVALID");
        var selection = root["selection"]?.AsObject() ?? throw new InvalidOperationException("PREFLIGHT_SELECTION_INVALID");
        selection["include_tags"] = new JsonArray();
        selection["exclude_tags"] = new JsonArray();
        selection["exclude_scenario_ids"] = new JsonArray();
        selection["include_scenario_ids"] = new JsonArray(scenarioIds.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray());
        await File.WriteAllTextAsync(destination, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine, Utf8NoBom, cancellationToken);
    }

    private async Task WriteCapabilitiesAsync(
        CapabilitySettings settings,
        DerivedRunCapabilitySnapshot derivedCapabilities,
        string destination,
        CancellationToken cancellationToken)
    {
        var root = JsonNode.Parse(await File.ReadAllTextAsync(appPaths.CapabilitiesPath, cancellationToken))?.AsObject()
            ?? throw new InvalidOperationException("PREFLIGHT_CAPABILITIES_INVALID");
        var capabilities = root["capabilities"]?.AsObject() ?? throw new InvalidOperationException("PREFLIGHT_CAPABILITIES_SECTION_INVALID");
        RunCapabilityDocument.Apply(capabilities, settings, derivedCapabilities);
        await File.WriteAllTextAsync(destination, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine, Utf8NoBom, cancellationToken);
    }

    private static bool ReadAllPassed(string path)
    {
        if (!File.Exists(path)) return false;
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        return document.RootElement.ValueKind == JsonValueKind.Array &&
               document.RootElement.EnumerateArray().All(item => item.TryGetProperty("status", out var value) && value.GetString() == "PASS");
    }

    private static bool ReadBoolean(string path, string property)
    {
        if (!File.Exists(path)) return false;
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        return document.RootElement.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.True;
    }
}
