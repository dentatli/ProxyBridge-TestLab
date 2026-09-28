[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
foreach ($module in @('Env','Config','ScenarioCatalog','ProfileAdapter','ProcessAdapter','ClientRunner')) { Import-Module (Join-Path $root "modules/$module.psm1") -Force }

function Get-ExpectedArguments {
    param([string]$Name)
    $document = Get-Content -LiteralPath (Join-Path $PSScriptRoot "fixtures/client-contract/$Name.arguments.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($document | ForEach-Object { [string]$_ })
}

function Get-CanonicalFixture {
    param([string]$Name)
    $raw = @(Import-ClientJsonLinesFile (Join-Path $PSScriptRoot "fixtures/client-jsonl/$Name.jsonl"))
    return @($raw | ConvertTo-CanonicalClientEvidence)
}

function Get-PlanArgumentValue {
    param($Plan, [string]$Name)
    $index = [array]::IndexOf(@($Plan.arguments), $Name)
    if ($index -lt 0 -or $index + 1 -ge @($Plan.arguments).Count) { throw "TEST_PLAN_ARGUMENT_MISSING: $Name" }
    return [string]$Plan.arguments[$index + 1]
}

$environment = Get-EffectiveRuntimeEnvironment -Environment (Import-DotEnv (Join-Path $PSScriptRoot 'fixtures/.env.test')) -RuntimeConfig (Import-RuntimeConfig (Join-Path $root 'config/runtime.json'))
$contract = Import-ClientContract (Join-Path $root 'config/client-contract.json')
$catalog = @(Import-ScenarioCatalog (Join-Path $root 'scenarios'))
$jsonlPath = 'C:\Fixture\evidence\client.jsonl'

$stage34a = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'issue206-proxy-to-block-abortive') -Variables $environment
$plan34a = New-ClientPlan -Scenario $stage34a -ExecutablePath $environment['PB_CLIENT_EXE'] -RunId 'fixture-run' -JsonlPath $jsonlPath -Contract $contract
Assert-SequenceEqual (Get-ExpectedArguments 'stage34a-proxy-block') @($plan34a.arguments) 'Stage 3.4A exact argument array'
Assert-Equal ($plan34a.operation_timeout_ms * 2 + $plan34a.timeout_budget_components.bind_retry_budget_ms + $plan34a.process_exit_grace_ms) $plan34a.process_timeout_ms 'issue206 process budget must include two operations, bind retry, and grace'
Assert-Equal 2 $plan34a.timeout_budget_components.operation_count 'issue206 operation count'

$stage34b = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'issue206-proxy-to-direct-ipv4-abortive') -Variables $environment
$plan34b = New-ClientPlan -Scenario $stage34b -ExecutablePath $environment['PB_CLIENT_EXE'] -RunId 'fixture-run' -JsonlPath $jsonlPath -Contract $contract
Assert-SequenceEqual (Get-ExpectedArguments 'stage34b-proxy-direct') @($plan34b.arguments) 'Stage 3.4B exact argument array'

$base = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-ipv4-direct') -Variables $environment
$basePlan = New-ClientPlan $base $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-SequenceEqual (Get-ExpectedArguments 'base-single-tcp') @($basePlan.arguments) 'base single TCP exact argument array'
Assert-Equal ($basePlan.operation_timeout_ms + $basePlan.process_exit_grace_ms) $basePlan.process_timeout_ms 'base process budget must include one operation and exit grace'
Assert-True ($basePlan.process_timeout_ms -gt $basePlan.operation_timeout_ms) 'base watchdog must exceed operation timeout'
$baseProxy = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-ipv4-proxy') -Variables $environment
$baseProxyPlan = New-ClientPlan $baseProxy $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
$proxyPolicyIndex = [array]::IndexOf(@($baseProxyPlan.arguments), '--tcp-peer-policy')
Assert-Equal 'record-only' $baseProxyPlan.arguments[$proxyPolicyIndex + 1] 'base PROXY TCP must default to record-only peer policy'

$udpConnected = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-ipv4-connected-direct') -Variables $environment
$udpConnectedPlan = New-ClientPlan $udpConnected $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-SequenceEqual (Get-ExpectedArguments 'base-single-udp-connected') @($udpConnectedPlan.arguments) 'base connected UDP exact argument array'

$udpUnconnected = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-ipv4-unconnected-proxy') -Variables $environment
$udpUnconnectedPlan = New-ClientPlan $udpUnconnected $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-SequenceEqual (Get-ExpectedArguments 'base-single-udp-unconnected') @($udpUnconnectedPlan.arguments) 'base unconnected UDP exact argument array'

