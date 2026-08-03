# ProxyBridge-TestLab

Independent deterministic test and evidence-collection framework for
[ProxyBridge](https://github.com/InterceptSuite/ProxyBridge).

ProxyBridge-TestLab is intended to validate Windows WFP routing behavior,
TCP and UDP correctness, connection lifecycle handling, rule evaluation,
SOCKS5 proxying, failure recovery, and regression scenarios.

This repository does not contain or modify ProxyBridge product code.

## Project status

The project is currently in the design and foundation stage.

Implemented:

- environment configuration skeleton;
- capability-based test selection;
- suite configuration;
- declarative scenario format;
- ProxyBridge `.pbprofile` schema;
- sanitized profile template;
- coverage model and orchestrator specification.

Not implemented yet:

- PowerShell test runner;
- automatic `.pbprofile` generation;
- ProxyBridge CLI lifecycle management;
- automatic VPS evidence collection;
- full scenario catalog;
- runtime GitHub Actions.

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
config/       Environment capabilities and suite selection
docs/         Architecture and coverage documentation
scenarios/    Declarative test scenarios
schemas/      JSON schemas
templates/    Public sanitized profile templates
```

Future layout:

```text
modules/      PowerShell runner modules
tests/        Unit, schema and loopback tests
harness/      Deterministic client and endpoint sources
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
config/suites.json
```

## Result statuses

Planned result classifications:

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
- [Environment setup](docs/environment-setup.md)

## License

MIT. See [LICENSE](LICENSE).
