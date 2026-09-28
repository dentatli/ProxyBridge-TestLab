Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProcessAdapter.psm1')

$script:MaxClientProcessTimeoutMs = 600000

function Get-ClientProperty {
    param($Client, [string]$Name, $Default, [switch]$Required)
    $property = $Client.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    if ($Required) { throw "CLIENT_CONTRACT_MISSING_$($Name.ToUpperInvariant())" }
    return $Default
}

function Add-ClientArgumentPair {
    param($Arguments, [string]$Name, $Value)
    if ($null -eq $Value) { throw "CLIENT_ARGUMENT_VALUE_MISSING_$($Name.TrimStart('-').ToUpperInvariant().Replace('-', '_'))" }
    $Arguments.Add($Name)
    $Arguments.Add([string]$Value)
}

function Get-ClientArgumentInt {
    param($Plan, [string]$Name, [int]$Default = 0)
    $index = [array]::IndexOf(@($Plan.arguments), $Name)
    if ($index -lt 0) { return $Default }
    if ($index + 1 -ge @($Plan.arguments).Count) { throw "CLIENT_ARGUMENT_VALUE_MISSING_$($Name.TrimStart('-').ToUpperInvariant().Replace('-', '_'))" }
    $value = 0
    if (-not [int]::TryParse([string]$Plan.arguments[$index + 1], [ref]$value) -or $value -lt 0) { throw "CLIENT_ARGUMENT_VALUE_INVALID_$($Name.TrimStart('-').ToUpperInvariant().Replace('-', '_'))" }
    return $value
}

function Set-ClientOperationTimeoutArgument {
    param($Plan, [int]$OperationTimeoutMs)
    $index = [array]::IndexOf(@($Plan.arguments), '--timeout-ms')
    if ($index -lt 0 -or $index + 1 -ge @($Plan.arguments).Count) { throw 'CLIENT_TIMEOUT_ARGUMENT_MISSING' }
    $Plan.arguments[$index + 1] = [string]$OperationTimeoutMs
}

function ConvertTo-ClientPort {
    param($Value, [string]$Name, [switch]$AllowZero)
    $port = 0
    if (-not [int]::TryParse([string]$Value, [ref]$port)) { throw "CLIENT_PORT_INVALID_$Name" }
    $minimum = $(if ($AllowZero) { 0 } else { 1 })
    if ($port -lt $minimum -or $port -gt 65535) { throw "CLIENT_PORT_INVALID_$Name" }
    return $port
}

function ConvertTo-ClientFamily {
    param($Value)
    $family = 0
    if (-not [int]::TryParse([string]$Value, [ref]$family) -or @(4, 6) -notcontains $family) {
        throw 'CLIENT_FAMILY_UNSUPPORTED'
    }
    return $family
}

function ConvertTo-ClientAction {
    param($Value, [string]$Name)
    $action = ([string]$Value).ToUpperInvariant()
    if (@('DIRECT', 'BLOCK', 'PROXY') -notcontains $action) { throw "CLIENT_ACTION_UNSUPPORTED_$Name" }
    return $action
}

function ConvertTo-ClientExpectation {
    param($Value, [string]$Name)
    $expectation = ([string]$Value).ToLowerInvariant()
    if (@('echo', 'no-echo') -notcontains $expectation) { throw "CLIENT_EXPECTATION_UNSUPPORTED_$Name" }
    return $expectation
}

function ConvertTo-ClientPeerPolicy {
    param($Value, [string]$Name)
    $policy = ([string]$Value).ToLowerInvariant()
    if (@('exact', 'record-only') -notcontains $policy) { throw "CLIENT_TCP_PEER_POLICY_UNSUPPORTED_$Name" }
    return $policy
}

function Get-ExpectedProxyConfigId {
    param($Scenario, [string]$Action, [string]$RuleKey = '')
    if ($Action -ne 'PROXY') { return 0 }
    $rules = @($Scenario.rule_set | Where-Object { [string]$_.action -eq 'PROXY' })
    if (-not [string]::IsNullOrWhiteSpace($RuleKey)) {
        $keyed = @($rules | Where-Object { [string]$_.rule_key -eq $RuleKey })
        if ($keyed.Count -gt 0) { $rules = $keyed }
    }
    if ($rules.Count -lt 1) { throw 'CLIENT_PROXY_CONFIG_EXPECTATION_MISSING' }
    $configId = 0
    if (-not [int]::TryParse([string]$rules[0].proxy_config_id, [ref]$configId) -or $configId -lt 1) {
        throw 'CLIENT_PROXY_CONFIG_EXPECTATION_INVALID'
    }
    return $configId
}

function Import-ClientContract {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'CLIENT_CONTRACT_NOT_FOUND' }
    try { $contract = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "CLIENT_CONTRACT_INVALID_JSON: $($_.Exception.Message)" }
    foreach ($field in @('schema_version', 'contract_id', 'modes')) {
        if ($null -eq $contract.PSObject.Properties[$field]) { throw "CLIENT_CONTRACT_MISSING_$($field.ToUpperInvariant())" }
    }
    if ([int]$contract.schema_version -ne 1) { throw 'CLIENT_CONTRACT_VERSION_UNSUPPORTED' }
    foreach ($mode in @('base', 'issue206', 'issue209')) {
        if ($null -eq $contract.modes.PSObject.Properties[$mode]) { throw "CLIENT_CONTRACT_MODE_MISSING_$($mode.ToUpperInvariant())" }
    }
    return $contract
}

