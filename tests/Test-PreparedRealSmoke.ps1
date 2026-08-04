[CmdletBinding()]param([switch]$EmitSummary)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root=Split-Path -Parent $PSScriptRoot
foreach($module in @('Env','Config','RuntimeEnvironment','DirectBaseline','ScenarioCatalog','ProfileAdapter','ClientRunner','MockRuntime','Assertions')){Import-Module (Join-Path $root "modules/$module.psm1") -Force}

$raw=Import-DotEnv (Join-Path $PSScriptRoot 'fixtures/.env.test')
$live=[System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase);foreach($key in $raw.Keys){$live[[string]$key]=[string]$raw[$key]}
$live['PB_VM_IPV4']='10.20.0.20';$live['PB_VPS_IPV4']='10.30.0.10';$live['PB_SOCKS_HOST']='10.40.0.10';$live['PB_SSH_HOST']='fixture-vps.internal';$null=$live.Remove('PB_VM_IPV6');$null=$live.Remove('PB_VPS_IPV6')
$runtime=Import-RuntimeConfig (Join-Path $root 'config/runtime.json')
$environment=Get-EffectiveRuntimeEnvironment -Environment $live -RuntimeConfig $runtime
$preparationPlan=New-RuntimeEnvironmentPlan -Environment $live -RuntimeConfig $runtime
$files=@{};foreach($binary in @($preparationPlan.binaries)){$files[[string]$binary.configured_path]=[string]$binary.expected_sha256}
$runtimeAdapter=New-MockRuntimeEnvironmentAdapter -Files $files -ServiceStates @('Running')
$preparation=Invoke-RuntimeEnvironmentPreparation -Plan $preparationPlan -Adapter $runtimeAdapter
Assert-Equal 'PASS_PREPARED' $preparation.status 'prepared real-smoke mock environment'

$baselinePlan=New-DirectBaselinePlan -Environment $environment -TimeoutMs 100
$baselineCollector={param($record)
    $received=[pscustomobject]@{event='MESSAGE_RECEIVED';sha256=$record.payload_sha256;local_ip=$record.remote_ip;local_port=$record.remote_port;remote_ip='192.0.2.50';remote_port=53000;bytes=64;error=''}
    $echoed=[pscustomobject]@{event='ECHOED';sha256=$record.payload_sha256;local_ip=$record.remote_ip;local_port=$record.remote_port;remote_ip='192.0.2.50';remote_port=53000;bytes=64;error=''}
    [pscustomobject]@{capture_complete=$true;complete_shas=@($record.payload_sha256);records=@($received,$echoed);query_results=@([pscustomobject]@{success=$true})}
}
$baseline=Invoke-DirectBaselineDiscovery -Plan $baselinePlan -Adapter (New-MockDirectBaselineAdapter) -VpsCollector $baselineCollector
Assert-Equal 'PASS_BASELINE' $baseline.status 'prepared real-smoke direct baseline'

$catalog=@(Import-ScenarioCatalog (Join-Path $root 'scenarios'))
$scenario=Resolve-JsonVariables -InputObject ($catalog|Where-Object scenario_id -eq 'issue206-proxy-to-block-abortive') -Variables $environment
$contract=Import-ClientContract (Join-Path $root 'config/client-contract.json')
$temp=New-TestDirectory
try{
    $clientPlan=New-ClientPlan -Scenario $scenario -ExecutablePath $environment['PB_CLIENT_EXE'] -RunId 'prepared-real-smoke' -JsonlPath (Join-Path $temp 'client.jsonl') -Contract $contract
    $mock=Invoke-MockScenario -Scenario $scenario -ClientPlan $clientPlan -FixtureRoot (Join-Path $PSScriptRoot 'fixtures/mock') -EvidenceDirectory $temp -Environment $environment
    $context=[pscustomobject]@{vps_capture_complete=$true;vps_capture_complete_shas=@($mock.client_result.canonical_records.payload_sha256);channel_capture_completed=$true;records_found=$false;direct_egress_ip=$baseline.direct_egress_ip;proxy_egress_ip='';expected_process='pb_net_client.exe'}
    $assertion=Test-ScenarioAssertions -Scenario $scenario -ClientPlan $clientPlan -ClientResult $mock.client_result -VpsRecords $mock.vps_records -ProxyBridgeRecords @() -EvidenceContext $context -RunMode real
    Assert-Equal 'PASS' $assertion.outcome 'prepared mock real smoke must pass without internal route records'
    $postClean=Test-RuntimeEnvironmentClean -Plan $preparationPlan -Adapter $runtimeAdapter
    Assert-True $postClean.passed 'prepared mock real smoke post-run state must be clean'
    if($EmitSummary){
        "ENVIRONMENT_PREPARED=$($preparation.status)"
        "DIRECT_BASELINE=$($baseline.status)"
        "PREPARED_REAL_SMOKE=$($assertion.outcome) basis=$($assertion.evidence_basis)"
        "POST_RUN_CLEAN=$($postClean.status)"
    }
}
finally{Remove-Item -LiteralPath $temp -Recurse -Force}
'PASS: prepared real-smoke mock'
