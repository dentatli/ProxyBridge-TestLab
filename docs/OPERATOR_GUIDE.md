# ProxyBridge TestLab operator guide

## Supported environment

- Windows x64 test machine.
- ProxyBridge product and driver installed separately on the Windows machine.
- Debian or Ubuntu server using systemd.
- SSH private-key authentication. SSH passwords are not supported.
- The Windows machine may be behind NAT; it only needs outbound connectivity.
  The server still needs a public, forwarded or overlay-routable address.

## Start

Run `packaging\Start-ProxyBridge-TestLab.ps1`. The controller binds only to
`127.0.0.1:5178` and opens the local browser. Configuration is entered only in
the UI. Do not create or edit an `.env` file.

## First-time workflow

1. Open **Environment Setup**. Verify the standard ProxyBridge locations and
   complete the requested local, proxy, endpoint and capability fields.
2. Open **Server Setup**. Enter the Debian/Ubuntu address, SSH user and private
   key. Validate the host key independently before accepting it.
3. Review the exact server plan and apply it. TestLab installs its versioned
   endpoint, dedicated account, systemd service and bounded log rotation.
4. Return to **Run Tests**, select executable tests and choose **Real traffic**.
5. Select **Review selected run**. This performs the bounded immutable preflight
   but does not execute a selected scenario.
6. Only after every gate passes, confirm and start the run.

## Result interpretation

- `PASS`: all mandatory evidence satisfied the scenario contract.
- `FAIL_PRODUCT`: complete evidence proves a product-path contradiction.
- `EXPECTED_FAIL`: the product failure matched a structured known-defect
  signature. It is not a pass.
- `HOLD_AMBIGUOUS`: evidence is incomplete; no product verdict is valid.
- `FAIL_HARNESS` or `FAIL_INFRASTRUCTURE`: correct the test environment and
  rerun. These are not product failures.
- `CONTAMINATED`: stop. Shared state was not proven clean.

Each test expands into a plain-English explanation, expected/observed behavior,
separate error classes, evidence channels, assertion timeline and sanitized
technical artifacts. The audit download excludes private configuration,
credentials, transcripts and generated profiles.

## VM validation checklist

Perform this only in a disposable VM or snapshot after installing the product
and building/restoring `bin\pb_net_client.exe`:

1. Verify the package with `packaging\Repair-ProxyBridge-TestLab.ps1`.
2. Configure the UI and provision the server.
3. Run fixture preview first; fixture results must not claim product coverage.
4. Run the three IPv4 TCP smoke scenarios individually.
5. Run IPv4 UDP DIRECT, BLOCK and PROXY individually.
6. Run the complete executable IPv4 diagnostic suite and confirm that one
   product failure does not stop independent later tests.
7. Confirm contamination or failed cleanup stops the remaining chain.
8. Download an audit and confirm it contains no key path, host value,
   credential, `.env`, generated profile or raw transcript.
9. Enable IPv6 only after the Windows host, server, firewall and proxy route are
   independently verified end to end.

## Stop, repair and remove local data

- Stop this package instance with `packaging\Stop-ProxyBridge-TestLab.ps1`.
- Verify package integrity with `packaging\Repair-ProxyBridge-TestLab.ps1`.
- Add `-RepairDataAcl` only to restore the current-user and SYSTEM ACL on the
  default data directory.
- `packaging\Uninstall-ProxyBridge-TestLabData.ps1 -ConfirmRemoval` irreversibly
  removes the current user's saved settings, protected secrets, jobs and local
  evidence after stopping this exact package instance.

Remote upgrade, repair and rollback are performed through **Server Setup** and
remain bound to the trusted host fingerprint and exact artifact hashes.
