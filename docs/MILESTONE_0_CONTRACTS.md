# Milestone 0 contracts

Status: implementation baseline  
Contract version: `v1`

This document fixes the boundaries that Milestones 1-8 must preserve. It does
not enable product, SSH or network runtime.

## 1. Authority boundaries

| Component | Owns | Must not own |
|---|---|---|
| Web UI | user intent, selection, presentation | assertions or verdicts |
| Local controller | validation, protected settings, jobs, progress, runner invocation | product behavior classification |
| PowerShell runner | plans, execution, evidence, assertions, cleanup, result status | persistent UI secrets |
| Linux endpoint | deterministic TCP/UDP behavior and canonical evidence | product verdicts |
| Report reader | schema validation and human explanation | rewriting recorded results |

The file-backed runner report is authoritative. UI summaries are derived views
and must retain links to the exact source records used.

## 2. Local storage contract

Default application root:

```text
%LOCALAPPDATA%\ProxyBridge-TestLab\
  config\settings.json
  config\secrets.dpapi
  known-hosts\known_hosts
  runtime\<run-id>\
  evidence\<run-id>\
  logs\controller.jsonl
```

Rules:

- `settings.json` contains non-secret structured settings only.
- `secrets.dpapi` is protected for the current Windows user.
- SSH private-key location, proxy credentials and any sensitive executable or
  evidence paths are treated as protected values.
- API responses expose secret `present` state, never the stored value.
- The controller never imports application settings from a repository `.env`.
- The controller may generate `runtime\<run-id>\input.env` solely as a private
  compatibility input for the current runner.
- The compatibility file is ACL-restricted, excluded from evidence/export,
  never logged or returned, removed in `finally`, and scavenged after an
  interrupted controller start.
- Writes use same-directory temporary files and atomic replacement.

The UI is the only supported configuration editor. Documentation and error
messages must direct the user to `Environment Setup`, not to manual `.env`
editing.

## 3. Local HTTP boundary

- Bind only to `127.0.0.1` and `::1`; no wildcard binding.
- Reject non-local `Host` values and unexpected origins.
- Mutating requests require same-origin validation and an anti-forgery token.
- Request bodies have explicit size limits and schema validation.
- No endpoint accepts a shell command or raw PowerShell expression.
- File paths are data passed to typed validators; they are never concatenated
  into command strings.
- Evidence endpoints resolve canonical paths beneath one configured evidence
  root and reject traversal, links escaping the root and alternate data streams.
- Controller and UI logs pass the shared redaction boundary.

## 4. API v1 surface

The initial HTTP surface is intentionally small:

```text
GET    /api/v1/system/status
GET    /api/v1/settings/schema
GET    /api/v1/settings
PUT    /api/v1/settings
POST   /api/v1/settings/validate

GET    /api/v1/server/status
POST   /api/v1/server/validate
POST   /api/v1/server/plan
POST   /api/v1/server/apply
POST   /api/v1/server/repair
GET    /api/v1/server/metrics

GET    /api/v1/catalog
GET    /api/v1/catalog/{scenarioId}
POST   /api/v1/runs/dry-run
POST   /api/v1/runs
GET    /api/v1/runs
GET    /api/v1/runs/{runId}
POST   /api/v1/runs/{runId}/cancel
GET    /api/v1/runs/{runId}/scenarios/{scenarioId}
GET    /api/v1/runs/{runId}/evidence/{artifactId}

SignalR /hubs/runs
```

`POST /runs` accepts scenario IDs and explicit public run options. It does not
accept executable paths, environment variables, credentials, output paths or
runner switches. The controller constructs those from validated stored state.

Real execution also requires a short-lived confirmation nonce issued only after
a successful immutable preflight. A stale browser tab cannot reuse the nonce.

## 5. Configuration sections

The UI model is structured; it is not a list of environment variables:

```text
local_product
local_client
proxy
server_connection
server_endpoint
capabilities
timeouts
retention
ui
```

Each field declares type, range, sensitivity, required conditions and a
human-readable remediation. A setting may be saved as incomplete, but readiness
cannot become `READY` until every selected capability's requirements validate.

## 6. Server state machine

```text
UNCONFIGURED
  -> VALIDATING
  -> NEEDS_HOST_TRUST
  -> PLAN_READY
  -> APPLYING
  -> VERIFYING
  -> READY
```

Any state may move to:

- `UNSUPPORTED`: OS is not Debian/Ubuntu or systemd is unavailable;
- `STALE`: fingerprint, endpoint hash, address, capability or receipt age
  changed;
- `ERROR`: a bounded operation failed without an applied partial state;
- `REPAIR_REQUIRED`: a known partial or drifted installation was observed.

Only `READY` plus a fresh pre-run immutable preflight enables real execution.
The host fingerprint can move from unknown to trusted only through an explicit
UI confirmation. A changed trusted fingerprint never auto-accepts.

## 7. Run state machine

