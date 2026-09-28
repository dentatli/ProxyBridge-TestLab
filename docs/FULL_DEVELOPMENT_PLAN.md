# ProxyBridge-TestLab full development plan

Status: approved for implementation  
Plan version: 1.0  
User-facing language: English

## Progress

| Milestone | Status | Effort | Evidence |
|---|---|---|---|
| 0 - baseline and contracts | Complete | Medium | Existing offline suite passed 15/15 |
| 1 - read-only UI shell | Complete | High | Release build passed; targeted UI-shell test passed |
| 2 - configuration and secrets | Complete | Very High | Release build passed with 0 warnings/errors; targeted settings-security test passed |
| 3 - server provisioning | Complete | Very High | Release build passed with 0 warnings/errors; guarded offline provisioning test passed |
| 4 - safe job orchestration | Complete | Very High | Release build passed with 0 warnings/errors; offline queue/lifecycle probe passed |
| 5 - human-readable results | Complete | High | Release build passed; offline result/explanation/export probe passed |
| 6 - false-result hardening | Complete | Very High | PS 5.1 evidence, endpoint, report and orchestration contract tests passed |
| 7 - traffic coverage | Complete | Very High | 91 executable contracts; 37 individually limited; 7 unsupported |
| 8 - release candidate | Complete | Very High | Run-All 21/21; verified self-contained `0.2.0-rc2` package with x64 client |
| 9 - protocol contracts | Complete | Very High | 38 families, 23 capabilities/profiles and exact 37-scenario roadmap validated |
| 10 - protocol worker | Complete | Very High | Bundled x64 runtime builder and offline worker/evidence self-test passed |
| 11 - endpoint plugins | Complete | Very High | Versioned server bundle, guarded provisioning and offline verification passed |
| 12 - DNS/TLS/HTTP vertical slice | In progress | High | Offline gate passed; independent first-use server identity confirmation is pending |
| 13-20 - full traffic expansion | Pending | High-Max | See `FULL_INTERNET_TRAFFIC_PLAN.md` |

## 1. Objective

Turn the existing deterministic PowerShell runner into a complete local test
application with a web UI. The application must configure the environment,
provision and verify the Linux endpoint, select and run tests, stream progress,
and explain every result without weakening the existing evidence and safety
contracts.

The PowerShell runner remains the only authority for scenario execution,
assertions, classification, cleanup and evidence. The UI is an orchestration
and presentation layer; it must not independently invent product verdicts.

## 2. Fixed product decisions

- The UI is a local web application bound to `127.0.0.1` only.
- The local controller uses ASP.NET Core on .NET 10 LTS.
- The existing runner remains compatible with Windows PowerShell 5.1.
- All user-facing UI, setup, progress, errors and reports are in English.
- Linux endpoint provisioning supports only Debian or Ubuntu with systemd.
- SSH authentication supports private keys only. Password SSH login is not
  supported.
- The Windows tester may be behind NAT. It needs outbound connectivity only.
- The Linux endpoint must have a public or otherwise routable address, port
  forwarding, or a supported overlay/VPN route.
- Product code and external product binaries remain outside this repository.

## 3. UI-only configuration

Users do not create, edit or inspect `.env` files.

The UI owns all configuration. Non-secret settings are stored in a local
per-user application directory. Credentials and sensitive paths are protected
with Windows DPAPI for the current user. An SSH key passphrase, if accepted by
a future implementation, is memory-only and is never persisted.

While the existing PowerShell runner still requires `-EnvPath`, the controller
may generate a private, ACL-restricted `.env` compatibility file inside the
run's private runtime directory. It is never returned by the API, displayed,
included in evidence, or exported. It is removed in a `finally` path, and stale
runtime directories are cleaned on the next application start. This is an
internal adapter, not a user configuration surface.

## 4. Target architecture

```text
Local browser
    -> loopback ASP.NET Core controller
        -> settings and protected-secret store
        -> run queue and progress stream
        -> existing PowerShell runner
            -> ProxyBridge CLI and deterministic Windows client
            -> Debian/Ubuntu endpoint through SSH and TCP/UDP
```

SignalR provides live progress. Reports remain file-backed and schema-driven so
CLI and UI executions produce the same classifications and evidence.

