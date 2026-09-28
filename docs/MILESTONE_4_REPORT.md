# Milestone 4 report

Status: complete  
Effort: Very High

## Delivered

- English Run Builder with suite/protocol/family/action/socket/known-defect
  filters and explicit scenario selection.
- Dry review API that accepts only public mode and scenario IDs.
- Persisted single-worker job queue with the documented state transitions,
  progress snapshots, SignalR publication and polling fallback.
- One-active-real-run lease enforcement in the controller lifecycle.
- Cooperative cancellation marker checked between runner scenarios; the current
  bounded operation retains its normal cleanup path.
- One bounded controller recovery only when the runner failed before evidence
  or runtime mutation.
- Controller-restart orphan handling that records `FAILED_TO_START` with
  `CONTROLLER_RESTART_INTERRUPTED` and never resumes runtime automatically.
- Fixture execution adapter using the authoritative PowerShell mock runner,
  generated controller-owned suite/capability overlays and app-private evidence.
- Live scenario progress, recovery count, state timeline, cancellation and links
  to completed sanitized results.

## Safety decisions

- Browser run requests cannot contain executable paths, credentials,
  environment variables, output paths, commands or runner switches.
- Fixture preview cannot start ProxyBridge, the traffic client, SSH or network.
- Product outcomes do not stop later independent scenarios while cleanup and
  shared-state health remain valid; contamination remains a safety stop.
- The real runner adapter is implemented but remains unreachable from the UI.
  A recently verified server is not equivalent to the exact signed
  immutable-preflight receipt required by the Milestone 0 contract, so no nonce
  is issued and the UI shows the missing gate explicitly.

## Verification

- Release build: PASS, 0 warnings and 0 errors.
- `tests\Test-RunOrchestration.ps1`: PASS.
- Modified PowerShell and JavaScript syntax: PASS.
- No ProxyBridge, traffic client, SSH or network process was started.
- Commit and push were not performed.

## Next milestone

Milestone 5 adds deterministic human explanations, expected-versus-observed
views, assertion timelines, product/harness separation and sanitized audit
export without recalculating runner verdicts.

Historical note: Milestone 8 later connected the real adapter to a bounded,
signed immutable-preflight receipt. The Milestone 4 fail-closed boundary above
describes the state at that milestone, not the release-candidate state.
