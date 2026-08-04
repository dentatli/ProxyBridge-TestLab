# End-to-end environment setup

This guide deploys the complete ProxyBridge-TestLab topology:

```text
Windows test VM
  pb_net_client.exe
        |
        v
  ProxyBridge WFP beta
     |          |
   DIRECT     SOCKS5
     |          |
     +------> Linux VPS deterministic endpoint
                    TCP/UDP :41001 and :41002
```

The repository does not include ProxyBridge product binaries, proxy credentials,
SSH keys, or runtime evidence. Supply those locally and keep them outside Git.

## 1. Safety requirements

Use an isolated Windows VM or a dedicated test host. Real suites may start and
stop verified ProxyBridge processes, load generated profiles, and generate TCP
and UDP traffic. Do not run driver, destructive lifecycle, or routing tests on a
production workstation.

Before every real run:

- verify the exact ProxyBridge, CLI, driver and test-client SHA-256 values;
- verify that `.env` is ignored by Git;
- verify the VPS endpoint and SOCKS5 backend independently;
- preserve the resulting evidence directory before changing the environment.

## 2. Build the Windows deterministic client

Requirements:

- Windows 10 or Windows 11 x64;
- Windows PowerShell 5.1 or PowerShell 7;
- either an x64 MSVC command prompt with `cl.exe`, or MinGW-w64 `gcc.exe`;
- the Windows SDK/Winsock libraries supplied by the selected toolchain.

From the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\scripts\Build-Harness.ps1'
```

When the compiler is not in `PATH`, pass it explicitly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\scripts\Build-Harness.ps1' `
    -CompilerPath 'C:\msys64\ucrt64\bin\gcc.exe'
```

The build script rejects non-x64 output. The resulting file is:

```text
bin\pb_net_client.exe
```

Record its exact hash:

```powershell
Get-FileHash '.\bin\pb_net_client.exe' -Algorithm SHA256
```

The executable is intentionally not committed. Different compilers may produce
valid binaries with different hashes; configure the hash of the binary actually
used for the run.

## 3. Deploy the deterministic endpoint on Linux

### 3.1 Requirements

- Debian or Ubuntu VPS;
- Python 3.10 or newer;
- public IPv4 for IPv4 testing;
- optional public IPv6 and route for IPv6 testing;
- inbound TCP and UDP access to ports `41001` and `41002`;
- SSH access from the Windows test host for evidence collection.

The endpoint is an unauthenticated echo service. Restrict firewall access to the
known DIRECT and proxy egress addresses whenever possible, and remove the rules
when testing is complete.

### 3.2 Install the repository and service account

After the repository is public, or with authenticated Git access:

```bash
sudo useradd --system --home /nonexistent --shell /usr/sbin/nologin proxybridge-testlab || true
sudo git clone https://github.com/dentatli/ProxyBridge-TestLab.git /opt/ProxyBridge-TestLab
sudo install -d -o proxybridge-testlab -g proxybridge-testlab /var/log/proxybridge-testlab
```

For an existing checkout:

```bash
cd /opt/ProxyBridge-TestLab
sudo git pull --ff-only
```

### 3.3 Manual endpoint launch

IPv4 public, IPv6 loopback only:

```bash
sudo -u proxybridge-testlab python3 /opt/ProxyBridge-TestLab/src/pb_net_endpoint.py \
  --jsonl-log /var/log/proxybridge-testlab/server.jsonl \
  --bind-ipv4 0.0.0.0 \
  --endpoint-a-port 41001 \
  --endpoint-b-port 41002
```

For public IPv4 and IPv6 add:

```text
--bind-ipv6 ::
```

Expected startup output:

```text
READY 8 listeners A=41001 B=41002
```

The endpoint creates TCP and UDP listeners for both endpoint ports and writes
one JSON object per line. Important events are:

```text
LISTENING
ACCEPTED
MESSAGE_RECEIVED
RECEIVED
ECHOED
CLOSED
SERVER_ERROR
```

TCP messages are newline-delimited. `pb_net_client.exe` already uses the required
framing.

### 3.4 systemd deployment

Install the example unit:

```bash
sudo cp /opt/ProxyBridge-TestLab/deploy/proxybridge-testlab-endpoint.service.example \
  /etc/systemd/system/proxybridge-testlab-endpoint.service
