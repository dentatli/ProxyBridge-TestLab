# ProxyBridge Automated Test Orchestrator — Design v1

## 1. Objective

Build a deterministic, resumable test orchestrator for ProxyBridge that:

- applies and verifies rule sets automatically;
- executes synthetic scenarios through `pb_net_client.exe`;
- collects ProxyBridge, client, VPS and environment evidence;
- records product failures and continues with independent scenarios;
- stops on harness, infrastructure or state-integrity failures;
- supports capability switches such as IPv6 disabled;
- produces a coverage report showing tested, failed, skipped, blocked and
  unsupported areas.

Literal testing of every possible Internet packet sequence is impossible.
The target is exhaustive coverage of meaningful equivalence classes, exhaustive
coverage of critical interactions, and pairwise/generated coverage for the
remaining combinatorial dimensions.

## 2. Configuration separation

### `.env`

Use only for flat machine-specific values:

- IP addresses;
- ports;
- file paths;
- SSH location;
- expected hashes;
- proxy endpoint.

Do not store scenario selection or nested policy in `.env`.

### `config/capabilities.json`

Describes what the current environment can actually test.

Examples:

- IPv4 enabled;
- IPv6 disabled with reason;
- performance disabled until correctness GO;
- packet capture unavailable;
- real-app tests disabled.

A scenario whose requirement is disabled becomes `SKIPPED_CAPABILITY`, not FAIL.

### `config/suites.json`

Controls what to run:

- include/exclude tags;
- include/exclude scenario IDs;
- repeat counts;
- continue/stop policy;
- known-defect policy;
- maximum consecutive product failures.

### `scenarios/*.json`

One declarative scenario per file. Each scenario contains:

- requirements;
- rule set;
- client arguments;
- server/VPS expectations;
- assertions;
- reset policy;
- tags.

## 3. Repository layout

```text
ProxyBridge-Test-Orchestrator/
├── .env.example
├── .gitignore
├── Run-WfpMatrix.ps1
├── config/
│   ├── capabilities.json
│   ├── suites.json
│   ├── known-defects.json
│   └── scenario-schema.json
├── modules/
│   ├── Env.psm1
│   ├── RuleAdapter.psm1
│   ├── ClientRunner.psm1
│   ├── VpsEvidence.psm1
│   ├── ProxyBridgeEvidence.psm1
│   ├── HealthChecks.psm1
│   ├── Assertions.psm1
│   └── Report.psm1
├── scenarios/
│   ├── base-policy/
│   ├── issue206/
│   ├── issue209/
│   ├── tcp/
│   ├── udp/
│   ├── lifecycle/
│   ├── rules/
│   ├── dns/
│   ├── security/
│   ├── real-apps/
│   └── performance/
└── docs/
    ├── ORCHESTRATOR_SPEC.md
    └── COVERAGE_MODEL.json
```

## 4. Status model

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

Continue after:

- PASS;
- FAIL_PRODUCT, if post-test health checks pass;
- EXPECTED_FAIL;
- HOLD_AMBIGUOUS, only for independent later scenarios;
- capability/selection skips.

Stop the full run after:

- FAIL_HARNESS;
- FAIL_INFRASTRUCTURE;
- CONTAMINATED;
- changed binary hashes;
- unknown active rule state;
- endpoint or SOCKS backend health failure;
- driver/service failure;
- evidence corruption.

## 5. Execution lifecycle per scenario

```text
resolve .env variables
→ check capability requirements
→ health preflight
→ verify binary hashes
→ apply exact rule set
→ read rules back and compare
→ capture log offsets/timestamps
→ run client
→ collect client JSONL and exit code
→ collect new ProxyBridge lines
→ query VPS by exact payload SHA-256
→ execute assertions
→ classify result
→ save evidence
→ post-test health check
→ apply reset policy
→ continue or stop
```

## 6. Rule adapter boundary

Do not use GUI coordinate automation as the primary mechanism.

Priority:

1. official `ProxyBridge_CLI.exe` rule commands;
2. official exported API from `ProxyBridgeCore.dll`;
3. documented persistent configuration format plus controlled reload;
4. GUI automation only as a temporary last resort.

Before implementing the runner, perform a read-only audit of the available CLI,
exports and configuration files.

