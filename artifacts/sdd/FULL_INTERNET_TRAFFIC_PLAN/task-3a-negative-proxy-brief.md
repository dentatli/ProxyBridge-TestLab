# Task 3a — Milestone 16 isolated negative proxy

Implement the smallest complete, offline-verifiable contract for
`failure-proxy-unavailable` and `failure-proxy-auth`. Preserve the accepted
Milestones 9-15 and the already executable Milestone 16 DNS/client-termination
scenarios.

## Safety and scope

- Do not run the UI, ProxyBridge, any client binary, SSH, listener, loopback,
  systemd, driver/service, or network traffic. Do not commit or push.
- Never read, clone, reuse, compare, log, or export the operator proxy endpoint
  or credentials for a negative-proxy profile.
- Add no public manual path, hash, port, username, password, or `.env` setting.
- A capability remains false unless a current signed server receipt proves the
  exact installed semantic contract. Editable capability JSON is not proof.
- Incomplete, malformed, stale, duplicate, cross-run, or cleanup-incomplete
  evidence must never produce PASS.

## Required contract

1. Add a TestLab-owned SOCKS5 negative server artifact and dedicated reserved
   identity/ports. It must never relay application traffic. The authentication
   path deterministically requires username/password negotiation and rejects it,
   recording only an attempt-bound principal digest and zero-relay proof. The
   unavailable path must have a deterministic, independently provable negative
   state; do not infer it from absence of endpoint payload alone and do not
   reuse the impairment-control port.
2. Provision, hash, self-test, listener/unbound-state verify, and roll back the
   negative-proxy artifacts through the existing generated UI-reviewed server
   plan. Extend the signed readiness receipt so the derived
   `isolated_proxy_negative_target` capability is true only for the exact current
   bundle and semantic verification. Public plan/status text must not disclose
   principal or credential values.
3. Generate an isolated run-owned negative `.pbprofile` contract. It must contain
   exactly the intended negative proxy configuration/rule, use a fresh non-
   operator config identity, and contain no cloned operator proxy config or
   credentials. Preserve ordinary profile generation behavior for all existing
   scenarios.
4. Add structured, attempt/run-bound evidence and assertions for the two
   negative cases. PASS requires the exact PROXY route/config identity, client
   no-response semantics, complete zero-delivery proof at the real destination,
   the matching negative-proxy semantic receipt, and cleanup/rollback proof.
   Direct fallback or endpoint payload is FAIL_PRODUCT. Missing proof is
   HOLD/FAIL_HARNESS and identity conflicts are CONTAMINATED according to the
   existing priority policy.
5. Promote the two scenarios only after the complete profile, server,
   orchestration, assertion and derived-capability contract is present and
   covered by offline fixtures. If a load-bearing runtime interface cannot be
   truthfully completed in this slice, leave the scenarios gated and report the
   exact blocker instead of weakening assertions.

## TDD and verification

- Capture a strict RED before production changes.
- Add dependency-free Windows PowerShell 5.1 coverage for isolated profile
  generation, server semantic self-test/receipt drift, derived readiness,
  positive auth/unavailable evidence, direct fallback, endpoint leak, missing
  or malformed receipt, wrong principal/config/run identity, duplicate receipt,
  expiry, and failed cleanup.
- Run only the new focused test(s) and the directly affected existing targeted
  tests once after implementation. Do not run `tests/Run-All.ps1` in this slice.
- Produce a narrow report and a readable incremental review diff under this
  SDD artifact directory.