sudo systemctl daemon-reload
sudo systemctl enable --now proxybridge-testlab-endpoint.service
```

For public IPv6, edit the unit and add `--bind-ipv6 ::` to `ExecStart`.

Verify:

```bash
sudo systemctl status proxybridge-testlab-endpoint.service --no-pager
sudo journalctl -u proxybridge-testlab-endpoint.service -n 100 --no-pager
sudo ss -lntup | grep -E ':(41001|41002)\b'
tail -f /var/log/proxybridge-testlab/server.jsonl
```

### 3.5 Firewall

Preferred: permit only the expected DIRECT and proxy egress IPs.

```bash
sudo ufw allow from <DIRECT_EGRESS_IPV4> to any port 41001 proto tcp
sudo ufw allow from <DIRECT_EGRESS_IPV4> to any port 41002 proto tcp
sudo ufw allow from <DIRECT_EGRESS_IPV4> to any port 41001 proto udp
sudo ufw allow from <DIRECT_EGRESS_IPV4> to any port 41002 proto udp

sudo ufw allow from <PROXY_EGRESS_IPV4> to any port 41001 proto tcp
sudo ufw allow from <PROXY_EGRESS_IPV4> to any port 41002 proto tcp
sudo ufw allow from <PROXY_EGRESS_IPV4> to any port 41001 proto udp
sudo ufw allow from <PROXY_EGRESS_IPV4> to any port 41002 proto udp
```

Temporary unrestricted rules are simpler but less safe:

```bash
sudo ufw allow 41001:41002/tcp
sudo ufw allow 41001:41002/udp
```

## 4. Configure the Windows tester

Create the local environment file:

```powershell
Copy-Item '.\.env.example' '.\.env'
notepad '.\.env'
```

Required groups:

```text
PB_VM_IPV4 / optional PB_VM_IPV6
PB_VPS_IPV4 / optional PB_VPS_IPV6
PB_ENDPOINT_A_PORT / PB_ENDPOINT_B_PORT
PB_SOCKS_HOST / PB_SOCKS_PORT / PB_SOCKS_PROXY_CONFIG_ID
PB_CLIENT_EXE
PB_PROXYBRIDGE_EXE
PB_PROXYBRIDGE_CLI_EXE
PB_DRIVER_PATH
PB_PROXYBRIDGE_SERVICE
PB_EVIDENCE_ROOT
expected SHA-256 values for client, CLI, GUI and driver
PB_SSH_HOST / PB_SSH_USER / PB_SSH_PORT / PB_SSH_KEY
PB_VPS_SERVER_LOG
```

Use absolute Windows paths. The VPS log path must match the endpoint's
`--jsonl-log` argument.

Verify local hashes:

```powershell
Get-FileHash $env:PB_CLIENT_EXE -Algorithm SHA256
Get-FileHash $env:PB_PROXYBRIDGE_CLI_EXE -Algorithm SHA256
Get-FileHash $env:PB_PROXYBRIDGE_EXE -Algorithm SHA256
Get-FileHash $env:PB_DRIVER_PATH -Algorithm SHA256
```

When using a `.env` file rather than PowerShell environment variables, run the
same commands with the literal configured paths.

Verify that secrets are ignored:

```powershell
git check-ignore -v .env
```

## 5. Configure capabilities

Edit:

```text
config/capabilities.json
```

Disable unavailable functionality instead of treating it as a failure:

```json
{
  "capabilities": {
    "ipv4": { "enabled": true, "reason": "" },
    "ipv6": { "enabled": false, "reason": "No native public IPv6 route" }
  }
}
```

To enable IPv6, all of the following must be true:

- the Windows host or VM has a usable global IPv6 address and default route;
- the VPS endpoint is bound to `::` and reachable on TCP/UDP ports 41001/41002;
- the firewall permits the relevant IPv6 sources;
- `PB_VM_IPV6` and `PB_VPS_IPV6` are configured;
- the SOCKS5 path supports the required IPv6 traffic.

Setting `ipv6.enabled=true` only enables scenario selection. It does not create
IPv6 connectivity. The current published validation results did not evaluate
IPv6, so treat IPv6 execution as experimental until independently verified.

## 6. Validate the TestLab without product runtime

Run the dependency-free tests:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\tests\Run-All.ps1'
```

