# Full Internet Traffic Expansion Plan

> Historical expansion plan. [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) supersedes the single Linux topology, mandatory developer tests and automatic milestone continuation. New runtime modes are planned, not implemented.

Status: approved and in progress  
Plan version: 1.0  
Approved: 2026-08-28  
User-facing language: English  
Publication policy: local working tree only; no commit or push

## 1. Objective

Extend ProxyBridge TestLab from its deterministic TCP/UDP correctness core into
an automated protocol, browser, failure-injection, performance and long-run
test system. Configuration, server provisioning, test selection, execution,
recovery, metrics and results remain controlled by the loopback web UI. Users
must not edit `.env` or manually install endpoint components.

The target is every meaningful user-process TCP/UDP traffic class that
ProxyBridge claims to handle. Literal coverage of every application and every
packet sequence is not a finite goal. Closed third-party applications are
represented by controlled standards-based equivalents unless an isolated,
non-secret real-client adapter can produce deterministic evidence.

## 2. Fixed boundaries

- Supported server platforms are Debian and Ubuntu with systemd from the
  explicit compatibility manifest.
- SSH authentication uses a private key only and a pinned host fingerprint.
- The Windows tester may be behind NAT and requires outbound connectivity only.
- ICMP, IGMP, GRE, ESP/AH, SCTP, raw sockets and non-IP link-layer traffic stay
  `UNSUPPORTED_PRODUCT_SCOPE` unless ProxyBridge publishes a contrary product
  contract.
- Existing `pb_net_client.exe` remains the native socket/WFP authority.
- A bundled Python protocol worker handles standards-aware application
  protocols. A real browser worker is used when browser semantics matter.
- A native performance worker is used where Python overhead could become the
  measured bottleneck.
- No scenario becomes executable without independent client/server evidence,
  negative fixtures and fail-closed assertions.

## 3. Target architecture

### Approved topology decision (2026-09-07)

Use one deployment model, not separate Local, Lab and Remote execution modes.
Windows runs TestLab, ProxyBridge and the traffic generators. A separate
Debian/Ubuntu systemd node hosts the TestLab-managed SOCKS5 proxy, protocol
receivers and server metrics/evidence collection. The primary development
topology is a Windows VM plus a Linux VM; the Linux node may also be a LAN
machine or VPS without changing the execution model.

The UI collects the Linux address, SSH user and private-key reference, verifies
host trust, presents the generated installation plan, and prepares and verifies
the proxy and endpoints automatically. No manual .env configuration is required.
This is an approved target; automatic managed-proxy provisioning must not be
claimed implemented until its code and verification are complete.

Local-only execution and a proxy colocated with ProxyBridge on Windows are out
of scope. Tests are gated by observed topology capabilities, not a Lab/Remote
label. VM connectivity alone does not prove external NAT or Internet traversal.
DIRECT must reach the receiver directly; PROXY must have correlated proxy and
receiver evidence. Proxy and receiver failures must be independently controllable.

```text
Loopback TestLab UI/controller
    -> readiness, catalog, scheduler and result service
    -> native socket worker
    -> bundled Python protocol worker
    -> native performance worker
    -> isolated browser worker
    -> existing PowerShell runner and ProxyBridge lifecycle

Pinned SSH control channel
    -> Debian/Ubuntu systemd endpoint agent
    -> versioned protocol plugins
    -> TestLab-owned network namespace/fault controls
    -> metrics and evidence collector
```

The endpoint exposes only selected data-plane ports. Provisioning, session
control, evidence and metrics use SSH; no public management API is created.

## 4. Coverage waves

### Transport and socket behavior

TCP/UDP, IPv4/IPv6, DIRECT/BLOCK/PROXY, connected/unconnected UDP, payload
boundaries, partial I/O, backpressure, graceful/abortive close, half-close,
reset, refused, timeout, long-lived flows, bursts, parallelism, tuple reuse,
multiple destinations, multiple processes, NAT idle/reconnect and registered
receive-only UDP.

### DNS and encryption

DNS over UDP/TCP, truncation fallback, NXDOMAIN/SERVFAIL/timeout, multiple
A/AAAA answers, DoT, DoH, TLS 1.2/1.3, SNI, ALPN, resumption, controlled
certificate failures, large records and shutdown behavior.

### Web

HTTP/1.0 and 1.1, keep-alive, chunked transfer, uploads/downloads, redirects,
compression, ranges, slow peers, HTTP/2 multiplexing and flow control, gRPC,
WebSocket/WSS, QUIC, HTTP/3, WebTransport and HLS/DASH traffic patterns.

### Standard application protocols

Passive FTP/FTPS, SFTP, SMTP/SMTPS, IMAP/IMAPS, POP3/POP3S, MQTT/MQTTS,
AMQP/AMQPS, NTP, IRC/TLS and controlled multi-peer traffic. Services use
ephemeral TestLab credentials and synthetic content only.

### Realtime and browser

