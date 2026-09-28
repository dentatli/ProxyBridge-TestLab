# Task 2b-core — browser worker to runner vertical slice

## Result

`DONE`

The reviewed browser worker is registered and wired through the source plugin
registry, manifest, application-canary catalog, execution planning, generated
mock evidence and browser-specific structured assertions. Only
`canary-browser-download` is now `EXECUTABLE`; WebRTC and screen sharing remain
capability-gated.

## TDD evidence

### RED

Commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolWorker.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Catalog.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolRunner.ps1
```

Results:

- `Test-ProtocolWorker.ps1`: exit `1`; expected 20 implemented plugins, actual
  19. This proved the browser worker was absent from the manifest/registry
  contract.
- `Test-Catalog.ps1`: exit `1`; expected 172 executable scenarios, actual 171.
  This proved `canary-browser-download` was still gated.
- `Test-ProtocolRunner.ps1`: exit `1` with
  `PROTOCOL_WORKER_PLUGIN_NOT_IMPLEMENTED`. This proved the generic runner could
  not build the required browser plan, before any browser-specific assertion
  path was reachable.

### Repair iteration

The first post-implementation `Test-ProtocolRunner.ps1` run exited `1` only in
the new malformed-server negative fixture: the missing field was correctly
recorded as a harness error, but a resource-count-only guard still allowed a
later strict property read. The guard was narrowed so deep correlation occurs
only when both resource records have complete contracts. No production
requirement was weakened.

### Final GREEN

Commands and results:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolWorker.ps1
exit 0: PASS: bundled protocol worker contract and offline self-test

powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolRunner.ps1
exit 0: PASS: fail-closed protocol runner lifecycle and assertions

powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Catalog.ps1
exit 0: PASS: catalog
```

No broader suite, listener, loopback/external network or runtime acceptance was
run.

## Design

- `browser-worker` is an implemented lazy runner for
  `plugins.browser.run_browser`, family `browser-web`, transport `TCP`, profile
  `browser-session`. Its manifest requires the worker's browser identity,
  observed-image, image-hash, process-tree, path-probe, response/content and
  cleanup evidence fields.
- The catalog uses a discriminating DIRECT TCP rule with
  `${PB_BROWSER_APPLICATION_BASENAME}` and `${PB_PROTOCOL_HTTP_PORT}`. The
  scenario remains selected only when `local_browser_runtime` and
  `server_browser_origin` are enabled.
- Browser planning replaces any scenario-supplied browser values. It derives
  the exact page URL, identity-bound download body hash, isolated profile and
  download paths, status `200`, protocol `http/1.1`, requested image, image
  hash, exact image identity, version and rule basename from run identities and
  the automatically materialized environment. The launched controller remains
  the protocol Python runtime; `expected_process` is the browser basename.
- Browser server collection has an asymmetric page/download parser because
  origin records truthfully describe server resources rather than pretending
  to contain client-only browser-image fields.
- Browser assertions require one canonical client completion and exactly one
  page plus one download record with the same identities/session, sequences 1
  and 2, exact paths, content/status/protocol correlation and verified cleanup.
  Route correlation requires the observed browser basename, exact destination,
  evidence window, PIDs from `browser_process_tree_pids`, and two distinct
  expected-action decisions.
- Generated mock evidence has the same client, two-resource server and
  two-route shape. Negative fixtures cover wrong content, missing/duplicate
  page and download, route PID outside the verified tree, one route,
  contradictory and wholly wrong route actions, unclean process tree and a
  malformed server record.
- Complete wrong content or route action is `FAIL_PRODUCT`; missing evidence is
  `HOLD_AMBIGUOUS`; duplicate/contradictory/identity contamination is
  `CONTAMINATED`; malformed evidence and cleanup failure are `FAIL_HARNESS`.
  Existing non-browser assertion and continuation semantics remain on the
  unchanged generic branch.

## Changed files

- `src/protocol_worker/registry.py`
- `src/protocol_worker/plugins/manifest.json`
- `modules/ProtocolRunner.psm1`
- `scenarios/application-canaries/canaries.catalog.json`
- `tests/Test-ProtocolWorker.ps1`
- `tests/Test-ProtocolRunner.ps1`
- `tests/Test-Catalog.ps1`
- `tests/fixtures/browser-runner/registry_contract.py`
- `tests/fixtures/mock/protocol/browser-direct.json`
- this report

The completed `src/protocol_worker/plugins/browser.py` and
`src/server_agent/browser_origin.py` were not edited.

## Concerns / deferred work

- Evidence is offline and fixture-backed. It does not claim that a real browser
  or ProxyBridge runtime passed.
- UI readiness/capability derivation remains the next serial slice. No browser
  setting or `.env` input was added.
- No WebRTC, screen sharing, synthetic media, performance, failure-control or
  LAN capability was enabled.
- No commit or push was performed.

## Fix round 1 — route identity and semantic evidence review

### Root causes

