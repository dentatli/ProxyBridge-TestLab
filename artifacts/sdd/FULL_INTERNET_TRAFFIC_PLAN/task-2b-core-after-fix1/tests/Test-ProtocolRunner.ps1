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

function New-BrowserScenario {
    return [pscustomobject][ordered]@{
        scenario_id='canary-browser-download';executor_kind='protocol-worker';timeout_ms=5000
        requires=@('local_browser_runtime','server_browser_origin','protocol_worker','ipv4','tcp','process_basename_rules')
        client=[pscustomobject]@{expected_action='DIRECT';protocol='TCP'}
        protocol_worker=[pscustomobject]@{
            plugin_id='browser-worker';protocol_family='browser-web';transport='TCP';evidence_profile_id='browser-session'
            parameters=[pscustomobject]@{
                remote_host='198.51.100.10';remote_port=42080
                browser_executable='C:\manual\browser.exe';target_url='https://manual.invalid/';expected_content_sha256=('f'*64)
            }
            expected=[pscustomobject]@{}
        }
    }
}

function Get-TestUtf8Sha256([string]$Value) {
    $bytes=[System.Text.Encoding]::UTF8.GetBytes($Value)
    $hasher=[System.Security.Cryptography.SHA256]::Create()
    try{return ([System.BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}
    finally{$hasher.Dispose();[array]::Clear($bytes,0,$bytes.Length)}
}

function Copy-TestObject($Value) {
    return ($Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}

function Add-FixRoundOutcomeMismatch($Failures,[string]$Name,[string]$Expected,[string]$Actual) {
    if($Actual-ne$Expected){$Failures.Add("$Name expected=$Expected actual=$Actual")}
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
    $fixtureBrowser = Join-Path $temp 'browser/fixture-browser.exe'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $fixtureBrowser) -Force
    Write-TestUtf8NoBom $fixtureBrowser 'fixture-browser-image'
    $environment['PB_BROWSER_EXE']=[System.IO.Path]::GetFullPath($fixtureBrowser)
    $environment['PB_EXPECTED_BROWSER_SHA256']=(Get-FileHash -LiteralPath $fixtureBrowser -Algorithm SHA256).Hash.ToLowerInvariant()
    $environment['PB_BROWSER_APPLICATION_BASENAME']='fixture-browser.exe'
    $environment['PB_BROWSER_APPLICATION_FULLPATH']=[System.IO.Path]::GetFullPath($fixtureBrowser)
    $environment['PB_BROWSER_VERSION']='123.0.0.0'

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

    $browserScenario=New-BrowserScenario
    $browserEvidence=Join-Path $temp 'browser-runner-evidence'
    $browserPlan=New-ProtocolExecutionPlan -Scenario $browserScenario -Environment $environment -RunId 'browser-run' -Attempt 1 -EvidenceDirectory $browserEvidence -RuntimeContracts $runtimeContracts -OperationTimeoutCapMs 5000 -ProcessExitGraceMs 2000
    $expectedBrowserUrl='http://198.51.100.10:42080/browser-origin/v1/runs/browser-run/scenarios/canary-browser-download/attempts/attempt-1/flows/flow-1/page'
    $expectedDownloadBody="proxybridge-testlab-browser-download-v1`n{`"attempt_id`":`"attempt-1`",`"flow_id`":`"flow-1`",`"run_id`":`"browser-run`",`"scenario_id`":`"canary-browser-download`"}`n"
    Assert-Equal $artifactPaths.PB_PROTOCOL_PYTHON_EXE ([string]$browserPlan.process_plan.executable) 'Python protocol runtime remains the browser controller process'
    Assert-Equal 'fixture-browser.exe' ([string]$browserPlan.expected_process) 'browser route correlation must use the automatic browser basename'
    Assert-Equal $environment.PB_BROWSER_EXE ([string]$browserPlan.worker_plan.parameters.browser_executable) 'browser executable must come from automatic environment materialization'
    Assert-Equal $environment.PB_EXPECTED_BROWSER_SHA256 ([string]$browserPlan.worker_plan.parameters.expected_browser_sha256) 'browser image hash must come from automatic environment materialization'
    Assert-Equal $environment.PB_BROWSER_APPLICATION_FULLPATH ([string]$browserPlan.worker_plan.parameters.expected_browser_identity) 'browser identity must come from automatic environment materialization'
    Assert-Equal $environment.PB_BROWSER_VERSION ([string]$browserPlan.worker_plan.parameters.expected_browser_version) 'browser version must come from automatic environment materialization'
    Assert-Equal $expectedBrowserUrl ([string]$browserPlan.worker_plan.parameters.target_url) 'browser page URL must be identity-bound and controller-derived'
    Assert-Equal (Get-TestUtf8Sha256 $expectedDownloadBody) ([string]$browserPlan.worker_plan.parameters.expected_content_sha256) 'browser download hash must match browser_origin.py identity-bound bytes'
    Assert-Equal 200 ([int]$browserPlan.worker_plan.parameters.expected_response_status) 'browser expected response status'
    Assert-Equal 'http/1.1' ([string]$browserPlan.worker_plan.parameters.expected_negotiated_protocol) 'browser protocol claim must match the HTTP/1.1 origin'
    Assert-Equal ([System.IO.Path]::GetFullPath((Join-Path $browserEvidence 'browser-profile'))) ([string]$browserPlan.worker_plan.parameters.profile_dir) 'browser profile must be run-owned below scenario evidence'
    Assert-Equal ([System.IO.Path]::GetFullPath((Join-Path $browserEvidence 'browser-downloads'))) ([string]$browserPlan.worker_plan.parameters.download_dir) 'browser downloads must be run-owned below scenario evidence'
    Assert-True (-not (Test-Path -LiteralPath ([string]$browserPlan.worker_plan.parameters.profile_dir))) 'browser runner must leave profile creation to the browser worker'
    Assert-True (-not (Test-Path -LiteralPath ([string]$browserPlan.worker_plan.parameters.download_dir))) 'browser runner must leave download directory creation to the browser worker'
    Assert-SequenceEqual @() @($browserPlan.worker_plan.parameters.browser_arguments) 'browser UI/scenario cannot inject launch arguments'

    $browserMock=Invoke-MockProtocolScenario -Scenario $browserScenario -ExecutionPlan $browserPlan -FixtureRoot (Join-Path $root 'tests/fixtures/mock')
    $browserPass=Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $browserMock.client_result -ServerRecords @($browserMock.server_records) -ProxyBridgeRecords @($browserMock.proxybridge_records) -EvidenceContext $browserMock.evidence_context -RunMode mock
    Assert-Equal 'PASS' $browserPass.outcome 'truthful generated browser fixture must pass'
    Assert-Equal 1 @($browserMock.client_result.records).Count 'browser mock must emit exactly one canonical client completion'
    Assert-SequenceEqual @('page','download') @($browserMock.server_records | Sort-Object sequence | ForEach-Object resource) 'browser mock must emit exact page/download server resources'
    Assert-Equal 2 @($browserMock.proxybridge_records).Count 'browser mock must emit two response-connection route decisions'

    $browserCollectionPlan=New-ProtocolServerCollectionPlan -Environment $environment -ExecutionPlan $browserPlan -Cursor ([pscustomobject]@{inode='123';offset=0})
    $browserServerJson=(@($browserMock.server_records | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }) -join [Environment]::NewLine)+[Environment]::NewLine
    $browserCollectionAdapter=New-MockProcessAdapter -InvokeResults @((New-ProcessResult '' 'PROCESS_EXITED' 0 $false $browserServerJson ''))
    $browserCollection=Invoke-ProtocolServerCollectionPlan -Plan $browserCollectionPlan -ExecutionPlan $browserPlan -RuntimeContracts $runtimeContracts -ProcessAdapter $browserCollectionAdapter
    Assert-Equal 2 @($browserCollection.records).Count 'browser server collection must parse the asymmetric page/download evidence contract'

    $wrongContent=Copy-TestObject $browserMock
    ($wrongContent.server_records | Where-Object resource -eq 'download').content_sha256=('e'*64)
    Assert-Equal 'FAIL_PRODUCT' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $wrongContent.client_result -ServerRecords @($wrongContent.server_records) -ProxyBridgeRecords @($wrongContent.proxybridge_records) -EvidenceContext $wrongContent.evidence_context -RunMode mock).outcome 'complete wrong browser download content is a product failure'

    foreach($resource in @('page','download')) {
        $missingResource=Copy-TestObject $browserMock
        $missingResource.server_records=@($missingResource.server_records | Where-Object resource -ne $resource)
        Assert-Equal 'HOLD_AMBIGUOUS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $missingResource.client_result -ServerRecords @($missingResource.server_records) -ProxyBridgeRecords @($missingResource.proxybridge_records) -EvidenceContext $missingResource.evidence_context -RunMode mock).outcome "missing browser $resource evidence must hold"

        $duplicateResource=Copy-TestObject $browserMock
        $duplicate=Copy-TestObject @($duplicateResource.server_records | Where-Object resource -eq $resource)[0]
        $duplicateResource.server_records=@($duplicateResource.server_records)+@($duplicate)
        Assert-Equal 'CONTAMINATED' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $duplicateResource.client_result -ServerRecords @($duplicateResource.server_records) -ProxyBridgeRecords @($duplicateResource.proxybridge_records) -EvidenceContext $duplicateResource.evidence_context -RunMode mock).outcome "duplicate browser $resource evidence must be contamination"
    }

    $outsideTree=Copy-TestObject $browserMock
    foreach($route in @($outsideTree.proxybridge_records)){$route.pid=9999}
    Assert-Equal 'CONTAMINATED' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $outsideTree.client_result -ServerRecords @($outsideTree.server_records) -ProxyBridgeRecords @($outsideTree.proxybridge_records) -EvidenceContext $outsideTree.evidence_context -RunMode mock).outcome 'browser route from outside verified process tree must be contamination'

    $oneRoute=Copy-TestObject $browserMock
    $oneRoute.proxybridge_records=@($oneRoute.proxybridge_records | Select-Object -First 1)
    Assert-Equal 'HOLD_AMBIGUOUS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $oneRoute.client_result -ServerRecords @($oneRoute.server_records) -ProxyBridgeRecords @($oneRoute.proxybridge_records) -EvidenceContext $oneRoute.evidence_context -RunMode mock).outcome 'one browser route decision cannot prove two closed HTTP responses'

    $contradictoryRoute=Copy-TestObject $browserMock
    $wrongRoute=Copy-TestObject @($contradictoryRoute.proxybridge_records)[0]
    $wrongRoute.action='BLOCK'
    $contradictoryRoute.proxybridge_records=@($contradictoryRoute.proxybridge_records)+@($wrongRoute)
    Assert-Equal 'CONTAMINATED' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $contradictoryRoute.client_result -ServerRecords @($contradictoryRoute.server_records) -ProxyBridgeRecords @($contradictoryRoute.proxybridge_records) -EvidenceContext $contradictoryRoute.evidence_context -RunMode mock).outcome 'contradictory browser route action must be rejected above product classification'

    $wrongAction=Copy-TestObject $browserMock
    foreach($route in @($wrongAction.proxybridge_records)){$route.action='BLOCK'}
    Assert-Equal 'FAIL_PRODUCT' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $wrongAction.client_result -ServerRecords @($wrongAction.server_records) -ProxyBridgeRecords @($wrongAction.proxybridge_records) -EvidenceContext $wrongAction.evidence_context -RunMode mock).outcome 'externally complete wrong browser route action is a product failure'

    $uncleanTree=Copy-TestObject $browserMock
    $uncleanTree.client_result.records[0].process_tree_cleaned=$false
    Assert-Equal 'FAIL_HARNESS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $uncleanTree.client_result -ServerRecords @($uncleanTree.server_records) -ProxyBridgeRecords @($uncleanTree.proxybridge_records) -EvidenceContext $uncleanTree.evidence_context -RunMode mock).outcome 'unclean browser process tree is a harness failure'

    $malformedServer=Copy-TestObject $browserMock
    $malformedServer.server_records[0]=$malformedServer.server_records[0] | Select-Object * -ExcludeProperty negotiated_protocol
    Assert-Equal 'FAIL_HARNESS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $malformedServer.client_result -ServerRecords @($malformedServer.server_records) -ProxyBridgeRecords @($malformedServer.proxybridge_records) -EvidenceContext $malformedServer.evidence_context -RunMode mock).outcome 'malformed browser server evidence cannot pass'

    $fixRoundFailures=[System.Collections.Generic.List[string]]::new()
    $duplicateConnection=Copy-TestObject $browserMock
    $duplicateConnection.proxybridge_records[1].pid=$duplicateConnection.proxybridge_records[0].pid
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'duplicate same browser connection' 'HOLD_AMBIGUOUS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $duplicateConnection.client_result -ServerRecords @($duplicateConnection.server_records) -ProxyBridgeRecords @($duplicateConnection.proxybridge_records) -EvidenceContext $duplicateConnection.evidence_context -RunMode mock).outcome

    $wrongNavigationDigest=Copy-TestObject $browserMock
    $wrongNavigationDigest.client_result.records[0].navigation_url_digest=('0'*64)
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'wrong navigation URL digest' 'CONTAMINATED' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $wrongNavigationDigest.client_result -ServerRecords @($wrongNavigationDigest.server_records) -ProxyBridgeRecords @($wrongNavigationDigest.proxybridge_records) -EvidenceContext $wrongNavigationDigest.evidence_context -RunMode mock).outcome

    $wrongProfileId=Copy-TestObject $browserMock
    $wrongProfileId.client_result.records[0].profile_id=('0'*64)
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'wrong isolated profile identity' 'CONTAMINATED' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $wrongProfileId.client_result -ServerRecords @($wrongProfileId.server_records) -ProxyBridgeRecords @($wrongProfileId.proxybridge_records) -EvidenceContext $wrongProfileId.evidence_context -RunMode mock).outcome

    $wrongProbeStatus=Copy-TestObject $browserMock
    $wrongProbeStatus.client_result.records[0].actual_path_probe_status='PROCESS_EXITED'
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'wrong browser path probe status' 'FAIL_HARNESS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $wrongProbeStatus.client_result -ServerRecords @($wrongProbeStatus.server_records) -ProxyBridgeRecords @($wrongProbeStatus.proxybridge_records) -EvidenceContext $wrongProbeStatus.evidence_context -RunMode mock).outcome

    $stringProbeAttempts=Copy-TestObject $browserMock
    $stringProbeAttempts.client_result.records[0].actual_path_probe_attempts='1'
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'string browser path probe attempts' 'FAIL_HARNESS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $stringProbeAttempts.client_result -ServerRecords @($stringProbeAttempts.server_records) -ProxyBridgeRecords @($stringProbeAttempts.proxybridge_records) -EvidenceContext $stringProbeAttempts.evidence_context -RunMode mock).outcome

    $zeroProbeAttempts=Copy-TestObject $browserMock
    $zeroProbeAttempts.client_result.records[0].actual_path_probe_attempts=0
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'zero browser path probe attempts' 'FAIL_HARNESS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $zeroProbeAttempts.client_result -ServerRecords @($zeroProbeAttempts.server_records) -ProxyBridgeRecords @($zeroProbeAttempts.proxybridge_records) -EvidenceContext $zeroProbeAttempts.evidence_context -RunMode mock).outcome

    $stringProbeElapsed=Copy-TestObject $browserMock
    $stringProbeElapsed.client_result.records[0].actual_path_probe_elapsed_ms='0'
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'string browser path probe elapsed' 'FAIL_HARNESS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $stringProbeElapsed.client_result -ServerRecords @($stringProbeElapsed.server_records) -ProxyBridgeRecords @($stringProbeElapsed.proxybridge_records) -EvidenceContext $stringProbeElapsed.evidence_context -RunMode mock).outcome

    $negativeProbeElapsed=Copy-TestObject $browserMock
    $negativeProbeElapsed.client_result.records[0].actual_path_probe_elapsed_ms=-1
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'negative browser path probe elapsed' 'FAIL_HARNESS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $negativeProbeElapsed.client_result -ServerRecords @($negativeProbeElapsed.server_records) -ProxyBridgeRecords @($negativeProbeElapsed.proxybridge_records) -EvidenceContext $negativeProbeElapsed.evidence_context -RunMode mock).outcome

    $wrongSessionId=Copy-TestObject $browserMock
    foreach($record in @($wrongSessionId.server_records)){$record.browser_session_id=('0'*64)}
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'wrong identity-bound browser session' 'CONTAMINATED' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $wrongSessionId.client_result -ServerRecords @($wrongSessionId.server_records) -ProxyBridgeRecords @($wrongSessionId.proxybridge_records) -EvidenceContext $wrongSessionId.evidence_context -RunMode mock).outcome

    $stringImageVerified=Copy-TestObject $browserMock
    $stringImageVerified.client_result.records[0].browser_image_sha256_verified='false'
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'string false browser image verification' 'FAIL_HARNESS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $stringImageVerified.client_result -ServerRecords @($stringImageVerified.server_records) -ProxyBridgeRecords @($stringImageVerified.proxybridge_records) -EvidenceContext $stringImageVerified.evidence_context -RunMode mock).outcome

    $stringCleanup=Copy-TestObject $browserMock
    $stringCleanup.client_result.records[0].process_tree_cleaned='false'
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'string false browser cleanup' 'FAIL_HARNESS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $stringCleanup.client_result -ServerRecords @($stringCleanup.server_records) -ProxyBridgeRecords @($stringCleanup.proxybridge_records) -EvidenceContext $stringCleanup.evidence_context -RunMode mock).outcome

    $singleWrongAction=Copy-TestObject $browserMock
    $singleWrongAction.proxybridge_records=@($singleWrongAction.proxybridge_records|Select-Object -First 1)
    $singleWrongAction.proxybridge_records[0].action='BLOCK'
    Add-FixRoundOutcomeMismatch $fixRoundFailures 'one wrong-action browser connection' 'HOLD_AMBIGUOUS' (Test-ProtocolScenarioAssertions -Scenario $browserScenario -ExecutionPlan $browserPlan -ClientResult $singleWrongAction.client_result -ServerRecords @($singleWrongAction.server_records) -ProxyBridgeRecords @($singleWrongAction.proxybridge_records) -EvidenceContext $singleWrongAction.evidence_context -RunMode mock).outcome
    if($fixRoundFailures.Count-gt 0){throw "FIX ROUND 1 RED: $($fixRoundFailures -join '; ')"}

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
