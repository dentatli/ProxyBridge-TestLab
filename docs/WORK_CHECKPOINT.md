# Work checkpoint

## Current resume point (2026-09-07, Task 3a isolated profile constructor)

The offline isolated-profile constructor slice is complete and independently
reviewed CLEAN. See `task-3a-profile-report.md` and `task-3a-profile-review.diff`
under `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN`.

- New `modules/NegativeProxyProfile.psm1` and targeted PS5.1 test
  `tests/Test-NegativeProxyProfile.ps1`: RED/GREEN, review repair RED/GREEN.
- One exact TCP PROXY rule, fresh profile/config identity and generated
  credentials; no operator configuration/template input. Canonical IPs and
  reserved managed-server ports. Ordinary ProfileAdapter remains untouched.
- Pure private in-memory output, no generated file or runtime integration.
  `runtime_authorized=false`; construction is not readiness proof.

Next: signed semantic receipt contract and its negative/offline fixtures,
followed by derived readiness, orchestration and no-fallback/cleanup assertions.
Bind profile GUID, run and attempt alongside numeric config ID. Wire the new
constructor only behind complete receipt validation; never publish its private
profile object in reports. Keep both negative scenarios CAPABILITY_GATED and
`isolated_proxy_negative_target=false`. Do not redo accepted foundation/profile
slices. All offline/no-commit/no-push restrictions and approved Windows plus
separate Linux architecture remain in force. Task 3a is still incomplete.

## Current resume point (2026-09-07, Task 3a Fix round 2 accepted)

Milestone 16 remains active. Fix round 2 is complete for the unpromoted
negative-proxy semantic foundation only; do not repeat its implementation or
already-passing tests. The topology clarification below remains authoritative.

- Regenerated `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-3a-review.diff`
  mechanically from exact hash-verified pre-task baselines: 11 scoped files,
  8 changed. Complete module and fixture changes are included. See the adjacent
  `rebuild-task-3a-review.py` and `task-3a-review-provenance.md` for provenance.
- Primary `git apply --numstat` succeeded. Independent read-only review was
  CLEAN: all 11 current scoped files match the after manifest and
  `git apply --reverse --check` succeeds against current source.
- No production source edits, repeated tests, build, runtime/network, deployment,
  commit or push occurred in this repair-package pass.

Next: continue Task 3a with test-first isolated run-owned profile and signed
semantic receipt contracts, then derived readiness, orchestration and fail-closed
evidence/cleanup assertions, following the existing brief. Keep
`isolated_proxy_negative_target=false` and both negative-proxy scenarios
`CAPABILITY_GATED` until the complete contract is reviewed. No runtime proof is
claimed. Preserve all existing work and offline restrictions. Superpowers is not
the workflow; grill-me is only for separately requested quizzes.

The September 3 section below is historical; its unfinished-diff blocker is now
resolved. Task 3a as a whole and Milestone 16 are not complete.

## Approved architecture clarification (2026-09-07)

The user approved one Windows + separate Linux deployment model. Windows hosts
TestLab, ProxyBridge and generators; Linux hosts the managed SOCKS5 proxy,
protocol receivers and metrics. Windows VM + Linux VM is the primary topology;
LAN and VPS deployments use the same model. There are no separate Lab/Remote
modes. Local-only and Windows-colocated proxy coverage are explicitly excluded.
Configuration and preparation remain UI-driven with key-only SSH. Gate tests on
observed network capabilities. See section 3 of FULL_INTERNET_TRAFFIC_PLAN.md.

This turn records the design only. No implementation, verification or runtime
acceptance is implied. The unfinished Task 3a Fix round 2 continuation below
remains the development resume point. Superpowers is no longer the requested
workflow; preserve its historical reports as evidence. Use grill-me for optional
read-only code-understanding quizzes, not as an implementation workflow.

## Current resume point (2026-09-03, proactive usage-limit checkpoint)

The user asked to begin checkpointing while the usage window was low. Preserve
the dirty working tree exactly. Do not commit/push, start the UI, deploy the
endpoint, or run a real browser, ProxyBridge, client, driver/service, SSH,
listener, loopback, systemd or external-network traffic merely to resume.

### Authoritative milestone state

- The original roadmap remains Milestones 14-20. SDD Task numbers are only
  internal review-sized slices and do not replace project milestone numbering.
- Milestone 14 remains complete and was not redone.
- Milestone 15 is complete and accepted. Task 1 browser lifecycle, Task 2a
  browser origin, Task 2b-core evidence/route assertions and Task 2b-UI derived
  capability/readiness integration passed their focused gates and independent
  review. The final bounded Milestone 15 offline gate passed 9/9 after one
  environment-only retry; only `canary-browser-download` was promoted. No real
  browser or product correctness is claimed.
- Milestone 16 is active as SDD Task 3, executed serially as 3a isolated
  negative proxy, 3b receipt-bound backend restart, and 3c TestLab-owned network
  impairment. Existing executable `failure-dns`,
  `failure-client-process-exit`, and `tcp-process-termination` are preserved and
  are not being reimplemented.

### Active Task 3a state