1. Route distinctness used `pid|timestamp|raw_line`. Timestamp and formatting
   describe observations, not TCP connections, so two log lines for one
   structured process/destination tuple could satisfy the two-connection gate.
2. Browser identity/probe/cleanup fields were checked only for presence or
   consumed through PowerShell casts. In particular, `[bool]'false'` is true,
   and navigation/profile/session digests were not recomputed from the plan
   identities.
3. Any wrong-action route record immediately added a product error, even when
   the second closed HTTP connection was missing and external route proof was
   therefore incomplete.

### RED

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolRunner.ps1
```

Result: exit `1` with one aggregated `FIX ROUND 1 RED`. It recorded these
incorrect outcomes before the production repair:

- duplicate observations of one structured browser connection: expected
  `HOLD_AMBIGUOUS`, actual `PASS`;
- wrong navigation digest, profile identity and identity-bound server session:
  expected `CONTAMINATED`, actual `PASS`;
- wrong path-probe status, string/zero attempts, string/negative elapsed time,
  string `false` image verification and string `false` cleanup: expected
  `FAIL_HARNESS`, actual `PASS`;
- one wrong-action connection with the second connection missing: expected
  `HOLD_AMBIGUOUS`, actual `FAIL_PRODUCT`.

The aggregate deliberately ran every new negative fixture before throwing, so
all three review findings were observed RED before `ProtocolRunner.psm1` was
changed.

### Repair

- Browser route records are grouped by a canonical structured connection tuple:
  normalized process basename, verified PID, exact destination IP and exact
  destination port. Timestamp and raw log text are excluded. Action sets are
  evaluated per tuple, so duplicate observations collapse and conflicting
  actions remain contamination.
- `navigation_url_digest` and `profile_id` must equal SHA-256 of the derived
  target URL and profile path. Every server `browser_session_id` must equal the
  separator-bound SHA-256 of run/scenario/attempt/flow identities.
- The path probe must be `PATH_OBTAINED`; attempts and elapsed values must be
  actual JSON integers with bounds `>= 1` and `>= 0`. Image verification and
  cleanup must be actual booleans equal to `true`; strings never satisfy the
  contract.
- Two distinct complete wrong-action connection tuples produce
  `FAIL_PRODUCT`. One wrong tuple, including duplicate observations of it,
  remains `HOLD_AMBIGUOUS`. Expected and wrong actions together remain
  `CONTAMINATED`.

### GREEN

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolRunner.ps1
```

Result: exit `0`:

```text
PASS: fail-closed protocol runner lifecycle and assertions
```

### Fix-round changed files

- `modules/ProtocolRunner.psm1`
- `tests/Test-ProtocolRunner.ps1`
- this report

The existing browser mock fixture already supplied two distinct structured
process/destination tuples and did not require a schema change. No browser,
product process, listener, SSH, loopback/external network, commit or push was
used.

## Fix round 2 — canonical browser TCP source endpoint

### Root cause

The fix-round-1 tuple was still only
`process|pid|destination_ip|destination_port`. `ProxyBridgeEvidence.psm1` did
not retain a structured local/source endpoint, so page and download connections
made by the same browser PID to the same origin collapsed into one tuple. A
timestamp or raw line cannot repair this because both identify observations,
not TCP connections.

### RED

Commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProxyBridgeEvidence.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolRunner.ps1
```

Results before production edits:

- `Test-ProxyBridgeEvidence.ps1`: exit `1`; the parsed structured route record
  had no `local_ip` property.
- `Test-ProtocolRunner.ps1`: exit `1` with aggregated `FIX ROUND 2 RED`:
  same PID plus distinct local ports incorrectly produced `HOLD_AMBIGUOUS`,
  while missing and string-valued local endpoints incorrectly produced `PASS`
  instead of `FAIL_HARNESS`.

The duplicate-observation fixture uses the same full connection tuple and
continued to produce `HOLD_AMBIGUOUS`, establishing the required discriminator.

### Repair

- A supported route line may now carry an explicit source endpoint as
  `from <local-ip>:<local-port> -> <destination>`. The parser retains
  `local_ip` and `local_port`, normalizes IP text through `IPAddress`, and
  validates the source port range. Legacy non-browser route and relay records
  remain parsed and receive empty/zero local fields rather than invented
  identities.
- Browser route evidence now fails as `FAIL_HARNESS` when the canonical local
  IP is absent or invalid, or when the local port is not an actual integer in
  `1..65535`.
- Browser connections are grouped by
  `process|pid|local_ip|local_port|destination_ip|destination_port`. The mock
  models page and download as the same browser PID with distinct local ports;
  repeated observations of the same full tuple still collapse.

### GREEN

Commands and results:

```powershell
PS> powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProxyBridgeEvidence.ps1
PASS: ProxyBridge route parser preserves canonical local endpoint evidence

