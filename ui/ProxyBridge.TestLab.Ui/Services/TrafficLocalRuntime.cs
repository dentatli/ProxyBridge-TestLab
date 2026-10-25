using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed partial class TrafficRuntimeService
{
    private async Task<JsonElement> WithLocalRuntimeAsync(string directory, Func<Payload, CancellationToken, Task<JsonElement>> execute)
    {
        var python = LocalPythonRuntime.Resolve(app.RepositoryRoot);
        if (!File.Exists(python)) throw new InvalidOperationException("TRAFFIC_PYTHON_311_REQUIRED");
        var nativeFiles = NativeFiles(app.RepositoryRoot);
        await PrepareLocalFirewallAsync(python, directory);
        var sources = Directory.EnumerateFiles(Path.Combine(app.RepositoryRoot, "src", "trafficlab"), "*.py")
            .Concat(TrafficDependencyFiles("win-x64")).Append(Path.Combine(app.RepositoryRoot,"vendor","traffic-dependencies.lock.json"))
            .Append(python).Concat(Directory.EnumerateFiles(Path.GetDirectoryName(python)!, "*.dll")).Concat(nativeFiles)
            .ToDictionary(path => path, path =>
            {
                if (File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("TRAFFIC_LOCAL_REPARSE_POINT");
                return Hash(File.ReadAllBytes(path));
            });
        var runtime = Path.Combine(directory, "local-origin");
        var bytes = RandomNumberGenerator.GetBytes(32);
        var secret = Convert.ToHexString(bytes).ToLowerInvariant();
        var protectedSecret = protector.Protect(bytes);
        try
        {
            using var archive = new FileStream(Path.Combine(directory,"local-origin-secret.dpapi"),FileMode.CreateNew,FileAccess.Write,FileShare.None);
            archive.Write(protectedSecret);
        }
        finally { CryptographicOperations.ZeroMemory(protectedSecret); }
        CryptographicOperations.ZeroMemory(bytes);
        ProcessStartInfo PythonStart(string executable, string module)
        {
            var start = new ProcessStartInfo(executable) { UseShellExecute=false, CreateNoWindow=true,
                WorkingDirectory=app.RepositoryRoot, RedirectStandardInput=true, RedirectStandardOutput=true, RedirectStandardError=true };
            start.ArgumentList.Add("-u"); start.ArgumentList.Add("-m"); start.ArgumentList.Add(module);
            start.Environment["PYTHONPATH"] = Path.Combine(app.RepositoryRoot,"src");
            start.Environment["PYTHONDONTWRITEBYTECODE"] = "1";
            return start;
        }
        Dictionary<string, int> applicationPorts;
        var portQuery = PythonStart(python, "trafficlab.local_runtime");
        portQuery.ArgumentList.Add("--application-ports");
        using (var query = Process.Start(portQuery) ?? throw new InvalidOperationException("TRAFFIC_LOCAL_PREPARATION_START_FAILED"))
        {
            query.StandardInput.Close();
            var output = query.StandardOutput.ReadToEndAsync();
            var errors = DrainAsync(query.StandardError);
            try { await query.WaitForExitAsync(Token).WaitAsync(TimeSpan.FromSeconds(15), Token); }
            catch { if (!query.HasExited) query.Kill(entireProcessTree: true); throw; }
            await errors;
            var text = await output;
            if (query.ExitCode != 0 || text.Length > 8192) throw new InvalidOperationException("TRAFFIC_LOCAL_PREPARATION_FAILED");
            applicationPorts = JsonSerializer.Deserialize<Dictionary<string, int>>(text) ?? throw new InvalidOperationException("TRAFFIC_LOCAL_PREPARATION_FAILED");
        }
        await using var nativeOrigin = await NativeHost.StartAsync(app.RepositoryRoot, directory, secret, false, applicationPorts, Token);
        await using var nativeWorker = await NativeHost.StartAsync(app.RepositoryRoot, directory, secret, true, applicationPorts, Token);
        foreach (var file in new[] { nativeOrigin.Configuration, nativeWorker.Configuration }) sources[file] = Hash(File.ReadAllBytes(file));
        try
        {
        var prepare = PythonStart(python,"trafficlab.local_runtime");
        prepare.ArgumentList.Add("--prepare");
        JsonElement prepared;
        using (var process = Process.Start(prepare) ?? throw new InvalidOperationException("TRAFFIC_LOCAL_PREPARATION_START_FAILED"))
        {
            var output = process.StandardOutput.ReadToEndAsync();
            var errors = DrainAsync(process.StandardError);
            await process.StandardInput.WriteAsync(JsonSerializer.Serialize(new { directory=runtime, secret, source_hashes=sources,
                native_engine = new { port = nativeOrigin.Binding.Port, executable = nativeOrigin.Binding.Executable, pid = nativeOrigin.Binding.Pid } }));
            process.StandardInput.Close();
            try { await process.WaitForExitAsync(Token).WaitAsync(TimeSpan.FromSeconds(45),Token); }
            catch { if (!process.HasExited) process.Kill(entireProcessTree:true); throw; }
            await errors;
            var text = await output;
            if (process.ExitCode != 0 || text.Length > 32768) throw new InvalidOperationException("TRAFFIC_LOCAL_PREPARATION_FAILED");
            using var data = JsonDocument.Parse(text);
            prepared = data.RootElement.Clone();
        }
        var configuration = prepared.GetProperty("configuration").GetString()!;
        await PrepareLocalFirewallAsync(prepared.GetProperty("executable").GetString()!, directory);
        var startOrigin = PythonStart(prepared.GetProperty("executable").GetString()!,"trafficlab.agent");
        startOrigin.Environment["PYTHONHOME"] = prepared.GetProperty("python_home").GetString();
        startOrigin.ArgumentList.Add("--config"); startOrigin.ArgumentList.Add(configuration);
        using var origin = Process.Start(startOrigin) ?? throw new InvalidOperationException("TRAFFIC_LOCAL_ORIGIN_START_FAILED");
        origin.StandardInput.Close();
        var originErrors = DrainAsync(origin.StandardError);
        Task? originOutput = null;
        try
        {
            var ready = await origin.StandardOutput.ReadLineAsync(Token).AsTask().WaitAsync(TimeSpan.FromSeconds(30),Token);
            originOutput = DrainAsync(origin.StandardOutput);
            if (ready != "TRAFFIC_AGENT_READY origin=42501 proxy=42502 control=42503" || origin.HasExited)
                throw new InvalidOperationException("TRAFFIC_LOCAL_ORIGIN_NOT_READY_OR_PORT_BUSY");
            var payload = new Payload(prepared.GetProperty("bundle_sha256").GetString()!,new(),new(),"","",secret,"local",
                nativeWorker.Binding, sources);
            return await execute(payload,Token);
        }
        finally
        {
            await File.WriteAllTextAsync(prepared.GetProperty("stop_path").GetString()!,"stop\n");
            try { await origin.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10)); }
            catch (TimeoutException)
            {
                if (!origin.HasExited) { origin.Kill(entireProcessTree:true); await origin.WaitForExitAsync(); } // Only this owned origin.
                throw new InvalidOperationException("TRAFFIC_LOCAL_ORIGIN_CLEANUP_FAILED");
            }
            await originErrors;
            if (originOutput is not null) await originOutput;
            if (origin.ExitCode != 0) throw new InvalidOperationException("TRAFFIC_LOCAL_ORIGIN_EXITED");
        }
        }
        finally
        {
            File.Delete(Path.Combine(runtime, "config-private.json"));
            foreach (var name in new[] { "server.key", "ssh_host.key" }) File.Delete(Path.Combine(runtime, "pki", name));
        }
    }
}
