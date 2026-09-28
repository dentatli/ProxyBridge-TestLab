# Task 3a isolated profile constructor

Status: CLEAN independent review for an unpromoted offline constructor only.

- Added `modules/NegativeProxyProfile.psm1` and
  `tests/Test-NegativeProxyProfile.ps1`. Ordinary profile generation is unchanged.
- One fresh profile/config identity and one exact TCP PROXY rule; generated
  credentials, no operator/environment/template inputs. Reserved ports come
  from the public managed-server catalog, not manual configuration.
- Input IPs are canonicalized; loopback, unspecified, multicast and wildcard
  destinations are rejected. No write or runtime call occurs.
- Returned profile is private: callers must never serialize the whole object
  into public evidence. Binding excludes credentials. Construction always
  returns `requires_verified_receipt=true`, `runtime_authorized=false`.
- Numeric identity is randomly allocated with bounded retries and module-local
  duplicate avoidance; it is NOT a globally unique authorization token. Future
  receipt/assertion integration must bind profile GUID, run and attempt too.

Verification: Windows PowerShell 5.1 targeted RED (module missing), GREEN;
review regression RED (constant numeric ID), GREEN after fresh ID allocation
and address canonicalization fixes. Independent re-review CLEAN. No compiled
source changed, no build needed. No already-passing existing tests rerun.

Incremental source diff: `task-3a-profile-review.diff` (both new files).
No runtime/network, generated profile files, real credentials, commit or push.

Remaining: signed server receipt and observed semantics, readiness derivation,
runner integration, no-fallback/zero-delivery and cleanup assertions. The
constructor is not wired into runtime. Both scenarios remain CAPABILITY_GATED;
Task 3a and Milestone 16 are not complete.
