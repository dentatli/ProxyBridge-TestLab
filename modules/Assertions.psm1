Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProxyBridgeEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'VpsEvidence.psm1')

function Get-AssertionContextValue {
    param($Context, [string]$Name, $Default)
    if ($null -ne $Context -and $null -ne $Context.PSObject.Properties[$Name]) { return $Context.$Name }
    return $Default
}

function Test-EvidenceIdentity {
    param([object[]]$Records, [string]$RunId, [string]$ScenarioId)
    foreach ($record in @($Records)) {
        if ($null -ne $record.PSObject.Properties['run_id'] -and -not [string]::IsNullOrWhiteSpace([string]$record.run_id) -and [string]$record.run_id -ne $RunId) { return $false }
        if ($null -ne $record.PSObject.Properties['test_id'] -and -not [string]::IsNullOrWhiteSpace([string]$record.test_id) -and [string]$record.test_id -ne $ScenarioId) { return $false }
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
    if([bool]$ClientResult.timed_out){$harnessErrors.Add('client timeout')}

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
    if([string]$Scenario.client.mode -eq 'issue209' -and $heldRechecks.Count -ne 1){$harnessErrors.Add("issue209 held_recheck count actual=$($heldRechecks.Count) expected=1")}
    elseif([string]$Scenario.client.mode -ne 'issue209' -and $heldRechecks.Count -gt 0){$harnessErrors.Add('unexpected held_recheck record')}
    if(-not (Test-EvidenceIdentity $clientRecords ([string]$ClientPlan.run_id) ([string]$Scenario.scenario_id))){$contamination.Add('client evidence identity mismatch')}
    if(-not (Test-EvidenceIdentity $VpsRecords ([string]$ClientPlan.run_id) ([string]$Scenario.scenario_id))){$contamination.Add('VPS evidence identity mismatch')}
    if(-not (Test-EvidenceIdentity $ProxyBridgeRecords ([string]$ClientPlan.run_id) ([string]$Scenario.scenario_id))){$contamination.Add('ProxyBridge evidence identity mismatch')}

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
    $startTime=Get-AssertionContextValue $EvidenceContext 'start_time_utc' ([datetime]::MinValue)
    $endTime=Get-AssertionContextValue $EvidenceContext 'end_time_utc' ([datetime]::MaxValue)

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

        $sameDestination=@(Find-ProxyBridgeFlowEvidence -Records $ProxyBridgeRecords -Process $expectedProcess -Pid $expectedPid -DestinationIp ([string]$expected.remote_ip) -DestinationPort ([int]$expected.remote_port) -StartTimeUtc $startTime -EndTimeUtc $endTime)
        $expectedRoute=@($sameDestination|Where-Object{[string]$_.action -eq [string]$expected.expected_action})
        $contradictoryRoute=@($sameDestination|Where-Object{-not [string]::IsNullOrWhiteSpace([string]$_.action) -and [string]$_.action -ne [string]$expected.expected_action})
        $wrongConfig=$false
        if($contradictoryRoute.Count -gt 0){$productErrors.Add("$label wrong ProxyBridge action")}
        if($expectedRoute.Count -gt 0 -and $null -ne $expected.PSObject.Properties['expected_proxy_config_id']){
            foreach($routeRecord in $expectedRoute){if($null -ne $routeRecord.PSObject.Properties['proxy_config_id'] -and [int]$routeRecord.proxy_config_id -ne [int]$expected.expected_proxy_config_id){$wrongConfig=$true;$productErrors.Add("$label wrong proxy config")}}
        }
        $internalRouteValid=($expectedRoute.Count -gt 0 -and $contradictoryRoute.Count -eq 0 -and -not $wrongConfig)

        $sha=([string]$record.payload_sha256).ToLowerInvariant();$shaCaptureComplete=$vpsComplete
        if($vpsCompleteShas.Count -gt 0){$shaCaptureComplete=$vpsCompleteShas -contains $sha}
        $expectedReceived=$(if([string]$expected.expected_action -eq 'BLOCK'){0}else{1})
        $expectedEchoed=$(if([string]$expected.expected_outcome -eq 'echo' -and [string]$expected.expected_action -ne 'BLOCK'){1}else{0})
        $vpsResult=Test-VpsPayloadEvidence -Records $VpsRecords -Sha256 $sha -Protocol ([string]$expected.protocol) -ExpectedReceived $expectedReceived -ExpectedEchoed $expectedEchoed -ExpectedDestinationPort ([int]$expected.remote_port)
        $externalRouteProof=$false
        if([string]$expected.expected_action -eq 'BLOCK'){
            $leaks=@($vpsResult.matches|Where-Object{[string]$_.event -in @('MESSAGE_RECEIVED','RECEIVED','ECHOED')})
            if($leaks.Count -gt 0){$productErrors.Add("$label block leak")}
            elseif(-not $shaCaptureComplete){$missingEvidence.Add("$label complete VPS capture")}
            else{$externalRouteProof=$true}
        }else{
            if(-not $shaCaptureComplete){$missingEvidence.Add("$label complete VPS capture")}
            if($vpsResult.received -eq 0){$missingEvidence.Add("$label VPS payload evidence")}
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
    return [pscustomobject][ordered]@{
        passed=($outcome -eq 'PASS');outcome=$outcome
        product_errors=@($productErrors|Sort-Object -Unique);harness_errors=@($harnessErrors|Sort-Object -Unique)
        missing_evidence=@($missingEvidence|Sort-Object -Unique);contamination=@($contamination|Sort-Object -Unique);errors=@($allErrors|Sort-Object -Unique)
        channel_capture_completed=$channelCaptureCompleted;records_found=$recordsFound;route_evidence_required=$routeEvidenceRequired
        external_route_proof_complete=$externalComplete;evidence_basis=$evidenceBasis;run_mode=$RunMode
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
