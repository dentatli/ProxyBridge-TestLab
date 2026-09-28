# Milestone 10 report

Status: complete  
Effort: Very High

## Outcome

A common protocol-worker SDK now accepts a bounded, versioned JSON plan,
resolves only statically registered plugins, emits canonical UTF-8-without-BOM
JSONL and validates all common plus plugin-specific evidence fields. Plans with
unknown plugins, unknown fields, excessive size/depth, invalid identities or
secret-bearing keys fail before execution.

The initial `contract-selftest` plugin has no network access and proves the
worker/manifest/evidence boundary. Worker stdout contains only a stable status;
plan and evidence content are not printed. Existing evidence files are never
overwritten.

`Build-ProtocolWorkerBundle.ps1` assembles an explicit x64 CPython runtime,
excludes user `site-packages`, debug files and bytecode, copies only public
worker/contracts, executes the self-test from the assembled runtime and writes
a complete SHA-256 inventory. Runtime installation and network dependency
downloads are prohibited during a test run.

## Verification

- `tests/Test-ProtocolWorker.ps1`: PASS.
- Assembled x64 worker self-test: PASS.
- Missing evidence field and secret-plan negative cases: PASS.
- Network/product/SSH runtime: not started.
- Commit/push: not performed.
