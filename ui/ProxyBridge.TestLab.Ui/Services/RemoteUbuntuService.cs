using System.Diagnostics;
using System.Net;
using System.Text.Json.Serialization;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record RemoteUbuntuConfiguration(
    [property: JsonPropertyName("host")] string? Host,
    [property: JsonPropertyName("port")] int Port = 22,
    [property: JsonPropertyName("private_key_path")] string? PrivateKeyPath = null);

public sealed record RemoteUbuntuView(bool Busy, string Stage, string? Error, bool HostSaved,
    int Port, string? PublicKey, ServerStatusView Status, ServerValidationView? Validation,
    ServerPlanView? Plan, ServerApplyView? Apply, bool TestReady = false);

/// <summary>Dedicated settings, identity, host trust and receipts; never imports diagnostic state automatically.</summary>
public sealed class RemoteUbuntuService
{
    private readonly AppStoragePaths _storage;
    private readonly AppPaths _app;
    private readonly SettingsStore _settings;
    private readonly ServerProvisioningService _server;
    private readonly RuntimeExecutionLease _runtimeLease;
    private readonly RunCoordinator _runs;
    private readonly CancellationToken _stopping;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly object _stateGate = new();
    private bool _busy;
    private bool _verified;
    private string _stage = "IDLE";
    private string? _error;
    private string? _publicKey;
    private ServerValidationView? _validation;
    private ServerPlanView? _plan;
    private ServerApplyView? _apply;

    public RemoteUbuntuService(AppPaths app, AppStoragePaths storage, DpapiSecretProtector protector,
        RuntimeExecutionLease runtimeLease, RunCoordinator runs, IHostApplicationLifetime lifetime)
    {
        _app = app;
        _storage = new AppStoragePaths(Path.Combine(storage.Root, "remote-ubuntu"));
        _runtimeLease = runtimeLease;
        _runs = runs;
        _stopping = lifetime.ApplicationStopping;
        var certificates = new ProtocolCertificateStore(_storage, protector);
        var ports = new ServerProtocolPortCatalog(app);
        _settings = new SettingsStore(_storage, protector, new LocalArtifactService(app, _storage, ports, certificates));
        _server = new ServerProvisioningService(_settings, new ServerTrustStore(_storage),
            new ServerReceiptStore(_storage, protector), new ServerArtifactBuilder(app, certificates, ports),
            new OpenSshServerTransport(_storage));
    }

    public async Task<RemoteUbuntuView> StateAsync(CancellationToken token)
    {
        var snapshot = await _settings.LoadAsync(token);
        var status = await _server.GetStatusAsync(token);
        lock (_stateGate)
        {
            if (status.State == "READY" && (!_verified || _busy || _error is not null ||
                _validation is { State: not "READY" } || _apply is { State: not "READY" }))
                status = status with { State = "VALIDATION_REQUIRED", ReceiptCurrent = false };
            return new(_busy, _stage, _error, snapshot.ProtectedValues.ContainsKey("server_connection.host"),
                snapshot.Settings.ServerConnection.SshPort, _publicKey, status, _validation, _plan, _apply);
        }
    }

    public Task<RemoteUbuntuView> ConfigureAsync(RemoteUbuntuConfiguration request) => OperateAsync("CONFIGURING", async () =>
    {
        if (request.Port is < 1 or > 65535) throw new InvalidOperationException("SSH_PORT_INVALID");
        var snapshot = await _settings.LoadAsync(_stopping);
        var values = new Dictionary<string, string?>();
        if (!string.IsNullOrWhiteSpace(request.Host))
        {
            if (!IPAddress.TryParse(request.Host.Trim(), out var address) || IPAddress.IsLoopback(address) ||
                address.Equals(IPAddress.Any) || address.Equals(IPAddress.IPv6Any))
                throw new InvalidOperationException("REMOTE_IP_INVALID");
            values["server_connection.host"] = address.ToString();
        }
        if (!string.IsNullOrWhiteSpace(request.PrivateKeyPath))
        {
            var key = ValidateKeyPath(request.PrivateKeyPath.Trim());
            var publicKey = await ReadPublicKeyAsync(key);
            values["server_connection.private_key_path"] = key;
            lock (_stateGate) _publicKey = publicKey;
        }
        snapshot.Settings.ServerConnection.Username = "root";
        snapshot.Settings.ServerConnection.SshPort = request.Port;
        await _settings.SaveAsync(new SettingsUpdateRequest { Settings = snapshot.Settings, ProtectedValues = values }, _stopping);
        lock (_stateGate) { _verified = false; _validation = null; _plan = null; _apply = null; }
    });

