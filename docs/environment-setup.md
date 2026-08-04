# Environment setup

## Overview

ProxyBridge-TestLab uses a Windows test machine, ProxyBridge, a deterministic
network client, and an external echo endpoint.

A typical topology is:

```text
pb_net_client.exe
        |
        v
ProxyBridge WFP
   |          |
DIRECT      SOCKS5
   |          |
   +---- external test endpoint
```

## Windows test machine

Recommended requirements:

- Windows 10 or Windows 11 x64;
- administrator privileges;
- isolated VM or dedicated test host;
- ProxyBridge-compatible WFP driver environment;
- Test Signing when required by the tested driver;
- Windows PowerShell 5.1 minimum;
- PowerShell 7 recommended;
- OpenSSH client for VPS evidence collection.

The environment must not be assumed to provide IPv6. Configure unavailable
features in `config/capabilities.json`.

## ProxyBridge

Required components may include:

```text
ProxyBridge.exe
ProxyBridge_CLI.exe
ProxyBridgeCore.dll
ProxyBridgeDrv.sys
```

Record separate expected SHA-256 values for the client,
`ProxyBridge_CLI.exe`, optional GUI executable, and optional driver in the
local `.env`. Never reuse the GUI hash as the CLI hash.

Do not use an installer, driver or temporary signing script unless the exact
test stage explicitly requires it.

## Profile execution

ProxyBridge CLI supports headless profile execution:

```powershell
ProxyBridge_CLI.exe --profile <path> --verbose 3
```

Generated profiles may contain environment-specific addresses or credentials
and must remain outside Git.

## External endpoint

The external endpoint should provide deterministic TCP and UDP echo listeners.

Recommended listener groups:

```text
TCP IPv4
UDP IPv4
TCP IPv6
UDP IPv6
```

Use separate ports for scenarios that require independent destinations.

The endpoint JSONL must expose these actual fields:

```text
event
sha256
local_ip
local_port
remote_ip
remote_port
bytes
error
```

The endpoint emits `MESSAGE_RECEIVED` for TCP, `RECEIVED` for UDP and
`ECHOED` after a response is sent. Real smoke uses the configured OpenSSH
client to query `${PB_VPS_SERVER_LOG}` once for every canonical client payload
SHA. `PB_VPS_EVIDENCE_IMPORT` is optional and used only by an explicitly
selected manual/import audit mode.

## SOCKS5 backend

The SOCKS5 backend must be independently health-checked before PROXY scenarios.

Record:

```text
host
port
authentication mode
expected public egress IP where stable
```

Do not store credentials in committed files.

## Local environment file

Create the local configuration:

```powershell
Copy-Item .env.example .env
notepad .env
```

Replace all documentation addresses and placeholder hashes.

Verify that Git ignores it:

```powershell
git check-ignore -v .env
```

## Capability configuration

Disable unavailable functions instead of allowing false failures.

Example:

```json
{
  "capabilities": {
    "ipv4": {
      "enabled": true,
      "reason": ""
    },
    "ipv6": {
      "enabled": false,
      "reason": "No usable IPv6 route"
    }
  }
}
```

## Runtime evidence

Each test run should use a unique evidence directory:

```text
evidence/<suite-id>/<run-id>/
```

A complete run should eventually contain:

```text
environment-snapshot.json
resolved-suite.json
resolved profiles
client JSONL
ProxyBridge log slice
VPS log matches
results.jsonl
summary.csv
coverage.json
transcript.txt
SHA256SUMS
```

## Safety boundary

Do not perform driver restart, uninstall, VM reboot, packet-loss injection or
snapshot restoration unless the selected suite explicitly declares the action
and the environment capability permits it.

Dry-run and mock validation must use `-FixtureMode`; this prevents accidental
use of the private `.env`. Real runtime requires the separate
`scripts/Invoke-RealSmoke.ps1 -ConfirmRealRuntime` entrypoint and must not be
combined with firewall, driver/service, installer or signing changes.
