[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/ScenarioCatalog.psm1') -Force
$catalog = @(Import-ScenarioCatalog (Join-Path $root 'scenarios'))
Assert-Equal 205 $catalog.Count 'catalog declaration count must include the Milestone 15 realtime matrix'
Assert-Equal $catalog.Count @($catalog.scenario_id | Sort-Object -Unique).Count 'scenario IDs must be unique'
$groups = @($catalog.coverage_group | Sort-Object -Unique)
Assert-True ($groups.Count -ge 12) 'catalog must cover at least 12 groups'
Assert-Equal 18 @($catalog | Where-Object { $_.coverage_group -eq 'base-policy' }).Count 'critical protocol/family/action matrix must remain exhaustive'
Assert-True (@($catalog | Where-Object { $_.coverage_group -eq 'issue206' }).Count -ge 9) 'all issue206 transitions plus legacy regression must exist'
Assert-Equal 7 @($catalog | Where-Object implementation_status -eq 'UNSUPPORTED_PRODUCT_SCOPE').Count 'unsupported product scope declarations must exist'
Assert-Equal 172 @($catalog | Where-Object implementation_status -eq 'EXECUTABLE').Count 'completed native, protocol-aware and controlled canary waves must be executable'
Assert-Equal 0 @($catalog | Where-Object implementation_status -eq 'DECLARATIVE_ONLY').Count 'approved roadmap items must resolve to an executable contract or an honest capability gate'
Assert-Equal 5 @($catalog | Where-Object implementation_status -eq 'SYSTEM_CHECK').Count 'cross-cutting lifecycle coverage must be represented as system checks'
Assert-Equal 21 @($catalog | Where-Object implementation_status -eq 'CAPABILITY_GATED').Count 'unavailable browser, failure-control, performance, LAN and product contracts must be capability gated'
Assert-Equal 15 @($catalog | Where-Object coverage_group -eq 'protocol-core').Count 'DNS, TLS, HTTP and HTTPS must cover DIRECT, BLOCK and PROXY'
Assert-Equal 15 @($catalog | Where-Object coverage_group -eq 'protocol-advanced').Count 'HTTP/2, gRPC, WebSocket, HTTP/3 and WebTransport must cover DIRECT, BLOCK and PROXY'
Assert-Equal 31 @($catalog | Where-Object coverage_group -eq 'protocol-standard').Count 'standard protocol coverage plus the explicit SFTP gate'
Assert-Equal 9 @($catalog | Where-Object coverage_group -eq 'protocol-realtime').Count 'STUN, TURN and SRTP must cover DIRECT, BLOCK and PROXY'
foreach($protocolScenario in @($catalog|Where-Object coverage_group -eq 'protocol-core')){
    Assert-Equal 'protocol-worker' $protocolScenario.executor_kind "$($protocolScenario.scenario_id) must use the protocol worker"
    Assert-Equal 'EXECUTABLE' $protocolScenario.implementation_status "$($protocolScenario.scenario_id) must have an executable evidence contract"
    Assert-True ($null-ne $protocolScenario.protocol_worker) "$($protocolScenario.scenario_id) protocol worker plan"
    Assert-True (@($protocolScenario.rule_set)[0].application -eq '${PB_PROTOCOL_WORKER_APPLICATION_BASENAME}') "$($protocolScenario.scenario_id) rule must watch the bundled Python worker"
}
foreach($protocolScenario in @($catalog|Where-Object coverage_group -eq 'protocol-advanced')){
    Assert-Equal 'protocol-worker' $protocolScenario.executor_kind "$($protocolScenario.scenario_id) must use the pinned protocol worker"
    Assert-Equal 'EXECUTABLE' $protocolScenario.implementation_status "$($protocolScenario.scenario_id) must have an executable evidence contract"
    Assert-True (@('http2-transaction','rpc-transaction','websocket-transaction','quic-http3-transaction') -contains [string]$protocolScenario.protocol_worker.evidence_profile_id) "$($protocolScenario.scenario_id) evidence profile"
}
foreach($protocolScenario in @($catalog|Where-Object { $_.coverage_group -eq 'protocol-standard' -and $_.implementation_status -eq 'EXECUTABLE' })){
    Assert-Equal 'protocol-worker' $protocolScenario.executor_kind "$($protocolScenario.scenario_id) must use the pinned protocol worker"
    Assert-True (@('file-transfer','mail-transaction','messaging-transaction','time-transaction','multi-peer-transaction') -contains [string]$protocolScenario.protocol_worker.evidence_profile_id) "$($protocolScenario.scenario_id) evidence profile"
}
$sftp = $catalog | Where-Object scenario_id -eq 'protocol-sftp'
Assert-Equal 'CAPABILITY_GATED' $sftp.implementation_status 'SFTP must not claim an incomplete SSH transport contract'
Assert-True (@($sftp.requires) -contains 'protocol_sftp') 'SFTP gate must name its unavailable capability'
Assert-Equal '${PB_PROTOCOL_SFTP_PORT}' $sftp.client.remote_port 'SFTP must use the managed endpoint port when enabled later'
Assert-Equal 18 @($catalog | Where-Object { $_.coverage_group -eq 'base-policy' -and $_.implementation_status -eq 'EXECUTABLE' }).Count 'base critical matrix must be executable and capability-gated'
Assert-Equal 9 @($catalog | Where-Object { $_.coverage_group -eq 'issue206' -and $_.implementation_status -eq 'EXECUTABLE' }).Count 'all issue206 transitions must have an executable two-flow contract'
foreach ($scenario in $catalog) {
    Assert-True (@($scenario.tags | Sort-Object -Unique).Count -eq @($scenario.tags).Count) "scenario tags must be unique"
    Assert-True (@('EXECUTABLE','DECLARATIVE_ONLY','SYSTEM_CHECK','CAPABILITY_GATED','UNSUPPORTED_PRODUCT_SCOPE') -contains [string]$scenario.implementation_status) 'implementation status must be explicit'
    if ($scenario.implementation_status -eq 'DECLARATIVE_ONLY') { Assert-True (-not [string]::IsNullOrWhiteSpace([string]$scenario.implementation_reason)) 'declarative scenario must explain missing executor' }
    if ($scenario.implementation_status -eq 'EXECUTABLE') {
        Assert-True (@('base','issue206','issue209') -contains [string]$scenario.client.mode) "$($scenario.scenario_id) executable mode must be supported by the client contract"
        Assert-True (@($scenario.assertions).Count -gt 0) "$($scenario.scenario_id) executable scenario must declare assertions"
        if ([string]$scenario.profile_expectation -eq 'valid') { Assert-True (-not [string]::IsNullOrWhiteSpace([string]$scenario.mock_fixture_id)) "$($scenario.scenario_id) executable scenario must have an offline fixture" }
    }
    if ([int]$scenario.client.family -eq 6) { Assert-True (@($scenario.requires) -contains 'ipv6') "$($scenario.scenario_id) IPv6 execution must be capability-gated" }
}
$genericDeclarativeReasons=@(
    'No real-application executor is implemented.',
    'No failure injector is implemented.',
    'Lifecycle behavior is covered by adapter unit tests, not by this network scenario executor.',
    'No performance executor or metric collector is implemented.',
    'The executor does not encode this rule-engine semantic.',
    'The executor does not encode the required multi-flow or multi-process security semantic.',
    'The base executor does not encode this lifecycle behavior.',
    'The base UDP executor does not encode this multi-datagram or lifecycle semantic.'
)
Assert-Equal 0 @($catalog|Where-Object{$_.implementation_status -eq 'DECLARATIVE_ONLY' -and $genericDeclarativeReasons -contains [string]$_.implementation_reason}).Count 'every remaining declarative case must state its own concrete limitation'
Assert-True ([string]($catalog|Where-Object scenario_id -eq 'udp-receive-only').implementation_reason -match 'NAT') 'receive-only limitation must explain the NAT boundary'
$receiveOnly = $catalog | Where-Object scenario_id -eq 'udp-receive-only'
Assert-Equal 'EXECUTABLE' $receiveOnly.implementation_status 'registered receive-only UDP must use the controlled endpoint contract'
Assert-Equal 'udp-registration-session' $receiveOnly.protocol_worker.evidence_profile_id 'receive-only UDP evidence profile'
foreach ($id in @('canary-webrtc','canary-screen-sharing')) {
    $browserScenario = $catalog | Where-Object scenario_id -eq $id
    Assert-Equal 'CAPABILITY_GATED' $browserScenario.implementation_status "$id must not claim synthetic browser or WebRTC execution"
    Assert-True (@($browserScenario.requires) -contains 'local_browser_runtime') "$id must name the automatic local browser gate"
}
$browserDownload = $catalog | Where-Object scenario_id -eq 'canary-browser-download'
Assert-Equal 'EXECUTABLE' $browserDownload.implementation_status 'controlled browser download must use the reviewed browser worker and origin contract'
Assert-Equal 'protocol-worker' $browserDownload.executor_kind 'browser controller remains the protocol worker runtime'
Assert-Equal 'browser-worker' $browserDownload.protocol_worker.plugin_id 'browser download worker plugin'
Assert-Equal 'browser-web' $browserDownload.protocol_worker.protocol_family 'browser download protocol family'
Assert-Equal 'browser-session' $browserDownload.protocol_worker.evidence_profile_id 'browser download evidence profile'
Assert-SequenceEqual @('local_browser_runtime','server_browser_origin','protocol_worker','ipv4','tcp','process_basename_rules') @($browserDownload.requires) 'browser download must preserve only its automatic runtime/origin and derived execution gates'
Assert-Equal '${PB_BROWSER_APPLICATION_BASENAME}' $browserDownload.rule_set[0].application 'browser DIRECT rule must use the automatically derived browser basename'
Assert-SequenceEqual @('${PB_PROTOCOL_HTTP_PORT}') @($browserDownload.rule_set[0].ports) 'browser DIRECT rule must discriminate the controlled HTTP origin port'
Assert-Equal 'TCP' $browserDownload.rule_set[0].protocol 'browser download rule transport'
Assert-Equal 'DIRECT' $browserDownload.rule_set[0].action 'browser download rule action'
foreach ($id in @('failure-proxy-unavailable','failure-proxy-auth','failure-backend-restart','udp-backend-restart')) {
    $failureGate = $catalog | Where-Object scenario_id -eq $id
    Assert-Equal 'CAPABILITY_GATED' $failureGate.implementation_status "$id must not run without an isolated failure-control contract"
    Assert-True (@($failureGate.requires) -contains 'control_failure_injection') "$id must require bounded failure-control authorization"
}
foreach ($id in @('performance-latency','performance-throughput','performance-cpu','performance-memory','performance-handles','performance-threads','performance-flow-rate','performance-datagrams-per-second')) {
    $performanceGate = $catalog | Where-Object scenario_id -eq $id
    Assert-Equal 'CAPABILITY_GATED' $performanceGate.implementation_status "$id must not turn correctness timing into a performance verdict"
    Assert-True (@($performanceGate.requires) -contains 'local_performance_worker') "$id must require the native performance worker"
}
foreach ($id in @('failure-dns','failure-client-process-exit','tcp-process-termination')) {
    $failureScenario = $catalog | Where-Object scenario_id -eq $id
    Assert-Equal 'EXECUTABLE' $failureScenario.implementation_status "$id must use a bounded controlled failure contract"
    Assert-Equal 'protocol-worker' $failureScenario.executor_kind "$id must use protocol-aware evidence"
}
foreach ($id in @('canary-http','canary-https','canary-dns','canary-http2','canary-http3-quic','canary-stun','canary-discord-voice')) {
    $canary = $catalog | Where-Object scenario_id -eq $id
    Assert-Equal 'EXECUTABLE' $canary.implementation_status "$id must use a completed protocol contract"
    Assert-Equal 'protocol-worker' $canary.executor_kind "$id must use protocol-aware evidence"
}
$voice = $catalog | Where-Object scenario_id -eq 'canary-discord-voice'
Assert-Equal 'rtp-media-session' $voice.protocol_worker.evidence_profile_id 'voice equivalence must use SRTP/RTCP evidence rather than an external account'
foreach ($id in @('rule-hot-update','rule-persistence')) {
    Assert-Equal 'CAPABILITY_GATED' ($catalog | Where-Object scenario_id -eq $id).implementation_status "$id must not claim a product API that does not exist"
}
Assert-Equal 5 @($catalog | Where-Object { $_.coverage_group -eq 'orchestrator-lifecycle' -and $_.implementation_status -eq 'SYSTEM_CHECK' }).Count 'lifecycle inventory must map to enforced controller checks'
$negative = $catalog | Where-Object scenario_id -eq 'rule-missing-proxy-config'
Assert-Equal 'invalid-missing-proxy-config' $negative.profile_expectation 'missing proxy config must be intentional negative validation'
foreach ($id in @('issue206-direct-to-block','issue206-direct-to-proxy','issue206-proxy-to-block','issue206-block-to-direct','issue206-block-to-proxy')) {
    $transition = $catalog | Where-Object scenario_id -eq $id
    Assert-Equal 'EXECUTABLE' $transition.implementation_status "$id must attempt both exact-port flows"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$transition.mock_fixture_id)) "$id must have two-flow offline evidence"
}
foreach ($id in @('issue206-proxy-to-direct-abortive','issue206-direct-to-proxy-abortive','issue206-proxy-to-block-abortive','issue206-proxy-to-direct-ipv4-abortive')) {
    Assert-Equal 'EXECUTABLE' ($catalog | Where-Object scenario_id -eq $id).implementation_status "$id deterministic abortive contract must remain executable"
}
foreach ($id in @('rule-selector-basename','rule-selector-full-path','rule-destination-ip','rule-single-port','rule-port-range')) {
    $discriminating = $catalog | Where-Object scenario_id -eq $id
    Assert-Equal 'BLOCK' $discriminating.client.expected_action "$id must not use fail-open-indistinguishable DIRECT"
    Assert-Equal 'BLOCK' $discriminating.rule_set[0].action "$id profile must externally discriminate a rule match"
}
$fullPath = $catalog | Where-Object scenario_id -eq 'rule-selector-full-path'
Assert-True ($fullPath.mock.expected_status -eq 'EXPECTED_FAIL' -and $fullPath.known_defect_id -eq 'full-path-watchlist-mismatch') 'full-path BLOCK regression must retain expected-failure mapping'
$watchedUdp = $catalog | Where-Object scenario_id -eq 'udp-watched-process-direct-drop'
Assert-Equal 2 @($watchedUdp.rule_set).Count 'watched UDP DIRECT profile must include a separate watch-enabling rule'
Assert-Equal 'DIRECT' $watchedUdp.rule_set[0].action 'tested watched UDP flow must remain DIRECT'
Assert-True ([string]$watchedUdp.rule_set[1].action -ne 'DIRECT') 'separate watched UDP rule must force the basename into the watchlist'
Assert-Equal $watchedUdp.rule_set[0].application $watchedUdp.rule_set[1].application 'watch-enabling rule must target the same basename'
$knownDefects = Get-Content -LiteralPath (Join-Path $root 'config/known-defects.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($id in @('udp-ipv4-connected-proxy','udp-ipv4-unconnected-proxy')) {
    Assert-Equal 'udp-proxy-reverse-source' (Get-KnownDefectMatch -Scenario ($catalog | Where-Object scenario_id -eq $id) -KnownDefects $knownDefects).id "$id must share proven UDP source-restoration defect coverage"
}
foreach ($id in @('tcp-payload-1','tcp-payload-small','tcp-payload-64k','tcp-payload-1m','udp-payload-0','udp-payload-65507')) {
    $payloadScenario = $catalog | Where-Object scenario_id -eq $id
    Assert-Equal 'EXECUTABLE' $payloadScenario.implementation_status "$id must use the configurable payload contract"
    Assert-Equal 'base-payload-direct' $payloadScenario.mock_fixture_id "$id must use payload-aware evidence fixtures"
}
$streaming = $catalog | Where-Object scenario_id -eq 'tcp-payload-streaming'
Assert-Equal 'EXECUTABLE' $streaming.implementation_status 'streaming must use the multi-record same-socket client contract'
Assert-Equal 4 $streaming.parameters.stream_count 'streaming must emit four independently evidenced messages'
Assert-Equal 'base-streaming-direct' $streaming.mock_fixture_id 'streaming must use its same-socket fixture'
foreach($id in @('dns-domain-direct','dns-domain-proxy','rule-destination-domain')){
    $domainScenario=$catalog|Where-Object scenario_id -eq $id
    Assert-Equal 'EXECUTABLE' $domainScenario.implementation_status "$id must use hostname resolution plus exact-IP evidence"
    Assert-Equal '${PB_TEST_DOMAIN}' $domainScenario.client.remote_host "$id must pass the configured domain to the client"
}
$domainDirect=$catalog|Where-Object scenario_id -eq 'dns-domain-direct'
Assert-Equal 'BLOCK' $domainDirect.rule_set[1].action 'domain DIRECT must have a discriminating IP fallback'
$disabledRule=$catalog|Where-Object scenario_id -eq 'rule-disabled'
Assert-Equal 'BLOCK' $disabledRule.rule_set[0].action 'disabled rule must be a non-DIRECT action'
Assert-True (-not [bool]$disabledRule.rule_set[0].enabled) 'disabled rule must remain disabled'
Assert-Equal 'DIRECT' $disabledRule.client.expected_action 'disabled non-DIRECT rule must prove fail-open behavior with DIRECT traffic'
$overlapRule=$catalog|Where-Object scenario_id -eq 'rule-priority-overlap'
Assert-SequenceEqual @('DIRECT','BLOCK') @($overlapRule.rule_set.action) 'overlap priority must preserve primary then conflicting rule order'
Assert-True ([bool]$overlapRule.parameters.require_internal_route) 'overlap priority must require an internal route decision'
$multipleConfigs=$catalog|Where-Object scenario_id -eq 'rule-multiple-proxy-configs'
Assert-Equal 2 $multipleConfigs.rule_set[0].proxy_config_id 'multiple-proxy scenario must select config 2'
Assert-True ([bool]$multipleConfigs.parameters.require_internal_route) 'multiple-proxy scenario must require exact config evidence'
Assert-True ([bool]$multipleConfigs.parameters.require_proxy_config_evidence) 'multiple-proxy scenario must reject route records without config ID'
$bothRule=$catalog|Where-Object scenario_id -eq 'rule-protocol-both'
Assert-Equal 'issue209' $bothRule.client.mode 'BOTH rule must exercise TCP and UDP in one scenario contract'
Assert-Equal 'BOTH' $bothRule.rule_set[0].protocol 'BOTH profile rule must remain a single BOTH rule'
$freshSecurity=$catalog|Where-Object scenario_id -eq 'security-fresh-flow-no-stale-action'
Assert-Equal 'issue206' $freshSecurity.client.mode 'fresh-flow security must use a two-action transition'
Assert-SequenceEqual @('PROXY','DIRECT') @($freshSecurity.rule_set.action) 'fresh-flow security transition'
$configIsolation=$catalog|Where-Object scenario_id -eq 'security-no-proxy-config-inheritance'
Assert-SequenceEqual @(1,2) @($configIsolation.rule_set.proxy_config_id) 'proxy-config isolation must switch from config 1 to config 2'
Assert-True ([bool]$configIsolation.parameters.require_proxy_config_evidence) 'proxy-config isolation must require config IDs on both flows'
foreach($id in @('tcp-graceful-close','tcp-abortive-close','tcp-half-close','tcp-server-close','tcp-reset','tcp-refused','tcp-timeout','tcp-long-lived','tcp-sequential-reuse')){
    Assert-Equal 'EXECUTABLE' ($catalog|Where-Object scenario_id -eq $id).implementation_status "$id must have a lifecycle evidence contract"
}
Assert-Equal '${PB_ENDPOINT_ERROR_PORT}' ($catalog|Where-Object scenario_id -eq 'tcp-refused').client.remote_port 'refused connection must target the reserved non-listener port'
Assert-Equal 0 ($catalog|Where-Object scenario_id -eq 'tcp-refused').parameters.expected_vps_received 'refused connection must require zero endpoint payloads'
Assert-Equal 'server-close' ($catalog|Where-Object scenario_id -eq 'tcp-server-close').parameters.endpoint_behavior 'server close must use endpoint control behavior'
Assert-Equal 4 ($catalog|Where-Object scenario_id -eq 'tcp-long-lived').parameters.stream_count 'long-lived test must keep four messages on one socket'
foreach($id in @('udp-one-socket-multiple-destinations','udp-delayed-response','udp-duplicate-response','udp-drop')){
    Assert-Equal 'EXECUTABLE' ($catalog|Where-Object scenario_id -eq $id).implementation_status "$id must have exact UDP semantics evidence"
}
$tcpParallel=$catalog|Where-Object scenario_id -eq 'tcp-parallel-connections'
Assert-Equal 'EXECUTABLE' $tcpParallel.implementation_status 'parallel TCP must use the bounded client executor'
Assert-Equal 8 $tcpParallel.parameters.parallel_count 'parallel TCP must request eight independent flows'
$udpParallel=$catalog|Where-Object scenario_id -eq 'udp-multiple-sockets-one-destination'
Assert-Equal 'EXECUTABLE' $udpParallel.implementation_status 'multiple UDP sockets must use the bounded client executor'
Assert-Equal 8 $udpParallel.parameters.parallel_count 'multiple UDP sockets must request eight independent flows'
$udpReconnect=$catalog|Where-Object scenario_id -eq 'udp-idle-reconnect'
Assert-Equal 'EXECUTABLE' $udpReconnect.implementation_status 'UDP idle reconnect must use the sequential fresh-socket contract'
Assert-Equal 2 $udpReconnect.parameters.reconnect_count 'UDP idle reconnect flow count'
Assert-Equal 1000 $udpReconnect.parameters.reconnect_wait_ms 'UDP idle reconnect bounded idle interval'
$udpOutOfOrder=$catalog|Where-Object scenario_id -eq 'udp-out-of-order'
Assert-Equal 'EXECUTABLE' $udpOutOfOrder.implementation_status 'UDP out-of-order must use the two-datagram endpoint contract'
Assert-Equal 'out-of-order' $udpOutOfOrder.parameters.endpoint_behavior 'UDP out-of-order endpoint behavior'
Assert-Equal 2 $udpOutOfOrder.parameters.stream_count 'UDP out-of-order datagram count'
$udpLateReuse=$catalog|Where-Object scenario_id -eq 'udp-late-response-after-reuse'
Assert-Equal 'EXECUTABLE' $udpLateReuse.implementation_status 'UDP late response must use exact tuple reuse with socket-generation evidence'
Assert-Equal 'late-response' $udpLateReuse.parameters.endpoint_behavior 'UDP late-response endpoint behavior'
Assert-Equal 500 $udpLateReuse.parameters.behavior_delay_ms 'UDP late-response bounded delay'
$pairwise=@($catalog|Where-Object coverage_group -eq 'secondary-pairwise')
Assert-Equal 4 @($pairwise|Where-Object implementation_status -eq 'EXECUTABLE').Count 'external pairwise cases must be executable'
Assert-Equal 4 @($pairwise|Where-Object implementation_status -eq 'CAPABILITY_GATED').Count 'LAN pairwise cases must remain explicitly topology gated'
foreach($externalCase in @($pairwise|Where-Object implementation_status -eq 'EXECUTABLE')){
    Assert-Equal 'external' $externalCase.parameters.topology "$($externalCase.scenario_id) executable pairwise topology"
    Assert-True ([bool]$externalCase.parameters.require_internal_route) "$($externalCase.scenario_id) DIRECT pairwise case must require internal route evidence"
    Assert-Equal 'generated-base-direct' $externalCase.mock_fixture_id "$($externalCase.scenario_id) generated fixture contract"
}
foreach($lanCase in @($pairwise|Where-Object implementation_status -eq 'CAPABILITY_GATED')){
    Assert-Equal 'lan' $lanCase.parameters.topology "$($lanCase.scenario_id) deferred pairwise topology"
    Assert-True ([string]$lanCase.implementation_reason -match 'LAN topology') "$($lanCase.scenario_id) must state the LAN limitation"
}
$crossProcess=$catalog|Where-Object scenario_id -eq 'security-no-cross-process-delivery'
Assert-Equal 'EXECUTABLE' $crossProcess.implementation_status 'cross-process isolation must use the multi-process client contract'
Assert-Equal 2 $crossProcess.parameters.process_count 'cross-process isolation must launch two client processes'
Assert-True ([bool]$crossProcess.parameters.require_internal_route) 'cross-process isolation must bind each PID to an internal route record'
foreach($failureId in @('failure-connect-refused','failure-silent-timeout')){
    $failureScenario=$catalog|Where-Object scenario_id -eq $failureId
    Assert-Equal 'EXECUTABLE' $failureScenario.implementation_status "$failureId must use an exact bounded failure contract"
    Assert-Equal 'DIRECT' $failureScenario.client.expected_action "$failureId must not depend on mutating the configured proxy"
}
$udpMultiDestination=$catalog|Where-Object scenario_id -eq 'udp-one-socket-multiple-destinations'
Assert-Equal 'unconnected' $udpMultiDestination.client.socket_mode 'one UDP socket must use sendto across two destinations'
Assert-Equal 2 $udpMultiDestination.parameters.stream_count 'one UDP socket must emit two independently identified datagrams'
Assert-Equal 2 ($catalog|Where-Object scenario_id -eq 'udp-duplicate-response').parameters.expected_response_count 'duplicate response must be observed twice by the client'
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
$uiHtml = Get-Content -LiteralPath (Join-Path $root 'ui/ProxyBridge.TestLab.Ui/wwwroot/index.html') -Raw -Encoding UTF8
$uiScript = Get-Content -LiteralPath (Join-Path $root 'ui/ProxyBridge.TestLab.Ui/wwwroot/app.js') -Raw -Encoding UTF8
Assert-True ($uiHtml -match 'catalog-coverage-matrix') 'catalog UI must expose coverage readiness by group'
Assert-True ($uiScript -match 'cannot produce a real product verdict') 'catalog UI must explain non-executable coverage honestly'
'PASS: catalog'
