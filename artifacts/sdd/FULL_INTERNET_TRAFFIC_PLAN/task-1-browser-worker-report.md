# Task 1 implementation report

## RED

Command:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1
```

Result:

```text
ASSERTION FAILED: supported Chromium-only fixture must produce evidence instead of rejecting fake-only switches
```

The replacement fixture rejects every `--testlab-*` argument. The interrupted
worker still passed those fake-only switches and waited for fixture-created
files, so it could not produce the required browser evidence.

## GREEN

Command:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1
```

Result:

```text
PASS: isolated browser worker core
```

## Files changed

- `src/protocol_worker/plugins/browser.py`
- `tests/Test-BrowserPlugin.ps1`
- `tests/fixtures/browser/fake_browser.py`
- `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-1-browser-worker-report.md`

## Design notes

- Browser launch now uses Chromium-compatible headless, DOM-dump,
  virtual-time-budget and isolated-profile flags; the worker rejects
  `--testlab-*` arguments and does not wait for test-created files.
- The DOM contains one bounded JSON marker for the deterministic content hash,
  response status and negotiated protocol. Controller-provided browser
  identity/version are recorded separately and are never taken from DOM.
- The controller path is preflighted with an exact SHA-256. After launch the
  executable path is obtained only from the OS process query, with bounded
  retry evidence and distinct exit, timeout and mismatch failures.
- The worker uses new profile and working/download directories, captures the
  live process tree, drains stdout/stderr under a fixed cap, terminates and
  verifies the exact known tree, then removes both directories before a PASS
  record is returned.
- Offline negative cases cover fake switches, malformed/multiple markers,
  wrong content hash, path-query timeout, exit before observable path, path
  mismatch and cleanup failure without PASS evidence.

## Remaining caveats

- The focused fixture emulates supported Chromium DOM-dump behavior using the
  local Python interpreter. No real browser, ProxyBridge, SSH, or network
  traffic was launched in this task.
- Controller/runner integration that supplies the new browser path/hash/
  identity/version contract remains outside Task 1 scope.

## Fix round 1

Command:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1
```

Result:

```text
PASS: isolated browser worker core
```

Changed design:

- The browser root is now assigned to a kill-on-close Windows Job Object before
  evidence capture. Job membership is merged with the live process-tree
  snapshot before cleanup, then the job is closed and every known member is
  independently checked until gone. A late child cannot produce PASS unless it
  is included in the recorded tree and verified terminated.
- Caller-supplied `browser_arguments` must be empty. All launch switches and
  the single navigation URL are worker-owned; positional paths, alternate URLs
  and controlled-flag overrides are rejected before launch.
- Profile and working/download directory creation now occurs inside the stable
  failure-and-cleanup block, so a partial setup is removed and only a stable
  worker error is returned.
- The focused fixture uses a generated hash-verified executable rather than a
  positional Python script. It enforces the exact Chromium flag surface,
  bounded virtual-time budget, fresh profile, run-owned working directory and
  one controlled URL; it also creates a late child for containment coverage.

## Fix round 2

Command:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1
```

Result:

```text
PASS: isolated browser worker core
```

Changed design:

- Browser execution now starts through `CreateProcessW` with
  `CREATE_SUSPENDED`. The newly created root is assigned to the Job Object
  before its primary thread is resumed; resume validates the returned suspend
  count and a live process handle within a bounded operation. Assign or resume
  failures clean up the exact suspended process and cannot produce PASS.
- Cleanup state is monotonic. Job query, job close, process-handle close,
  known-PID termination, output-reader and directory-cleanup failures are
  accumulated; no later successful step can overwrite an earlier cleanup
  failure. A failed `CloseHandle` retains the Job handle for fail-closed
  handling.
- Isolated profile and working/download paths are marked owned only after this
  invocation creates them. Setup-race failures remove only paths already
  created by this worker and leave a competing actor's directory untouched.
- The fixture now starts its containment child immediately after producing its
  controlled DOM, and both generated C# and retained Python fixture require
  the exact navigation URL `https://testlab.invalid/browser/download`.
- The focused harness kills its exact driver tree through a bounded timeout
  cleanup path before reporting a driver timeout. Temporary lifecycle tracing
  used to diagnose the suspended assign-failure case was removed before GREEN.

## Fix round 3

### RED

Command:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1
```

Result:

```text
ASSERTION FAILED: reader-open failure must terminate the created suspended root before returning control
```

The injected `_open_reader` failure recorded the PID created by `CreateProcessW`.
Before this fix, construction failed before the caller received the process
object, leaving that exact suspended root alive; the test terminated the
recorded PID afterwards to avoid leaving a fixture process behind.

### GREEN

Command:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1
```

Result:

```text
PASS: isolated browser worker core
```

### Design notes

- `_SuspendedBrowserProcess` now establishes cleanup ownership from its first
  acquired pipe handle. Any pipe or NUL-input acquisition failure closes every
  handle acquired so far and reports the stable suspended-launch worker error.
- On every post-`CreateProcessW` construction failure, the constructor
  terminates and waits for the exact suspended root before closing its process,
  thread, pipe and stream handles, then rethrows
  `BROWSER_SUSPENDED_LAUNCH_FAILED`.
- The offline fixture monkeypatches only existing internal boundaries to cover
  reader-open, stderr-pipe and NUL-input failures; it records the created PID
  and verifies that no PASS record is emitted.
