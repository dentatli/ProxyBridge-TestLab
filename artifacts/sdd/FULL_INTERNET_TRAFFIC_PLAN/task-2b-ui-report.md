# Milestone 15 / Task 2b-UI report

Status: DONE

## RED

Test-first edits were already present only in `Ui.RunProbe/Program.cs` and
`tests/Test-RunOrchestration.ps1`. No Task 2b-UI production file had been
changed when RED was captured.

Command:

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' build '.\ui\ProxyBridge.TestLab.Ui.RunProbe\ProxyBridge.TestLab.Ui.RunProbe.csproj' --configuration Release --nologo
```

Result: exit `1`. The UI dependency built, then RunProbe failed because the
test-requested production contracts did not exist. Representative exact
diagnostics were:

```text
Program.cs(94,29): error CS0103: Имя "DerivedRunCapabilitySnapshot" не существует в текущем контексте.
Program.cs(102,31): error CS0103: Имя "RunCapabilityReadiness" не существует в текущем контексте.
Program.cs(122,5): error CS0103: Имя "RunCapabilityDocument" не существует в текущем контексте.
Предупреждений: 0
Ошибок: 16
```

The PowerShell wrapper was not run against the stale previously built DLL
after this expected compile RED; that would not have executed the new probe
checks.

## Implementation

- Added one shared `RuntimeCapabilityService` and public-safe
  `DerivedRunCapabilitySnapshot`. The snapshot exposes only booleans/statuses;
  it does not expose browser path/hash/version or server receipt data.
- `local_browser_runtime` is true only for a `READY` browser status containing
  an allowlisted Edge/Chrome/Chromium basename/identity, a version and a
  64-character hexadecimal SHA-256.
- `server_browser_origin` is true only for exact server state `READY`; `STALE`
  and every other state fail closed.
- `RunCapabilityReadiness` checks only capabilities named by each selected
  `CatalogScenario.Requires`. Fixture mode returns no browser capability
  gates, and non-browser selections pass both browser gates.
- `RunReadinessService` obtains one snapshot and passes that same snapshot into
  immutable preflight. `PowerShellRunExecutor` refreshes a snapshot for a real
  run. Mock execution does not query browser/server state.
- `RunCapabilityDocument` is the single writer used by both real-run and
  immutable-preflight capability documents, preventing derivation drift.
- Public gate text contains only concise English state/remediation. No manual
  browser path, hash, client executable or `.env` field was added.

## Changed files

- `ui/ProxyBridge.TestLab.Ui/Services/RuntimeCapabilityService.cs` (new)
- `ui/ProxyBridge.TestLab.Ui/Services/RunReadinessService.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/RunExecutor.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/ImmutablePreflightService.cs`
- `ui/ProxyBridge.TestLab.Ui/Program.cs`
- `ui/ProxyBridge.TestLab.Ui.RunProbe/Program.cs`
- `tests/Test-RunOrchestration.ps1`
- `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-2b-ui-report.md`

## GREEN

Build command:

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' build '.\ui\ProxyBridge.TestLab.Ui.RunProbe\ProxyBridge.TestLab.Ui.RunProbe.csproj' --configuration Release --nologo
```

Build result: exit `0`; both UI and RunProbe built. Output summary was
`Предупреждений: 1`, `Ошибок: 0`; the warning was nullable diagnostic
`CS8601` at existing `LocalArtifactService.cs(205,57)`.

Focused test command (run exactly once after implementation):

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File '.\tests\Test-RunOrchestration.ps1'
```

Result: exit `0`.

```text
PASS: safe UI run orchestration
```

## Self-review and prohibited actions

The incremental Task 2b-UI diff was reviewed against `task-2b-ui-before`.
Browser worker/origin, scenario catalog, product code, network assertions and
server transport were not changed.

No UI, browser, ProxyBridge product, traffic client, driver/service, listener,
SSH, loopback or external-network activity was started. No deployment,
commit, push, subagent, firewall/profile change or runtime acceptance claim
was performed.

## Fix round 1/5

Initial review found that mock capability materialization disabled the two
browser requirements, generic server readiness was represented by the
browser-origin flag, renamed executables could pass browser discovery, and the
focused tests did not exercise the production readiness/capability-file seams.
The prior RED/GREEN evidence above is preserved unchanged.

### Fix-round RED

The focused tests were changed first to require:

- rejection of the actual RunProbe host copied and renamed to `msedge.exe`;
- deterministic positive browser discovery through a test-only file-version
  metadata provider at the external file-metadata boundary;
- real `RunReadinessService.PrepareAsync` behavior for browser, non-browser and
  mock selections;
- real `RunCapabilityFileService.WriteForExecutionAsync` mock materialization;
- actual `ScenarioCatalog.Test-ScenarioSelection` selection of
  `canary-browser-download` from that materialized mock capability file.

Command:

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' build '.\ui\ProxyBridge.TestLab.Ui.RunProbe\ProxyBridge.TestLab.Ui.RunProbe.csproj' --configuration Release --nologo
```

