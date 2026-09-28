# Task 1: repair the interrupted real-browser worker core

This task is limited to:

- `src/protocol_worker/plugins/browser.py`
- `tests/Test-BrowserPlugin.ps1`
- `tests/fixtures/browser/`

Do not edit manifests, catalogs, PowerShell runner modules, server code, UI,
documentation, or unrelated tests. Do not commit or push.

## Required behavior

1. Start with a regression test that fails because the current implementation
   passes fake-only `--testlab-*` switches and waits for fake-created files.
   The fixture must reject any such switch and emulate only supported Chromium
   behavior: bounded `--headless=new`, `--dump-dom`,
   `--virtual-time-budget=<ms>`, isolated `--user-data-dir=<path>`, controlled
   URL, and DOM written to stdout. Record the expected RED output before
   changing production code.
2. The production command must use only real Chromium/Edge/Chrome switches.
   Parse a single bounded machine-readable marker from dumped DOM. The marker
   proves the controlled page fetched deterministic content and must include
   content SHA-256, response status and browser-observed negotiated protocol.
   Never accept marker identity/version/path values as browser identity proof.
3. Controller-supplied parameters must include the discovered browser path,
   expected image SHA-256, browser identity and version. Before launch, verify
   existence and exact SHA-256. The observed post-start image must come only
   from the OS process query and equal the requested path; never substitute the
   requested path as observed.
4. Actual-image probing is bounded: retry every 25-50 ms while the process is
   alive, using a positive timeout in the plan. Evidence records include
   `actual_path_probe_status`, `actual_path_probe_attempts`, and
   `actual_path_probe_elapsed_ms`. Distinguish exit-before-observable,
   query-timeout, and observed-path-mismatch errors.
5. Use a fresh non-existing profile directory and a run-owned working/download
   directory. Capture the browser process tree while alive, bind evidence to
   that tree, terminate the exact tree on every outcome, verify no known member
   remains, then remove the isolated directories. Cleanup failure is a stable
   worker error and can never produce PASS.
6. A successful record must satisfy the public `browser-session` evidence
   contract: `browser_identity`, `browser_version`, `profile_id`,
   `navigation_url_digest`, `negotiated_protocol`, `response_status`,
   `content_sha256`, and `process_tree_cleaned`, plus requested/observed image,
   image SHA verification, process-tree PIDs and path-probe evidence. It also
   carries the common protocol-worker identity fields.
7. Keep stdout/DOM/stderr bounded. Do not emit page content, profile paths,
   credentials, or raw browser logs in the returned record or exception text.
8. Add negative coverage for unsupported fake switches, malformed/multiple DOM
   markers, wrong content hash, bounded path-query timeout, exit before path,
   path mismatch, and failed cleanup/no PASS. Tests run on Windows PowerShell
   5.1 without live browser, ProxyBridge, SSH, or network traffic.

## Verification

Run exactly the focused command while iterating:

`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BrowserPlugin.ps1`

The final output must be pristine and the report must contain both RED and
GREEN command/output evidence.
