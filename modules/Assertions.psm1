Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProxyBridgeEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'VpsEvidence.psm1')

function Get-AssertionContextValue {
    param($Context, [string]$Name, $Default)
    if ($null -ne $Context -and $null -ne $Context.PSObject.Properties[$Name]) { return $Context.$Name }
    return $Default
}

function Test-EvidenceIdentity {
    param(
        [object[]]$Records,
        [string]$RunId,
        [string]$ScenarioId,
        [datetime]$StartTimeUtc = [datetime]::MinValue,
        [datetime]$EndTimeUtc = [datetime]::MaxValue,
        [bool]$RequireIdentity = $false,
        [bool]$RequireTimestamp = $false
    )
    foreach ($record in @($Records)) {
        foreach ($identity in @(@('run_id', $RunId), @('test_id', $ScenarioId))) {
            $property = $record.PSObject.Properties[[string]$identity[0]]
            if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                if ($RequireIdentity) { return $false }
            }
            elseif ([string]$property.Value -ne [string]$identity[1]) { return $false }
        }
        $timestampProperty = $record.PSObject.Properties['timestamp_utc']
        if ($null -eq $timestampProperty -or [string]::IsNullOrWhiteSpace([string]$timestampProperty.Value)) {
            if ($RequireTimestamp) { return $false }
            continue
        }
        $observed = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse([string]$timestampProperty.Value, [ref]$observed)) { return $false }
        $observedUtc = $observed.UtcDateTime
        if ($StartTimeUtc -ne [datetime]::MinValue -and $observedUtc -lt $StartTimeUtc.ToUniversalTime().AddSeconds(-2)) { return $false }
        if ($EndTimeUtc -ne [datetime]::MaxValue -and $observedUtc -gt $EndTimeUtc.ToUniversalTime().AddSeconds(2)) { return $false }
    }
    return $true
}

