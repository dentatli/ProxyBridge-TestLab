using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class ServerProvisioningService(
    SettingsStore settingsStore,
    ServerTrustStore trustStore,
    ServerReceiptStore receiptStore,
    ServerArtifactBuilder artifactBuilder,
    IServerTransport transport)
{
    private readonly SemaphoreSlim _operationGate = new(1, 1);
    private readonly object _stateGate = new();
    private readonly Dictionary<string, PendingTrust> _pendingTrust = new(StringComparer.Ordinal);
    private readonly Dictionary<string, StoredPlan> _plans = new(StringComparer.Ordinal);
    private ServerDiscoveryData? _lastDiscovery;
    private string? _lastValidatedTargetHash;
    private DateTimeOffset? _lastVerifiedUtc;

    public async Task<ServerStatusView> GetStatusAsync(CancellationToken cancellationToken)
    {
        var snapshot = await settingsStore.LoadAsync(cancellationToken);
        if (!TryBuildTarget(snapshot, out var target, out var remediation))
            return new ServerStatusView("UNCONFIGURED", "Complete the SSH connection fields before server setup.", false, false, false, null, null, remediation);

        var targetHash = ServerTrustStore.ComputeTargetHash(target!);
        var trust = await trustStore.LoadAsync(cancellationToken);
        var receipt = await receiptStore.LoadValidAsync(cancellationToken);
        var trusted = trust is not null && string.Equals(trust.TargetHash, targetHash, StringComparison.Ordinal);
        var receiptCurrent = receipt is not null && receipt.Receipt.ExpiresUtc > DateTimeOffset.UtcNow &&
            string.Equals(receipt.Receipt.TargetHash, targetHash, StringComparison.Ordinal) && trusted &&
            trust!.Fingerprints.OrderBy(value => value, StringComparer.Ordinal).SequenceEqual(receipt.Receipt.HostFingerprints.OrderBy(value => value, StringComparer.Ordinal), StringComparer.Ordinal);
        bool recentlyVerified;
        lock (_stateGate)
        {
            recentlyVerified = receiptCurrent && string.Equals(_lastValidatedTargetHash, targetHash, StringComparison.Ordinal) &&
                _lastVerifiedUtc is not null && DateTimeOffset.UtcNow - _lastVerifiedUtc < TimeSpan.FromMinutes(15);
        }

        if (recentlyVerified)
            return new ServerStatusView("READY", "The Debian/Ubuntu endpoint is provisioned and recently verified.", true, true, true, _lastVerifiedUtc, receipt!.Receipt.ExpiresUtc, []);
        if (receiptCurrent)
            return new ServerStatusView("STALE", "A valid receipt exists, but this controller session has not revalidated the remote endpoint.", true, true, true, _lastVerifiedUtc, receipt!.Receipt.ExpiresUtc, ["Validate the server again before a real run."]);
        if (!trusted)
            return new ServerStatusView("NEEDS_HOST_TRUST", "The SSH host key has not been explicitly trusted.", true, false, false, null, null, ["Validate the connection and confirm the displayed fingerprint."]);
        return new ServerStatusView("VALIDATION_REQUIRED", "The SSH host is trusted, but no current readiness receipt is available.", true, true, false, _lastVerifiedUtc, null, ["Validate the server and create an installation or repair plan."]);
    }

    public async Task<ServerValidationView> ValidateAsync(ServerValidationRequest request, CancellationToken cancellationToken, bool ubuntuOnly = false)
    {
        await _operationGate.WaitAsync(cancellationToken);
        try { return await ValidateCoreAsync(request, cancellationToken, ubuntuOnly); }
        finally { _operationGate.Release(); }
    }

    public async Task<ServerPlanView> CreatePlanAsync(CancellationToken cancellationToken, bool ubuntuOnly = false)
    {
        await _operationGate.WaitAsync(cancellationToken);
        try
        {
            var validation = await ValidateCoreAsync(new ServerValidationRequest(), cancellationToken, ubuntuOnly);
            if (validation.State is not ("PLAN_READY" or "REPAIR_REQUIRED" or "READY"))
                throw new ServerOperationException("SERVER_NOT_READY_FOR_PLAN", validation);

            var snapshot = await settingsStore.LoadAsync(cancellationToken);
            var target = BuildTarget(snapshot);
            var targetHash = ServerTrustStore.ComputeTargetHash(target);
            ServerDiscoveryData discovery;
            lock (_stateGate) discovery = _lastDiscovery ?? throw new InvalidOperationException("SERVER_DISCOVERY_MISSING");
            var artifacts = artifactBuilder.Build(snapshot.Settings, GetAllowedSources(snapshot, discovery));
            var planId = Guid.NewGuid().ToString("N");
            var now = DateTimeOffset.UtcNow;
            var warnings = new List<string>
            {
                "Host firewall policy remains externally owned; TestLab does not replace or broaden it.",
                "The endpoint systemd unit denies other sources and allows the observed SSH-client egress plus a configured proxy-host IP.",
                "TCP/UDP control probes and proxy-egress verification remain per-run launch gates.",
                "Every installed protocol plugin is hash-verified and must pass the dependency-free server-agent self-test.",
                "Protocol ports and certificates are TestLab-managed defaults; no manual port, hash or certificate entry is required."
            };
            if (!string.Equals(discovery.FirewallAdapter, "none", StringComparison.Ordinal))
                warnings.Add($"Detected {discovery.FirewallAdapter}; no unowned firewall rules will be modified.");
            if (snapshot.Settings.Capabilities.Socks5 &&
                (!snapshot.ProtectedValues.TryGetValue("proxy.host", out var proxyHost) || !System.Net.IPAddress.TryParse(proxyHost, out _)))
                warnings.Add("The SOCKS host is not an IP address, so its real egress is not added automatically; proxy readiness remains blocked until a later control probe proves and scopes it.");
            var packages = discovery.Python3 ? Array.Empty<string>() : ["python3"];
            var plan = new ServerPlanView(
                planId, now, now.AddMinutes(10), validation.State == "READY" ? "NO_CHANGE_VERIFY" : validation.State,
                "Configured SSH endpoint", packages,
                ["/opt/proxybridge-testlab", "/var/log/proxybridge-testlab", "/opt/proxybridge-testlab/current/server-plugin-manifest.json", "/etc/systemd/system/proxybridge-testlab-endpoint.service", "/etc/logrotate.d/proxybridge-testlab"],
                artifacts.Ports.TcpPorts,
                artifacts.Ports.UdpPorts,
                artifacts.PublicHashes,
                artifacts.BundleId,
                artifacts.ImplementedPlugins,
                [target.Username == "root" ? "sh -s < plan-owned installer" : "sudo -n sh -s < plan-owned installer"],
                [
                    new ServerPlanStep(1, "VERIFY_STAGED_ARTIFACTS", "Decode to a private temporary directory, verify every artifact and run the endpoint and protocol self-tests before activation.", true, "Remove only the plan-owned staging directory."),
                    new ServerPlanStep(2, "ENSURE_RUNTIME", discovery.Python3 ? "Use the existing Python 3 runtime." : "Install the Debian/Ubuntu python3 package.", !discovery.Python3, "Installed packages are retained because removing shared dependencies is unsafe."),
                    new ServerPlanStep(3, "ENSURE_SERVICE_IDENTITY", "Create the dedicated unprivileged proxybridge-testlab account when absent.", true, "Remove the account only if this plan created it and activation fails."),
                    new ServerPlanStep(4, "ATOMIC_ACTIVATION", "Activate a versioned endpoint, systemd unit and log rotation configuration.", true, "Restore the exact prior TestLab files and service state."),
                    new ServerPlanStep(5, "VERIFY_SERVICE", "Verify bundle hashes, plugin self-test, enabled/active service state and every required TCP/UDP listener.", false, "No rollback is needed for read-only verification.")
                ], warnings, artifacts.Ports.ListenerTcpPorts, artifacts.Ports.ListenerUdpPorts);
            var settingsDigest = ComputeSettingsDigest(snapshot, artifacts);
            lock (_stateGate)
            {
                _plans.Clear();
                _plans[planId] = new StoredPlan(plan, targetHash, settingsDigest, discovery, artifacts, ubuntuOnly);
            }
            return plan;
        }
        finally { _operationGate.Release(); }
    }

    public async Task<ServerApplyView> ApplyAsync(ServerApplyRequest request, bool repair, CancellationToken cancellationToken)
    {
        if (!request.Confirmed) throw new ServerOperationException("SERVER_PLAN_CONFIRMATION_REQUIRED");
        await _operationGate.WaitAsync(cancellationToken);
        try
        {
            StoredPlan stored;
            lock (_stateGate)
            {
                if (!_plans.TryGetValue(request.PlanId, out stored!)) throw new ServerOperationException("SERVER_PLAN_NOT_FOUND");
                _plans.Remove(request.PlanId);
            }
            if (stored.View.ExpiresUtc <= DateTimeOffset.UtcNow) throw new ServerOperationException("SERVER_PLAN_EXPIRED");
            if (repair && stored.View.State == "PLAN_READY") throw new ServerOperationException("SERVER_REPAIR_PLAN_REQUIRED");

            var snapshot = await settingsStore.LoadAsync(cancellationToken);
            var target = BuildTarget(snapshot);
            var targetHash = ServerTrustStore.ComputeTargetHash(target);
            var currentArtifacts = artifactBuilder.Build(snapshot.Settings, GetAllowedSources(snapshot, stored.Discovery));
            if (!string.Equals(stored.TargetHash, targetHash, StringComparison.Ordinal) ||
                !string.Equals(stored.SettingsDigest, ComputeSettingsDigest(snapshot, currentArtifacts), StringComparison.Ordinal))
                throw new ServerOperationException("SERVER_PLAN_INPUT_CHANGED");

            if (stored.UbuntuOnly)
            {
                var currentDiscovery = await transport.DiscoverAsync(target, stored.Artifacts.Ports, cancellationToken);
                if (!SupportedUbuntu(currentDiscovery) || target.Username != "root")
                    throw new ServerOperationException("UBUNTU_PLATFORM_CHANGED");
                if (currentDiscovery.ConflictingTcpPorts.Count > 0 || currentDiscovery.ConflictingUdpPorts.Count > 0)
                    throw new ServerOperationException("SERVER_PORT_CONFLICT");
            }

            if (stored.View.State == "NO_CHANGE_VERIFY")
            {
                var noChangeVerification = await transport.VerifyAsync(target, stored.Artifacts.Ports, cancellationToken);
                var noChangeHashesMatch = noChangeVerification.Succeeded && noChangeVerification.PluginSelfTestPassed &&
                    noChangeVerification.PluginCount == stored.Artifacts.ImplementedPlugins.Count &&
                    string.Equals(noChangeVerification.EndpointSha256, stored.Artifacts.Hashes["pb_net_endpoint.py"], StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(noChangeVerification.UnitSha256, stored.Artifacts.Hashes["proxybridge-testlab-endpoint.service"], StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(noChangeVerification.PluginManifestSha256, stored.Artifacts.Hashes["server-plugin-manifest.json"], StringComparison.OrdinalIgnoreCase);
                if (!noChangeHashesMatch) return new ServerApplyView("REPAIR_REQUIRED", "SERVER_VERIFICATION_FAILED", false, false, false, null, null);
                var noChangeTrust = await trustStore.LoadAsync(cancellationToken) ?? throw new ServerOperationException("SSH_HOST_NOT_TRUSTED");
                var noChangeReceipt = await receiptStore.CreateAsync(targetHash, noChangeTrust.Fingerprints, stored.Artifacts.Hashes, cancellationToken);
                lock (_stateGate) { _lastValidatedTargetHash = targetHash; _lastVerifiedUtc = DateTimeOffset.UtcNow; }
                return new ServerApplyView("READY", "No server changes were needed; the existing endpoint was verified.", false, false, true, _lastVerifiedUtc, noChangeReceipt.Receipt.ExpiresUtc);
            }

            var applied = await transport.ApplyAsync(target, request.PlanId, snapshot.Settings, stored.Artifacts, !stored.Discovery.Python3, cancellationToken);
            if (!applied.Succeeded)
                return new ServerApplyView("REPAIR_REQUIRED", applied.ErrorCode, false, applied.RollbackAttempted, applied.RollbackSucceeded, null, null);

            var verification = await transport.VerifyAsync(target, stored.Artifacts.Ports, cancellationToken);
            var hashesMatch = verification.Succeeded &&
                string.Equals(verification.EndpointSha256, stored.Artifacts.Hashes["pb_net_endpoint.py"], StringComparison.OrdinalIgnoreCase) &&
                string.Equals(verification.UnitSha256, stored.Artifacts.Hashes["proxybridge-testlab-endpoint.service"], StringComparison.OrdinalIgnoreCase) &&
                string.Equals(verification.PluginManifestSha256, stored.Artifacts.Hashes["server-plugin-manifest.json"], StringComparison.OrdinalIgnoreCase) &&
                verification.PluginSelfTestPassed && verification.PluginCount == stored.Artifacts.ImplementedPlugins.Count;
            if (!hashesMatch)
                return new ServerApplyView("REPAIR_REQUIRED", "SERVER_POST_APPLY_VERIFICATION_FAILED", true, false, false, null, null);

            var trust = await trustStore.LoadAsync(cancellationToken) ?? throw new ServerOperationException("SSH_HOST_NOT_TRUSTED");
            var receipt = await receiptStore.CreateAsync(targetHash, trust.Fingerprints, stored.Artifacts.Hashes, cancellationToken);
            lock (_stateGate)
            {
                _lastValidatedTargetHash = targetHash;
                _lastVerifiedUtc = DateTimeOffset.UtcNow;
            }
            return new ServerApplyView("READY", "The endpoint was applied and verified.", true, false, true, _lastVerifiedUtc, receipt.Receipt.ExpiresUtc);
        }
        finally { _operationGate.Release(); }
    }

    public async Task<ServerMetricsView> GetMetricsAsync(CancellationToken cancellationToken)
    {
        var status = await GetStatusAsync(cancellationToken);
        if (status.State != "READY") throw new ServerOperationException("SERVER_NOT_READY_FOR_METRICS");
        var snapshot = await settingsStore.LoadAsync(cancellationToken);
        return await transport.GetMetricsAsync(BuildTarget(snapshot), cancellationToken);
    }

    private async Task<ServerValidationView> ValidateCoreAsync(ServerValidationRequest request, CancellationToken cancellationToken, bool ubuntuOnly = false)
    {
        var snapshot = await settingsStore.LoadAsync(cancellationToken);
        if (!TryBuildTarget(snapshot, out var target, out var remediation))
            return new ServerValidationView("UNCONFIGURED", "Complete the SSH connection fields first.", [], null, false, null, remediation);
        var targetHash = ServerTrustStore.ComputeTargetHash(target!);
        HostKeyObservation observation;
        try { observation = await transport.ScanHostKeysAsync(target!, cancellationToken); }
        catch (InvalidOperationException exception)
        {
            return new ServerValidationView("ERROR", Humanize(exception.Message), [], null, false, null, ["Verify the server address, SSH port and outbound connectivity."]);
        }

        var trust = await trustStore.LoadAsync(cancellationToken);
        var changed = trust is not null && (!string.Equals(trust.TargetHash, targetHash, StringComparison.Ordinal) || !ServerTrustStore.Matches(trust, targetHash, observation));
        var trusted = trust is not null && ServerTrustStore.Matches(trust, targetHash, observation);
        if (!trusted)
        {
            if (request.ConfirmHostTrust)
            {
                PendingTrust? pending;
                lock (_stateGate) _pendingTrust.TryGetValue(targetHash, out pending);
                if (pending is null || pending.ExpiresUtc <= DateTimeOffset.UtcNow || !FixedEquals(pending.Token, request.TrustToken))
                    return CreateTrustView(observation, targetHash, changed, "The host-key confirmation expired. Validate again.");
                if (!pending.Observation.KnownHostLines.OrderBy(value => value, StringComparer.Ordinal)
                    .SequenceEqual(observation.KnownHostLines.OrderBy(value => value, StringComparer.Ordinal), StringComparer.Ordinal))
                    return CreateTrustView(observation, targetHash, changed, "The host key changed during confirmation. Validate the new fingerprint independently.");
                if (pending.Changed && !request.ReplaceChangedHostKey)
                    return CreateTrustView(observation, targetHash, true, "The SSH target or host key changed. Explicit replacement confirmation is required.");
                await trustStore.SaveAsync(targetHash, pending.Observation, cancellationToken);
                lock (_stateGate) _pendingTrust.Remove(targetHash);
            }
            else
            {
                return CreateTrustView(observation, targetHash, changed, changed
                    ? "The SSH target or host key differs from the stored trust record. Connection is blocked until explicitly replaced."
                    : "Confirm the displayed SSH host-key fingerprint before discovery.");
            }
        }

        ServerDiscoveryData discovery;
        var requiredPorts = artifactBuilder.GetRequiredPorts(snapshot.Settings);
        try { discovery = await transport.DiscoverAsync(target!, requiredPorts, cancellationToken); }
        catch (InvalidOperationException exception)
        {
            return new ServerValidationView("ERROR", Humanize(exception.Message), observation.Fingerprints, null, false, null, ["Verify the private key, SSH user and non-interactive login."]);
        }
        var view = ToDiscoveryView(discovery);
        if (ubuntuOnly && (!SupportedUbuntu(discovery) || target!.Username != "root"))
            return new ServerValidationView("UNSUPPORTED", "UBUNTU_LTS_ROOT_REQUIRED", observation.Fingerprints, null, false, view,
                ["Use root on Ubuntu 22.04, 24.04 or 26.04 LTS with systemd."]);
        if (discovery.OsId is not ("debian" or "ubuntu") || !discovery.Systemd)
            return new ServerValidationView("UNSUPPORTED", "Only Debian or Ubuntu with systemd as PID 1 is supported.", observation.Fingerprints, null, false, view, ["Use a supported Debian/Ubuntu systemd server."]);
        if (!discovery.SudoNonInteractive)
            return new ServerValidationView("ERROR", "The SSH account cannot run sudo -n. No changes were made.", observation.Fingerprints, null, false, view, ["Grant the selected account narrowly scoped non-interactive sudo before provisioning."]);
        if (discovery.AvailableDiskKb < 131072)
            return new ServerValidationView("ERROR", "The server has less than 128 MiB available under /opt.", observation.Fingerprints, null, false, view, ["Free disk space and validate again."]);
        if (discovery.Python3 && !discovery.PythonCompatible)
            return new ServerValidationView("UNSUPPORTED", "The server Python runtime is older than 3.10.", observation.Fingerprints, null, false, view, ["Use a supported Debian/Ubuntu release with Python 3.10 or newer."]);
        if (!System.Net.IPAddress.TryParse(discovery.DirectEgressIp, out _))
            return new ServerValidationView("ERROR", "The SSH session did not expose a valid client egress address.", observation.Fingerprints, null, false, view, ["Verify the SSH route and validate again."]);
        if (discovery.ConflictingTcpPorts.Count > 0 || discovery.ConflictingUdpPorts.Count > 0)
            return new ServerValidationView("ERROR", "One or more TestLab-owned protocol ports are already in use by another service.", observation.Fingerprints, null, false, view,
                ["Free the listed TCP/UDP ports on the endpoint and validate again. TestLab will not stop or replace an unrelated service."]);

        var artifacts = artifactBuilder.Build(snapshot.Settings, GetAllowedSources(snapshot, discovery));
        var exact = discovery.ServiceActive && discovery.ServiceEnabled &&
            string.Equals(discovery.EndpointSha256, artifacts.Hashes["pb_net_endpoint.py"], StringComparison.OrdinalIgnoreCase) &&
            string.Equals(discovery.UnitSha256, artifacts.Hashes["proxybridge-testlab-endpoint.service"], StringComparison.OrdinalIgnoreCase) &&
            string.Equals(discovery.PluginManifestSha256, artifacts.Hashes["server-plugin-manifest.json"], StringComparison.OrdinalIgnoreCase) &&
            discovery.PluginSelfTestPassed && discovery.PluginCount == artifacts.ImplementedPlugins.Count;
        lock (_stateGate) { _lastDiscovery = discovery; _lastValidatedTargetHash = targetHash; }
        if (exact)
        {
            var verification = await transport.VerifyAsync(target!, artifacts.Ports, cancellationToken);
            var verificationExact = verification.Succeeded && verification.PluginSelfTestPassed &&
                verification.PluginCount == artifacts.ImplementedPlugins.Count &&
                string.Equals(verification.EndpointSha256, artifacts.Hashes["pb_net_endpoint.py"], StringComparison.OrdinalIgnoreCase) &&
                string.Equals(verification.UnitSha256, artifacts.Hashes["proxybridge-testlab-endpoint.service"], StringComparison.OrdinalIgnoreCase) &&
                string.Equals(verification.PluginManifestSha256, artifacts.Hashes["server-plugin-manifest.json"], StringComparison.OrdinalIgnoreCase);
            if (verificationExact)
            {
                var currentTrust = await trustStore.LoadAsync(cancellationToken) ?? throw new InvalidOperationException("SSH_HOST_NOT_TRUSTED");
                await receiptStore.CreateAsync(targetHash, currentTrust.Fingerprints, artifacts.Hashes, cancellationToken);
                lock (_stateGate) _lastVerifiedUtc = DateTimeOffset.UtcNow;
                return new ServerValidationView("READY", "The installed endpoint matches this TestLab build and is healthy.", observation.Fingerprints, null, false, view, []);
            }
        }

        var state = discovery.ServiceExists ? "REPAIR_REQUIRED" : "PLAN_READY";
        var message = discovery.ServiceExists
            ? "A partial, stopped or drifted TestLab endpoint was found. Review a repair plan before changes."
            : "Read-only discovery passed. Review the exact installation plan before changes.";
        return new ServerValidationView(state, message, observation.Fingerprints, null, false, view, []);
    }

    private ServerValidationView CreateTrustView(HostKeyObservation observation, string targetHash, bool changed, string message)
    {
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(24)).ToLowerInvariant();
        lock (_stateGate)
        {
            _pendingTrust[targetHash] = new PendingTrust(token, observation, changed, DateTimeOffset.UtcNow.AddMinutes(5));
        }
        return new ServerValidationView("NEEDS_HOST_TRUST", message, observation.Fingerprints, token, changed, null,
            [changed ? "Compare this server fingerprint through an independent server-console channel before replacing stored trust." : "Compare the fingerprint with the value shown by your server provider before trusting it."]);
    }

    private static bool TryBuildTarget(SettingsSnapshot snapshot, out ServerTarget? target, out IReadOnlyList<string> remediation)
    {
        var issues = new List<string>();
        snapshot.ProtectedValues.TryGetValue("server_connection.host", out var host);
        snapshot.ProtectedValues.TryGetValue("server_connection.private_key_path", out var key);
        var user = snapshot.Settings.ServerConnection.Username;
        if (string.IsNullOrWhiteSpace(host)) issues.Add("Enter the server host or IP in Environment Setup.");
        if (string.IsNullOrWhiteSpace(user)) issues.Add("Enter the SSH user in Environment Setup.");
        if (string.IsNullOrWhiteSpace(key) || !File.Exists(key)) issues.Add("Select an existing SSH private key in Environment Setup.");
        if (snapshot.Settings.ServerConnection.SshPort is < 1 or > 65535) issues.Add("Enter a valid SSH port.");
        if (issues.Count > 0) { target = null; remediation = issues; return false; }
        target = new ServerTarget(host!, snapshot.Settings.ServerConnection.SshPort, user, key!);
        remediation = [];
        return true;
    }

    private static ServerTarget BuildTarget(SettingsSnapshot snapshot) =>
        TryBuildTarget(snapshot, out var target, out _) ? target! : throw new ServerOperationException("SERVER_CONNECTION_INCOMPLETE");

    private static ServerDiscoveryView ToDiscoveryView(ServerDiscoveryData value) => new(
        value.OsId, value.OsVersion, value.Architecture, value.Systemd, value.SudoNonInteractive, value.Python3, value.PythonVersion, value.PythonCompatible,
        value.AvailableDiskKb, value.ServiceExists ? (value.ServiceActive ? "ACTIVE" : "INSTALLED_NOT_ACTIVE") : "NOT_INSTALLED",
        value.FirewallAdapter, !string.IsNullOrWhiteSpace(value.DirectEgressIp), value.PluginSelfTestPassed, value.PluginCount,
        value.ConflictingTcpPorts, value.ConflictingUdpPorts);

    private static string ComputeSettingsDigest(SettingsSnapshot snapshot, ServerArtifactBundle artifacts)
    {
        var protectedSubset = snapshot.ProtectedValues.Where(item => item.Key.StartsWith("server_", StringComparison.Ordinal))
            .OrderBy(item => item.Key, StringComparer.Ordinal).Select(item => new KeyValuePair<string, string>(item.Key, item.Value));
        var value = new
        {
            snapshot.Settings.ServerConnection.Username,
            snapshot.Settings.ServerConnection.SshPort,
            snapshot.Settings.ServerEndpoint.PortA,
            snapshot.Settings.ServerEndpoint.PortB,
            snapshot.Settings.Capabilities.Ipv6,
            protected_values = protectedSubset,
            hashes = artifacts.Hashes.OrderBy(item => item.Key, StringComparer.Ordinal)
        };
        return Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(value))).ToLowerInvariant();
    }

    private static IReadOnlyList<string> GetAllowedSources(SettingsSnapshot snapshot, ServerDiscoveryData discovery)
    {
        var values = new List<string> { discovery.DirectEgressIp };
        if (snapshot.ProtectedValues.TryGetValue("proxy.host", out var proxyHost) && System.Net.IPAddress.TryParse(proxyHost, out var proxyAddress))
            values.Add(proxyAddress.ToString());
        return values.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    }

    private static bool FixedEquals(string expected, string? actual)
    {
        if (string.IsNullOrEmpty(actual)) return false;
        var left = Encoding.UTF8.GetBytes(expected); var right = Encoding.UTF8.GetBytes(actual);
        try { return left.Length == right.Length && CryptographicOperations.FixedTimeEquals(left, right); }
        finally { CryptographicOperations.ZeroMemory(left); CryptographicOperations.ZeroMemory(right); }
    }

    private static string Humanize(string code) => code switch
    {
        "SSH_HOST_KEY_SCAN_TIMEOUT" => "SSH host-key discovery timed out.",
        "SSH_HOST_KEY_UNAVAILABLE" => "No SSH host key was returned.",
        "SSH_OPERATION_TIMEOUT" => "The bounded SSH operation timed out.",
        "SSH_OPERATION_FAILED" => "SSH authentication or the read-only remote command failed.",
        _ => "Server validation failed without changing the server."
    };

    private sealed record PendingTrust(string Token, HostKeyObservation Observation, bool Changed, DateTimeOffset ExpiresUtc);
    private static bool SupportedUbuntu(ServerDiscoveryData discovery) =>
        discovery.OsId == "ubuntu" && discovery.OsVersion is "22.04" or "24.04" or "26.04" && discovery.Systemd;

    private sealed record StoredPlan(ServerPlanView View, string TargetHash, string SettingsDigest, ServerDiscoveryData Discovery, ServerArtifactBundle Artifacts, bool UbuntuOnly);
}

public sealed class ServerOperationException : Exception
{
    public ServerOperationException(string code, object? detail = null) : base(code) => Detail = detail;
    public object? Detail { get; }
}
