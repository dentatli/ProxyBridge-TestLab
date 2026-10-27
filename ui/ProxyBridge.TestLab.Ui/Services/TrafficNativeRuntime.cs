using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed partial class TrafficRuntimeService
{
    private sealed record NativeBinding(int Port, int Pid, string Executable);

    private static string NativeFolder(string root) => Path.Combine(root, "bin", "runtime", "traffic-engine");

    private static string[] NativeFiles(string root)
    {
        var folder = NativeFolder(root);
        foreach (var name in new[] { "pb_testlab_origin.exe", "pb_testlab_worker.exe", "ProxyBridge.TestLab.TrafficEngine.dll",
            "ProxyBridge.TestLab.TrafficEngine.runtimeconfig.json", "coreclr.dll" })
            if (!File.Exists(Path.Combine(folder, name))) throw new InvalidOperationException("TRAFFIC_NATIVE_ENGINE_MISSING");
        var files = Directory.GetFiles(folder, "*", SearchOption.AllDirectories);
        foreach (var file in files)
        {
            for (var path = file; path is not null; path = Path.GetDirectoryName(path))
                if (File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint))
                    throw new InvalidOperationException("TRAFFIC_LOCAL_REPARSE_POINT");
        }
        return files;
    }

    private sealed class NativeHost(Process process, string configuration, string stopPath,
        Task errors, Task output, NativeBinding binding) : IAsyncDisposable
    {
        public NativeBinding Binding { get; } = binding;
        public string Configuration { get; } = configuration;

        public static async Task<NativeHost> StartAsync(string root, string directory, string secret, bool worker,
            IReadOnlyDictionary<string, int> applicationPorts, CancellationToken token, bool policyChecks = false)
        {
            var role = worker ? "worker" : "origin";
            var executable = Path.Combine(NativeFolder(root), $"pb_testlab_{role}.exe");
            var config = Path.Combine(directory, $"native-{role}-private.json");
            var stop = Path.Combine(directory, $"native-{role}.stop");
            await File.WriteAllTextAsync(config, JsonSerializer.Serialize(new { secret, bind = "127.0.0.1", port = 42501,
                proxy_port = worker ? 0 : 42502, stop_path = stop, worker_only = worker, application_ports = applicationPorts,
                policy_checks = !worker && policyChecks }), token);
            var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true,
                WorkingDirectory = NativeFolder(root), RedirectStandardOutput = true, RedirectStandardError = true,
                RedirectStandardInput = true };
            start.ArgumentList.Add("--config"); start.ArgumentList.Add(config);
            Process? child = null;
            Task? errors = null;
            try
            {
                child = Process.Start(start) ?? throw new InvalidOperationException("TRAFFIC_NATIVE_ENGINE_START_FAILED");
                child.StandardInput.Close();
                errors = DrainAsync(child.StandardError);
                var line = await child.StandardOutput.ReadLineAsync(token).AsTask().WaitAsync(TimeSpan.FromSeconds(20), token);
                var match = Regex.Match(line ?? "", @"^TRAFFIC_ENGINE_READY origin=42501 udp_buffer=\d+ proxy=(\d+) control=(\d+) worker_only=(True|False)$");
                if (!match.Success || child.HasExited || int.Parse(match.Groups[1].Value) != (worker ? 0 : 42502) ||
                    match.Groups[3].Value != (worker ? "True" : "False") ||
                    !int.TryParse(match.Groups[2].Value, out var port) || port is < 1024 or > 65535 ||
                    !string.Equals(child.MainModule?.FileName, executable, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("TRAFFIC_NATIVE_ENGINE_NOT_READY");
                return new NativeHost(child, config, stop, errors, DrainAsync(child.StandardOutput), new(port, child.Id, executable));
            }
            catch
            {
                if (child is not null)
                {
                    if (!child.HasExited) { child.Kill(entireProcessTree: true); await child.WaitForExitAsync(); }
                    if (errors is not null) await errors;
                    child.Dispose();
                }
                File.Delete(config);
                throw;
            }
        }

        public async ValueTask DisposeAsync()
        {
            try
            {
                await File.WriteAllTextAsync(stopPath, "stop\n");
                try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10)); }
                catch (TimeoutException)
                {
                    if (!process.HasExited) { process.Kill(entireProcessTree: true); await process.WaitForExitAsync(); }
                    throw new InvalidOperationException("TRAFFIC_NATIVE_ENGINE_CLEANUP_FAILED");
                }
                await Task.WhenAll(errors, output);
                if (process.ExitCode != 0) throw new InvalidOperationException("TRAFFIC_NATIVE_ENGINE_EXITED");
            }
            finally { File.Delete(Configuration); process.Dispose(); }
        }
    }
}