$udpPayload = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-payload-65507') -Variables $environment
$udpPayloadPlan = New-ClientPlan $udpPayload $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal '65507' (Get-PlanArgumentValue $udpPayloadPlan '--payload-size') 'UDP maximum application payload argument'
Assert-Equal 65507 $udpPayloadPlan.flows[0].payload_size 'UDP maximum application payload plan evidence'
$tcpPayload = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-payload-1m') -Variables $environment
$tcpPayloadPlan = New-ClientPlan $tcpPayload $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal '1048576' (Get-PlanArgumentValue $tcpPayloadPlan '--payload-size') 'TCP 1 MiB application payload argument'
Assert-Equal 1048576 $tcpPayloadPlan.flows[0].payload_size 'TCP 1 MiB application payload plan evidence'
$tcpStreaming = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-payload-streaming') -Variables $environment
$tcpStreamingPlan = New-ClientPlan $tcpStreaming $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal '4' (Get-PlanArgumentValue $tcpStreamingPlan '--stream-count') 'TCP stream message-count argument'
Assert-Equal 4 @($tcpStreamingPlan.flows).Count 'TCP stream plan must require four same-socket records'
Assert-Equal 4 $tcpStreamingPlan.timeout_budget_components.operation_count 'TCP stream watchdog must budget every message operation'
Assert-Equal ($tcpStreamingPlan.operation_timeout_ms * 4 + $tcpStreamingPlan.process_exit_grace_ms) $tcpStreamingPlan.process_timeout_ms 'TCP stream process budget'
$tcpParallel = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-parallel-connections') -Variables $environment
$tcpParallelPlan = New-ClientPlan $tcpParallel $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal '8' (Get-PlanArgumentValue $tcpParallelPlan '--parallel-count') 'TCP parallel flow-count argument'
Assert-Equal 8 @($tcpParallelPlan.flows).Count 'TCP parallel plan must require eight independent records'
Assert-Equal 8 $tcpParallelPlan.parallel_count 'TCP parallel count evidence'
Assert-Equal 1 $tcpParallelPlan.timeout_budget_components.operation_count 'parallel flows share one bounded wall-clock operation budget'
Assert-Equal ($tcpParallelPlan.operation_timeout_ms + $tcpParallelPlan.process_exit_grace_ms) $tcpParallelPlan.process_timeout_ms 'parallel process budget must not multiply simultaneous flow timeouts'
$invalidParallel = $tcpParallel | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$invalidParallel.client.local_port = 32000
Assert-Throws { New-ClientPlan $invalidParallel $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract } 'CLIENT_PARALLEL_REQUIRES_EPHEMERAL_PORTS' 'parallel executor must require independent ephemeral local ports'
$domainDirect = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'dns-domain-direct') -Variables $environment
$domainDirectPlan = New-ClientPlan $domainDirect $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal $environment['PB_TEST_DOMAIN'] (Get-PlanArgumentValue $domainDirectPlan '--remote-host') 'domain scenario must pass the configured hostname'
Assert-Equal $environment['PB_VPS_IPV4'] $domainDirectPlan.flows[0].remote_ip 'domain scenario must retain exact resolved-IP expectation'
Assert-Equal $environment['PB_TEST_DOMAIN'] $domainDirectPlan.flows[0].remote_host 'domain evidence plan must retain the requested hostname'
$halfClose = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-half-close') -Variables $environment
$halfClosePlan = New-ClientPlan $halfClose $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal 'half-close' (Get-PlanArgumentValue $halfClosePlan '--close-mode') 'half-close argument'
Assert-Equal 'half-close' $halfClosePlan.flows[0].close_mode 'half-close evidence expectation'
$serverClose = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-server-close') -Variables $environment
$serverClosePlan = New-ClientPlan $serverClose $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal 'server-close' (Get-PlanArgumentValue $serverClosePlan '--endpoint-behavior') 'server-close endpoint control argument'
$refused = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-refused') -Variables $environment
$refusedPlan = New-ClientPlan $refused $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal $environment['PB_ENDPOINT_ERROR_PORT'] (Get-PlanArgumentValue $refusedPlan '--tcp-remote-port') 'refused test must use reserved non-listener port'
Assert-Equal 0 $refusedPlan.flows[0].expected_vps_received 'refused test endpoint expectation'
$longLived = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-long-lived') -Variables $environment
$longLivedPlan = New-ClientPlan $longLived $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal '250' (Get-PlanArgumentValue $longLivedPlan '--stream-interval-ms') 'long-lived inter-message interval'
Assert-Equal 750 $longLivedPlan.timeout_budget_components.inter_flow_wait_ms 'long-lived watchdog must include three bounded waits'
$udpMultiDestination = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-one-socket-multiple-destinations') -Variables $environment
$udpMultiDestinationPlan = New-ClientPlan $udpMultiDestination $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal 2 @($udpMultiDestinationPlan.flows).Count 'UDP multi-destination plan flow count'
Assert-Equal $environment['PB_ENDPOINT_B_PORT'] (Get-PlanArgumentValue $udpMultiDestinationPlan '--second-remote-port') 'UDP second destination argument'
Assert-Equal $environment['PB_ENDPOINT_B_PORT'] ([string]$udpMultiDestinationPlan.flows[1].remote_port) 'UDP second destination evidence'
$udpDuplicate = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-duplicate-response') -Variables $environment
$udpDuplicatePlan = New-ClientPlan $udpDuplicate $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal 'duplicate' (Get-PlanArgumentValue $udpDuplicatePlan '--endpoint-behavior') 'UDP duplicate endpoint control'
Assert-Equal 2 $udpDuplicatePlan.flows[0].expected_response_count 'UDP duplicate client response expectation'
$udpMultipleSockets = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-multiple-sockets-one-destination') -Variables $environment
$udpMultipleSocketsPlan = New-ClientPlan $udpMultipleSockets $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal '8' (Get-PlanArgumentValue $udpMultipleSocketsPlan '--parallel-count') 'UDP multiple-socket parallel argument'
Assert-Equal 8 @($udpMultipleSocketsPlan.flows).Count 'UDP multiple-socket plan flow count'
$udpReconnect = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-idle-reconnect') -Variables $environment
$udpReconnectPlan = New-ClientPlan $udpReconnect $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal '2' (Get-PlanArgumentValue $udpReconnectPlan '--reconnect-count') 'UDP reconnect flow-count argument'
Assert-Equal '1000' (Get-PlanArgumentValue $udpReconnectPlan '--inter-flow-wait-ms') 'UDP reconnect idle-wait argument'
Assert-Equal 2 @($udpReconnectPlan.flows).Count 'UDP reconnect plan flow count'
Assert-Equal ($udpReconnectPlan.operation_timeout_ms * 2 + 1000 + $udpReconnectPlan.process_exit_grace_ms) $udpReconnectPlan.process_timeout_ms 'UDP reconnect watchdog budget'
$udpOutOfOrder = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-out-of-order') -Variables $environment
$udpOutOfOrderPlan = New-ClientPlan $udpOutOfOrder $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal 'out-of-order' (Get-PlanArgumentValue $udpOutOfOrderPlan '--endpoint-behavior') 'UDP reorder endpoint control'
Assert-Equal 2 @($udpOutOfOrderPlan.flows).Count 'UDP reorder flow count'
Assert-SequenceEqual @(2,1) @($udpOutOfOrderPlan.flows.expected_response_order) 'UDP reorder client response order'
$udpLateReuse = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-late-response-after-reuse') -Variables $environment
$udpLateReusePlan = New-ClientPlan $udpLateReuse $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal 'late-response' (Get-PlanArgumentValue $udpLateReusePlan '--endpoint-behavior') 'UDP late-response endpoint control'
Assert-Equal '20' (Get-PlanArgumentValue $udpLateReusePlan '--bind-retry-count') 'UDP late-response bounded bind retries'
Assert-SequenceEqual @('no-echo','echo') @($udpLateReusePlan.flows.expected_outcome) 'UDP late-response per-generation outcomes'
Assert-Equal ($udpLateReusePlan.operation_timeout_ms * 2 + 500 + $udpLateReusePlan.process_exit_grace_ms) $udpLateReusePlan.process_timeout_ms 'UDP late-response watchdog must include two operations, bind retry and grace'
$crossProcess = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'security-no-cross-process-delivery') -Variables $environment
$crossProcessPlan = New-ClientPlan $crossProcess $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-Equal 2 $crossProcessPlan.process_count 'cross-process plan process count'
Assert-Equal 2 @($crossProcessPlan.flows).Count 'cross-process plan flow count'
Assert-Equal 2 @($crossProcessPlan.child_process_plans).Count 'cross-process child plan count'
Assert-Equal '1' (Get-PlanArgumentValue $crossProcessPlan.child_process_plans[0] '--process-index') 'first child process index'
Assert-Equal '2' (Get-PlanArgumentValue $crossProcessPlan.child_process_plans[1] '--process-index') 'second child process index'
Assert-True ([string]$crossProcessPlan.child_process_plans[0].jsonl_path -ne [string]$crossProcessPlan.child_process_plans[1].jsonl_path) 'cross-process children must write separate JSONL files'
Assert-Equal 1 $crossProcessPlan.timeout_budget_components.operation_count 'concurrent child processes share one bounded wall-clock operation budget'