    public Task<RemoteUbuntuView> IdentityAsync() => OperateAsync("IDENTITY", async () =>
    {
        var snapshot = await _settings.LoadAsync(_stopping);
        var key = snapshot.ProtectedValues.GetValueOrDefault("server_connection.private_key_path");
        if (string.IsNullOrWhiteSpace(key))
        {
            _storage.EnsureSecureDirectories();
            var directory = Path.Combine(_storage.ConfigRoot, "ssh-identity");
            if (Directory.Exists(directory) && (File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("SSH_KEY_PATH_INVALID");
            AppStoragePaths.EnsureSecureDirectory(directory);
            ValidateKeyLocation(directory);
            // A unique name prevents retries or another session from replacing an existing identity.
            key = Path.Combine(directory, "id_ed25519_" + Guid.NewGuid().ToString("N"));
            await KeygenAsync(["-q", "-t", "ed25519", "-N", "", "-C", "ProxyBridge-TestLab", "-f", key]);
            snapshot.Settings.ServerConnection.Username = "root";
            await _settings.SaveAsync(new SettingsUpdateRequest { Settings = snapshot.Settings,
                ProtectedValues = new() { ["server_connection.private_key_path"] = key } }, _stopping);
        }
        var publicKey = await ReadPublicKeyAsync(ValidateKeyPath(key));
        lock (_stateGate) { _publicKey = publicKey; _plan = null; }
    });

    public Task<RemoteUbuntuView> CheckAsync(ServerValidationRequest request) => OperateAsync("CHECKING", async () =>
    {
        lock (_stateGate) _verified = false;
        var result = await _server.ValidateAsync(request, _stopping, ubuntuOnly: true);
        lock (_stateGate) { _verified = result.State == "READY"; _validation = result; _plan = null; _apply = null; }
    });

    public Task<RemoteUbuntuView> PlanAsync() => OperateAsync("PLANNING", async () =>
    {
        var plan = await _server.CreatePlanAsync(_stopping, ubuntuOnly: true);
        lock (_stateGate) { _plan = plan; _apply = null; }
    });

    public Task<RemoteUbuntuView> ApplyAsync(ServerApplyRequest request) => OperateAsync("APPLYING", async () =>
    {
        ServerPlanView? plan;
        lock (_stateGate) plan = _plan;
        if (plan is null || plan.PlanId != request.PlanId) throw new InvalidOperationException("SERVER_PLAN_NOT_FOUND");
        lock (_stateGate) _verified = false;
        var result = await _server.ApplyAsync(request, plan.State == "REPAIR_REQUIRED", _stopping);
        lock (_stateGate) { _verified = result.State == "READY"; _apply = result; _plan = null; _validation = null; }
    });

    private async Task<RemoteUbuntuView> OperateAsync(string stage, Func<Task> action)
    {
        if (!await _gate.WaitAsync(0, _stopping)) throw new InvalidOperationException("REMOTE_OPERATION_ACTIVE");
        FileStream? operationLock = null;
        FileStream? runtimeLease = null;
        try
        {
            _storage.EnsureSecureDirectories();
            operationLock = new FileStream(Path.Combine(_storage.Root, ".operation.lock"), FileMode.OpenOrCreate,
                FileAccess.ReadWrite, FileShare.None);
            runtimeLease = _runtimeLease.Acquire();
            if (_runs.List().Any(job => job.Mode == "real" && !job.Terminal))
                throw new InvalidOperationException("REAL_RUN_ALREADY_ACTIVE");
            lock (_stateGate) { _busy = true; _stage = stage; _error = null; }
            await action();
            lock (_stateGate) _stage = "COMPLETE";
        }
        catch (ServerOperationException exception)
        {
            lock (_stateGate)
            {
                _error = exception.Message;
                _verified = false;
                if (exception.Detail is ServerValidationView validation) _validation = validation;
                _plan = null;
                _stage = "FAILED";
            }
        }
        catch (Exception exception) when (exception is InvalidOperationException or IOException or UnauthorizedAccessException or OperationCanceledException or SettingsValidationException)
        {
            // Never return process stderr, private paths, keys or credentials to the browser.
            lock (_stateGate)
            {
                _error = exception is InvalidOperationException ? exception.Message :
                    exception is OperationCanceledException ? "REMOTE_OPERATION_CANCELLED" :
                    exception is SettingsValidationException ? "REMOTE_SETTINGS_INVALID" : "REMOTE_STORAGE_OR_LEASE_ERROR";
                _stage = "FAILED";
                _plan = null;
                _verified = false;
            }
        }
        finally
        {
            runtimeLease?.Dispose();
            operationLock?.Dispose();
            lock (_stateGate) _busy = false;
            _gate.Release();
        }
        return await StateAsync(_stopping);
    }

    private string ValidateKeyPath(string key)
    {
        if (!Path.IsPathFullyQualified(key) || key.StartsWith(@"\\", StringComparison.Ordinal))
            throw new InvalidOperationException("SSH_KEY_PATH_INVALID");
        var full = Path.GetFullPath(key);
        if (full.StartsWith(_app.RepositoryRoot.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(full) || new FileInfo(full).Length is < 1 or > 65536)
            throw new InvalidOperationException("SSH_KEY_PATH_INVALID");
        ValidateKeyLocation(full);
        return full;
    }

    private static void ValidateKeyLocation(string full)
    {
        for (string? current = full; current is not null; current = Path.GetDirectoryName(current))
        {
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("SSH_KEY_PATH_INVALID");
            if (Directory.Exists(current) && (Directory.Exists(Path.Combine(current, ".git")) || File.Exists(Path.Combine(current, ".git"))))
                throw new InvalidOperationException("SSH_KEY_PATH_INVALID");
        }
    }

    private async Task<string> ReadPublicKeyAsync(string key)
    {
        var output = (await KeygenAsync(["-y", "-P", "", "-f", key])).Trim();
        if (output.Length > 16384 || output.Contains('\n') ||
            !(output.StartsWith("ssh-ed25519 ", StringComparison.Ordinal) || output.StartsWith("ssh-rsa ", StringComparison.Ordinal) ||
              output.StartsWith("ecdsa-sha2-", StringComparison.Ordinal)))
            throw new InvalidOperationException("SSH_PUBLIC_KEY_INVALID");
        return output;
    }

    private async Task<string> KeygenAsync(IEnumerable<string> arguments)
    {
        var tool = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "OpenSSH", "ssh-keygen.exe");
        if (!File.Exists(tool)) throw new InvalidOperationException("WINDOWS_OPENSSH_NOT_INSTALLED");
        var start = new ProcessStartInfo(tool) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("SSH_KEY_TOOL_FAILED");
        process.StandardInput.Close();
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_stopping);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        try { await process.WaitForExitAsync(timeout.Token); }
        catch (OperationCanceledException)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync(CancellationToken.None);
            await Task.WhenAll(output, error);
            throw new InvalidOperationException("SSH_KEY_TOOL_TIMEOUT");
        }
        await error;
        if (process.ExitCode != 0) throw new InvalidOperationException("SSH_KEY_TOOL_FAILED");
        return await output;
    }
}