function New-BaseClientPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$JsonlPath,
        $Contract
    )

    $client = $Scenario.client
    $family = ConvertTo-ClientFamily (Get-ClientProperty $client 'family' $null -Required)
    $protocol = ([string](Get-ClientProperty $client 'protocol' $null -Required)).ToLowerInvariant()
    if (@('tcp', 'udp') -notcontains $protocol) { throw 'CLIENT_BASE_PROTOCOL_UNSUPPORTED' }
    $udpMode = ([string](Get-ClientProperty $client 'socket_mode' 'connected')).ToLowerInvariant()
    if ($protocol -eq 'udp' -and @('connected', 'unconnected') -notcontains $udpMode) { throw 'CLIENT_UDP_SOCKET_MODE_UNSUPPORTED' }
    $expectedAction = ConvertTo-ClientAction (Get-ClientProperty $client 'expected_action' $null -Required) 'BASE'
    $expect = ConvertTo-ClientExpectation (Get-ClientProperty $client 'expected_outcome' $(if ($expectedAction -eq 'BLOCK') { 'no-echo' } else { 'echo' })) 'BASE'
    $timeoutMs = [int](Get-ClientProperty $client 'timeout_ms' $Scenario.timeout_ms)
    if ($timeoutMs -lt 1) { throw 'CLIENT_TIMEOUT_INVALID' }
    $localPort = ConvertTo-ClientPort (Get-ClientProperty $client 'local_port' 0) 'LOCAL' -AllowZero
    $remotePort = ConvertTo-ClientPort (Get-ClientProperty $client 'remote_port' $null -Required) 'REMOTE'
    $tcpPeerPolicy = ''
    if ($protocol -eq 'tcp') {
        $defaultPolicy = $(if ($expectedAction -eq 'PROXY') { 'record-only' } else { 'exact' })
        $tcpPeerPolicy = ConvertTo-ClientPeerPolicy (Get-ClientProperty $client 'tcp_peer_policy' $defaultPolicy) 'BASE'
    }
    $payloadSize = $null
    if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
        $null -ne $Scenario.parameters.PSObject.Properties['payload_size']) {
        $parsedPayloadSize = -1
        if (-not [int]::TryParse([string]$Scenario.parameters.payload_size, [ref]$parsedPayloadSize) -or $parsedPayloadSize -lt 0) {
            throw 'CLIENT_PAYLOAD_SIZE_INVALID'
        }
        $maximumPayloadSize = $(if ($protocol -eq 'udp') { 65507 } else { 1048576 })
        if ($parsedPayloadSize -gt $maximumPayloadSize) { throw 'CLIENT_PAYLOAD_SIZE_UNSUPPORTED' }
        $payloadSize = $parsedPayloadSize
    }
    $streamCount = 1
    if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
        $null -ne $Scenario.parameters.PSObject.Properties['stream_count']) {
        if (-not [int]::TryParse([string]$Scenario.parameters.stream_count, [ref]$streamCount) -or
            $streamCount -lt 2 -or $streamCount -gt 64) {
            throw 'CLIENT_STREAM_COUNT_INVALID'
        }
        if ($null -eq $payloadSize) { throw 'CLIENT_STREAM_PAYLOAD_SIZE_REQUIRED' }
    }
    $parallelCount = 1
    if ($null -ne $Scenario.PSObject.Properties['parameters']) {
        $parallelValue = $null
        if ($null -ne $Scenario.parameters.PSObject.Properties['parallel_count']) {
            $parallelValue = $Scenario.parameters.parallel_count
        } elseif ($null -ne $Scenario.parameters.PSObject.Properties['concurrency']) {
            $parallelValue = $Scenario.parameters.concurrency
        }
        if ($null -ne $parallelValue) {
            if (-not [int]::TryParse([string]$parallelValue, [ref]$parallelCount) -or
                $parallelCount -lt 1 -or $parallelCount -gt 32) {
                throw 'CLIENT_PARALLEL_COUNT_INVALID'
            }
        }
    }
    if ($parallelCount -gt 1 -and $streamCount -gt 1) { throw 'CLIENT_PARALLEL_STREAM_CONFLICT' }
    if ($parallelCount -gt 1 -and $localPort -ne 0) { throw 'CLIENT_PARALLEL_REQUIRES_EPHEMERAL_PORTS' }
    $processCount = 1
    if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
        $null -ne $Scenario.parameters.PSObject.Properties['process_count']) {
        if (-not [int]::TryParse([string]$Scenario.parameters.process_count, [ref]$processCount) -or
            $processCount -lt 1 -or $processCount -gt 8) { throw 'CLIENT_PROCESS_COUNT_INVALID' }
    }
    if ($processCount -gt 1 -and ($parallelCount -gt 1 -or $streamCount -gt 1)) { throw 'CLIENT_MULTI_PROCESS_FLOW_MODE_CONFLICT' }
    if ($processCount -gt 1 -and $localPort -ne 0) { throw 'CLIENT_MULTI_PROCESS_REQUIRES_EPHEMERAL_PORTS' }
    $reconnectCount = 1
    $reconnectWaitMs = 0
    if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
        $null -ne $Scenario.parameters.PSObject.Properties['reconnect_count']) {
        if (-not [int]::TryParse([string]$Scenario.parameters.reconnect_count, [ref]$reconnectCount) -or
            $reconnectCount -lt 2 -or $reconnectCount -gt 32) { throw 'CLIENT_RECONNECT_COUNT_INVALID' }
        if ($protocol -ne 'udp') { throw 'CLIENT_RECONNECT_REQUIRES_UDP' }
        if ($parallelCount -gt 1 -or $processCount -gt 1 -or $streamCount -gt 1) { throw 'CLIENT_RECONNECT_FLOW_MODE_CONFLICT' }
        if ($localPort -ne 0) { throw 'CLIENT_RECONNECT_REQUIRES_EPHEMERAL_PORTS' }
        if ($null -eq $Scenario.parameters.PSObject.Properties['reconnect_wait_ms'] -or
            -not [int]::TryParse([string]$Scenario.parameters.reconnect_wait_ms, [ref]$reconnectWaitMs) -or
            $reconnectWaitMs -lt 1 -or $reconnectWaitMs -gt 60000) { throw 'CLIENT_RECONNECT_WAIT_INVALID' }
    }
    $secondStreamRemotePort = $null
    if ($streamCount -gt 1 -and $protocol -eq 'udp') {
        if ($udpMode -ne 'unconnected') { throw 'CLIENT_UDP_MULTI_DESTINATION_REQUIRES_UNCONNECTED' }
        if ($null -eq $Scenario.parameters.PSObject.Properties['second_remote_port']) { throw 'CLIENT_UDP_STREAM_SECOND_REMOTE_PORT_REQUIRED' }
        $secondStreamRemotePort = ConvertTo-ClientPort $Scenario.parameters.second_remote_port 'SECOND_REMOTE'
    }
    $streamIntervalMs = 0
    if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
        $null -ne $Scenario.parameters.PSObject.Properties['stream_interval_ms']) {
        if (-not [int]::TryParse([string]$Scenario.parameters.stream_interval_ms, [ref]$streamIntervalMs) -or
            $streamIntervalMs -lt 0 -or $streamIntervalMs -gt 60000) { throw 'CLIENT_STREAM_INTERVAL_INVALID' }
        if ($streamCount -lt 2) { throw 'CLIENT_STREAM_INTERVAL_REQUIRES_STREAM' }
    }
    $baseCloseMode = ''
    if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
        $null -ne $Scenario.parameters.PSObject.Properties['close_mode']) {
        $baseCloseMode = ([string]$Scenario.parameters.close_mode).ToLowerInvariant()
        if (@('graceful','abortive','half-close') -notcontains $baseCloseMode) { throw 'CLIENT_BASE_CLOSE_MODE_UNSUPPORTED' }
    }
    $endpointBehavior = ''
    $behaviorDelayMs = 0
    $baseBindRetryCount = 0
    $baseBindRetryDelayMs = 0
    if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
        $null -ne $Scenario.parameters.PSObject.Properties['endpoint_behavior']) {
        $endpointBehavior = ([string]$Scenario.parameters.endpoint_behavior).ToLowerInvariant()
        if (@('normal','delay','server-close','reset','silent-timeout','drop','duplicate','out-of-order','late-response') -notcontains $endpointBehavior) { throw 'CLIENT_ENDPOINT_BEHAVIOR_UNSUPPORTED' }
        if ($null -eq $payloadSize) { throw 'CLIENT_ENDPOINT_BEHAVIOR_PAYLOAD_SIZE_REQUIRED' }
        if ($null -ne $Scenario.parameters.PSObject.Properties['behavior_delay_ms']) {
            if (-not [int]::TryParse([string]$Scenario.parameters.behavior_delay_ms, [ref]$behaviorDelayMs) -or $behaviorDelayMs -lt 0 -or $behaviorDelayMs -gt 60000) { throw 'CLIENT_BEHAVIOR_DELAY_INVALID' }
        }
        if ($endpointBehavior -eq 'out-of-order' -and
            ($protocol -ne 'udp' -or $udpMode -ne 'unconnected' -or $streamCount -ne 2 -or $secondStreamRemotePort -ne $remotePort)) {
            throw 'CLIENT_OUT_OF_ORDER_CONTRACT_INVALID'
        }
        if ($endpointBehavior -eq 'late-response' -and
            ($protocol -ne 'udp' -or $udpMode -ne 'unconnected' -or $streamCount -ne 2 -or
             $secondStreamRemotePort -ne $remotePort -or $behaviorDelayMs -lt 100)) {
            throw 'CLIENT_LATE_RESPONSE_CONTRACT_INVALID'
        }
        if ($endpointBehavior -eq 'late-response') {
            if ($null -eq $Scenario.parameters.PSObject.Properties['bind_retry_count'] -or
                -not [int]::TryParse([string]$Scenario.parameters.bind_retry_count, [ref]$baseBindRetryCount) -or
                $baseBindRetryCount -lt 1 -or $baseBindRetryCount -gt 1000) { throw 'CLIENT_BASE_BIND_RETRY_COUNT_INVALID' }
            if ($null -eq $Scenario.parameters.PSObject.Properties['bind_retry_delay_ms'] -or
                -not [int]::TryParse([string]$Scenario.parameters.bind_retry_delay_ms, [ref]$baseBindRetryDelayMs) -or
                $baseBindRetryDelayMs -lt 1 -or $baseBindRetryDelayMs -gt 60000) { throw 'CLIENT_BASE_BIND_RETRY_DELAY_INVALID' }
        }
    }

    $arguments = [System.Collections.Generic.List[string]]::new()
    Add-ClientArgumentPair $arguments '--mode' 'single'
    Add-ClientArgumentPair $arguments '--family' $family
    Add-ClientArgumentPair $arguments '--protocol' $protocol
    if ($protocol -eq 'udp') { Add-ClientArgumentPair $arguments '--udp-mode' $udpMode }
    if ($protocol -eq 'tcp') { Add-ClientArgumentPair $arguments '--tcp-peer-policy' $tcpPeerPolicy }
    if (-not [string]::IsNullOrWhiteSpace($baseCloseMode)) { Add-ClientArgumentPair $arguments '--close-mode' $baseCloseMode }
    Add-ClientArgumentPair $arguments '--local-ip' (Get-ClientProperty $client 'local_ip' $null -Required)
    Add-ClientArgumentPair $arguments '--local-port' $localPort
    Add-ClientArgumentPair $arguments '--remote-ip' (Get-ClientProperty $client 'remote_ip' $null -Required)
    $remoteHost = [string](Get-ClientProperty $client 'remote_host' '')
    if (-not [string]::IsNullOrWhiteSpace($remoteHost)) { Add-ClientArgumentPair $arguments '--remote-host' $remoteHost }
    Add-ClientArgumentPair $arguments $(if ($protocol -eq 'tcp') { '--tcp-remote-port' } else { '--udp-remote-port' }) $remotePort
    Add-ClientArgumentPair $arguments '--expected-action' $expectedAction
    Add-ClientArgumentPair $arguments '--expect' $expect
    Add-ClientArgumentPair $arguments '--timeout-ms' $timeoutMs
    if ($null -ne $payloadSize) { Add-ClientArgumentPair $arguments '--payload-size' $payloadSize }
    if ($streamCount -gt 1) { Add-ClientArgumentPair $arguments '--stream-count' $streamCount }
    if ($parallelCount -gt 1) { Add-ClientArgumentPair $arguments '--parallel-count' $parallelCount }
    if ($reconnectCount -gt 1) {
        Add-ClientArgumentPair $arguments '--reconnect-count' $reconnectCount
        Add-ClientArgumentPair $arguments '--inter-flow-wait-ms' $reconnectWaitMs
    }
    if ($streamIntervalMs -gt 0) { Add-ClientArgumentPair $arguments '--stream-interval-ms' $streamIntervalMs }
    if ($null -ne $secondStreamRemotePort) { Add-ClientArgumentPair $arguments '--second-remote-port' $secondStreamRemotePort }
    if (-not [string]::IsNullOrWhiteSpace($endpointBehavior)) {
        Add-ClientArgumentPair $arguments '--endpoint-behavior' $endpointBehavior
        Add-ClientArgumentPair $arguments '--behavior-delay-ms' $behaviorDelayMs
        if ($endpointBehavior -eq 'late-response') {
            Add-ClientArgumentPair $arguments '--bind-retry-count' $baseBindRetryCount
            Add-ClientArgumentPair $arguments '--bind-retry-delay-ms' $baseBindRetryDelayMs
        }
    }
    Add-ClientArgumentPair $arguments '--test-id' $Scenario.scenario_id
    Add-ClientArgumentPair $arguments '--run-id' $RunId
    Add-ClientArgumentPair $arguments '--jsonl-log' $JsonlPath

    $flows = [System.Collections.Generic.List[object]]::new()
    $flowCount = $(if ($processCount -gt 1) { $processCount } elseif ($parallelCount -gt 1) { $parallelCount } elseif ($reconnectCount -gt 1) { $reconnectCount } else { $streamCount })
    for ($flowIndex = 0; $flowIndex -lt $flowCount; $flowIndex++) {
        $flow = [pscustomobject][ordered]@{
            flow_index = $flowIndex
            protocol = $protocol.ToUpperInvariant()
            expected_action = $expectedAction
            expected_outcome = $expect
            remote_ip = [string](Get-ClientProperty $client 'remote_ip' $null -Required)
            remote_port = $(if ($flowIndex -gt 0 -and $null -ne $secondStreamRemotePort) { $secondStreamRemotePort } else { $remotePort })
            expected_proxy_config_id = Get-ExpectedProxyConfigId -Scenario $Scenario -Action $expectedAction -RuleKey 'primary'
        }
        if (-not [string]::IsNullOrWhiteSpace($remoteHost)) { $flow | Add-Member -NotePropertyName remote_host -NotePropertyValue $remoteHost }
        if ($null -ne $payloadSize) { $flow | Add-Member -NotePropertyName payload_size -NotePropertyValue $payloadSize }
        if (-not [string]::IsNullOrWhiteSpace($baseCloseMode)) { $flow | Add-Member -NotePropertyName close_mode -NotePropertyValue $baseCloseMode }
        if (-not [string]::IsNullOrWhiteSpace($endpointBehavior)) {
            $flow | Add-Member -NotePropertyName endpoint_behavior -NotePropertyValue $endpointBehavior
            $flow | Add-Member -NotePropertyName behavior_delay_ms -NotePropertyValue $behaviorDelayMs
            if ($endpointBehavior -eq 'out-of-order') {
                $flow | Add-Member -NotePropertyName expected_response_order -NotePropertyValue $(if ($flowIndex -eq 0) { 2 } else { 1 })
            }
            if ($endpointBehavior -eq 'late-response') {
                if ($flowIndex -eq 0) {
                    $flow.expected_outcome = 'no-echo'
                    $flow | Add-Member -NotePropertyName expected_vps_received -NotePropertyValue 1
                    $flow | Add-Member -NotePropertyName expected_vps_echoed -NotePropertyValue 1
                    $flow | Add-Member -NotePropertyName expected_response_count -NotePropertyValue 0
                } else {
                    $flow | Add-Member -NotePropertyName expected_response_count -NotePropertyValue 1
                }
            }
        }
        if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
            $null -ne $Scenario.parameters.PSObject.Properties['expected_vps_received']) {
            $expectedVpsReceived = -1
            if (-not [int]::TryParse([string]$Scenario.parameters.expected_vps_received, [ref]$expectedVpsReceived) -or $expectedVpsReceived -lt 0) { throw 'CLIENT_EXPECTED_VPS_RECEIVED_INVALID' }
            $flow | Add-Member -NotePropertyName expected_vps_received -NotePropertyValue $expectedVpsReceived
        }
        if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
            $null -ne $Scenario.parameters.PSObject.Properties['expected_vps_echoed']) {
            $expectedVpsEchoed = -1
            if (-not [int]::TryParse([string]$Scenario.parameters.expected_vps_echoed, [ref]$expectedVpsEchoed) -or $expectedVpsEchoed -lt 0) { throw 'CLIENT_EXPECTED_VPS_ECHOED_INVALID' }
            $flow | Add-Member -NotePropertyName expected_vps_echoed -NotePropertyValue $expectedVpsEchoed
        }
        if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
            $null -ne $Scenario.parameters.PSObject.Properties['expected_response_count']) {
            $expectedResponseCount = -1
            if (-not [int]::TryParse([string]$Scenario.parameters.expected_response_count, [ref]$expectedResponseCount) -or $expectedResponseCount -lt 0) { throw 'CLIENT_EXPECTED_RESPONSE_COUNT_INVALID' }
            $flow | Add-Member -NotePropertyName expected_response_count -NotePropertyValue $expectedResponseCount
        }
        if ($null -ne $Scenario.PSObject.Properties['parameters'] -and
            $null -ne $Scenario.parameters.PSObject.Properties['expected_min_timing_ms']) {
            $expectedMinTimingMs = -1
            if (-not [int]::TryParse([string]$Scenario.parameters.expected_min_timing_ms, [ref]$expectedMinTimingMs) -or $expectedMinTimingMs -lt 0) { throw 'CLIENT_EXPECTED_MIN_TIMING_INVALID' }
            $flow | Add-Member -NotePropertyName expected_min_timing_ms -NotePropertyValue $expectedMinTimingMs
        }
        $flows.Add($flow)
    }
    $childProcessPlans = [System.Collections.Generic.List[object]]::new()
    if ($processCount -gt 1) {
        $testIdIndex = [array]::IndexOf(@($arguments), '--test-id')
        $jsonlIndex = [array]::IndexOf(@($arguments), '--jsonl-log')
        if ($testIdIndex -lt 0 -or $jsonlIndex -lt 0 -or $jsonlIndex + 1 -ge $arguments.Count) { throw 'CLIENT_MULTI_PROCESS_ARGUMENT_LAYOUT_INVALID' }
        $jsonlDirectory = [System.IO.Path]::GetDirectoryName($JsonlPath)
        $jsonlName = [System.IO.Path]::GetFileNameWithoutExtension($JsonlPath)
        $jsonlExtension = [System.IO.Path]::GetExtension($JsonlPath)
        for ($processIndex = 1; $processIndex -le $processCount; $processIndex++) {
            $childArguments = [System.Collections.Generic.List[string]]::new()
            foreach ($argument in @($arguments)) { $childArguments.Add([string]$argument) }
            $childArguments.Insert($testIdIndex, [string]$processIndex)
            $childArguments.Insert($testIdIndex, '--process-index')
            $childJsonlPath = Join-Path $jsonlDirectory ("$jsonlName.process-$processIndex$jsonlExtension")
            $childJsonlArgumentIndex = [array]::IndexOf(@($childArguments), '--jsonl-log')
            $childArguments[$childJsonlArgumentIndex + 1] = $childJsonlPath
            $childProcessPlans.Add([pscustomobject][ordered]@{
                process_index=$processIndex; executable=$ExecutablePath; arguments=$childArguments.ToArray(); jsonl_path=$childJsonlPath
            })
        }
    }
    return [pscustomobject][ordered]@{
        contract_id = $(if ($null -ne $Contract) { [string]$Contract.contract_id } else { 'proxybridge-client-stage34' })
        executor = 'base'
        executable = $ExecutablePath
        arguments = $arguments.ToArray()
        operation_timeout_ms = $timeoutMs
        operation_count = $(if ($reconnectCount -gt 1) { $reconnectCount } else { $streamCount })
        parallel_count = $parallelCount
        process_count = $processCount
        reconnect_count = $reconnectCount
        reconnect_wait_ms = $reconnectWaitMs
        additional_wait_budget_ms = (([long]([Math]::Max(0, $streamCount - 1)) * [long]$streamIntervalMs) + ([long]([Math]::Max(0, $reconnectCount - 1)) * [long]$reconnectWaitMs))
        scenario_id = [string]$Scenario.scenario_id
        run_id = $RunId
        jsonl_path = $JsonlPath
        flows = $flows.ToArray()
        expected_records = $flows.ToArray()
        child_process_plans = $childProcessPlans.ToArray()
    }
}