- `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-3a-negative-proxy-brief.md`
  defines the scope and safety contract. The first implementer was lost at the
  usage reset before RED or code changes; the resumed implementer started from
  that exact point.
- An unpromoted semantic foundation is present:
  `src/server_agent/negative_proxy.py`, disabled protocol configuration,
  immutable bundle inclusion, a distinct reserved unavailable port, fail-closed
  config validation and focused offline tests. There is no negative-proxy bind
  path or listener.
- Initial RED was captured by `tests/Test-FailureControl.ps1` with the expected
  missing `negative_proxy` module. GREEN then passed. The affected ServerProbe
  build passed with 0 warnings/errors and `tests/Test-ServerProvisioning.ps1`
  passed after its synthetic repository included the new immutable artifact.
- Initial independent review was NOT APPROVED. Fix round 1 corrected the real
  PLANNED-plugin catalog break, exact staging self-test mismatch, valid SOCKS5
  multi-method parsing, password-dependent principal digest, false declarative
  UNBOUND wording, both-port collision validation and missing protocol-fixture
  export. Focused failure-control and provisioning checks then passed.
- Fix round 1 re-review confirmed the production safety corrections but did not
  approve the review package: its incremental diff omitted current code and the
  failure-control fixture, the manifests omitted a changed provisioning test,
  the unavailable-port collision lacked its own regression, and report wording
  overstated semantic `relay_count=0` as runtime proof.
- Fix round 2/5 reached a safe checkpoint. The independent unavailable-port
  collision regression was added and `tests/Test-FailureControl.ps1` passed;
  comparable manifests now include the changed provisioning test and the report
  correctly limits `relay_count=0` to evaluator intent rather than runtime
  proof. The exact complete incremental Task 3a review diff is still unfinished,
  so Fix round 2 and the foundation are not accepted. The loopback
  `tests/Test-ProtocolVerticalSlice.ps1` remains deliberately NOT RUN because it
  starts a listener and traffic prohibited by this offline slice; export
  inclusion is covered statically instead.

### Truthful capability state and remaining blocker

- `isolated_proxy_negative_target` remains false.
- `failure-proxy-unavailable` and `failure-proxy-auth` remain
  `CAPABILITY_GATED`.
- Task 3a is not complete. Promotion still requires a run-owned isolated
  `.pbprofile`, signed semantic/listener-or-unbound/rollback receipt, safe
  orchestration, exact PROXY config identity, complete real-destination
  zero-delivery evidence, no-fallback assertions and cleanup proof. Absence of
  endpoint payload alone can never prove a negative-proxy PASS.

### Exact continuation order

1. Regenerate the exact complete Task 3a incremental review diff, including all
   current `negative_proxy.py` and failure-control fixture lines. Then obtain a
   fresh independent CLEAN re-review of the unpromoted foundation; do not rerun
   already-passing tests merely to regenerate review evidence.
2. Continue Task 3a with TDD for the run-owned profile, signed semantic receipt,
   derived capability/readiness, orchestration and fail-closed assertions.
   Promote the two scenarios only after the complete offline contract passes
   and is independently reviewed.
3. Continue Milestone 16 serially with Task 3b backend restart and Task 3c
   namespace-local bounded impairment. Privileged actions must remain inside a
   generated UI-reviewed, allowlisted, receipt-bound plan with verified cleanup.
4. Continue the approved roadmap in order: Milestones 17, 18, 19 and 20. Do not
   redo accepted work.

No prohibited runtime/network action, commit or push was performed in this
continuation.

## Current resume point (2026-09-01, later user-requested limit stop)

Work stopped immediately when the user reported that the usage limit was
ending. Preserve the dirty working tree exactly. Do not commit/push, start the
UI, deploy the endpoint, or run a real browser, ProxyBridge, client,
driver/service, SSH, listener, loopback or external-network traffic merely to
resume.

### Project milestone numbering (authoritative)

The project plan is still Milestones 14-20. The SDD `Task` names below are
internal review-sized slices, not a replacement roadmap:

| SDD slice | Project milestone | Meaning |
|---|---|---|
| Task 1 | Milestone 15 | isolated real-browser worker and Windows process-tree lifecycle |
| Task 2a | Milestone 15 | controlled server browser-origin and immutable provisioning artifact |
| Task 2b-core | Milestone 15 | worker registry, scenario, execution plan, route/evidence assertions and mocks |
| Task 2b-UI | Milestone 15 | automatically derived browser/server capability, selection readiness and final offline browser slice |
| Task 3 | Milestone 16 | remaining safe failure injection and isolated negative-proxy/impairment integration |
| Task 4 | Milestone 17 | native performance runner, synchronized metrics and bounded soak orchestration |
| Task 5 | Milestone 18 | optional LAN peer receipt/topology gate |
| Task 6 | Milestone 19 | run profiles, restart-safe resume, typed metrics and readable UI/reporting |
| Tasks 7-8 | Milestone 20 | offline audit, isolated-VM acceptance preparation and final verification |

Milestone 14 was already completed in the approved baseline and is not being
redone. Current work is therefore still **Milestone 15**, split only so each
load-bearing interface gets its own TDD and review gate.

### Completed and accepted in Milestone 15