Result: exit `1`, `Предупреждений: 0`, `Ошибок: 4`. Exact missing-contract
diagnostics were `CS0246` for `IRunCatalogProvider`, `IRunSettingsProvider`,
`ILocalRuntimeStatusProvider`, and `IRuntimeCapabilityService`. These are the
test-requested production integration boundaries. The PowerShell wrapper was
not run against a stale probe DLL after the compile RED.

### Fix-round implementation

- Added narrow interfaces for catalog, saved-settings, local-runtime and
  derived-runtime state. RunProbe fakes only these external state boundaries;
  it executes the real readiness and capability-file services.
- Added a distinct `ServerReady` snapshot value. The unconditional generic
  Server Setup gate remains required for every real run and uses
  `ServerReady`; the selection-aware `server_browser_origin` gate uses its own
  value and passes when the selected scenario does not require it. This follows
  the ledger ruling; if endpoint-core and per-plugin readiness diverge later,
  the server status contract will need per-plugin readiness.
- Added `FixtureSelection`, used only by mock capability-file materialization.
  It enables the selected browser fixture requirements without querying or
  claiming real browser/server availability. The mock runner mode remains the
  authoritative fixture isolation boundary.
- Added the instance-based `RunCapabilityFileService`, shared by execution and
  immutable preflight. Real execution derives current state; immutable
  preflight receives the exact readiness snapshot; mock execution uses only
  `FixtureSelection`.
- Strengthened browser discovery to require a coherent allowlisted basename,
  file-version `ProductName`, `OriginalFilename`, and nonempty version before
  SHA-256 is computed. Edge and Chrome require their matching original
  executable names; Chromium accepts `chromium.exe` or the Chromium build name
  `chrome.exe`. This is file-version identity validation, not cryptographic
  publisher verification.
- The deterministic positive test injects only file-version resource metadata
  for a test-owned copied image. Production always reads `FileVersionInfo`
  directly from the candidate file.
- Applied the narrow nullable-safe browser-path local in
  `LocalArtifactService`, resolving `CS8601` without changing public behavior.

Fix-round changed files:

- `ui/ProxyBridge.TestLab.Ui/Services/CatalogService.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/SettingsStore.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/LocalArtifactService.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/RuntimeCapabilityService.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/RunReadinessService.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/RunExecutor.cs`
- `ui/ProxyBridge.TestLab.Ui/Services/ImmutablePreflightService.cs`
- `ui/ProxyBridge.TestLab.Ui/Program.cs`
- `ui/ProxyBridge.TestLab.Ui.RunProbe/Program.cs`
- `tests/Test-RunOrchestration.ps1`
- `artifacts/sdd/FULL_INTERNET_TRAFFIC_PLAN/task-2b-ui-report.md`

### Fix-round GREEN

Build command:

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' build '.\ui\ProxyBridge.TestLab.Ui.RunProbe\ProxyBridge.TestLab.Ui.RunProbe.csproj' --configuration Release --nologo
```

Build result: exit `0`; `Предупреждений: 0`, `Ошибок: 0`.

Focused test command, run exactly once after the fix:

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File '.\tests\Test-RunOrchestration.ps1'
```

Result: exit `0`.

```text
PASS: safe UI run orchestration
```

### Fix-round self-review and prohibited actions

The scoped changes retain the unconditional generic server gate, keep browser
capabilities selection-aware, and do not change the scenario catalog, browser
worker/origin, product code, server transport or network assertions. The
public settings/UI scan still finds no browser path/hash controls.

No UI, runner, browser, ProxyBridge product, traffic client, driver/service,
listener, SSH, loopback or external-network activity was started. No
deployment, commit, push, subagent, firewall/profile change or runtime
acceptance claim was performed.