function New-Issue206ClientPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$JsonlPath,
        $Contract
    )

    $client = $Scenario.client
    $family = ConvertTo-ClientFamily (Get-ClientProperty $client 'family' 4)
    $firstAction = ConvertTo-ClientAction (Get-ClientProperty $client 'first_expected_action' $null -Required) 'FIRST'
    $secondAction = ConvertTo-ClientAction (Get-ClientProperty $client 'second_expected_action' $null -Required) 'SECOND'
    $firstExpect = ConvertTo-ClientExpectation (Get-ClientProperty $client 'first_expect' $(if ($firstAction -eq 'BLOCK') { 'no-echo' } else { 'echo' })) 'FIRST'
    $secondExpect = ConvertTo-ClientExpectation (Get-ClientProperty $client 'second_expect' $(if ($secondAction -eq 'BLOCK') { 'no-echo' } else { 'echo' })) 'SECOND'
    $timeoutMs = [int](Get-ClientProperty $client 'timeout_ms' $Scenario.timeout_ms)
    if ($timeoutMs -lt 1) { throw 'CLIENT_TIMEOUT_INVALID' }
    $localPort = ConvertTo-ClientPort (Get-ClientProperty $client 'local_port' 0) 'LOCAL' -AllowZero
    $firstRemotePort = ConvertTo-ClientPort (Get-ClientProperty $client 'first_remote_port' $null -Required) 'FIRST_REMOTE'
    $secondRemotePort = ConvertTo-ClientPort (Get-ClientProperty $client 'second_remote_port' $null -Required) 'SECOND_REMOTE'
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($pair in @(
        @('--mode', 'issue206'),
        @('--family', $family),
        @('--local-ip', (Get-ClientProperty $client 'local_ip' $null -Required)),
        @('--local-port', $localPort),
        @('--remote-ip', (Get-ClientProperty $client 'remote_ip' $null -Required)),
        @('--first-remote-ip', (Get-ClientProperty $client 'first_remote_ip' $null -Required)),
        @('--first-remote-port', $firstRemotePort),
        @('--second-remote-ip', (Get-ClientProperty $client 'second_remote_ip' $null -Required)),
        @('--second-remote-port', $secondRemotePort),
        @('--close-mode', (Get-ClientProperty $client 'close_mode' 'abortive')),
        @('--first-expected-action', $firstAction),
        @('--second-expected-action', $secondAction),
        @('--first-expect', $firstExpect),
        @('--second-expect', $secondExpect),
        @('--first-tcp-peer-policy', (Get-ClientProperty $client 'first_tcp_peer_policy' 'record-only')),
        @('--second-tcp-peer-policy', (Get-ClientProperty $client 'second_tcp_peer_policy' 'exact')),
        @('--timeout-ms', $timeoutMs),
        @('--bind-retry-count', (Get-ClientProperty $client 'bind_retry_count' 100)),
        @('--bind-retry-delay-ms', (Get-ClientProperty $client 'bind_retry_delay_ms' 50)),
        @('--test-id', $Scenario.scenario_id),
        @('--run-id', $RunId),
        @('--jsonl-log', $JsonlPath)
    )) { Add-ClientArgumentPair $arguments ([string]$pair[0]) $pair[1] }

    $flows = @(
        [pscustomobject][ordered]@{
            flow_index = 0; protocol = 'TCP'; expected_action = $firstAction
            expected_outcome = $firstExpect
            remote_ip = [string](Get-ClientProperty $client 'first_remote_ip' $null -Required)
            remote_port = $firstRemotePort
            expected_proxy_config_id = Get-ExpectedProxyConfigId -Scenario $Scenario -Action $firstAction -RuleKey 'first'
        },
        [pscustomobject][ordered]@{
            flow_index = 1; protocol = 'TCP'; expected_action = $secondAction
            expected_outcome = $secondExpect
            remote_ip = [string](Get-ClientProperty $client 'second_remote_ip' $null -Required)
            remote_port = $secondRemotePort
            expected_proxy_config_id = Get-ExpectedProxyConfigId -Scenario $Scenario -Action $secondAction -RuleKey 'second'
        }
    )
    return [pscustomobject][ordered]@{
        contract_id = $(if ($null -ne $Contract) { [string]$Contract.contract_id } else { 'proxybridge-client-stage34' })
        executor = 'issue206'
        executable = $ExecutablePath
        arguments = $arguments.ToArray()
        operation_timeout_ms = $timeoutMs
        scenario_id = [string]$Scenario.scenario_id
        run_id = $RunId
        jsonl_path = $JsonlPath
        flows = $flows
        expected_records = $flows
    }
}

