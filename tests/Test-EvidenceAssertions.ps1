[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
foreach ($module in @('Env','Config','ScenarioCatalog','ProfileAdapter','ClientRunner','MockRuntime','ProxyBridgeEvidence','VpsEvidence','Assertions')) { Import-Module (Join-Path $root "modules/$module.psm1") -Force }

$environment = Get-EffectiveRuntimeEnvironment -Environment (Import-DotEnv (Join-Path $PSScriptRoot 'fixtures/.env.test')) -RuntimeConfig (Import-RuntimeConfig (Join-Path $root 'config/runtime.json'))
$contract = Import-ClientContract (Join-Path $root 'config/client-contract.json')
$catalog = @(Import-ScenarioCatalog (Join-Path $root 'scenarios'))
$defects = Import-KnownDefectsConfig (Join-Path $root 'config/known-defects.json')
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures/mock'
$temp = New-TestDirectory

function Invoke-FixtureAssertion {
    param([string]$ScenarioId, [string]$FixtureId)
    $scenario = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq $ScenarioId) -Variables $environment
    $scenario.mock_fixture_id = $FixtureId
    $evidence = Join-Path $temp ($ScenarioId + '-' + $FixtureId)
    $null = New-Item -ItemType Directory -Path $evidence -Force
    $plan = New-ClientPlan -Scenario $scenario -ExecutablePath $environment['PB_CLIENT_EXE'] -RunId 'fixture-run' -JsonlPath (Join-Path $evidence 'client.jsonl') -Contract $contract -ExpectedSha256 $environment['PB_EXPECTED_CLIENT_SHA256']
    $mock = Invoke-MockScenario -Scenario $scenario -ClientPlan $plan -FixtureRoot $fixtureRoot -EvidenceDirectory $evidence -Environment $environment
    $assertion = Test-ScenarioAssertions -Scenario $scenario -ClientPlan $plan -ClientResult $mock.client_result -VpsRecords $mock.vps_records -ProxyBridgeRecords $mock.proxybridge_records -EvidenceContext $mock.evidence_context -RunMode mock
    return [pscustomobject]@{scenario=$scenario;plan=$plan;mock=$mock;assertion=$assertion}
}

function New-VpsFixtureRecord {
    param([string]$Event, [string]$Sha256, [int]$LocalPort, [int]$RemotePort)
    return [pscustomobject]@{
        event=$Event;sha256=$Sha256;local_ip='198.51.100.10';local_port=$LocalPort
        remote_ip='192.0.2.50';remote_port=$RemotePort;bytes=64;error='';test_id='issue209-tcp-to-udp';run_id='fixture-run'
    }
}

