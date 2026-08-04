# Adding scenarios

Use machine-specific values only through `${ENV_KEY}` placeholders. Never put a
real IP address, hostname, credential or local path in a scenario catalog.

Scenarios may be full documents or compact entries under a catalog document.
Every expanded scenario has a unique `scenario_id`, unique tags,
`schema_version: 1`, capability requirements, a coverage group, rule/client
plans and assertions. Critical protocol/family/action combinations must be
listed explicitly. Use the `pairwise` form only for secondary dimensions.

Every scenario must also declare `implementation_status`. Use `EXECUTABLE` only
when the selected command builder and evidence assertions encode the defining
semantic. `DECLARATIVE_ONLY` requires a concrete `implementation_reason` and is
never selected by a real suite. Dry-run reports it as `NOT_IMPLEMENTED`; mock
may only report the orchestration contract as `MOCK_HOLD`.

Capability absence produces `SKIPPED_CAPABILITY`. Disabled or suite-filtered
entries produce `SKIPPED_SELECTION`. Product areas not claimed by ProxyBridge
use `UNSUPPORTED_PRODUCT_SCOPE`. Known defects belong in
`config/known-defects.json`, with either `do-not-run` or `run-as-regression`.

Run `tests/Test-Catalog.ps1` and the full `tests/Run-All.ps1` after editing the
catalog. Do not run real smoke as part of catalog authoring.
