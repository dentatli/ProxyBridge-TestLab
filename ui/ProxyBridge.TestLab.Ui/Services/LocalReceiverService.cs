using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record LocalReceiverStatus(
    string State,
    string? RunId,
    string? AttemptId,
    int? EndpointAPort,
    int? EndpointBPort,
    bool RouteVerified,
    string Detail);

public sealed record LocalReceiverEvidence(
    string RunId,
    string AttemptId,
    bool CaptureComplete,
    int MatchingMessages,
    int ForeignMessages,
    int InvalidMessages,
    int MalformedRecords,
    string RouteStatus);

public sealed class LocalReceiverService(AppPaths appPaths, AppStoragePaths storagePaths, LocalArtifactService artifacts) : IHostedService
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private Process? _process;
    private FileStream? _lease;
    private string? _runtimeDirectory;
    private string? _evidencePath;
    private string? _runId;
    private string? _attemptId;
    private int _portA;
    private int _portB;
    private LocalReceiverEvidence? _lastEvidence;

    public Task StartAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        await StopReceiverAsync(CancellationToken.None);
    }

    public LocalReceiverStatus GetStatus()
    {
        var process = _process;
        if (process is not null)
        {
            bool exited;
            try { exited = process.HasExited; }
            catch (InvalidOperationException) { exited = true; }
            return new LocalReceiverStatus(
                exited ? "PROCESS_EXITED" : "RUNNING",
                _runId, _attemptId, _portA, _portB, false,
                exited ? "Receiver exited; close and inspect its evidence." :
                    "Receiver is listening. Proxy routing has not been proven.");
        }

        return new LocalReceiverStatus("STOPPED", null, null, null, null, false,
            _lastEvidence is null ? "Receiver has not been started." : "Last receiver capture is available.");
    }

    public LocalReceiverEvidence? GetLastEvidence() => _lastEvidence;

    public async Task<LocalReceiverStatus> StartReceiverAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (_process is not null) throw new InvalidOperationException("LOCAL_RECEIVER_ALREADY_ACTIVE");
            var python = ResolvePython();
            var endpoint = Path.Combine(appPaths.RepositoryRoot, "src", "pb_net_endpoint.py");
            if (python is null || !File.Exists(endpoint))
                throw new InvalidOperationException("LOCAL_RECEIVER_RUNTIME_MISSING");

            _lastEvidence = null;
            _runId = "local-" + Guid.NewGuid().ToString("N");
            _attemptId = "attempt-" + Guid.NewGuid().ToString("N");
            _runtimeDirectory = Path.Combine(storagePaths.RuntimeRoot, _runId);
            AppStoragePaths.EnsureSecureDirectory(_runtimeDirectory);
            _lease = new FileStream(Path.Combine(_runtimeDirectory, ".lease"), FileMode.CreateNew,
                FileAccess.ReadWrite, FileShare.None);
            var evidenceRoot = Path.Combine(storagePaths.EvidenceRoot, "local-receivers");
            AppStoragePaths.EnsureSecureDirectory(evidenceRoot);
            _evidencePath = Path.Combine(evidenceRoot, _runId + ".jsonl");
            using (File.Create(_evidencePath)) { }
            _portA = SelectPort();
            do { _portB = SelectPort(); } while (_portB == _portA);

            var start = new ProcessStartInfo(python)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            foreach (var argument in new[]
            {
                "-I", "-B", endpoint, "--jsonl-log", _evidencePath, "--control-stdin",
                "--endpoint-a-port", _portA.ToString(System.Globalization.CultureInfo.InvariantCulture),
                "--endpoint-b-port", _portB.ToString(System.Globalization.CultureInfo.InvariantCulture)
            }) start.ArgumentList.Add(argument);
            _process = Process.Start(start) ?? throw new InvalidOperationException("LOCAL_RECEIVER_START_FAILED");
            var metadataPath = Path.Combine(evidenceRoot, _runId + ".metadata.json");
            await File.WriteAllTextAsync(metadataPath, JsonSerializer.Serialize(new
            {
                runId = _runId,
                attemptId = _attemptId,
                processId = _process.Id,
                executablePath = Path.GetFullPath(python),
                endpointPath = Path.GetFullPath(endpoint),
                startedUtc = DateTimeOffset.UtcNow,
                endpointAPort = _portA,
                endpointBPort = _portB
            }), cancellationToken);
            _ = _process.StandardError.ReadToEndAsync();

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(10));
            string? ready;
            try { ready = await _process.StandardOutput.ReadLineAsync(timeout.Token); }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                throw new InvalidOperationException("LOCAL_RECEIVER_READY_TIMEOUT");
            }
            if (ready != $"READY 8 listeners A={_portA} B={_portB}" || _process.HasExited ||
                !HasExpectedListeners(_evidencePath, _portA, _portB))
                throw new InvalidOperationException("LOCAL_RECEIVER_LISTENERS_UNVERIFIED");
            return GetStatus();
        }
        catch
        {
            await StopCoreAsync();
            throw;
        }
        finally { _gate.Release(); }
    }

    public async Task<LocalReceiverEvidence?> StopReceiverAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try { return await StopCoreAsync(); }
        finally { _gate.Release(); }
    }

    private async Task<LocalReceiverEvidence?> StopCoreAsync()
    {
        var process = _process;
        var directory = _runtimeDirectory;
        var evidencePath = _evidencePath;
        var runId = _runId;
        var attemptId = _attemptId;
        try
        {
            if (process is not null && !process.HasExited)
            {
                try
                {
                    await process.StandardInput.WriteLineAsync("STOP");
                    await process.StandardInput.FlushAsync();
                    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                    await process.WaitForExitAsync(timeout.Token);
                }
                catch (Exception exception) when (exception is IOException or InvalidOperationException or OperationCanceledException)
                {
                    if (!process.HasExited) process.Kill(entireProcessTree: true);
                }
            }
            if (process is not null && !process.HasExited) await process.WaitForExitAsync();
            if (evidencePath is null || runId is null || attemptId is null || !File.Exists(evidencePath)) return null;
            _lastEvidence = InspectEvidence(evidencePath, runId, attemptId, _portA, _portB);
            return _lastEvidence;
        }
        finally
        {
            process?.Dispose();
            _process = null;
            _lease?.Dispose();
            _lease = null;
            _runtimeDirectory = null;
            _evidencePath = null;
            _runId = null;
            _attemptId = null;
            _portA = 0;
            _portB = 0;
            if (directory is not null && Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    private string? ResolvePython()
    {
        if (File.Exists(artifacts.ProtocolPythonPath)) return artifacts.ProtocolPythonPath;
        var developmentPython = Path.Combine(appPaths.RepositoryRoot, "bin", "dev-venv", "Scripts", "python.exe");
        return File.Exists(developmentPython) ? developmentPython : null;
    }

    private static int SelectPort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        try { return ((IPEndPoint)listener.LocalEndpoint).Port; }
        finally { listener.Stop(); }
    }

    private static bool HasExpectedListeners(string path, int portA, int portB)
    {
        try
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var line in File.ReadLines(path))
            {
                using var record = JsonDocument.Parse(line);
                var root = record.RootElement;
                if (root.GetProperty("event").GetString() != "LISTENING") continue;
                var family = root.GetProperty("family").GetString();
                var protocol = root.GetProperty("protocol").GetString();
                var port = root.GetProperty("local_port").GetInt32();
                var address = root.GetProperty("local_ip").GetString();
                if (family is not ("IPv4" or "IPv6") || protocol is not ("TCP" or "UDP") ||
                    port != portA && port != portB ||
                    address != (family == "IPv4" ? "127.0.0.1" : "::1")) return false;
                seen.Add($"{family}/{protocol}/{port}");
            }
            return seen.Count == 8;
        }
        catch (Exception exception) when (exception is IOException or JsonException or KeyNotFoundException or InvalidOperationException)
        {
            return false;
        }
    }

    private static LocalReceiverEvidence InspectEvidence(string path, string runId, string attemptId, int portA, int portB)
    {
        var matching = 0;
        var foreign = 0;
        var invalid = 0;
        var malformed = 0;
        var stopped = 0;
        var serverErrors = 0;
        foreach (var line in File.ReadLines(path))
        {
            try
            {
                using var record = JsonDocument.Parse(line);
                var root = record.RootElement;
                var eventName = root.GetProperty("event").GetString();
                if (eventName == "STOPPED") stopped++;
                if (eventName == "SERVER_ERROR") serverErrors++;
                if (eventName is not ("RECEIVED" or "MESSAGE_RECEIVED")) continue;
                var identity = root.GetProperty("run_id").GetString();
                if (identity != runId) { foreign++; continue; }
                var family = root.GetProperty("family").GetString();
                var protocol = root.GetProperty("protocol").GetString();
                var port = root.GetProperty("local_port").GetInt32();
                var address = root.GetProperty("local_ip").GetString();
                if (string.IsNullOrWhiteSpace(root.GetProperty("test_id").GetString()) ||
                    root.GetProperty("sequence").GetInt32() <= 0 ||
                    root.GetProperty("bytes").GetInt32() <= 0 ||
                    root.GetProperty("sha256").GetString()?.Length != 64 ||
                    family is not ("IPv4" or "IPv6") || protocol is not ("TCP" or "UDP") ||
                    port != portA && port != portB ||
                    address != (family == "IPv4" ? "127.0.0.1" : "::1")) invalid++;
                else matching++;
            }
            catch (Exception exception) when (exception is JsonException or KeyNotFoundException or InvalidOperationException)
            {
                malformed++;
            }
        }
        var complete = HasExpectedListeners(path, portA, portB) && stopped == 1 && serverErrors == 0 &&
            malformed == 0 && foreign == 0 && invalid == 0;
        return new LocalReceiverEvidence(runId, attemptId, complete, matching, foreign, invalid, malformed, "UNVERIFIED");
    }
}