## 5. UI surfaces

### Dashboard

Show TestLab, ProxyBridge and endpoint readiness, the last verification time,
enabled capabilities, the most recent run and result counts. `Run Tests` stays
disabled until every required readiness gate passes.

### Environment Setup

Collect and validate executable paths, service identity, SOCKS configuration,
evidence retention, capabilities and timeouts. Standard paths are prefilled,
the bundled client is discovered relative to TestLab, and exact integrity
values are calculated internally. The page shows only masked sensitive values
and presence indicators.

### Server Setup

Collect host/IP, SSH port, user, private-key path, endpoint ports and allowed
direct/proxy egress sources. The wizard validates the key, verifies the SSH host
fingerprint, detects the OS and systemd, checks non-interactive sudo, previews
changes, provisions the endpoint, and produces a signed readiness receipt.

### Test Catalog and Run Builder

Support filtering and selection by suite, protocol, address family, action,
socket mode, selector, implementation status, capability and known defect.
Every scenario displays its purpose, prerequisites, planned rules, traffic,
expected outcome, required evidence and known limitation.

### Live Run

Show the current scenario and phase, completed and remaining counts, elapsed
time, endpoint health, scenario results, bounded recovery and safety-stop
reason. Cancellation stops future work and performs the normal cleanup path.

### Results

Every scenario has two expandable views:

- `Explanation`: what was tested, expected, observed, why the status was
  assigned and the recommended next action;
- `Technical evidence`: sanitized plans, lifecycle, client records,
  ProxyBridge records, endpoint records, assertions, missing evidence, cleanup,
  timestamps and hashes.

### Server Metrics

Collect service state and uptime, CPU/memory, disk usage, TCP/UDP event counts,
endpoint errors and sanitized recent logs through SSH. No public metrics API is
opened on the endpoint.

## 6. Endpoint provisioning contract

Provisioning is idempotent and has four explicit steps:

1. read-only preflight;
2. exact change plan and user confirmation;
3. bounded application with recorded transitions;
4. service, transport and evidence verification.

Preflight must verify SSH, host identity, Debian/Ubuntu, systemd as PID 1,
architecture, `sudo -n`, disk space, required ports and conflicting units.
Unsupported systems are rejected before mutation.

Provisioning creates a dedicated unprivileged service account, versioned
endpoint files, protected evidence directories, a systemd unit and log
rotation. Every uploaded artifact is hash-verified before activation. Firewall
changes are narrowly scoped to TestLab ports, are previewed, never replace the
host's default policy, and roll back only TestLab-owned rules on failure.

The server records the observed client NAT egress during readiness. A changed
egress address makes readiness stale and requires the UI to refresh the scoped
access rule. Proxy egress is verified independently.

## 7. Readiness and launch guard

A real run is unavailable until all required gates pass:

- configuration schema valid;
- all required UI settings present;
- no unresolved placeholders in the internal resolved configuration;
- local executable paths and exact hashes verified;
- server provisioned and its receipt current;
- SSH host fingerprint unchanged;
- endpoint artifact hash and service state verified;
- required TCP/UDP control probes complete;
- required proxy backend healthy;
- selected capabilities satisfied;
- ProxyBridge environment clean and prepared;
- direct baseline available where required.

The UI identifies every failed gate and links to its remediation. It never
offers a bypass that maps incomplete readiness to a product verdict.

## 8. Execution and continuation policy

Scenario-local product outcomes do not stop independent later scenarios.
Execution continues after `PASS`, `FAIL_PRODUCT`, `EXPECTED_FAIL`,
`HOLD_AMBIGUOUS`, `BLOCKED_BY_KNOWN_DEFECT`, capability/selection skips and
`NOT_IMPLEMENTED`, subject to the suite's explicit bounded failure policy.

Every scenario is followed by cleanup, reset and a health check. A harness or
infrastructure failure triggers one bounded recovery attempt. Execution may
continue only when the shared environment is proven clean. `CONTAMINATED`, an
unknown active rule state, binary hash drift, failed cleanup, or an unhealthy
shared service causes a safety stop. Remaining scenarios are recorded as not
run because of that stop; they are never reported as product failures.

