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

    $productErrors = [System.Collections.Generic.List[string]]::new()
    $harnessErrors = [System.Collections.Generic.List[string]]::new()
    $missingEvidence = [System.Collections.Generic.List[string]]::new()
    $contamination = [System.Collections.Generic.List[string]]::new()
    if ([bool]$ClientResult.timed_out) { $harnessErrors.Add('client timeout') }
    if ([int]$ClientResult.exit_code -ne 0) { $harnessErrors.Add("client exit code $($ClientResult.exit_code)") }

    $clientRecords = @()
    if ($null -ne $ClientResult.PSObject.Properties['canonical_records']) { $clientRecords = @($ClientResult.canonical_records) }
    elseif ($null -ne $ClientResult.PSObject.Properties['records']) { $clientRecords = @($ClientResult.records) }
    $flows = @($clientRecords | Where-Object { [string]$_.record_kind -eq 'flow' } | Sort-Object { [int]$_.flow_index })
    $heldRechecks = @($clientRecords | Where-Object { [string]$_.record_kind -eq 'held_recheck' })
    $expectedFlows = @($ClientPlan.flows | Sort-Object { [int]$_.flow_index })
    if ($flows.Count -ne $expectedFlows.Count) { $harnessErrors.Add("flow count actual=$($flows.Count) expected=$($expectedFlows.Count)") }
    if ([string]$Scenario.client.mode -eq 'issue209' -and $heldRechecks.Count -ne 1) { $harnessErrors.Add("issue209 held_recheck count actual=$($heldRechecks.Count) expected=1") }
    elseif ([string]$Scenario.client.mode -ne 'issue209' -and $heldRechecks.Count -gt 0) { $harnessErrors.Add('unexpected held_recheck record') }
    if (-not (Test-EvidenceIdentity -Records $clientRecords -RunId ([string]$ClientPlan.run_id) -ScenarioId ([string]$Scenario.scenario_id))) { $contamination.Add('client evidence identity mismatch') }
    if (-not (Test-EvidenceIdentity -Records $VpsRecords -RunId ([string]$ClientPlan.run_id) -ScenarioId ([string]$Scenario.scenario_id))) { $contamination.Add('VPS evidence identity mismatch') }

    $vpsComplete = [bool](Get-AssertionContextValue $EvidenceContext 'vps_capture_complete' $false)
    $vpsCompleteShas = @((Get-AssertionContextValue $EvidenceContext 'vps_capture_complete_shas' @()) | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $proxyBridgeComplete = [bool](Get-AssertionContextValue $EvidenceContext 'proxybridge_capture_complete' $false)
    $directEgress = [string](Get-AssertionContextValue $EvidenceContext 'direct_egress_ip' '')
    $proxyEgress = [string](Get-AssertionContextValue $EvidenceContext 'proxy_egress_ip' '')
    $expectedProcess = [string](Get-AssertionContextValue $EvidenceContext 'expected_process' '')
    $expectedPid = $(if ($null -ne $ClientResult.PSObject.Properties['pid']) { [int]$ClientResult.pid } else { 0 })
    $startTime = Get-AssertionContextValue $EvidenceContext 'start_time_utc' ([datetime]::MinValue)
    $endTime = Get-AssertionContextValue $EvidenceContext 'end_time_utc' ([datetime]::MaxValue)

    foreach ($record in $clientRecords) {
        $label = $(if ([string]$record.record_kind -eq 'held_recheck') { 'held_recheck' } else { "flow $([int]$record.flow_index)" })
        $expected = $null
        if ([string]$record.record_kind -eq 'held_recheck') { $expected = @($expectedFlows | Where-Object { [int]$_.flow_index -eq 0 }) | Select-Object -First 1 }
        else { $expected = @($expectedFlows | Where-Object { [int]$_.flow_index -eq [int]$record.flow_index }) | Select-Object -First 1 }
        if ($null -eq $expected) { $harnessErrors.Add("$label has no plan expectation"); continue }

        $missingClientField = $false
        foreach ($required in @('protocol','expected_action','expected_outcome','actual_local_ip','actual_local_port','remote_ip','remote_port','actual_remote_ip','actual_remote_port','payload_sha256','response_sha256','no_response','client_pass')) {
            if ($null -eq $record.PSObject.Properties[$required]) { $harnessErrors.Add("$label missing $required"); $missingClientField = $true }
        }
        if ($missingClientField) { continue }
        if ([string]$record.payload_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { $harnessErrors.Add("$label payload SHA invalid"); continue }
        if (-not [string]::Equals([string]$record.protocol, [string]$expected.protocol, [System.StringComparison]::OrdinalIgnoreCase)) { $harnessErrors.Add("$label protocol does not match plan") }
        if ([string]$record.expected_action -ne [string]$expected.expected_action) { $harnessErrors.Add("$label expected action does not match plan") }
        if ([string]$record.expected_outcome -ne [string]$expected.expected_outcome) { $harnessErrors.Add("$label expectation does not match plan") }
        if ($null -ne $expected.PSObject.Properties['tcp_peer_policy'] -and [string]$expected.protocol -eq 'TCP' -and [string]$record.tcp_peer_policy -ne [string]$expected.tcp_peer_policy) { $harnessErrors.Add("$label TCP peer policy does not match plan") }
        if ([string]$record.remote_ip -ne [string]$expected.remote_ip -or [int]$record.remote_port -ne [int]$expected.remote_port -or [string]$record.actual_remote_ip -ne [string]$expected.remote_ip -or [int]$record.actual_remote_port -ne [int]$expected.remote_port) { $productErrors.Add("$label wrong destination") }
        if ([string]$expected.expected_outcome -eq 'echo') {
            if ([string]$record.payload_sha256 -ne [string]$record.response_sha256 -or [bool]$record.no_response) { $productErrors.Add("$label echo mismatch") }
        }
        else {
            if (-not [bool]$record.no_response -or -not [string]::IsNullOrEmpty([string]$record.response_sha256)) { $productErrors.Add("$label unexpected response") }
        }
        if (-not [bool]$record.client_pass) { $productErrors.Add("$label client result failed") }

        $sameDestination = @(Find-ProxyBridgeFlowEvidence -Records $ProxyBridgeRecords -Process $expectedProcess -Pid $expectedPid -DestinationIp ([string]$expected.remote_ip) -DestinationPort ([int]$expected.remote_port) -StartTimeUtc $startTime -EndTimeUtc $endTime)
        $expectedRoute = @($sameDestination | Where-Object { [string]$_.action -eq [string]$expected.expected_action })
        $contradictoryRoute = @($sameDestination | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.action) -and [string]$_.action -ne [string]$expected.expected_action })
        if ($sameDestination.Count -eq 0) { $missingEvidence.Add("$label ProxyBridge route evidence") }
        elseif ($expectedRoute.Count -eq 0 -or $contradictoryRoute.Count -gt 0) { $productErrors.Add("$label wrong ProxyBridge action") }
        elseif ($null -ne $expected.PSObject.Properties['expected_proxy_config_id']) {
            foreach ($routeRecord in $expectedRoute) {
                if ($null -ne $routeRecord.PSObject.Properties['proxy_config_id'] -and [int]$routeRecord.proxy_config_id -ne [int]$expected.expected_proxy_config_id) { $productErrors.Add("$label wrong proxy config") }
            }
        }

        $expectedReceived = $(if ([string]$expected.expected_action -eq 'BLOCK') { 0 } else { 1 })
        $expectedEchoed = $(if ([string]$expected.expected_outcome -eq 'echo' -and [string]$expected.expected_action -ne 'BLOCK') { 1 } else { 0 })
        $route = $(if ([string]$expected.expected_action -eq 'DIRECT') { 'DIRECT' } elseif ([string]$expected.expected_action -eq 'PROXY') { 'PROXY' } else { '' })
        $vpsResult = Test-VpsPayloadEvidence -Records $VpsRecords -Sha256 ([string]$record.payload_sha256) -Protocol ([string]$expected.protocol) -ExpectedReceived $expectedReceived -ExpectedEchoed $expectedEchoed -ExpectedDestinationPort ([int]$expected.remote_port) -ExpectedRoute $route -DirectEgressIp $directEgress -ProxyEgressIp $proxyEgress
        $shaCaptureComplete = $vpsComplete
        if ($vpsCompleteShas.Count -gt 0) { $shaCaptureComplete = $vpsCompleteShas -contains ([string]$record.payload_sha256).ToLowerInvariant() }
        if ([string]$expected.expected_action -eq 'BLOCK') {
            $blockPayloadEvents = @($vpsResult.matches | Where-Object { [string]$_.event -in @('MESSAGE_RECEIVED','RECEIVED','ECHOED') })
            if ($blockPayloadEvents.Count -gt 0) { $productErrors.Add("$label block leak") }
            elseif (-not $shaCaptureComplete) { $missingEvidence.Add("$label complete VPS capture") }
        }
        elseif ($vpsResult.received -eq 0) { $missingEvidence.Add("$label VPS payload evidence") }
        elseif (-not $vpsResult.passed) {
            foreach ($error in @($vpsResult.errors)) { $productErrors.Add("$label $error") }
        }
    }

    if ($expectedFlows.Count -ge 2 -and $flows.Count -ge 2) {
        if ([string]$Scenario.client.mode -eq 'issue206' -and ([string]$flows[0].actual_local_ip -ne [string]$flows[1].actual_local_ip -or [int]$flows[0].actual_local_port -ne [int]$flows[1].actual_local_port)) { $productErrors.Add('same local IP/port reuse') }
        if ([string]$Scenario.client.mode -eq 'issue209') {
            if ([int]$flows[0].actual_local_port -ne [int]$flows[1].actual_local_port) { $productErrors.Add('issue209 same numeric local port reuse') }
            if ([string]$flows[0].protocol -eq [string]$flows[1].protocol) { $harnessErrors.Add('issue209 opposite protocol was not exercised') }
            if ($heldRechecks.Count -eq 1) {
                $held = $heldRechecks[0]
                if ([int]$held.actual_local_port -ne [int]$flows[0].actual_local_port) { $harnessErrors.Add('issue209 held_recheck local port mismatch') }
                if ([int]$held.flow_index -ne 0) { $harnessErrors.Add('issue209 held_recheck does not reference first flow') }
            }
        }
    }
    if (-not $proxyBridgeComplete -and $expectedFlows.Count -gt 0) { $missingEvidence.Add('complete ProxyBridge capture') }

    $outcome = 'PASS'
    if ($contamination.Count -gt 0) { $outcome = 'CONTAMINATED' }
    elseif ($harnessErrors.Count -gt 0) { $outcome = 'FAIL_HARNESS' }
    elseif ($productErrors.Count -gt 0) { $outcome = 'FAIL_PRODUCT' }
    elseif ($missingEvidence.Count -gt 0) { $outcome = 'HOLD_AMBIGUOUS' }
    $allErrors = @($productErrors.ToArray()) + @($harnessErrors.ToArray()) + @($missingEvidence.ToArray()) + @($contamination.ToArray())
    return [pscustomobject][ordered]@{
        passed=($outcome -eq 'PASS'); outcome=$outcome
        product_errors=@($productErrors | Sort-Object -Unique)
        harness_errors=@($harnessErrors | Sort-Object -Unique)
        missing_evidence=@($missingEvidence | Sort-Object -Unique)
        contamination=@($contamination | Sort-Object -Unique)
        errors=@($allErrors | Sort-Object -Unique)
        run_mode=$RunMode
    }
}