- Task 1 browser worker/process lifecycle is complete after its recorded
  breaker adjudication and focused `tests\Test-BrowserPlugin.ps1` PASS.
- Task 2a browser origin is complete: marker compatibility, truthful ALPN,
  Transfer-Encoding fail-closed behavior and the complete `/browser-origin`
  namespace were reviewed CLEAN. The primary focused browser-origin and server
  provisioning tests passed.
- Task 2b-core is now complete. The final evidence contract proves the two
  closed browser TCP connections with distinct canonical server
  `remote_port` values and uses a verified product route as mandatory
  corroboration. Missing route remains HOLD, mixed actions remain
  CONTAMINATED, and incomplete external evidence cannot become a product
  verdict.
- Fix round 4 added the formerly missing `remote_port` mutation. It produces
  exact `FAIL_HARNESS`, excludes product errors, and was mutation-proven to fail
  under a temporary production validation bypass. Production was restored
  unchanged. The primary agent independently observed
  `PASS: fail-closed protocol runner lifecycle and assertions`; the scoped
  re-review returned CLEAN.
- Only `canary-browser-download` is promoted. WebRTC and screen sharing remain
  capability-gated. Detailed evidence is in the Task 1/2a/2b-core reports,
  snapshots and review diffs under
  `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/`.

### Active but interrupted: Task 2b-UI / Milestone 15

- The implementation contract is fixed in
  `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-2b-ui-brief.md`; the exact
  pre-change files are in `task-2b-ui-before`.
- TDD tests were started but the implementer was interrupted before production
  work and before writing `task-2b-ui-report.md`:
  - `ui/ProxyBridge.TestLab.Ui.RunProbe/Program.cs` now contains offline tests
    for `DerivedRunCapabilitySnapshot`, `RunCapabilityReadiness` and
    `RunCapabilityDocument`;
  - `tests/Test-RunOrchestration.ps1` now asserts that the public settings/UI
    surface exposes no manual browser path or SHA/hash control.
- No Task 2b-UI production file changed. In particular,
  `ui/ProxyBridge.TestLab.Ui/Services/RuntimeCapabilityService.cs` does not yet
  exist. The added RunProbe tests deliberately reference the not-yet-created
  production types and therefore represent the pending RED state.
- No focused build/test result was returned before interruption; do not claim
  RED execution or GREEN. No verification was run after the stop request.

### Exact continuation order

1. Do not redo Task 1, Task 2a or Task 2b-core. Resume the interrupted
   `browser_ui_implementer` task from the existing test edits and
   `task-2b-ui-brief.md`.
2. If strict RED was not actually captured before interruption, build the
   existing UI/RunProbe projects as required and run only
   `tests\Test-RunOrchestration.ps1` once to record the RED. Then implement the
   smallest shared derived-capability service and rerun only that focused test
   for GREEN.
3. Complete Task 2b-UI, still inside Milestone 15: derive
   `local_browser_runtime` only from allowlisted local image/version/hash and
   `server_browser_origin` only from a current receipt-verified server state;
   expose selection-aware English readiness without adding manual browser
   path/hash fields or `.env` setup. Use the same derived state for readiness,
   real-run capabilities and immutable preflight capabilities.
4. Create the narrow Task 2b-UI review diff/report, obtain an independent CLEAN
   review, then run the bounded final Milestone 15 offline gate and accept only
   `canary-browser-download`. Real browser/ProxyBridge correctness remains a
   later explicitly authorized isolated-VM acceptance run.
5. Continue the original roadmap in order: Milestone 16, 17, 18, 19 and 20.
   The internal Task 3-8 labels are only the review slices shown in the table
   above.

To resume, say: `Продолжи по верхнему checkpoint в docs/WORK_CHECKPOINT.md;
мы всё ещё завершаем Milestone 15, продолжи Task 2b-UI с текущего TDD RED.`

## Current resume point (2026-08-31, user-requested limit stop)

Work stopped immediately when the user reported that the usage limit was
ending. The only active Task 2a fix subagent was interrupted. It had not
changed any scoped implementation or test file after the review snapshot; the
current scoped files still match `task-2a-after`. Preserve the dirty working
tree. Do not commit/push, start the UI, deploy the endpoint, or run a real
browser, ProxyBridge, driver/service, SSH, or external-network traffic merely
to resume.

### Completed and independently verified

- Task 1, the isolated browser worker, is complete. Five delegated fix rounds
  exhausted the review breaker; the primary agent then adjudicated the two
  remaining load-bearing findings with a failing regression and a narrow
  repair. CRT descriptors transferred by `open_osfhandle` are now explicitly
  owned through reader construction and independently closed on failure. The
  Job-containment fixture no longer allows fallback process termination to
  mask a broken Job.