- `Stop-TestDriverTree` now performs the exact-driver fallback from a
  finally-style cleanup path when `taskkill` exceeds its bounded wait. Its
  deterministic regression uses a short forced timeout and verifies that the
  exact Python driver is gone before the timeout is reported.

### Concerns

- Coverage remains offline and exercises Windows handle/process behavior
  through the generated local fixture only. No real browser, ProxyBridge, SSH
  or network activity was used.

## Fix round 4

### RED

Command (all focused iterations):

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1
```

Observed constructor-cleanup RED:

```text
ASSERTION FAILED: constructor cleanup failure reader-cleanup-wait-timeout must be propagated through the stable wrapper; expected='BROWSER_SUSPENDED_PROCESS_CLEANUP_FAILED' actual='fixture reader open failure'
```

Observed test-driver exception RED:

```text
ASSERTION FAILED: taskkill exceptions must be reported only after exact-driver fallback and final verification; expected='ASSERTION FAILED: driver-tree cleanup operation failed' actual='Exception calling "Kill" with "0" argument(s): "fixture taskkill Kill exception"'
```

Observed exact-root TerminateProcess RED:

```text
ASSERTION FAILED: constructor cleanup failure reader-cleanup-terminate-failure must not return while the exact root remains active
```

### GREEN

Command:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1
```

Result:

```text
PASS: isolated browser worker core
```

### Files changed

- `src/protocol_worker/plugins/browser.py`
- `tests/Test-BrowserPlugin.ps1`
- `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-1-browser-worker-report.md`

### Design notes

- Suspended-root cleanup uses the original process handle and returns a
  verified result. It distinguishes an already-signaled process from an active
  process, checks `TerminateProcess`, performs a bounded process-handle wait,
  and requires a successful non-`STILL_ACTIVE` `GetExitCodeProcess` result.
- Constructor cleanup is monotonic: a failed or exceptional terminate/status
  attempt is retried for exact-root cleanup but remains a cleanup failure;
  pipe, stream, thread and process-handle close results are also accumulated.
  Cleanup failures are exposed through `BROWSER_SUSPENDED_LAUNCH_FAILED` with
  the stable `BROWSER_SUSPENDED_PROCESS_CLEANUP_FAILED` cause.
- `Stop-TestDriverTree` accumulates taskkill start/wait/status/kill exceptions,
  always reaches the exact driver fallback, and performs a final bounded driver
  verification before reporting timeout or cleanup-operation failure.
- Reader-open regressions duplicate the created process handle before raising.
  All liveness checks, emergency termination and final close use that exact
  handle; the recorded PID is never used to terminate a potentially reused PID.

### Concerns

- Coverage remains offline and uses injected one-shot Win32 cleanup failures
  against the generated local fixture. No real browser, ProxyBridge, SSH or
  network activity was used.

## Fix round 5

### RED

Command:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1
```

Result:

```text
ASSERTION FAILED: persistent TerminateProcess/Wait failure must occur only after Job assignment; root_alive=True; later_thread_close=False; later_process_close=False; cleanup_error=BROWSER_SUSPENDED_LAUNCH_FAILED
```

The persistent Win32-failure regression reached reader conversion before Job
assignment, left the exact suspended root active until exact-handle fixture
cleanup, and showed that a non-`OSError` stdout-close exception skipped both
the later thread-handle and process-handle close attempts.

### GREEN

Command:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1
```

Result:

```text
PASS: isolated browser worker core
```

### Design notes

- `_SuspendedBrowserProcess` construction now owns only raw pipe, NUL and
  suspended-process handles. Pre-`CreateProcessW` failures close every acquired
  raw handle independently; after a successful create, construction performs
  no reader conversion or fallible handle close before returning ownership.
- `run_browser` assigns the suspended root to the kill-on-close Job before a
  separate output-reader setup step, and resumes only after that setup. A
  reader failure therefore closes containment first, verifies the exact
  original process handle is signaled, and only then closes process resources.
- Process close is per-resource and monotonic. Each stream, raw pipe, primary
  thread and process handle close is attempted independently; failed resources
  remain owned where possible, and any close failure returns false so the
  stable `BROWSER_TREE_CLEANUP_FAILED` result overrides the original failure.
- The regressions retain a duplicate exact process handle for liveness and
  emergency cleanup. Persistent old-path `TerminateProcess`/wait failures no
  longer leave the suspended root outside containment, and an early stdout
  close exception cannot skip later thread/process handle closes or emit PASS.

### Concerns

- Coverage remains offline and uses the generated local Chromium-style
  fixture plus injected Win32/stream failures. No real browser, ProxyBridge,
  SSH or network activity was used.

## Breaker adjudication

The fifth review found two load-bearing cleanup gaps: partial
`open_osfhandle`/`fdopen` ownership transfer could leak a CRT descriptor, and
the Job-containment fixture still allowed the ordinary tree-termination
fallback to mask a broken Job.

The new descriptor regression failed before the repair with:

```text
ASSERTION FAILED: partial reader conversion must close the transferred CRT descriptor instead of the original Win32 handle
```

The worker now records a transferred descriptor as an owned resource before
reader construction, clears the original Win32-handle ownership immediately,
and closes every still-owned descriptor independently during cleanup. The Job
fixture replaces tree termination with exact-handle observation, so only Job
closure can satisfy containment.

Final focused verification:

```text
PASS: isolated browser worker core
```
