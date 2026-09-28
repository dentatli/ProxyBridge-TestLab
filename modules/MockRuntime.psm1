Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProcessAdapter.psm1')
Import-Module (Join-Path $PSScriptRoot 'ClientRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProxyBridgeEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'VpsEvidence.psm1')

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-MockPlanValue {
    param($ClientPlan, [int]$FlowIndex, [string]$Name)
    $flow = @($ClientPlan.flows | Where-Object { [int]$_.flow_index -eq $FlowIndex }) | Select-Object -First 1
    if ($null -eq $flow -or $null -eq $flow.PSObject.Properties[$Name]) { return '' }
    return [string]$flow.$Name
}

function Get-MockObjectValue {
    param($Object, [string]$Name, $Default)
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Resolve-MockEvidenceTemplate {
    param([string]$Text, [hashtable]$Variables)
    $resolved = $Text
    foreach ($name in @($Variables.Keys | Sort-Object Length -Descending)) { $resolved = $resolved.Replace("`${$name}", [string]$Variables[$name]) }
    $unresolved = @([regex]::Matches($resolved, '\$\{[A-Z0-9_]+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    if ($unresolved.Count -gt 0) { throw "MOCK_FIXTURE_UNRESOLVED: $($unresolved -join ',')" }
    return $resolved
}

function Copy-ResolvedMockEvidence {
    param([string]$Source, [string]$Destination, [hashtable]$Variables)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "MOCK_FIXTURE_FILE_NOT_FOUND: $(Split-Path -Leaf $Source)" }
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Source), [System.Text.Encoding]::UTF8)
    $resolved = Resolve-MockEvidenceTemplate -Text $text -Variables $Variables
    [System.IO.File]::WriteAllText($Destination, $resolved, $script:Utf8NoBom)
}

function Complete-MockVpsEvidence {
    param([string]$Path, [hashtable]$Variables)
    $completed = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @([System.IO.File]::ReadAllLines($Path))) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $record = $line | ConvertFrom-Json
        $flowIndex = [int](Get-MockObjectValue $record 'flow_index' 0)
        $declaredPhase = [string](Get-MockObjectValue $record 'phase' '')
        $heldRecheck = $declaredPhase -eq 'held_recheck' -or
            ([string]::IsNullOrWhiteSpace($declaredPhase) -and [string]$record.sha256 -eq [string]$Variables.FLOW2_SHA)
        $phase = $(if (-not [string]::IsNullOrWhiteSpace($declaredPhase)) { $declaredPhase } elseif ($heldRecheck) { [string]$Variables.PHASE2 } elseif ($flowIndex -eq 0) { [string]$Variables.PHASE0 } else { [string]$Variables.PHASE1 })
        $sequence = [int](Get-MockObjectValue $record 'sequence' $(if ($heldRecheck) { 3 } else { $flowIndex + 1 }))
        $protocol = [string](Get-MockObjectValue $record 'protocol' $(if ($flowIndex -eq 1) { [string]$Variables.PROTOCOL1 } else { [string]$Variables.PROTOCOL0 }))
        foreach ($pair in @(
            @('timestamp_utc', [string]$Variables.TIMESTAMP), @('monotonic_ns', [long](1000000000 + $sequence)),
            @('family', [string]$Variables.FAMILY), @('protocol', $protocol), @('test_id', [string]$Variables.TEST_ID),
            @('run_id', [string]$Variables.RUN_ID), @('phase', $phase), @('sequence', $sequence)
        )) {
            if ($null -eq $record.PSObject.Properties[[string]$pair[0]]) { $record | Add-Member -NotePropertyName ([string]$pair[0]) -NotePropertyValue $pair[1] }
        }
        $completed.Add(($record | ConvertTo-Json -Compress -Depth 20))
    }
    $text = $(if ($completed.Count -gt 0) { ($completed -join [Environment]::NewLine) + [Environment]::NewLine } else { '' })
    [System.IO.File]::WriteAllText($Path, $text, $script:Utf8NoBom)
}