## 9. False-result prevention

- Product verdicts require complete mandatory evidence channels.
- Every flow has run, scenario and phase identities, a random payload, exact
  SHA-256, timestamps and a protocol/address/port tuple.
- Stale endpoint records cannot satisfy a current assertion.
- Critical routes use independent client, endpoint, baseline and optional
  ProxyBridge evidence.
- BLOCK requires both client no-response semantics and zero exact endpoint
  payload matches.
- Evidence corruption or absence produces a harness/infrastructure/ambiguous
  result, never a false product PASS.
- Known defects match structured `product_errors` signatures only. Unrelated
  failures remain `FAIL_PRODUCT`.
- Repeats expose each attempt and an aggregate such as consistent pass,
  intermittent or consistent failure. A flaky result is not normalized to
  PASS.

## 10. Coverage waves

1. Preserve and harden the existing IPv4 TCP/UDP DIRECT/BLOCK/PROXY matrix,
   selectors, invalid-profile cases, no-leak checks and known signatures.
2. Add lifecycle and state transitions: supported issue206/issue209 cases,
   graceful/abortive close, exact tuple reuse, reconnect, delayed responses,
   hot updates and bounded component restarts.
3. Add deterministic payload classes: boundary sizes, partial TCP I/O,
   multiple messages, binary payloads, UDP delayed/duplicate/reordered and
   receive-only behavior where the external client contract can prove them.
4. Add bounded concurrency: parallel TCP, parallel UDP, mixed protocols,
   multiple destinations and process isolation.
5. Complete discriminating rule-engine coverage: selectors, destination,
   ports/ranges, precedence, overlap, enabled state, missing proxies and exact
   readback.
6. Add IPv6 only after end-to-end host, server, firewall, endpoint and proxy
   capabilities are proven.
7. Add fixture-first failure injection for endpoint, proxy, SSH, client, CLI,
   malformed evidence, timeouts, disk/write failures, hash drift and cleanup.
8. Add real-application canaries only after synthetic correctness is stable.
9. Add performance and soak measurements only after the correctness gate.

The catalog targets meaningful equivalence classes and critical interactions;
it does not claim literal exhaustiveness over every possible packet sequence.

## 11. Implementation milestones

### Milestone 0 - Baseline lock and contracts

Document system boundaries, configuration ownership, API v1, state machines,
status semantics, threat model and acceptance gates. Run the existing offline
test suite once. Do not run product, SSH or network operations.

### Milestone 1 - Read-only UI shell

Implement the loopback controller, English dashboard, catalog browser and
fixture/report viewer. No real-run endpoint is enabled.

Completed in the local baseline. The controller is loopback-only, the catalog
projection is produced by the authoritative PowerShell catalog module, and the
report viewer reads only sanitized report fields and an explicit mock fixture.
No mutation or real-runtime HTTP endpoint exists.

### Milestone 2 - UI configuration and secret boundary

Implement settings schemas, DPAPI storage, masking, internal ephemeral runner
input generation and redaction tests. Remove all user instructions to edit
`.env` manually.

Completed. The controller now validates schema-driven settings, stores public
values separately from CurrentUser DPAPI-protected secrets, returns presence
flags instead of secret values, protects mutations with same-origin and CSRF
checks, and can create an ACL-restricted short-lived compatibility input for
the existing runner. No real-runtime endpoint was enabled.

### Milestone 3 - Server provisioning

Implement SSH trust, read-only discovery, dry-run plan, idempotent install,
repair/upgrade, rollback, readiness receipt and metrics for Debian/Ubuntu with
systemd.

Completed in the local baseline. Server Setup now requires explicit SSH-key
validation, fail-closed host fingerprint trust, supported-platform discovery,
an exact ten-minute plan and separate confirmation before mutation. The
idempotent installer uses a dedicated account, versioned artifacts, atomic
activation, bounded SSH processes, rollback, a signed 24-hour receipt and
sanitized SSH-collected metrics. The endpoint unit scopes accepted sources;
host firewall policy remains externally owned. Real test execution remains
fail-closed until an exact immutable-preflight receipt can authorize it.

### Milestone 4 - Safe job orchestration