- The primary post-adjudication command
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1`
  passed with `PASS: isolated browser worker core`.
- Task 1 evidence is preserved in `task-1-after-adjudication` and
  `task-1-adjudication-review.diff`; the ledger and
  `task-1-browser-worker-report.md` record the breaker ruling. Do not redo
  Task 1.
- Task 2a's first implementation integrated exact versioned browser-origin
  page/download routing, deterministic evidence, runtime bundling and plugin
  registration. The primary agent independently observed:
  `PASS: browser-origin` and `PASS: guarded offline server provisioning`.
  Its scoped baseline/current snapshots and review package are
  `task-2a-before`, `task-2a-after`, and `task-2a-review.diff`.

### Open Task 2a review findings — implementation is not accepted yet

1. `browser_origin.py` emits `PROXYBRIDGE_TESTLAB_BROWSER_RESULT_V1`, while the
   completed browser worker requires `PB_TESTLAB_BROWSER_READY`. The test only
   checked the initial placeholder, so a real completed page would fail with
   `BROWSER_DOM_MARKER_INVALID`.
2. The secure listener advertises ALPN `h2`, but its request parser accepts
   only HTTP/1.1. Chromium can therefore negotiate a protocol the listener
   cannot parse. Make ALPN truthful; do not fake HTTP/2 support.
3. Browser-origin GET currently ignores `Transfer-Encoding`; a chunked request
   can be treated as bodyless and emit successful evidence. It must fail
   closed with no success evidence.
4. Only `/browser-origin/` is reserved. Bare `/browser-origin` and its query
   variant can fall through to generic header-bound HTTP. Reserve the complete
   namespace while allowing success only for exact versioned paths.

The Task 2a fix-round-1 subagent was stopped before it changed the scoped
files. No fix-round RED/GREEN evidence exists yet.

### Exact continuation order

1. Do not rerun or redispatch Task 1. Resume Task 2a fix round 1 from the four
   findings above, within the existing Task 2a scope plus the already approved
   narrow ServerProbe fixture update.
2. Add focused regressions that fail on the current code: completed marker
   compatibility (not merely the placeholder), truthful ALPN, chunked browser
   request rejection with zero success evidence, and bare/query namespace
   rejection even with generic TestLab headers. Then make the minimum server
   and fixture changes.
3. Run only `tests\Test-BrowserOrigin.ps1` and
   `tests\Test-ServerProvisioning.ps1`, update
   `task-2a-browser-origin-report.md`, create the fix-round incremental diff,
   and dispatch a fresh read-only re-review. Do not accept Task 2a or promote
   `canary-browser-download` until review is clean.
4. After clean Task 2a review, continue Task 2b: worker registry,
   ProtocolRunner, exact route correlation, derived capabilities/readiness and
   truthful promotion of only `canary-browser-download`. WebRTC and screen
   sharing remain capability-gated until their genuine contracts exist.
5. Continue Tasks 3-8 in `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/progress.md`
   without redoing completed milestones. Real isolated-VM acceptance and soak
   remain separate authorized runtime work.

To resume, say: `Продолжи по верхнему checkpoint в docs/WORK_CHECKPOINT.md;
сначала заверши Task 2a fix round 1 и clean re-review.`

## Current resume point (2026-08-30, user-requested limit stop)

Work stopped immediately when the user reported 20% remaining in the current
five-hour usage window. The only active implementation subagent was
interrupted and is no longer running. Preserve the dirty working tree. Do not
redo Milestones 9-14, commit, push, start the UI, deploy the endpoint, or run
ProxyBridge/SSH/external-network traffic merely to resume.

### What happened in this continuation

- Superpowers SDD/TDD workflow and Serena navigation were resumed from the
  previous checkpoint. The task ledger is
  `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/progress.md`.
- Task 1 remained strictly limited to
  `src/protocol_worker/plugins/browser.py`,
  `tests/Test-BrowserPlugin.ps1`, and `tests/fixtures/browser/`.
- The original interrupted worker was observed RED because it passed fake-only
  `--testlab-*` switches. Its first Chromium-style repair reached the focused
  GREEN, but independent review correctly rejected it: a late child could
  escape the stale PID snapshot, caller arguments could add another URL,
  partial directory setup was unsafe, and the fixture checks were incomplete.
- Fix round 1 reached the focused GREEN. Re-review still rejected it because
  Job assignment happened after process execution began, Job cleanup failure
  could be overwritten, directory ownership was racy, and the exact URL was
  not enforced.
- Fix round 2 now contains a custom Windows suspended-launch path, intended
  order `CreateProcessW(CREATE_SUSPENDED) -> assign Job -> resume`, monotonic
  cleanup state, ownership-tracked profile/download directories, exact URL
  validation, Job query/close/assign/resume negative injections, and a
  timeout-safe focused-test driver cleanup path.
- The first Fix round 2 focused run hung and was interrupted. Systematic
  debugging localized it to the injected Job-assignment failure: the exact
  root remained suspended and unassigned while the old `taskkill /T` cleanup
  could block. The implementation was then changed to bounded direct
  `TerminateProcess` cleanup for known PIDs. A suspended unassigned root cannot
  have created a child.
- `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-1-browser-worker-report.md`
  currently contains a Fix round 2 PASS claim, but the primary agent did not
  observe that final run before interruption. Treat the claim as **unverified**
  and do not accept Task 1 from it.
- Independent review artifacts are preserved under
  `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/`: `task-1-before`, `task-1-after`,
  `task-1-after-fix1`, `task-1-review.diff`, and
  `task-1-fix1-review.diff`.
- A future server-side brief was prepared at
  `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-2a-browser-origin-brief.md`.
  It has not started and no shared manifest/server/UI file was changed for it.
- No real browser, ProxyBridge product, driver/service, SSH, endpoint
  deployment, external network, commit, or push was performed in this
  continuation.

### Exact continuation order

1. Before running anything, inspect only the exact prior fixture process names
   if needed to prove the interrupted diagnostic left no test-owned process.
   Do not perform a general process audit.
2. Run exactly once:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1`.
   If it hangs or fails, use the bounded test-driver cleanup and continue
   systematic debugging from the suspended assign-failure path. Do not weaken
   the assertions or revert to `taskkill /T` in production cleanup.
