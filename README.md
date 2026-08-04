# ProxyBridge-TestLab

Independent deterministic test and evidence-collection framework for
[ProxyBridge](https://github.com/InterceptSuite/ProxyBridge).

ProxyBridge-TestLab is intended to validate Windows WFP routing behavior,
TCP and UDP correctness, connection lifecycle handling, rule evaluation,
SOCKS5 proxying, failure recovery, and regression scenarios.

This repository does not contain or modify ProxyBridge product code.

## Project status

The repository contains a safe orchestration boundary for dry-run and mock
synthetic-correctness matrices. Windows PowerShell 5.1 is the minimum supported
version; PowerShell 7 is recommended.

Implemented:

- private `.env` parsing and capability/suite/scenario separation;
- capability-based test selection;
- strict `.pbprofile` generation and validation;
- a 135-ID declaration catalog with an explicitly smaller executable subset;
- exhaustive declared critical matrix plus deterministic pairwise declarations;
- known-defect, unsupported and skipped classifications;
- exact base/issue206/issue209 client command builders;
- real-harness JSONL normalization with raw and canonical records;
- shared gated process, CLI lifecycle, health, client, VPS and assertion boundaries;
- gated per-payload dynamic SSH evidence plans with optional import-existing audit mode;
- fixture-backed mock evidence that is independent of expected rule actions;
- redacted UTF-8-without-BOM reports and checksums;
- dependency-free Windows PowerShell tests.

Requires a later explicitly authorized real-runtime run:

- validation against the installed product/client binary contracts;
- real product and client process execution;
- execution of the implemented VPS collector against a real host;
- driver/service, destructive lifecycle and performance execution.

## Safe commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-DryRun.ps1 -FixtureMode
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-MockMatrix.ps1 -FixtureMode
```

Real runtime is never an implicit fallback. `scripts/Invoke-RealSmoke.ps1` is a
separate manual command requiring `-ConfirmRealRuntime`; do not run it until the
local `.env`, hashes, binaries and isolated test environment are verified.

## Goals

The test lab is designed to provide:

- deterministic TCP and UDP tests;
- isolated ProxyBridge profiles per scenario;
- automatic rule generation;
- IPv4 and optional IPv6 coverage;
- DIRECT, BLOCK and PROXY validation;
- stateful connection tests;
- issue-specific regression tests;
- exact payload SHA-256 verification;
- client, ProxyBridge and VPS evidence correlation;
- capability-based skips instead of false failures;
- machine-readable result and coverage reports.

Testing every possible Internet packet sequence is not feasible. The project
instead targets exhaustive coverage of critical combinations, meaningful
equivalence classes, stateful scenarios, and pairwise coverage for secondary
dimensions.

## Repository layout

```text
modules/      PowerShell runner modules
tests/        Dependency-free unit, schema and fixture-backed tests
config/       Capabilities, suites and known-defect policy
scenarios/    Compact declarative catalogs
schemas/      Profile, scenario, suite and result contracts
scripts/      Dry-run, mock and separately gated real-smoke entrypoints
docs/         Safety, evidence, coverage and authoring documentation
```

## Configuration

Copy the example environment file:

```powershell
Copy-Item .env.example .env
```

Edit `.env` and replace the documentation values with values for the local test
environment.

The `.env` file may contain:

- local and remote IP addresses;
- ProxyBridge paths;
- SOCKS5 endpoints;
- SSH destinations;
- expected binary hashes;
- evidence paths.

`.env` is ignored by Git and must never be committed.

Environment limitations are configured separately in:

```text
config/capabilities.json
```

For example, an environment without IPv6 should use:

```json
{
  "ipv6": {
    "enabled": false,
    "reason": "IPv6 is not available in this environment"
  }
}
```

IPv6 scenarios will then be classified as `SKIPPED_CAPABILITY`, not failed.

Test selection is configured in:

```text
config/suites/*.json
```

## Result statuses

Every result includes `run_mode` and `implementation_status`. Catalog entries
are `EXECUTABLE`, `DECLARATIVE_ONLY`, or `UNSUPPORTED_PRODUCT_SCOPE`.

Dry-run results use:

```text
DRY_RUN_READY
NOT_IMPLEMENTED
```

Mock results use only:

```text
MOCK_PASS
MOCK_EXPECTED_FAIL
MOCK_HOLD
```

Real-runtime classifications are:

```text
PASS
FAIL_PRODUCT
EXPECTED_FAIL
HOLD_AMBIGUOUS
BLOCKED_BY_KNOWN_DEFECT
SKIPPED_CAPABILITY
SKIPPED_SELECTION
UNSUPPORTED_PRODUCT_SCOPE
FAIL_HARNESS
FAIL_INFRASTRUCTURE
CONTAMINATED
```

Only real `PASS`/`FAIL_PRODUCT` records become `TESTED_PASS`/`TESTED_FAIL` in
coverage. Mock evidence validates the orchestration contract; it is never
reported as product-tested coverage.

Product failures may be recorded while independent scenarios continue.

Harness, infrastructure, binary-integrity and contaminated-state failures stop
the complete run.

## Security

Generated `.pbprofile` files may contain real hosts, process paths, usernames or
passwords. They are excluded from Git by default.

Do not commit:

- `.env`;
- generated `.pbprofile` files;
- credentials;
- SSH private keys;
- raw packet captures;
- crash dumps;
- unredacted runtime evidence.

See [SECURITY.md](SECURITY.md).

## Documentation

- [Orchestrator specification](docs/ORCHESTRATOR_SPEC.md)
- [Coverage model](docs/COVERAGE_MODEL.json)
- [Coverage explanation](docs/coverage-model.md)
- [Environment setup](docs/environment-setup.md)
- [Adding scenarios](docs/adding-scenarios.md)
- [Evidence format](docs/evidence-format.md)
- [Runtime safety](docs/runtime-safety.md)
- [Known defects](docs/known-defects.md)

## License

MIT. See [LICENSE](LICENSE).