function New-Issue209ClientPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$JsonlPath,
        $Contract
    )

    $client = $Scenario.client
    $timeoutMs = [int](Get-ClientProperty $client 'timeout_ms' $Scenario.timeout_ms)
    if ($timeoutMs -lt 1) { throw 'CLIENT_TIMEOUT_INVALID' }
    $localPort = ConvertTo-ClientPort (Get-ClientProperty $client 'local_port' 0) 'LOCAL' -AllowZero
    $firstRemotePort = ConvertTo-ClientPort (Get-ClientProperty $client 'first_remote_port' $null -Required) 'FIRST_REMOTE'
    $secondRemotePort = ConvertTo-ClientPort (Get-ClientProperty $client 'second_remote_port' $null -Required) 'SECOND_REMOTE'
    $family = ConvertTo-ClientFamily (Get-ClientProperty $client 'family' 4)
    $firstProtocol = ([string](Get-ClientProperty $client 'first_protocol' $null -Required)).ToLowerInvariant()
    if (@('tcp', 'udp') -notcontains $firstProtocol) { throw 'CLIENT_ISSUE209_PROTOCOL_UNSUPPORTED' }
    $secondProtocol = $(if ($firstProtocol -eq 'tcp') { 'udp' } else { 'tcp' })
    $declaredSecondProtocol = ([string](Get-ClientProperty $client 'second_protocol' $secondProtocol)).ToLowerInvariant()
    if ($declaredSecondProtocol -ne $secondProtocol) { throw 'CLIENT_ISSUE209_SECOND_PROTOCOL_MISMATCH' }
    $firstAction = ConvertTo-ClientAction (Get-ClientProperty $client 'first_expected_action' $null -Required) 'FIRST'
    $secondAction = ConvertTo-ClientAction (Get-ClientProperty $client 'second_expected_action' $null -Required) 'SECOND'
    $firstExpect = ConvertTo-ClientExpectation (Get-ClientProperty $client 'first_expect' 'echo') 'FIRST'
    if ($firstExpect -ne 'echo') { throw 'CLIENT_ISSUE209_FIRST_EXPECT_MUST_BE_ECHO' }
    $secondExpect = ConvertTo-ClientExpectation (Get-ClientProperty $client 'second_expect' 'echo') 'SECOND'
    $udpMode = ([string](Get-ClientProperty $client 'socket_mode' 'connected')).ToLowerInvariant()
    if (@('connected', 'unconnected') -notcontains $udpMode) { throw 'CLIENT_UDP_SOCKET_MODE_UNSUPPORTED' }
    $firstPeerPolicy = ConvertTo-ClientPeerPolicy (Get-ClientProperty $client 'first_tcp_peer_policy' $(if ($firstAction -eq 'PROXY') { 'record-only' } else { 'exact' })) 'FIRST'
    $secondPeerPolicy = ConvertTo-ClientPeerPolicy (Get-ClientProperty $client 'second_tcp_peer_policy' $(if ($secondAction -eq 'PROXY') { 'record-only' } else { 'exact' })) 'SECOND'
    $interFlowWaitMs = [int](Get-ClientProperty $client 'inter_flow_wait_ms' 100)
    if ($interFlowWaitMs -lt 0) { throw 'CLIENT_ISSUE209_INTER_FLOW_WAIT_INVALID' }
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($pair in @(
        @('--mode', 'issue209'),
        @('--family', $family),
        @('--first-protocol', $firstProtocol),
        @('--udp-mode', $udpMode),
        @('--local-ip', (Get-ClientProperty $client 'local_ip' $null -Required)),
        @('--local-port', $localPort),
        @('--first-remote-ip', (Get-ClientProperty $client 'first_remote_ip' $null -Required)),
        @('--first-remote-port', $firstRemotePort),
        @('--second-remote-ip', (Get-ClientProperty $client 'second_remote_ip' $null -Required)),
        @('--second-remote-port', $secondRemotePort),
        @('--first-expected-action', $firstAction),
        @('--second-expected-action', $secondAction),
        @('--first-expect', $firstExpect),
        @('--second-expect', $secondExpect),
        @('--first-tcp-peer-policy', $firstPeerPolicy),
        @('--second-tcp-peer-policy', $secondPeerPolicy),
        @('--inter-flow-wait-ms', $interFlowWaitMs),
        @('--timeout-ms', $timeoutMs),
        @('--bind-retry-count', (Get-ClientProperty $client 'bind_retry_count' 100)),
        @('--bind-retry-delay-ms', (Get-ClientProperty $client 'bind_retry_delay_ms' 50)),
        @('--test-id', $Scenario.scenario_id),
        @('--run-id', $RunId),
        @('--jsonl-log', $JsonlPath)
    )) { Add-ClientArgumentPair $arguments ([string]$pair[0]) $pair[1] }

    $flows = @(
        [pscustomobject][ordered]@{ flow_index=0; protocol=$firstProtocol.ToUpperInvariant(); tcp_peer_policy=$firstPeerPolicy; expected_action=$firstAction; expected_outcome=$firstExpect; remote_ip=[string](Get-ClientProperty $client 'first_remote_ip' $null -Required); remote_port=$firstRemotePort; expected_proxy_config_id=(Get-ExpectedProxyConfigId -Scenario $Scenario -Action $firstAction -RuleKey 'first') },
        [pscustomobject][ordered]@{ flow_index=1; protocol=$secondProtocol.ToUpperInvariant(); tcp_peer_policy=$secondPeerPolicy; expected_action=$secondAction; expected_outcome=$secondExpect; remote_ip=[string](Get-ClientProperty $client 'second_remote_ip' $null -Required); remote_port=$secondRemotePort; expected_proxy_config_id=(Get-ExpectedProxyConfigId -Scenario $Scenario -Action $secondAction -RuleKey 'second') }
    )
    $heldRecheck = [pscustomobject][ordered]@{
        record_kind='held_recheck'; flow_index=0; protocol=$firstProtocol.ToUpperInvariant(); tcp_peer_policy=$firstPeerPolicy
        expected_action=$firstAction; expected_outcome=$firstExpect
        remote_ip=[string](Get-ClientProperty $client 'first_remote_ip' $null -Required); remote_port=$firstRemotePort
        expected_proxy_config_id=(Get-ExpectedProxyConfigId -Scenario $Scenario -Action $firstAction -RuleKey 'first')
    }
    return [pscustomobject][ordered]@{
        contract_id = $(if ($null -ne $Contract) { [string]$Contract.contract_id } else { 'proxybridge-client-stage34' })
        executor = 'issue209'
        executable = $ExecutablePath
        arguments = $arguments.ToArray()
        operation_timeout_ms = $timeoutMs
        scenario_id = [string]$Scenario.scenario_id
        run_id = $RunId
        jsonl_path = $JsonlPath
        flows = $flows
        expected_records = @($flows) + @($heldRecheck)
    }
}

