using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record ServerTarget(string Host, int Port, string Username, string PrivateKeyPath);
public sealed record HostKeyObservation(IReadOnlyList<string> KnownHostLines, IReadOnlyList<string> Fingerprints);
public sealed record ServerDiscoveryData(
    string OsId,
    string OsVersion,
    string Architecture,
    bool Systemd,
    bool SudoNonInteractive,
    bool Python3,
    string PythonVersion,
    bool PythonCompatible,
    long AvailableDiskKb,
    bool ServiceExists,
    bool ServiceActive,
    bool ServiceEnabled,
    string EndpointSha256,
    string UnitSha256,
    string PluginManifestSha256,
    bool PluginSelfTestPassed,
    int PluginCount,
    IReadOnlyList<int> ConflictingTcpPorts,
    IReadOnlyList<int> ConflictingUdpPorts,
    string DirectEgressIp,
    string FirewallAdapter);
public sealed record ServerApplyData(bool Succeeded, bool RollbackAttempted, bool RollbackSucceeded, string ErrorCode);
public sealed record ServerVerificationData(bool Succeeded, string EndpointSha256, string UnitSha256, string PluginManifestSha256, bool PluginSelfTestPassed, int PluginCount, bool ServiceActive, bool ServiceEnabled, bool PortsListening, string ErrorCode);

public interface IServerTransport
{
    Task<HostKeyObservation> ScanHostKeysAsync(ServerTarget target, CancellationToken cancellationToken);
    Task<ServerDiscoveryData> DiscoverAsync(ServerTarget target, ServerPortSet ports, CancellationToken cancellationToken);
    Task<ServerApplyData> ApplyAsync(ServerTarget target, string planId, PublicSettings settings, ServerArtifactBundle artifacts, bool installPython, CancellationToken cancellationToken);
    Task<ServerVerificationData> VerifyAsync(ServerTarget target, ServerPortSet ports, CancellationToken cancellationToken);
    Task<ServerMetricsView> GetMetricsAsync(ServerTarget target, CancellationToken cancellationToken);
}

public sealed partial class OpenSshServerTransport(AppStoragePaths paths) : IServerTransport
{
    private static readonly TimeSpan ScanTimeout = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan CommandTimeout = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan ApplyTimeout = TimeSpan.FromMinutes(5);

    public async Task<HostKeyObservation> ScanHostKeysAsync(ServerTarget target, CancellationToken cancellationToken)
    {
        ValidateTarget(target);
        var result = await RunProcessAsync(FindOpenSshTool("ssh-keyscan.exe"),
            ["-T", "10", "-p", target.Port.ToString(CultureInfo.InvariantCulture), target.Host], null, ScanTimeout, cancellationToken);
        var lines = result.StandardOutput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(line => !line.StartsWith('#'))
            .Select(line => NormalizeKnownHostLine(line, target))
            .Distinct(StringComparer.Ordinal)
            .OrderBy(line => line, StringComparer.Ordinal)
            .ToArray();
        if (result.TimedOut) throw new InvalidOperationException("SSH_HOST_KEY_SCAN_TIMEOUT");
        if (lines.Length == 0) lines = await ScanHostKeysViaAuthenticatedProbeAsync(target, cancellationToken);
        if (lines.Length == 0) throw new InvalidOperationException("SSH_HOST_KEY_UNAVAILABLE");
        var fingerprints = lines.Select(ComputeFingerprint).OrderBy(value => value, StringComparer.Ordinal).ToArray();
        return new HostKeyObservation(lines, fingerprints);
    }

