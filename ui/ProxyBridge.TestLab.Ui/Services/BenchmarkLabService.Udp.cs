using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed partial class BenchmarkLabService
{
    public object GetLocalUdpReports(string? evidenceId = null)
    {
        var bindings = SavedBuildBindings();
        var root = Path.Combine(paths.RepositoryRoot, "artifacts", "local-route");
        var items = new List<object>();
        var unreadable = 0;
        if (!Directory.Exists(root)) return new { items, unreadable };
        if (IsReparse(root)) return new { items, unreadable = 1 };
        foreach (var directory in Directory.EnumerateDirectories(root, "lab-udp_echo-smoke-*")
                     .Where(directory => evidenceId is null || Path.GetFileName(directory) == evidenceId)
                     .OrderByDescending(Directory.GetCreationTimeUtc).Take(evidenceId is null ? 50 : 1))
        {
            var id = Path.GetFileName(directory);
            try
            {
                using var manifestDocument = ReadBoundedJson(Path.Combine(directory, "comparison-manifest.json"));
                var manifest = manifestDocument.RootElement;
                var workload = SavedWorkload(manifest) ?? throw new InvalidOperationException("UDP_WORKLOAD_MISSING");
                var packetCount = workload.GetProperty("packet_count").GetInt32();
                var streams = workload.GetProperty("streams").GetInt32();
                if (manifest.GetProperty("scenario_id").GetString() != "udp_echo_local_v1" ||
                    manifest.GetProperty("comparison_mode").GetString() != "ROUTED" || manifest.GetProperty("pair_count").GetInt32() != 1 ||
                    manifest.GetProperty("packet_count").GetInt32() != packetCount || manifest.GetProperty("stream_count").GetInt32() != streams ||
                    manifest.GetProperty("interval_ms").GetInt32() != workload.GetProperty("interval_ms").GetInt32() ||
                    manifest.GetProperty("message_size_bytes").GetInt32() != 512 || manifest.GetProperty("warmup_packets").GetInt32() != 100 ||
                    manifest.GetProperty("destination_mode").GetString() != "SHARED" || manifest.GetProperty("helper_log_flush_mode").GetString() != "BUFFERED")
                    throw new InvalidOperationException("LOCAL_UDP_MANIFEST_INVALID");
                var status = manifest.GetProperty("status").GetString();
                var confirmed = false;
                var correctness = "NOT_CONFIRMED";
                string? bundle = null, conditions = null;
                var modes = new Dictionary<string, object>();
                if (status == "COMPLETED")
                {
                    using var reportDocument = ReadBoundedJson(Path.Combine(directory, "comparison-report.json"));
                    var report = reportDocument.RootElement;
                    if (report.GetProperty("status").GetString() != "LIMITED_COMPARISON" || report.GetProperty("errors").GetArrayLength() != 0 ||
                        report.GetProperty("runs").GetArrayLength() != 2 || manifest.GetProperty("runs").GetArrayLength() != 2 ||
                        !string.IsNullOrEmpty(manifest.GetProperty("error").GetString())) throw new InvalidOperationException("LOCAL_UDP_REPORT_INVALID");
                    var index = 0;
                    correctness = "PASS";
                    foreach (var mode in new[] { "OFF", "PROXY" })
                    {
                        var name = "pair-01-" + mode.ToLowerInvariant();
                        var saved = manifest.GetProperty("runs")[index];
                        var embedded = report.GetProperty("runs")[index++];
                        if (saved.GetProperty("directory").GetString() != name || saved.GetProperty("mode").GetString() != mode ||
                            saved.GetProperty("status").GetString() != "COMPLETED" || saved.GetProperty("pair").GetInt32() != 1 ||
                            embedded.GetProperty("directory").GetString() != name || embedded.GetProperty("mode").GetString() != mode)
                            throw new InvalidOperationException("LOCAL_UDP_RUN_INVALID");
                        var run = Path.Combine(directory, name);
                        using var sourceDocument = ReadBoundedJson(Path.Combine(run, "udp-benchmark-report.json"));
                        using var configDocument = ReadBoundedJson(Path.Combine(run, "benchmark-config.json"));
                        using var receiptDocument = ReadBoundedJson(Path.Combine(run, "route-probe-receipt.json"));
                        using var buildDocument = ReadBoundedJson(Path.Combine(run, "product-build.json"));
                        using var dependenciesDocument = ReadBoundedJson(Path.Combine(run, "dependencies.json"));
                        var source = sourceDocument.RootElement;
                        var config = configDocument.RootElement;
                        var receipt = receiptDocument.RootElement;
                        var build = buildDocument.RootElement;
                        var defect = source.GetProperty("correctness_status").GetString();
                        var performance = source.GetProperty("performance_status").GetString();
                        if (!(defect == "PASS" && performance == "MEASURED" || mode == "PROXY" && defect == "SOURCE_ENDPOINT_MISMATCH" && performance == "MEASURED_WITH_SOURCE_DEFECT") ||
                            source.GetProperty("response_sources").GetProperty("UNEXPECTED").GetInt32() != 0 ||
                            source.GetProperty("receiver_confirmed_packets").GetInt32() != packetCount || source.GetProperty("accepted_responses").GetInt32() != packetCount ||
                            source.GetProperty("pc_metrics").GetProperty("status").GetString() != "OBSERVED" ||
                            !source.GetProperty("pc_metrics").GetProperty("receiver_identity_verified").GetBoolean() ||
                            !source.GetProperty("stream_layout_verified").GetBoolean() || !source.GetProperty("destination_layout_verified").GetBoolean() ||
                            !source.GetProperty("logging_policy_verified").GetBoolean() ||
                            config.GetProperty("packet_count").GetInt32() != packetCount || config.GetProperty("parallelism").GetInt32() != streams ||
                            config.GetProperty("warmup_packets_per_stream").GetInt32() != 100 || config.GetProperty("interval_ms").GetInt32() != workload.GetProperty("interval_ms").GetInt32() ||
                            config.GetProperty("message_size_bytes").GetInt32() != 512 || config.GetProperty("destination_mode").GetString() != "SHARED" ||
                            config.GetProperty("helper_log_flush_mode").GetString() != "BUFFERED" ||
                            !receipt.GetProperty("workers_stopped").GetBoolean() || !receipt.GetProperty("driver_stop_observed").GetBoolean() ||
                            !build.GetProperty("files_verified").GetBoolean() || build.GetProperty("selected_contract").GetString() != "driver" ||
                            !BenchmarkWorkload.Matches(embedded.GetProperty("metrics"), source.GetProperty("metrics")) ||
                            !BenchmarkWorkload.Matches(embedded.GetProperty("pc"), source.GetProperty("pc_metrics").GetProperty("phases").GetProperty("measurement")) ||
                            embedded.GetProperty("correctness_status").GetString() != defect || embedded.GetProperty("performance_status").GetString() != performance)
                            throw new InvalidOperationException("LOCAL_UDP_EVIDENCE_INCOMPLETE");
                        if (defect != "PASS") correctness = defect!;
                        var currentBundle = build.GetProperty("bundle_sha256").GetString();
                        if (bundle is not null && bundle != currentBundle) throw new InvalidOperationException("LOCAL_UDP_MIXED_KITS");
                        bundle = currentBundle;
                        // Include immutable tool fingerprints and workload; exclude runtime identity and mode.
                        var currentConditions = ConditionsKey(JsonSerializer.SerializeToElement(new
                        {
                            workload, dependencies = dependenciesDocument.RootElement,
                            sampler_sha256 = config.GetProperty("sampler_wheel_sha256").GetString()
                        }));
                        if (conditions is not null && conditions != currentConditions) throw new InvalidOperationException("LOCAL_UDP_MIXED_TOOLS");
                        conditions = currentConditions;
                        var metrics = source.GetProperty("metrics");
                        var cli = source.GetProperty("pc_metrics").GetProperty("phases").GetProperty("measurement").GetProperty("processes").GetProperty("proxybridge_cli");
                        modes[mode.ToLowerInvariant()] = new { p50_ms = Number(metrics, "rtt_median_ms"), p95_ms = Number(metrics, "rtt_p95_ms"), p99_ms = Number(metrics, "rtt_p99_ms"),
                            packets_per_s = Number(metrics, "packets_per_s"), verified_packets = packetCount,
                            cpu_pct_machine = mode == "PROXY" ? Number(cli, "cpu_pct_machine_mean") : (double?)null,
                            private_mib = mode == "PROXY" ? Number(cli, "private_bytes_mean") / 1048576 : (double?)null };
                    }
                    confirmed = true;
                }
                items.Add(new { id, created_at_utc = manifest.GetProperty("started_at_utc").GetString(), scenario = "udp_echo", contract = "driver", profile = "WORKLOAD",
                    workload_preset = workload, status = confirmed ? "LIMITED_COMPARISON" : status, terminal = status != "RUNNING",
                    build = ReportBuild(directory, confirmed ? bundle : null, bindings), correctness,
                    performance_confirmed = confirmed, conditions_key = confirmed ? conditions : null, udp_metrics = confirmed ? modes : null,
                    saved_evidence_only = true, runtime_state_observed = false });
            }
            catch (Exception error) when (IsSavedReportError(error)) { unreadable++; items.Add(UnreadableLocalAttempt(directory, "udp_echo", bindings)); }
        }
        return new { items, unreadable };
    }
}
