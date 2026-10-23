namespace ProxyBridge.TestLab.Ui.Services;

/// <summary>Files-only prerequisites. Runtime, driver identity and route proof remain controller gates.</summary>
public sealed record BenchmarkScenarioCapability(string Id, bool ControllerSupported, bool PrerequisitesPresent,
    string? Reason, string[] Missing, bool RuntimeVerified = false);

public static class BenchmarkLocalCatalog
{
    public static readonly string[] AutomaticScenarios = ["tcp_rtt", "tcp_transfer", "tcp_upload", "tcp_download", "tcp_rtt_three_modes", "tcp_connections", "udp_echo", "tcp_loaded_rtt"];
    public static bool IsTransfer(string? scenario) => scenario is "tcp_transfer" or "tcp_upload" or "tcp_download";
    public static int TotalRuns(string? scenario) => scenario is "tcp_transfer" or "tcp_loaded_rtt" ? 4 : scenario == "tcp_rtt_three_modes" ? 3 : 2;

    public static BenchmarkScenarioCapability[] Inspect(string root)
    {
        var common = new[] { "bin/pb_console_host.exe", "bin/pb_wfp_state.exe", "config/local-controller-dependencies.json", "src/pb_net_endpoint.py", "src/pb_pc_sampler.py",
            "src/pb_controlled_tcp_proxy.py", "bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl",
            "bin/tools/psutil-7.2.2/packages/psutil/__init__.py", "bin/tools/psutil-7.2.2/psutil-7.2.2-cp37-abi3-win_amd64.whl" };
        var python = new[] { Path.Combine(root, "bin", "runtime", "python", "python.exe"),
            Path.Combine(root, "bin", "protocol-worker", "runtime", "python", "python.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".cache", "codex-runtimes", "codex-primary-runtime", "dependencies", "python", "python.exe") }.FirstOrDefault(IsRegularFile);
        var items = AutomaticScenarios.Concat(["udp_connections", "mixed_soak"])
            .Select(id =>
            {
                var supported = AutomaticScenarios.Contains(id);
                var dependencies = common.Concat(id == "udp_echo" ? ["bin/pb_net_client.exe", "src/pb_controlled_udp_proxy.py"] : id is "tcp_rtt" or "tcp_rtt_three_modes"
                    ? ["bin/tcp-rtt/pb_tcp_rtt_client.exe", "bin/tcp-rtt/build-receipt.json"]
                    : IsTransfer(id) || id == "tcp_connections"
                        ? ["bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe", "bin/tools/ctstraffic-2.0.3.9/ctsTrafficReceiver.exe"]
                        : id == "tcp_loaded_rtt" ? ["bin/tcp-rtt/pb_tcp_rtt_client.exe", "bin/tcp-rtt/build-receipt.json", "bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe", "bin/tools/ctstraffic-2.0.3.9/ctsTrafficReceiver.exe", "src/pb_tcp_nodelay_diagnostic.py"] : Array.Empty<string>());
                var missing = dependencies.Where(file => !IsRegularFile(Path.Combine(root, file))).Select(file => Path.GetFileName(file)!).ToList();
                if (id is "tcp_rtt_three_modes" or "tcp_connections")
                    missing.AddRange(new[] { "bin/tools/windivert-2.2.2/windivertctl.exe", "bin/tools/windivert-2.2.2/WinDivert.dll" }.Where(file => !IsRegularFile(Path.Combine(root, file))).Select(file => Path.GetFileName(file)!));
                if (python is null) missing.Add("python.exe");
                return new BenchmarkScenarioCapability(id, supported, supported && missing.Count == 0,
                    !supported ? "LOCAL_CONTROLLER_PENDING" : missing.Count > 0 ? "LOCAL_DEPENDENCIES_MISSING" : null,
                    supported ? missing.ToArray() : Array.Empty<string>());
            }).ToArray();
        return items;
    }

    private static bool IsRegularFile(string path)
    {
        try
        {
            if (!File.Exists(path)) return false;
            for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
                if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) return false;
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
    }
}
