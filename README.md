# ProxyBridge-TestLab

Current application: bilingual **Builds → Testing → Run → Results**, selected
tests with individual presets, saved named suites and validated launch history.
See [UI guide](ui/README.md), [functional inventory](docs/DEVELOPMENT_FUNCTIONAL_STATUS.md)
and [development handoff](docs/CHAT_HANDOFF_DEVELOPMENT.md). TCP failure diagnosis
continues separately; its working copy and frozen kits are not development inputs.

Independent deterministic test and evidence-collection framework for
[ProxyBridge](https://github.com/InterceptSuite/ProxyBridge).

ProxyBridge-TestLab validates Windows WFP routing behavior, TCP and UDP policy
enforcement, connection lifecycle handling, rule evaluation, SOCKS5 proxying,
known regressions, and externally verifiable route evidence.

This repository does not contain or modify ProxyBridge product code.

## Historical harness results

The framework has completed real IPv4 execution against ProxyBridge
4.1.0-Beta WFP in an isolated Windows VM.

Latest full diagnostic sweep:

```text
135 catalog entries
25 implemented IPv4 scenarios executed
17 PASS
7 EXPECTED_FAIL (known defects reproduced)
1 FAIL_PRODUCT (additional isolated routing failure under investigation)
0 harness/infrastructure/contamination failures
```

See [Current test results](docs/test-results.md) for the concise sanitized
summary and limitations.

## Included components

- a 135-ID scenario catalog with explicit `EXECUTABLE`, `DECLARATIVE_ONLY`, and
  `UNSUPPORTED_PRODUCT_SCOPE` boundaries;
- PowerShell orchestration, profile generation, process lifecycle control,
  environment preparation, assertions, evidence correlation, reporting, and
  redaction;
- source for the deterministic Windows client: `src/pb_net_client.c`;
- source for the deterministic Linux TCP/UDP endpoint:
  `src/pb_net_endpoint.py`;
- an x64 Windows client build script;
- a systemd service example for the endpoint;
- dry-run, mock, real-smoke, and real diagnostic suite configurations;
- dependency-free Windows PowerShell fixture tests;
- known-defect signature matching so unrelated product failures are not hidden.

The repository intentionally does not include:

- ProxyBridge binaries or driver packages;
- compiled `pb_net_client.exe` binaries;
- proxy credentials;
- SSH private keys;
- machine-specific `.env` files;
- raw runtime evidence.

## Quick start

### Local web UI

The default page is the RU/EN laboratory. Add named builds, select tests and their
individual settings, save reusable suites, explicitly prepare/start a queue and
inspect Comparison/History. The retired technical dashboard is no longer shipped.
Source builds do not establish product correctness; runtime evidence gates remain.

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' run `
    --project '.\ui\ProxyBridge.TestLab.Ui\ProxyBridge.TestLab.Ui.csproj'
```

Open `http://127.0.0.1:5178/`. See [Local web UI](ui/README.md). The Ubuntu wizard
and a separate 16-case traffic catalog are implemented; see [traffic workloads,
evidence and acceptance limits](docs/TRAFFIC_LAB.md). Real product checks require
an administrator UI (`scripts/Start-TestLabUi.ps1 -Administrator`, after building).
Driver file identity and owned cleanup remain mandatory. The v4.0.0 adapter and
acceptance of arbitrary/relocated product bundles remain pending.

The standalone harness and its technical backend are retained below. They are
separate from the laboratory workflow; their historical verification is not proof
of the current checkout. Ordinary development does not require running a full
diagnostic suite.

### 1. Clone

```powershell
git clone https://github.com/dentatli/ProxyBridge-TestLab.git
Set-Location '.\ProxyBridge-TestLab'
```

### 2. Build the Windows client

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\scripts\Build-Harness.ps1'
```

Output:

```text
bin\pb_net_client.exe
```

### 3. Configure the current laboratory

Use Builds, Testing and Run as described in [the operator guide](docs/OPERATOR_GUIDE.md).
The previous Environment Setup screen has been removed. Shared settings and SSH
backend services remain for development and existing probes. Testing → remote
contains its own Ubuntu wizard and traffic runtime; it does not remove evidence
gates or grant readiness to the older remote launch adapter.

### 4. Configure the tester

The laboratory stores choices in the per-user application directory and protects
build paths with DPAPI. Templates do not store credentials or runtime readiness.
The retained technical runner uses its own guarded configuration adapter; do not
manually alter old `.env` files or diagnostic preparations as a development step.

### 5. Validate TestLab itself

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\tests\Run-All.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\scripts\Invoke-DryRun.ps1' -FixtureMode
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\scripts\Invoke-MockMatrix.ps1' -FixtureMode
```

### 6. Real execution status

The safe job orchestrator and real runner adapter are present. Real execution
still requires a dedicated signed immutable-preflight receipt for the exact
selection; Server Setup readiness alone is insufficient and there is no UI
bypass.

## Repository layout

```text
src/          Windows client and Linux endpoint source
modules/      PowerShell runner modules
scripts/      build, dry-run, mock and gated real-smoke entrypoints
deploy/       service examples
config/       capabilities, runtime policy, suites and known defects
scenarios/    declarative scenario catalogs
schemas/      profile, scenario, suite and result contracts
tests/        dependency-free unit, schema and fixture tests
docs/         setup, evidence, safety, coverage and current results
```

## Result statuses

Real-runtime classifications include:

```text
PASS
FAIL_PRODUCT
EXPECTED_FAIL
HOLD_AMBIGUOUS
BLOCKED_BY_KNOWN_DEFECT
SKIPPED_CAPABILITY
SKIPPED_SELECTION
NOT_IMPLEMENTED
UNSUPPORTED_PRODUCT_SCOPE
FAIL_HARNESS
FAIL_INFRASTRUCTURE
CONTAMINATED
```

Important distinctions:

- `EXPECTED_FAIL` means a known defect was reproduced with its declared
  signature; it is not a product pass;
- `NOT_IMPLEMENTED` means the catalog declares the coverage but no executable
  client contract exists yet;
- mock evidence validates TestLab, not ProxyBridge;
- `RUN_COMPLETE` means reports were written; read `summary.json` and
  `summary.csv` for execution completeness and the product verdict.

## IPv6

IPv6 scenarios are present, but setting `ipv6.enabled=true` only selects them.
A valid host/VM route, public server listener, firewall rules, UI-configured
addresses, and proxy support are all required. The published WFP results did not evaluate
IPv6 because the test environment lacked native public IPv6 connectivity.

## Security

The endpoint is an unauthenticated echo service. Restrict it by firewall to the
expected DIRECT and proxy egress addresses, and remove temporary rules after
use.

Do not commit:

- `.env`;
- generated `.pbprofile` files;
- credentials or SSH keys;
- private certificates;
- raw packet captures or crash dumps;
- unredacted runtime evidence.

See [SECURITY.md](SECURITY.md) and [Runtime safety](docs/runtime-safety.md).

## Documentation

- [End-to-end environment setup](docs/environment-setup.md)
- [Current test results](docs/test-results.md)
- [Orchestrator specification](docs/ORCHESTRATOR_SPEC.md)
- [Coverage model](docs/COVERAGE_MODEL.json)
- [Coverage explanation](docs/coverage-model.md)
- [Adding scenarios](docs/adding-scenarios.md)
- [Evidence format](docs/evidence-format.md)
- [Runtime safety](docs/runtime-safety.md)
- [Known defects](docs/known-defects.md)

## License

MIT. See [LICENSE](LICENSE).
