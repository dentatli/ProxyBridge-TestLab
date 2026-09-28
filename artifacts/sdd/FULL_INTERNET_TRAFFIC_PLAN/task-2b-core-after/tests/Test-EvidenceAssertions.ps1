[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
foreach ($module in @('Env','Config','ScenarioCatalog','ProfileAdapter','ProcessAdapter','ClientRunner','MockRuntime','ProxyBridgeEvidence','VpsEvidence','Assertions')) { Import-Module (Join-Path $root "modules/$module.psm1") -Force }

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
    param([string]$Event, [string]$Sha256, [int]$LocalPort, [int]$RemotePort, [string]$Protocol, [string]$Phase, [int]$Sequence)
    return [pscustomobject]@{
        timestamp_utc='2030-01-01T00:02:00Z';monotonic_ns=(1000000000 + $Sequence);family='IPv4';protocol=$Protocol
        event=$Event;sha256=$Sha256;local_ip='198.51.100.10';local_port=$LocalPort
        remote_ip='192.0.2.50';remote_port=$RemotePort;bytes=64;error='';test_id='issue209-tcp-to-udp';run_id='fixture-run';phase=$Phase;sequence=$Sequence
    }
}

try {
    $pass = Invoke-FixtureAssertion 'tcp-ipv4-direct' 'base-direct'
    Assert-Equal 'PASS' $pass.assertion.outcome 'complete direct fixture must pass assertions'
    Assert-True (@($pass.assertion.evidence_completeness | Where-Object { $_.mandatory -and -not $_.validated }).Count -eq 0) 'complete fixture must validate every mandatory assertion channel'

    $stream = Invoke-FixtureAssertion 'tcp-payload-streaming' 'base-streaming-direct'
    Assert-Equal 'PASS' $stream.assertion.outcome 'four TCP messages on one socket tuple must pass assertions'
    Assert-Equal 4 @($stream.mock.client_result.canonical_records).Count 'stream fixture must preserve four canonical records'
    Assert-Equal 1 @($stream.mock.client_result.canonical_records.actual_local_port | Sort-Object -Unique).Count 'stream fixture must prove one local socket tuple'
    $splitStreamResult = $stream.mock.client_result | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $splitStreamResult.canonical_records[2].actual_local_port = 32001
    $splitStream = Test-ScenarioAssertions -Scenario $stream.scenario -ClientPlan $stream.plan -ClientResult $splitStreamResult -VpsRecords $stream.mock.vps_records -ProxyBridgeRecords $stream.mock.proxybridge_records -EvidenceContext $stream.mock.evidence_context -RunMode mock
    Assert-True ($splitStream.outcome -ne 'PASS') 'a reconnect disguised as streaming must not pass'
    Assert-True ((@($splitStream.harness_errors) -join ',') -match 'one local socket tuple') 'stream socket-tuple failure must be explicit'
    $changedSocketResult = $stream.mock.client_result | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $changedSocketResult.canonical_records[2].socket_id = 7002
    $changedSocket = Test-ScenarioAssertions -Scenario $stream.scenario -ClientPlan $stream.plan -ClientResult $changedSocketResult -VpsRecords $stream.mock.vps_records -ProxyBridgeRecords $stream.mock.proxybridge_records -EvidenceContext $stream.mock.evidence_context -RunMode mock
    Assert-Equal 'FAIL_HARNESS' $changedSocket.outcome 'same tuple on a replacement socket must not pass as streaming'
    Assert-True ((@($changedSocket.harness_errors) -join ',') -match 'one socket identity') 'stream socket-identity failure must be explicit'

    foreach($transitionCase in @(
        @('issue206-direct-to-block','issue206-direct-block'),
        @('issue206-direct-to-proxy','issue206-direct-proxy'),
        @('issue206-proxy-to-block','issue206-proxy-block'),
        @('issue206-block-to-direct','issue206-block-direct'),
        @('issue206-block-to-proxy','issue206-block-proxy')
    )){
        $transitionResult=Invoke-FixtureAssertion ([string]$transitionCase[0]) ([string]$transitionCase[1])
        Assert-Equal 'PASS' $transitionResult.assertion.outcome "$($transitionCase[0]) complete two-flow fixture must pass"
        Assert-Equal 2 @($transitionResult.mock.client_result.canonical_records|Where-Object record_kind -eq 'flow').Count "$($transitionCase[0]) must preserve both flow records"
    }
    foreach($domainCase in @(
        @('dns-domain-direct','base-direct'),
        @('dns-domain-proxy','base-proxy'),
        @('rule-destination-domain','base-direct')
    )){
        $domainResult=Invoke-FixtureAssertion ([string]$domainCase[0]) ([string]$domainCase[1])
        Assert-Equal 'PASS' $domainResult.assertion.outcome "$($domainCase[0]) domain-aware evidence must pass"
        Assert-Equal $environment['PB_TEST_DOMAIN'] $domainResult.mock.client_result.canonical_records[0].remote_host "$($domainCase[0]) must preserve requested hostname evidence"
    }
    foreach($ruleCase in @(
        @('rule-disabled','base-direct'),
        @('rule-priority-overlap','base-direct'),
        @('rule-protocol-both','issue209-direct'),
        @('rule-multiple-proxy-configs','base-proxy-config2')
    )){
        $ruleResult=Invoke-FixtureAssertion ([string]$ruleCase[0]) ([string]$ruleCase[1])
        Assert-Equal 'PASS' $ruleResult.assertion.outcome "$($ruleCase[0]) exact rule evidence must pass"
    }
    $missingConfigEvidence=Invoke-FixtureAssertion 'rule-multiple-proxy-configs' 'base-proxy'
    Assert-Equal 'HOLD_AMBIGUOUS' $missingConfigEvidence.assertion.outcome 'proxy traffic without exact config ID must not pass the multiple-config scenario'
    Assert-True ((@($missingConfigEvidence.assertion.missing_evidence)-join ',') -match 'exact proxy config decision') 'missing config-ID evidence must be explicit'
    $freshFlowSecurity=Invoke-FixtureAssertion 'security-fresh-flow-no-stale-action' 'issue206-proxy-direct'
    Assert-Equal 'PASS' $freshFlowSecurity.assertion.outcome 'fresh flow must independently change from PROXY to DIRECT'
    $configIsolationSecurity=Invoke-FixtureAssertion 'security-no-proxy-config-inheritance' 'issue206-proxy-config-switch'
    Assert-Equal 'PASS' $configIsolationSecurity.assertion.outcome 'second flow must select proxy config 2 instead of inheriting config 1'
    $configIsolationMissing=Invoke-FixtureAssertion 'security-no-proxy-config-inheritance' 'issue206-proxy-direct-wrong-second'
    Assert-Equal 'HOLD_AMBIGUOUS' $configIsolationMissing.assertion.outcome 'two proxy flows without exact per-flow config IDs must not pass isolation'
    foreach($lifecycleCase in @(
        @('tcp-graceful-close','tcp-graceful-close'),
        @('tcp-abortive-close','tcp-abortive-close'),
        @('tcp-half-close','tcp-half-close'),
        @('tcp-server-close','tcp-server-close'),
        @('tcp-reset','tcp-reset'),
        @('tcp-refused','tcp-refused'),
        @('tcp-timeout','tcp-timeout'),
        @('tcp-long-lived','base-streaming-direct'),
        @('tcp-sequential-reuse','issue206-direct-direct')
    )){
        $lifecycleResult=Invoke-FixtureAssertion ([string]$lifecycleCase[0]) ([string]$lifecycleCase[1])
        Assert-Equal 'PASS' $lifecycleResult.assertion.outcome "$($lifecycleCase[0]) complete lifecycle evidence must pass"
    }
    $missingCloseEvent=Invoke-FixtureAssertion 'tcp-graceful-close' 'base-direct'
    Assert-Equal 'HOLD_AMBIGUOUS' $missingCloseEvent.assertion.outcome 'graceful close without endpoint CLOSED evidence must not pass'
    foreach($udpSemanticCase in @(
        @('udp-one-socket-multiple-destinations','udp-one-socket-two-dest'),
        @('udp-delayed-response','udp-delayed-response'),
        @('udp-duplicate-response','udp-duplicate-response'),
        @('udp-drop','udp-drop')
    )){
        $udpSemantic=Invoke-FixtureAssertion ([string]$udpSemanticCase[0]) ([string]$udpSemanticCase[1])
        Assert-Equal 'PASS' $udpSemantic.assertion.outcome "$($udpSemanticCase[0]) complete semantics evidence must pass"
    }
    $tcpParallel=Invoke-FixtureAssertion 'tcp-parallel-connections' 'generated-base-direct'
    Assert-Equal 'PASS' $tcpParallel.assertion.outcome 'eight concurrent TCP flows with independent evidence must pass'
    Assert-Equal 8 @($tcpParallel.mock.client_result.canonical_records).Count 'parallel TCP fixture record count'
    Assert-Equal 8 @($tcpParallel.mock.client_result.canonical_records.actual_local_port|Sort-Object -Unique).Count 'parallel TCP fixture must prove unique local socket tuples'
    $duplicateTupleResult=$tcpParallel.mock.client_result|ConvertTo-Json -Depth 100|ConvertFrom-Json
    $duplicateTupleResult.canonical_records[7].actual_local_port=$duplicateTupleResult.canonical_records[0].actual_local_port
    $duplicateTupleAssertion=Test-ScenarioAssertions -Scenario $tcpParallel.scenario -ClientPlan $tcpParallel.plan -ClientResult $duplicateTupleResult -VpsRecords $tcpParallel.mock.vps_records -ProxyBridgeRecords $tcpParallel.mock.proxybridge_records -EvidenceContext $tcpParallel.mock.evidence_context -RunMode mock
    Assert-Equal 'FAIL_HARNESS' $duplicateTupleAssertion.outcome 'duplicate local tuple must fail the parallel harness contract'
    Assert-True ((@($duplicateTupleAssertion.harness_errors)-join ',') -match 'unique local socket tuples') 'parallel duplicate-tuple failure must be explicit'
    $udpParallel=Invoke-FixtureAssertion 'udp-multiple-sockets-one-destination' 'generated-base-direct'
    Assert-Equal 'PASS' $udpParallel.assertion.outcome 'eight concurrent UDP sockets with independent evidence must pass'
    $udpReconnect=Invoke-FixtureAssertion 'udp-idle-reconnect' 'generated-base-direct'
    Assert-Equal 'PASS' $udpReconnect.assertion.outcome 'two UDP sockets separated by an idle interval must pass reconnect evidence'
    Assert-Equal 2 @($udpReconnect.mock.client_result.canonical_records.actual_local_port|Sort-Object -Unique).Count 'UDP reconnect must prove a fresh local tuple'
    $reusedReconnect=$udpReconnect.mock.client_result|ConvertTo-Json -Depth 100|ConvertFrom-Json
    $reusedReconnect.canonical_records[1].actual_local_port=$reusedReconnect.canonical_records[0].actual_local_port
    $reusedReconnectAssertion=Test-ScenarioAssertions -Scenario $udpReconnect.scenario -ClientPlan $udpReconnect.plan -ClientResult $reusedReconnect -VpsRecords $udpReconnect.mock.vps_records -ProxyBridgeRecords $udpReconnect.mock.proxybridge_records -EvidenceContext $udpReconnect.mock.evidence_context -RunMode mock
    Assert-Equal 'FAIL_HARNESS' $reusedReconnectAssertion.outcome 'reconnect without a fresh tuple must not pass'
    $udpOutOfOrder=Invoke-FixtureAssertion 'udp-out-of-order' 'generated-base-direct'
    Assert-Equal 'PASS' $udpOutOfOrder.assertion.outcome 'reversed UDP responses with exact payload identities must pass'
    Assert-SequenceEqual @(2,1) @($udpOutOfOrder.mock.client_result.canonical_records.response_order) 'client must record reversed receive order'
    $wrongResponseOrder=$udpOutOfOrder.mock.client_result|ConvertTo-Json -Depth 100|ConvertFrom-Json
    $wrongResponseOrder.canonical_records[0].response_order=1
    $wrongResponseOrderAssertion=Test-ScenarioAssertions -Scenario $udpOutOfOrder.scenario -ClientPlan $udpOutOfOrder.plan -ClientResult $wrongResponseOrder -VpsRecords $udpOutOfOrder.mock.vps_records -ProxyBridgeRecords $udpOutOfOrder.mock.proxybridge_records -EvidenceContext $udpOutOfOrder.mock.evidence_context -RunMode mock
    Assert-Equal 'FAIL_PRODUCT' $wrongResponseOrderAssertion.outcome 'wrong UDP client receive order must be a product-path failure'
    $wrongEndpointOrder=@($udpOutOfOrder.mock.vps_records|ForEach-Object{$_|ConvertTo-Json -Depth 20|ConvertFrom-Json})
    $echoes=@($wrongEndpointOrder|Where-Object event -eq 'ECHOED'|Sort-Object monotonic_ns)
    $echoes[0].monotonic_ns,$echoes[1].monotonic_ns=$echoes[1].monotonic_ns,$echoes[0].monotonic_ns
    $wrongEndpointOrderAssertion=Test-ScenarioAssertions -Scenario $udpOutOfOrder.scenario -ClientPlan $udpOutOfOrder.plan -ClientResult $udpOutOfOrder.mock.client_result -VpsRecords $wrongEndpointOrder -ProxyBridgeRecords $udpOutOfOrder.mock.proxybridge_records -EvidenceContext $udpOutOfOrder.mock.evidence_context -RunMode mock
    Assert-Equal 'FAIL_PRODUCT' $wrongEndpointOrderAssertion.outcome 'endpoint echo order must independently prove the reordered path'
    $udpLateReuse=Invoke-FixtureAssertion 'udp-late-response-after-reuse' 'generated-base-direct'
    Assert-Equal 'PASS' $udpLateReuse.assertion.outcome 'late response must not cross into the reused tuple socket generation'
    Assert-Equal 1 @($udpLateReuse.mock.client_result.canonical_records.actual_local_port|Sort-Object -Unique).Count 'late-response test must reuse the exact local tuple'
    Assert-Equal 2 @($udpLateReuse.mock.client_result.canonical_records.socket_id|Sort-Object -Unique).Count 'late-response test must prove two socket generations'
    $lateDelivered=$udpLateReuse.mock.client_result|ConvertTo-Json -Depth 100|ConvertFrom-Json
    $lateDelivered.canonical_records[1].actual_result='fail:udp_late_response_delivered'
    $lateDelivered.canonical_records[1].client_pass=$false
    $lateDeliveredAssertion=Test-ScenarioAssertions -Scenario $udpLateReuse.scenario -ClientPlan $udpLateReuse.plan -ClientResult $lateDelivered -VpsRecords $udpLateReuse.mock.vps_records -ProxyBridgeRecords $udpLateReuse.mock.proxybridge_records -EvidenceContext $udpLateReuse.mock.evidence_context -RunMode mock
    Assert-Equal 'FAIL_PRODUCT' $lateDeliveredAssertion.outcome 'late response delivered to the reused tuple must be a product failure'
    $sameGeneration=$udpLateReuse.mock.client_result|ConvertTo-Json -Depth 100|ConvertFrom-Json
    $sameGeneration.canonical_records[1].socket_id=$sameGeneration.canonical_records[0].socket_id
    $sameGenerationAssertion=Test-ScenarioAssertions -Scenario $udpLateReuse.scenario -ClientPlan $udpLateReuse.plan -ClientResult $sameGeneration -VpsRecords $udpLateReuse.mock.vps_records -ProxyBridgeRecords $udpLateReuse.mock.proxybridge_records -EvidenceContext $udpLateReuse.mock.evidence_context -RunMode mock
    Assert-Equal 'FAIL_HARNESS' $sameGenerationAssertion.outcome 'late-response fixture without a new socket generation must not pass'
    foreach($failureCase in @(
        @('failure-connect-refused','tcp-refused'),
        @('failure-silent-timeout','tcp-timeout')
    )){
        $failureResult=Invoke-FixtureAssertion ([string]$failureCase[0]) ([string]$failureCase[1])
        Assert-Equal 'PASS' $failureResult.assertion.outcome "$($failureCase[0]) exact injected failure evidence must pass"
    }
    $externalPairwise=@($catalog|Where-Object{$_.coverage_group -eq 'secondary-pairwise' -and $_.implementation_status -eq 'EXECUTABLE'})
    Assert-Equal 4 $externalPairwise.Count 'only externally provable pairwise cases should execute'
    foreach($pairwiseScenario in $externalPairwise){
        $pairwiseResult=Invoke-FixtureAssertion ([string]$pairwiseScenario.scenario_id) 'generated-base-direct'
        Assert-Equal 'PASS' $pairwiseResult.assertion.outcome "$($pairwiseScenario.scenario_id) generated evidence must satisfy its exact plan"
    }
    $crossProcess=Invoke-FixtureAssertion 'security-no-cross-process-delivery' 'generated-base-direct'
    Assert-Equal 'PASS' $crossProcess.assertion.outcome 'two independently identified client processes must pass cross-delivery isolation'
    Assert-Equal 2 @($crossProcess.mock.client_result.pids|Sort-Object -Unique).Count 'cross-process fixture lifecycle PID count'
    Assert-Equal 2 @($crossProcess.mock.client_result.canonical_records.process_id|Sort-Object -Unique).Count 'cross-process record PID count'
    $duplicatePidResult=$crossProcess.mock.client_result|ConvertTo-Json -Depth 100|ConvertFrom-Json
    $duplicatePidResult.canonical_records[1].process_id=$duplicatePidResult.canonical_records[0].process_id
    $duplicatePidAssertion=Test-ScenarioAssertions -Scenario $crossProcess.scenario -ClientPlan $crossProcess.plan -ClientResult $duplicatePidResult -VpsRecords $crossProcess.mock.vps_records -ProxyBridgeRecords $crossProcess.mock.proxybridge_records -EvidenceContext $crossProcess.mock.evidence_context -RunMode mock
    Assert-Equal 'FAIL_HARNESS' $duplicatePidAssertion.outcome 'duplicate PID evidence must not claim cross-process coverage'
    Assert-True ((@($duplicatePidAssertion.harness_errors)-join ',') -match 'distinct process IDs') 'cross-process duplicate-PID failure must be explicit'
    $duplicateMismatch=Invoke-FixtureAssertion 'udp-duplicate-response' 'udp-duplicate-response'
    $duplicateMismatch.mock.client_result.canonical_records[0].response_count=1
    $duplicateMismatchAssertion=Test-ScenarioAssertions -Scenario $duplicateMismatch.scenario -ClientPlan $duplicateMismatch.plan -ClientResult $duplicateMismatch.mock.client_result -VpsRecords $duplicateMismatch.mock.vps_records -ProxyBridgeRecords $duplicateMismatch.mock.proxybridge_records -EvidenceContext $duplicateMismatch.mock.evidence_context -RunMode mock
    Assert-Equal 'FAIL_PRODUCT' $duplicateMismatchAssertion.outcome 'one observed response must not pass a duplicate-response contract'

    $staleVps = @($pass.mock.vps_records | ForEach-Object { $_ | ConvertTo-Json -Depth 20 | ConvertFrom-Json })
    foreach($record in $staleVps){$record.timestamp_utc='2029-12-31T23:00:00Z'}
    $staleAssertion = Test-ScenarioAssertions -Scenario $pass.scenario -ClientPlan $pass.plan -ClientResult $pass.mock.client_result -VpsRecords $staleVps -ProxyBridgeRecords $pass.mock.proxybridge_records -EvidenceContext $pass.mock.evidence_context -RunMode real
    Assert-Equal 'CONTAMINATED' $staleAssertion.outcome 'stale endpoint records must not satisfy a current assertion'

    $wrongPhaseVps = @($pass.mock.vps_records | ForEach-Object { $_ | ConvertTo-Json -Depth 20 | ConvertFrom-Json })
    foreach($record in $wrongPhaseVps){$record.phase='second_flow'}
    $wrongPhaseAssertion = Test-ScenarioAssertions -Scenario $pass.scenario -ClientPlan $pass.plan -ClientResult $pass.mock.client_result -VpsRecords $wrongPhaseVps -ProxyBridgeRecords $pass.mock.proxybridge_records -EvidenceContext $pass.mock.evidence_context -RunMode real
    Assert-Equal 'CONTAMINATED' $wrongPhaseAssertion.outcome 'endpoint phase mismatch must not satisfy a current assertion'

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

    $udpBlock = Invoke-FixtureAssertion 'udp-ipv4-connected-block' 'udp-block-no-response'
    Assert-Equal 'PASS' $udpBlock.assertion.outcome 'UDP BLOCK no-response must not require an observed response source'

    $udpProxySource = Invoke-FixtureAssertion 'udp-ipv4-connected-proxy' 'udp-proxy-source-mismatch'
    $udpProxySource.mock.client_result.exit_code = 10
    $udpProxyAssertion = Test-ScenarioAssertions -Scenario $udpProxySource.scenario -ClientPlan $udpProxySource.plan -ClientResult $udpProxySource.mock.client_result -VpsRecords $udpProxySource.mock.vps_records -ProxyBridgeRecords $udpProxySource.mock.proxybridge_records -EvidenceContext $udpProxySource.mock.evidence_context -RunMode real
    Assert-Equal 'FAIL_PRODUCT' $udpProxyAssertion.outcome 'canonical UDP source mismatch with exit 10 must be a product failure'
    Assert-True ((@($udpProxyAssertion.product_errors) -join ',') -match 'fail:udp_response_source') 'UDP source mismatch signature must remain readable'
    Assert-True (-not ((@($udpProxyAssertion.harness_errors) -join ',') -match 'client exit code 10')) 'proven product-path failure must suppress generic exit-code harness classification'
    $udpProxyDefect = Get-KnownDefectMatch -Scenario $udpProxySource.scenario -KnownDefects $defects
    Assert-SequenceEqual @('wrong response source','fail:udp_response_source') @($udpProxyDefect.signature.required_product_error_suffixes) 'UDP reverse-source defect must declare its complete product-error signature'
    Assert-Equal 'EXPECTED_FAIL' (Get-ClassifiedStatus -AssertionResult $udpProxyAssertion -KnownDefect $udpProxyDefect -RunMode real) 'base UDP PROXY source mismatch must map to the known defect'

    $udpUnrelated = Invoke-FixtureAssertion 'udp-ipv4-connected-proxy' 'base-proxy-wrong-egress'
    Assert-Equal 'FAIL_PRODUCT' $udpUnrelated.assertion.outcome 'unrelated UDP PROXY wrong-egress fixture must remain a product failure'
    Assert-Equal 'FAIL_PRODUCT' (Get-ClassifiedStatus -AssertionResult $udpUnrelated.assertion -KnownDefect $udpProxyDefect -RunMode real) 'unrelated UDP PROXY product failure must not match reverse-source signature'

    $signatureOutsideProductErrors = [pscustomobject]@{
        outcome='FAIL_PRODUCT'
        product_errors=@('flow 0 wrong proxy egress')
        harness_errors=@('flow 0 client result failed: fail:udp_response_source')
        missing_evidence=@('flow 0 wrong response source')
    }
    Assert-Equal 'FAIL_PRODUCT' (Get-ClassifiedStatus -AssertionResult $signatureOutsideProductErrors -KnownDefect $udpProxyDefect -RunMode real) 'known-defect signature must ignore harness and missing-evidence text'

    $unscopedProductFailure = [pscustomobject]@{outcome='FAIL_PRODUCT';product_errors=@('unrelated product failure');harness_errors=@();missing_evidence=@()}
    foreach($legacyScenarioId in @('rule-selector-full-path','udp-watched-process-direct-drop','issue206-proxy-to-direct-abortive')){
        $legacyScenario=$catalog|Where-Object scenario_id -eq $legacyScenarioId
        $legacyDefect=Get-KnownDefectMatch -Scenario $legacyScenario -KnownDefects $defects
        Assert-True ($null -eq $legacyDefect.PSObject.Properties['signature']) "$legacyScenarioId defect must remain signature-free"
        Assert-Equal 'EXPECTED_FAIL' (Get-ClassifiedStatus -AssertionResult $unscopedProductFailure -KnownDefect $legacyDefect -RunMode real) "$legacyScenarioId legacy mapping must remain unchanged"
    }

    $issue206Missing = Invoke-FixtureAssertion 'issue206-proxy-to-block-abortive' 'issue206-missing-second'
    Assert-Equal 'FAIL_HARNESS' $issue206Missing.assertion.outcome 'issue206 missing second flow must not produce a product verdict'
    Assert-Equal 0 @($issue206Missing.assertion.product_errors).Count 'invalid issue206 execution contract must suppress product errors'
    Assert-True ((@($issue206Missing.assertion.harness_errors) -join ',') -match 'flow count|both phases') 'issue206 harness limitation must be explicit'

    $issue206 = Invoke-FixtureAssertion 'issue206-proxy-to-direct-abortive' 'issue206-proxy-direct-wrong-second'
    Assert-Equal 'FAIL_PRODUCT' $issue206.assertion.outcome 'issue206 wrong second route must fail assertions'
    $defect = Get-KnownDefectMatch -Scenario $issue206.scenario -KnownDefects $defects
    Assert-Equal 'MOCK_EXPECTED_FAIL' (Get-ClassifiedStatus -AssertionResult $issue206.assertion -KnownDefect $defect -RunMode mock -MockExpectation 'EXPECTED_FAIL') 'known issue206 negative fixture must classify honestly'

    $issue209Fixture = Invoke-FixtureAssertion 'issue209-tcp-to-udp' 'issue209-direct'
    Assert-Equal 'PASS' $issue209Fixture.assertion.outcome 'executable issue209 mock fixture must satisfy the three-record contract'

    $required = Test-ScenarioAssertions -Scenario $pass.scenario -ClientPlan $pass.plan -ClientResult $pass.mock.client_result -VpsRecords @() -ProxyBridgeRecords @() -EvidenceContext ([pscustomobject]@{vps_capture_complete=$false;proxybridge_capture_complete=$false}) -RunMode real
    Assert-Equal 'HOLD_AMBIGUOUS' $required.outcome 'real assertions without external evidence cannot pass'

    $vpsLine = '{"timestamp_utc":"2030-01-01T00:00:00Z","monotonic_ns":1,"event":"MESSAGE_RECEIVED","family":"IPv4","protocol":"TCP","sha256":"' + ('a' * 64) + '","local_ip":"198.51.100.10","local_port":41001,"remote_ip":"192.0.2.50","remote_port":50000,"bytes":64,"error":"","test_id":"fixture-test","run_id":"fixture-run","phase":"single","sequence":1}'
    Assert-Equal 1 @(ConvertFrom-VpsJsonLines @($vpsLine)).Count 'actual VPS schema must parse'
    Assert-Throws { ConvertFrom-VpsJsonLines @('{"event":"MESSAGE_RECEIVED","payload_sha256":"' + ('a' * 64) + '"}') } 'VPS_EVIDENCE_SCHEMA_INVALID' 'obsolete VPS fields must be rejected'
    $udpLine = '{"timestamp_utc":"2030-01-01T00:00:00Z","monotonic_ns":2,"event":"RECEIVED","family":"IPv4","protocol":"UDP","sha256":"' + ('b' * 64) + '","local_ip":"198.51.100.10","local_port":41001,"remote_ip":"192.0.2.50","remote_port":50001,"bytes":64,"error":"","test_id":"fixture-test","run_id":"fixture-run","phase":"single","sequence":1}'
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
        (New-VpsFixtureRecord 'MESSAGE_RECEIVED' ('5' * 64) 41002 50000 'TCP' 'first_flow' 1), (New-VpsFixtureRecord 'ECHOED' ('5' * 64) 41002 50000 'TCP' 'first_flow' 1),
        (New-VpsFixtureRecord 'RECEIVED' ('6' * 64) 41001 50001 'UDP' 'second_flow' 2), (New-VpsFixtureRecord 'ECHOED' ('6' * 64) 41001 50001 'UDP' 'second_flow' 2),
        (New-VpsFixtureRecord 'MESSAGE_RECEIVED' ('7' * 64) 41002 50002 'TCP' 'held_recheck' 3), (New-VpsFixtureRecord 'ECHOED' ('7' * 64) 41002 50002 'TCP' 'held_recheck' 3)
    )
    $context209 = [pscustomobject]@{vps_capture_complete=$true;proxybridge_capture_complete=$true;direct_egress_ip='192.0.2.50';proxy_egress_ip='198.51.100.50';expected_process='pb_net_client.exe'}
    $assert209 = Test-ScenarioAssertions -Scenario $scenario209 -ClientPlan $plan209 -ClientResult $client209 -VpsRecords $vps209 -ProxyBridgeRecords $pb209 -EvidenceContext $context209 -RunMode mock
    Assert-Equal 'PASS' $assert209.outcome 'issue209 first, second and held recheck records must pass independently'
    $client209MissingHeld = [pscustomobject]@{exit_code=0;timed_out=$false;pid=4242;canonical_records=@($canonical209 | Where-Object phase -ne 'held_recheck')}
    $missingHeld = Test-ScenarioAssertions -Scenario $scenario209 -ClientPlan $plan209 -ClientResult $client209MissingHeld -VpsRecords $vps209 -ProxyBridgeRecords $pb209 -EvidenceContext $context209 -RunMode mock
    Assert-Equal 'FAIL_HARNESS' $missingHeld.outcome 'missing issue209 held_recheck must never pass'

    $dynamicPlan = New-VpsDynamicEvidencePlan -Environment $environment -CanonicalRecords $canonical209 -EvidenceDirectory (Join-Path $temp 'vps-plan') -SshExecutablePath 'ssh.exe'
    Assert-Equal 3 @($dynamicPlan.queries).Count 'dynamic SSH plan must create one exact query per canonical payload SHA'
    Assert-SequenceEqual @('first_flow-1-vps.jsonl','second_flow-2-vps.jsonl','held_recheck-3-vps.jsonl') @($dynamicPlan.queries | ForEach-Object { Split-Path -Leaf $_.output_path }) 'dynamic SSH outputs must be phase and sequence specific'
    Assert-Equal 'ssh.exe' $dynamicPlan.queries[0].process_plan.executable 'dynamic collector plan must remain gated behind ssh.exe process adapter'
    Assert-True (@($dynamicPlan.queries[0].process_plan.arguments) -contains 'IdentitiesOnly=yes') 'dynamic collector must use only the configured SSH identity'
    Assert-True (@($dynamicPlan.queries[0].process_plan.arguments) -contains 'UserKnownHostsFile=C:\Users\Fixture\.ssh\known_hosts') 'dynamic collector must pin an explicit known-hosts file'

    $cursorPlan = New-VpsLogCursorPlan -Environment $environment -SshExecutablePath 'ssh.exe'
    Assert-True (@($cursorPlan.process_plan.arguments) -contains 'UserKnownHostsFile=C:\Users\Fixture\.ssh\known_hosts') 'cursor collector must pin an explicit known-hosts file'
    $cursorProcess = [pscustomobject]@{exit_code=0;timed_out=$false;pid=98;actual_path='ssh.exe';stdout="INODE=123`nOFFSET=456`n";stderr=''}
    $cursor = Invoke-VpsLogCursorPlan -Plan $cursorPlan -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($cursorProcess))
    Assert-Equal '123' $cursor.inode 'VPS cursor inode'
    Assert-Equal 456 $cursor.offset 'VPS cursor byte offset'
    $windowedPlan = New-VpsDynamicEvidencePlan -Environment $environment -CanonicalRecords @($canonical209[0]) -EvidenceDirectory (Join-Path $temp 'vps-windowed') -SshExecutablePath 'ssh.exe' -Cursor $cursor
    Assert-True ([string]$windowedPlan.queries[0].process_plan.arguments[-1] -match 'tail -c \+457') 'VPS query must start after the captured byte offset'
    Assert-True ([string]$windowedPlan.queries[0].process_plan.arguments[-1] -match "= '123'") 'VPS query must reject log rotation/inode changes'

    $identityFree = New-VpsFixtureRecord 'RECEIVED' ('8' * 64) 41001 50000 'UDP' '' 0
    $identityFree.test_id='';$identityFree.run_id='';$identityFree.phase='';$identityFree.sequence=0
    $annotated = @(ConvertFrom-VpsJsonLines -Lines @(($identityFree | ConvertTo-Json -Compress)) -ExpectedIdentity $windowedPlan.queries[0])
    Assert-Equal 'cursor_exact_sha' $annotated[0].identity_source 'raw payload evidence must disclose cursor+SHA identity attribution'
    Assert-Equal $canonical209[0].test_id $annotated[0].test_id 'cursor identity must bind exact test ID'

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