function Get-ClassifiedStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$AssertionResult,
        $KnownDefect,
        [ValidateSet('mock', 'real')][string]$RunMode,
        [string]$MockExpectation = 'PASS'
    )
    if ($RunMode -eq 'mock') {
        switch ([string]$AssertionResult.outcome) {
            'PASS' { return 'MOCK_PASS' }
            'HOLD_AMBIGUOUS' { return 'MOCK_HOLD' }
            'FAIL_PRODUCT' {
                if ($null -ne $KnownDefect -or $MockExpectation -eq 'EXPECTED_FAIL') { return 'MOCK_EXPECTED_FAIL' }
                return 'MOCK_HOLD'
            }
            default { return 'MOCK_HOLD' }
        }
    }
    if ([string]$AssertionResult.outcome -eq 'FAIL_PRODUCT' -and $null -ne $KnownDefect) { return 'EXPECTED_FAIL' }
    return [string]$AssertionResult.outcome
}

function Test-ShouldStopRun {
    [CmdletBinding()]
    param([string]$Status, $Suite, [int]$ConsecutiveProductFailures, [bool]$Independent = $true)
    switch ($Status) {
        'FAIL_HARNESS' { return [bool]$Suite.execution.stop_on_harness_failure }
        'FAIL_INFRASTRUCTURE' { return [bool]$Suite.execution.stop_on_infrastructure_failure }
        'CONTAMINATED' { return [bool]$Suite.execution.stop_on_state_contamination }
        'FAIL_PRODUCT' { return ((-not [bool]$Suite.execution.continue_on_product_failure) -or $ConsecutiveProductFailures -ge [int]$Suite.execution.max_consecutive_product_failures) }
        'EXPECTED_FAIL' { return (-not [bool]$Suite.execution.continue_on_expected_failure) }
        'HOLD_AMBIGUOUS' { return ((-not [bool]$Suite.execution.continue_on_ambiguous_hold) -or -not $Independent) }
        default { return $false }
    }
}

Export-ModuleMember -Function Test-ScenarioAssertions, Get-ClassifiedStatus, Test-ShouldStopRun