3. If the focused test is GREEN, create a Fix round 2 incremental diff from
   `task-1-after-fix1` to the current scoped files and dispatch a read-only
   re-review. The reviewer must verify atomic suspended assignment/resume,
   monotonic Job/handle cleanup, exact-PID termination, ownership-safe
   directory cleanup, exact URL/flag enforcement, and no false PASS.
4. Only after a clean re-review mark Task 1 complete in the SDD ledger. Then
   begin Task 2a from its brief. Do not promote `canary-browser-download`
   before the full browser-origin/runner/route/UI offline vertical slice.
5. Continue Tasks 2-8 in the existing ledger order. Real isolated-VM
   correctness and long soak remain separately evidenced acceptance runs; an
   offline test must never claim they passed.

To resume, say: `Продолжи по верхнему checkpoint в docs/WORK_CHECKPOINT.md;
сначала заверши Task 1 Fix round 2 и re-review.`

## Current resume point (2026-08-30, usage-limit pause)

Work stopped immediately at the user's request. The three active subagent tasks
were stopped; no background implementation should be assumed to continue after
this checkpoint. Preserve the dirty working tree. Do not redo Milestones 9-14,
commit, push, start the UI, deploy the endpoint, or run ProxyBridge/SSH/network
traffic merely to resume.

### Completed and checked in this continuation

- The stale M12-M16 checkpoint gate was executed before new work. Catalog,
  protocol-worker, protocol runner, server provisioning, UI shell and the
  M12-M16 offline vertical slice all passed.
- All 15 remaining `DECLARATIVE_ONLY` entries were moved to explicit, truthful
  capability gates rather than being presented as implemented traffic. Current
  catalog inventory is 205 total: 171 `EXECUTABLE`, 0 `DECLARATIVE_ONLY`, 22
  `CAPABILITY_GATED`, 5 `SYSTEM_CHECK`, and 7 `UNSUPPORTED_PRODUCT_SCOPE`.
  `tests/Test-Catalog.ps1` was observed RED before the catalog change and PASS
  after it.
- `config/capabilities.json` now names the missing browser, browser-origin,
  WebRTC-peer, synthetic-media, negative-proxy, restart-control, performance
  worker/origin, server-window and local-product-metric capabilities. They are
  disabled until their real readiness evidence exists.
- Automatic browser discovery was added to
  `ui/ProxyBridge.TestLab.Ui/Services/LocalArtifactService.cs`. It uses only a
  fixed Edge/Chrome/Chromium candidate list and derives path, version and image
  hash for the run-owned environment; there is no UI or `.env` browser-path
  field. The RunProbe test was observed RED before implementation. The Release
  build then passed and `tests/Test-RunOrchestration.ps1` passed. One nullable
  warning remains at `LocalArtifactService.cs` around the browser basename
  assignment and should be removed before the next build.
- The pure receipt-bound restart-control core is present in
  `src/server_agent/failure_control.py`, with an injected adapter and no direct
  systemd/network capability. `tests/Test-FailureControl.ps1` passed offline.
- The deterministic browser-origin core is present in
  `src/server_agent/browser_origin.py`. `tests/Test-BrowserOrigin.ps1` passed
  offline. It is not yet wired into the endpoint listener or provisioning
  manifest.
- The isolated native performance-worker source/build contract is present in
  `src/pb_perf_client.c`, `scripts/Build-PerformanceHarness.ps1` and
  `tests/Test-PerformanceWorker.ps1`. No C compiler was available; the test
  therefore completed only the explicit source/argument validation gate and
  did not claim a binary self-test.
- No product process, driver/service, SSH, server deployment, external network,
  commit or push was performed.

### Interrupted work that is not validated

- `src/protocol_worker/plugins/browser.py`, `tests/Test-BrowserPlugin.ps1` and
  `tests/fixtures/browser/` are a work in progress. The first draft incorrectly
  depended on fake-browser-only command-line flags. Review feedback required a
  real Chromium-supported surface (`--dump-dom` plus a bounded virtual-time
  budget and controlled-page marker), bounded actual-image probing, and all
  `browser-session` evidence fields. The subagent was interrupted while making
  that repair. Do not promote `canary-browser-download` to `EXECUTABLE` or trust
  this test until the implementation and test are reviewed and rerun.
- `tests/Test-PerformanceOrigin.ps1` exists in RED/incomplete state, but
  `src/server_agent/performance_origin.py` and its fixture were not created
  before the subagent was interrupted. Continue from the failing test; do not
  delete or silently weaken it.