$issue209 = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'issue209-tcp-to-udp') -Variables $environment
$issue209Plan = New-ClientPlan $issue209 $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-SequenceEqual (Get-ExpectedArguments 'issue209-tcp-to-udp') @($issue209Plan.arguments) 'issue209 exact argument array'
Assert-Equal 'EXECUTABLE' $issue209.implementation_status 'exact issue209 builder and three-record model must be executable'
Assert-Equal 3 @($issue209Plan.expected_records).Count 'issue209 plan must require two flows and held recheck'
Assert-Equal ($issue209Plan.operation_timeout_ms * 3 + $issue209Plan.timeout_budget_components.inter_flow_wait_ms + $issue209Plan.timeout_budget_components.bind_retry_budget_ms + $issue209Plan.process_exit_grace_ms) $issue209Plan.process_timeout_ms 'issue209 process budget must include three phases, inter-flow wait, bind retry, and grace'
Assert-Equal 3 $issue209Plan.timeout_budget_components.operation_count 'issue209 operation count'

$cappedPlan = New-ClientPlan -Scenario $base -ExecutablePath $environment['PB_CLIENT_EXE'] -RunId 'fixture-run' -JsonlPath $jsonlPath -Contract $contract -OperationTimeoutCapMs 1200 -ProcessExitGraceMs 2000
Assert-Equal 1200 $cappedPlan.operation_timeout_ms 'suite cap must apply to operation timeout'
Assert-Equal '1200' (Get-PlanArgumentValue -Plan $cappedPlan -Name '--timeout-ms') 'suite cap must synchronize --timeout-ms argument'
Assert-Equal 3200 $cappedPlan.process_timeout_ms 'base process timeout must be recomputed after operation cap'
$invalidIssue209 = $issue209 | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$invalidIssue209.client.first_expect = 'no-echo'
Assert-Throws { New-ClientPlan $invalidIssue209 $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract } 'CLIENT_ISSUE209_FIRST_EXPECT_MUST_BE_ECHO' 'issue209 first expectation must be echo'