PS> powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolRunner.ps1
PASS: fail-closed protocol runner lifecycle and assertions
```

Both commands exited `0`.

### Fix-round changed files

- `modules/ProxyBridgeEvidence.psm1`
- `tests/Test-ProxyBridgeEvidence.ps1`
- `modules/ProtocolRunner.psm1`
- `tests/Test-ProtocolRunner.ps1`
- this report

No browser, ProxyBridge/product process, listener, driver/service, SSH,
loopback/external network, commit or push was used. WebRTC/screen gates and
non-browser assertion behavior were not changed.

## Fix round 3 — plan-ruling correction for connection proof

This ruling supersedes the fix-round-2 claim that a ProxyBridge local endpoint
is required for browser verdicts. `docs/evidence-format.md` defines route
correlation by process, optional PID, destination, action and scoped lifetime;
it does not guarantee a local/source endpoint.

### Root cause

Fix round 2 incorrectly treated two internal route records as the proof of two
TCP connections and made an invented `from <local-endpoint>` extension
mandatory. The authoritative page/download server records already expose the
client-side ephemeral ports as `remote_port`, which is the supported evidence
that the origin observed two separate connections.

### RED

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolRunner.ps1
```

Result: exit `1` with aggregated `FIX ROUND 3 RED`. Before the production
repair it observed:

- one expected-action route and duplicate observations of one route produced
  `HOLD_AMBIGUOUS` instead of `PASS`;
- the documented route format without a local endpoint, an absent optional
  local endpoint and a malformed optional local endpoint produced
  `FAIL_HARNESS` instead of `PASS`;
- equal page/download server `remote_port` values produced `PASS` instead of
  `HOLD_AMBIGUOUS`;
- a string-valued server `remote_port` produced `PASS` instead of
  `FAIL_HARNESS`;
- one wrong-action route with otherwise complete external evidence produced
  `HOLD_AMBIGUOUS` instead of `FAIL_PRODUCT`.

The same RED run also confirmed the already-correct boundaries: no route and a
wrong route with a missing download record both remained `HOLD_AMBIGUOUS`.

### Ruling implementation

- Exactly one page and one download record remain mandatory. Both server
  `remote_port` fields must be actual integers in `1..65535`, and their values
  must differ. Equal values cannot prove two origin-observed TCP connections
  and therefore add missing evidence rather than a harness/product error.
- Internal route evidence remains mandatory corroboration. One expected-action
  record is sufficient when it matches the browser basename, a verified
  process-tree PID, exact destination and scoped time window. Missing expected
  corroboration holds; expected and wrong actions together contaminate.
- One or more wrong-action records produce `FAIL_PRODUCT` only when the client,
  page, download, capture state and distinct origin connection ports are
  otherwise complete. Incomplete external evidence remains
  `HOLD_AMBIGUOUS`, subject to the established harness/contamination priority.
- Browser verdicts no longer read or validate route `local_ip`/`local_port`.
  The backward-compatible parser extension from fix round 2 remains optional,
  while generated browser mock routes now use the documented legacy format.
- Fix-round-1 identity, content, path-probe, boolean cleanup and classification
  validation is unchanged. Non-browser assertions are unchanged.

### GREEN

Command and result:

```powershell
PS> powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolRunner.ps1
PASS: fail-closed protocol runner lifecycle and assertions
```

The command exited `0`.

### Fix-round changed files

- `modules/ProtocolRunner.psm1`
- `tests/Test-ProtocolRunner.ps1`
- this report

`modules/ProxyBridgeEvidence.psm1` and its focused test were not changed in
this round, so `Test-ProxyBridgeEvidence.ps1` was not rerun. No browser,
ProxyBridge/product process, listener, driver/service, SSH, loopback/external
network, commit or push was used.

## Fix round 4 — missing canonical server `remote_port`

Production already failed closed when a canonical browser-origin server record
lacked `remote_port`; the existing missing-field fixture removed only
`negotiated_protocol`. One focused fixture now removes `remote_port` from only
the `page` record and requires `FAIL_HARNESS` with no product errors.

### Mutation proof and GREEN

With unchanged production, the amended focused test exited `0`:

```text
PASS: fail-closed protocol runner lifecycle and assertions
```

A temporary fail-open mutation removed `remote_port` from the mandatory field
set, skipped its absent-value type/range rejection and allowed the missing port
through the connection-distinctness gate. The same command then exited `1`
with the new regression assertion:

```text
ASSERTION FAILED: missing page browser origin client port is a harness failure; expected='FAIL_HARNESS' actual='PASS'
```

`modules/ProtocolRunner.psm1` was restored exactly; its SHA-256 before and after
the mutation was
`fcabb51aac6fecc12096ab47abe1e17ce746677786503ab6781d0f44cf4cad6e`.
The final focused command was:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProtocolRunner.ps1
```

It exited `0` with:

```text
PASS: fail-closed protocol runner lifecycle and assertions
```

### Fix-round changed files

- `tests/Test-ProtocolRunner.ps1`
- this report

No production file remains changed by this fix round. No browser,
ProxyBridge/product process, listener, driver/service, SSH, network, commit or
push was used.