function New-GeneratedBaseMockEvidence {
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)]$ClientPlan,
        [Parameter(Mandatory)][string]$ClientPath,
        [Parameter(Mandatory)][string]$ProxyBridgePath,
        [Parameter(Mandatory)][string]$VpsPath,
        [Parameter(Mandatory)][hashtable]$Variables
    )
    if ([string]$ClientPlan.executor -ne 'base') { throw 'MOCK_GENERATOR_BASE_EXECUTOR_REQUIRED' }
    $flows = @($ClientPlan.flows | Sort-Object { [int]$_.flow_index })
    if ($flows.Count -lt 1 -or $flows.Count -gt 32) { throw 'MOCK_GENERATOR_FLOW_COUNT_INVALID' }
    $parallelCount = $(if ($null -ne $ClientPlan.PSObject.Properties['parallel_count']) { [int]$ClientPlan.parallel_count } else { 1 })
    $processCount = $(if ($null -ne $ClientPlan.PSObject.Properties['process_count']) { [int]$ClientPlan.process_count } else { 1 })
    $reconnectCount = $(if ($null -ne $ClientPlan.PSObject.Properties['reconnect_count']) { [int]$ClientPlan.reconnect_count } else { 1 })
    $streamCount = $(if ($null -ne $Scenario.PSObject.Properties['parameters'] -and $null -ne $Scenario.parameters.PSObject.Properties['stream_count']) { [int]$Scenario.parameters.stream_count } else { 1 })
    $expectedFlowCount = $(if ($processCount -gt 1) { $processCount } elseif ($parallelCount -gt 1) { $parallelCount } elseif ($reconnectCount -gt 1) { $reconnectCount } else { $streamCount })
    if ($expectedFlowCount -ne $flows.Count) { throw 'MOCK_GENERATOR_EXECUTOR_COUNT_MISMATCH' }
    $lateResponse = $flows.Count -eq 2 -and $null -ne $flows[0].PSObject.Properties['endpoint_behavior'] -and [string]$flows[0].endpoint_behavior -eq 'late-response'
    if (@($flows | Where-Object { [string]$_.expected_action -ne 'DIRECT' -or ([string]$_.expected_outcome -ne 'echo' -and -not $lateResponse) }).Count -gt 0) {
        throw 'MOCK_GENERATOR_DIRECT_ECHO_ONLY'
    }

    $clientLines = [System.Collections.Generic.List[string]]::new()
    $vpsLines = [System.Collections.Generic.List[string]]::new()
    $proxyLines = [System.Collections.Generic.List[string]]::new()
    $outOfOrder = $flows.Count -eq 2 -and $null -ne $flows[0].PSObject.Properties['endpoint_behavior'] -and [string]$flows[0].endpoint_behavior -eq 'out-of-order'
    foreach ($flow in $flows) {
        $flowIndex = [int]$flow.flow_index
        if ($flowIndex -lt 0 -or $flowIndex -ge $flows.Count) { throw 'MOCK_GENERATOR_FLOW_INDEX_INVALID' }
        $sequence = $flowIndex + 1
        $phase = $(if ($processCount -gt 1) { "process_$sequence" } elseif ($parallelCount -gt 1) { "parallel_$sequence" } elseif ($reconnectCount -gt 1) { "reconnect_$sequence" } elseif ($streamCount -gt 1) { "stream_$sequence" } else { 'single' })
        $protocol = ([string]$flow.protocol).ToUpperInvariant()
        if (@('TCP','UDP') -notcontains $protocol) { throw 'MOCK_GENERATOR_PROTOCOL_INVALID' }
        $payloadBytes = $(if ($null -ne $flow.PSObject.Properties['payload_size']) { [int]$flow.payload_size } else { 64 })
        if ($payloadBytes -lt 0) { throw 'MOCK_GENERATOR_PAYLOAD_SIZE_INVALID' }
        $payloadSha = ([long]$sequence).ToString('x64')
        $localPort = $(if ($streamCount -gt 1) { 32000 } else { 32000 + $flowIndex })
        $socketId = $(if (($streamCount -gt 1 -and -not $lateResponse) -or $processCount -gt 1) { 7001 } else { 7001 + $flowIndex })
        $remoteIp = [string]$flow.remote_ip
        $remotePort = [int]$flow.remote_port
        if ([string]::IsNullOrWhiteSpace($remoteIp) -or $remotePort -lt 1) { throw 'MOCK_GENERATOR_REMOTE_ENDPOINT_INVALID' }
        $closeMode = $(if ($null -ne $flow.PSObject.Properties['close_mode']) { [string]$flow.close_mode } else { 'none' })
        $endpointBehavior = $(if ($null -ne $flow.PSObject.Properties['endpoint_behavior']) { [string]$flow.endpoint_behavior } else { '' })
        $behaviorDelay = $(if ($null -ne $flow.PSObject.Properties['behavior_delay_ms']) { [int]$flow.behavior_delay_ms } else { 0 })
        $minimumTiming = $(if ($null -ne $flow.PSObject.Properties['expected_min_timing_ms']) { [int]$flow.expected_min_timing_ms } else { 0 })
        $timing = [Math]::Max(1, $minimumTiming + 1)
        $udpMode = $(if ($protocol -eq 'UDP') { [string]$Scenario.client.socket_mode } else { 'n/a' })
        $tcpPolicy = $(if ($protocol -eq 'TCP') { [string]$Scenario.client.tcp_peer_policy } else { 'n/a' })
        $remoteHost = $(if ($null -ne $flow.PSObject.Properties['remote_host']) { [string]$flow.remote_host } else { '' })
        $recordPid = $(if ($processCount -gt 1) { 4242 + $flowIndex } else { 4242 })
        $noResponse = [string]$flow.expected_outcome -eq 'no-echo'
        $flowTimestamp = ([datetimeoffset]::Parse([string]$Variables.TIMESTAMP).AddMilliseconds([long]$flowIndex * [long](Get-MockObjectValue $ClientPlan 'reconnect_wait_ms' 0))).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $clientRecord = [pscustomobject][ordered]@{
            timestamp_utc=$flowTimestamp; test_id=[string]$Scenario.scenario_id; run_id=[string]$ClientPlan.run_id
            mode='single'; process_id=$recordPid; sequence=$sequence; phase=$phase; expected_action='DIRECT'; expect=[string]$flow.expected_outcome
            family=('IPv' + [string]$Scenario.client.family); protocol=$protocol; tcp_peer_policy=$tcpPolicy
            udp_mode=$udpMode; close_mode=$closeMode; endpoint_behavior=$endpointBehavior; behavior_delay_ms=$behaviorDelay
            requested_local_ip=[string]$Scenario.client.local_ip; requested_local_port=0
            actual_local_ip=[string]$Scenario.client.local_ip; actual_local_port=$localPort
            socket_id=$socketId
            requested_remote_ip=$remoteIp; requested_remote_host=$remoteHost; requested_remote_port=$remotePort
            actual_remote_ip=$(if($noResponse){''}else{$remoteIp}); actual_remote_port=$(if($noResponse){0}else{$remotePort}); wsa_error=0
            bytes_sent=$payloadBytes; bytes_received=$(if($noResponse){0}else{$payloadBytes}); response_count=$(if($noResponse){0}else{1})
            response_order=$(if ($outOfOrder) { if ($flowIndex -eq 0) { 2 } else { 1 } } else { 0 })
            payload_sha256=$payloadSha; response_sha256=$(if($noResponse){''}else{$payloadSha}); timing_ms=$timing
            expected_result=[string]$flow.expected_outcome; actual_result=$(if($noResponse){'pass:no_echo_socket_closed'}else{'pass'})
        }
        $clientLines.Add(($clientRecord | ConvertTo-Json -Compress -Depth 20))
        $receivedEvent = $(if ($protocol -eq 'UDP') { 'RECEIVED' } else { 'MESSAGE_RECEIVED' })
        $events = $(if ($outOfOrder) { @($receivedEvent) } else { @($receivedEvent, 'ECHOED') })
        foreach ($event in $events) {
            $vpsLines.Add(([pscustomobject][ordered]@{
                timestamp_utc=$flowTimestamp; monotonic_ns=(1000000000 + ($sequence * 10) + $vpsLines.Count)
                family=('IPv' + [string]$Scenario.client.family); protocol=$protocol; event=$event; sha256=$payloadSha
                local_ip=$remoteIp; local_port=$remotePort; remote_ip=[string]$Variables.DIRECT_EGRESS_IP
                remote_port=(50000 + $flowIndex); bytes=$payloadBytes; error=''; test_id=[string]$Scenario.scenario_id
                run_id=[string]$ClientPlan.run_id; phase=$phase; sequence=$sequence
            } | ConvertTo-Json -Compress -Depth 20))
        }
        if (-not [string]::IsNullOrWhiteSpace($closeMode)) {
            $closeEvent = $(if ($closeMode -eq 'abortive') { 'RESET_BY_PEER' } elseif ($closeMode -in @('graceful','half-close')) { 'CLOSED' } else { '' })
            if ($closeEvent) {
                $vpsLines.Add(([pscustomobject][ordered]@{
                    timestamp_utc=$flowTimestamp; monotonic_ns=(1000001000 + $sequence)
                    family=('IPv' + [string]$Scenario.client.family); protocol=$protocol; event=$closeEvent; sha256=$payloadSha
                    local_ip=$remoteIp; local_port=$remotePort; remote_ip=[string]$Variables.DIRECT_EGRESS_IP
                    remote_port=(50000 + $flowIndex); bytes=0; error=''; test_id=[string]$Scenario.scenario_id
                    run_id=[string]$ClientPlan.run_id; phase=$phase; sequence=$sequence
                } | ConvertTo-Json -Compress -Depth 20))
            }
        }
        $endpoint = $(if ($remoteIp -match ':') { "[$remoteIp]:$remotePort" } else { "${remoteIp}:$remotePort" })
        $proxyLines.Add("$flowTimestamp $($Variables.PROCESS) ($recordPid) -> $endpoint via Direct")
    }
    if ($outOfOrder) {
        foreach ($flow in @($flows | Sort-Object { [int]$_.flow_index } -Descending)) {
            $flowIndex = [int]$flow.flow_index
            $sequence = $flowIndex + 1
            $payloadSha = ([long]$sequence).ToString('x64')
            $payloadBytes = [int]$flow.payload_size
            $flowTimestamp = ([datetimeoffset]::Parse([string]$Variables.TIMESTAMP).AddMilliseconds($sequence)).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            $vpsLines.Add(([pscustomobject][ordered]@{
                timestamp_utc=$flowTimestamp; monotonic_ns=(1000005000 + $vpsLines.Count)
                family=('IPv' + [string]$Scenario.client.family); protocol='UDP'; event='ECHOED'; sha256=$payloadSha
                local_ip=[string]$flow.remote_ip; local_port=[int]$flow.remote_port; remote_ip=[string]$Variables.DIRECT_EGRESS_IP
                remote_port=50000; bytes=$payloadBytes; error=''; test_id=[string]$Scenario.scenario_id
                run_id=[string]$ClientPlan.run_id; phase="stream_$sequence"; sequence=$sequence
            } | ConvertTo-Json -Compress -Depth 20))
        }
    }
    [System.IO.File]::WriteAllLines($ClientPath, $clientLines.ToArray(), $script:Utf8NoBom)
    if ($processCount -gt 1) {
        $children = @($ClientPlan.child_process_plans | Sort-Object { [int]$_.process_index })
        if ($children.Count -ne $clientLines.Count) { throw 'MOCK_GENERATOR_CHILD_PLAN_COUNT_MISMATCH' }
        for ($childIndex = 0; $childIndex -lt $children.Count; $childIndex++) {
            [System.IO.File]::WriteAllLines([string]$children[$childIndex].jsonl_path, @([string]$clientLines[$childIndex]), $script:Utf8NoBom)
        }
    }
    [System.IO.File]::WriteAllLines($VpsPath, $vpsLines.ToArray(), $script:Utf8NoBom)
    [System.IO.File]::WriteAllLines($ProxyBridgePath, $proxyLines.ToArray(), $script:Utf8NoBom)
}

