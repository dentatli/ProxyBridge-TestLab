using System.Diagnostics;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed partial class TrafficRuntimeService
{
    private async Task PrepareLocalFirewallAsync(string python, string directory)
    {
        var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true,
            WorkingDirectory = app.RepositoryRoot, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
            Path.Combine(app.RepositoryRoot, "scripts", "Initialize-LocalFirewall.ps1"), "-RepositoryRoot", app.RepositoryRoot,
            "-PythonPath", python }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("TRAFFIC_FIREWALL_HELPER_FAILED");
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        try
        {
            await process.WaitForExitAsync(deadline.Token);
            var output = await stdout;
            if (process.ExitCode != 0 || output.Length > 8192 || !string.IsNullOrWhiteSpace(await stderr))
                throw new InvalidOperationException("TRAFFIC_FIREWALL_PREPARATION_FAILED");
            using var result = JsonDocument.Parse(output);
            if (!result.RootElement.TryGetProperty("verified", out var verified) || verified.ValueKind != JsonValueKind.True)
                throw new InvalidOperationException("TRAFFIC_FIREWALL_PREPARATION_FAILED");
            await File.WriteAllTextAsync(Path.Combine(directory, "local-firewall.json"), output);
        }
        catch
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            try { await Task.WhenAll(stdout, stderr); } catch (IOException) { }
            throw;
        }
    }
}
