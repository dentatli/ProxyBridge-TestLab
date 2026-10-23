using System.Text.Json;
using System.Text.Json.Nodes;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed partial class BenchmarkLabService
{
    public object GetLocalLoadedRttReports(string? evidenceId = null)
    {
        var bindings = SavedBuildBindings();
        var root = Path.Combine(paths.RepositoryRoot, "artifacts", "local-route");
        var items = new List<object>();
        var unreadable = 0;
        if (!Directory.Exists(root)) return new { items, unreadable };
        if (IsReparse(root)) return new { items, unreadable = 1 };
        foreach (var directory in Directory.EnumerateDirectories(root, "lab-tcp_loaded_rtt-smoke-*")
                     .Where(directory => evidenceId is null || Path.GetFileName(directory) == evidenceId)
                     .OrderByDescending(Directory.GetCreationTimeUtc).Take(evidenceId is null ? 50 : 1))
        {
            var id = Path.GetFileName(directory);
            try
            {
                using var manifestDocument = ReadBoundedJson(Path.Combine(directory, "comparison-manifest.json"));
                var manifest = manifestDocument.RootElement;
                var workload = SavedWorkload(manifest) ?? throw new InvalidOperationException("LOCAL_LOADED_WORKLOAD_MISSING");
                if (manifest.GetProperty("profile").GetString() != "SMOKE" || manifest.GetProperty("scenario_id").GetString() != "tcp_loaded_echo_rtt_v1" ||
                    manifest.GetProperty("pair_count").GetInt32() != 1 || manifest.GetProperty("tcp_fixture_revision").GetString() != "accepted_nodelay_v1" ||
                    !manifest.GetProperty("proxy_accepted_tcp_nodelay").GetBoolean()) throw new InvalidOperationException("LOCAL_LOADED_MANIFEST_INVALID");
                foreach (var key in new[] { "echo_count", "warmup_count", "message_bytes", "pause_ms", "transfer_bytes", "rate_limit_bytes_per_s" })
                    if (manifest.GetProperty(key).GetInt64() != workload.GetProperty(key).GetInt64()) throw new InvalidOperationException("LOCAL_LOADED_PARAMETERS_DIFFER");
                var status = manifest.GetProperty("status").GetString();
                var confirmed = false;
                string? bundle = null, conditions = null;
                var metrics = new Dictionary<string, object>();
                if (status == "COMPLETED")
                {
                    using var comparisonDocument = ReadBoundedJson(Path.Combine(directory, "comparison-report.json"));
                    var comparison = comparisonDocument.RootElement;
                    if (comparison.GetProperty("status").GetString() != "LIMITED_COMPARISON" || comparison.GetProperty("errors").GetArrayLength() != 0 ||
                        comparison.GetProperty("runs").GetArrayLength() != 4 || comparison.GetProperty("pairs").GetArrayLength() != 2 ||
                        manifest.GetProperty("runs").GetArrayLength() != 4 || !string.IsNullOrEmpty(manifest.GetProperty("error").GetString()))
                        throw new InvalidOperationException("LOCAL_LOADED_REPORT_INVALID");
                    var index = 0;
                    foreach (var direction in new[] { "push", "pull" })
                    {
                        var modes = new Dictionary<string, object>();
                        foreach (var mode in new[] { "OFF", "PROXY" })
                        {
                            var name = direction + "-pair-01-" + mode.ToLowerInvariant();
                            var saved = manifest.GetProperty("runs")[index];
                            var embedded = comparison.GetProperty("runs")[index++];
                            if (saved.GetProperty("directory").GetString() != name || saved.GetProperty("mode").GetString() != mode || saved.GetProperty("direction").GetString() != direction ||
                                saved.GetProperty("status").GetString() != "COMPLETED" || embedded.GetProperty("directory").GetString() != name)
                                throw new InvalidOperationException("LOCAL_LOADED_RUN_INVALID");
                            var run = Path.Combine(directory, name);
                            using var sourceDocument = ReadBoundedJson(Path.Combine(run, "tcp-loaded-rtt-report.json"));
                            using var receiptDocument = ReadBoundedJson(Path.Combine(run, "run-receipt.json"));
                            using var configDocument = ReadBoundedJson(Path.Combine(run, "benchmark-config.json"));
                            using var buildDocument = ReadBoundedJson(Path.Combine(run, "product-build.json"));
                            var source = sourceDocument.RootElement;
                            var receipt = receiptDocument.RootElement;
                            var config = configDocument.RootElement;
                            var build = buildDocument.RootElement;
                            if (!BenchmarkWorkload.Matches(source, embedded.GetProperty("report")) || !BenchmarkWorkload.Matches(config, source.GetProperty("config")) ||
                                !BenchmarkWorkload.Matches(workload, config.GetProperty("loaded_workload_preset")) ||
                                source.GetProperty("status").GetString() != "MEASURED" || source.GetProperty("correctness").GetString() != "PASS" || source.GetProperty("errors").GetArrayLength() != 0 ||
                                source.GetProperty("mode").GetString() != mode || source.GetProperty("direction").GetString() != direction ||
                                source.GetProperty("failed_echoes").GetInt32() != 0 || source.GetProperty("load_verified_payload_bytes").GetInt64() != workload.GetProperty("transfer_bytes").GetInt64() ||
                                source.GetProperty("load_overlap").GetProperty("progress_samples").GetInt32() < 3 ||
                                !receipt.GetProperty("workers_stopped").GetBoolean() || !receipt.GetProperty("driver_stop_observed").GetBoolean() ||
                                receipt.GetProperty("status").GetString() != "COMPLETED" || !string.IsNullOrEmpty(receipt.GetProperty("error").GetString()) ||
                                !build.GetProperty("files_verified").GetBoolean() || build.GetProperty("selected_contract").GetString() != "driver" ||
                                build.GetProperty("bundle_sha256").GetString() != source.GetProperty("bundle_sha256").GetString())
                                throw new InvalidOperationException("LOCAL_LOADED_EVIDENCE_INCOMPLETE");
                            var currentBundle = build.GetProperty("bundle_sha256").GetString();
                            if (bundle is not null && bundle != currentBundle) throw new InvalidOperationException("LOCAL_LOADED_MIXED_KITS");
                            bundle = currentBundle;
                            var normalized = JsonNode.Parse(config.GetRawText())!.AsObject();
                            normalized["load"]!.AsObject().Remove("direction");
                            normalized["load"]!.AsObject().Remove("receiver_pid");
                            foreach (var key in new[] { "run_id", "receiver_pid", "proxy_pid", "sampler_pid" }) normalized.Remove(key);
                            var currentConditions = ConditionsKey(JsonSerializer.SerializeToElement(new { config = normalized,
                                other_drivers = source.GetProperty("other_driver_names_sha256").GetString() }));
                            if (conditions is not null && conditions != currentConditions) throw new InvalidOperationException("LOCAL_LOADED_MIXED_CONDITIONS");
                            conditions = currentConditions;
                            var rtt = source.GetProperty("rtt");
                            var cli = mode == "PROXY" ? source.GetProperty("pc").GetProperty("proxybridge_cli") : default;
                            modes[mode.ToLowerInvariant()] = new { p50_ms = Number(rtt, "p50_ms"), p95_ms = Number(rtt, "p95_ms"), p99_ms = Number(rtt, "p99_ms"),
                                load_mbit_per_s = Number(source, "load_useful_mbit_per_s"),
                                cpu_pct_machine = mode == "PROXY" ? Number(cli, "cpu_pct_machine_mean") : (double?)null,
                                private_mib = mode == "PROXY" ? Number(cli, "private_mib_mean") : (double?)null };
                        }
                        metrics[direction] = modes;
                    }
                    confirmed = true;
                }
                items.Add(new { id, created_at_utc = manifest.GetProperty("started_at_utc").GetString(), scenario = "tcp_loaded_rtt", contract = "driver", profile = "WORKLOAD", workload_preset = workload,
                    status = confirmed ? "LIMITED_COMPARISON" : status, terminal = status != "RUNNING", build = ReportBuild(directory, confirmed ? bundle : null, bindings),
                    correctness = confirmed ? "PASS" : "NOT_CONFIRMED", conditions_key = confirmed ? conditions : null, loaded_metrics = confirmed ? metrics : null, saved_evidence_only = true });
            }
            catch (Exception error) when (IsSavedReportError(error)) { unreadable++; items.Add(UnreadableLocalAttempt(directory, "tcp_loaded_rtt", bindings)); }
        }
        return new { items, unreadable };
    }
}
