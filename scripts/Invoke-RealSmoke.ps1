[CmdletBinding()]
param(
    [Parameter(Mandatory)][switch]$ConfirmRealRuntime,
    [string]$EnvPath,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $ConfirmRealRuntime) { throw 'REAL_RUNTIME_CONFIRMATION_REQUIRED' }
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $repoRoot '.env' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot 'evidence/real-smoke' }
if (-not (Test-Path -LiteralPath $EnvPath -PathType Leaf)) { throw 'PRIVATE_ENV_REQUIRED' }

# This entrypoint selects the accepted Stage 3.4A TCP issue206 PROXY->BLOCK
# contract. The runner performs hash/environment preflight before product start,
# captures lifecycle/client/ProxyBridge evidence, dynamically queries exact
# payload SHA matches from the VPS after client completion, and cleans up the
# CLI in a lifecycle finally block. It never mutates firewall, driver/service,
# VPS configuration, installer state, or signing policy.
$runnerOutput = @(& (Join-Path $repoRoot 'Run-WfpMatrix.ps1') `
    -EnvPath $EnvPath `
    -CapabilitiesPath (Join-Path $repoRoot 'config/capabilities.json') `
    -SuitePath (Join-Path $repoRoot 'config/suites/real-smoke.json') `
    -KnownDefectsPath (Join-Path $repoRoot 'config/known-defects.json') `
    -ScenarioRoot (Join-Path $repoRoot 'scenarios') `
    -OutputRoot $OutputRoot `
    -Only 'issue206-proxy-to-block-abortive' `
    -MaxScenarios 1 `
    -StopOnInfrastructureFailure `
    -AllowProductRuntime)
$runnerOutput | ForEach-Object { Write-Output $_ }

$completion = @($runnerOutput | Where-Object { [string]$_ -match '^RUN_COMPLETE\s' }) | Select-Object -Last 1
if ($null -eq $completion -or [string]$completion -notmatch '\brun_id=(?<run_id>[^\s]+)') { throw 'REAL_SMOKE_RESULT_NOT_FOUND' }
$runId = [string]$Matches.run_id
$resultsPath = Join-Path (Join-Path $OutputRoot $runId) 'results.jsonl'
if (-not (Test-Path -LiteralPath $resultsPath -PathType Leaf)) { throw 'REAL_SMOKE_RESULTS_MISSING' }
$records = @(
    foreach ($line in [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $resultsPath))) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { $line | ConvertFrom-Json }
    }
)
$executed = @($records | Where-Object { [bool]$_.selected -and [int]$_.attempt -gt 0 })
if ($executed.Count -ne 1) { throw "REAL_SMOKE_RESULT_COUNT_INVALID=$($executed.Count)" }
$runtimeStatus = [string]$executed[0].status
$formalStatus = $(
    if ($runtimeStatus -eq 'PASS') { 'PASS' }
    elseif ($runtimeStatus -match 'HOLD|AMBIGUOUS|CONTAMINATED') { 'HOLD' }
    else { 'FAIL' }
)
Write-Output "REAL_SMOKE_RESULT=$formalStatus run_id=$runId runtime_status=$runtimeStatus"
if ($formalStatus -ne 'PASS') { throw "REAL_SMOKE_$formalStatus status=$runtimeStatus" }
