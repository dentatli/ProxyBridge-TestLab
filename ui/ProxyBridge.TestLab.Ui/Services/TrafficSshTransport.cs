using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed partial class OpenSshServerTransport
{
    internal async Task<JsonElement> ExecuteTrafficPythonAsync(ServerTarget target, string script, CancellationToken token)
    {
        ValidateTarget(target);
        if (target.Username != "root" || !File.Exists(paths.KnownHostsPath))
            throw new InvalidOperationException("TRAFFIC_SSH_TRUST_REQUIRED");
        var arguments = BuildSshArguments(target);
        arguments.AddRange(["python3", "-B", "-"]);
        var result = await RunProcessAsync(FindOpenSshTool("ssh.exe"), arguments, script.Replace("\r\n", "\n"), TimeSpan.FromSeconds(90), token);
        if (result.TimedOut || result.ExitCode != 0 || result.StandardOutput.Length > 262144)
            throw new InvalidOperationException("TRAFFIC_SSH_OPERATION_FAILED");
        using var document = JsonDocument.Parse(result.StandardOutput);
        var value = document.RootElement.Clone();
        if (value.TryGetProperty("error", out var error)) throw new InvalidOperationException(error.GetString() ?? "TRAFFIC_REMOTE_ERROR");
        return value;
    }
}
