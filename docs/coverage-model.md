# Coverage model

The machine-readable model is `COVERAGE_MODEL.json`. Coverage combines:

- exhaustive critical protocol × family × action interactions;
- explicit stateful issue #206/#209, lifecycle, UDP and security scenarios;
- deterministic pairwise coverage for payload, close mode, selector, endpoint,
  concurrency, topology and timing;
- disabled application/performance placeholders;
- explicit unsupported product-scope declarations.

The catalog is a declaration inventory, not a count of working tests. Reports
separately count declared, executable, declarative, unsupported and selected
entries. They distinguish `DRY_RUN_READY`, `NOT_IMPLEMENTED`, `MOCK_PASS`,
`MOCK_EXPECTED_FAIL`, `MOCK_HOLD`, `TESTED_PASS`, `TESTED_FAIL`, `EXPECTED_FAIL`,
`BLOCKED_BY_KNOWN_DEFECT`, `SKIPPED_CAPABILITY`, `SKIPPED_SELECTION`,
and `UNSUPPORTED_PRODUCT_SCOPE`. Literal all-packet
exhaustiveness is impossible and is not claimed.

`TESTED_PASS` and `TESTED_FAIL` are emitted only from real runtime. Dry-run and
mock coverage retain their own statuses and never become tested product claims.