function New-ClientPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$JsonlPath,
        $Contract,
        [string]$ExpectedSha256 = '',
        [int]$ActualPathTimeoutMs = 2000,
        [int]$OperationTimeoutCapMs = [int]::MaxValue,
        [int]$ProcessExitGraceMs = 2000
    )
    if ($ActualPathTimeoutMs -lt 1) { throw 'CLIENT_ACTUAL_PATH_TIMEOUT_INVALID' }
    if ($OperationTimeoutCapMs -lt 1) { throw 'CLIENT_OPERATION_TIMEOUT_CAP_INVALID' }
    if ($ProcessExitGraceMs -lt 1) { throw 'CLIENT_PROCESS_EXIT_GRACE_INVALID' }
    $mode = ([string]$Scenario.client.mode).ToLowerInvariant()
    if ($null -ne $Contract -and $null -eq $Contract.modes.PSObject.Properties[$mode]) { throw "CLIENT_CONTRACT_MODE_MISSING_$($mode.ToUpperInvariant())" }
    $plan = switch ($mode) {
        'base' { New-BaseClientPlan -Scenario $Scenario -ExecutablePath $ExecutablePath -RunId $RunId -JsonlPath $JsonlPath -Contract $Contract }
        'issue206' { New-Issue206ClientPlan -Scenario $Scenario -ExecutablePath $ExecutablePath -RunId $RunId -JsonlPath $JsonlPath -Contract $Contract }
        'issue209' { New-Issue209ClientPlan -Scenario $Scenario -ExecutablePath $ExecutablePath -RunId $RunId -JsonlPath $JsonlPath -Contract $Contract }
        default { throw "CLIENT_EXECUTOR_NOT_IMPLEMENTED: $mode" }
    }
    $operationTimeoutMs = [Math]::Min([int]$plan.operation_timeout_ms, $OperationTimeoutCapMs)
    Set-ClientOperationTimeoutArgument -Plan $plan -OperationTimeoutMs $operationTimeoutMs
    $operationCount = if ($null -ne $plan.PSObject.Properties['operation_count']) {
        [int]$plan.operation_count
    } else {
        switch ([string]$plan.executor) { 'base' { 1 } 'issue206' { 2 } 'issue209' { 3 } default { throw 'CLIENT_TIMEOUT_BUDGET_EXECUTOR_UNSUPPORTED' } }
    }
    if ($operationCount -lt 1) { throw 'CLIENT_TIMEOUT_OPERATION_COUNT_INVALID' }
    $bindRetryCount = Get-ClientArgumentInt -Plan $plan -Name '--bind-retry-count'
    $bindRetryDelayMs = Get-ClientArgumentInt -Plan $plan -Name '--bind-retry-delay-ms'
    $interFlowWaitMs = $(if ($null -ne $plan.PSObject.Properties['additional_wait_budget_ms']) { [long]$plan.additional_wait_budget_ms } elseif ([string]$plan.executor -eq 'issue209') { Get-ClientArgumentInt -Plan $plan -Name '--inter-flow-wait-ms' } else { 0 })
    $operationBudgetMs = [long]$operationCount * [long]$operationTimeoutMs
    $bindRetryBudgetMs = [long]$bindRetryCount * [long]$bindRetryDelayMs
    $processTimeoutMs = $operationBudgetMs + $bindRetryBudgetMs + [long]$interFlowWaitMs + [long]$ProcessExitGraceMs
    if ($processTimeoutMs -gt $script:MaxClientProcessTimeoutMs -or $processTimeoutMs -gt [int]::MaxValue) { throw 'CLIENT_PROCESS_TIMEOUT_BUDGET_EXCEEDED' }
    if ($processTimeoutMs -le $operationTimeoutMs) { throw 'CLIENT_PROCESS_TIMEOUT_NOT_GREATER_THAN_OPERATION_TIMEOUT' }
    $plan.operation_timeout_ms = $operationTimeoutMs
    $plan | Add-Member -NotePropertyName process_timeout_ms -NotePropertyValue ([int]$processTimeoutMs)
    $plan | Add-Member -NotePropertyName process_exit_grace_ms -NotePropertyValue $ProcessExitGraceMs
    $plan | Add-Member -NotePropertyName timeout_budget_components -NotePropertyValue ([pscustomobject][ordered]@{
        operation_count = $operationCount
        operation_timeout_ms = $operationTimeoutMs
        operation_budget_ms = $operationBudgetMs
        bind_retry_count = $bindRetryCount
        bind_retry_delay_ms = $bindRetryDelayMs
        bind_retry_budget_ms = $bindRetryBudgetMs
        inter_flow_wait_ms = $interFlowWaitMs
        process_exit_grace_ms = $ProcessExitGraceMs
        total_ms = $processTimeoutMs
        maximum_ms = $script:MaxClientProcessTimeoutMs
    })
    $plan | Add-Member -NotePropertyName expected_sha256 -NotePropertyValue $ExpectedSha256
    $plan | Add-Member -NotePropertyName actual_path_timeout_ms -NotePropertyValue $ActualPathTimeoutMs
    if ($null -ne $plan.PSObject.Properties['child_process_plans']) {
        foreach ($childPlan in @($plan.child_process_plans)) {
            $childPlan | Add-Member -NotePropertyName process_timeout_ms -NotePropertyValue ([int]$processTimeoutMs)
            $childPlan | Add-Member -NotePropertyName actual_path_timeout_ms -NotePropertyValue $ActualPathTimeoutMs
        }
    }
    return $plan
}