$unsupportedFlags = @('--socket-mode','--remote-port','--second-protocol','--hold-first','--recheck-first')
foreach ($plan in @($basePlan, $baseProxyPlan, $udpConnectedPlan, $udpUnconnectedPlan, $udpReconnectPlan, $udpOutOfOrderPlan, $udpLateReusePlan, $issue209Plan, $crossProcessPlan)) {
    foreach ($flag in $unsupportedFlags) { Assert-True (@($plan.arguments) -notcontains $flag) "$($plan.executor) must not emit unsupported $flag" }
}
Assert-Equal 'single' $basePlan.arguments[1] 'base builder must use harness single mode'

$normalized34a = @(Get-CanonicalFixture 'stage34a-issue206-proxy-block')
Assert-Equal 2 $normalized34a.Count 'Stage 3.4A real-format JSONL must normalize two records'
Assert-Equal 0 $normalized34a[0].flow_index 'Stage 3.4A first flow index'
Assert-True $normalized34a[1].no_response 'Stage 3.4A no-echo pass must normalize no_response'
Assert-True ($null -ne $normalized34a[0].raw_record) 'canonical evidence must retain raw record'

$normalized34b = @(Get-CanonicalFixture 'stage34b-issue206-proxy-direct')
Assert-Equal 2 $normalized34b.Count 'Stage 3.4B real-format JSONL must normalize two records'
Assert-Equal 'DIRECT' $normalized34b[1].expected_action 'Stage 3.4B second action must normalize'
Assert-True $normalized34b[1].client_pass 'Stage 3.4B echo pass must normalize client_pass'

$normalized209 = @(Get-CanonicalFixture 'issue209-three-record')
Assert-Equal 3 $normalized209.Count 'issue209 real-format JSONL must normalize three records'
Assert-SequenceEqual @('first_flow','second_flow','held_recheck') @($normalized209.phase) 'issue209 phases must remain ordered'
Assert-Equal 'held_recheck' $normalized209[2].record_kind 'held recheck record kind must normalize explicitly'
Assert-Equal 0 $normalized209[2].flow_index 'held recheck must relate to first flow'