```text
DRAFT -> VALIDATING -> QUEUED -> PREFLIGHT -> RUNNING
                                      |          |
                                      |          -> RECOVERING -> RUNNING
                                      |          -> CANCELLING -> CANCELLED
                                      |          -> COMPLETED
                                      |          -> SAFETY_STOPPED
                                      -> FAILED_TO_START
```

- At most one real run may be active.
- Dry-run and report viewing cannot mutate product/server state.
- Cancellation is cooperative first, then bounded process cleanup; it is not a
  raw process-tree kill.
- A controller restart discovers an orphaned run, validates its evidence and
  records an interrupted terminal state. It does not silently resume product
  operations.

## 8. Scenario result contract

The runner's existing result statuses remain authoritative:

```text
PASS
FAIL_PRODUCT
EXPECTED_FAIL
HOLD_AMBIGUOUS
BLOCKED_BY_KNOWN_DEFECT
SKIPPED_CAPABILITY
SKIPPED_SELECTION
NOT_IMPLEMENTED
UNSUPPORTED_PRODUCT_SCOPE
FAIL_HARNESS
FAIL_INFRASTRUCTURE
CONTAMINATED
```

Dry-run and mock statuses remain distinct and never become tested product
coverage. `EXPECTED_FAIL` remains a reproduced product defect, not a pass.

Scenarios skipped after a run-level safety stop receive a separate UI/report
execution disposition `NOT_RUN_SAFETY_STOP`; it is not added as a product
result status and does not affect the product verdict.

## 9. Continuation decision table

| Outcome | Default action | Required condition |
|---|---|---|
| PASS | continue | cleanup and health pass |
| FAIL_PRODUCT | continue | shared state proven clean |
| EXPECTED_FAIL | continue | shared state proven clean |
| HOLD_AMBIGUOUS | continue if independent | shared state proven clean |
| skip/not implemented | continue | no runtime mutation occurred |
| FAIL_HARNESS | bounded recovery | continue only after clean proof |
| FAIL_INFRASTRUCTURE | bounded recovery | continue only after clean proof |
| CONTAMINATED | stop | recovery is not evidence of prior result validity |
| hash/rule-state drift | stop | immutable or state authority lost |

The UI may explain this table but cannot override it with a generic
`continue anyway` control.

## 10. Evidence completeness contract

Before a product verdict, the result records whether each required channel was
requested, captured, parsed and validated:

```text
rule_plan
rule_apply_readback
client_plan
client_lifecycle
client_jsonl
proxybridge_lifecycle
proxybridge_records
endpoint_query
endpoint_jsonl
direct_baseline
assertion_result
cleanup
post_run_health
```

Scenario contracts identify which channels are mandatory. Missing mandatory
evidence cannot produce `PASS`. A definite, canonical product contradiction may
produce `FAIL_PRODUCT` only when higher-priority contamination, malformed
evidence and shared-state failures have been excluded.

Human explanations are deterministic templates populated from structured
assertion fields. They must not infer a cause absent from the evidence.

## 11. Server provisioning safety

- All discovery before `server/apply` is read-only.
- `server/plan` returns exact packages, paths, units, commands, ports, hashes
  and rollback operations, with sensitive arguments redacted.
- `server/apply` requires the exact unexpired plan ID and its user confirmation.
- Remote commands are selected from typed operations; arbitrary command text is
  not accepted from the browser.
- Uploaded content is written to a temporary path, hash-verified, permissioned,
  then atomically activated.
- The endpoint runs as a dedicated non-root user.
- `sudo -n` is required for unattended provisioning; lack of it produces a
  remediation message and no mutation.
- Firewall adapters modify only rules carrying a TestLab ownership marker.
- Rollback never changes unrelated packages, units, users or firewall rules.

## 12. Threat model baseline

Required tests and mitigations cover:

- malicious sites calling localhost APIs: origin, host and anti-forgery checks;
- DNS rebinding: fixed loopback binding and host allowlist;
- command injection: typed operations and argument-safe process APIs;
- path traversal/symlink escape: canonical-root validation;
- secret leakage: DPAPI, response masking and shared redaction;
- SSH man-in-the-middle: explicit first trust and fail-closed key changes;
- evidence spoofing/staleness: run/phase identity and exact payload SHA-256;
- concurrent or duplicate real runs: exclusive controller lease;
- controller crash: bounded orphan detection and no automatic runtime resume;
- privilege expansion: exact provisioning plan and narrowly scoped sudo use.

## 13. Milestone 0 acceptance

Milestone 0 is complete when:

- the approved development plan is present;
- UI-only configuration and the internal `.env` compatibility boundary are
  explicit;
- API, storage, authority, state, continuation, evidence and threat contracts
  are documented;
- no runtime code, product code, catalog or assertions changed;
- one existing offline `tests\Run-All.ps1` baseline passes;
- no ProxyBridge, client, SSH or network runtime was invoked.
