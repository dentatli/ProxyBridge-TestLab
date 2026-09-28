# Task 3a — isolated negative proxy foundation

Status: unpromoted, capability-gated semantic foundation accepted after Fix
round 2 CLEAN independent review (2026-09-07). Task 3a is not complete.

## Fix round 2 review-package completion

- Mechanically regenerated the complete incremental diff from byte-hash-verified
  pre-task baselines (11 scoped files, 8 changed). Provenance and the bounded
  regeneration script are adjacent to the diff. Historical progress ledger
  changes are explicitly outside implementation diff scope.
- Primary diff parse (`git apply --numstat`) succeeded. Independent read-only
  review found no actionable findings, verified all 11 current scoped files
  against the after manifest, and passed `git apply --reverse --check`.
- No source changed and no build or already-passing test was repeated in this
  completion pass. Acceptance covers the offline semantic foundation only.

## Scope completed

- Added a TestLab-owned negative SOCKS5 semantic module to the immutable server
  bundle. Its only accepted method negotiation is username/password; every
  parsed authentication attempt is rejected and produces an attempt-bound
  principal digest plus semantic zero-relay intent. This evaluator result is
  not runtime relay proof; real zero-relay evidence remains unproven and
  blocking. No principal or secret is emitted.
- Added two distinct reserved identities in the generated protocol config:
  an auth-negative target and an unavailable target. The artifact is explicitly
  disabled. Configuration alone is only `NOT_VERIFIED`; independent
  listener/unbound and rollback proof is still required. It does not reuse
  failure or impairment control.
- The protocol config loader validates both negative ports against every
  existing protocol-service port. The plugin remains `PLANNED` with an empty
  plugin artifact declaration (required by the catalog contract); the immutable
  bundle includes `negative_proxy.py` independently. No firewall, listener,
  deployment, server receipt, capability or scenario was enabled.
- SOCKS method parsing now accepts any exact RFC 1928 method list containing
  username/password, rejects malformed frames, and rejects every valid
  authentication frame. The retained digest is attempt identity plus username
  only; it is independent of the password and no plaintext field is returned.

## TDD and focused evidence

- RED: Windows PowerShell 5.1 `tests/Test-FailureControl.ps1` exited 1 before
  production edits. `contract_test.py:9` raised
  `ModuleNotFoundError: No module named 'negative_proxy'`; its focused wrapper
  then reported expected exit `0`, actual `1`.
- GREEN: the same test exited 0 with `PASS: failure-control`.
- Fix round 1 RED: the focused fixture reported
  `NEGATIVE_PROXY_REGRESSION_RED` for all six review regressions: PLANNED
  artifacts, declarative `UNBOUND`, valid multi-method negotiation,
  password-dependent digest, missing cross-service collision check, and
  invalid attempt identity. The focused ServerProvisioning RED separately
  caught the changed protocol self-test output.
- Fix round 1 GREEN: `Test-FailureControl.ps1` exited 0. ServerProbe rebuilt
  with 0 warnings and 0 errors, and `Test-ServerProvisioning.ps1` exited 0;
  its static checks cover the exact transport self-test string and inclusion of
  `negative_proxy.py` in the safe protocol-fixture export.
- Fix round 2 GREEN: `Test-FailureControl.ps1` exited 0 after adding an
  independent unavailable-port collision regression. No provisioning build or
  loopback test was rerun because no covered source changed.
- Direct provisioning verification: the targeted ServerProbe build completed
  with 0 warnings and 0 errors. The first `Test-ServerProvisioning.ps1` run
  correctly failed with `ENDPOINT_ARTIFACT_MISSING`, because its synthetic
  repository omitted the newly required immutable artifact. The fixture was
  minimally corrected; its rebuild completed with 0 warnings/errors and the
  same targeted test exited 0 with `PASS: guarded offline server provisioning`.

No UI, ProxyBridge, client binary, listener, loopback, SSH, network, service,
deployment, full test suite, commit, or push was run.

`Test-ProtocolVerticalSlice.ps1` was deliberately **not run**: it starts a
127.0.0.1 protocol server and sends loopback traffic, both prohibited in this
offline slice. This is not a passing result.

## Mandatory remaining blocker

This slice cannot truthfully promote `failure-proxy-unavailable` or
`failure-proxy-auth`. The current server receipt signs artifact hashes but does
not bind a verified negative-proxy semantic receipt, listener/unbound-state or
rollback result. There is also no run-owned negative `.pbprofile` generator,
no orchestration channel for its fresh identity, and no exact assertion model
for PROXY/no-response/zero-delivery/no-fallback/cleanup evidence. Until that
complete contract and offline fixtures exist, `isolated_proxy_negative_target`
remains false and both scenarios remain `CAPABILITY_GATED`.
