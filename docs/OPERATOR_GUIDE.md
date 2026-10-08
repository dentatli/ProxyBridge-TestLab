# ProxyBridge TestLab operator guide

Current application workflow, 2026-10-08. The default page is the bilingual
laboratory; the retired technical dashboard is no longer shipped.

## Supported scope

- Windows x64 test machine; product/driver installed and managed separately.
- Current GUI runtime: the known driver kit at its original checkout-bound path.
- Selected tests: TCP RTT, combined upload/download, separate three-mode RTT,
  and TCP connection load/recovery. Evidence and cleanup checks remain mandatory.
- Unknown/relocated kits and 4.0.0 need further runtime-adapter integration.
- The remote wizard targets Ubuntu Server 22.04/24.04/26.04 LTS; remote GUI
  execution remains blocked until platform, components and route are verified.

## Start and choose a run

For a source checkout, follow [UI startup instructions](../ui/README.md).
For a published package, use `packaging\Start-ProxyBridge-TestLab.ps1`.
Open `http://127.0.0.1:5178/`. Real GUI execution requires an administrator UI.
Starting the UI does not install a driver or configure the system proxy.

1. **Builds:** select the product files, inspect them and save the build under
   a user name. A successful files-only inspection is not runtime readiness.
2. **Testing:** choose tests and set their individual duration/load. Use a
   saved named suite to repeat the same choices on another build.
3. **Run:** prepare a fresh plan, review build/tests/conditions/estimated time,
   then explicitly start it. A blocker must be resolved, not bypassed.
4. **Stop:** request stop after the current run, then wait for verification
   and cleanup. Navigation and refresh do not stop a running job.
5. **Results:** inspect Comparison and History. Errors, cancellations and
   incomplete evidence remain visible. A failed latest attempt is not replaced
   by an older successful result.

CPU/private RAM refer to the sampled CLI process, not the driver. Connection
counts do not establish internal-table overflow or maximum capacity. Data-only
transfer profiles do not prove normal TCP close. Conditions keys do not prove
full comparability of hardware and background activity.

## Validation

Source build and UI checks do not establish product/runtime correctness.
Use [the functional inventory](DEVELOPMENT_FUNCTIONAL_STATUS.md) for the current
verification boundary and [development handoff](CHAT_HANDOFF_DEVELOPMENT.md)
for remaining work. Product/traffic checks on the shared VM must be coordinated
with diagnostic work. Do not start them while debugger points or diagnostic
workloads are active; heavy/long runs require their own authorization.

## Stop, repair and remove local data

- Stop this package instance with `packaging\Stop-ProxyBridge-TestLab.ps1`.
- Verify package integrity with `packaging\Repair-ProxyBridge-TestLab.ps1`.
- Add `-RepairDataAcl` only to restore the current-user and SYSTEM ACL on the
  default data directory.
- `packaging\Uninstall-ProxyBridge-TestLabData.ps1 -ConfirmRemoval` irreversibly
  removes the current user's saved settings, protected secrets, jobs and local
  evidence after stopping this exact package instance. UI source cleanup does
  not run this command or delete that data.

Shared settings, SSH trust/provisioning, catalog and safety APIs remain available
for development and existing probes; their prior technical dashboard has been
removed. The future Ubuntu wizard will provide the remote user workflow without
weakening host-key, data/route, readiness and cleanup gates.