Implement one-active-real-run enforcement, queueing, progress, cancellation,
bounded recovery and fixture/mock execution through the existing runner.

Completed in the local baseline. The browser submits only scenario IDs and a
public mode; the controller owns runner inputs, generated suite/capability
overlays, evidence paths and process arguments. Jobs are persisted, queued
through one worker, streamed through the `/hubs/runs` contract, recover once
only before evidence/runtime mutation, and become interrupted terminal records
after a controller restart. Cooperative cancellation stops future scenarios
and lets the current bounded operation follow normal cleanup. Fixture jobs run
through the authoritative PowerShell mock path. The real adapter is present but
remains fail-closed because a server receipt alone is not the signed, exact
immutable-preflight receipt required by the Milestone 0 contract.

### Milestone 5 - Human-readable results

Implement explanation and evidence views, assertion timeline, expected versus
actual, product/harness separation and sanitized audit export.

Completed in the local baseline. Result details now use deterministic templates
over the runner's structured fields, keep product, harness, missing-evidence and
contamination causes separate, and show the expected behavior, observed outcome,
evidence basis, channel status and assertion timeline. The download endpoint
builds a bounded in-memory ZIP from an explicit sanitized allowlist and excludes
compatibility inputs, generated profiles, credentials, transcripts, reparse
points and arbitrary evidence files.

### Milestone 6 - False-result hardening

Implement completeness matrices, negative controls, contradiction fixtures,
stale-record rejection, fault injection and continuation/recovery tests.

Completed in the local baseline. Canonical client and endpoint evidence now
requires run, scenario, phase, sequence and UTC-window correlation. Endpoint
records outside the active lifecycle or inconsistent with their client flow are
classified as contamination. The runner writes a channel-by-channel completeness
matrix and will not preserve a product verdict when a mandatory channel is
incomplete. Repeated attempts retain individual statuses plus a fail-closed
aggregate (`CONSISTENT_PASS`, `CONSISTENT_FAILURE` or `INTERMITTENT`). Existing
negative-control, malformed-evidence, contradiction, bounded-recovery and
continuation fixtures remain part of the offline suite.

### Milestone 7 - Traffic coverage waves

Implement the coverage waves as separate reviewable changes. A scenario becomes
`EXECUTABLE` only when its client contract and evidence prove its assertion.

Completed after the correction review. The catalog contains 135 meaningful
classes across 15 groups: 91 executable traffic/evidence contracts, 37
individually limited declarative entries and 7 explicit unsupported
product-scope entries. The executable set now includes payload boundaries and
streaming, advanced TCP/UDP lifecycle, exact tuple reuse, concurrency,
cross-process isolation, DNS and rule-engine discrimination, safe endpoint
failure injection and the critical IPv4/IPv6 DIRECT/BLOCK/PROXY matrix. IPv6
remains capability-gated.

The remaining 37 entries are not represented as completed tests. Each has an
explicit catalog-tested reason identifying its missing external application,
authorized lifecycle/control mechanism, inbound/NAT contract or calibrated
performance methodology. Real-run selection remains limited to exact
contracts, and no entry was promoted merely to increase the executable count.

### Milestone 8 - Packaging and release candidate

Produce a self-contained Windows package, versioned endpoint artifact,
upgrade/uninstall/recovery paths, operator and security documentation, and a
sanitized release audit.

Completed after traffic coverage closed its corrected implementation boundary.
The release publisher created the new self-contained win-x64 `0.2.0-rc2`
controller directory and ZIP from an explicit public allowlist, included the
compiled x64 client, recorded a manifest and SHA-256 inventory and refused
overwrite of earlier artifacts. All 550 packaged files were verified against
that inventory. Launch, exact-process stop, package verification, default-data
ACL repair and confirmation-gated data removal scripts provide bounded local
recovery/removal paths. Server Setup activates content-addressed endpoint
versions atomically and retains rollback and repair behavior. The real adapter
is connected only through a signed, selection-bound two-minute
immutable-preflight receipt. Operator, release and security guides document the
remaining manual VM validation boundary.

## 12. Codex reasoning-effort policy