function ConvertFrom-ClientJsonLines {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $records.Add(($line | ConvertFrom-Json)) }
        catch { throw "CLIENT_JSONL_INVALID: $($_.Exception.Message)" }
    }
    return $records.ToArray()
}

function Import-ClientJsonLinesFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'CLIENT_JSONL_NOT_FOUND' }
    return @(ConvertFrom-ClientJsonLines -Lines @([System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path))))
}

function ConvertTo-ClientEvidenceTimestamp {
    param($Value)
    if ($Value -is [datetimeoffset]) { return ([datetimeoffset]$Value).UtcDateTime.ToString('o') }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('o') }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Value, [ref]$parsed)) { throw 'CLIENT_EVIDENCE_TIMESTAMP_INVALID' }
    return $parsed.UtcDateTime.ToString('o')
}

function ConvertTo-CanonicalClientEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)]$Record)
    process {
        $raw = $Record
        if ($Record -is [string]) {
            if ([string]::IsNullOrWhiteSpace([string]$Record)) { throw 'CLIENT_JSONL_EMPTY_RECORD' }
            try { $raw = [string]$Record | ConvertFrom-Json }
            catch { throw "CLIENT_JSONL_INVALID: $($_.Exception.Message)" }
        }
        foreach ($field in @(
            'timestamp_utc','test_id','run_id','mode','sequence','phase','expected_action','expect','family','protocol',
            'tcp_peer_policy','udp_mode','close_mode','requested_local_ip','requested_local_port','actual_local_ip',
            'actual_local_port','requested_remote_ip','requested_remote_port','actual_remote_ip','actual_remote_port',
            'wsa_error','bytes_sent','bytes_received','payload_sha256','response_sha256','timing_ms','expected_result','actual_result'
        )) {
            if ($null -eq $raw.PSObject.Properties[$field]) { throw "CLIENT_EVIDENCE_MISSING_$($field.ToUpperInvariant())" }
        }
        $phase = ([string]$raw.phase).ToLowerInvariant()
        $mode = ([string]$raw.mode).ToLowerInvariant()
        $recordKind = 'flow'
        $flowIndex = -1
        if ($phase -match '^stream_([1-9][0-9]*)$') {
            if ($mode -ne 'single') { throw 'CLIENT_EVIDENCE_STREAM_MODE_MISMATCH' }
            $streamSequence = [int]$Matches[1]
            if ($streamSequence -ne [int]$raw.sequence) { throw 'CLIENT_EVIDENCE_STREAM_SEQUENCE_MISMATCH' }
            $flowIndex = $streamSequence - 1
        } elseif ($phase -match '^parallel_([1-9][0-9]*)$') {
            if ($mode -ne 'single') { throw 'CLIENT_EVIDENCE_PARALLEL_MODE_MISMATCH' }
            $parallelSequence = [int]$Matches[1]
            if ($parallelSequence -ne [int]$raw.sequence -or $parallelSequence -gt 32) { throw 'CLIENT_EVIDENCE_PARALLEL_SEQUENCE_MISMATCH' }
            $flowIndex = $parallelSequence - 1
        } elseif ($phase -match '^process_([1-8])$') {
            if ($mode -ne 'single') { throw 'CLIENT_EVIDENCE_PROCESS_MODE_MISMATCH' }
            $processSequence = [int]$Matches[1]
            if ($processSequence -ne [int]$raw.sequence) { throw 'CLIENT_EVIDENCE_PROCESS_SEQUENCE_MISMATCH' }
            $flowIndex = $processSequence - 1
        } elseif ($phase -match '^reconnect_([1-9]|[12][0-9]|3[0-2])$') {
            if ($mode -ne 'single') { throw 'CLIENT_EVIDENCE_RECONNECT_MODE_MISMATCH' }
            $reconnectSequence = [int]$Matches[1]
            if ($reconnectSequence -ne [int]$raw.sequence) { throw 'CLIENT_EVIDENCE_RECONNECT_SEQUENCE_MISMATCH' }
            $flowIndex = $reconnectSequence - 1
        } else {
            switch ($phase) {
                'single' { if ($mode -ne 'single') { throw 'CLIENT_EVIDENCE_SINGLE_MODE_MISMATCH' }; $flowIndex = 0 }
                'first_flow' { $flowIndex = 0 }
                'second_flow' { $flowIndex = 1 }
                'held_recheck' { $recordKind = 'held_recheck'; $flowIndex = 0 }
                default { throw "CLIENT_EVIDENCE_PHASE_UNSUPPORTED: $phase" }
            }
        }
        $actualResult = [string]$raw.actual_result
        $clientPass = $actualResult -match '^pass(?::|$)'
        $noResponse = $clientPass -and $actualResult -match '^pass:no_echo_' -and [long]$raw.bytes_received -eq 0 -and [string]::IsNullOrEmpty([string]$raw.response_sha256)
        $canonical = [pscustomobject][ordered]@{
            raw_record=$raw; record_kind=$recordKind; flow_index=$flowIndex
            timestamp_utc=(ConvertTo-ClientEvidenceTimestamp $raw.timestamp_utc); test_id=[string]$raw.test_id; run_id=[string]$raw.run_id
            mode=$mode; sequence=[int]$raw.sequence; phase=$phase
            expected_action=([string]$raw.expected_action).ToUpperInvariant(); expected_outcome=([string]$raw.expect).ToLowerInvariant()
            family=[string]$raw.family; protocol=([string]$raw.protocol).ToUpperInvariant()
            tcp_peer_policy=[string]$raw.tcp_peer_policy; udp_mode=[string]$raw.udp_mode; close_mode=[string]$raw.close_mode
            requested_local_ip=[string]$raw.requested_local_ip; requested_local_port=[int]$raw.requested_local_port
            actual_local_ip=[string]$raw.actual_local_ip; actual_local_port=[int]$raw.actual_local_port
            remote_ip=[string]$raw.requested_remote_ip; remote_port=[int]$raw.requested_remote_port
            actual_remote_ip=[string]$raw.actual_remote_ip; actual_remote_port=[int]$raw.actual_remote_port
            wsa_error=[int]$raw.wsa_error; bytes_sent=[long]$raw.bytes_sent; bytes_received=[long]$raw.bytes_received
            payload_sha256=[string]$raw.payload_sha256; response_sha256=[string]$raw.response_sha256; timing_ms=[long]$raw.timing_ms
            expected_result=[string]$raw.expected_result; actual_result=$actualResult
            no_response=[bool]$noResponse; client_pass=[bool]$clientPass
        }
        if ($null -ne $raw.PSObject.Properties['requested_remote_host']) {
            $canonical | Add-Member -NotePropertyName remote_host -NotePropertyValue ([string]$raw.requested_remote_host)
        }
        if ($null -ne $raw.PSObject.Properties['endpoint_behavior']) {
            $canonical | Add-Member -NotePropertyName endpoint_behavior -NotePropertyValue ([string]$raw.endpoint_behavior)
        }
        if ($null -ne $raw.PSObject.Properties['behavior_delay_ms']) {
            $canonical | Add-Member -NotePropertyName behavior_delay_ms -NotePropertyValue ([int]$raw.behavior_delay_ms)
        }
        if ($null -ne $raw.PSObject.Properties['response_count']) {
            $canonical | Add-Member -NotePropertyName response_count -NotePropertyValue ([int]$raw.response_count)
        }
        if ($null -ne $raw.PSObject.Properties['response_order']) {
            $canonical | Add-Member -NotePropertyName response_order -NotePropertyValue ([int]$raw.response_order)
        }
        if ($null -ne $raw.PSObject.Properties['process_id']) {
            $canonical | Add-Member -NotePropertyName process_id -NotePropertyValue ([int]$raw.process_id)
        }
        if ($null -ne $raw.PSObject.Properties['socket_id']) {
            $canonical | Add-Member -NotePropertyName socket_id -NotePropertyValue ([long]$raw.socket_id)
        }
        $canonical
    }
}