STUN, TURN, ICE, DTLS, RTP/RTCP, SRTP, WebRTC data/audio/video, synthetic
screen sharing, voice/game traffic patterns and real Chromium navigation,
download, upload, WebSocket, HTTP/2, HTTP/3 and WebRTC canaries.

### Failure and network conditions

Isolated delay, jitter, loss, duplication, reordering, corruption, rate limits
and burst loss; unavailable/auth-failing proxy, controlled DNS failure,
endpoint/client/CLI termination, backend restart, malformed evidence, disk/log
failure, stale readiness, upgrade failure and cleanup failure.

### Performance and soak

Latency p50/p95/p99, TCP throughput, UDP datagrams/sec and loss, new-flow rate,
concurrency, ProxyBridge CPU/memory/handles/threads, endpoint resources and
post-load recovery. Results require a same-run direct baseline and calibrated
warm-up/sample policies.

## 5. Automation contract

The UI accepts server address, SSH port/user/key and first-use host trust. It
then performs OS/systemd/architecture/sudo/disk/port preflight, previews exact
changes, installs a dedicated account, uploads pinned offline artifacts,
creates a private CA and service certificates, installs systemd units, applies
only TestLab-owned firewall rules, verifies every plugin and issues a signed
readiness receipt.

The Run button remains disabled until local artifacts, endpoint receipt,
protocol plugins, selected capabilities, product lifecycle and clean-state
checks pass. Missing capability is visible and never normalized to a product
failure.

## 6. Evidence and classification

Every transaction carries run, scenario, attempt, flow, process, socket, phase
and sequence identities, deterministic payload hash, UTC and monotonic timing,
tuple information and protocol-specific fields. Mandatory channels are client,
server, route/action and lifecycle/cleanup. Performance adds synchronized local
and server metric windows plus a same-run baseline.

- `PASS`: every mandatory channel agrees.
- `FAIL_PRODUCT`: complete evidence proves product-path behavior is wrong.
- `FAIL_HARNESS`: worker, endpoint, parser or orchestration failed.
- `HOLD_AMBIGUOUS`: evidence is incomplete or contradictory.
- `EXPECTED_FAIL`: exact structured known-defect signature matched.
- `SKIPPED_CAPABILITY`: a verified environmental capability is absent.
- `UNSUPPORTED_PRODUCT_SCOPE`: outside the claimed product contract.

A scenario-local outcome never stops independent later scenarios. Cleanup,
reset and a health proof follow every attempt. Only contamination, unknown
active state, failed cleanup, artifact drift, lost server identity or unhealthy
shared runtime causes a safety stop.

## 7. Run profiles

- Quick: bounded critical readiness and route matrix, normally 15-30 minutes.
- Full correctness: every enabled correctness/protocol scenario, normally 3-6
  hours.
- Extended: repeats, impairment and concurrency, normally 8-16 hours.
- Soak: explicit 24, 48 or 72 hour stability run.

Long runs persist state, remain cancellable, perform normal cleanup, and resume
only after revalidating artifacts, server identity, receipt and shared health.

## 8. Milestones

| Milestone | Deliverable | Effort |
|---|---|---|
| 9 | Protocol taxonomy, capability model, evidence profiles and acceptance gates | Very High |
| 10 | Common protocol-worker SDK and bundled Windows runtime contract | Very High |
| 11 | Versioned endpoint plugin system and automated provisioning | Very High |
| 12 | DNS, TLS and HTTP/1.1 vertical slice through UI | High |
| 13 | HTTP/2, HTTP/3, QUIC, WebSocket, gRPC and WebTransport | Very High |
| 14 | Mail, file transfer, messaging, NTP and controlled multi-peer protocols | High |
| 15 | STUN, TURN, WebRTC, RTP/media and browser workers | Very High |
| 16 | Safe failure injection and isolated network impairment | Very High |
| 17 | Native performance runner and long soak orchestration | Very High |
| 18 | Optional LAN agent and multi-peer topology | Very High |
| 19 | Complete UI integration, resume, metrics and readable reports | High |
| 20 | Offline audit, isolated-VM acceptance and final release candidate | Max |

Each milestone ends with schema validation, positive and negative fixtures,
targeted offline tests, redaction review, continuation/cleanup checks, UI
projection and a concise report. Implementation continues automatically after
the gate passes. A failed gate is repaired before proceeding.

## 9. Completion criteria

- Every supported protocol family has deterministic positive and negative
  transactions and externally discriminating DIRECT/BLOCK/PROXY evidence.
- IPv4/IPv6 and optional topology are capability-gated.
- Every formerly declarative scenario is executable, a non-traffic system
  check, capability-gated, or proven outside product scope.
- Server and local dependencies are installed from the UI; no manual `.env`.
- Long runs survive interruption without reusing stale readiness or evidence.
- Local product failures continue after cleanup; unsafe shared state stops.
- Reports explain every result and never disclose credentials or private data.
- Full correctness passes in an isolated VM and the 24-hour soak completes
  without leaks, contamination or unexplained evidence loss.