Dry-run catalog and profile generation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\scripts\Invoke-DryRun.ps1' `
    -FixtureMode
```

Fixture-backed mock matrix:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\scripts\Invoke-MockMatrix.ps1' `
    -FixtureMode
```

Mock results validate TestLab behavior. They are not product test results.

## 7. Run a single real smoke test

The smoke entrypoint executes one deterministic issue #206 scenario and requires
an explicit confirmation switch:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\scripts\Invoke-RealSmoke.ps1' `
    -ConfirmRealRuntime
```

Expected high-level output:

```text
ENVIRONMENT_PREPARED status=PASS_PREPARED run_id=<id>
RUN_COMPLETE mode=real run_id=<id> ...
EVIDENCE_PATH=<path>
REAL_SMOKE_RESULT=PASS ...
```

Do not proceed to a full matrix when the smoke test reports an infrastructure,
harness, ambiguous, or contaminated-state failure.

## 8. Run the real IPv4 diagnostic sweep

This suite continues after scenario-local product, harness and infrastructure
results so that one run can report the full current executable subset. It still
stops on contaminated state.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\Run-WfpMatrix.ps1' `
    -EnvPath '.\.env' `
    -CapabilitiesPath '.\config\capabilities.json' `
    -SuitePath '.\config\suites\real-diagnostic-ipv4.json' `
    -KnownDefectsPath '.\config\known-defects.json' `
    -ClientContractPath '.\config\client-contract.json' `
    -RuntimeConfigPath '.\config\runtime.json' `
    -ScenarioRoot '.\scenarios' `
    -OutputRoot '.\evidence\real-diagnostic-ipv4' `
    -AllowProductRuntime `
    -PrepareRuntimeEnvironment `
    -ContinueOnProductFailure
```

The suite currently selects the implemented synthetic IPv4 correctness subset.
The 135-ID catalog also contains declarative future coverage, IPv6 scenarios,
application canaries, performance plans, and unsupported protocol boundaries.

## 9. Read results

Use the newest run directory without copying the run ID manually:

```powershell
$Run = Get-ChildItem '.\evidence\real-diagnostic-ipv4' -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName

Import-Csv "$Run\summary.csv" |
    Group-Object status |
    Sort-Object Name |
    Select-Object Name,Count |
    Format-Table -AutoSize

Import-Csv "$Run\summary.csv" |
    Where-Object {
        $_.status -notin @(
            'SKIPPED_SELECTION',
            'SKIPPED_CAPABILITY',
            'NOT_IMPLEMENTED',
            'UNSUPPORTED_PRODUCT_SCOPE'
        )
    } |
    Select-Object scenario_id,status,attempt,duration_ms |
    Format-Table -AutoSize
```

Interpretation:

- `PASS` — the tested product behavior matched the external evidence;
- `FAIL_PRODUCT` — a product behavior failed without a harness failure;
- `EXPECTED_FAIL` — a known defect was reproduced with its declared signature;
- `FAIL_HARNESS` / `FAIL_INFRASTRUCTURE` — no reliable product verdict;
- `CONTAMINATED` — stop; later results would not be trustworthy;
- `NOT_IMPLEMENTED` — catalog coverage exists but no executable client contract yet;
- `SKIPPED_CAPABILITY` — the environment cannot run the scenario.

`RUN_COMPLETE` means that reports and checksums were written. Use
`summary.json` and `summary.csv` to determine whether execution was complete and
to read the product verdict.

## 10. Evidence handling

Each run creates a separate directory containing client records, profiles,
ProxyBridge evidence, exact VPS payload matches, assertions, summaries, a
transcript, and `SHA256SUMS`.

Do not publish raw evidence without reviewing it. Evidence may contain public or
private IP addresses, local paths, usernames, process names, and endpoint data.
Use only redacted summaries in public issues unless the developer explicitly
requests a private evidence archive.
