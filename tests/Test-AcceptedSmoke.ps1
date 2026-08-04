[CmdletBinding()]param([switch]$EmitSummary)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root=Split-Path -Parent $PSScriptRoot
foreach($module in @('Env','Config','ScenarioCatalog','ProfileAdapter','ClientRunner','MockRuntime','Assertions')){Import-Module (Join-Path $root "modules/$module.psm1") -Force}
$environment=Get-EffectiveRuntimeEnvironment -Environment (Import-DotEnv (Join-Path $PSScriptRoot 'fixtures/.env.test')) -RuntimeConfig (Import-RuntimeConfig (Join-Path $root 'config/runtime.json'))
$catalog=@(Import-ScenarioCatalog (Join-Path $root 'scenarios'))
$scenario=Resolve-JsonVariables -InputObject ($catalog|Where-Object scenario_id -eq 'issue206-proxy-to-block-abortive') -Variables $environment
$contract=Import-ClientContract (Join-Path $root 'config/client-contract.json')
$temp=New-TestDirectory
try{
    $plan=New-ClientPlan -Scenario $scenario -ExecutablePath $environment['PB_CLIENT_EXE'] -RunId 'accepted-smoke' -JsonlPath (Join-Path $temp 'client.jsonl') -Contract $contract -ExpectedSha256 $environment['PB_EXPECTED_CLIENT_SHA256']
    $mock=Invoke-MockScenario -Scenario $scenario -ClientPlan $plan -FixtureRoot (Join-Path $PSScriptRoot 'fixtures/mock') -EvidenceDirectory $temp -Environment $environment
    $context=[pscustomobject]@{
        vps_capture_complete=$true;vps_capture_complete_shas=@($mock.client_result.canonical_records|ForEach-Object{[string]$_.payload_sha256})
        channel_capture_completed=$true;records_found=$false;direct_egress_ip='192.0.2.50';proxy_egress_ip='';expected_process='pb_net_client.exe'
    }
    $assertion=Test-ScenarioAssertions -Scenario $scenario -ClientPlan $plan -ClientResult $mock.client_result -VpsRecords $mock.vps_records -ProxyBridgeRecords @() -EvidenceContext $context -RunMode real
    Assert-Equal 'PASS' $assertion.outcome 'accepted PROXY then BLOCK smoke must pass from complete external evidence without internal records'
    Assert-True $assertion.external_route_proof_complete 'accepted smoke external route proof must be complete'
    Assert-True (-not $assertion.records_found) 'accepted smoke fixture must contain no internal records'
    Assert-Equal 'CLIENT+VPS+DIRECT_BASELINE' $assertion.evidence_basis 'accepted smoke evidence basis'
    if($EmitSummary){"ACCEPTED_SMOKE=$($assertion.outcome) basis=$($assertion.evidence_basis) internal_records=$($assertion.records_found)"}
}
finally{Remove-Item -LiteralPath $temp -Recurse -Force}
'PASS: accepted smoke external evidence'
