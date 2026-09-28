# Milestone 3 report

Status: Complete  
Reasoning effort: Very High, because this milestone introduces SSH host trust,
remote privilege use, rollback and a server-readiness security boundary.

## Delivered

- English Server Setup workflow for Debian or Ubuntu with systemd.
- Private-key-only Windows OpenSSH invocation with password, interactive login
  and user SSH configuration disabled.
- Explicit first-use host fingerprint trust and fail-closed changed-key
  replacement confirmation.
- Read-only discovery of OS, PID 1, architecture, `sudo -n`, Python, disk,
  existing service state, direct NAT egress and external firewall ownership.
- Exact ten-minute plan with packages, managed paths, ports, artifact integrity,
  fixed command, transitions and rollback descriptions.
- Idempotent versioned endpoint installation under a dedicated unprivileged
  account, atomically activated systemd unit, protected JSONL evidence and log
  rotation.
- Service-owned network source restrictions for loopback, observed direct
  egress and a configured proxy-host IP; unrelated host firewall policy is not
  modified.
- Post-apply verification of artifacts, enabled/active systemd state and TCP
  and UDP listeners on both endpoint ports.
- DPAPI-backed HMAC signing key and a fail-closed 24-hour readiness receipt.
- Read-only CPU, memory, restart, disk, evidence and sanitized recent-log
  metrics over SSH after `READY`.
- No server operation is started by page load; every SSH or mutation step needs
  an explicit UI action.

## Configuration simplification

- Manual SHA-256 fields were removed from Environment Setup. Integrity values
  are calculated internally from the exact selected files.
- `Client executable path` was removed. TestLab uses
  `bin\pb_net_client.exe` relative to the repository.
- Standard ProxyBridge, driver, evidence and optional default SSH-key paths are
  preconfigured.
- A literal SSH server IP is reused as the endpoint IP when no override exists.
- SSH user is stored as a normal public setting and no longer displays a
  saved-secret removal checkbox.

## Offline verification

- Release build: PASS, 0 warnings, 0 errors.
- PowerShell and JavaScript syntax: PASS.
- `tests\Test-ServerProvisioning.ps1`: PASS.
- The fake transport covers trust-before-discovery, invalid trust token,
  changed-key replacement, unsupported OS, exact plan confirmation, automatic
  client path and hashes, source-scoped unit generation, signed receipt tamper
  rejection, apply failure rollback reporting and metrics.

## Safety boundary

No ProxyBridge executable, traffic client, real SSH connection, remote command
or network test was started during implementation or verification. Run
mutations remain absent. No commit or push was performed.

## Next milestone

Milestone 4 implements one-active-run orchestration, fixture execution, guarded
real-run preparation, progress, cancellation and bounded recovery. Recommended
effort: Very High; use Max only for a concrete unresolved lifecycle race.
