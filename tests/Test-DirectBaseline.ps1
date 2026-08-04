[CmdletBinding()]param([switch]$EmitSummary)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root=Split-Path -Parent $PSScriptRoot
foreach($module in @('Env','Config','DirectBaseline')){Import-Module (Join-Path $root "modules/$module.psm1") -Force}
$environment=Get-EffectiveRuntimeEnvironment -Environment (Import-DotEnv (Join-Path $PSScriptRoot 'fixtures/.env.test')) -RuntimeConfig (Import-RuntimeConfig (Join-Path $root 'config/runtime.json'))
$plan=New-DirectBaselinePlan -Environment $environment -TimeoutMs 100
Assert-Equal 'powershell-dotnet-tcp-control' $plan.executor 'baseline must use internal .NET control flow'
Assert-True ([string]$plan.watched_application -ne 'powershell.exe') 'baseline control must not use watched client executable'

$collector={
    param($record)
    $received=[pscustomobject]@{event='MESSAGE_RECEIVED';sha256=$record.payload_sha256;local_ip=$record.remote_ip;local_port=$record.remote_port;remote_ip='192.0.2.50';remote_port=52000;bytes=64;error=''}
    $echoed=[pscustomobject]@{event='ECHOED';sha256=$record.payload_sha256;local_ip=$record.remote_ip;local_port=$record.remote_port;remote_ip='192.0.2.50';remote_port=52000;bytes=64;error=''}
    return [pscustomobject]@{capture_complete=$true;complete_shas=@($record.payload_sha256);records=@($received,$echoed);query_results=@([pscustomobject]@{success=$true})}
}
$result=Invoke-DirectBaselineDiscovery -Plan $plan -Adapter (New-MockDirectBaselineAdapter) -VpsCollector $collector
Assert-True $result.passed 'exact baseline client and VPS evidence must pass'
Assert-Equal '192.0.2.50' $result.direct_egress_ip 'baseline must derive source from VPS received record'
Assert-Equal 'PASS_BASELINE' $result.status 'baseline status must be explicit'

$failedCollector={param($record)[pscustomobject]@{capture_complete=$false;complete_shas=@();records=@();query_results=@([pscustomobject]@{success=$false})}}
$failed=Invoke-DirectBaselineDiscovery -Plan $plan -Adapter (New-MockDirectBaselineAdapter) -VpsCollector $failedCollector
Assert-True (-not $failed.passed) 'failed exact query must fail baseline'
Assert-Equal 'DIRECT_BASELINE_QUERY_INCOMPLETE' $failed.reason 'query failure must be precise'

$mismatch=Invoke-DirectBaselineDiscovery -Plan $plan -Adapter (New-MockDirectBaselineAdapter) -VpsCollector $collector -ExpectedDirectEgressIpv4 '203.0.113.9'
Assert-True (-not $mismatch.passed) 'explicit expected direct egress mismatch must fail'
Assert-Equal 'DIRECT_BASELINE_EXPECTED_EGRESS_MISMATCH' $mismatch.reason 'explicit override mismatch reason'

if($EmitSummary){
    "DIRECT_BASELINE=$($result.status) source_discovered=$(-not [string]::IsNullOrWhiteSpace($result.direct_egress_ip))"
    "DIRECT_BASELINE_QUERY_FAILURE=$($failed.status) reason=$($failed.reason)"
}
'PASS: direct baseline discovery'
