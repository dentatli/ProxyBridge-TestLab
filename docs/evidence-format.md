# Evidence format

Each run creates one unique directory containing:

```text
environment-snapshot.json
environment-preparation-plan.json
environment-preparation-result.json
immutable-preflight.json
direct-baseline-client.json
direct-baseline-vps.jsonl
direct-baseline-result.json
resolved-suite.json
selection.jsonl
results.jsonl
failures.jsonl
skipped.jsonl
summary.csv
coverage.json
transcript.txt
generated-profiles/
scenarios/<scenario-id>/rule-plan.json
scenarios/<scenario-id>/client-plan.json
scenarios/<scenario-id>/profile-validation.json
scenarios/<scenario-id>/reset-plan.json
scenarios/<scenario-id>/client-result.json
scenarios/<scenario-id>/proxybridge-evidence.json
scenarios/<scenario-id>/vps-evidence.json
scenarios/<scenario-id>/<phase>-vps.jsonl
scenarios/<scenario-id>/vps-collection-result.json
summary.json
SHA256SUMS
```

Text files use UTF-8 without BOM. JSONL contains one compact object per line.
Writes that replace whole reports use a same-directory temporary file. The
shared redaction boundary protects raw, JSON-escaped and Windows-escaped
environment values before transcript, JSONL, JSON, CSV or errors are emitted.
Structured values are recursively redacted before JSON serialization, so a
sensitive numeric field becomes the JSON string `[REDACTED]` without breaking
syntax. Short harmless scalars are not globally replaced.
Environment snapshots contain key, presence and category only.

Generated profiles are intentionally excluded from Git and audit packages
because they may contain resolved environment values. `SHA256SUMS` covers the
remaining run evidence and generated profiles inside the private evidence tree.

VPS JSONL uses the endpoint contract `event`, `sha256`, `local_ip`,
`local_port`, `remote_ip`, `remote_port`, `bytes`, and `error`. TCP receive
events are `MESSAGE_RECEIVED`, UDP receive events are `RECEIVED`, and echo
events are `ECHOED`. Dynamic collection creates one phase-specific file only
after a successful exact-SHA SSH query; an empty successful query is complete
for BLOCK. ProxyBridge route evidence is parsed from textual
Direct/Proxy/Blocked and single- or multi-line relay records and is correlated
by process, optional PID, destination, action and scoped CLI lifetime;
ProxyBridge text is not required to contain a payload SHA.

ProxyBridge route records are authoritative contradictions when present and
otherwise corroboration. Complete client plus exact-SHA VPS evidence may prove
TCP PROXY, DIRECT or BLOCK without internal Activity/RELAY output. Assertions
record `channel_capture_completed`, `records_found`,
`route_evidence_required`, `external_route_proof_complete` and
`evidence_basis`. Equal observed direct/proxy egress remains ambiguous unless
an internal route record resolves it.