function Test-ScenarioAssertions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)]$ClientPlan,
        [Parameter(Mandatory)]$ClientResult,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$VpsRecords,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ProxyBridgeRecords,
        $EvidenceContext,
        [ValidateSet('mock', 'real')][string]$RunMode = 'mock'
    )

    $productErrors=[System.Collections.Generic.List[string]]::new()
    $harnessErrors=[System.Collections.Generic.List[string]]::new()
    $missingEvidence=[System.Collections.Generic.List[string]]::new()
    $contamination=[System.Collections.Generic.List[string]]::new()
    $externalProofs=[System.Collections.Generic.List[bool]]::new()
    $routeEvidenceRequired=$false;$internalRouteUsed=$false
    $forceInternalRoute=$false
    if($null -ne $Scenario.PSObject.Properties['parameters'] -and $null -ne $Scenario.parameters.PSObject.Properties['require_internal_route']){$forceInternalRoute=[bool]$Scenario.parameters.require_internal_route}
    $forceProxyConfigEvidence=$false
    if($null -ne $Scenario.PSObject.Properties['parameters'] -and $null -ne $Scenario.parameters.PSObject.Properties['require_proxy_config_evidence']){$forceProxyConfigEvidence=[bool]$Scenario.parameters.require_proxy_config_evidence}
    if([bool]$ClientResult.timed_out){$harnessErrors.Add('client timeout')}

    $startTime=Get-AssertionContextValue $EvidenceContext 'start_time_utc' ([datetime]::MinValue)
    $endTime=Get-AssertionContextValue $EvidenceContext 'end_time_utc' ([datetime]::MaxValue)

    $clientRecords=@()
    if($null -ne $ClientResult.PSObject.Properties['canonical_records']){$clientRecords=@($ClientResult.canonical_records)}
    elseif($null -ne $ClientResult.PSObject.Properties['records']){$clientRecords=@($ClientResult.records)}
    $flows=@($clientRecords|Where-Object{[string]$_.record_kind -eq 'flow'}|Sort-Object{[int]$_.flow_index})
    $heldRechecks=@($clientRecords|Where-Object{[string]$_.record_kind -eq 'held_recheck'})
    $expectedFlows=@($ClientPlan.flows|Sort-Object{[int]$_.flow_index})
    if($flows.Count -ne $expectedFlows.Count){$harnessErrors.Add("flow count actual=$($flows.Count) expected=$($expectedFlows.Count)")}
    $issue206ContractInvalid=$false
    if([string]$Scenario.client.mode -eq 'issue206'){
        if($flows.Count -ne $expectedFlows.Count){$issue206ContractInvalid=$true}
        if($flows.Count -ge 2){
            if([string]$flows[0].phase -ne 'first_flow' -or [string]$flows[1].phase -ne 'second_flow'){$harnessErrors.Add('issue206 both phases were not reached');$issue206ContractInvalid=$true}
            if([int]$flows[0].wsa_error -eq 10048 -or [int]$flows[1].wsa_error -eq 10048){$harnessErrors.Add('issue206 exact-port reuse failed with WSAEADDRINUSE 10048');$issue206ContractInvalid=$true}
            if([string]$flows[0].actual_local_ip -ne [string]$flows[1].actual_local_ip -or [int]$flows[0].actual_local_port -ne [int]$flows[1].actual_local_port){$harnessErrors.Add('issue206 exact same local tuple was not created');$issue206ContractInvalid=$true}
        }elseif($flows.Count -gt 0){$harnessErrors.Add('issue206 both phases were not reached');$issue206ContractInvalid=$true}
    }
    $streamCount=1
    if($null -ne $Scenario.PSObject.Properties['parameters'] -and $null -ne $Scenario.parameters.PSObject.Properties['stream_count']){$streamCount=[int]$Scenario.parameters.stream_count}
    $lateResponseReuse=$streamCount -eq 2 -and $null -ne $Scenario.parameters.PSObject.Properties['endpoint_behavior'] -and [string]$Scenario.parameters.endpoint_behavior -eq 'late-response'
    if($streamCount -gt 1 -and $flows.Count -gt 0){
        for($streamIndex=0;$streamIndex -lt $flows.Count;$streamIndex++){
            if([string]$flows[$streamIndex].phase -ne "stream_$($streamIndex + 1)"){$harnessErrors.Add('stream phases are incomplete or out of order');break}
        }
        foreach($streamFlow in @($flows|Select-Object -Skip 1)){
            if([string]$streamFlow.actual_local_ip -ne [string]$flows[0].actual_local_ip -or [int]$streamFlow.actual_local_port -ne [int]$flows[0].actual_local_port){$harnessErrors.Add('stream did not preserve one local socket tuple');break}
        }
        if(@($flows|Where-Object{$null -eq $_.PSObject.Properties['socket_id'] -or [long]$_.socket_id -lt 1}).Count -gt 0){$harnessErrors.Add('stream socket identity evidence is unavailable')}
        elseif($lateResponseReuse -and @($flows.socket_id|Sort-Object -Unique).Count -ne $flows.Count){$harnessErrors.Add('UDP late-response reuse did not create a new socket generation')}
        elseif(-not $lateResponseReuse -and @($flows.socket_id|Sort-Object -Unique).Count -ne 1){$harnessErrors.Add('stream did not preserve one socket identity')}
    }
    $parallelCount=$(if($null -ne $ClientPlan.PSObject.Properties['parallel_count']){[int]$ClientPlan.parallel_count}else{1})
    if($parallelCount -gt 1 -and $flows.Count -gt 0){
        $parallelSocketIds=[System.Collections.Generic.HashSet[long]]::new()
        foreach($parallelFlow in $flows){
            if($null -eq $parallelFlow.PSObject.Properties['socket_id'] -or [long]$parallelFlow.socket_id -lt 1){$harnessErrors.Add('parallel socket identity evidence is unavailable');continue}
            if(-not $parallelSocketIds.Add([long]$parallelFlow.socket_id)){$harnessErrors.Add('parallel flows did not use distinct socket identities')}
        }
    }
    if($parallelCount -gt 1 -and $flows.Count -gt 0){
        $parallelTuples=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $parallelHashes=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        for($parallelIndex=0;$parallelIndex -lt $flows.Count;$parallelIndex++){
            $parallelFlow=$flows[$parallelIndex]
            if([string]$parallelFlow.phase -ne "parallel_$($parallelIndex + 1)"){$harnessErrors.Add('parallel phases are incomplete or out of order');break}
            if([int]$parallelFlow.actual_local_port -lt 1 -or [string]::IsNullOrWhiteSpace([string]$parallelFlow.actual_local_ip)){$harnessErrors.Add('parallel flow local tuple is unavailable');continue}
            if(-not $parallelTuples.Add("$([string]$parallelFlow.actual_local_ip)|$([int]$parallelFlow.actual_local_port)")){$harnessErrors.Add('parallel flows did not use unique local socket tuples')}
            if(-not $parallelHashes.Add([string]$parallelFlow.payload_sha256)){$harnessErrors.Add('parallel flows did not use unique payload identities')}
        }
    }
    $processCount=$(if($null -ne $ClientPlan.PSObject.Properties['process_count']){[int]$ClientPlan.process_count}else{1})
    if($processCount -gt 1 -and $flows.Count -gt 0){
        $processIds=[System.Collections.Generic.HashSet[int]]::new()
        for($processIndex=0;$processIndex -lt $flows.Count;$processIndex++){
            $processFlow=$flows[$processIndex]
            if([string]$processFlow.phase -ne "process_$($processIndex + 1)"){$harnessErrors.Add('cross-process phases are incomplete or out of order');break}
            if($null -eq $processFlow.PSObject.Properties['process_id'] -or [int]$processFlow.process_id -lt 1){$harnessErrors.Add('cross-process PID evidence is unavailable');continue}
            if(-not $processIds.Add([int]$processFlow.process_id)){$harnessErrors.Add('cross-process flows did not use distinct process IDs')}
        }
    }
    $reconnectCount=$(if($null -ne $ClientPlan.PSObject.Properties['reconnect_count']){[int]$ClientPlan.reconnect_count}else{1})
    if($reconnectCount -gt 1 -and $flows.Count -gt 0){
        $reconnectTuples=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $reconnectSocketIds=[System.Collections.Generic.HashSet[long]]::new()
        for($reconnectIndex=0;$reconnectIndex -lt $flows.Count;$reconnectIndex++){
            $reconnectFlow=$flows[$reconnectIndex]
            if([string]$reconnectFlow.phase -ne "reconnect_$($reconnectIndex + 1)"){$harnessErrors.Add('UDP reconnect phases are incomplete or out of order');break}
            if(-not $reconnectTuples.Add("$([string]$reconnectFlow.actual_local_ip)|$([int]$reconnectFlow.actual_local_port)")){$harnessErrors.Add('UDP reconnect did not create a fresh local socket tuple')}
            if($null -eq $reconnectFlow.PSObject.Properties['socket_id'] -or [long]$reconnectFlow.socket_id -lt 1){$harnessErrors.Add('UDP reconnect socket identity evidence is unavailable')}
            elseif(-not $reconnectSocketIds.Add([long]$reconnectFlow.socket_id)){$harnessErrors.Add('UDP reconnect did not create a fresh socket identity')}
            if($reconnectIndex -gt 0 -and [int]$ClientPlan.reconnect_wait_ms -gt 0){
                $prior=[datetimeoffset]::Parse([string]$flows[$reconnectIndex - 1].timestamp_utc)
                $current=[datetimeoffset]::Parse([string]$reconnectFlow.timestamp_utc)
                if(($current-$prior).TotalMilliseconds -lt ([int]$ClientPlan.reconnect_wait_ms - 50)){$harnessErrors.Add('UDP reconnect idle interval was not observed')}
            }
        }
    }
    if([string]$Scenario.client.mode -eq 'issue209' -and $heldRechecks.Count -ne 1){$harnessErrors.Add("issue209 held_recheck count actual=$($heldRechecks.Count) expected=1")}
    elseif([string]$Scenario.client.mode -ne 'issue209' -and $heldRechecks.Count -gt 0){$harnessErrors.Add('unexpected held_recheck record')}
    $clientIdentityValid=Test-EvidenceIdentity $clientRecords ([string]$ClientPlan.run_id) ([string]$Scenario.scenario_id) $startTime $endTime $true $true
    $vpsIdentityValid=Test-EvidenceIdentity $VpsRecords ([string]$ClientPlan.run_id) ([string]$Scenario.scenario_id) $startTime $endTime $true $true
    if(-not $clientIdentityValid){$contamination.Add('client evidence identity or timestamp mismatch')}
    if(-not $vpsIdentityValid){$contamination.Add('VPS evidence identity or timestamp mismatch')}
    if(-not (Test-EvidenceIdentity $ProxyBridgeRecords ([string]$ClientPlan.run_id) ([string]$Scenario.scenario_id) $startTime $endTime $false $false)){$contamination.Add('ProxyBridge evidence identity or timestamp mismatch')}
    foreach($vpsRecord in @($VpsRecords)){
        $matchingClient=@($clientRecords|Where-Object{[string]$_.payload_sha256 -eq [string]$vpsRecord.sha256})|Select-Object -First 1
        if($null -eq $matchingClient){continue}
        foreach($field in @('phase','sequence','family','protocol')){
            if($null -eq $vpsRecord.PSObject.Properties[$field] -or -not [string]::Equals([string]$vpsRecord.$field,[string]$matchingClient.$field,[System.StringComparison]::OrdinalIgnoreCase)){
                $contamination.Add("VPS evidence $field does not match the client flow")
            }
        }
    }

    $vpsComplete=[bool](Get-AssertionContextValue $EvidenceContext 'vps_capture_complete' $false)
    $vpsCompleteShas=@((Get-AssertionContextValue $EvidenceContext 'vps_capture_complete_shas' @())|ForEach-Object{([string]$_).ToLowerInvariant()})
    $legacyChannel=[bool](Get-AssertionContextValue $EvidenceContext 'proxybridge_capture_complete' $false)
    $channelCaptureCompleted=[bool](Get-AssertionContextValue $EvidenceContext 'channel_capture_completed' $legacyChannel)
    $recordsFound=[bool](Get-AssertionContextValue $EvidenceContext 'records_found' (@($ProxyBridgeRecords).Count -gt 0))
    if(@($ProxyBridgeRecords).Count -gt 0){$recordsFound=$true}
    $directEgress=[string](Get-AssertionContextValue $EvidenceContext 'direct_egress_ip' '')
    $proxyEgress=[string](Get-AssertionContextValue $EvidenceContext 'proxy_egress_ip' '')
    $expectedProcess=[string](Get-AssertionContextValue $EvidenceContext 'expected_process' '')
    $expectedPid=$(if($null -ne $ClientResult.PSObject.Properties['pid']){[int]$ClientResult.pid}else{0})

    foreach($record in $clientRecords){
        $label=$(if([string]$record.record_kind -eq 'held_recheck'){'held_recheck'}else{"flow $([int]$record.flow_index)"})
        $expected=$(if([string]$record.record_kind -eq 'held_recheck'){@($expectedFlows|Where-Object{[int]$_.flow_index -eq 0})|Select-Object -First 1}else{@($expectedFlows|Where-Object{[int]$_.flow_index -eq [int]$record.flow_index})|Select-Object -First 1})
        if($null -eq $expected){$harnessErrors.Add("$label has no plan expectation");continue}
        $missingClientField=$false
        foreach($required in @('protocol','expected_action','expected_outcome','actual_local_ip','actual_local_port','remote_ip','remote_port','actual_remote_ip','actual_remote_port','payload_sha256','response_sha256','no_response','client_pass')){if($null -eq $record.PSObject.Properties[$required]){$harnessErrors.Add("$label missing $required");$missingClientField=$true}}
        if($missingClientField){continue}
        if([string]$record.payload_sha256 -notmatch '^[A-Fa-f0-9]{64}$'){$harnessErrors.Add("$label payload SHA invalid");continue}
        if(-not [string]::Equals([string]$record.protocol,[string]$expected.protocol,[System.StringComparison]::OrdinalIgnoreCase)){$harnessErrors.Add("$label protocol does not match plan")}
        if([string]$record.expected_action -ne [string]$expected.expected_action){$harnessErrors.Add("$label expected action does not match plan")}
        if([string]$record.expected_outcome -ne [string]$expected.expected_outcome){$harnessErrors.Add("$label expectation does not match plan")}
        if($null -ne $expected.PSObject.Properties['remote_host']){
            if($null -eq $record.PSObject.Properties['remote_host'] -or -not [string]::Equals([string]$record.remote_host,[string]$expected.remote_host,[System.StringComparison]::OrdinalIgnoreCase)){$harnessErrors.Add("$label requested domain does not match plan")}
        }
        if($null -ne $expected.PSObject.Properties['close_mode'] -and [string]$record.close_mode -ne [string]$expected.close_mode){$harnessErrors.Add("$label close mode does not match plan")}
        if($null -ne $expected.PSObject.Properties['endpoint_behavior']){
            if($null -eq $record.PSObject.Properties['endpoint_behavior'] -or [string]$record.endpoint_behavior -ne [string]$expected.endpoint_behavior){$harnessErrors.Add("$label endpoint behavior does not match plan")}
        }
        if($null -ne $expected.PSObject.Properties['expected_response_count']){
            if($null -eq $record.PSObject.Properties['response_count']){$harnessErrors.Add("$label response count evidence missing")}
            elseif([int]$record.response_count -ne [int]$expected.expected_response_count){$productErrors.Add("$label response count actual=$([int]$record.response_count) expected=$([int]$expected.expected_response_count)")}
        }
        if($null -ne $expected.PSObject.Properties['expected_response_order']){
            if($null -eq $record.PSObject.Properties['response_order']){$harnessErrors.Add("$label response order evidence missing")}
            elseif([int]$record.response_order -ne [int]$expected.expected_response_order){$productErrors.Add("$label response order actual=$([int]$record.response_order) expected=$([int]$expected.expected_response_order)")}
        }
        if($null -ne $expected.PSObject.Properties['expected_min_timing_ms'] -and [long]$record.timing_ms -lt [long]$expected.expected_min_timing_ms){$productErrors.Add("$label timing actual=$([long]$record.timing_ms)ms expected-at-least=$([long]$expected.expected_min_timing_ms)ms")}
        if($null -ne $expected.PSObject.Properties['payload_size']){
            $expectedPayloadSize=[long]$expected.payload_size
            if([long]$record.bytes_sent -ne $expectedPayloadSize){$productErrors.Add("$label sent payload bytes actual=$([long]$record.bytes_sent) expected=$expectedPayloadSize")}
            if([string]$expected.expected_outcome -eq 'echo' -and [long]$record.bytes_received -ne $expectedPayloadSize){$productErrors.Add("$label received payload bytes actual=$([long]$record.bytes_received) expected=$expectedPayloadSize")}
        }
        if($null -ne $expected.PSObject.Properties['tcp_peer_policy'] -and [string]$expected.protocol -eq 'TCP' -and [string]$record.tcp_peer_policy -ne [string]$expected.tcp_peer_policy){$harnessErrors.Add("$label TCP peer policy does not match plan")}
        if([string]$record.remote_ip -ne [string]$expected.remote_ip -or [int]$record.remote_port -ne [int]$expected.remote_port){$harnessErrors.Add("$label requested destination does not match plan")}
        if([string]$expected.expected_outcome -eq 'echo'){
            if([string]$record.actual_remote_ip -ne [string]$expected.remote_ip -or [int]$record.actual_remote_port -ne [int]$expected.remote_port){$productErrors.Add("$label wrong response source")}
            if([string]$record.payload_sha256 -ne [string]$record.response_sha256 -or [bool]$record.no_response){$productErrors.Add("$label echo mismatch")}
        }elseif(-not [bool]$record.no_response -or -not [string]::IsNullOrEmpty([string]$record.response_sha256)){$productErrors.Add("$label unexpected response")}
        if(-not [bool]$record.client_pass){
            $actualResult=$(if($null -ne $record.PSObject.Properties['actual_result']){[string]$record.actual_result}else{'failed'})
            $productErrors.Add("$label client result failed: $actualResult")
        }

        $flowPid=$(if($null -ne $record.PSObject.Properties['process_id']){[int]$record.process_id}else{$expectedPid})
        $sameDestination=@(Find-ProxyBridgeFlowEvidence -Records $ProxyBridgeRecords -Process $expectedProcess -Pid $flowPid -DestinationIp ([string]$expected.remote_ip) -DestinationPort ([int]$expected.remote_port) -StartTimeUtc $startTime -EndTimeUtc $endTime)
        $expectedRoute=@($sameDestination|Where-Object{[string]$_.action -eq [string]$expected.expected_action})
        $contradictoryRoute=@($sameDestination|Where-Object{-not [string]::IsNullOrWhiteSpace([string]$_.action) -and [string]$_.action -ne [string]$expected.expected_action})
        $wrongConfig=$false;$exactConfigObserved=(-not $forceProxyConfigEvidence)
        if($contradictoryRoute.Count -gt 0){$productErrors.Add("$label wrong ProxyBridge action")}
        if($expectedRoute.Count -gt 0 -and $null -ne $expected.PSObject.Properties['expected_proxy_config_id']){
            foreach($routeRecord in $expectedRoute){
                if($null -ne $routeRecord.PSObject.Properties['proxy_config_id']){
                    if([int]$routeRecord.proxy_config_id -ne [int]$expected.expected_proxy_config_id){$wrongConfig=$true;$productErrors.Add("$label wrong proxy config")}
                    else{$exactConfigObserved=$true}
                }
            }
            if($forceProxyConfigEvidence -and -not $exactConfigObserved){$missingEvidence.Add("$label exact proxy config decision")}
        }
        $internalRouteValid=($expectedRoute.Count -gt 0 -and $contradictoryRoute.Count -eq 0 -and -not $wrongConfig -and $exactConfigObserved)
        if($forceInternalRoute){
            $routeEvidenceRequired=$true
            if(-not $internalRouteValid){$missingEvidence.Add("$label exact internal route decision")}
            else{$internalRouteUsed=$true}
        }

        $sha=([string]$record.payload_sha256).ToLowerInvariant();$shaCaptureComplete=$vpsComplete
        if($vpsCompleteShas.Count -gt 0){$shaCaptureComplete=$vpsCompleteShas -contains $sha}
        $expectedReceived=$(if($null -ne $expected.PSObject.Properties['expected_vps_received']){[int]$expected.expected_vps_received}elseif([string]$expected.expected_action -eq 'BLOCK'){0}else{1})
        $expectedEchoed=$(if($null -ne $expected.PSObject.Properties['expected_vps_echoed']){[int]$expected.expected_vps_echoed}elseif([string]$expected.expected_outcome -eq 'echo' -and [string]$expected.expected_action -ne 'BLOCK'){1}else{0})
        $vpsResult=Test-VpsPayloadEvidence -Records $VpsRecords -Sha256 $sha -Protocol ([string]$expected.protocol) -ExpectedReceived $expectedReceived -ExpectedEchoed $expectedEchoed -ExpectedDestinationPort ([int]$expected.remote_port)
        if($shaCaptureComplete -and $null -ne $expected.PSObject.Properties['close_mode']){
            $closeEvent=$(if([string]$expected.close_mode -eq 'abortive'){'RESET_BY_PEER'}else{'CLOSED'})
            if(@($vpsResult.matches|Where-Object{[string]$_.event -eq $closeEvent}).Count -eq 0){$missingEvidence.Add("$label endpoint $closeEvent evidence")}
        }
        if($shaCaptureComplete -and $null -ne $expected.PSObject.Properties['endpoint_behavior']){
            $behaviorEvent=switch([string]$expected.endpoint_behavior){'server-close'{'SERVER_CLOSED'}'reset'{'RESET'}default{''}}
            if(-not [string]::IsNullOrWhiteSpace($behaviorEvent) -and @($vpsResult.matches|Where-Object{[string]$_.event -eq $behaviorEvent}).Count -eq 0){$missingEvidence.Add("$label endpoint $behaviorEvent evidence")}
        }
        $externalRouteProof=$false
        if([string]$expected.expected_action -eq 'BLOCK'){
            $leaks=@($vpsResult.matches|Where-Object{[string]$_.event -in @('MESSAGE_RECEIVED','RECEIVED','ECHOED')})
            if($leaks.Count -gt 0){$productErrors.Add("$label block leak")}
            elseif(-not $shaCaptureComplete){$missingEvidence.Add("$label complete VPS capture")}
            else{$externalRouteProof=$true}
        }else{
            if(-not $shaCaptureComplete){$missingEvidence.Add("$label complete VPS capture")}
            if($expectedReceived -eq 0){
                if(-not $vpsResult.passed){foreach($error in @($vpsResult.errors)){$productErrors.Add("$label $error")}}
                elseif($internalRouteValid){$internalRouteUsed=$true}
                elseif($shaCaptureComplete){$missingEvidence.Add("$label route proof");$routeEvidenceRequired=$true}
            }
            elseif($vpsResult.received -eq 0){$missingEvidence.Add("$label VPS payload evidence")}
            elseif(-not $vpsResult.passed){foreach($error in @($vpsResult.errors)){$productErrors.Add("$label $error")}}
            else{
                $receivedEvent=$(if([string]$expected.protocol -eq 'UDP'){'RECEIVED'}else{'MESSAGE_RECEIVED'})
                $sources=@($vpsResult.matches|Where-Object{[string]$_.event -eq $receivedEvent}|Select-Object -ExpandProperty remote_ip -Unique)
                $sourceAddress=$null
                if($sources.Count -ne 1 -or -not [System.Net.IPAddress]::TryParse([string]$sources[0],[ref]$sourceAddress)){$missingEvidence.Add("$label VPS source evidence")}
                elseif([string]$expected.expected_action -eq 'DIRECT'){
                    if([string]::IsNullOrWhiteSpace($directEgress)){$routeEvidenceRequired=$true}
                    elseif([string]$sources[0] -ne $directEgress){$productErrors.Add("$label wrong direct egress")}
                    else{$externalRouteProof=$true}
                }elseif([string]$expected.expected_action -eq 'PROXY'){
                    if(-not [string]::IsNullOrWhiteSpace($proxyEgress) -and [string]$sources[0] -ne $proxyEgress){$productErrors.Add("$label wrong proxy egress")}
                    elseif(-not [string]::IsNullOrWhiteSpace($directEgress) -and [string]$sources[0] -eq $directEgress){$routeEvidenceRequired=$true}
                    elseif(-not [string]::IsNullOrWhiteSpace($directEgress) -or -not [string]::IsNullOrWhiteSpace($proxyEgress)){$externalRouteProof=$true}
                    else{$routeEvidenceRequired=$true}
                }
            }
            if($shaCaptureComplete -and -not $externalRouteProof -and $internalRouteValid){$internalRouteUsed=$true}
            elseif($shaCaptureComplete -and -not $externalRouteProof -and $productErrors.Count -eq 0){$missingEvidence.Add("$label route proof");$routeEvidenceRequired=$true}
        }
        $externalProofs.Add($externalRouteProof)
    }

    if($expectedFlows.Count -eq 2 -and $flows.Count -eq 2 -and $null -ne $expectedFlows[0].PSObject.Properties['endpoint_behavior'] -and [string]$expectedFlows[0].endpoint_behavior -eq 'out-of-order'){
        $expectedEchoOrder=@([string]$flows[1].payload_sha256,[string]$flows[0].payload_sha256)
        $observedEchoOrder=@($VpsRecords|Where-Object{[string]$_.event -eq 'ECHOED' -and @($expectedEchoOrder) -contains [string]$_.sha256}|Sort-Object{[long]$_.monotonic_ns}|ForEach-Object{[string]$_.sha256})
        if($observedEchoOrder.Count -ne 2){$missingEvidence.Add('UDP out-of-order endpoint echo sequence')}
        elseif($observedEchoOrder[0] -ne $expectedEchoOrder[0] -or $observedEchoOrder[1] -ne $expectedEchoOrder[1]){$productErrors.Add('UDP endpoint did not emit responses in reversed order')}
    }

    if($expectedFlows.Count -ge 2 -and $flows.Count -ge 2){
        if([string]$Scenario.client.mode -eq 'issue209'){
            if([int]$flows[0].actual_local_port -ne [int]$flows[1].actual_local_port){$productErrors.Add('issue209 same numeric local port reuse')}
            if([string]$flows[0].protocol -eq [string]$flows[1].protocol){$harnessErrors.Add('issue209 opposite protocol was not exercised')}
            if($heldRechecks.Count -eq 1){$held=$heldRechecks[0];if([int]$held.actual_local_port -ne [int]$flows[0].actual_local_port){$harnessErrors.Add('issue209 held_recheck local port mismatch')};if([int]$held.flow_index -ne 0){$harnessErrors.Add('issue209 held_recheck does not reference first flow')}}
        }
    }

    if($issue206ContractInvalid){$productErrors.Clear()}
    if(-not [bool]$ClientResult.timed_out -and [int]$ClientResult.exit_code -ne 0 -and $productErrors.Count -eq 0){$harnessErrors.Add("client exit code $($ClientResult.exit_code)")}

    $outcome='PASS'
    if($contamination.Count -gt 0){$outcome='CONTAMINATED'}elseif($harnessErrors.Count -gt 0){$outcome='FAIL_HARNESS'}elseif($productErrors.Count -gt 0){$outcome='FAIL_PRODUCT'}elseif($missingEvidence.Count -gt 0){$outcome='HOLD_AMBIGUOUS'}
    $externalComplete=($externalProofs.Count -gt 0 -and @($externalProofs|Where-Object{-not $_}).Count -eq 0)
    $evidenceBasis=$(if($outcome -eq 'HOLD_AMBIGUOUS'){'HOLD_MISSING_ROUTE_PROOF'}elseif($outcome -eq 'PASS' -and $externalComplete){'CLIENT+VPS+DIRECT_BASELINE'}elseif($outcome -eq 'PASS' -and $internalRouteUsed){'CLIENT+VPS+PROXYBRIDGE'}elseif($outcome -eq 'FAIL_PRODUCT'){'CONTRADICTORY_EVIDENCE'}else{'CLIENT+VPS'})
    $allErrors=@($productErrors.ToArray())+@($harnessErrors.ToArray())+@($missingEvidence.ToArray())+@($contamination.ToArray())
    $completeness=@(
        [pscustomobject][ordered]@{channel='client_plan';mandatory=$true;requested=$true;captured=($expectedFlows.Count -gt 0);parsed=($expectedFlows.Count -gt 0);validated=($expectedFlows.Count -gt 0)},
        [pscustomobject][ordered]@{channel='client_jsonl';mandatory=$true;requested=$true;captured=($clientRecords.Count -gt 0);parsed=($clientRecords.Count -gt 0);validated=($clientIdentityValid -and $flows.Count -eq $expectedFlows.Count)},
        [pscustomobject][ordered]@{channel='endpoint_query';mandatory=$true;requested=$true;captured=$vpsComplete;parsed=$vpsComplete;validated=($vpsComplete -and $vpsIdentityValid)},
        [pscustomobject][ordered]@{channel='endpoint_jsonl';mandatory=$true;requested=$true;captured=$vpsComplete;parsed=$vpsComplete;validated=($vpsComplete -and $vpsIdentityValid)},
        [pscustomobject][ordered]@{channel='proxybridge_records';mandatory=$routeEvidenceRequired;requested=$channelCaptureCompleted;captured=$recordsFound;parsed=$channelCaptureCompleted;validated=(-not $routeEvidenceRequired -or $recordsFound)},
        [pscustomobject][ordered]@{channel='assertion_result';mandatory=$true;requested=$true;captured=$true;parsed=$true;validated=($contamination.Count -eq 0 -and $harnessErrors.Count -eq 0)}
    )
    return [pscustomobject][ordered]@{
        passed=($outcome -eq 'PASS');outcome=$outcome
        product_errors=@($productErrors|Sort-Object -Unique);harness_errors=@($harnessErrors|Sort-Object -Unique)
        missing_evidence=@($missingEvidence|Sort-Object -Unique);contamination=@($contamination|Sort-Object -Unique);errors=@($allErrors|Sort-Object -Unique)
        channel_capture_completed=$channelCaptureCompleted;records_found=$recordsFound;route_evidence_required=$routeEvidenceRequired
        external_route_proof_complete=$externalComplete;evidence_basis=$evidenceBasis;run_mode=$RunMode
        evidence_completeness=$completeness
    }
}

