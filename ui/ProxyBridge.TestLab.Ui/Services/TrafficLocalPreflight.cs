namespace ProxyBridge.TestLab.Ui.Services;

public sealed partial class TrafficRuntimeService
{
    private object LocalPreflight()
    {
        var errors = LocalFileErrors();
        return new { ready = errors.Length == 0, errors, scope = "files-only", runtime_verified = false };
    }

    private string[] LocalFileErrors()
    {
        var errors = new List<string>();
        try
        {
            var home = Path.GetDirectoryName(LocalPythonRuntime.Resolve(app.RepositoryRoot))!;
            if (!File.Exists(Path.Combine(home, "python311.dll")) || !File.Exists(Path.Combine(home, "Lib", "encodings", "__init__.py")))
                errors.Add("TRAFFIC_PYTHON_311_REQUIRED");
        }
        catch (InvalidOperationException) { errors.Add("TRAFFIC_PYTHON_311_REQUIRED"); }
        foreach (var file in new[] { "bin/pb_console_host.exe", "bin/pb_core_host.exe", "bin/pb_wfp_state.exe", "scripts/Invoke-TrafficLabRun.ps1",
            "scripts/Assert-TrafficLabIdle.ps1", "scripts/Assert-WinDivertTrafficIdle.ps1", "scripts/Set-TrafficWfpDevice.ps1", "config/traffic-workloads.json", "config/traffic-echo.proto", "config/product-cli-adapters.json", "vendor/traffic-dependencies.lock.json",
            "modules/InterceptionState.psm1", "modules/ProcessAdapter.psm1", "src/pb_service_query.cs", "src/pb_loaded_drivers.cs",
            "src/trafficlab/runner.py", "src/trafficlab/core_session.py", "src/trafficlab/session_runner.py", "src/trafficlab/local_runtime.py" })
            if (!File.Exists(Path.Combine(app.RepositoryRoot, file))) errors.Add("TRAFFIC_LOCAL_FILES_MISSING");
        try { _ = TrafficDependencyFiles("win-x64", verifyContent: false).ToArray(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or InvalidOperationException or KeyNotFoundException)
        { errors.Add("TRAFFIC_LOCAL_FILES_MISSING"); }
        return errors.Distinct().ToArray();
    }

    private void ValidateLocalFiles()
    {
        var errors = LocalFileErrors();
        if (errors.Length > 0) throw new InvalidOperationException(errors[0]);
        _ = TrafficDependencyFiles("win-x64").ToArray(); // Full pinned wheel verification before creating an attempt.
    }
}