## 7. Coverage strategy

### Exhaustive critical matrices

Run every combination for:

- protocol × family × action;
- UDP socket mode × action;
- all six issue #206 action transitions;
- both issue #209 directions;
- basename and full-path process selectors;
- critical lifecycle transitions;
- direct-leak/security assertions.

### Stateful hand-authored scenarios

Required for:

- same-port generation reuse;
- concurrent TCP/UDP identity;
- delayed UDP responses;
- receive-only UDP;
- reconnect and backend restart;
- process/driver restart;
- rule hot update and persistence.

### Generated pairwise coverage

Use pairwise generation for lower-risk dimensions such as:

- payload size;
- endpoint mode;
- close mode;
- local topology;
- rule selector variant;
- concurrency level.

Do not generate the full Cartesian product blindly.

## 8. Coverage report

The runner must produce:

```text
coverage.json
summary.csv
results.jsonl
failures.jsonl
skipped.jsonl
transcript.txt
resolved-suite.json
environment-snapshot.json
```

Coverage cells must distinguish:

- tested PASS;
- tested FAIL;
- expected fail;
- blocked by known defect;
- skipped by environment;
- unsupported by product scope;
- not yet implemented.

## 9. Implementation phases

### Stage 3.1E-0 — read-only control-plane audit

No source changes.

Determine:

- whether `ProxyBridge_CLI.exe` can list/add/update/delete/enable rules;
- whether it can list/add proxy configurations;
- where the GUI persists configuration;
- whether rules can be read back deterministically;
- whether update completion is observable in logs;
- whether a safe reset-to-known-rule-set operation exists.

### Stage 3.1E-1 — runner foundation

Implement only:

- `.env` loading;
- JSON validation;
- capability filtering;
- dry-run;
- result/evidence directory creation;
- health checks;
- a mock rule adapter;
- one loopback scenario.

### Stage 3.1E-2 — real rule adapter

Implement one supported control-plane method and prove:

```text
apply rule
→ read back
→ exact comparison
→ one automated TCP DIRECT smoke
```

### Stage 3.1E-3 — automated WFP smoke

Reproduce one already accepted manual scenario and compare evidence.

Recommended:

```text
Stage 3.4A PROXY→BLOCK
```

### Stage 3.1E-4 — IPv4 TCP and issue #206 suite

Automate:

- TCP DIRECT/BLOCK/PROXY;
- all six issue #206 transitions;
- graceful and abortive close;
- rule persistence/hot update.

### Stage 3.1E-5 — UDP and issue #209 suite

Add connected/unconnected UDP, known-defect classification, collision tests,
reconnect and delayed-response scenarios.

### Later stages

Add IPv6 only when the capability profile enables it. Add real applications and
performance only after synthetic correctness is sufficiently stable.

## 10. First implementation gate

Do not build the full orchestrator before the control-plane audit. The first
unknown is how rules can be changed and read back without GUI interaction.
Everything else is already sufficiently specified.

## 11. Implemented safe boundary

The current code implements dry-run, fixture-backed mock orchestration, and a
separately gated real-smoke path. It performs
catalog discovery, capability and suite selection, known-defect classification,
profile generation/validation, executor-specific client plans, mock evidence assertions,
failure policy and deterministic reports. Selection is recorded for the entire
catalog before scenario execution, so a later stop remains auditable.

Real product, process-observation and network operations are never selected by
default. They require `-AllowProductRuntime` and the separate confirmed
real-smoke script. The real path provides binary hash/process/service/TCP
preflight, asynchronous CLI/client lifecycle, textual ProxyBridge evidence and
one gated SSH query per canonical payload SHA after client completion. A
successful empty exact-match query is complete BLOCK no-leak evidence;
import-existing remains an explicit manual-audit option. No real adapter is
invoked by dry-run, mock or the automated tests.

The 135 catalog IDs are declarations, not 135 working tests. Every expanded
entry is explicitly `EXECUTABLE`, `DECLARATIVE_ONLY` (with a reason), or
`UNSUPPORTED_PRODUCT_SCOPE`. Only real execution can produce tested coverage;
dry-run and mock retain `DRY_RUN_*`/`MOCK_*` statuses. Literal exhaustive
testing of all packet sequences is neither possible nor claimed.