function Get-ClassifiedStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$AssertionResult,$KnownDefect,[ValidateSet('mock','real')][string]$RunMode,[string]$MockExpectation='PASS')
    $knownDefectMatched=$false
    if($null -ne $KnownDefect){
        $knownDefectMatched=$true
        if($null -ne $KnownDefect.PSObject.Properties['signature']){
            $knownDefectMatched=$false
            $productErrors=$(if($null -ne $AssertionResult.PSObject.Properties['product_errors']){@($AssertionResult.product_errors)}else{@()})
            $requiredSuffixes=$(if($null -ne $KnownDefect.signature.PSObject.Properties['required_product_error_suffixes']){@($KnownDefect.signature.required_product_error_suffixes)}else{@()})
            if($requiredSuffixes.Count -gt 0){
                $knownDefectMatched=$true
                foreach($suffix in $requiredSuffixes){
                    $suffixMatched=$false
                    foreach($productError in $productErrors){if(([string]$productError).EndsWith([string]$suffix,[System.StringComparison]::OrdinalIgnoreCase)){$suffixMatched=$true;break}}
                    if(-not $suffixMatched){$knownDefectMatched=$false;break}
                }
            }
        }
    }
    if($RunMode -eq 'mock'){
        switch([string]$AssertionResult.outcome){'PASS'{return 'MOCK_PASS'}'HOLD_AMBIGUOUS'{return 'MOCK_HOLD'}'FAIL_PRODUCT'{if($knownDefectMatched -or ($null -eq $KnownDefect -and $MockExpectation -eq 'EXPECTED_FAIL')){return 'MOCK_EXPECTED_FAIL'};return 'MOCK_HOLD'}default{return 'MOCK_HOLD'}}
    }
    if([string]$AssertionResult.outcome -eq 'FAIL_PRODUCT' -and $knownDefectMatched){return 'EXPECTED_FAIL'}
    return [string]$AssertionResult.outcome
}

function Test-ShouldStopRun {
    [CmdletBinding()]
    param([string]$Status,$Suite,[int]$ConsecutiveProductFailures,[bool]$Independent=$true)
    switch($Status){'FAIL_HARNESS'{return [bool]$Suite.execution.stop_on_harness_failure}'FAIL_INFRASTRUCTURE'{return [bool]$Suite.execution.stop_on_infrastructure_failure}'CONTAMINATED'{return [bool]$Suite.execution.stop_on_state_contamination}'FAIL_PRODUCT'{return ((-not [bool]$Suite.execution.continue_on_product_failure)-or $ConsecutiveProductFailures -ge [int]$Suite.execution.max_consecutive_product_failures)}'EXPECTED_FAIL'{return (-not [bool]$Suite.execution.continue_on_expected_failure)}'HOLD_AMBIGUOUS'{return ((-not [bool]$Suite.execution.continue_on_ambiguous_hold)-or -not $Independent)}default{return $false}}
}

Export-ModuleMember -Function Test-ScenarioAssertions, Get-ClassifiedStatus, Test-ShouldStopRun
