using System.Diagnostics;
using System.Text;
using System.Text.Json;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class ServerProtocolSmokeService(
    AppPaths appPaths,
    AppStoragePaths storagePaths,
    SettingsStore settingsStore,
    ServerProvisioningService serverProvisioning,
    RunnerEnvironmentService runnerEnvironment)
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task<ServerProtocolSmokeView> RunAsync(CancellationToken cancellationToken)
    {
        if (!await _gate.WaitAsync(0, cancellationToken))
            return new ServerProtocolSmokeView("BUSY", "An endpoint protocol smoke is already running.", 0, 0, 0, []);
        try
        {
            var server = await serverProvisioning.GetStatusAsync(cancellationToken);
            if (server.State != "READY")
                return new ServerProtocolSmokeView("BLOCKED", "Validate and provision the test server before endpoint protocol smoke.", 0, 0, 0, []);

            var snapshot = await settingsStore.LoadAsync(cancellationToken);
            var runId = $"protocol-smoke-{DateTimeOffset.UtcNow:yyyyMMddTHHmmssZ}-{Guid.NewGuid():N}";
            RunnerInputLease lease;
            try { lease = await runnerEnvironment.MaterializeProtocolSmokeAsync(snapshot, runId, cancellationToken); }
            catch (InvalidOperationException)
            {
                return new ServerProtocolSmokeView("BLOCKED", "The packaged protocol worker runtime is missing or failed integrity validation.", 0, 0, 0, []);
            }
            try
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
                    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(appPaths.RepositoryRoot, "scripts", "Invoke-ProtocolOnlySmoke.ps1"),
                    "-EnvPath", lease.Path,
                    "-ScenarioRoot", appPaths.ScenarioRoot,
                    "-RuntimeConfigPath", appPaths.RuntimeConfigPath,
                    "-OutputRoot", lease.RootPath
                }) startInfo.ArgumentList.Add(argument);

                using var process = Process.Start(startInfo);
                if (process is null)
                    return Failed("The endpoint protocol smoke process could not be started.");
                var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
                var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeout.CancelAfter(TimeSpan.FromMinutes(2));
                try { await process.WaitForExitAsync(timeout.Token); }
                catch (OperationCanceledException)
                {
                    try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
                    await process.WaitForExitAsync(CancellationToken.None);
                    if (cancellationToken.IsCancellationRequested) throw;
                    _ = await stdoutTask; _ = await stderrTask;
                    return Failed("The endpoint protocol smoke exceeded its bounded two-minute deadline.");
                }

                var stdout = await stdoutTask;
                _ = await stderrTask;
                var jsonLine = stdout.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
                    .Reverse()
                    .FirstOrDefault(IsProtocolSmokeSummary);
                if (string.IsNullOrWhiteSpace(jsonLine))
                    return Failed("The endpoint protocol smoke failed without exposing private connection details.");
                try
                {
                    using var document = JsonDocument.Parse(jsonLine);
                    var root = document.RootElement;
                    if (process.ExitCode != 0)
                    {
                        var errorCode = root.TryGetProperty("error_code", out var codeElement) ? codeElement.GetString() ?? "UNEXPECTED_FAILURE" : "UNEXPECTED_FAILURE";
                        var failureCode = root.TryGetProperty("failure_code", out var failureElement) ? failureElement.GetString() ?? "UNCLASSIFIED" : "UNCLASSIFIED";
                        if (errorCode.Any(character => !(char.IsAsciiLetterUpper(character) || char.IsDigit(character) || character == '_'))) errorCode = "UNEXPECTED_FAILURE";
                        if (failureCode.Any(character => !(char.IsAsciiLetterUpper(character) || char.IsDigit(character) || character == '_'))) failureCode = "UNCLASSIFIED";
                        return Failed($"The endpoint protocol smoke stopped at {errorCode}/{failureCode} without exposing private connection details.");
                    }
                    if (root.GetProperty("state").GetString() != "PASS" || root.GetProperty("proxybridge_started").GetBoolean())
                        return Failed("The endpoint protocol smoke did not satisfy its isolated no-product contract.");
                    var results = root.GetProperty("results").EnumerateArray().Select(item => new ServerProtocolSmokeScenarioView(
                        item.GetProperty("scenario_id").GetString() ?? "",
                        item.GetProperty("status").GetString() ?? "FAIL",
                        item.GetProperty("client_records").GetInt32(),
                        item.GetProperty("server_records").GetInt32(),
                        item.GetProperty("identities_matched").GetBoolean(),
                        item.GetProperty("payload_hash_matched").GetBoolean())).ToArray();
                    var count = root.GetProperty("scenario_count").GetInt32();
                    if (count != results.Length || results.Any(item => item.Status != "PASS" || !item.IdentitiesMatched || !item.PayloadHashMatched))
                        return Failed("The endpoint protocol smoke returned an inconsistent summary.");
                    return new ServerProtocolSmokeView("PASS", "DNS, TLS, HTTP and HTTPS endpoint contracts passed without starting ProxyBridge.", count, count, 0, results);
                }
                catch (Exception exception) when (exception is JsonException or InvalidOperationException or KeyNotFoundException)
                {
                    return Failed("The endpoint protocol smoke returned malformed summary evidence.");
                }
            }
            finally
            {
                await lease.DisposeAsync();
                DeletePrivateSmokeArtifacts(lease.RootPath);
            }
        }
        finally { _gate.Release(); }
    }

    private static ServerProtocolSmokeView Failed(string message) => new("FAIL", message, 0, 0, 1, []);

    private static bool IsProtocolSmokeSummary(string line)
    {
        try
        {
            using var document = JsonDocument.Parse(line);
            return document.RootElement.TryGetProperty("smoke_kind", out var kind) &&
                kind.ValueKind == JsonValueKind.String &&
                kind.GetString() == "protocol-endpoint-without-product";
        }
        catch (JsonException) { return false; }
    }

    private void DeletePrivateSmokeArtifacts(string path)
    {
        var root = Path.GetFullPath(storagePaths.RuntimeRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var candidate = Path.GetFullPath(path);
        if (!candidate.StartsWith(root, StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFileName(candidate).StartsWith("protocol-smoke-", StringComparison.Ordinal) ||
            (Directory.Exists(candidate) && File.GetAttributes(candidate).HasFlag(FileAttributes.ReparsePoint))) return;
        try { if (Directory.Exists(candidate)) Directory.Delete(candidate, recursive: true); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
