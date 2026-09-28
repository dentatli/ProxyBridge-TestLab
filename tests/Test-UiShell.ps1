[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Join-Path $repoRoot 'ui\ProxyBridge.TestLab.Ui'
$program = Get-Content -LiteralPath (Join-Path $projectRoot 'Program.cs') -Raw
$preflight = Get-Content -LiteralPath (Join-Path $projectRoot 'Services\ImmutablePreflightService.cs') -Raw
$readiness = Get-Content -LiteralPath (Join-Path $projectRoot 'Services\RunReadinessService.cs') -Raw
$html = Get-Content -LiteralPath (Join-Path $projectRoot 'wwwroot\index.html') -Raw
$javascript = Get-Content -LiteralPath (Join-Path $projectRoot 'wwwroot\app.js') -Raw

Assert-True ($program -match 'UseUrls\("http://127\.0\.0\.1:5178"\)') 'UI controller must bind to loopback only'
Assert-True ($program -match 'IPAddress\.IsLoopback') 'UI controller must reject non-loopback clients'
Assert-True ($program -match 'real_runtime_available\s*=\s*true') 'release controller must expose the guarded real adapter'
Assert-True ($preflight -match 'SignedImmutablePreflightReceipt' -and $preflight -match 'PreflightOnly') 'real adapter must require signed immutable preflight'
Assert-True ($readiness -match 'VerifyAsync' -and $readiness -match 'ConfirmationNonce') 'real confirmation must be issued only through readiness and preflight gates'
Assert-True ($program -match 'MapPost\("/runs/dry-run"') 'Milestone 4 must expose run review'
Assert-True ($program -match 'MapPost\("/runs"') 'Milestone 4 must expose guarded run queueing'
Assert-True ($program -match 'MapPost\("/server/validate"') 'Milestone 3 must expose guarded server validation'
Assert-True ($program -match 'MapPost\("/server/plan"') 'Milestone 3 must expose exact server planning'
Assert-True ($html -match 'lang="en"') 'UI must be English'
Assert-True ($html -match 'Test server is not configured') 'UI must explain the server readiness lock'
Assert-True ($html -match 'Run Tests</button>') 'UI must display the run affordance'
Assert-True ($html -match 'data-open-run>Run Tests</button>') 'run affordance must open the guarded Run Builder'
Assert-True ($javascript -match 'this UI does not recalculate the verdict') 'result explanation must preserve runner authority'

$catalogJson = & (Join-Path $repoRoot 'scripts\Export-UiCatalog.ps1') `
    -ScenarioRoot (Join-Path $repoRoot 'scenarios') `
    -KnownDefectsPath (Join-Path $repoRoot 'config\known-defects.json')
$catalog = $catalogJson | ConvertFrom-Json
Assert-Equal 205 $catalog.Count 'UI catalog must use all authoritative native and protocol-aware scenarios'
Assert-True (@($catalog | Where-Object { $_.implementation_status -eq 'EXECUTABLE' }).Count -gt 0) 'UI catalog must expose executable status'
Assert-True (@($catalog | Where-Object { $_.implementation_status -eq 'DECLARATIVE_ONLY' }).Count -gt 0) 'UI catalog must expose declarative status'
Assert-Equal 5 @($catalog | Where-Object { $_.implementation_status -eq 'SYSTEM_CHECK' }).Count 'UI catalog must distinguish system checks from traffic tests'
Assert-Equal 7 @($catalog | Where-Object { $_.implementation_status -eq 'CAPABILITY_GATED' }).Count 'UI catalog must expose capability-gated coverage honestly'
Assert-True (@($catalog | Where-Object { $null -ne $_.known_defect }).Count -gt 0) 'UI catalog must expose public known-defect metadata'
foreach ($scenario in $catalog) {
    Assert-True ($null -eq $scenario.PSObject.Properties['rule_set']) 'UI catalog must not expose resolved rule sets'
    Assert-True ($null -eq $scenario.PSObject.Properties['client']) 'UI catalog must not expose client runtime plans'
}

$fixtureRoot = Join-Path $repoRoot 'tests\fixtures\ui-runs\mock-ui-preview'
$summary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'summary.json') -Raw | ConvertFrom-Json
Assert-True ([bool]$summary.fixture) 'sample report must be explicitly identified as a fixture'
Assert-Equal 'mock' ([string]$summary.run_mode) 'sample report must never claim real runtime'
Assert-True (Test-Path -LiteralPath (Join-Path $fixtureRoot 'results.jsonl')) 'sample result list must exist'

'PASS: read-only UI shell'
