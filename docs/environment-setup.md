# Environment setup

> Target workflow updated 2026-10-07: the new lab UI will generate an SSH key, show its public key for root authorized_keys, and offer IP/optional port plus **Automatic setup** or **Check connection**. Production support is limited to recent Ubuntu; the release allowlist remains to be defined. See [REMOTE_UBUNTU_SETUP_PLAN.md](REMOTE_UBUNTU_SETUP_PLAN.md). The Debian/Ubuntu and manual plan/apply flow below describes the existing technical interface. Remote tests remain blocked in the new UI until controllers and readiness checks are integrated.

ProxyBridge-TestLab configuration is managed only through the local English web
UI. Do not create or edit a repository `.env` file and do not copy credentials,
addresses or private paths into public configuration files.

## 1. Start the local UI

Requirements:

- Windows 10 or Windows 11 x64;
- .NET 10 SDK or the future self-contained application package;
- an isolated VM or dedicated test host for real WFP execution.

From the repository root:

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' run `
    --project '.\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj'
```

Open `http://127.0.0.1:5178` and select `Environment Setup`. The controller
listens on loopback only and rejects unexpected host names and cross-origin
mutation requests.

## 2. Configure the Windows environment

The UI divides settings into these sections:

- `ProxyBridge`: GUI, CLI and driver paths plus the service name. Standard
  installation paths are preconfigured and binary integrity values are
  calculated internally;
- the deterministic traffic client is discovered automatically at
  `bin\pb_net_client.exe` and is not a user setting;
- `SOCKS proxy`: endpoint and existing ProxyBridge proxy configuration ID;
- `SSH connection`: server host, port, user and private-key path;
- `Traffic endpoint`: Windows/server addresses, evidence path and ports;
- `Capabilities`: protocol and address-family availability;
- `Timeouts`: bounded client and process lifecycle budgets;
- `Evidence retention`: private local evidence location and retention limits.

Sensitive values are write-only in the UI. After saving, the interface reports
only `SAVED` or `MISSING`; it never returns the value. Replacing a value requires
typing a new one. Removing it requires selecting the explicit clear action.

## 3. Storage and validation

Non-secret settings are stored under:

```text
%LOCALAPPDATA%\ProxyBridge-TestLab\config\settings.json
```

Sensitive paths and host/IP values are stored in:

```text
%LOCALAPPDATA%\ProxyBridge-TestLab\config\secrets.dpapi
```

`secrets.dpapi` contains a DPAPI CurrentUser ciphertext envelope. It can be
decrypted only in the same Windows user context. Neither file belongs in Git.
The SSH user is a normal non-secret setting, so it has no saved-secret removal
checkbox.

The UI separates two outcomes:

- `valid for save`: values are syntactically safe and may be stored;
- `configuration ready`: every required value and local file prerequisite is
  present.

Incomplete but syntactically valid settings may be saved. They never unlock a
real run.

## 4. Internal runner compatibility

The existing PowerShell runner consumes a flat environment input. The local
controller maps typed UI settings to those internal keys only when an authorized
run is created.

The generated `runtime\<run-id>\input.env` file:

- is ACL-restricted to the current user and LocalSystem;
- uses UTF-8 without BOM;
- is never displayed or returned by the API;
- is never included in reports or exports;
- is covered by an exclusive cleanup lease and removed after use;
- is scavenged on the next controller start after an interrupted process;
- is not the persistent source of configuration.

## 5. Server setup

`Server Setup` supports Debian and Ubuntu with systemd only. Authentication is
private-key-only; password and keyboard-interactive SSH are disabled.

Server actions are never started merely by opening the page. The operator must:

1. select `Validate connection` for read-only host-key and platform discovery;
2. independently compare and explicitly trust the displayed host fingerprint;
3. create and review an unexpired plan containing packages, managed paths,
   ports, integrity records, fixed command and rollback operations;
4. explicitly confirm and apply that exact plan;
5. wait for post-apply artifact, systemd and TCP/UDP listener verification.

The installer uses a dedicated unprivileged account, versioned endpoint files,
an atomically activated systemd unit, a protected evidence directory and log
rotation. Its unit denies unlisted network sources and permits the observed
SSH-client egress plus a configured proxy-host IP. TestLab never replaces the
host firewall policy or removes unrelated packages, units, accounts or rules.

A signed local readiness receipt expires after 24 hours. Restarting the
controller or changing host trust requires validation again. Metrics are read
over SSH only after the endpoint reaches `READY` and recent messages are
redacted before display.

The Windows tester may be behind NAT because it initiates outbound traffic. The
Linux endpoint must have a public/routable address, port forwarding, or a
supported overlay/VPN path. Proxy egress is a separate per-run readiness
gate and is never inferred from the direct SSH source.

## 6. Offline validation

Run dependency-free repository tests without product or network runtime:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\tests\Run-All.ps1'
```

Fixture and mock results validate TestLab behavior. They are not ProxyBridge
product results.

## 7. Real execution status

Real execution is fail-closed. Server readiness is necessary but not sufficient:
the controller must run a bounded immutable preflight and issue a signed
two-minute receipt for the exact selection and private input. The preflight
covers immutable local binary checks, endpoint verification, proxy-backend
readiness, direct-baseline requirements and a clean shared product state. The
receipt is reviewed first and is not silently regenerated when the run is
queued.

There is no `continue anyway` control for contamination, unknown rule state,
hash drift or failed cleanup.
