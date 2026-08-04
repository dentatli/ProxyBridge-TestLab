Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProcessAdapter.psm1')
Import-Module (Join-Path $PSScriptRoot 'ClientRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProxyBridgeEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'VpsEvidence.psm1')

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-MockPlanValue {
    param($ClientPlan, [int]$FlowIndex, [string]$Name)
    $flow = @($ClientPlan.flows | Where-Object { [int]$_.flow_index -eq $FlowIndex }) | Select-Object -First 1
    if ($null -eq $flow) { return '' }
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
    $fixtureDirectory = Join-Path $FixtureRoot ([string]$Scenario.mock_fixture_id)
    if (-not (Test-Path -LiteralPath $fixtureDirectory -PathType Container)) { throw "MOCK_FIXTURE_NOT_FOUND: $($Scenario.mock_fixture_id)" }
    if (-not (Test-Path -LiteralPath $EvidenceDirectory)) { $null = New-Item -ItemType Directory -Path $EvidenceDirectory -Force }

    $flow0Sha = '1111111111111111111111111111111111111111111111111111111111111111'
    $flow1Sha = '2222222222222222222222222222222222222222222222222222222222222222'
    $flow2Sha = '3333333333333333333333333333333333333333333333333333333333333333'
    $protocol0 = Get-MockPlanValue $ClientPlan 0 'protocol'
    $protocol1 = Get-MockPlanValue $ClientPlan 1 'protocol'
    $action0 = Get-MockPlanValue $ClientPlan 0 'expected_action'
    $action1 = Get-MockPlanValue $ClientPlan 1 'expected_action'
    $expect0 = Get-MockPlanValue $ClientPlan 0 'expected_outcome'
    $expect1 = Get-MockPlanValue $ClientPlan 1 'expected_outcome'
    $variables = @{
        TIMESTAMP='2030-01-01T00:00:00Z'; PROCESS=[System.IO.Path]::GetFileName([string]$ClientPlan.executable)
        TEST_ID=[string]$Scenario.scenario_id; RUN_ID=[string]$ClientPlan.run_id; LOCAL_IP=[string]$Scenario.client.local_ip; LOCAL_PORT='32000'
        FLOW0_SHA=$flow0Sha; FLOW1_SHA=$flow1Sha; FLOW2_SHA=$flow2Sha
        MODE=$(if ([string]$ClientPlan.executor -eq 'base') { 'single' } else { [string]$ClientPlan.executor })
        FAMILY=('IPv' + [string]$Scenario.client.family)
        PROTOCOL0=$protocol0; PROTOCOL1=$protocol1
        ACTION0=$action0; ACTION1=$action1; EXPECT0=$expect0; EXPECT1=$expect1
        UDP_MODE0=$(if ($protocol0 -eq 'UDP') { [string](Get-MockObjectValue $Scenario.client 'socket_mode' 'connected') } else { 'n/a' })
        UDP_MODE1=$(if ($protocol1 -eq 'UDP') { [string](Get-MockObjectValue $Scenario.client 'socket_mode' 'connected') } else { 'n/a' })
        TCP_POLICY0=$(if ($protocol0 -eq 'TCP' -and $action0 -eq 'PROXY') { 'record-only' } elseif ($protocol0 -eq 'TCP') { 'exact' } else { 'n/a' })
        TCP_POLICY1=$(if ($protocol1 -eq 'TCP' -and $action1 -eq 'PROXY') { 'record-only' } elseif ($protocol1 -eq 'TCP') { 'exact' } else { 'n/a' })
        CLOSE_MODE=[string](Get-MockObjectValue $Scenario.client 'close_mode' 'graceful')
        RECEIVED_EVENT0=$(if ($protocol0 -eq 'UDP') { 'RECEIVED' } else { 'MESSAGE_RECEIVED' })
        RECEIVED_EVENT1=$(if ($protocol1 -eq 'UDP') { 'RECEIVED' } else { 'MESSAGE_RECEIVED' })
        REMOTE0_IP=(Get-MockPlanValue $ClientPlan 0 'remote_ip'); REMOTE0_PORT=(Get-MockPlanValue $ClientPlan 0 'remote_port')
        REMOTE1_IP=(Get-MockPlanValue $ClientPlan 1 'remote_ip'); REMOTE1_PORT=(Get-MockPlanValue $ClientPlan 1 'remote_port')
        DIRECT_EGRESS_IP='192.0.2.50'
        PROXY_EGRESS_IP='198.51.100.50'
    }
    $variables.REMOTE0_ENDPOINT = $(if ($variables.REMOTE0_IP -match ':') { "[$($variables.REMOTE0_IP)]:$($variables.REMOTE0_PORT)" } else { "$($variables.REMOTE0_IP):$($variables.REMOTE0_PORT)" })
    $variables.REMOTE1_ENDPOINT = $(if ($variables.REMOTE1_IP -match ':') { "[$($variables.REMOTE1_IP)]:$($variables.REMOTE1_PORT)" } else { "$($variables.REMOTE1_IP):$($variables.REMOTE1_PORT)" })

    $clientPath = [string]$ClientPlan.jsonl_path
    $proxyBridgePath = Join-Path $EvidenceDirectory 'proxybridge.log'
    $vpsPath = Join-Path $EvidenceDirectory 'vps.jsonl'
    Copy-ResolvedMockEvidence -Source (Join-Path $fixtureDirectory 'client.jsonl') -Destination $clientPath -Variables $variables
    Copy-ResolvedMockEvidence -Source (Join-Path $fixtureDirectory 'proxybridge.log') -Destination $proxyBridgePath -Variables $variables
    Copy-ResolvedMockEvidence -Source (Join-Path $fixtureDirectory 'vps.jsonl') -Destination $vpsPath -Variables $variables

    $processResult = [pscustomobject]@{
        exit_code=0; timed_out=$false; pid=4242; actual_path=[string]$ClientPlan.executable
        stdout='fixture human stdout (not JSONL)'; stderr=''
    }
    $processAdapter = New-MockProcessAdapter -InvokeResults @($processResult) -ActualPath ([string]$ClientPlan.executable)
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