    private async Task<string[]> ScanHostKeysViaAuthenticatedProbeAsync(ServerTarget target, CancellationToken cancellationToken)
    {
        var probeRoot = Path.Combine(paths.RuntimeRoot, "host-key-probe-" + Guid.NewGuid().ToString("N"));
        AppStoragePaths.EnsureSecureDirectory(probeRoot);
        var probeKnownHosts = Path.Combine(probeRoot, "known_hosts");
        try
        {
            var arguments = new List<string>
            {
                "-T", "-F", "NUL", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
                "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
                "-o", "StrictHostKeyChecking=accept-new", "-o", "HashKnownHosts=no",
                "-o", $"UserKnownHostsFile={probeKnownHosts}", "-o", "GlobalKnownHostsFile=NUL",
                "-o", "ConnectTimeout=10", "-i", target.PrivateKeyPath,
                "-p", target.Port.ToString(CultureInfo.InvariantCulture),
                $"{target.Username}@{FormatHost(target.Host)}", "true"
            };
            var result = await RunProcessAsync(FindOpenSshTool("ssh.exe"), arguments, null, ScanTimeout, cancellationToken);
            if (result.TimedOut) throw new InvalidOperationException("SSH_HOST_KEY_SCAN_TIMEOUT");
            if (result.ExitCode != 0 || !File.Exists(probeKnownHosts)) throw new InvalidOperationException("SSH_HOST_KEY_UNAVAILABLE");
            return File.ReadAllLines(probeKnownHosts, Encoding.UTF8)
                .Where(line => !string.IsNullOrWhiteSpace(line) && !line.StartsWith('#'))
                .Select(line => NormalizeKnownHostLine(line.Trim(), target))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(line => line, StringComparer.Ordinal)
                .ToArray();
        }
        finally
        {
            var runtimePrefix = Path.GetFullPath(paths.RuntimeRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var resolvedProbe = Path.GetFullPath(probeRoot);
            if (resolvedProbe.StartsWith(runtimePrefix, StringComparison.OrdinalIgnoreCase) &&
                Path.GetFileName(resolvedProbe).StartsWith("host-key-probe-", StringComparison.Ordinal) &&
                Directory.Exists(resolvedProbe))
            {
                Directory.Delete(resolvedProbe, recursive: true);
            }
        }
    }

    public async Task<ServerDiscoveryData> DiscoverAsync(ServerTarget target, ServerPortSet ports, CancellationToken cancellationToken)
    {
        ValidatePorts(ports);
        var tcpPortWords = string.Join(' ', ports.TcpPorts);
        var udpPortWords = string.Join(' ', ports.UdpPorts);
        var script = $$"""
            set -u
            os_id=''; os_version=''
            if [ -r /etc/os-release ]; then . /etc/os-release; os_id="${ID:-}"; os_version="${VERSION_ID:-}"; fi
            pid1="$(cat /proc/1/comm 2>/dev/null || true)"
            arch="$(uname -m 2>/dev/null || true)"
            sudo_ok=0; if [ "$(id -u)" = 0 ] || sudo -n true >/dev/null 2>&1; then sudo_ok=1; fi
            python_ok=0; command -v python3 >/dev/null 2>&1 && python_ok=1
            python_version=''; python_compatible=0
            if [ "$python_ok" -eq 1 ]; then
              python_version="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
              python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)' >/dev/null 2>&1 && python_compatible=1 || true
            fi
            disk_kb="$(df -Pk /opt 2>/dev/null | awk 'NR==2 {print $4}' || true)"; [ -n "$disk_kb" ] || disk_kb=0
            service_exists=0; systemctl cat proxybridge-testlab-endpoint.service >/dev/null 2>&1 && service_exists=1
            service_active=0; systemctl is-active --quiet proxybridge-testlab-endpoint.service >/dev/null 2>&1 && service_active=1
            service_enabled=0; systemctl is-enabled --quiet proxybridge-testlab-endpoint.service >/dev/null 2>&1 && service_enabled=1
            endpoint_hash=''; [ -r /opt/proxybridge-testlab/current/pb_net_endpoint.py ] && endpoint_hash="$(sha256sum /opt/proxybridge-testlab/current/pb_net_endpoint.py | awk '{print $1}')"
            unit_hash=''; [ -r /etc/systemd/system/proxybridge-testlab-endpoint.service ] && unit_hash="$(sha256sum /etc/systemd/system/proxybridge-testlab-endpoint.service | awk '{print $1}')"
            plugin_hash=''; [ -r /opt/proxybridge-testlab/current/server-plugin-manifest.json ] && plugin_hash="$(sha256sum /opt/proxybridge-testlab/current/server-plugin-manifest.json | awk '{print $1}')"
            plugin_selftest=0; plugin_count=0
            if [ -r /opt/proxybridge-testlab/current/pb_server_agent.py ] && [ -r /opt/proxybridge-testlab/current/server-plugin-manifest.json ]; then
              if [ "$(id -u)" = 0 ]; then
                plugin_output="$(runuser -u proxybridge-testlab -- python3 -B /opt/proxybridge-testlab/current/pb_server_agent.py --self-test --manifest /opt/proxybridge-testlab/current/server-plugin-manifest.json 2>/dev/null || true)"
              else
                plugin_output="$(sudo -n -u proxybridge-testlab python3 -B /opt/proxybridge-testlab/current/pb_server_agent.py --self-test --manifest /opt/proxybridge-testlab/current/server-plugin-manifest.json 2>/dev/null || true)"
              fi
              plugin_count="$(printf '%s\n' "$plugin_output" | sed -n 's/^SERVER_AGENT_SELF_TEST_OK plugins=\([0-9][0-9]*\)$/\1/p')"
              if [ -n "$plugin_count" ]; then plugin_selftest=1; else plugin_count=0; fi
            fi
            tcp_conflicts=''; udp_conflicts=''
            if [ "$service_active" -eq 0 ] && command -v ss >/dev/null 2>&1; then
              tcp_listeners="$(ss -H -lnt 2>/dev/null | awk '{print $4}')"
              udp_listeners="$(ss -H -lnu 2>/dev/null | awk '{print $4}')"
              for port in {{tcpPortWords}}; do printf '%s\n' "$tcp_listeners" | grep -Eq "[:.]${port}$" && tcp_conflicts="${tcp_conflicts}${tcp_conflicts:+,}${port}" || true; done
              for port in {{udpPortWords}}; do printf '%s\n' "$udp_listeners" | grep -Eq "[:.]${port}$" && udp_conflicts="${udp_conflicts}${udp_conflicts:+,}${port}" || true; done
            fi
            direct_ip="${SSH_CONNECTION%% *}"
            firewall='none'; command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active' && firewall='ufw-external'
            [ "$firewall" = none ] && command -v nft >/dev/null 2>&1 && firewall='nftables-external'
            printf '%s\n' "OS_ID=$os_id" "OS_VERSION=$os_version" "PID1=$pid1" "ARCH=$arch" "SUDO_N=$sudo_ok" "PYTHON3=$python_ok" "PYTHON_VERSION=$python_version" "PYTHON_COMPATIBLE=$python_compatible" "DISK_KB=$disk_kb" "SERVICE_EXISTS=$service_exists" "SERVICE_ACTIVE=$service_active" "SERVICE_ENABLED=$service_enabled" "ENDPOINT_SHA256=$endpoint_hash" "UNIT_SHA256=$unit_hash" "PLUGIN_MANIFEST_SHA256=$plugin_hash" "PLUGIN_SELFTEST=$plugin_selftest" "PLUGIN_COUNT=$plugin_count" "TCP_CONFLICTS=$tcp_conflicts" "UDP_CONFLICTS=$udp_conflicts" "DIRECT_IP=$direct_ip" "FIREWALL=$firewall"
            """;
        var values = await RunKeyValueScriptAsync(target, script, false, CommandTimeout, cancellationToken);
        return new ServerDiscoveryData(
            Get(values, "OS_ID"), Get(values, "OS_VERSION"), Get(values, "ARCH"),
            Get(values, "PID1") == "systemd", Flag(values, "SUDO_N"), Flag(values, "PYTHON3"), Get(values, "PYTHON_VERSION"), Flag(values, "PYTHON_COMPATIBLE"),
            Number(values, "DISK_KB"), Flag(values, "SERVICE_EXISTS"), Flag(values, "SERVICE_ACTIVE"), Flag(values, "SERVICE_ENABLED"),
            Get(values, "ENDPOINT_SHA256"), Get(values, "UNIT_SHA256"), Get(values, "PLUGIN_MANIFEST_SHA256"), Flag(values, "PLUGIN_SELFTEST"), checked((int)Number(values, "PLUGIN_COUNT")),
            ParsePortList(Get(values, "TCP_CONFLICTS")), ParsePortList(Get(values, "UDP_CONFLICTS")), Get(values, "DIRECT_IP"), Get(values, "FIREWALL"));
    }

    public async Task<ServerApplyData> ApplyAsync(ServerTarget target, string planId, PublicSettings settings, ServerArtifactBundle artifacts, bool installPython, CancellationToken cancellationToken)
    {
        if (!PlanIdRegex().IsMatch(planId)) throw new InvalidOperationException("SERVER_PLAN_ID_INVALID");
        var unitHash = artifacts.Hashes["proxybridge-testlab-endpoint.service"];
        var logrotateHash = artifacts.Hashes["proxybridge-testlab"];
        var runtimeDecodeCommands = string.Join("\n", artifacts.RuntimeFiles.OrderBy(item => item.Key, StringComparer.Ordinal).Select(item =>
        {
            var relative = item.Key.Replace('\\', '/');
            if (!Regex.IsMatch(relative, "^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$", RegexOptions.CultureInvariant)) throw new InvalidOperationException("SERVER_RUNTIME_ARTIFACT_PATH_INVALID");
            var slash = relative.LastIndexOf('/');
            var directoryCommand = slash > 0 ? $"install -d -m 0700 \"$stage/runtime/{relative[..slash]}\"\n" : "";
            return $"{directoryCommand}printf '%s' '{Convert.ToBase64String(item.Value)}' | base64 -d > \"$stage/runtime/{relative}\"";
        }));
        var runtimeVerifyCommands = string.Join("\n", artifacts.RuntimeFiles.OrderBy(item => item.Key, StringComparer.Ordinal).Select(item =>
            $"[ \"$(sha256sum \"$stage/runtime/{item.Key.Replace('\\', '/')}\" | awk '{{print $1}}')\" = '{artifacts.Hashes[item.Key]}' ]"));
        var script = $$"""
            set -eu
            plan='{{planId}}'
            stage="/tmp/proxybridge-testlab-$plan"
            backup="/var/lib/proxybridge-testlab/backups/$plan"
            version="/opt/proxybridge-testlab/versions/{{artifacts.BundleId}}"
            unit='/etc/systemd/system/proxybridge-testlab-endpoint.service'
            rotation='/etc/logrotate.d/proxybridge-testlab'
            success=0; user_created=0; version_created=0; backup_captured=0; was_active=0; was_enabled=0
            systemctl is-active --quiet proxybridge-testlab-endpoint.service >/dev/null 2>&1 && was_active=1 || true
            systemctl is-enabled --quiet proxybridge-testlab-endpoint.service >/dev/null 2>&1 && was_enabled=1 || true
            rollback() {
              [ "$success" -eq 1 ] && return 0
              set +e
              if [ "$backup_captured" -eq 1 ]; then
                systemctl stop proxybridge-testlab-endpoint.service >/dev/null 2>&1
                [ -e "$backup/unit" ] && cp -a "$backup/unit" "$unit" || rm -f "$unit"
                [ -e "$backup/rotation" ] && cp -a "$backup/rotation" "$rotation" || rm -f "$rotation"
                rm -f /opt/proxybridge-testlab/current
                [ -L "$backup/current" ] && cp -a "$backup/current" /opt/proxybridge-testlab/current
                if [ -d "$backup/version" ]; then rm -rf "$version"; cp -a "$backup/version" "$version"; elif [ "$version_created" -eq 1 ]; then rm -rf "$version"; fi
                systemctl daemon-reload >/dev/null 2>&1
                [ "$was_enabled" -eq 1 ] && systemctl enable proxybridge-testlab-endpoint.service >/dev/null 2>&1 || systemctl disable proxybridge-testlab-endpoint.service >/dev/null 2>&1
                [ "$was_active" -eq 1 ] && systemctl start proxybridge-testlab-endpoint.service >/dev/null 2>&1
              fi
              [ "$user_created" -eq 1 ] && userdel proxybridge-testlab >/dev/null 2>&1
              rm -f "$unit.new-$plan" "$rotation.new-$plan"
              rm -rf "$stage"
            }
            trap rollback EXIT
            trap 'exit 1' HUP INT TERM
            install -d -m 0700 "$stage" "$stage/runtime" "$backup"
            {{runtimeDecodeCommands}}
            printf '%s' '{{Convert.ToBase64String(artifacts.Unit)}}' | base64 -d > "$stage/proxybridge-testlab-endpoint.service"
            printf '%s' '{{Convert.ToBase64String(artifacts.Logrotate)}}' | base64 -d > "$stage/proxybridge-testlab"
            {{runtimeVerifyCommands}}
            [ "$(sha256sum "$stage/proxybridge-testlab-endpoint.service" | awk '{print $1}')" = '{{unitHash}}' ]
            [ "$(sha256sum "$stage/proxybridge-testlab" | awk '{print $1}')" = '{{logrotateHash}}' ]
            {{(installPython ? "export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get install -y python3" : ":")}}
            python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)'
            [ "$(python3 -B "$stage/runtime/pb_server_agent.py" --self-test --manifest "$stage/runtime/server-plugin-manifest.json")" = 'SERVER_AGENT_SELF_TEST_OK plugins={{artifacts.ImplementedPlugins.Count}}' ]
            [ "$(python3 -B "$stage/runtime/pb_protocol_server.py" --self-test --config "$stage/runtime/protocol-server-config.json")" = 'PROTOCOL_SERVER_SELF_TEST_OK services=29' ]
            if ! id -u proxybridge-testlab >/dev/null 2>&1; then useradd --system --home /nonexistent --shell /usr/sbin/nologin proxybridge-testlab; user_created=1; fi
            [ -e "$unit" ] && cp -a "$unit" "$backup/unit"
            [ -e "$rotation" ] && cp -a "$rotation" "$backup/rotation"
            [ -L /opt/proxybridge-testlab/current ] && cp -a /opt/proxybridge-testlab/current "$backup/current"
            [ -d "$version" ] && cp -a "$version" "$backup/version"
            backup_captured=1
            if [ -d "$version" ]; then rm -rf "$version"; install -d -m 0755 "$version"; else install -d -m 0755 "$version"; version_created=1; fi
            cp -a "$stage/runtime/." "$version/"
            find "$version" -type d -exec chmod 0755 {} +
            find "$version" -type f -exec chmod 0644 {} +
            chmod 0755 "$version/pb_net_endpoint.py" "$version/pb_server_agent.py" "$version/pb_protocol_server.py"
            chown proxybridge-testlab:proxybridge-testlab "$version/tls/server.key.pem"
            chmod 0600 "$version/tls/server.key.pem"
            install -d -o proxybridge-testlab -g proxybridge-testlab -m 0750 /var/log/proxybridge-testlab
            for log in server.jsonl protocols.jsonl; do
              [ -e "/var/log/proxybridge-testlab/$log" ] || : > "/var/log/proxybridge-testlab/$log"
              chown proxybridge-testlab:proxybridge-testlab "/var/log/proxybridge-testlab/$log"
              chmod 0640 "/var/log/proxybridge-testlab/$log"
            done
            ln -sfn "$version" /opt/proxybridge-testlab/current.new
            mv -Tf /opt/proxybridge-testlab/current.new /opt/proxybridge-testlab/current
            install -m 0644 "$stage/proxybridge-testlab-endpoint.service" "$unit.new-$plan"
            install -m 0644 "$stage/proxybridge-testlab" "$rotation.new-$plan"
            mv -f "$unit.new-$plan" "$unit"
            mv -f "$rotation.new-$plan" "$rotation"
            systemctl daemon-reload
            systemctl enable --now proxybridge-testlab-endpoint.service
            systemctl is-active --quiet proxybridge-testlab-endpoint.service
            success=1
            rm -rf "$stage"
            printf '%s\n' 'APPLY_OK=1' 'ROLLBACK_ATTEMPTED=0' 'ROLLBACK_OK=1'
            """;
        try
        {
            var values = await RunKeyValueScriptAsync(target, script, true, ApplyTimeout, cancellationToken);
            return new ServerApplyData(Flag(values, "APPLY_OK"), false, true, Flag(values, "APPLY_OK") ? "" : "SERVER_APPLY_FAILED");
        }
        catch (InvalidOperationException exception)
        {
            return new ServerApplyData(false, true, false, exception.Message.StartsWith("SSH_", StringComparison.Ordinal) ? exception.Message : "SERVER_APPLY_FAILED");
        }
    }

    public async Task<ServerVerificationData> VerifyAsync(ServerTarget target, ServerPortSet ports, CancellationToken cancellationToken)
    {
        ValidatePorts(ports);
        var tcpChecks = string.Join("\n", (ports.ListenerTcpPorts ?? ports.TcpPorts).Select(port => $"printf '%s\\n' \"$tcp\" | grep -Eq '[:.]{port}$' || listeners=0"));
        var udpChecks = string.Join("\n", (ports.ListenerUdpPorts ?? ports.UdpPorts).Select(port => $"printf '%s\\n' \"$udp\" | grep -Eq '[:.]{port}$' || listeners=0"));
        var script = $$"""
            set -u
            endpoint_hash=''; [ -r /opt/proxybridge-testlab/current/pb_net_endpoint.py ] && endpoint_hash="$(sha256sum /opt/proxybridge-testlab/current/pb_net_endpoint.py | awk '{print $1}')"
            unit_hash=''; [ -r /etc/systemd/system/proxybridge-testlab-endpoint.service ] && unit_hash="$(sha256sum /etc/systemd/system/proxybridge-testlab-endpoint.service | awk '{print $1}')"
            plugin_hash=''; [ -r /opt/proxybridge-testlab/current/server-plugin-manifest.json ] && plugin_hash="$(sha256sum /opt/proxybridge-testlab/current/server-plugin-manifest.json | awk '{print $1}')"
            plugin_selftest=0; plugin_count=0
            if [ -r /opt/proxybridge-testlab/current/pb_server_agent.py ] && [ -r /opt/proxybridge-testlab/current/server-plugin-manifest.json ]; then
              if [ "$(id -u)" = 0 ]; then
                plugin_output="$(runuser -u proxybridge-testlab -- python3 -B /opt/proxybridge-testlab/current/pb_server_agent.py --self-test --manifest /opt/proxybridge-testlab/current/server-plugin-manifest.json 2>/dev/null || true)"
              else
                plugin_output="$(sudo -n -u proxybridge-testlab python3 -B /opt/proxybridge-testlab/current/pb_server_agent.py --self-test --manifest /opt/proxybridge-testlab/current/server-plugin-manifest.json 2>/dev/null || true)"
              fi
              plugin_count="$(printf '%s\n' "$plugin_output" | sed -n 's/^SERVER_AGENT_SELF_TEST_OK plugins=\([0-9][0-9]*\)$/\1/p')"
              if [ -n "$plugin_count" ]; then plugin_selftest=1; else plugin_count=0; fi
            fi
            active=0; systemctl is-active --quiet proxybridge-testlab-endpoint.service && active=1
            enabled=0; systemctl is-enabled --quiet proxybridge-testlab-endpoint.service && enabled=1
            listeners=1
            if command -v ss >/dev/null 2>&1; then
              tcp="$(ss -H -lnt | awk '{print $4}')"; udp="$(ss -H -lnu | awk '{print $4}')"
              {{tcpChecks}}
              {{udpChecks}}
            else listeners=0; fi
            printf '%s\n' "ENDPOINT_SHA256=$endpoint_hash" "UNIT_SHA256=$unit_hash" "PLUGIN_MANIFEST_SHA256=$plugin_hash" "PLUGIN_SELFTEST=$plugin_selftest" "PLUGIN_COUNT=$plugin_count" "ACTIVE=$active" "ENABLED=$enabled" "LISTENERS=$listeners"
            """;
        try
        {
            var values = await RunKeyValueScriptAsync(target, script, false, CommandTimeout, cancellationToken);
            var active = Flag(values, "ACTIVE"); var enabled = Flag(values, "ENABLED"); var listeners = Flag(values, "LISTENERS");
            var pluginSelfTest = Flag(values, "PLUGIN_SELFTEST");
            var succeeded = active && enabled && listeners && pluginSelfTest;
            return new ServerVerificationData(succeeded, Get(values, "ENDPOINT_SHA256"), Get(values, "UNIT_SHA256"), Get(values, "PLUGIN_MANIFEST_SHA256"), pluginSelfTest, checked((int)Number(values, "PLUGIN_COUNT")), active, enabled, listeners, succeeded ? "" : "SERVER_VERIFICATION_FAILED");
        }
        catch (InvalidOperationException exception)
        {
            return new ServerVerificationData(false, "", "", "", false, 0, false, false, false, exception.Message);
        }
    }

    public async Task<ServerMetricsView> GetMetricsAsync(ServerTarget target, CancellationToken cancellationToken)
    {
        const string script = """
            set -u
            props="$(systemctl show proxybridge-testlab-endpoint.service -p ActiveState -p SubState -p MainPID -p NRestarts -p MemoryCurrent -p CPUUsageNSec 2>/dev/null || true)"
            printf '%s\n' "$props"
            evidence_bytes=0; evidence_records=0; endpoint_errors=0
            for log in /var/log/proxybridge-testlab/server.jsonl /var/log/proxybridge-testlab/protocols.jsonl; do
              if [ -r "$log" ]; then
                value="$(wc -c < "$log")"; evidence_bytes=$((evidence_bytes + value))
                value="$(wc -l < "$log")"; evidence_records=$((evidence_records + value))
                value="$(grep -c '"error":"[^" ]' "$log" 2>/dev/null || true)"; endpoint_errors=$((endpoint_errors + value))
              fi
            done
            disk_kb="$(df -Pk /var/log/proxybridge-testlab 2>/dev/null | awk 'NR==2 {print $4}' || true)"; [ -n "$disk_kb" ] || disk_kb=0
            printf '%s\n' "EVIDENCE_BYTES=$evidence_bytes" "EVIDENCE_RECORDS=$evidence_records" "ENDPOINT_ERRORS=$endpoint_errors" "DISK_KB=$disk_kb"
            journalctl -u proxybridge-testlab-endpoint.service --since '-5 minutes' -p warning --no-pager -n 10 -o cat 2>/dev/null | sed 's/^/LOG=/' || true
            """;
        var values = await RunKeyValueScriptAsync(target, script, false, CommandTimeout, cancellationToken, keepRepeatedLogKeys: true);
        var messages = values.Where(item => item.Key.StartsWith("LOG#", StringComparison.Ordinal)).Select(item => Redact(item.Value, target)).Take(10).ToArray();
        return new ServerMetricsView("COLLECTED", Get(values, "ActiveState"), Get(values, "SubState"), Number(values, "MainPID"), Number(values, "NRestarts"), Number(values, "MemoryCurrent"), Number(values, "CPUUsageNSec"), Number(values, "EVIDENCE_BYTES"), Number(values, "EVIDENCE_RECORDS"), Number(values, "ENDPOINT_ERRORS"), Number(values, "DISK_KB"), messages, DateTimeOffset.UtcNow);
    }

    private async Task<Dictionary<string, string>> RunKeyValueScriptAsync(ServerTarget target, string script, bool sudo, TimeSpan timeout, CancellationToken cancellationToken, bool keepRepeatedLogKeys = false)
    {
        ValidateTarget(target);
        if (!File.Exists(paths.KnownHostsPath)) throw new InvalidOperationException("SSH_HOST_NOT_TRUSTED");
        var args = BuildSshArguments(target);
        if (sudo && target.Username != "root") { args.Add("sudo"); args.Add("-n"); }
        if (target.Username == "root") script = "[ \"$(id -u)\" = 0 ] || exit 77\n" + script;
        args.Add("sh"); args.Add("-s");
        var normalizedScript = script.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
        var result = await RunProcessAsync(FindOpenSshTool("ssh.exe"), args, normalizedScript, timeout, cancellationToken);
        if (result.TimedOut) throw new InvalidOperationException("SSH_OPERATION_TIMEOUT");
        if (result.ExitCode != 0) throw new InvalidOperationException("SSH_OPERATION_FAILED");
        return ParseKeyValues(result.StandardOutput, keepRepeatedLogKeys);
    }

    private List<string> BuildSshArguments(ServerTarget target) =>
    [
        "-T", "-F", "NUL", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
        "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
        "-o", "StrictHostKeyChecking=yes", "-o", $"UserKnownHostsFile={paths.KnownHostsPath}",
        "-o", "GlobalKnownHostsFile=NUL", "-o", "ConnectTimeout=10",
        "-i", target.PrivateKeyPath, "-p", target.Port.ToString(CultureInfo.InvariantCulture),
        $"{target.Username}@{FormatHost(target.Host)}"
    ];

    private static async Task<ProcessResult> RunProcessAsync(string fileName, IReadOnlyList<string> arguments, string? standardInput, TimeSpan timeout, CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo(fileName) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = standardInput is not null, CreateNoWindow = true };
        foreach (var argument in arguments) startInfo.ArgumentList.Add(argument);
        using var process = new Process { StartInfo = startInfo };
        if (!process.Start()) throw new InvalidOperationException("SSH_PROCESS_START_FAILED");
        var stdout = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderr = process.StandardError.ReadToEndAsync(cancellationToken);
        if (standardInput is not null)
        {
            await process.StandardInput.WriteAsync(standardInput.AsMemory(), cancellationToken);
            process.StandardInput.Close();
        }
        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutCts.CancelAfter(timeout);
        var timedOut = false;
        try { await process.WaitForExitAsync(timeoutCts.Token); }
        catch (OperationCanceledException)
        {
            timedOut = !cancellationToken.IsCancellationRequested;
            try { process.Kill(true); } catch (InvalidOperationException) { }
            await process.WaitForExitAsync(CancellationToken.None);
            if (cancellationToken.IsCancellationRequested) throw;
        }
        var output = await stdout; _ = await stderr;
        return new ProcessResult(process.ExitCode, output, timedOut);
    }

