# Milestone 8 report

Status: complete - offline release candidate produced  
Effort: Very High

## Outcome

The final local release candidate is available as a self-contained Windows x64
package. It contains the loopback UI/controller, public TestLab runtime files,
server provisioning and recovery scripts, documentation and the compiled x64
`pb_net_client.exe` required for real-run readiness.

- Version: `0.2.0-rc2`
- Directory: `artifacts/releases/ProxyBridge-TestLab-0.2.0-rc2-win-x64`
- ZIP: `artifacts/releases/ProxyBridge-TestLab-0.2.0-rc2-win-x64.zip`
- ZIP SHA-256:
  `D2EFBEAA4FC7AEA0C8E54B56653907B89ADD0C002CE25958FDA6A28D8790C880`
- Packaged files verified: 550
- Bundled client ready: yes

The publisher used an explicit public allowlist and did not include `.env`,
credentials, generated profiles, evidence, `.git` or ProxyBridge product
binaries. Every packaged file was verified against `SHA256SUMS.txt`; required
controller, client, manifest, version and checksum files were present.
The earlier `0.2.0-rc1` artifact is superseded because it was created before
the final completion documents were synchronized; it is not the release
candidate named by this report.

## Safety and readiness boundary

The controller remains loopback-only. A real run stays disabled until the UI
configuration, exact local artifacts, trusted SSH host, supported
Debian/Ubuntu systemd endpoint, signed readiness receipt, server channels and
selected capabilities pass the bounded readiness gates. Users do not edit
`.env`; the controller owns any private compatibility input and removes it.

The real-run adapter uses the existing fail-closed runner contracts. A local
product outcome does not stop unrelated later scenarios after cleanup and a
healthy-state proof. Contamination, failed cleanup, binary drift or an
unhealthy shared service still causes a safety stop.

## Offline verification

- `tests/Run-All.ps1`: PASS, 21/21 targeted test groups.
- Release publish: PASS, self-contained win-x64 controller and client included.
- Package allowlist and required-file inspection: PASS.
- Complete internal SHA-256 inventory verification: PASS.
- No ProxyBridge, driver, compiled client process, SSH, endpoint service or
  network traffic was started.
- Manual UI and real-runtime validation remain deferred to the user's VM.
- Commit and push were not performed.
