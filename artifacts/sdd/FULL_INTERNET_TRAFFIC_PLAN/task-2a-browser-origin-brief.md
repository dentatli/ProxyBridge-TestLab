# Task 2a: integrate the controlled browser origin

This task starts only after Task 1 passes re-review. It is server-side and
must not edit the browser worker, scenario catalog, PowerShell runner, route
assertions, UI readiness, or capability generation.

## Scope

- `src/server_agent/browser_origin.py`
- `src/server_agent/pb_protocol_server.py`
- `src/server_agent/plugins/catalog.json`
- `ui/ProxyBridge.TestLab.Ui/Services/ServerArtifactBuilder.cs`
- server-provisioning/browser-origin fixtures and targeted tests only

Do not commit or push. Do not deploy, use SSH, start ProxyBridge, or access an
external network.

## Required behavior

1. Start with a failing integration test proving that the current HTTP listener
   does not route the versioned browser-origin page/download paths and that the
   provisioning bundle omits `browser_origin.py`.
2. Keep the existing strict, path-bound identity contract. Route only exact
   `/browser-origin/v1/runs/<run>/scenarios/<scenario>/attempts/<attempt>/flows/<flow>/{page,download}`
   paths before the generic header-bound HTTP handler. Invalid/traversal/query
   paths fail closed and never emit a successful evidence record.
3. The page must execute a deterministic same-origin `fetch` of the matching
   download resource, hash the returned bytes with Web Crypto, read the
   browser-observed negotiated protocol, and place exactly one bounded JSON
   marker in the DOM under `script#proxybridge-testlab-browser-result`. The
   marker fields are `dom_marker`, `content_sha256`, `response_status`, and
   `negotiated_protocol`. No credentials, private paths, raw headers, or page
   payloads are logged.
4. Page and download responses are deterministic, no-store, nosniff, and
   bounded. The download body is identity-bound. Server evidence emits one
   canonical record per resource with run/scenario/attempt/flow identities,
   resource, event, content hash/length, tuple and protocol fields needed for
   later correlation. Sequence values are deterministic and distinct.
5. Register `browser-origin` as IMPLEMENTED only after the artifact builder
   includes `browser_origin.py` in the immutable runtime bundle and plugin
   manifest. Existing endpoint service count and unrelated plugins must not be
   changed accidentally.
6. Tests must cover page/download success, deterministic hash, exact marker
   contract, invalid path/query/traversal, malformed request with no PASS
   evidence, bundle/plugin integrity, and unchanged generic HTTP behavior.
   Windows PowerShell 5.1 compatibility is required.

## Verification

Run only the focused browser-origin test(s) named by the implementation report
and `tests/Test-ServerProvisioning.ps1`. No real browser or external network.
