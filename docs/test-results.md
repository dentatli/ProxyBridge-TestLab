# Current ProxyBridge WFP test results

This document is a concise, sanitized snapshot of the current investigation.
It is not a release certification and does not include raw environment evidence.

## Tested object

```text
Product: ProxyBridge 4.1.0-Beta WFP
Platform: Windows 10 Pro 22H2 x64 VM
TestLab: ProxyBridge-TestLab
Endpoint: deterministic external TCP/UDP echo server
Protocols evaluated here: IPv4 TCP and UDP
```

## Latest full IPv4 diagnostic sweep

```text
Run ID: 20260804T152149Z-d30d31ed
Catalog entries: 135
Current executable IPv4 scenarios run: 25
Scenario cleanup: 25/25 PASS_CLEAN
Harness/infrastructure/contamination failures: 0
```

Result distribution for the 25 executed scenarios:

```text
PASS           17
EXPECTED_FAIL   7
FAIL_PRODUCT    1
```

Remaining catalog disposition:

```text
BLOCKED_BY_KNOWN_DEFECT   2
SKIPPED_CAPABILITY        9   (IPv6 unavailable in the test environment)
NOT_IMPLEMENTED          74
SKIPPED_SELECTION        18   (application/performance/manual categories)
UNSUPPORTED_PRODUCT_SCOPE 7
```

Evidence archive SHA-256:

```text
3F92FB8900C30B020ABC413A80B6CFC4E311CB72AF4FE79CDC45A5FB0065D589
```

## Confirmed working in the tested environment

- TCP IPv4 `DIRECT`, `BLOCK`, and `PROXY` with basename application matching;
- UDP IPv4 `DIRECT` and `BLOCK`, connected and unconnected;
- no external payload leak in the tested BLOCK scenarios;
- TCP PROXY external egress differs from the direct baseline as expected;
- basename, destination-IP, single-port, and port-range rule selectors;
- expected rejection of an invalid missing-proxy profile before product start;
- security scenarios for BLOCK no-leak, PROXY no-direct-leak, and no wrong destination;
- issue #206 `PROXY → BLOCK` with abortive exact local-port reuse.

## Reproduced known defects

### Full-path application selector can fail open

A rule using the full DOS executable path can be reported by user mode as
`Blocked` or `Proxy` while the driver watchlist does not match the WFP
`ALE_APP_ID` namespace. Basename matching works in the tested build.

### UDP PROXY does not restore the original response source

Connected and unconnected UDP requests reached the VPS through the proxy and the
correct payload returned, but the client observed the local ProxyBridge relay as
the response source rather than the original remote endpoint.

### Watched-process UDP DIRECT can be silently dropped

When the executable is present in the driver watchlist because of another
non-DIRECT rule, a UDP DIRECT flow can be redirected to the local relay and then
not forwarded externally.

### Issue #206 PROXY → DIRECT wrong egress

After abortive exact local-port reuse, a fresh flow expected to be DIRECT did not
match the independently measured direct-egress baseline.

## Additional isolated product failure under investigation

An isolated two-rule scenario contains:

```text
TCP :41002 → DIRECT
TCP :41001 → PROXY
```

The first DIRECT flow completed but did not use the direct-egress baseline,
before the second flow and before port reuse could affect it.

```text
Run ID: 20260804T171530Z-7146b259
Status: FAIL_PRODUCT
Evidence archive SHA-256:
282139332241DD258D4B77C4BFECAA10D98933FAAD9F7B73E4C026607B1DE853
```

Current interpretation: candidate watched-process or mixed-rule TCP DIRECT
wrong-egress defect. It is not yet classified as an issue #206 transition
failure because the first flow was already incorrect.

## Not yet concluded

- IPv6 correctness: not evaluated because the test host/VM lacked native public IPv6;
- issue #209 opposite-protocol same-port collision: blocked by current product behavior;
- advanced TCP lifecycle and concurrency;
- advanced UDP delayed, duplicate, receive-only, reconnect, and fragmentation cases;
- failure injection;
- full payload-size matrix;
- real-application canaries such as Discord and QUIC under the WFP beta;
- performance and resource regression.

## Overall verdict

```text
TestLab current real IPv4 executable subset: operational
ProxyBridge 4.1.0-Beta IPv4 correctness: NO-GO
Release readiness: NO-GO
```

Known failures should be rerun by the developer against a build containing the
corresponding fixes. `EXPECTED_FAIL` means that the TestLab reproduced a known
defect with the declared signature; it does not mean that the product passed.
