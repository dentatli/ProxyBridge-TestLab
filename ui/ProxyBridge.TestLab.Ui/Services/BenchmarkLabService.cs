using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record ProductSelectionRequest(string InstallationDirectory, string Contract, string? DriverPath, string? DisplayName = null);

/// <summary>Files-only selection and saved report display; never starts a benchmark or product.</summary>
public sealed class BenchmarkLabService(AppPaths paths, AppStoragePaths storage, DpapiSecretProtector protector, BenchmarkBuildCatalog builds)
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private string SelectionPath => Path.Combine(storage.ConfigRoot, "benchmark-selection.dpapi");

    public async Task<JsonElement> InspectAsync(ProductSelectionRequest request, CancellationToken cancellationToken)
    {
        _ = BenchmarkBuildCatalog.Label(request.DisplayName, request.Contract);
        if (request.Contract is not ("driver" or "v4.0.0") ||
            !IsLocalPath(request.InstallationDirectory) ||
            (!string.IsNullOrWhiteSpace(request.DriverPath) && !IsLocalPath(request.DriverPath)))
            throw new InvalidOperationException("INVALID_PRODUCT_SELECTION");
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "powershell.exe"))
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true,
            RedirectStandardError = true, StandardOutputEncoding = System.Text.Encoding.UTF8,
            StandardErrorEncoding = System.Text.Encoding.UTF8, WorkingDirectory = paths.RepositoryRoot
        };
        foreach (var value in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                     Path.Combine(paths.RepositoryRoot, "scripts", "Inspect-ProductSelection.ps1"),
                     "-InstallationDirectory", request.InstallationDirectory, "-Contract", request.Contract })
            start.ArgumentList.Add(value);
        if (!string.IsNullOrWhiteSpace(request.DriverPath))
        {
            start.ArgumentList.Add("-DriverPath");
            start.ArgumentList.Add(request.DriverPath);
        }
        using var process = Process.Start(start) ?? throw new InvalidOperationException("SELECTION_INSPECTOR_NOT_STARTED");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(30));
        var stdout = process.StandardOutput.ReadToEndAsync(deadline.Token);
        var stderr = process.StandardError.ReadToEndAsync(deadline.Token);
        try
        {
            await process.WaitForExitAsync(deadline.Token);
            var text = await stdout;
            _ = await stderr;
            if (process.ExitCode != 0 || text.Length > 131072)
                throw new InvalidOperationException("PRODUCT_FILES_INSPECTION_FAILED");
            using var document = JsonDocument.Parse(text);
            return document.RootElement.Clone();
        }
        catch
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            // Observe both pipe tasks before disposing the process on cancellation.
            try { await Task.WhenAll(stdout, stderr); } catch (OperationCanceledException) { }
            throw;
        }
    }

    public async Task<JsonElement> SelectAsync(ProductSelectionRequest request, CancellationToken cancellationToken)
    {
        var observed = await InspectAsync(request, cancellationToken);
        if (!observed.GetProperty("files_observed").GetBoolean() ||
            observed.GetProperty("status").GetString() == "UNSUPPORTED_BEFORE_4_0_0")
            throw new InvalidOperationException("PRODUCT_SELECTION_NOT_SUPPORTED");
        await _gate.WaitAsync(cancellationToken);
        try
        {
            storage.EnsureSecureDirectories();
            var entry = await builds.RememberAsync(request, observed, cancellationToken);
            request = request with { DisplayName = entry.DisplayName };
            observed = BenchmarkBuildCatalog.Attach(observed, entry);
            var plaintext = JsonSerializer.SerializeToUtf8Bytes(new { request, observation = observed });
            byte[] encrypted;
            try { encrypted = protector.Protect(plaintext); }
            finally { CryptographicOperations.ZeroMemory(plaintext); }
            try
            {
                var temporary = SelectionPath + ".tmp";
                await File.WriteAllBytesAsync(temporary, encrypted, cancellationToken);
                File.Move(temporary, SelectionPath, overwrite: true);
            }
            finally { CryptographicOperations.ZeroMemory(encrypted); }
            return observed;
        }
        finally { _gate.Release(); }
    }

    public async Task<JsonElement?> GetSelectionAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (!File.Exists(SelectionPath)) return null;
            var ciphertext = await File.ReadAllBytesAsync(SelectionPath, cancellationToken);
            var plaintext = protector.Unprotect(ciphertext);
            try
            {
                using var document = JsonDocument.Parse(plaintext);
                // Stored paths remain private. This is a saved observation, not a current readiness check.
                var observed = document.RootElement.GetProperty("observation").Clone();
                var request = document.RootElement.GetProperty("request").Deserialize<ProductSelectionRequest>()!;
                var entry = await builds.FindAsync(request.Contract, observed.GetProperty("bundle_sha256").GetString()!, cancellationToken);
                // Migrate the old single saved choice from its original files-only observation, without probes.
                entry ??= await builds.RememberAsync(request, observed, cancellationToken);
                return BenchmarkBuildCatalog.Attach(observed, entry);
            }
            finally { CryptographicOperations.ZeroMemory(plaintext); }
        }
        finally { _gate.Release(); }
    }

    internal async Task<ProductSelectionRequest?> ReadSavedRequestAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (!File.Exists(SelectionPath)) return null;
            var plaintext = protector.Unprotect(await File.ReadAllBytesAsync(SelectionPath, cancellationToken));
            try
            {
                using var document = JsonDocument.Parse(plaintext);
                return document.RootElement.GetProperty("request").Deserialize<ProductSelectionRequest>();
            }
            finally { CryptographicOperations.ZeroMemory(plaintext); }
        }
        finally { _gate.Release(); }
    }

    internal async Task<BenchmarkBuildEntry> BindBuildAsync(ProductSelectionRequest request, JsonElement observation, CancellationToken token)
    {
        return await builds.FindAsync(request.Contract, observation.GetProperty("bundle_sha256").GetString()!, token)
            ?? await builds.RememberAsync(request, observation, token);
    }

    public object GetReports()
    {
        var root = Path.Combine(paths.RepositoryRoot, "artifacts", "version-comparison");
        var reports = new List<object>();
        var seenSources = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var unreadable = 0;
        if (!Directory.Exists(root)) return new { items = reports, unreadable };
        if (IsReparse(root)) return new { items = reports, unreadable = 1 };
        foreach (var directory in Directory.EnumerateDirectories(root)
                     .Where(path => Path.GetFileName(path).StartsWith("tcp-transfer-4.0.0-driver-", StringComparison.Ordinal) ||
                                    Path.GetFileName(path).StartsWith("tcp-rtt-4.0.0-driver-", StringComparison.Ordinal))
                     .OrderDescending().Take(100))
        {
            var id = Path.GetFileName(directory);
            if (!id.StartsWith("tcp-transfer-4.0.0-driver-", StringComparison.Ordinal) &&
                !id.StartsWith("tcp-rtt-4.0.0-driver-", StringComparison.Ordinal)) continue;
            try
            {
                var file = Path.Combine(directory, "comparison-report.json");
                if (IsReparse(directory) || !File.Exists(file) || IsReparse(file) || new FileInfo(file).Length > 4 * 1024 * 1024) continue;
                using var document = JsonDocument.Parse(File.ReadAllText(file));
                var data = document.RootElement;
                if (data.GetProperty("status").GetString() != "LIMITED_VERSION_COMPARISON" ||
                    data.GetProperty("errors").GetArrayLength() != 0) continue;
                var transfer = id.StartsWith("tcp-transfer-", StringComparison.Ordinal);
                var legacy = data.GetProperty("legacy");
                var driver = data.GetProperty("driver");
                var sourceKey = (transfer ? "transfer|" : "rtt|") + legacy.GetProperty("directory").GetString() + "|" + driver.GetProperty("directory").GetString();
                if (seenSources.Contains(sourceKey)) continue;
                reports.Add(new
                {
                    id, kind = transfer ? "tcp_transfer" : "tcp_rtt", status = "LIMITED_VERSION_COMPARISON",
                    created_at_utc = data.GetProperty("created_at_utc").GetString(),
                    legacy_metrics = transfer ? TransferMetrics(legacy) : RttMetrics(legacy),
                    driver_metrics = transfer ? TransferMetrics(driver) : RttMetrics(driver),
                    normal_tcp_close_verified = false
                });
                seenSources.Add(sourceKey);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or KeyNotFoundException or InvalidOperationException or FormatException)
            { unreadable++; }
        }
        return new { items = reports, unreadable };
    }

    public object GetLocalRttReports(string? evidenceId = null)
    {
        var buildBindings = SavedBuildBindings();
        var root = Path.Combine(paths.RepositoryRoot, "artifacts", "local-route");
        var items = new List<object>();
        var unreadable = 0;
        if (!Directory.Exists(root)) return new { items, unreadable };
        if (IsReparse(root)) return new { items, unreadable = 1 };
        foreach (var directory in Directory.EnumerateDirectories(root, "lab-tcp_rtt-smoke-*").Concat(Directory.EnumerateDirectories(root, "lab-tcp_rtt_three_modes-smoke-*")).Concat(Directory.EnumerateDirectories(root, "tcp-rtt-three-modes-smoke-*")).Where(directory => evidenceId is null || Path.GetFileName(directory) == evidenceId).OrderByDescending(Directory.GetCreationTimeUtc).Take(evidenceId is null ? 100 : 1))
        {
            var id = Path.GetFileName(directory);
            var threeModes = id.StartsWith("tcp-rtt-three-modes-smoke-", StringComparison.Ordinal) || id.StartsWith("lab-tcp_rtt_three_modes-smoke-", StringComparison.Ordinal);
            try
            {
                using var manifestDocument = ReadBoundedJson(Path.Combine(directory, "comparison-manifest.json"));
                var manifest = manifestDocument.RootElement;
                var workload = SavedWorkload(manifest);
                var echoes = workload?.GetProperty("echo_count").GetInt32() ?? 128;
                var warmup = workload?.GetProperty("warmup_count").GetInt32() ?? (threeModes ? 200 : 16);
                var pause = workload?.GetProperty("pause_ms").GetInt32() ?? 20;
                var stage = workload is null ? "three_modes_readiness_v1" : "three_modes_workload_v1";
                if (manifest.GetProperty("profile").GetString() != "SMOKE" || manifest.GetProperty("scenario_id").GetString() != "tcp_echo_rtt_v1")
                    throw new InvalidOperationException("LOCAL_RTT_PROFILE_UNSUPPORTED");
                if (workload is not null && (manifest.GetProperty("echo_count").GetInt32() != echoes || manifest.GetProperty("warmup_count").GetInt32() != warmup ||
                    manifest.GetProperty("pause_ms").GetInt32() != pause || manifest.GetProperty("message_bytes").GetInt32() != 512 || manifest.GetProperty("readiness_only").GetBoolean()))
                    throw new InvalidOperationException("LOCAL_WORKLOAD_MANIFEST_INVALID");
                if (threeModes && (manifest.GetProperty("comparison_stage").GetString() != stage || manifest.GetProperty("product_contract").GetString() != "driver" || manifest.GetProperty("readiness_only").GetBoolean() != (workload is null)))
                    throw new InvalidOperationException("LOCAL_THREE_MODE_METHOD_INVALID");
                var created = DateTimeOffset.Parse(manifest.GetProperty("started_at_utc").GetString()!);
                object? metrics = null;
                object? delta = null;
                object? cliMetrics = null;
                object? unruledCliMetrics = null;
                object? unruledDelta = null;
                string? conditionsKey = null;
                string? verifiedBundle = null;
                var confirmed = false;
                var status = manifest.GetProperty("status").GetString();
                if (status == "COMPLETED")
                {
                    try
                    {
                        using var reportDocument = ReadBoundedJson(Path.Combine(directory, "comparison-report.json"));
                        var report = reportDocument.RootElement;
                        if (report.GetProperty("status").GetString() != "LIMITED_COMPARISON" || report.GetProperty("errors").GetArrayLength() != 0 ||
                            report.GetProperty("runs").GetArrayLength() != (threeModes ? 3 : 2) || (!threeModes && report.GetProperty("pairs").GetArrayLength() != 1) ||
                            manifest.GetProperty("runs").GetArrayLength() != (threeModes ? 3 : 2) || manifest.GetProperty("pair_count").GetInt32() != 1 || !string.IsNullOrEmpty(manifest.GetProperty("error").GetString()))
                            throw new InvalidOperationException("LOCAL_RTT_REPORT_NOT_CONFIRMED");
                        if (threeModes && (report.GetProperty("comparison_stage").GetString() != stage || report.GetProperty("readiness_only").GetBoolean() != (workload is null)))
                            throw new InvalidOperationException("LOCAL_THREE_MODE_REPORT_INVALID");
                        var modes = new Dictionary<string, object>();
                        var runIndex = 0;
                        foreach (var run in report.GetProperty("runs").EnumerateArray())
                        {
                            var mode = run.GetProperty("mode").GetString();
                            if ((mode is not ("OFF" or "PROXY") && !(threeModes && mode == "UNRULED")) || modes.ContainsKey(mode!.ToLowerInvariant()) || run.GetProperty("pair").GetInt32() != 1 ||
                                run.GetProperty("directory").GetString() != "pair-01-" + mode.ToLowerInvariant())
                                throw new InvalidOperationException("LOCAL_RTT_RUN_INVALID");
                            var entry = manifest.GetProperty("runs")[runIndex];
                            if (run.GetProperty("status").GetString() != "COMPLETED" || entry.GetProperty("status").GetString() != "COMPLETED" ||
                                entry.GetProperty("directory").GetString() != run.GetProperty("directory").GetString() || entry.GetProperty("mode").GetString() != mode ||
                                (threeModes && mode != new[] { "OFF", "UNRULED", "PROXY" }[runIndex]))
                                throw new InvalidOperationException("LOCAL_RTT_MANIFEST_SOURCE_MISMATCH");
                            runIndex++;
                            var result = run.GetProperty("report");
                            var runRoot = Path.Combine(directory, "pair-01-" + mode.ToLowerInvariant());
                            using var source = ReadBoundedJson(Path.Combine(runRoot, "tcp-rtt-report.json"));
                            using var receiptDocument = ReadBoundedJson(Path.Combine(runRoot, "run-receipt.json"));
                            using var identityDocument = ReadBoundedJson(Path.Combine(runRoot, "product-build.json"));
                            var receipt = receiptDocument.RootElement;
                            var identity = identityDocument.RootElement;
                            var config = result.GetProperty("config");
                            if (!JsonElement.DeepEquals(source.RootElement, result) || result.GetProperty("status").GetString() != "MEASURED" ||
                                result.GetProperty("correctness").GetString() != "PASS" || result.GetProperty("mode").GetString() != mode ||
                                result.GetProperty("errors").GetArrayLength() != 0 || result.GetProperty("failed_echoes").GetInt32() != 0 ||
                                result.GetProperty("verified_echoes").GetInt32() != (echoes + warmup) || result.GetProperty("measured_echoes").GetInt32() != echoes ||
                                config.GetProperty("echo_count").GetInt32() != echoes || config.GetProperty("warmup_count").GetInt32() != warmup ||
                                config.GetProperty("message_bytes").GetInt32() != 512 || config.GetProperty("pause_ms").GetInt32() != pause ||
                                receipt.GetProperty("status").GetString() != "COMPLETED" || receipt.GetProperty("mode").GetString() != mode ||
                                !receipt.GetProperty("workers_stopped").GetBoolean() || !receipt.GetProperty("driver_stop_observed").GetBoolean() ||
                                !receipt.GetProperty("receiver_identity_verified").GetBoolean() || !string.IsNullOrEmpty(receipt.GetProperty("error").GetString()) ||
                                identity.GetProperty("selected_contract").GetString() != "driver" || !identity.GetProperty("files_verified").GetBoolean() ||
                                identity.GetProperty("bundle_sha256").GetString() != result.GetProperty("bundle_sha256").GetString())
                                throw new InvalidOperationException("LOCAL_RTT_SAVED_EVIDENCE_INCOMPLETE");
                            if (threeModes && (config.GetProperty("comparison_stage").GetString() != stage || config.GetProperty("live_socket_observation_policy").GetString() != "owned-socket-snapshot-before-measurement-v1"))
                                throw new InvalidOperationException("LOCAL_THREE_MODE_CONFIG_MISMATCH");
                            if (!SameWorkload(workload, SavedWorkload(config)) || (workload is not null && config.GetProperty("live_socket_observation_policy").GetString() != "owned-socket-snapshot-before-measurement-v1"))
                                throw new InvalidOperationException("LOCAL_WORKLOAD_MISMATCH");
                            var rtt = result.GetProperty("rtt");
                            verifiedBundle ??= result.GetProperty("bundle_sha256").GetString();
                            if (verifiedBundle != result.GetProperty("bundle_sha256").GetString()) throw new InvalidOperationException("LOCAL_RTT_MIXED_KITS");
                            var method = ConditionsKey(config);
                            conditionsKey ??= method;
                            if (conditionsKey != method) throw new InvalidOperationException("LOCAL_RTT_MIXED_CONDITIONS");
                            if (mode == "PROXY")
                            {
                                var cli = result.GetProperty("pc").GetProperty("proxybridge_cli");
                                cliMetrics = new { cpu_pct_machine = Number(cli, "cpu_pct_machine_mean"), private_mib = Number(cli, "private_mib_mean") };
                            }
                            if (mode == "UNRULED")
                            {
                                var cli = result.GetProperty("pc").GetProperty("proxybridge_cli");
                                unruledCliMetrics = new { cpu_pct_machine = Number(cli, "cpu_pct_machine_mean"), private_mib = Number(cli, "private_mib_mean") };
                            }
                            modes[mode.ToLowerInvariant()] = new { p50_ms = Number(rtt, "p50_ms"), p95_ms = Number(rtt, "p95_ms"), p99_ms = Number(rtt, "p99_ms"), max_ms = Number(rtt, "max_ms") };
                        }
                        var pair = threeModes ? report.GetProperty("deltas_ms").GetProperty("proxy_vs_off") : report.GetProperty("pairs")[0];
                        delta = new { p50_ms = Number(pair, "p50_ms"), p95_ms = Number(pair, "p95_ms"), p99_ms = Number(pair, "p99_ms") };
                        if (threeModes)
                        {
                            var unruled = report.GetProperty("deltas_ms").GetProperty("unruled_vs_off");
                            unruledDelta = new { p50_ms = Number(unruled, "p50_ms"), p95_ms = Number(unruled, "p95_ms"), p99_ms = Number(unruled, "p99_ms") };
                        }
                        metrics = modes;
                        confirmed = true;
                    }
                    catch (Exception error) when (IsSavedReportError(error)) { unreadable++; }
                }
                items.Add(new
                {
                    id, created_at_utc = created, contract = "driver", scenario = threeModes ? "tcp_rtt_three_modes" : "tcp_rtt", profile = workload is null ? "SMOKE" : "WORKLOAD", workload_preset = workload,
                    build = ReportBuild(directory, confirmed ? verifiedBundle : null, buildBindings),
                    attempt_status = status, terminal = status is "COMPLETED" or "FAILED" or "CANCELLED",
                    conditions_key = confirmed ? conditionsKey : null, cli_metrics = confirmed ? cliMetrics : null,
                    unruled_cli_metrics = confirmed ? unruledCliMetrics : null, unruled_addition_ms = confirmed ? unruledDelta : null,
                    status = confirmed ? "LIMITED_COMPARISON" : status is "FAILED" or "CANCELLED" ? status : "INCONCLUSIVE",
                    correctness = confirmed ? "PASS" : "NOT_CONFIRMED", mode_metrics = metrics, paired_addition_ms = delta,
                    verified_echoes = confirmed ? ((threeModes ? 3 : 2) * (echoes + warmup)) : (int?)null, measured_echoes = confirmed ? ((threeModes ? 3 : 2) * echoes) : (int?)null,
                    failed_echoes = confirmed ? 0 : (int?)null, saved_evidence_only = true, runtime_state_observed = false
                });
            }
            catch (Exception error) when (IsSavedReportError(error))
            {
                unreadable++;
                items.Add(UnreadableLocalAttempt(directory, threeModes ? "tcp_rtt_three_modes" : "tcp_rtt", buildBindings));
            }
        }
        return new { items, unreadable };
    }

    public object GetLocalTransferReports(string? evidenceId = null)
    {
        var buildBindings = SavedBuildBindings();
        var root = Path.Combine(paths.RepositoryRoot, "artifacts", "local-route");
        var items = new List<object>();
        var unreadable = 0;
        if (!Directory.Exists(root)) return new { items, unreadable };
        if (IsReparse(root)) return new { items, unreadable = 1 };
        foreach (var directory in Directory.EnumerateDirectories(root, "lab-tcp_transfer-smoke-*").Where(directory => evidenceId is null || Path.GetFileName(directory) == evidenceId).OrderDescending().Take(evidenceId is null ? 50 : 1))
        {
            var id = Path.GetFileName(directory);
            try
            {
                using var manifestDocument = ReadBoundedJson(Path.Combine(directory, "comparison-manifest.json"));
                var manifest = manifestDocument.RootElement;
                var workload = SavedWorkload(manifest);
                var volume = workload?.GetProperty("transfer_bytes").GetInt64() ?? 67108864;
                var rate = workload?.GetProperty("rate_limit_bytes_per_s").GetInt64() ?? 8388608;
                if (manifest.GetProperty("profile").GetString() != "SMOKE" || !manifest.GetProperty("transfer_only").GetBoolean() ||
                    manifest.GetProperty("product_label").GetString() != "driver" || manifest.GetProperty("transfer_bytes").GetInt64() != volume ||
                    manifest.GetProperty("rate_limit_bytes_per_s").GetInt64() != rate || manifest.GetProperty("pair_count").GetInt32() != 1 ||
                    manifest.GetProperty("tcp_shutdown_policy").GetString() != "data-transfer-only-v1" ||
                    manifest.GetProperty("shutdown_mode").GetString() != "rude")
                    throw new InvalidOperationException("LOCAL_TRANSFER_PROFILE_UNSUPPORTED");
                var created = DateTimeOffset.Parse(manifest.GetProperty("started_at_utc").GetString()!);
                var status = manifest.GetProperty("status").GetString();
                var confirmed = false;
                object? metrics = null;
                string? verifiedBundle = null;
                string? conditionsKey = null;
                if (status == "COMPLETED")
                {
                    try
                    {
                        using var reportDocument = ReadBoundedJson(Path.Combine(directory, "comparison-report.json"));
                        var report = reportDocument.RootElement;
                        if (report.GetProperty("status").GetString() != "LIMITED_COMPARISON" || report.GetProperty("errors").GetArrayLength() != 0 ||
                            report.GetProperty("runs").GetArrayLength() != 4 || report.GetProperty("pairs").GetArrayLength() != 2 ||
                            manifest.GetProperty("runs").GetArrayLength() != 4 || !string.IsNullOrEmpty(manifest.GetProperty("error").GetString()) ||
                            !report.GetProperty("transfer_only").GetBoolean() || report.GetProperty("normal_tcp_close_verified").GetBoolean())
                            throw new InvalidOperationException("LOCAL_TRANSFER_REPORT_NOT_CONFIRMED");
                        var values = new Dictionary<string, JsonElement>();
                        string? bundle = null;
                        var expectedNames = new[] { "push-pair-01-off", "push-pair-01-proxy", "pull-pair-01-off", "pull-pair-01-proxy" };
                        var index = 0;
                        foreach (var run in report.GetProperty("runs").EnumerateArray())
                        {
                            var direction = run.GetProperty("direction").GetString();
                            var mode = run.GetProperty("mode").GetString();
                            var name = run.GetProperty("directory").GetString();
                            var entry = manifest.GetProperty("runs")[index];
                            if (direction is not ("push" or "pull") || mode is not ("OFF" or "PROXY") ||
                                name != expectedNames[index++] || name != direction + "-pair-01-" + mode.ToLowerInvariant() || run.GetProperty("pair").GetInt32() != 1 || run.GetProperty("status").GetString() != "COMPLETED" ||
                                entry.GetProperty("directory").GetString() != name || entry.GetProperty("status").GetString() != "COMPLETED" ||
                                entry.GetProperty("mode").GetString() != mode || entry.GetProperty("direction").GetString() != direction || entry.GetProperty("pair").GetInt32() != 1)
                                throw new InvalidOperationException("LOCAL_TRANSFER_RUN_INVALID");
                            var result = run.GetProperty("report");
                            var runRoot = Path.Combine(directory, name!);
                            using var source = ReadBoundedJson(Path.Combine(runRoot, "tcp-benchmark-report.json"));
                            using var receiptDocument = ReadBoundedJson(Path.Combine(runRoot, "run-receipt.json"));
                            using var identityDocument = ReadBoundedJson(Path.Combine(runRoot, "product-build.json"));
                            var receipt = receiptDocument.RootElement;
                            var identity = identityDocument.RootElement;
                            var config = result.GetProperty("config");
                            if (!JsonElement.DeepEquals(source.RootElement, result) || result.GetProperty("status").GetString() != "MEASURED" ||
                                result.GetProperty("errors").GetArrayLength() != 0 || result.GetProperty("mode").GetString() != mode ||
                                result.GetProperty("direction").GetString() != direction || result.GetProperty("verified_payload_bytes").GetInt64() != volume ||
                                config.GetProperty("direction").GetString() != direction || config.GetProperty("transfer_bytes").GetInt64() != volume || config.GetProperty("rate_limit_bytes_per_s").GetInt64() != rate ||
                                config.GetProperty("connections").GetInt32() != 1 || config.GetProperty("buffer_bytes").GetInt32() != 65536 ||
                                config.GetProperty("verify").GetString() != "data" || !config.GetProperty("transfer_only").GetBoolean() ||
                                config.GetProperty("shutdown_mode").GetString() != "rude" || config.GetProperty("product_label").GetString() != "driver" ||
                                config.GetProperty("tcp_shutdown_policy").GetString() != "data-transfer-only-v1" ||
                                receipt.GetProperty("status").GetString() != "COMPLETED" || receipt.GetProperty("mode").GetString() != mode ||
                                receipt.GetProperty("direction").GetString() != direction || !receipt.GetProperty("workers_stopped").GetBoolean() ||
                                !receipt.GetProperty("driver_stop_observed").GetBoolean() || !receipt.GetProperty("receiver_identity_verified").GetBoolean() ||
                                !string.IsNullOrEmpty(receipt.GetProperty("error").GetString()) || identity.GetProperty("selected_contract").GetString() != "driver" ||
                                !identity.GetProperty("files_verified").GetBoolean() || identity.GetProperty("bundle_sha256").GetString() != result.GetProperty("bundle_sha256").GetString())
                                throw new InvalidOperationException("LOCAL_TRANSFER_SAVED_EVIDENCE_INCOMPLETE");
                            bundle ??= result.GetProperty("bundle_sha256").GetString();
                            if (bundle != result.GetProperty("bundle_sha256").GetString()) throw new InvalidOperationException("LOCAL_TRANSFER_MIXED_KITS");
                            if (!SameWorkload(workload, SavedWorkload(config))) throw new InvalidOperationException("LOCAL_WORKLOAD_MISMATCH");
                            var method = ConditionsKey(config);
                            conditionsKey ??= method;
                            if (conditionsKey != method) throw new InvalidOperationException("LOCAL_TRANSFER_MIXED_CONDITIONS");
                            values.Add(direction + "-" + mode, result);
                        }
                        var directions = new Dictionary<string, object>();
                        foreach (var direction in new[] { "push", "pull" })
                        {
                            var pairs = report.GetProperty("pairs").EnumerateArray().Where(pair => pair.GetProperty("direction").GetString() == direction).ToArray();
                            if (pairs.Length != 1 || pairs[0].GetProperty("pair").GetInt32() != 1) throw new InvalidOperationException("LOCAL_TRANSFER_PAIR_INVALID");
                            var off = values[direction + "-OFF"];
                            var proxy = values[direction + "-PROXY"];
                            var cli = proxy.GetProperty("pc").GetProperty("proxybridge_cli");
                            directions[direction] = new
                            {
                                off_mbit_per_s = Number(off, "useful_mbit_per_s"), proxy_mbit_per_s = Number(proxy, "useful_mbit_per_s"),
                                change_pct = Number(pairs[0], "rate_change_pct"), cli_cpu_pct_machine = Number(cli, "cpu_pct_machine_mean"),
                                cli_private_mib = Number(cli, "private_mib_mean")
                            };
                        }
                        metrics = directions;
                        verifiedBundle = bundle;
                        confirmed = true;
                    }
                    catch (Exception error) when (IsSavedReportError(error)) { unreadable++; }
                }
                items.Add(new
                {
                    id, created_at_utc = created, contract = "driver", scenario = "tcp_transfer", profile = workload is null ? "SMOKE" : "WORKLOAD", workload_preset = workload,
                    build = ReportBuild(directory, confirmed ? verifiedBundle : null, buildBindings),
                    attempt_status = status, terminal = status is "COMPLETED" or "FAILED" or "CANCELLED",
                    conditions_key = confirmed ? conditionsKey : null,
                    status = confirmed ? "LIMITED_COMPARISON" : status is "FAILED" or "CANCELLED" ? status : "INCONCLUSIVE",
                    correctness = confirmed ? "PASS" : "NOT_CONFIRMED", direction_metrics = metrics,
                    verified_payload_bytes = confirmed ? volume * 4 : (long?)null, normal_tcp_close_verified = false,
                    saved_evidence_only = true, runtime_state_observed = false
                });
            }
            catch (Exception error) when (IsSavedReportError(error))
            {
                unreadable++;
                items.Add(UnreadableLocalAttempt(directory, "tcp_transfer", buildBindings));
            }
        }
        return new { items, unreadable };
    }

    public object GetLocalConnectionReports(string? evidenceId = null)
    {
        var root = Path.Combine(paths.RepositoryRoot, "artifacts", "local-route");
        var bindings = SavedBuildBindings();
        var items = new List<object>();
        var unreadable = 0;
        if (!Directory.Exists(root) || IsReparse(root)) return new { items, unreadable };
        foreach (var directory in Directory.EnumerateDirectories(root, "lab-tcp_connections-smoke-*")
            .Where(d => evidenceId is null || Path.GetFileName(d) == evidenceId).OrderByDescending(Directory.GetCreationTimeUtc).Take(evidenceId is null ? 100 : 1))
        {
            try
            {
                var id = Path.GetFileName(directory);
                using var manifestDoc = ReadBoundedJson(Path.Combine(directory, "comparison-manifest.json"));
                var manifest = manifestDoc.RootElement;
                var workload = SavedWorkload(manifest) ?? throw new InvalidOperationException("LOCAL_WORKLOAD_INVALID");
                var confirmed = manifest.GetProperty("status").GetString() == "COMPLETED";
                var modes = new List<object>();
                string? bundle = null, conditions = null;
                if (confirmed)
                {
                    using var reportDoc = ReadBoundedJson(Path.Combine(directory, "comparison-report.json"));
                    var report = reportDoc.RootElement;
                    confirmed = report.GetProperty("scenario").GetString() == "tcp_connections" && report.GetProperty("method").GetString() == "tcp-connection-load-v1" &&
                        report.GetProperty("status").GetString() == "LIMITED_COMPARISON" && report.GetProperty("errors").GetArrayLength() == 0 &&
                        SameWorkload(workload, SavedWorkload(report)) && !report.GetProperty("table_occupancy_observed").GetBoolean() && !report.GetProperty("maximum_capacity_verified").GetBoolean();
                    var hashes = report.GetProperty("source_sha256").EnumerateObject().ToArray();
                    if (hashes.Length is < 20 or > 200) confirmed = false;
                    foreach (var property in hashes)
                    {
                        if (!System.Text.RegularExpressions.Regex.IsMatch(property.Name, "^(off|proxy)/(?:baseline/|load-(?:8|32|64|256|640)/|recovery/)?[a-z0-9-]+\\.(json|jsonl|csv|pbprofile)$"))
                            throw new InvalidOperationException("LOCAL_SOURCE_PATH_INVALID");
                        var file = Path.Combine(directory, property.Name.Replace('/', Path.DirectorySeparatorChar));
                        AssertNoReparse(file);
                        if (new FileInfo(file).Length > 16 * 1024 * 1024 || !string.Equals(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))), property.Value.GetString(), StringComparison.OrdinalIgnoreCase)) confirmed = false;
                    }
                    var entries = report.GetProperty("modes").EnumerateArray().ToArray();
                    if (entries.Length != 2 || !entries.Select(entry => entry.GetProperty("mode").GetString()).SequenceEqual(new[] { "OFF", "PROXY" })) confirmed = false;
                    foreach (var entry in entries)
                    {
                        var mode = entry.GetProperty("mode").GetString()!;
                        if (mode is not ("OFF" or "PROXY") || entry.GetProperty("status").GetString() != "MEASURED" || entry.GetProperty("errors").GetArrayLength() != 0 ||
                            !entry.GetProperty("recovery_verified").GetBoolean() || !SameWorkload(workload, SavedWorkload(entry.GetProperty("config")))) confirmed = false;
                        var cohorts = entry.GetProperty("cohorts").EnumerateArray().ToArray();
                        var expectedLevels = workload.GetProperty("levels").EnumerateArray().Select(level => level.GetInt32()).ToArray();
                        var expectedIds = new[] { "baseline" }.Concat(expectedLevels.Select(level => "load-" + level)).Append("recovery").ToArray();
                        if (cohorts.Length != 5 || !cohorts.Select(cohort => cohort.GetProperty("id").GetString()).SequenceEqual(expectedIds) ||
                            !cohorts.Select(cohort => cohort.GetProperty("requested_connections").GetInt32()).SequenceEqual(new[] { 4 }.Concat(expectedLevels).Append(4))) confirmed = false;
                        var publicCohorts = new List<object>();
                        foreach (var cohort in cohorts)
                        {
                            var requested = cohort.GetProperty("requested_connections").GetInt32();
                            if (requested is < 1 or > 640 || cohort.GetProperty("status").GetString() != "MEASURED" || cohort.GetProperty("errors").GetArrayLength() != 0 ||
                                cohort.GetProperty("successful_connections").GetInt32() != requested || cohort.GetProperty("confirmed_concurrent_connections").GetInt32() != requested) confirmed = false;
                            var pc = cohort.GetProperty("pc");
                            var cpu = mode == "PROXY" ? pc.GetProperty("proxybridge_cli").GetProperty("cpu_pct_machine_mean").GetDouble() : (double?)null;
                            var ram = mode == "PROXY" ? pc.GetProperty("proxybridge_cli").GetProperty("private_mib_mean").GetDouble() : (double?)null;
                            if ((cpu is not null && (!double.IsFinite(cpu.Value) || cpu < 0)) || (ram is not null && (!double.IsFinite(ram.Value) || ram < 0))) confirmed = false;
                            publicCohorts.Add(new { id = cohort.GetProperty("id").GetString(), phase = cohort.GetProperty("phase").GetString(),
                                requested_connections = requested, confirmed_connections = cohort.GetProperty("confirmed_concurrent_connections").GetInt32(),
                                successful_connections = cohort.GetProperty("successful_connections").GetInt32(), failed_connections = cohort.GetProperty("failed_connections").GetInt32(),
                                verified_payload_bytes = cohort.GetProperty("verified_payload_bytes").GetInt64(), cpu_pct_machine_mean = cpu, private_mib_mean = ram });
                        }
                        modes.Add(new { mode, cohorts = publicCohorts, recovery_verified = entry.GetProperty("recovery_verified").GetBoolean() });
                        var currentBundle = entry.GetProperty("bundle_sha256").GetString();
                        if (bundle is not null && bundle != currentBundle) confirmed = false;
                        bundle = currentBundle;
                        var currentConditions = ConditionsKey(entry.GetProperty("config"));
                        if (conditions is not null && conditions != currentConditions) confirmed = false;
                        conditions = currentConditions;
                    }
                }
                items.Add(new { id, created_at_utc = manifest.GetProperty("started_at_utc").GetString(), scenario = "tcp_connections", contract = "driver", profile = "WORKLOAD",
                    workload_preset = workload, status = manifest.GetProperty("status").GetString(), correctness = confirmed ? "PASS" : "NOT_CONFIRMED", terminal = manifest.GetProperty("status").GetString() != "RUNNING",
                    build = ReportBuild(directory, confirmed ? bundle : null, bindings), conditions_key = confirmed ? conditions : null,
                    modes = confirmed ? modes : new List<object>(), table_occupancy_observed = false, maximum_capacity_verified = false });
            }
            catch (Exception error) when (error is IOException or JsonException or InvalidOperationException or KeyNotFoundException or UnauthorizedAccessException or ArgumentException)
            { unreadable++; items.Add(UnreadableLocalAttempt(directory, "tcp_connections", bindings)); }
        }
        return new { items, unreadable };
    }

    public object GetLaunchAttempts(int offset = 0)
    {
        var root = Path.Combine(paths.RepositoryRoot, "artifacts", "benchmark-launch");
        var items = new List<object>();
        var unreadable = 0;
        if (!Directory.Exists(root)) return new { items, unreadable, next_offset = (int?)null };
        if (IsReparse(root)) return new { items, unreadable = 1, next_offset = (int?)null };
        if (offset < 0) throw new InvalidOperationException("HISTORY_OFFSET_INVALID");
        var directories = Directory.EnumerateDirectories(root, "plan-*-control").OrderByDescending(Directory.GetCreationTimeUtc).ThenByDescending(Path.GetFileName).Skip(offset).Take(1001).ToArray();
        foreach (var directory in directories.Take(1000))
        {
            try
            {
                using var jobDocument = ReadBoundedJson(Path.Combine(directory, "job.json"));
                var job = jobDocument.RootElement.Deserialize<BenchmarkRunView>(new JsonSerializerOptions(JsonSerializerDefaults.Web))
                    ?? throw new InvalidOperationException("HISTORY_JOB_INVALID");
                if (!System.Text.RegularExpressions.Regex.IsMatch(job.PlanId, "^plan-[a-f0-9]{32}$") || Path.GetFileName(directory) != job.PlanId + "-control")
                    throw new InvalidOperationException("HISTORY_JOB_INVALID");
                using var planDocument = ReadBoundedJson(Path.Combine(root, job.PlanId + ".json"));
                var plan = planDocument.RootElement;
                var scenario = plan.GetProperty("scenario").GetString();
                var workload = SavedWorkload(plan);
                if (plan.GetProperty("id").GetString() != job.PlanId || plan.GetProperty("contract").GetString() != "driver" ||
                    plan.GetProperty("mode").GetString() != "local" || plan.GetProperty("profile").GetString() != "SMOKE" ||
                    scenario is not ("tcp_rtt" or "tcp_transfer" or "tcp_rtt_three_modes" or "tcp_connections")) throw new InvalidOperationException("HISTORY_PLAN_INVALID");
                var buildId = BenchmarkBuildCatalog.Identity("driver", plan.GetProperty("bundle_sha256").GetString()!);
                if (plan.TryGetProperty("build_id", out var storedId) && storedId.GetString() != buildId)
                    throw new InvalidOperationException("HISTORY_BUILD_INVALID");
                var name = plan.TryGetProperty("build_name_at_run", out var storedName) ? BenchmarkBuildCatalog.Label(storedName.GetString(), "driver") : null;
                string? evidenceId = null;
                var receiptFile = Path.Combine(root, job.PlanId + "-run", "controller-process.json");
                if (File.Exists(receiptFile))
                {
                    try
                    {
                        using var receiptDocument = ReadBoundedJson(receiptFile);
                        var receipt = receiptDocument.RootElement;
                        var evidence = Path.GetFullPath(receipt.GetProperty("evidence_directory").GetString()!);
                        if (receipt.GetProperty("plan_id").GetString() == job.PlanId && receipt.GetProperty("scenario").GetString() == scenario &&
                            string.Equals(Path.GetDirectoryName(evidence), Path.Combine(paths.RepositoryRoot, "artifacts", "local-route"), StringComparison.OrdinalIgnoreCase) &&
                            Path.GetFileName(evidence).StartsWith("lab-" + scenario + "-smoke-", StringComparison.Ordinal)) evidenceId = Path.GetFileName(evidence);
                    }
                    catch (Exception error) when (IsSavedReportError(error)) { }
                }
                items.Add(new
                {
                    id = "launch-" + job.PlanId, plan_id = job.PlanId, created_at_utc = job.StartedAtUtc,
                    contract = "driver", scenario, profile = workload is null ? "SMOKE" : "WORKLOAD", workload_preset = workload, status = job.Status, terminal = job.Terminal,
                    evidence_id = evidenceId,
                    not_started = job.Reason == "SUITE_TEST_NOT_STARTED",
                    build = new { id = buildId, name_at_run = name, plan_id = job.PlanId, identity_scope = "planned-files" },
                    correctness = "NOT_CONFIRMED", saved_evidence_only = true
                });
            }
            catch (Exception error) when (IsSavedReportError(error)) { unreadable++; }
        }
        return new { items, unreadable, next_offset = directories.Length > 1000 ? (int?)(offset + 1000) : null };
    }

    private object UnreadableLocalAttempt(string directory, string scenario, Dictionary<string, (string Id, string? Name, string Bundle, string Plan)> bindings)
        => new { id = Path.GetFileName(directory), created_at_utc = Directory.GetCreationTimeUtc(directory), contract = "driver", scenario,
            profile = "SMOKE", status = "INCONCLUSIVE", attempt_status = "UNREADABLE", terminal = true,
            build = ReportBuild(directory, null, bindings), correctness = "NOT_CONFIRMED", evidence_unreadable = true, saved_evidence_only = true };

    private JsonElement? SavedWorkload(JsonElement data)
    {
        if (!data.TryGetProperty("workload_preset", out var workload) || workload.ValueKind == JsonValueKind.Null) return null;
        JsonElement? expected = workload.TryGetProperty("method", out var method) && method.GetString() == "tcp-connection-load-v1" ? ConnectionWorkload.Resolve(workload.GetProperty("duration").GetString(), workload.GetProperty("load").GetString()) : BenchmarkWorkload.Resolve(paths.RepositoryRoot, workload.GetProperty("duration").GetString(), workload.GetProperty("load").GetString());
        if (expected is null || !BenchmarkWorkload.Matches(workload, expected.Value)) throw new InvalidOperationException("LOCAL_WORKLOAD_INVALID");
        return workload.Clone();
    }

    private static bool SameWorkload(JsonElement? left, JsonElement? right) =>
        left is null ? right is null : right is not null && BenchmarkWorkload.Matches(left.Value, right.Value);

    private static string ConditionsKey(JsonElement config)
    {
        // Exclude ephemeral endpoints/process ids and the product version being compared.
        var ignore = new HashSet<string> { "receiver_port", "proxy_port", "receiver_pid", "proxy_pid", "sampler_pid", "run_id", "direction", "product_label" };
        var values = new SortedDictionary<string, JsonElement>(StringComparer.Ordinal);
        foreach (var property in config.EnumerateObject())
            if (!ignore.Contains(property.Name)) values[property.Name] = property.Value.Clone();
        return Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(values)));
    }

    private Dictionary<string, (string Id, string? Name, string Bundle, string Plan)> SavedBuildBindings()
    {
        var root = Path.Combine(paths.RepositoryRoot, "artifacts", "benchmark-launch");
        var bindings = new Dictionary<string, (string, string?, string, string)>(StringComparer.OrdinalIgnoreCase);
        if (!Directory.Exists(root) || IsReparse(root)) return bindings;
        foreach (var file in Directory.EnumerateFiles(root, "plan-*.json").OrderByDescending(File.GetLastWriteTimeUtc).Take(1000))
        {
            try
            {
                using var planDocument = ReadBoundedJson(file);
                var plan = planDocument.RootElement;
                var id = plan.GetProperty("id").GetString()!;
                if (!System.Text.RegularExpressions.Regex.IsMatch(id, "^plan-[a-f0-9]{32}$") || Path.GetFileName(file) != id + ".json" ||
                    plan.GetProperty("contract").GetString() != "driver" || plan.GetProperty("mode").GetString() != "local" ||
                    plan.GetProperty("profile").GetString() != "SMOKE") continue;
                var scenario = plan.GetProperty("scenario").GetString();
                if (scenario is not ("tcp_rtt" or "tcp_transfer" or "tcp_rtt_three_modes" or "tcp_connections")) continue;
                var bundle = plan.GetProperty("bundle_sha256").GetString()!;
                var identity = BenchmarkBuildCatalog.Identity("driver", bundle);
                if (plan.TryGetProperty("build_id", out var buildId) && buildId.GetString() != identity) continue;
                using var receiptDocument = ReadBoundedJson(Path.Combine(root, id + "-run", "controller-process.json"));
                var receipt = receiptDocument.RootElement;
                var directory = Path.GetFullPath(receipt.GetProperty("evidence_directory").GetString()!);
                if (receipt.GetProperty("plan_id").GetString() != id || receipt.GetProperty("scenario").GetString() != scenario ||
                    !string.Equals(Path.GetDirectoryName(directory), Path.Combine(paths.RepositoryRoot, "artifacts", "local-route"), StringComparison.OrdinalIgnoreCase) ||
                    !Path.GetFileName(directory).StartsWith("lab-" + scenario + "-smoke-", StringComparison.Ordinal)) continue;
                var name = plan.TryGetProperty("build_name_at_run", out var nameProperty) ? BenchmarkBuildCatalog.Label(nameProperty.GetString(), "driver") : null;
                bindings.TryAdd(directory, (identity, name, bundle, id));
            }
            catch (Exception error) when (IsSavedReportError(error)) { }
        }
        return bindings;
    }

    private static object? ReportBuild(string directory, string? verifiedBundle, Dictionary<string, (string Id, string? Name, string Bundle, string Plan)> bindings)
    {
        var hasBinding = bindings.TryGetValue(Path.GetFullPath(directory), out var entry);
        if (verifiedBundle is not null)
            return new { id = BenchmarkBuildCatalog.Identity("driver", verifiedBundle),
                name_at_run = hasBinding && string.Equals(entry.Bundle, verifiedBundle, StringComparison.OrdinalIgnoreCase) ? entry.Name : null,
                plan_id = hasBinding && string.Equals(entry.Bundle, verifiedBundle, StringComparison.OrdinalIgnoreCase) ? entry.Plan : null,
                identity_scope = "verified-files" };
        return hasBinding ? new { id = entry.Id, name_at_run = entry.Name, plan_id = entry.Plan, identity_scope = "planned-files" } : null;
    }

    private static JsonDocument ReadBoundedJson(string file)
    {
        if (IsReparse(file) || IsReparse(Path.GetDirectoryName(file)!) || new FileInfo(file).Length > 4 * 1024 * 1024)
            throw new InvalidOperationException("SAVED_REPORT_FILE_INVALID");
        return JsonDocument.Parse(File.ReadAllText(file));
    }
    private static bool IsSavedReportError(Exception error) => error is IOException or UnauthorizedAccessException or JsonException or
        KeyNotFoundException or InvalidOperationException or FormatException or ArgumentException;

    private static void AssertNoReparse(string path)
    {
        for (var current = Path.GetFullPath(path); !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
            if (IsReparse(current)) throw new InvalidOperationException("SAVED_REPORT_REPARSE_POINT");
    }

    private static object TransferMetrics(JsonElement series)
    {
        var result = new Dictionary<string, object>();
        foreach (var direction in new[] { "push", "pull" })
        {
            var metric = series.GetProperty("metrics").GetProperty(direction);
            var modes = metric.GetProperty("mode_medians");
            var cli = metric.GetProperty("cli");
            result[direction] = new
            {
                mode_medians = new { off = Number(modes, "OFF"), proxy = Number(modes, "PROXY") },
                paired_change_pct_median = Number(metric, "paired_change_pct_median"),
                cli = new { cpu_pct_machine_mean = Number(cli, "cpu_pct_machine_mean"), private_mib_mean = Number(cli, "private_mib_mean") }
            };
        }
        return result;
    }

    private static object RttMetrics(JsonElement series)
    {
        var values = series.GetProperty("paired_addition_ms");
        return new { p50_ms = Number(values, "p50_ms"), p95_ms = Number(values, "p95_ms"), p99_ms = Number(values, "p99_ms") };
    }

    private static double Number(JsonElement values, string key)
    {
        var result = values.GetProperty(key).GetDouble();
        if (!double.IsFinite(result)) throw new InvalidOperationException("REPORT_NUMBER_NOT_FINITE");
        return result;
    }

    private static bool IsReparse(string path) => (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
    private static bool IsLocalPath(string? path) => !string.IsNullOrWhiteSpace(path) && path.Length <= 1024 &&
        path.Length >= 3 && char.IsAsciiLetter(path[0]) && path[1] == ':' && (path[2] is '\\' or '/') &&
        !path.Any(char.IsControl);
}
