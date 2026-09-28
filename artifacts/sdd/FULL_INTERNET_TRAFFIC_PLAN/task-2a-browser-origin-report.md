# Task 2a — Browser Origin Integration

## Scope completed

- Registered the deterministic `browser-origin` endpoint plugin as
  `IMPLEMENTED` and declared its runtime artifacts.
- Added `browser_origin.py` to the immutable server runtime bundle before the
  plugin manifest is calculated.
- Added only an exact versioned browser-origin path branch before the existing
  header-bound HTTP handler. Generic HTTP still requires `X-TestLab-*` identity
  headers.
- Updated the local ServerProbe fixture to model the new artifact and its
  implemented-plugin count. The endpoint service count and unrelated plugin
  expectations were not changed.

## TDD evidence

### RED

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserOrigin.ps1
```

Result: exit `1`. The new real in-memory HTTP boundary sent a versioned page
request without TestLab-only headers. The old generic route emitted no HTTP
response, so `parse_response` failed with `ValueError: not enough values to
unpack`. This proves the required route was absent.

### GREEN

Commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserOrigin.ps1
& 'C:\Program Files\dotnet\dotnet.exe' build .\ui\ProxyBridge.TestLab.Ui.ServerProbe\ProxyBridge.TestLab.Ui.ServerProbe.csproj -c Release --no-restore
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ServerProvisioning.ps1
```

Results:

- `PASS: browser-origin`
- ServerProbe build: `0` warnings, `0` errors.
- `PASS: guarded offline server provisioning`

## Design notes

- Browser-origin accepts only `GET`, no body, and the exact path grammar
  already enforced by `build_browser_origin_response`. A query, traversal, or
  malformed versioned path is consumed fail-closed and writes no successful
  evidence.
- The HTML makes a same-origin `fetch` of its matching download, hashes the
  bytes through Web Crypto, obtains `nextHopProtocol` from the corresponding
  Performance Resource Timing entry, and updates exactly one bounded JSON DOM
  marker (`script#proxybridge-testlab-browser-result`). The marker has only
  `dom_marker`, `content_sha256`, `response_status`, and
  `negotiated_protocol`.
- Both resources send `Cache-Control: no-store` and
  `X-Content-Type-Options: nosniff`. Their bodies and evidence are
  deterministic. Server evidence carries the identity tuple, transport tuple,
  negotiated protocol, resource hash/length and distinct deterministic
  sequences (`page=1`, `download=2`).
- The tests use in-memory `StreamReader`/writer boundaries; no listener,
  browser, product process, SSH, or external network was started.

## Changed files

- `src/server_agent/browser_origin.py`
- `src/server_agent/pb_protocol_server.py`
- `src/server_agent/plugins/catalog.json`
- `ui/ProxyBridge.TestLab.Ui/Services/ServerArtifactBuilder.cs`
- `ui/ProxyBridge.TestLab.Ui.ServerProbe/Program.cs`
- `tests/fixtures/browser-origin/contract_test.py`
- `tests/Test-ServerProvisioning.ps1`
- this report

## Concerns / deferred work

- This task intentionally does not register the local browser worker, change
  scenario dispatch/assertions, generate readiness/capability state, or
  promote the browser-download scenario. Those remain Task 2b and later
  offline vertical-slice work.
- No real browser acceptance run is claimed.

## Fix round 1 — review findings

### Root causes

- The server page used `PROXYBRIDGE_TESTLAB_BROWSER_RESULT_V1`, while the
  already completed worker accepts only `PB_TESTLAB_BROWSER_READY`.
- One shared TLS context advertised `h2`, `http/1.1`, and `pb-test/1` to
  listeners with different parsers. In particular, HTTPS/browser-origin could
  negotiate `h2` and then pass those bytes to the HTTP/1.1 parser.
- `_read_http_request` treated a request with `Transfer-Encoding: chunked` as
  bodyless because it only consumed `Content-Length`.
- Dispatch reserved only paths beginning `/browser-origin/`; the bare root and
  its query form fell through to generic header-bound HTTP.

### RED evidence

The same focused command was run after each test-first regression:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserOrigin.ps1
```

Observed failures, in order:

1. Exit `1` at `completed_markers`: emitted completion values did not equal
   `PB_TESTLAB_BROWSER_READY`.
2. Exit `1` at `chunked_wire`: the chunked browser-origin GET incorrectly
   returned a successful response.
3. Exit `1` at `reserved_wire`: `/browser-origin` with generic identity headers
   incorrectly returned a generic HTTP success.
4. Exit `1` at `_ssl_context(..., ("http/1.1",))`: the implementation exposed
   only a shared no-argument ALPN context.

### Repair

- Both completed JavaScript branches now assign the exact worker-compatible
  marker `PB_TESTLAB_BROWSER_READY`; the fixture validates the completed
  assignment values rather than only the initial placeholder.
- TLS contexts are listener-specific: `pb-test/1` for the TLS echo listener,
  `http/1.1` for HTTPS/WebSocket, `h2` for HTTP/2/gRPC, and no ALPN claim for
  the standard TLS protocol suite. The test exercises real `_ssl_context`
  behavior through an in-memory context boundary and proves HTTP/1.1 does not
  advertise `h2`.
- Any `Transfer-Encoding` is rejected before body handling because this bounded
  server implements only `Content-Length` framing.
- The complete `/browser-origin` path segment is reserved, including bare,
  slash, query, fragment, and percent-encoded boundary forms. Only the exact
  versioned page/download grammar can succeed; unrelated generic HTTP remains
  unchanged.

### GREEN evidence

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserOrigin.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ServerProvisioning.ps1
```

Results:

- `PASS: browser-origin`
- `PASS: guarded offline server provisioning`

### Fix-round changed files

- `src/server_agent/browser_origin.py`
- `src/server_agent/pb_protocol_server.py`
- `tests/fixtures/browser-origin/contract_test.py`
- this report

No listener, browser, product process, SSH, or network action was performed.