- The new browser/failure/performance cores are not registered in shared
  manifests, endpoint artifacts, PowerShell dispatch, capability generation,
  reports, packaging or `tests/Run-All.ps1` yet.

### Exact continuation order

1. Review the interrupted browser worker diff. Replace every fake-only browser
   flag with the real controlled-page/DOM-output contract, add bounded observed
   image probing and process-tree cleanup evidence, then run only
   `tests/Test-BrowserPlugin.ps1`.
2. Integrate browser-origin and browser-worker through the protocol manifest,
   server plugin manifest/artifact builder, endpoint listener, ProtocolRunner,
   process-tree route correlation, automatically derived capability file and
   selection-aware UI readiness. Promote only `canary-browser-download` after
   the complete offline vertical slice passes. Keep WebRTC and screen-sharing
   gated until a genuine remote `RTCPeerConnection` contract exists.
3. Review and integrate `failure_control.py` only through a generated,
   allowlisted, receipt-bound privileged adapter. The negative-proxy and restart
   scenarios remain gated until the run-owned proxy/profile and rollback
   evidence contracts are complete.
4. Complete the already-written failing performance-origin test, then review
   the native worker. Do not enable performance scenarios until an x64 binary
   passes integrity/calibration self-test and synchronized local/server metric
   windows are implemented.
5. Continue Milestones 18-20 in the approved order: LAN-peer receipt gate;
   restart-safe run-profile/resume and typed metric UI; offline audit and
   isolated-VM acceptance preparation.
6. Update catalog counts only as complete gates become executable. Finish with
   the planned targeted tests, one final `tests/Run-All.ps1`, syntax/diff/gating
   checks and concise milestone reports. Real VM correctness and the 24-hour
   soak remain separate, explicitly authorized acceptance runs.

To resume, the user can simply say: `Продолжи по docs/WORK_CHECKPOINT.md с
пункта 1, не переделывая завершённое.`

## Current resume point (2026-08-29, latest pause)

Work was paused immediately at the user's request because the usage window was
ending. Preserve the current dirty working tree. Do not commit, push, restart
the UI, deploy the endpoint, or run ProxyBridge/SSH/external-network traffic
when resuming unless the user explicitly changes the approved plan.

### Completed and verified in the latest continuation

- Milestone 14 protocol work is complete: FTP/FTPS, SMTP/SMTPS, IMAP/IMAPS,
  POP3/POP3S, MQTT/MQTTS, AMQP/AMQPS, NTP, IRC/IRCS and controlled multi-peer
  transactions have client/server evidence contracts and passed the local
  loopback vertical slice. SFTP remains an explicit capability gate; FTP is not
  used as a substitute for SSH/SFTP.
- Milestone 15 controlled realtime work is present for STUN Binding, TURN
  Allocate, authenticated encrypted RTP/RTCP media and registered receive-only
  UDP. The M12-M15 loopback slice passed. Real browser/WebRTC coverage is not
  implemented and must not be claimed by synthetic UDP traffic.
- Milestone 16 controlled DNS SERVFAIL and supervised client-process
  termination are implemented. `failure-dns`, `failure-client-process-exit`
  and `tcp-process-termination` are executable protocol-worker scenarios.
- The Windows process-termination fixture was repaired so a TCP reset produced
  by `TerminateProcess` is accepted as disconnect evidence only after the full
  framed payload and its SHA-256 have already been validated. The updated
  M12-M16 protocol loopback vertical slice passed once:
  `PASS: Milestones 12-16 protocol loopback vertical slice`.
- A stale diagnostic Python process and only its exact
  `.failure-debug-f88949a1c88e497d9197cf67b981b7c6` directory were removed.
- No real ProxyBridge GUI/CLI, driver, SSH, endpoint deployment or external
  network test was run in this continuation.

### Latest edits not yet revalidated as a group

- `src/server_agent/failure_protocols.py` contains the Windows RST/EOF repair.
- `tests/Test-Catalog.ps1` was updated to the current expected catalog counts
  and to require the three completed Milestone 16 scenarios to be executable.
- `tests/Test-ProtocolWorker.ps1` now expects 19 implemented worker plugins.
- Those two updated targeted tests and the broader suite were **not run after
  the final expectation edits**, because work stopped immediately on request.
- Current catalog inventory measured immediately before the pause is:
  205 total, 171 `EXECUTABLE`, 15 `DECLARATIVE_ONLY`, 7 `CAPABILITY_GATED`,
  5 `SYSTEM_CHECK`, and 7 `UNSUPPORTED_PRODUCT_SCOPE`.

### Remaining 15 declarative scenarios

- Browser/realtime: `canary-webrtc`, `canary-screen-sharing`,
  `canary-browser-download`.
- Failure injection: `failure-proxy-unavailable`, `failure-proxy-auth`,
  `failure-backend-restart`, `udp-backend-restart`.
- Performance: `performance-latency`, `performance-throughput`,
  `performance-cpu`, `performance-memory`, `performance-handles`,
  `performance-threads`, `performance-flow-rate`,
  `performance-datagrams-per-second`.

