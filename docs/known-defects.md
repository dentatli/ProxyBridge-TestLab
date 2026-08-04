# Known defects

`config/known-defects.json` currently records:

- full-path watched-rule mismatch — run as regression;
- watched-process UDP DIRECT silent drop — run as regression;
- UDP PROXY reverse-source leak — run as regression;
- issue #206 PROXY to DIRECT same-port egress regression — run as regression;
- issue #209 collision prerequisite — do not run until deterministic setup is
  reachable.

A matching `do-not-run` item is `BLOCKED_BY_KNOWN_DEFECT`. A matching
`run-as-regression` item classifies fixture-backed mock rejection as
`MOCK_EXPECTED_FAIL`; only an authorized real-runtime rejection is
`EXPECTED_FAIL`.