function Invoke-MockScenario {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)]$ClientPlan,
        [Parameter(Mandatory)][string]$FixtureRoot,
        [Parameter(Mandatory)][string]$EvidenceDirectory,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment
    )
    if ([string]::IsNullOrWhiteSpace([string]$Scenario.mock_fixture_id)) { throw 'MOCK_FIXTURE_ID_REQUIRED' }
    $generatedBaseFixture = [string]$Scenario.mock_fixture_id -eq 'generated-base-direct'
    $fixtureDirectory = Join-Path $FixtureRoot ([string]$Scenario.mock_fixture_id)
    if (-not $generatedBaseFixture -and -not (Test-Path -LiteralPath $fixtureDirectory -PathType Container)) { throw "MOCK_FIXTURE_NOT_FOUND: $($Scenario.mock_fixture_id)" }
    if (-not (Test-Path -LiteralPath $EvidenceDirectory)) { $null = New-Item -ItemType Directory -Path $EvidenceDirectory -Force }

    $flow0Sha = '1111111111111111111111111111111111111111111111111111111111111111'
    $flow1Sha = '2222222222222222222222222222222222222222222222222222222222222222'
    $flow2Sha = '3333333333333333333333333333333333333333333333333333333333333333'
    $flow3Sha = '4444444444444444444444444444444444444444444444444444444444444444'
    $protocol0 = Get-MockPlanValue $ClientPlan 0 'protocol'
    $protocol1 = Get-MockPlanValue $ClientPlan 1 'protocol'
    $action0 = Get-MockPlanValue $ClientPlan 0 'expected_action'
    $action1 = Get-MockPlanValue $ClientPlan 1 'expected_action'
    $expect0 = Get-MockPlanValue $ClientPlan 0 'expected_outcome'
    $expect1 = Get-MockPlanValue $ClientPlan 1 'expected_outcome'
    $variables = @{
        TIMESTAMP='2030-01-01T00:00:00Z'; PROCESS=[System.IO.Path]::GetFileName([string]$ClientPlan.executable)
        TEST_ID=[string]$Scenario.scenario_id; RUN_ID=[string]$ClientPlan.run_id; LOCAL_IP=[string]$Scenario.client.local_ip; LOCAL_PORT='32000'
        FLOW0_SHA=$flow0Sha; FLOW1_SHA=$flow1Sha; FLOW2_SHA=$flow2Sha; FLOW3_SHA=$flow3Sha
        MODE=$(if ([string]$ClientPlan.executor -eq 'base') { 'single' } else { [string]$ClientPlan.executor })
        FAMILY=('IPv' + [string]$Scenario.client.family)
        PROTOCOL0=$protocol0; PROTOCOL1=$protocol1
        PROTOCOL2=(Get-MockPlanValue $ClientPlan 2 'protocol'); PROTOCOL3=(Get-MockPlanValue $ClientPlan 3 'protocol')
        PHASE0=$(if ([string]$ClientPlan.executor -eq 'base') { 'single' } else { 'first_flow' }); PHASE1='second_flow'; PHASE2='held_recheck'
        ACTION0=$action0; ACTION1=$action1; EXPECT0=$expect0; EXPECT1=$expect1
        UDP_MODE0=$(if ($protocol0 -eq 'UDP') { [string](Get-MockObjectValue $Scenario.client 'socket_mode' 'connected') } else { 'n/a' })
        UDP_MODE1=$(if ($protocol1 -eq 'UDP') { [string](Get-MockObjectValue $Scenario.client 'socket_mode' 'connected') } else { 'n/a' })
        TCP_POLICY0=$(if ($protocol0 -eq 'TCP' -and $action0 -eq 'PROXY') { 'record-only' } elseif ($protocol0 -eq 'TCP') { 'exact' } else { 'n/a' })
        TCP_POLICY1=$(if ($protocol1 -eq 'TCP' -and $action1 -eq 'PROXY') { 'record-only' } elseif ($protocol1 -eq 'TCP') { 'exact' } else { 'n/a' })
        CLOSE_MODE=[string](Get-MockObjectValue $Scenario.client 'close_mode' 'graceful')
        ENDPOINT_BEHAVIOR0=(Get-MockPlanValue $ClientPlan 0 'endpoint_behavior')
        BEHAVIOR_DELAY0=$(if (-not [string]::IsNullOrWhiteSpace((Get-MockPlanValue $ClientPlan 0 'behavior_delay_ms'))) { Get-MockPlanValue $ClientPlan 0 'behavior_delay_ms' } else { '0' })
        RECEIVED_EVENT0=$(if ($protocol0 -eq 'UDP') { 'RECEIVED' } else { 'MESSAGE_RECEIVED' })
        RECEIVED_EVENT1=$(if ($protocol1 -eq 'UDP') { 'RECEIVED' } else { 'MESSAGE_RECEIVED' })
        REMOTE0_IP=(Get-MockPlanValue $ClientPlan 0 'remote_ip'); REMOTE0_PORT=(Get-MockPlanValue $ClientPlan 0 'remote_port')
        REMOTE0_HOST=(Get-MockPlanValue $ClientPlan 0 'remote_host')
        REMOTE1_IP=(Get-MockPlanValue $ClientPlan 1 'remote_ip'); REMOTE1_PORT=(Get-MockPlanValue $ClientPlan 1 'remote_port')
        REMOTE2_IP=(Get-MockPlanValue $ClientPlan 2 'remote_ip'); REMOTE2_PORT=(Get-MockPlanValue $ClientPlan 2 'remote_port')
        REMOTE3_IP=(Get-MockPlanValue $ClientPlan 3 'remote_ip'); REMOTE3_PORT=(Get-MockPlanValue $ClientPlan 3 'remote_port')
        BYTES0=$(if (-not [string]::IsNullOrWhiteSpace((Get-MockPlanValue $ClientPlan 0 'payload_size'))) { Get-MockPlanValue $ClientPlan 0 'payload_size' } else { '64' })
        BYTES1=$(if (-not [string]::IsNullOrWhiteSpace((Get-MockPlanValue $ClientPlan 1 'payload_size'))) { Get-MockPlanValue $ClientPlan 1 'payload_size' } else { '64' })
        BYTES2=$(if (-not [string]::IsNullOrWhiteSpace((Get-MockPlanValue $ClientPlan 2 'payload_size'))) { Get-MockPlanValue $ClientPlan 2 'payload_size' } else { '64' })
        BYTES3=$(if (-not [string]::IsNullOrWhiteSpace((Get-MockPlanValue $ClientPlan 3 'payload_size'))) { Get-MockPlanValue $ClientPlan 3 'payload_size' } else { '64' })
        DIRECT_EGRESS_IP='192.0.2.50'
        PROXY_EGRESS_IP='198.51.100.50'
    }
    $variables.REMOTE0_ENDPOINT = $(if ($variables.REMOTE0_IP -match ':') { "[$($variables.REMOTE0_IP)]:$($variables.REMOTE0_PORT)" } else { "$($variables.REMOTE0_IP):$($variables.REMOTE0_PORT)" })
    $variables.REMOTE1_ENDPOINT = $(if ($variables.REMOTE1_IP -match ':') { "[$($variables.REMOTE1_IP)]:$($variables.REMOTE1_PORT)" } else { "$($variables.REMOTE1_IP):$($variables.REMOTE1_PORT)" })

    $clientPath = [string]$ClientPlan.jsonl_path
    $proxyBridgePath = Join-Path $EvidenceDirectory 'proxybridge.log'
    $vpsPath = Join-Path $EvidenceDirectory 'vps.jsonl'
    if ($generatedBaseFixture) {
        New-GeneratedBaseMockEvidence -Scenario $Scenario -ClientPlan $ClientPlan -ClientPath $clientPath -ProxyBridgePath $proxyBridgePath -VpsPath $vpsPath -Variables $variables
    } else {
        Copy-ResolvedMockEvidence -Source (Join-Path $fixtureDirectory 'client.jsonl') -Destination $clientPath -Variables $variables
        Copy-ResolvedMockEvidence -Source (Join-Path $fixtureDirectory 'proxybridge.log') -Destination $proxyBridgePath -Variables $variables
        Copy-ResolvedMockEvidence -Source (Join-Path $fixtureDirectory 'vps.jsonl') -Destination $vpsPath -Variables $variables
    }
    Complete-MockVpsEvidence -Path $vpsPath -Variables $variables

    $processResults = [System.Collections.Generic.List[object]]::new()
    $mockProcessCount = $(if ($null -ne $ClientPlan.PSObject.Properties['process_count']) { [int]$ClientPlan.process_count } else { 1 })
    for ($mockProcessIndex = 0; $mockProcessIndex -lt $mockProcessCount; $mockProcessIndex++) {
        $processResults.Add([pscustomobject]@{
            exit_code=0; timed_out=$false; pid=(4242 + $mockProcessIndex); actual_path=[string]$ClientPlan.executable
            stdout='fixture human stdout (not JSONL)'; stderr=''
        })
    }
    $processAdapter = New-MockProcessAdapter -InvokeResults $processResults.ToArray() -ActualPath ([string]$ClientPlan.executable)
    $clientResult = Invoke-ClientPlan -Plan $ClientPlan -ProcessAdapter $processAdapter
    $proxyBridgeRecords = @(Import-ProxyBridgeTextEvidence -Path $proxyBridgePath)
    $vpsRecords = @(Import-VpsEvidence -Path $vpsPath)
    $context = [pscustomobject][ordered]@{
        vps_capture_complete=$true; vps_capture_complete_shas=@($clientResult.canonical_records | ForEach-Object { [string]$_.payload_sha256 } | Sort-Object -Unique)
        channel_capture_completed=$true; records_found=(@($proxyBridgeRecords).Count -gt 0)
        direct_egress_ip=[string]$variables.DIRECT_EGRESS_IP; proxy_egress_ip=[string]$variables.PROXY_EGRESS_IP
        expected_process=[string]$variables.PROCESS
        start_time_utc=[datetime]'2029-12-31T23:59:00Z'; end_time_utc=[datetime]'2030-01-01T00:01:00Z'
    }
    return [pscustomobject][ordered]@{
        client_result=$clientResult; proxybridge_records=$proxyBridgeRecords; vps_records=$vpsRecords
        evidence_context=$context; process_adapter=$processAdapter
        captured_paths=@($clientPath, $proxyBridgePath, $vpsPath)
    }
}

Export-ModuleMember -Function Resolve-MockEvidenceTemplate, Invoke-MockScenario
