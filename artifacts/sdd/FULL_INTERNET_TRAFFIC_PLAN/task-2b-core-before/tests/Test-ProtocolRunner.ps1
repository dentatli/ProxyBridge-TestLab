[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/ProtocolWorker.psm1') -Force
Import-Module (Join-Path $root 'modules/ProtocolRunner.psm1') -Force
Import-Module (Join-Path $root 'modules/ProcessAdapter.psm1') -Force
Import-Module (Join-Path $root 'modules/ProxyBridgeEvidence.psm1') -Force

$runtimeContracts = Import-ProtocolWorkerRuntimeContract -RuntimeContractPath (Join-Path $root 'config/protocol-worker-runtime.json') -PluginManifestPath (Join-Path $root 'src/protocol_worker/plugins/manifest.json')
$temp = New-TestDirectory

function New-Scenario([string]$Action) {
    return [pscustomobject][ordered]@{
        scenario_id="protocol-dns-$($Action.ToLowerInvariant())";executor_kind='protocol-worker';timeout_ms=5000;requires=@('ipv4','udp','protocol_worker')
        client=[pscustomobject]@{expected_action=$Action;protocol='UDP'}
        protocol_worker=[pscustomobject]@{
            plugin_id='protocol-dns';protocol_family='dns-classic';transport='UDP';evidence_profile_id='dns-transaction'
            parameters=[pscustomobject]@{remote_host='198.51.100.10';remote_port=42053;dns_transport='UDP';query_name='a.probe.test.';query_type='A'}
            expected=[pscustomobject]@{response_code=0;answers=@('192.0.2.123')}
        }
    }
}

function New-DnsRecord($Plan,[string]$Phase,[string]$Result,[string]$RemoteIp,[bool]$NoResponse=$false) {
    $record=[pscustomobject][ordered]@{
        schema_version=1;run_id=[string]$Plan.worker_plan.run_id;scenario_id=[string]$Plan.worker_plan.scenario_id;attempt_id=[string]$Plan.worker_plan.attempt_id;flow_id=[string]$Plan.worker_plan.flow_id
        phase=$Phase;sequence=1;event=$(if($NoResponse){'DNS_NO_RESPONSE_OBSERVED'}else{'DNS_TRANSACTION_COMPLETED'});timestamp_utc='2030-01-01T00:00:00.000Z';monotonic_ms=10
        process_id=$(if($Phase-eq'client'){4242}else{5000});socket_id=7001;protocol_family='dns-classic';transport='UDP'
        local_ip=$(if($Phase-eq'client'){'192.0.2.20'}else{'198.51.100.10'});local_port=$(if($Phase-eq'client'){32000}else{42053})
        remote_ip=$RemoteIp;remote_port=$(if($Phase-eq'client'){42053}else{51000});payload_sha256=('a'*64);bytes=128;result=$Result
        dns_transport='UDP';query_id=1234;query_name='a.probe.test.';query_type=1;response_code=$(if($NoResponse){-1}else{0});answer_digest=('b'*64);truncated=$false;dnssec_status=$(if($NoResponse){'NOT_OBSERVED'}else{'NOT_REQUESTED'})
        no_response_observed=$NoResponse
    }
    return $record
}

function Write-ClientRecord($Plan,$Record) {
    Write-TestUtf8NoBom ([string]$Plan.client_jsonl_path) (($Record|ConvertTo-Json -Compress -Depth 20)+[Environment]::NewLine)
}

function New-ProcessResult([string]$ActualPath,[string]$ProbeStatus='PATH_OBTAINED',[int]$ExitCode=0,[bool]$TimedOut=$false,[string]$Stdout='PROTOCOL_WORKER_OK records=1',[string]$Stderr='') {
    return [pscustomobject]@{exit_code=$ExitCode;timed_out=$TimedOut;pid=4242;actual_path=$ActualPath;actual_path_probe_status=$ProbeStatus;actual_path_probe_attempts=1;actual_path_probe_elapsed_ms=1;stdout=$Stdout;stderr=$Stderr}
}

function New-RouteRecords($Plan,[string]$Route) {
    $line="2030-01-01T00:00:00Z python.exe (4242) -> $($Plan.remote_host):$($Plan.remote_port) via $Route"
    return @(ConvertFrom-ProxyBridgeTextLines -Lines @($line) -DefaultTimestampUtc ([datetime]'2030-01-01T00:00:00Z'))
}

try {
    $artifactPaths=@{
        PB_PROTOCOL_PYTHON_EXE=(Join-Path $temp 'runtime/python.exe')
        PB_PROTOCOL_WORKER_ENTRYPOINT=(Join-Path $temp 'worker/pb_protocol_worker.py')
        PB_PROTOCOL_WORKER_MANIFEST=(Join-Path $temp 'worker/manifest.json')
        PB_PROTOCOL_EVIDENCE_CONTRACT=(Join-Path $temp 'config/evidence.json')
        PB_PROTOCOL_CA_PEM=(Join-Path $temp 'config/ca.pem')
    }
    foreach($path in $artifactPaths.Values){$parent=Split-Path -Parent $path;if(-not(Test-Path $parent)){$null=New-Item -ItemType Directory -Path $parent -Force};Write-TestUtf8NoBom $path 'fixture'}
    Copy-Item -LiteralPath (Join-Path $root 'src/protocol_worker/plugins/manifest.json') -Destination $artifactPaths.PB_PROTOCOL_WORKER_MANIFEST -Force
    Copy-Item -LiteralPath (Join-Path $root 'config/protocol-evidence-contract.json') -Destination $artifactPaths.PB_PROTOCOL_EVIDENCE_CONTRACT -Force
    $environment=[System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($item in $artifactPaths.GetEnumerator()){$environment[$item.Key]=[string]$item.Value}
    foreach($pair in @(@('PB_SSH_HOST','192.0.2.40'),@('PB_SSH_USER','fixture-user'),@('PB_SSH_KEY','C:\fixture\key'),@('PB_SSH_KNOWN_HOSTS','C:\fixture\known_hosts'),@('PB_SSH_PORT','22'),@('PB_VPS_PROTOCOL_LOG','/var/log/proxybridge-testlab/protocols.jsonl'))){$environment[$pair[0]]=$pair[1]}
    foreach($pair in @(
        @('PB_EXPECTED_PROTOCOL_PYTHON_SHA256','PB_PROTOCOL_PYTHON_EXE'),@('PB_EXPECTED_PROTOCOL_WORKER_SHA256','PB_PROTOCOL_WORKER_ENTRYPOINT'),
        @('PB_EXPECTED_PROTOCOL_MANIFEST_SHA256','PB_PROTOCOL_WORKER_MANIFEST'),@('PB_EXPECTED_PROTOCOL_EVIDENCE_CONTRACT_SHA256','PB_PROTOCOL_EVIDENCE_CONTRACT'),@('PB_EXPECTED_PROTOCOL_CA_SHA256','PB_PROTOCOL_CA_PEM')
    )){$environment[$pair[0]]=(Get-FileHash -LiteralPath $environment[$pair[1]] -Algorithm SHA256).Hash.ToLowerInvariant()}

    $scenario=New-Scenario 'DIRECT'
    $cursorPlan=New-ProtocolLogCursorPlan -Environment $environment
    Assert-True ([string]$cursorPlan.process_plan.arguments[-1] -match '^sudo -n -u proxybridge-testlab sh -c ') 'protected protocol log cursor must run as the endpoint service identity'
    $plan=New-ProtocolExecutionPlan -Scenario $scenario -Environment $environment -RunId 'protocol-run' -Attempt 1 -EvidenceDirectory $temp -RuntimeContracts $runtimeContracts -OperationTimeoutCapMs 5000 -ProcessExitGraceMs 2000
    $collectionPlan=New-ProtocolServerCollectionPlan -Environment $environment -ExecutionPlan $plan -Cursor ([pscustomobject]@{inode='123';offset=0})
    Assert-True ([string]$collectionPlan.process_plan.arguments[-1] -match '^sudo -n -u proxybridge-testlab sh -c ') 'protected protocol evidence collection must run as the endpoint service identity'
    Assert-Equal 7000 $plan.process_timeout_ms 'protocol process budget includes operation plus exit grace'
    Assert-Equal 5 @($plan.artifacts).Count 'all protocol artifacts are verified'
    $clientRecord=New-DnsRecord $plan 'client' 'PASS' '198.51.100.10'
    Write-ClientRecord $plan $clientRecord
    $adapter=New-MockProcessAdapter -InvokeResults @((New-ProcessResult $artifactPaths.PB_PROTOCOL_PYTHON_EXE)) -ActualPath $artifactPaths.PB_PROTOCOL_PYTHON_EXE
    $clientResult=Invoke-ProtocolExecutionPlan -Plan $plan -RuntimeContracts $runtimeContracts -ProcessAdapter $adapter
    Assert-True $clientResult.prelaunch_verified 'protocol prelaunch exact hashes'
    Assert-Equal 5 $adapter.state.prelaunch_verify_count 'every artifact must be rechecked before launch'
    Assert-Equal 'PATH_OBTAINED' $clientResult.actual_path_probe_status 'observed Python path'

    $exitPlan=New-ProtocolExecutionPlan -Scenario $scenario -Environment $environment -RunId 'protocol-run' -Attempt 2 -EvidenceDirectory $temp -RuntimeContracts $runtimeContracts -OperationTimeoutCapMs 5000 -ProcessExitGraceMs 2000
    Write-ClientRecord $exitPlan (New-DnsRecord $exitPlan 'client' 'PASS' '198.51.100.10')
    $exitAdapter=New-MockProcessAdapter -InvokeResults @((New-ProcessResult '' 'PROCESS_EXITED')) -ActualPathProbeSequence @('__PROCESS_EXITED__')
    $exitResult=Invoke-ProtocolExecutionPlan -Plan $exitPlan -RuntimeContracts $runtimeContracts -ProcessAdapter $exitAdapter
    Assert-True (-not $exitResult.actual_path_required) 'short-lived verified worker may exit before actual path observation'
    Assert-Throws { Invoke-ProtocolExecutionPlan -Plan $plan -RuntimeContracts $runtimeContracts -ProcessAdapter (New-MockProcessAdapter -InvokeResults @((New-ProcessResult 'C:\wrong\python.exe')) -ActualPath 'C:\wrong\python.exe') } 'PROTOCOL_PATH_VERIFICATION_FAILED' 'wrong observed Python path must fail'
    Assert-Throws { Invoke-ProtocolExecutionPlan -Plan $plan -RuntimeContracts $runtimeContracts -ProcessAdapter (New-MockProcessAdapter -InvokeResults @((New-ProcessResult '' 'QUERY_TIMEOUT')) -ActualPathProbeSequence @('')) } 'PROTOCOL_PATH_QUERY_TIMEOUT' 'live path query timeout must fail'
    Assert-Throws { Invoke-ProtocolExecutionPlan -Plan $plan -RuntimeContracts $runtimeContracts -ProcessAdapter (New-MockProcessAdapter -InvokeResults @((New-ProcessResult $artifactPaths.PB_PROTOCOL_PYTHON_EXE)) -PrelaunchHashVerified $false) } 'PROTOCOL_PRELAUNCH_HASH_FAILED' 'artifact hash mismatch must prevent launch'

    $serverRecord=New-DnsRecord $plan 'server' 'PASS' '192.0.2.50'
    $context=[pscustomobject]@{server_capture_complete=$true;channel_capture_completed=$true;direct_egress_ip='192.0.2.50';proxy_egress_ip='198.51.100.50';start_time_utc=[datetime]'2029-12-31T23:59:00Z';end_time_utc=[datetime]'2030-01-01T00:01:00Z'}
    $directAssertion=Test-ProtocolScenarioAssertions -Scenario $scenario -ExecutionPlan $plan -ClientResult $clientResult -ServerRecords @($serverRecord) -ProxyBridgeRecords (New-RouteRecords $plan 'Direct') -EvidenceContext $context -RunMode mock
    Assert-Equal 'PASS' $directAssertion.outcome 'DIRECT protocol evidence must pass'
    $generatedMock=Invoke-MockProtocolScenario -Scenario $scenario -ExecutionPlan $plan -FixtureRoot (Join-Path $root 'tests/fixtures/mock')
    $generatedAssertion=Test-ProtocolScenarioAssertions -Scenario $scenario -ExecutionPlan $plan -ClientResult $generatedMock.client_result -ServerRecords @($generatedMock.server_records) -ProxyBridgeRecords @($generatedMock.proxybridge_records) -EvidenceContext $generatedMock.evidence_context -RunMode mock
    Assert-Equal 'PASS' $generatedAssertion.outcome 'deterministic DIRECT protocol fixture must pass'

    $blockScenario=New-Scenario 'BLOCK'
    $blockPlan=New-ProtocolExecutionPlan -Scenario $blockScenario -Environment $environment -RunId 'protocol-block-run' -Attempt 1 -EvidenceDirectory (Join-Path $temp 'block') -RuntimeContracts $runtimeContracts -OperationTimeoutCapMs 5000 -ProcessExitGraceMs 2000
    $blockClientRecord=New-DnsRecord $blockPlan 'client' 'PASS' '' $true
    $blockClientResult=$clientResult|Select-Object *
    $blockClientResult.records=@($blockClientRecord);$blockClientResult.raw_records=@($blockClientRecord);$blockClientResult.canonical_records=@($blockClientRecord)
    $blockAssertion=Test-ProtocolScenarioAssertions -Scenario $blockScenario -ExecutionPlan $blockPlan -ClientResult $blockClientResult -ServerRecords @() -ProxyBridgeRecords (New-RouteRecords $blockPlan 'Blocked') -EvidenceContext $context -RunMode mock
    Assert-Equal 'PASS' $blockAssertion.outcome 'BLOCK requires client no-response, zero server matches, and exact route'
    $leakAssertion=Test-ProtocolScenarioAssertions -Scenario $blockScenario -ExecutionPlan $blockPlan -ClientResult $blockClientResult -ServerRecords @((New-DnsRecord $blockPlan 'server' 'PASS' '192.0.2.50')) -ProxyBridgeRecords (New-RouteRecords $blockPlan 'Blocked') -EvidenceContext $context -RunMode mock
    Assert-Equal 'FAIL_PRODUCT' $leakAssertion.outcome 'BLOCK server leak is a product failure'

    $missingServer=Test-ProtocolScenarioAssertions -Scenario $scenario -ExecutionPlan $plan -ClientResult $clientResult -ServerRecords @() -ProxyBridgeRecords (New-RouteRecords $plan 'Direct') -EvidenceContext $context -RunMode mock
    Assert-Equal 'HOLD_AMBIGUOUS' $missingServer.outcome 'response path without server evidence must not pass'

    $proxyScenario=New-Scenario 'PROXY'
    $proxyPlan=New-ProtocolExecutionPlan -Scenario $proxyScenario -Environment $environment -RunId 'protocol-proxy-run' -Attempt 1 -EvidenceDirectory (Join-Path $temp 'proxy') -RuntimeContracts $runtimeContracts -OperationTimeoutCapMs 5000 -ProcessExitGraceMs 2000
    $proxyClientRecord=New-DnsRecord $proxyPlan 'client' 'PASS' '198.51.100.10'
    $proxyClientResult=$clientResult|Select-Object *;$proxyClientResult.records=@($proxyClientRecord);$proxyClientResult.raw_records=@($proxyClientRecord);$proxyClientResult.canonical_records=@($proxyClientRecord)
    $wrongEgress=Test-ProtocolScenarioAssertions -Scenario $proxyScenario -ExecutionPlan $proxyPlan -ClientResult $proxyClientResult -ServerRecords @((New-DnsRecord $proxyPlan 'server' 'PASS' '192.0.2.50')) -ProxyBridgeRecords (New-RouteRecords $proxyPlan 'Proxy SOCKS5') -EvidenceContext $context -RunMode mock
    Assert-Equal 'FAIL_PRODUCT' $wrongEgress.outcome 'PROXY direct-egress leak is a product failure'
}
finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}

'PASS: fail-closed protocol runner lifecycle and assertions'
