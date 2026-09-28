# Milestone 15 / Task 2b-UI implementation brief

## Scope

Complete only the automatic capability/readiness integration for the already
accepted `canary-browser-download` core. Do not alter the browser worker,
browser origin, scenario catalog, product code, server transport, or network
assertion policy.

## Required behavior

1. Derive `local_browser_runtime` automatically from
   `LocalArtifactService.GetBrowserRuntimeStatus()`. It is enabled only when an
   allowlisted Edge/Chrome/Chromium image has a verified version and SHA-256.
2. Derive `server_browser_origin` automatically only while
   `ServerProvisioningService.GetStatusAsync()` returns `READY`. The existing
   service defines `READY` as a current receipt plus current-session endpoint
   verification; `STALE` and every other state must fail closed.
3. Use the same derived capability values in both real-run and immutable
   preflight capability documents. Do not accept these values from public UI
   input or `.env`.
4. Real-run readiness must be selection-aware:
   - a selection requiring `local_browser_runtime` is blocked when the browser
     is unavailable and shows concise English remediation;
   - a selection requiring `server_browser_origin` is blocked unless the
     current server state is `READY` and directs the user to Server Setup;
   - selections that do not require either capability remain unaffected;
   - fixture preview remains offline and is not blocked by local browser or
     server-origin availability.
5. Keep browser executable path, version hash, and server receipt details out
   of public gate text. Do not add manual browser path, browser SHA-256, client
   executable, or `.env` fields to the UI.
6. Materialized private runner input may include the verified browser image,
   exact SHA-256, basename/full path, version, and allowlisted browser identity.
   These remain internal and are never rendered in public readiness output.

## TDD acceptance

Extend the dependency-contained `Ui.RunProbe` / `Test-RunOrchestration.ps1`
coverage before production changes. Cover at minimum:

- verified browser + server `READY` enables both derived capabilities;
- missing browser disables only `local_browser_runtime`;
- server `STALE` disables `server_browser_origin`;
- required missing browser/origin blocks the selection with English
  remediation;
- a non-browser selection is not blocked by those absent capabilities;
- fixture mode is not browser/server-origin gated;
- capability-document application writes both values from the derived state;
- public UI/source has no manual browser path/hash controls.

Observe a strict RED before implementation, then run only the focused
orchestration test after the smallest implementation. Building the existing UI
and RunProbe projects is allowed; starting the UI or any browser/product/client,
driver/service, listener, SSH, loopback, or external network action is not.

## Review and constraints

Write `task-2b-ui-report.md` with the RED command/result, changed files, focused
GREEN command/result, and explicit prohibited-action statement. Do not commit
or push. Do not spawn subagents. Stop after the focused test passes.
