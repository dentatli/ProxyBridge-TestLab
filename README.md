# ProxyBridge-TestLab

Independent deterministic test and evidence-collection framework for
[ProxyBridge](https://github.com/InterceptSuite/ProxyBridge).

ProxyBridge-TestLab validates Windows WFP routing behavior, TCP and UDP policy
enforcement, connection lifecycle handling, rule evaluation, SOCKS5 proxying,
known regressions, and externally verifiable route evidence.

This repository does not contain or modify ProxyBridge product code.

## Current status

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

### 3. Deploy the Linux endpoint

The endpoint listens on TCP and UDP ports `41001` and `41002` and writes JSONL
evidence. Follow the complete server and firewall instructions in
[End-to-end environment setup](docs/environment-setup.md).

### 4. Configure the tester

```powershell
Copy-Item '.\.env.example' '.\.env'
notepad '.\.env'
```

Replace every documentation address, path, and hash with the actual isolated
test-environment values. `.env` is ignored and must never be committed.

Configure unavailable capabilities in:

```text
config/capabilities.json
```

### 5. Validate TestLab itself

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\tests\Run-All.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\scripts\Invoke-DryRun.ps1' -FixtureMode
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\scripts\Invoke-MockMatrix.ps1' -FixtureMode
```

### 6. Run one real smoke

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\scripts\Invoke-RealSmoke.ps1' `
    -ConfirmRealRuntime
```

### 7. Run the current real IPv4 diagnostic subset

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\Run-WfpMatrix.ps1' `
    -EnvPath '.\.env' `
    -CapabilitiesPath '.\config\capabilities.json' `
    -SuitePath '.\config\suites\real-diagnostic-ipv4.json' `
    -KnownDefectsPath '.\config\known-defects.json' `
    -ClientContractPath '.\config\client-contract.json' `
    -RuntimeConfigPath '.\config\runtime.json' `
    -ScenarioRoot '.\scenarios' `
    -OutputRoot '.\evidence\real-diagnostic-ipv4' `
    -AllowProductRuntime `
    -PrepareRuntimeEnvironment `
    -ContinueOnProductFailure
```

The diagnostic suite continues after scenario-local results so it can report
all current executable tests, but it stops on contaminated state.

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
A valid host/VM route, public server listener, firewall rules, `.env` addresses,
and proxy support are all required. The published WFP results did not evaluate
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