    private static Dictionary<string, string> ParseKeyValues(string output, bool keepRepeatedLogKeys)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        var logIndex = 0;
        foreach (var line in output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            var separator = line.IndexOf('=');
            if (separator <= 0) continue;
            var key = line[..separator]; var value = line[(separator + 1)..];
            if (!KeyRegex().IsMatch(key) || value.Any(character => character is '\0' or '\r' or '\n')) continue;
            if (keepRepeatedLogKeys && key == "LOG") key = $"LOG#{logIndex++}";
            values[key] = value;
        }
        return values;
    }

    private static string NormalizeKnownHostLine(string line, ServerTarget target)
    {
        var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 3 || !KnownHostAlgorithmRegex().IsMatch(parts[1])) throw new InvalidOperationException("SSH_HOST_KEY_FORMAT_INVALID");
        var expectedHost = target.Port == 22 ? target.Host : $"[{target.Host}]:{target.Port}";
        if (!string.Equals(parts[0], expectedHost, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("SSH_HOST_KEY_TARGET_MISMATCH");
        try { _ = Convert.FromBase64String(parts[2]); } catch (FormatException) { throw new InvalidOperationException("SSH_HOST_KEY_FORMAT_INVALID"); }
        return string.Join(' ', parts);
    }

    private static string ComputeFingerprint(string line)
    {
        var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var digest = SHA256.HashData(Convert.FromBase64String(parts[2]));
        return $"{parts[1]} SHA256:{Convert.ToBase64String(digest).TrimEnd('=')}";
    }

    private static string FindOpenSshTool(string name)
    {
        var system = Environment.GetFolderPath(Environment.SpecialFolder.System);
        var candidate = Path.Combine(system, "OpenSSH", name);
        return File.Exists(candidate) ? candidate : throw new InvalidOperationException("WINDOWS_OPENSSH_NOT_INSTALLED");
    }

    private static void ValidateTarget(ServerTarget target)
    {
        if (string.IsNullOrWhiteSpace(target.Host) || target.Host.Any(char.IsWhiteSpace) || target.Host.StartsWith('-')) throw new InvalidOperationException("SSH_HOST_INVALID");
        if (!IPAddress.TryParse(target.Host, out _) && (Uri.CheckHostName(target.Host) != UriHostNameType.Dns || !DnsNameRegex().IsMatch(target.Host))) throw new InvalidOperationException("SSH_HOST_INVALID");
        ValidatePort(target.Port);
        if (!UserRegex().IsMatch(target.Username)) throw new InvalidOperationException("SSH_USER_INVALID");
        if (!Path.IsPathFullyQualified(target.PrivateKeyPath) || !File.Exists(target.PrivateKeyPath)) throw new InvalidOperationException("SSH_PRIVATE_KEY_NOT_FOUND");
    }

    private static void ValidatePort(int port) { if (port is < 1 or > 65535) throw new InvalidOperationException("SERVER_PORT_INVALID"); }
    private static void ValidatePorts(ServerPortSet ports)
    {
        if (ports.TcpPorts.Count == 0 || ports.UdpPorts.Count == 0) throw new InvalidOperationException("SERVER_PORT_SET_EMPTY");
        foreach (var port in ports.TcpPorts.Concat(ports.UdpPorts)) ValidatePort(port);
        if (ports.TcpPorts.Distinct().Count() != ports.TcpPorts.Count || ports.UdpPorts.Distinct().Count() != ports.UdpPorts.Count)
            throw new InvalidOperationException("SERVER_PORT_SET_DUPLICATE");
        if (ports.ListenerTcpPorts?.Any(port => !ports.TcpPorts.Contains(port)) == true ||
            ports.ListenerUdpPorts?.Any(port => !ports.UdpPorts.Contains(port)) == true)
            throw new InvalidOperationException("SERVER_LISTENER_OUTSIDE_RESERVED_PORTS");
    }
    private static IReadOnlyList<int> ParsePortList(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return [];
        var result = new List<int>();
        foreach (var item in value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!int.TryParse(item, NumberStyles.None, CultureInfo.InvariantCulture, out var port)) throw new InvalidOperationException("SERVER_PORT_CONFLICT_RESULT_INVALID");
            ValidatePort(port);
            result.Add(port);
        }
        return result.Distinct().Order().ToArray();
    }
    private static string FormatHost(string host) => IPAddress.TryParse(host, out var address) && address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6 ? $"[{host}]" : host;
    private static string Get(IReadOnlyDictionary<string, string> values, string key) => values.TryGetValue(key, out var value) ? value : "";
    private static bool Flag(IReadOnlyDictionary<string, string> values, string key) => Get(values, key) == "1";
    private static long Number(IReadOnlyDictionary<string, string> values, string key) => long.TryParse(Get(values, key), NumberStyles.None, CultureInfo.InvariantCulture, out var value) ? value : 0;
    private static string Redact(string value, ServerTarget target)
    {
        var redacted = value.Replace(target.Host, "[host]", StringComparison.OrdinalIgnoreCase)
            .Replace(target.Username, "[user]", StringComparison.OrdinalIgnoreCase)
            .Replace(target.PrivateKeyPath, "[path]", StringComparison.OrdinalIgnoreCase);
        redacted = SensitiveAssignmentRegex().Replace(redacted, "$1=[redacted]");
        return IpRegex().Replace(PathRegex().Replace(redacted, "[path]"), "[address]");
    }

    private sealed record ProcessResult(int ExitCode, string StandardOutput, bool TimedOut);
    [GeneratedRegex("^[A-Z][A-Z0-9_]*$")] private static partial Regex KeyRegex();
    [GeneratedRegex("^(ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|ssh-rsa)$")] private static partial Regex KnownHostAlgorithmRegex();
    [GeneratedRegex("^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$")] private static partial Regex DnsNameRegex();
    [GeneratedRegex("^[A-Za-z_][A-Za-z0-9_.-]{0,63}$")] private static partial Regex UserRegex();
    [GeneratedRegex("^[a-f0-9]{32}$")] private static partial Regex PlanIdRegex();
    [GeneratedRegex(@"(?<![A-Za-z0-9])(?:\d{1,3}\.){3}\d{1,3}(?![A-Za-z0-9])|(?<![A-Za-z0-9])[A-Fa-f0-9:]{3,}(?![A-Za-z0-9])")] private static partial Regex IpRegex();
    [GeneratedRegex(@"(?:/[A-Za-z0-9_.-]+){2,}")] private static partial Regex PathRegex();
    [GeneratedRegex(@"(?i)\b(password|username|secret|token|credential|ssh_key|key_path)\s*=\s*[^\s]+")]
    private static partial Regex SensitiveAssignmentRegex();
}