The approved plan requires honest evidence. A real Chromium/browser adapter,
an isolated negative proxy, synchronized endpoint restart control, a native
performance generator and product/server metric windows must be implemented or
explicitly capability-gated. Do not relabel a synthetic approximation as real
browser, WebRTC, proxy-failure or performance coverage.

### Exact next actions

1. Run the narrow current-state checks: catalog, protocol-worker, protocol
   runner, server provisioning, UI shell and the M12-M16 vertical slice. Repair
   any stale count/fixture expectation before adding more functionality.
2. Finish Milestone 16: isolated negative-proxy and restart contracts, then
   TestLab-owned bounded impairment controls with rollback evidence. Keep all
   privileged actions inside the generated UI-reviewed server plan.
3. Finish Milestone 15 browser-dependent work with automatic browser discovery,
   an isolated profile/process tree and real browser-observed evidence. If no
   supported browser exists, return `SKIPPED_CAPABILITY`; never substitute the
   requested executable path for the observed process image.
4. Finish Milestone 17 with the native performance worker, same-run DIRECT
   baseline, synchronized local/server samples, bounded soak/cancellation and
   post-load recovery. Then complete optional Milestone 18 LAN-peer gating.
5. Complete Milestone 19 restart-safe resume, UI run-profile selection,
   readable per-test metrics/log explanations and sanitized export. Complete
   Milestone 20 offline audit and isolated-VM acceptance preparation last.
6. Only after all gates pass, update milestone reports and the final catalog
   counts. Commit and push remain prohibited.

---

## Current resume point (2026-08-29)

Work is intentionally paused at the user's request. Preserve the current dirty
worktree; do not commit, push, restart the UI, or run a live server/network gate
while resuming this checkpoint.

### Completed since the previous checkpoint

- Milestone 13 has a complete local vertical slice for HTTP/2, gRPC,
  WebSocket/WSS, QUIC/HTTP/3 and WebTransport, including client plugins,
  server listeners, catalog entries, runner integration and offline bundled
  dependencies.
- The last completed M13 checks passed: catalog, protocol runner lifecycle and
  assertions, the DNS/TLS/HTTP/1.1 plus M13 loopback vertical slice, UI shell,
  guarded offline server provisioning, and the Release UI/probe builds with
  zero warnings and zero errors.
- One first-run M13 vertical-slice invocation returned a transient
  `PROTOCOL_SERVER_ERROR UNEXPECTED_FAILURE`; the immediate bounded
  reproduction and the next targeted run passed. Repeat and investigate this
  before declaring M13 final so that a flaky startup cannot be hidden.

### In progress and not yet validated

- Milestone 14 source work has started for FTP/FTPS, SMTP/SMTPS, IMAP/IMAPS,
  POP3/POP3S, MQTT/MQTTS, AMQP/AMQPS, NTPv4, IRC/IRCS and a controlled
  two-peer TCP relay. SFTP remains explicitly capability-gated because a real
  SSH host-key and SFTP-subsystem contract is not implemented.
- The new M14 Python sources, server catalog/configuration, UI artifact builder,
  runner profiles and scenario catalog are present, but M14 is **not complete**.
- Initial Python/PowerShell/JSON static checks passed before the latest
  multipeer stream-lifetime fix. That fix has not been rechecked.
- The bundled protocol worker is stale relative to the M14 sources. C# has not
  been rebuilt after the M14 changes. Catalog counts and the vertical-slice
  fixture still reflect M13, and no M14 loopback transaction has run.
- The UI development process was stopped deliberately to release a locked DLL
  and has not been restarted. No live server gate was retried in this segment.

### Exact next actions

1. Re-run the bounded static checks after the latest multipeer fix.
2. Inspect and complete the SecurityProbe/ServerProbe M14 fixtures, then build
   the C# projects once.
3. Rebuild the offline protocol-worker bundle from the pinned dependencies.
4. Update the vertical-slice fixture for 25 listeners and add real M14
   transactions, including fail-closed negative cases.
5. Run and, where lifecycle stability requires it, repeat the targeted M13/M14
   checks; investigate the recorded transient M13 startup failure.
6. Recount and update catalog/UI expectations and documentation only after the
   executable M14 paths pass.
7. Proceed to Milestone 15 only after Milestone 14 is fully green.

Commit and push have not been performed.

---

Timestamp: 2026-08-28  
State: Milestones 9-11 complete; Milestone 12 offline gate passed; server discovery is `PLAN_READY`

## Authoritative state

- `docs/FULL_INTERNET_TRAFFIC_PLAN.md` remains the approved autonomous plan
  through Milestone 20. Continue without requesting approval between milestones,
  but keep every runtime action behind its declared readiness and evidence gate.
- Milestones 9 and 10 are complete: protocol contracts, the dependency-locked
  worker SDK, the offline bundle builder and their dependency-free tests exist.
- Milestone 11 is complete: the Debian/Ubuntu systemd server plugin catalog,
  agent, provisioning plan, trust/preflight handling, report and server tests
  are present.
- Milestone 12 server-side DNS, TLS, HTTP and HTTPS vertical slices are present:
  `pb_protocol_server.py`, fixed TestLab-owned ports, locally generated TLS
  material, server plugin declarations and provisioning/listener verification.