Use the lowest effort that reliably satisfies the milestone's acceptance
criteria. A higher setting is not a general quality guarantee and must not
replace focused tests, evidence or review. The normal project default is
`Medium`; return to it after any deliberately elevated task.

The labels below correspond to the effort selector in the Codex UI:

- `Light` - documentation spelling, small wording changes, file discovery,
  simple status inspection and clearly mechanical one-file edits. Do not use it
  for assertions, security boundaries, lifecycle code or real-runtime plans.
- `Medium` - default for routine implementation, isolated bug fixes, schemas,
  fixtures, ordinary unit tests and small UI components. This is the preferred
  cost/productivity setting when the affected contract is already clear.
- `High` - multi-file features, UI/backend integration, report presentation,
  runner adapters and reviews where several existing contracts interact. Use
  it when `Medium` misses dependencies or the task has meaningful regression
  risk.
- `Very High` - security-sensitive configuration, DPAPI/redaction, SSH trust,
  server provisioning, process lifecycle, concurrency, timeout budgeting and
  assertion/classification changes. Use for implementation and targeted review
  of these areas, then return to `Medium`.
- `Max` - rare quality-first work: unexplained evidence contradictions,
  contamination analysis, difficult cross-protocol races, threat-model review,
  final release/security audit, or a failed `Very High` attempt. Keep the task
  narrow and run representative checks to confirm that the extra effort helped.
- `Ultra` - exceptional, explicitly approved work that divides into several
  independent parallel investigations or implementation streams. It consumes
  the usage allowance quickly and is not appropriate for ordinary milestones,
  routine tests, sequential debugging or documentation.

Recommended effort by milestone:

| Milestone | Normal effort | Raise only when |
|---|---|---|
| 0 - baseline and contracts | Medium | a contract conflict requires High |
| 1 - read-only UI shell | High | security boundary review requires Very High |
| 2 - configuration and secrets | Very High | final threat review requires Max |
| 3 - server provisioning | Very High | privilege/rollback ambiguity requires Max |
| 4 - safe job orchestration | Very High | unresolved lifecycle race requires Max |
| 5 - results UX | High | verdict/evidence semantics change requires Very High |
| 6 - false-result hardening | Very High | cross-channel contradiction requires Max |
| 7 - traffic coverage | High | lifecycle/concurrency work requires Very High |
| 8 - release candidate | Very High | final security/release audit requires Max |

Operating rules:

1. Start a new routine task at `Medium` unless the table requires more.
2. Increase one level only for a concrete risk or an unsuccessful lower-effort
   attempt; do not increase merely because a task is long.
3. Prefer a narrower prompt, exact acceptance criteria and one targeted test
   over raising effort.
4. Use `Max` for a bounded diagnosis or final audit, not for an entire
   milestone.
5. Use `Ultra` only after explicit agreement that parallel work is beneficial.
6. Record the chosen effort and reason in each milestone kickoff and report.
7. After the difficult step is complete, reset the next task to `Medium`.

This policy follows the official guidance to use `Medium` as the balanced
starting point, `High` or `Very High` when additional reasoning has a measured
quality benefit, and `Max` only for the hardest quality-first workloads. Recheck
the policy when changing the Codex model or when representative project tests
show a different cost/quality tradeoff. See [OpenAI model guidance](https://developers.openai.com/api/docs/guides/latest-model).

## 13. Development workflow

Each milestone follows the same order:

1. inspect the affected contracts and agree on acceptance criteria;
2. implement the smallest coherent change;
3. run syntax and targeted offline tests;
4. run fixture/mock integration where applicable;
5. verify redaction and forbidden-call gates;
6. review the incremental diff and concise report;
7. proceed to the next milestone only after review;
8. run a separately authorized real smoke only after all offline gates pass.

No milestone should combine unrelated UI, assertion, provisioning and catalog
changes. Real ProxyBridge, SSH and network activity is never part of an ordinary
development test.

## 14. Completion criteria

The project is complete when the English UI controls all configuration, a
supported server can be provisioned without manual file editing, real execution
is impossible without fresh readiness, independent product failures do not stop
the suite, unsafe shared state does stop it, every verdict is evidence-backed,
all results are readable and expandable, exported evidence is sanitized, and
installation, upgrade, recovery and removal are documented and verified.