function Invoke-ClientPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$ProcessAdapter,
        [switch]$AllowProductRuntime
    )

    if ($null -eq $ProcessAdapter.PSObject.Properties['VerifyExecutable']) { throw 'CLIENT_ADAPTER_MISSING_VERIFY_EXECUTABLE' }
    if ($null -eq $Plan.PSObject.Properties['expected_sha256'] -or [string]$Plan.expected_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'CLIENT_PRELAUNCH_EXPECTED_HASH_INVALID' }
    $prelaunch = & $ProcessAdapter.VerifyExecutable ([string]$Plan.executable) ([string]$Plan.expected_sha256)
    if (-not [bool]$prelaunch.path_verified) { throw 'CLIENT_PRELAUNCH_PATH_MISSING' }
    if (-not [bool]$prelaunch.hash_verified) {
        if ([string]$prelaunch.status -eq 'HASH_MISMATCH') { throw 'CLIENT_PRELAUNCH_HASH_MISMATCH' }
        throw 'CLIENT_PRELAUNCH_HASH_VERIFICATION_FAILED'
    }

    if ($null -ne $Plan.PSObject.Properties['child_process_plans'] -and @($Plan.child_process_plans).Count -gt 1) {
        $processResults = @(Invoke-ConcurrentProcessPlans -Plans @($Plan.child_process_plans) -ProcessAdapter $ProcessAdapter -AllowProductRuntime:$AllowProductRuntime)
        $rawRecords = [System.Collections.Generic.List[object]]::new()
        $canonicalRecords = [System.Collections.Generic.List[object]]::new()
        $actualPathRequired = $false
        $expectedPath = [System.IO.Path]::GetFullPath([string]$Plan.executable).TrimEnd('\')
        for ($processIndex = 0; $processIndex -lt $processResults.Count; $processIndex++) {
            $processResult = $processResults[$processIndex]
            $probeStatus = [string]$processResult.actual_path_probe_status
            if ($probeStatus -eq 'QUERY_TIMEOUT') { throw 'CLIENT_PATH_QUERY_TIMEOUT' }
            if ($probeStatus -eq 'PATH_OBTAINED') {
                $actualPathRequired = $true
                try { $actualPath = [System.IO.Path]::GetFullPath([string]$processResult.actual_path).TrimEnd('\') }
                catch { throw 'CLIENT_PATH_VERIFICATION_FAILED' }
                if (-not [string]::Equals($expectedPath, $actualPath, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'CLIENT_PATH_VERIFICATION_FAILED' }
            } elseif ($probeStatus -ne 'PROCESS_EXITED') { throw 'CLIENT_PATH_PROBE_STATUS_INVALID' }
            if (-not [bool]$processResult.timed_out) {
                $childRecords = @(Import-ClientJsonLinesFile -Path ([string]$Plan.child_process_plans[$processIndex].jsonl_path))
                if ($childRecords.Count -ne 1) { throw 'CLIENT_PROCESS_RECORD_COUNT_INVALID' }
                if ($null -eq $childRecords[0].PSObject.Properties['process_id'] -or [int]$childRecords[0].process_id -ne [int]$processResult.pid) { throw 'CLIENT_PROCESS_IDENTITY_MISMATCH' }
                $rawRecords.Add($childRecords[0])
                $canonicalRecords.Add(($childRecords[0] | ConvertTo-CanonicalClientEvidence))
            }
        }
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $combinedLines = @($rawRecords | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 })
        [System.IO.File]::WriteAllLines([string]$Plan.jsonl_path, $combinedLines, $utf8NoBom)
        $timedOut = @($processResults | Where-Object { [bool]$_.timed_out }).Count -gt 0
        $nonzero = @($processResults | Where-Object { [int]$_.exit_code -ne 0 } | Select-Object -First 1)
        $exitCode = $(if ($timedOut) { -1 } elseif ($nonzero.Count -gt 0) { [int]$nonzero[0].exit_code } else { 0 })
        return [pscustomobject][ordered]@{
            exit_code=$exitCode; timed_out=$timedOut; pid=[int]$processResults[0].pid
            pids=@($processResults | ForEach-Object { [int]$_.pid }); actual_path=[string]$processResults[0].actual_path
            prelaunch_path_verified=[bool]$prelaunch.path_verified; prelaunch_hash_verified=[bool]$prelaunch.hash_verified
            actual_path_probe_status='MULTI_PROCESS'; actual_path_probe_attempts=[int](($processResults | Measure-Object -Property actual_path_probe_attempts -Sum).Sum)
            actual_path_probe_elapsed_ms=[int](($processResults | Measure-Object -Property actual_path_probe_elapsed_ms -Maximum).Maximum)
            actual_path_required=[bool]$actualPathRequired; process_results=$processResults
            stdout=(@($processResults.stdout) -join [Environment]::NewLine); stderr=(@($processResults.stderr) -join [Environment]::NewLine)
            raw_records=$rawRecords.ToArray(); canonical_records=$canonicalRecords.ToArray(); records=$canonicalRecords.ToArray()
            jsonl_path=[string]$Plan.jsonl_path; run_mode=$(if ([bool]$ProcessAdapter.is_mock) { 'mock' } else { 'real' })
        }
    }

    $processResult = Invoke-ProcessPlan -Plan $Plan -ProcessAdapter $ProcessAdapter -AllowProductRuntime:$AllowProductRuntime
    $probeStatus = [string]$processResult.actual_path_probe_status
    $actualPathRequired = $probeStatus -ne 'PROCESS_EXITED'
    if ($probeStatus -eq 'QUERY_TIMEOUT') { throw 'CLIENT_PATH_QUERY_TIMEOUT' }
    if ($probeStatus -eq 'PATH_OBTAINED') {
        try {
            $expectedPath = [System.IO.Path]::GetFullPath([string]$Plan.executable).TrimEnd('\')
            $actualPath = [System.IO.Path]::GetFullPath([string]$processResult.actual_path).TrimEnd('\')
            if (-not [string]::Equals($expectedPath, $actualPath, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'CLIENT_PATH_VERIFICATION_FAILED' }
        }
        catch {
            if ($_.Exception.Message -eq 'CLIENT_PATH_VERIFICATION_FAILED') { throw }
            throw 'CLIENT_PATH_VERIFICATION_FAILED'
        }
    }
    elseif ($probeStatus -ne 'PROCESS_EXITED') { throw 'CLIENT_PATH_PROBE_STATUS_INVALID' }

    $rawRecords = @()
    $canonicalRecords = @()
    if (-not [bool]$processResult.timed_out) {
        $rawRecords = @(Import-ClientJsonLinesFile -Path $Plan.jsonl_path)
        $canonicalRecords = @($rawRecords | ConvertTo-CanonicalClientEvidence)
    }
    return [pscustomobject][ordered]@{
        exit_code = [int]$processResult.exit_code
        timed_out = [bool]$processResult.timed_out
        pid = [int]$processResult.pid
        actual_path = [string]$processResult.actual_path
        prelaunch_path_verified = [bool]$prelaunch.path_verified
        prelaunch_hash_verified = [bool]$prelaunch.hash_verified
        actual_path_probe_status = $probeStatus
        actual_path_probe_attempts = [int]$processResult.actual_path_probe_attempts
        actual_path_probe_elapsed_ms = [int]$processResult.actual_path_probe_elapsed_ms
        actual_path_required = [bool]$actualPathRequired
        stdout = [string]$processResult.stdout
        stderr = [string]$processResult.stderr
        raw_records = $rawRecords
        canonical_records = $canonicalRecords
        records = $canonicalRecords
        jsonl_path = [string]$Plan.jsonl_path
        run_mode = $(if ([bool]$ProcessAdapter.is_mock) { 'mock' } else { 'real' })
    }
}

Export-ModuleMember -Function Import-ClientContract, New-BaseClientPlan, New-Issue206ClientPlan, New-Issue209ClientPlan, New-ClientPlan, ConvertFrom-ClientJsonLines, Import-ClientJsonLinesFile, ConvertTo-CanonicalClientEvidence, Invoke-ClientPlan
