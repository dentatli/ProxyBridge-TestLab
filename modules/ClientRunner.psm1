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

    $arguments = [System.Collections.Generic.List[string]]::new()
    Add-ClientArgumentPair $arguments '--mode' 'single'
    Add-ClientArgumentPair $arguments '--family' $family
    Add-ClientArgumentPair $arguments '--protocol' $protocol
    if ($protocol -eq 'udp') { Add-ClientArgumentPair $arguments '--udp-mode' $udpMode }
    if ($protocol -eq 'tcp') { Add-ClientArgumentPair $arguments '--tcp-peer-policy' $tcpPeerPolicy }
    Add-ClientArgumentPair $arguments '--local-ip' (Get-ClientProperty $client 'local_ip' $null -Required)
    Add-ClientArgumentPair $arguments '--local-port' $localPort
    Add-ClientArgumentPair $arguments '--remote-ip' (Get-ClientProperty $client 'remote_ip' $null -Required)
    Add-ClientArgumentPair $arguments $(if ($protocol -eq 'tcp') { '--tcp-remote-port' } else { '--udp-remote-port' }) $remotePort
    Add-ClientArgumentPair $arguments '--expected-action' $expectedAction
    Add-ClientArgumentPair $arguments '--expect' $expect
    Add-ClientArgumentPair $arguments '--timeout-ms' $timeoutMs
    Add-ClientArgumentPair $arguments '--test-id' $Scenario.scenario_id
    Add-ClientArgumentPair $arguments '--run-id' $RunId
    Add-ClientArgumentPair $arguments '--jsonl-log' $JsonlPath

    $flow = [pscustomobject][ordered]@{
        flow_index = 0
        protocol = $protocol.ToUpperInvariant()
        expected_action = $expectedAction
        expected_outcome = $expect
        remote_ip = [string](Get-ClientProperty $client 'remote_ip' $null -Required)
        remote_port = $remotePort
        expected_proxy_config_id = Get-ExpectedProxyConfigId -Scenario $Scenario -Action $expectedAction -RuleKey 'primary'
    }
    return [pscustomobject][ordered]@{
        contract_id = $(if ($null -ne $Contract) { [string]$Contract.contract_id } else { 'proxybridge-client-stage34' })
        executor = 'base'
        executable = $ExecutablePath
        arguments = $arguments.ToArray()
        operation_timeout_ms = $timeoutMs
        scenario_id = [string]$Scenario.scenario_id
        run_id = $RunId
        jsonl_path = $JsonlPath
        flows = @($flow)
        expected_records = @($flow)
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
    $operationCount = switch ([string]$plan.executor) { 'base' { 1 } 'issue206' { 2 } 'issue209' { 3 } default { throw 'CLIENT_TIMEOUT_BUDGET_EXECUTOR_UNSUPPORTED' } }
    $bindRetryCount = $(if ([string]$plan.executor -eq 'base') { 0 } else { Get-ClientArgumentInt -Plan $plan -Name '--bind-retry-count' })
    $bindRetryDelayMs = $(if ([string]$plan.executor -eq 'base') { 0 } else { Get-ClientArgumentInt -Plan $plan -Name '--bind-retry-delay-ms' })
    $interFlowWaitMs = $(if ([string]$plan.executor -eq 'issue209') { Get-ClientArgumentInt -Plan $plan -Name '--inter-flow-wait-ms' } else { 0 })
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
        switch ($phase) {
            'single' { if ($mode -ne 'single') { throw 'CLIENT_EVIDENCE_SINGLE_MODE_MISMATCH' }; $flowIndex = 0 }
            'first_flow' { $flowIndex = 0 }
            'second_flow' { $flowIndex = 1 }
            'held_recheck' { $recordKind = 'held_recheck'; $flowIndex = 0 }
            default { throw "CLIENT_EVIDENCE_PHASE_UNSUPPORTED: $phase" }
        }
        $actualResult = [string]$raw.actual_result
        $clientPass = $actualResult -match '^pass(?::|$)'
        $noResponse = $clientPass -and $actualResult -match '^pass:no_echo_' -and [long]$raw.bytes_received -eq 0 -and [string]::IsNullOrEmpty([string]$raw.response_sha256)
        [pscustomobject][ordered]@{
            raw_record=$raw; record_kind=$recordKind; flow_index=$flowIndex
            timestamp_utc=[string]$raw.timestamp_utc; test_id=[string]$raw.test_id; run_id=[string]$raw.run_id
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
