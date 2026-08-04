[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/ScenarioCatalog.psm1') -Force
$catalog = @(Import-ScenarioCatalog (Join-Path $root 'scenarios'))
Assert-Equal 135 $catalog.Count 'catalog declaration count must remain stable'
Assert-Equal $catalog.Count @($catalog.scenario_id | Sort-Object -Unique).Count 'scenario IDs must be unique'
$groups = @($catalog.coverage_group | Sort-Object -Unique)
Assert-True ($groups.Count -ge 12) 'catalog must cover at least 12 groups'
Assert-Equal 18 @($catalog | Where-Object { $_.coverage_group -eq 'base-policy' }).Count 'critical protocol/family/action matrix must remain exhaustive'
Assert-True (@($catalog | Where-Object { $_.coverage_group -eq 'issue206' }).Count -ge 9) 'all issue206 transitions plus legacy regression must exist'
Assert-Equal 7 @($catalog | Where-Object implementation_status -eq 'UNSUPPORTED_PRODUCT_SCOPE').Count 'unsupported product scope declarations must exist'
Assert-Equal 41 @($catalog | Where-Object implementation_status -eq 'EXECUTABLE').Count 'only exact-contract scenarios may be executable'
Assert-Equal 87 @($catalog | Where-Object implementation_status -eq 'DECLARATIVE_ONLY').Count 'declarative count must include unsupported payload-size executors'
Assert-Equal 18 @($catalog | Where-Object { $_.coverage_group -eq 'base-policy' -and $_.implementation_status -eq 'EXECUTABLE' }).Count 'base critical matrix must be executable and capability-gated'
Assert-True (@($catalog | Where-Object { $_.coverage_group -eq 'issue206' -and $_.implementation_status -eq 'EXECUTABLE' }).Count -ge 9) 'issue206 exact-contract scenarios must be executable'
foreach ($scenario in $catalog) {
    Assert-True (@($scenario.tags | Sort-Object -Unique).Count -eq @($scenario.tags).Count) "scenario tags must be unique"
    Assert-True (@('EXECUTABLE','DECLARATIVE_ONLY','UNSUPPORTED_PRODUCT_SCOPE') -contains [string]$scenario.implementation_status) 'implementation status must be explicit'
    if ($scenario.implementation_status -eq 'DECLARATIVE_ONLY') { Assert-True (-not [string]::IsNullOrWhiteSpace([string]$scenario.implementation_reason)) 'declarative scenario must explain missing executor' }
}
foreach ($id in @('rule-priority-overlap','rule-multiple-proxy-configs','rule-destination-domain','rule-protocol-both','tcp-half-close','tcp-server-close','tcp-process-termination','udp-one-socket-multiple-destinations','rule-hot-update','canary-http','performance-latency')) {
    Assert-Equal 'DECLARATIVE_ONLY' ($catalog | Where-Object scenario_id -eq $id).implementation_status "$id must not claim execution"
}
$negative = $catalog | Where-Object scenario_id -eq 'rule-missing-proxy-config'
Assert-Equal 'invalid-missing-proxy-config' $negative.profile_expectation 'missing proxy config must be intentional negative validation'
foreach ($id in @('tcp-payload-1','tcp-payload-small','tcp-payload-64k','tcp-payload-1m','udp-payload-0','udp-payload-65507')) {
    Assert-Equal 'DECLARATIVE_ONLY' ($catalog | Where-Object scenario_id -eq $id).implementation_status "$id requires unsupported configurable payload size"
}
Assert-Equal 'EXECUTABLE' ($catalog | Where-Object scenario_id -eq 'issue209-tcp-to-udp').implementation_status 'exact issue209 builder and three-record model must be executable'
Assert-Equal 'issue209-direct' ($catalog | Where-Object scenario_id -eq 'issue209-tcp-to-udp').mock_fixture_id 'executable issue209 must have a three-record mock fixture'
$realSmokeSuite = Get-Content -LiteralPath (Join-Path $root 'config/suites/real-smoke.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-SequenceEqual @('issue206-proxy-to-block-abortive') @($realSmokeSuite.selection.include_scenario_ids) 'real smoke must select exactly the accepted issue206 PROXY to BLOCK case'
$realSmokeScript = Get-Content -LiteralPath (Join-Path $root 'scripts/Invoke-RealSmoke.ps1') -Raw -Encoding UTF8
Assert-True ($realSmokeScript -match 'ConfirmRealRuntime') 'real smoke must require explicit confirmation'
Assert-True ($realSmokeScript -match 'REAL_SMOKE_RESULT=') 'real smoke must emit a formal result'
Assert-True ($realSmokeScript -notmatch 'ImportExistingVpsEvidence') 'real smoke must default to dynamic VPS collection'
$runnerScript = Get-Content -LiteralPath (Join-Path $root 'Run-WfpMatrix.ps1') -Raw -Encoding UTF8
Assert-True ($runnerScript -match 'New-VpsDynamicEvidencePlan') 'real runner must build dynamic per-payload VPS queries'
'PASS: catalog'