$temp = New-TestDirectory
try {
    $outputPath = Join-Path $temp 'client.jsonl'
    $fixtureLine = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/client-jsonl/stage34a-issue206-proxy-block.jsonl') -Encoding UTF8 | Select-Object -First 1
    Write-TestUtf8NoBom $outputPath $fixtureLine
    $expectedHash = 'a' * 64
    $filePlan = [pscustomobject]@{ executable='fixture-client.exe';expected_sha256=$expectedHash;arguments=@('--mode','single');timeout_ms=100;actual_path_timeout_ms=50;jsonl_path=$outputPath }
    $processResult = [pscustomobject]@{exit_code=0;timed_out=$false;pid=7;actual_path='fixture-client.exe';actual_path_probe_status='PATH_OBTAINED';actual_path_probe_attempts=1;actual_path_probe_elapsed_ms=0;stdout='human stdout, not json';stderr='human stderr'}
    $result = Invoke-ClientPlan -Plan $filePlan -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($processResult))
    Assert-Equal 1 @($result.raw_records).Count 'client must preserve raw JSONL records'
    Assert-Equal 1 @($result.canonical_records).Count 'client must return canonical JSONL records'
    Assert-Equal 'human stdout, not json' $result.stdout 'human stdout must be preserved separately'
    Assert-Equal 'human stderr' $result.stderr 'human stderr must be preserved separately'
    Assert-True $result.prelaunch_path_verified 'client path must be verified before launch'
    Assert-True $result.prelaunch_hash_verified 'client hash must be verified before launch'
    Assert-True $result.actual_path_required 'observed client path must remain required when available'

    $shortResult = [pscustomobject]@{exit_code=0;timed_out=$false;pid=8;actual_path='';actual_path_probe_status='PROCESS_EXITED';actual_path_probe_attempts=1;actual_path_probe_elapsed_ms=1;stdout='';stderr=''}
    $shortClient = Invoke-ClientPlan -Plan $filePlan -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($shortResult))
    Assert-Equal 0 $shortClient.exit_code 'successful short-lived client exit code'
    Assert-Equal 1 @($shortClient.canonical_records).Count 'successful short-lived client must still consume valid JSONL'
    Assert-Equal 'PROCESS_EXITED' $shortClient.actual_path_probe_status 'short-lived client probe status'
    Assert-True (-not $shortClient.actual_path_required) 'successful hash-verified short-lived client must not require observed path'
    Assert-Equal '' $shortClient.actual_path 'short-lived client must not substitute requested path as observed path'

    $failedShortResult = [pscustomobject]@{exit_code=7;timed_out=$false;pid=9;actual_path='';actual_path_probe_status='PROCESS_EXITED';actual_path_probe_attempts=1;actual_path_probe_elapsed_ms=1;stdout='';stderr='fixture client failure'}
    $failedShortClient = Invoke-ClientPlan -Plan $filePlan -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($failedShortResult))
    Assert-Equal 7 $failedShortClient.exit_code 'nonzero short-lived client must remain a client failure result'
    Assert-Equal 'PROCESS_EXITED' $failedShortClient.actual_path_probe_status 'nonzero short-lived client must not become a path failure'

    $queryTimeoutResult = [pscustomobject]@{exit_code=-1;timed_out=$true;pid=10;actual_path='';actual_path_probe_status='QUERY_TIMEOUT';actual_path_probe_attempts=3;actual_path_probe_elapsed_ms=50;stdout='';stderr=''}
    Assert-Throws { Invoke-ClientPlan -Plan $filePlan -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($queryTimeoutResult)) } 'CLIENT_PATH_QUERY_TIMEOUT' 'long-running client with unavailable path must fail explicitly'

    $wrongPathResult = [pscustomobject]@{exit_code=0;timed_out=$false;pid=11;actual_path='C:\Fixture\wrong-client.exe';actual_path_probe_status='PATH_OBTAINED';actual_path_probe_attempts=1;actual_path_probe_elapsed_ms=0;stdout='';stderr=''}
    Assert-Throws { Invoke-ClientPlan -Plan $filePlan -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($wrongPathResult)) } 'CLIENT_PATH_VERIFICATION_FAILED' 'observed wrong client path must fail verification'

    $hashMismatchAdapter = New-MockProcessAdapter -InvokeResults @($processResult) -PrelaunchHashVerified $false
    Assert-Throws { Invoke-ClientPlan -Plan $filePlan -ProcessAdapter $hashMismatchAdapter } 'CLIENT_PRELAUNCH_HASH_MISMATCH' 'prelaunch hash mismatch must fail before process start'
    Assert-Equal 0 $hashMismatchAdapter.state.invoke_count 'prelaunch hash mismatch must not invoke process adapter'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }

'PASS: client contract'