try {
    $pass = Invoke-FixtureAssertion 'tcp-ipv4-direct' 'base-direct'
    Assert-Equal 'PASS' $pass.assertion.outcome 'complete direct fixture must pass assertions'

    $wrongAction = Invoke-FixtureAssertion 'tcp-ipv4-direct' 'base-wrong-action'
    Assert-Equal 'FAIL_PRODUCT' $wrongAction.assertion.outcome 'wrong ProxyBridge action must be caught'
    Assert-True ((@($wrongAction.assertion.product_errors) -join ',') -match 'wrong ProxyBridge action') 'wrong action reason must be explicit'

    $wrongActionMissingVps = Test-ScenarioAssertions -Scenario $wrongAction.scenario -ClientPlan $wrongAction.plan -ClientResult $wrongAction.mock.client_result -VpsRecords @() -ProxyBridgeRecords $wrongAction.mock.proxybridge_records -EvidenceContext ([pscustomobject]@{vps_capture_complete=$false;proxybridge_capture_complete=$true;expected_process='pb_net_client.exe'}) -RunMode real
    Assert-Equal 'FAIL_PRODUCT' $wrongActionMissingVps.outcome 'definite wrong action must outrank unrelated missing VPS evidence'

    $wrongEgress = Invoke-FixtureAssertion 'tcp-ipv4-proxy' 'base-proxy-wrong-egress'
    Assert-Equal 'FAIL_PRODUCT' $wrongEgress.assertion.outcome 'wrong proxy egress must be caught'
    Assert-True ((@($wrongEgress.assertion.product_errors) -join ',') -match 'wrong proxy egress|direct leak') 'wrong egress reason must be explicit'

    $proxyPass = Invoke-FixtureAssertion 'tcp-ipv4-proxy' 'base-proxy'
    $externalProxyContext = [pscustomobject]@{vps_capture_complete=$true;vps_capture_complete_shas=@($proxyPass.mock.client_result.canonical_records.payload_sha256);channel_capture_completed=$true;records_found=$false;direct_egress_ip='192.0.2.50';proxy_egress_ip='';expected_process='pb_net_client.exe'}
    $externalProxy = Test-ScenarioAssertions -Scenario $proxyPass.scenario -ClientPlan $proxyPass.plan -ClientResult $proxyPass.mock.client_result -VpsRecords $proxyPass.mock.vps_records -ProxyBridgeRecords @() -EvidenceContext $externalProxyContext -RunMode real
    Assert-Equal 'PASS' $externalProxy.outcome 'external PROXY evidence must pass without internal route records'
    Assert-Equal 'CLIENT+VPS+DIRECT_BASELINE' $externalProxy.evidence_basis 'external PROXY evidence basis'

    $ambiguousContext = [pscustomobject]@{vps_capture_complete=$true;vps_capture_complete_shas=@($proxyPass.mock.client_result.canonical_records.payload_sha256);channel_capture_completed=$true;records_found=$false;direct_egress_ip='198.51.100.50';proxy_egress_ip='';expected_process='pb_net_client.exe'}
    $ambiguous = Test-ScenarioAssertions -Scenario $proxyPass.scenario -ClientPlan $proxyPass.plan -ClientResult $proxyPass.mock.client_result -VpsRecords $proxyPass.mock.vps_records -ProxyBridgeRecords @() -EvidenceContext $ambiguousContext -RunMode real
    Assert-Equal 'HOLD_AMBIGUOUS' $ambiguous.outcome 'same direct/proxy egress must hold without internal route evidence'
    Assert-True $ambiguous.route_evidence_required 'same egress must require internal route evidence'

    $contradictory = @(ConvertFrom-ProxyBridgeTextLines @('2030-01-01T00:00:00Z pb_net_client.exe (4242) -> 198.51.100.10:41001 via Direct'))
    $contradiction = Test-ScenarioAssertions -Scenario $proxyPass.scenario -ClientPlan $proxyPass.plan -ClientResult $proxyPass.mock.client_result -VpsRecords $proxyPass.mock.vps_records -ProxyBridgeRecords $contradictory -EvidenceContext $externalProxyContext -RunMode real
    Assert-Equal 'FAIL_PRODUCT' $contradiction.outcome 'contradictory internal route must outrank complete external evidence'

    $missingVps = Invoke-FixtureAssertion 'tcp-ipv4-direct' 'base-missing-vps'
    Assert-Equal 'HOLD_AMBIGUOUS' $missingVps.assertion.outcome 'missing VPS evidence cannot pass'

    $blockLeak = Invoke-FixtureAssertion 'tcp-ipv4-block' 'base-block-leak'
    Assert-Equal 'FAIL_PRODUCT' $blockLeak.assertion.outcome 'block leak must be caught'

    $issue206 = Invoke-FixtureAssertion 'issue206-proxy-to-direct-abortive' 'issue206-proxy-direct-wrong-second'
    Assert-Equal 'FAIL_PRODUCT' $issue206.assertion.outcome 'issue206 wrong second route must fail assertions'
    $defect = Get-KnownDefectMatch -Scenario $issue206.scenario -KnownDefects $defects
    Assert-Equal 'MOCK_EXPECTED_FAIL' (Get-ClassifiedStatus -AssertionResult $issue206.assertion -KnownDefect $defect -RunMode mock -MockExpectation 'EXPECTED_FAIL') 'known issue206 negative fixture must classify honestly'

    $issue209Fixture = Invoke-FixtureAssertion 'issue209-tcp-to-udp' 'issue209-direct'
    Assert-Equal 'PASS' $issue209Fixture.assertion.outcome 'executable issue209 mock fixture must satisfy the three-record contract'

    $required = Test-ScenarioAssertions -Scenario $pass.scenario -ClientPlan $pass.plan -ClientResult $pass.mock.client_result -VpsRecords @() -ProxyBridgeRecords @() -EvidenceContext ([pscustomobject]@{vps_capture_complete=$false;proxybridge_capture_complete=$false}) -RunMode real
    Assert-Equal 'HOLD_AMBIGUOUS' $required.outcome 'real assertions without external evidence cannot pass'

    $vpsLine = '{"event":"MESSAGE_RECEIVED","sha256":"' + ('a' * 64) + '","local_ip":"198.51.100.10","local_port":41001,"remote_ip":"192.0.2.50","remote_port":50000,"bytes":64,"error":""}'
    Assert-Equal 1 @(ConvertFrom-VpsJsonLines @($vpsLine)).Count 'actual VPS schema must parse'
    Assert-Throws { ConvertFrom-VpsJsonLines @('{"event":"MESSAGE_RECEIVED","payload_sha256":"' + ('a' * 64) + '"}') } 'VPS_EVIDENCE_SCHEMA_INVALID' 'obsolete VPS fields must be rejected'
    $udpLine = '{"event":"RECEIVED","sha256":"' + ('b' * 64) + '","local_ip":"198.51.100.10","local_port":41001,"remote_ip":"192.0.2.50","remote_port":50001,"bytes":64,"error":""}'
    $udpRecords = @(ConvertFrom-VpsJsonLines @($udpLine))
    $udpCheck = Test-VpsPayloadEvidence -Records $udpRecords -Sha256 ('b' * 64) -Protocol UDP -ExpectedReceived 1 -ExpectedEchoed 0 -ExpectedDestinationPort 41001
    Assert-True ([bool]$udpCheck.passed) 'UDP endpoint receive event must be RECEIVED'

    $exactRoute = @(Import-ProxyBridgeTextEvidence (Join-Path $PSScriptRoot 'fixtures/proxybridge/stage34a-route.log'))
    Assert-Equal 4 $exactRoute.Count 'Stage 3.4A route and relay fixtures must parse'
    Assert-SequenceEqual @('PROXY','BLOCK','PROXY','BLOCK') @($exactRoute.action) 'route and numeric relay actions must map exactly'
    Assert-Equal 1 $exactRoute[2].proxy_config_id 'relay cfg=1 must be preserved'
    Assert-Equal 0 $exactRoute[3].proxy_config_id 'relay cfg=0 must be preserved'
    Assert-Equal '11:55:47' $exactRoute[0].observed_local_time 'local time prefix must be preserved'
    $localCorrelated = @(Find-ProxyBridgeFlowEvidence -Records $exactRoute -Process 'pb_net_client.exe' -Pid 4242 -DestinationIp '198.51.100.10' -DestinationPort 41002 -Action PROXY -StartTimeUtc ([datetime]'2029-12-31T23:59:00Z') -EndTimeUtc ([datetime]'2030-01-01T00:01:00Z'))
    Assert-True ($localCorrelated.Count -ge 1) 'lifetime-scoped local-time route must not be discarded for lacking UTC date'

    $multiRelay = @(Import-ProxyBridgeTextEvidence (Join-Path $PSScriptRoot 'fixtures/proxybridge/stage34a-relay-multiline.log'))
    Assert-Equal 1 $multiRelay.Count 'multi-line relay fixture must collapse to one record'
    Assert-Equal 'PROXY' $multiRelay[0].action 'multi-line relay numeric action must map'
    Assert-Equal 1 $multiRelay[0].proxy_config_id 'multi-line relay cfg must be preserved'

    $pbLines = @(
        '2030-01-01T00:00:00Z pb_net_client.exe (4242) -> 198.51.100.10:41001 via Direct',
        'pb_net_client.exe -> 198.51.100.10:41003 via Blocked',
        '2030-01-01T00:00:04Z pb_net_client.exe (PID:4242) -> 198.51.100.10:41004 via Proxy ProxyConfigId=7'
    )
    $parsed = @(ConvertFrom-ProxyBridgeTextLines $pbLines)
    Assert-Equal 3 $parsed.Count 'ISO, missing-PID and PID-prefixed routes must parse'
    Assert-Equal 7 $parsed[2].proxy_config_id 'explicit ProxyConfigId evidence must be preserved'
    Assert-True ($null -eq $parsed[0].PSObject.Properties['payload_sha256']) 'ProxyBridge logs must not require nonexistent payload SHA'
    $relayWithoutAction = @(ConvertFrom-ProxyBridgeTextLines @('[RELAY] accepted redirect: pid=4242 dest=198.51.100.10:41002 cfg=1'))
    Assert-Equal '' $relayWithoutAction[0].action 'relay evidence without action must not invent a PROXY decision'

    $scenario209 = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'issue209-tcp-to-udp') -Variables $environment
    $plan209 = New-ClientPlan -Scenario $scenario209 -ExecutablePath $environment['PB_CLIENT_EXE'] -RunId 'fixture-run' -JsonlPath (Join-Path $temp 'issue209-client.jsonl') -Contract $contract
    $raw209 = @(Import-ClientJsonLinesFile (Join-Path $PSScriptRoot 'fixtures/client-jsonl/issue209-three-record.jsonl'))
    $canonical209 = @($raw209 | ConvertTo-CanonicalClientEvidence)
    $client209 = [pscustomobject]@{exit_code=0;timed_out=$false;pid=4242;raw_records=$raw209;canonical_records=$canonical209;stdout='';stderr=''}
    $pb209 = @(ConvertFrom-ProxyBridgeTextLines @(
        '[12:00:00] pb_net_client.exe (PID:4242) -> 198.51.100.10:41002 via Direct',
        '[12:00:01] pb_net_client.exe (PID:4242) -> 198.51.100.10:41001 via Direct'
    ))
    $vps209 = @(
        (New-VpsFixtureRecord 'MESSAGE_RECEIVED' ('5' * 64) 41002 50000), (New-VpsFixtureRecord 'ECHOED' ('5' * 64) 41002 50000),
        (New-VpsFixtureRecord 'RECEIVED' ('6' * 64) 41001 50001), (New-VpsFixtureRecord 'ECHOED' ('6' * 64) 41001 50001),
        (New-VpsFixtureRecord 'MESSAGE_RECEIVED' ('7' * 64) 41002 50002), (New-VpsFixtureRecord 'ECHOED' ('7' * 64) 41002 50002)
    )
    $context209 = [pscustomobject]@{vps_capture_complete=$true;proxybridge_capture_complete=$true;direct_egress_ip='192.0.2.50';proxy_egress_ip='198.51.100.50';expected_process='pb_net_client.exe'}
    $assert209 = Test-ScenarioAssertions -Scenario $scenario209 -ClientPlan $plan209 -ClientResult $client209 -VpsRecords $vps209 -ProxyBridgeRecords $pb209 -EvidenceContext $context209 -RunMode mock
    Assert-Equal 'PASS' $assert209.outcome 'issue209 first, second and held recheck records must pass independently'
    $client209MissingHeld = [pscustomobject]@{exit_code=0;timed_out=$false;pid=4242;canonical_records=@($canonical209 | Where-Object phase -ne 'held_recheck')}
    $missingHeld = Test-ScenarioAssertions -Scenario $scenario209 -ClientPlan $plan209 -ClientResult $client209MissingHeld -VpsRecords $vps209 -ProxyBridgeRecords $pb209 -EvidenceContext $context209 -RunMode mock
    Assert-Equal 'FAIL_HARNESS' $missingHeld.outcome 'missing issue209 held_recheck must never pass'

    $dynamicPlan = New-VpsDynamicEvidencePlan -Environment $environment -CanonicalRecords $canonical209 -EvidenceDirectory (Join-Path $temp 'vps-plan') -SshExecutablePath 'ssh.exe'
    Assert-Equal 3 @($dynamicPlan.queries).Count 'dynamic SSH plan must create one exact query per canonical payload SHA'
    Assert-SequenceEqual @('first_flow-vps.jsonl','second_flow-vps.jsonl','held_recheck-vps.jsonl') @($dynamicPlan.queries | ForEach-Object { Split-Path -Leaf $_.output_path }) 'dynamic SSH outputs must be phase-specific'
    Assert-Equal 'ssh.exe' $dynamicPlan.queries[0].process_plan.executable 'dynamic collector plan must remain gated behind ssh.exe process adapter'

    $rawBlock = @(Import-ClientJsonLinesFile (Join-Path $PSScriptRoot 'fixtures/client-jsonl/stage34a-issue206-proxy-block.jsonl'))
    $blockCanonical = @($rawBlock | ConvertTo-CanonicalClientEvidence | Where-Object phase -eq 'second_flow')
    $blockPlan = New-VpsDynamicEvidencePlan -Environment $environment -CanonicalRecords $blockCanonical -EvidenceDirectory (Join-Path $temp 'vps-empty-block') -SshExecutablePath 'ssh.exe'
    $emptySshResult = [pscustomobject]@{exit_code=0;timed_out=$false;pid=99;actual_path='ssh.exe';stdout='';stderr=''}
    $emptyCapture = Invoke-VpsDynamicEvidencePlan -Plan $blockPlan -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($emptySshResult))
    Assert-True $emptyCapture.capture_complete 'successful empty BLOCK query must be a complete capture'
    Assert-Equal 0 @($emptyCapture.records).Count 'successful empty BLOCK query must contain zero exact-hash records'
    Assert-Equal 1 @($emptyCapture.complete_shas).Count 'successful empty BLOCK query must mark its SHA complete'
    Assert-NoUtf8Bom $blockPlan.queries[0].output_path 'dynamic VPS JSONL must use UTF-8 without BOM'
    $emptyBlockCheck = Test-VpsPayloadEvidence -Records @() -Sha256 $blockCanonical[0].payload_sha256 -Protocol TCP -ExpectedReceived 0 -ExpectedEchoed 0
    Assert-True ([bool]$emptyBlockCheck.passed) 'complete empty BLOCK query must prove no received payload'

    $failedBlockPlan = New-VpsDynamicEvidencePlan -Environment $environment -CanonicalRecords $blockCanonical -EvidenceDirectory (Join-Path $temp 'vps-failed-block') -SshExecutablePath 'ssh.exe'
    $failedSshResult = [pscustomobject]@{exit_code=255;timed_out=$false;pid=100;actual_path='ssh.exe';stdout='';stderr='fixture SSH failure'}
    $failedCapture = Invoke-VpsDynamicEvidencePlan -Plan $failedBlockPlan -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($failedSshResult))
    Assert-True (-not [bool]$failedCapture.capture_complete) 'failed SSH query must not mark VPS capture complete'
    Assert-Equal 0 @($failedCapture.complete_shas).Count 'failed SSH query must not complete any SHA'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }

'PASS: evidence assertions'
