# Task 2b-core: browser worker to runner vertical slice

This task starts after Task 1 and Task 2a are complete. It wires the already
reviewed browser worker and browser origin through the source worker registry,
scenario catalog, execution planning, mock fixtures and structured assertions.
It does not implement UI readiness/capability derivation; that is the next
serial slice. Do not commit or push. Do not start a real browser, ProxyBridge,
driver/service, listener, SSH or network traffic.

## Scope

- `src/protocol_worker/registry.py`
- `src/protocol_worker/plugins/manifest.json`
- `modules/ProtocolRunner.psm1`
- `scenarios/application-canaries/canaries.catalog.json`
- the smallest necessary browser/catalog/protocol-runner/assertion fixture and
  targeted PowerShell tests
- `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-2b-core-report.md`

Do not edit the completed browser worker or browser-origin implementation.
Do not enable WebRTC, screen sharing, synthetic media, performance, failure
control or LAN capabilities. Do not add a browser path/hash field to the UI or
`.env` contract.

## Required behavior

1. Start with focused failing tests. Prove that `browser-worker` is absent from
   the source registry/manifest, `canary-browser-download` is gated, and the
   generic protocol plan/assertions do not provide a truthful browser contract.
2. Register `browser-worker` as an implemented lazy source plugin using
   `plugins.browser.run_browser`, protocol family `browser-web`, TCP transport,
   evidence profile `browser-session`, and its actual required evidence fields.
3. Promote only `canary-browser-download` to `EXECUTABLE`. It remains
   selection-gated by `local_browser_runtime` and `server_browser_origin`.
   Keep `canary-webrtc` and `canary-screen-sharing` capability-gated. Use a
   discriminating DIRECT TCP rule for the automatically derived browser
   basename and the controlled HTTP origin port; no manual browser values.
4. Build a browser execution plan from run/scenario/attempt/flow identities.
   The plan must derive, never accept from the browser UI:
   - exact controlled page URL under `/browser-origin/v1/.../page`;
   - identity-bound expected download SHA-256 matching `browser_origin.py`;
   - run-owned profile and download directories below the scenario evidence
     directory;
   - expected response `200` and truthful protocol `http/1.1`;
   - requested browser path, exact image hash, identity, version and rule
     basename from the automatically materialized environment.
   The Python protocol runtime remains the controller process, but
   `expected_process` and WFP route correlation must use the observed browser
   image/process tree. Never substitute the requested path as observed proof.
5. Browser assertions are not the generic one-client/one-server contract.
   Require exactly one canonical client completion, exactly two canonical
   server resources (`page` and `download`) with matching identities, distinct
   deterministic sequences, matching download content SHA-256, response and
   negotiated protocol, complete cleanup, and no malformed/duplicate evidence.
   Route proof must be restricted to verified PIDs from
   `browser_process_tree_pids`, the browser basename, exact destination and
   evidence time window. Because the origin closes each HTTP response, require
   two distinct expected-action TCP route decisions and reject any
   contradictory action. Missing/malformed evidence is never PASS; externally
   complete wrong action/content is `FAIL_PRODUCT`; cleanup/identity/evidence
   corruption remains higher-priority harness/contamination failure.
6. Extend the generated mock path with the same browser evidence shape. Tests
   must include positive PASS and negative fixtures for wrong content,
   missing/duplicate page or download, route from a PID outside the verified
   tree, only one route decision, contradictory route action, and unclean tree.
7. Preserve every non-browser protocol behavior and current continuation/
   contamination semantics. Update exact catalog/manifest counts only where
   the truthful promotion requires it.

## Verification

Run only the focused tests covering the changed source contracts, expected to
include `tests/Test-ProtocolWorker.ps1`, `tests/Test-ProtocolRunner.ps1`,
`tests/Test-Catalog.ps1`, and the smallest evidence/assertion test if amended.
All tests must run in Windows PowerShell 5.1 without external modules. No
loopback or external network vertical slice is authorized in this task.