- Milestone 12 client-side DNS, TLS and HTTP/1.1 workers are implemented. A
  no-response expectation now produces explicit bounded evidence, while an
  unexpected response fails closed.
- The catalog/UI plumbing now carries `executor_kind`, `protocol_family` and
  `evidence_profile_id`; a selected protocol-worker test has a dedicated local
  runtime readiness gate.
- Automatic runner environment materialization now exposes protocol worker,
  manifest, evidence contract and CA paths with internally computed hashes.
  These hashes remain hidden from human settings fields.
- Runtime preflight optionally validates every protocol artifact when the
  protocol runtime is present, without adding Python to global process cleanup.
- `ProtocolRunner.psm1` and `Run-WfpMatrix.ps1` now execute protocol-worker
  plans through standard evidence filenames. DIRECT, BLOCK and PROXY mock
  integration passes without treating a complete zero-record BLOCK capture as
  missing evidence.
- A separate protocol-worker actual-path probe timeout and exact five-artifact
  prelaunch validation keep the CLI lifecycle contract unchanged.
- The protocol CA is persisted as a public PEM; the server private key remains
  inside the protected certificate store and server bundle only.
- The NTP default moved to port 42132 because 42123 overlapped the declared FTP
  passive range. The port catalog now rejects overlaps.
- No PowerShell test listener remains. The old `TcpListener` source that caused
  a Windows Firewall prompt was removed; ephemeral loopback ports are allocated
  by the isolated Python fixture server. The user can safely choose Cancel if a
  prompt from an already-running old test is still visible.
- No ProxyBridge GUI/CLI, driver action, external client or real traffic matrix
  has been run in this continuation.
- A private test server was reached with the configured SSH key. Windows
  `ssh-keyscan` failed on the server's newer KEX preference, so the UI now uses
  a protected, authenticated, ephemeral `known_hosts` fallback and deletes it
  after extracting the public host key. The user independently confirmed the
  first-use host identity; read-only discovery then verified supported Ubuntu,
  systemd, non-interactive sudo, Python and sufficient disk. The endpoint is not
  installed yet and the guarded workflow is now `PLAN_READY`. Private target,
  user, key path and fingerprint are deliberately absent here.
- Protected non-password fields now use text inputs with autocomplete disabled;
  they no longer trigger browser password-storage prompts.
- Environment Setup now presents five ordinary sections and groups timeouts,
  retention, interface values and technical ports under Advanced. SOCKS5 and
  Test network purposes are explained in user language. Async settings/server
  actions disable on the first click, reject repeat clicks and show a spinner
  plus an operation label until completion.
- Commit and push were not performed.

## Last completed checks

- PowerShell syntax: PASS (136 `.ps1`/`.psm1` files).
- Release UI/ServerProbe builds: PASS, 0 warnings, 0 errors.
- `tests/Run-All.ps1`: PASS (26/26 targeted tests under Windows PowerShell 5.1).
- `tests/Test-ProtocolMatrixIntegration.ps1`: PASS for the selected protocol
  DIRECT/BLOCK/PROXY orchestration path.
- Release UI build after the settings UX repair: PASS, 0 warnings, 0 errors.
- `tests/Test-UiSettings.ps1`: PASS after password-manager and repeat-click
  prevention plus the simplified settings projection.
- `tests/Test-ServerProvisioning.ps1`: PASS after the compatible host-key
  discovery fallback.
- Local bundled CPython 3.11 x64 protocol worker: 722 files, self-test PASS.

## Exact continuation point

1. Create and review the UI-generated exact server plan.
2. Apply it, and require matching hashes,
   plugin self-tests, active/enabled systemd state and every declared listener.
3. Run the authorized protocol-only server smoke without ProxyBridge, then
   complete `docs/MILESTONE_12_REPORT.md`.
4. Continue Milestones 13-20 in order, stopping on any false-positive risk,
   missing mandatory evidence or cleanup contamination.

## Files most recently edited at the pause

- `modules/Env.psm1`
- `modules/RuntimeEnvironment.psm1`
- `modules/ScenarioCatalog.psm1`
- `scripts/Export-UiCatalog.ps1`
- `src/protocol_worker/plugins/common.py`
- `src/protocol_worker/plugins/dns.py`
- `src/protocol_worker/plugins/tls.py`
- `src/protocol_worker/plugins/http1.py`
- `tests/Test-ProtocolVerticalSlice.ps1`
- `ui/ProxyBridge.TestLab.Ui/Models/CatalogScenario.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/LocalArtifactService.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/RunReadinessService.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/SettingsSchema.cs`
- `ui/ProxyBridge.TestLab.Ui/wwwroot/app.js`
- `ui/ProxyBridge.TestLab.Ui/wwwroot/index.html`
- `ui/ProxyBridge.TestLab.Ui/wwwroot/styles.css`
- `tests/Test-UiSettings.ps1`
- `ui/ProxyBridge.TestLab.Ui.ServerProbe/Program.cs`
- `ui/ProxyBridge.TestLab.Ui.SecurityProbe/Program.cs`
