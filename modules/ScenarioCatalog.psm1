Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Config.psm1')
Import-Module (Join-Path $PSScriptRoot 'Pairwise.psm1')

function Get-OptionalValue {
    param($Object, [string]$Name, $Default)
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Merge-UniqueStrings {
    param([object[]]$Sets)
    $values = [System.Collections.Generic.List[string]]::new()
    foreach ($set in $Sets) {
        foreach ($value in @($set)) {
            $text = [string]$value
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            if (-not $values.Contains($text)) { $values.Add($text) }
        }
    }
    return $values.ToArray()
}

function ConvertTo-CatalogScenario {
    param($Entry, $Defaults, [string]$CatalogId)
    if ($null -ne $Entry.PSObject.Properties['rule_set']) {
        if ($null -eq $Entry.PSObject.Properties['coverage_group']) { $Entry | Add-Member -NotePropertyName coverage_group -NotePropertyValue $CatalogId }
        return $Entry
    }

    $id = [string](Get-OptionalValue $Entry 'scenario_id' (Get-OptionalValue $Entry 'id' ''))
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Catalog '$CatalogId' contains an entry without id." }
    $protocol = ([string](Get-OptionalValue $Entry 'protocol' (Get-OptionalValue $Defaults 'protocol' 'TCP'))).ToUpperInvariant()
    $family = [int](Get-OptionalValue $Entry 'family' (Get-OptionalValue $Defaults 'family' 4))
    $action = ([string](Get-OptionalValue $Entry 'action' (Get-OptionalValue $Defaults 'action' 'DIRECT'))).ToUpperInvariant()
    $socketMode = [string](Get-OptionalValue $Entry 'socket_mode' (Get-OptionalValue $Defaults 'socket_mode' 'connected'))
    $selector = [string](Get-OptionalValue $Entry 'selector' (Get-OptionalValue $Defaults 'selector' 'basename'))
    $transition = [string](Get-OptionalValue $Entry 'transition' '')
    $coverageGroup = [string](Get-OptionalValue $Entry 'coverage_group' $CatalogId)
    $enabled = [bool](Get-OptionalValue $Entry 'enabled' (Get-OptionalValue $Defaults 'enabled' $true))
    $unsupportedStatus = [string](Get-OptionalValue $Entry 'unsupported_status' (Get-OptionalValue $Defaults 'unsupported_status' ''))
    $implementationStatus = ([string](Get-OptionalValue $Entry 'implementation_status' (Get-OptionalValue $Defaults 'implementation_status' 'DECLARATIVE_ONLY'))).ToUpperInvariant()
    if ($unsupportedStatus -eq 'UNSUPPORTED_PRODUCT_SCOPE') { $implementationStatus = 'UNSUPPORTED_PRODUCT_SCOPE' }
    $implementationReason = [string](Get-OptionalValue $Entry 'implementation_reason' (Get-OptionalValue $Defaults 'implementation_reason' ''))
    $mockFixtureId = [string](Get-OptionalValue $Entry 'mock_fixture_id' (Get-OptionalValue $Defaults 'mock_fixture_id' ''))
    $profileExpectation = [string](Get-OptionalValue $Entry 'profile_expectation' (Get-OptionalValue $Defaults 'profile_expectation' 'valid'))

    $protocolRequires = $(if ($protocol -eq 'BOTH') { @('tcp', 'udp') } else { @($protocol.ToLowerInvariant()) })
    $derivedRequires = @($(if ($family -eq 6) { 'ipv6' } else { 'ipv4' })) + @($protocolRequires)
    if ($protocol -eq 'UDP') { $derivedRequires += "${socketMode}_udp" }
    if ($action -eq 'PROXY' -or $transition -match 'PROXY') { $derivedRequires += 'socks5' }
    $derivedRequires += $(if ($selector -eq 'full-path') { 'process_full_path_rules' } else { 'process_basename_rules' })
    $requires = Merge-UniqueStrings -Sets @((Get-OptionalValue $Defaults 'requires' @()), (Get-OptionalValue $Entry 'requires' @()), $derivedRequires)
    $tags = Merge-UniqueStrings -Sets @((Get-OptionalValue $Defaults 'tags' @()), (Get-OptionalValue $Entry 'tags' @()), @($coverageGroup, $protocol.ToLowerInvariant(), "ipv$family", $action.ToLowerInvariant(), $socketMode, "selector-$selector"))

    $application = $(if ($selector -eq 'full-path') { '${PB_RULE_APPLICATION_FULLPATH}' } else { '${PB_RULE_APPLICATION_BASENAME}' })
    $host = $(if ($family -eq 6) { '${PB_VPS_IPV6}' } else { '${PB_VPS_IPV4}' })
    $localIp = $(if ($family -eq 6) { '${PB_VM_IPV6}' } else { '${PB_VM_IPV4}' })
    $targetKind = [string](Get-OptionalValue $Entry 'target_kind' 'ip')
    $ruleHost = $(if ($targetKind -eq 'domain') { '' } else { $host })
    $ruleDomains = $(if ($targetKind -eq 'domain') { @('${PB_TEST_DOMAIN}') } else { @('*') })
    $rulePorts = @([string](Get-OptionalValue $Entry 'port_expression' '${PB_ENDPOINT_A_PORT}'))
    $rules = [System.Collections.Generic.List[object]]::new()
    $transitionParts = @()
    if (-not [string]::IsNullOrWhiteSpace($transition)) {
        $transitionParts = @($transition -split '->')
        if ($transitionParts.Count -ne 2) { throw "Scenario '$id' has invalid transition." }
        for ($index = 0; $index -lt 2; $index++) {
            $ruleAction = $transitionParts[$index].ToUpperInvariant()
            $rules.Add([pscustomobject][ordered]@{
                rule_key=$(if ($index -eq 0) { 'first' } else { 'second' }); application=$application; host=$host
                ports=@($(if ($index -eq 0) { '${PB_ENDPOINT_B_PORT}' } else { '${PB_ENDPOINT_A_PORT}' })); domains=@('*')
                protocol=$protocol; action=$ruleAction; proxy_config_id=$(if ($ruleAction -eq 'PROXY') { '${PB_SOCKS_PROXY_CONFIG_ID}' } else { 0 }); enabled=$true
            })
        }
    }
    elseif ($implementationStatus -ne 'UNSUPPORTED_PRODUCT_SCOPE') {
        $proxyConfigId = $(if ($action -eq 'PROXY') { '${PB_SOCKS_PROXY_CONFIG_ID}' } else { 0 })
        if ($profileExpectation -eq 'invalid-missing-proxy-config') { $proxyConfigId = 999 }
        $rules.Add([pscustomobject][ordered]@{
            rule_key='primary'; application=$application; host=$ruleHost; ports=$rulePorts; domains=$ruleDomains
            protocol=$protocol; action=$action; proxy_config_id=$proxyConfigId; enabled=[bool](Get-OptionalValue $Entry 'rule_enabled' $true)
        })
    }

    $clientMode = [string](Get-OptionalValue $Entry 'mode' (Get-OptionalValue $Defaults 'mode' $(if ($transition) { 'issue206' } else { 'base' })))
    $client = [pscustomobject][ordered]@{
        mode=$clientMode; family=$family; protocol=$protocol; socket_mode=$socketMode; local_ip=$localIp; local_port=0
        remote_ip=$host; remote_port='${PB_ENDPOINT_A_PORT}'; close_mode=[string](Get-OptionalValue $Entry 'close_mode' 'graceful')
        payload_size=[int](Get-OptionalValue $Entry 'payload_size' 64); expected_action=$action
        expected_outcome=[string](Get-OptionalValue $Entry 'expected_outcome' $(if ($action -eq 'BLOCK') { 'no-echo' } else { 'echo' }))
        tcp_peer_policy=[string](Get-OptionalValue $Entry 'tcp_peer_policy' $(if ($action -eq 'PROXY') { 'record-only' } else { 'exact' }))
    }
    if ($clientMode -eq 'issue206') {
        $firstAction = $(if ($transitionParts.Count -eq 2) { $transitionParts[0].ToUpperInvariant() } else { [string](Get-OptionalValue $Entry 'first_expected_action' 'DIRECT') })
        $secondAction = $(if ($transitionParts.Count -eq 2) { $transitionParts[1].ToUpperInvariant() } else { [string](Get-OptionalValue $Entry 'second_expected_action' 'DIRECT') })
        foreach ($property in ([ordered]@{
            first_remote_ip=$host; first_remote_port='${PB_ENDPOINT_B_PORT}'; second_remote_ip=$host; second_remote_port='${PB_ENDPOINT_A_PORT}'
            first_expected_action=$firstAction; second_expected_action=$secondAction
            first_expect=$(if ($firstAction -eq 'BLOCK') { 'no-echo' } else { 'echo' }); second_expect=$(if ($secondAction -eq 'BLOCK') { 'no-echo' } else { 'echo' })
            first_tcp_peer_policy='record-only'; second_tcp_peer_policy='exact'; bind_retry_count=100; bind_retry_delay_ms=50
        }).GetEnumerator()) { $client | Add-Member -NotePropertyName $property.Key -NotePropertyValue $property.Value }
    }
    elseif ($clientMode -eq 'issue209') {
        $firstProtocol = [string](Get-OptionalValue $Entry 'first_protocol' $(if ($id -match 'tcp-to-udp') { 'TCP' } else { 'UDP' }))
        $secondProtocol = [string](Get-OptionalValue $Entry 'second_protocol' $(if ($firstProtocol -eq 'TCP') { 'UDP' } else { 'TCP' }))
        foreach ($property in ([ordered]@{
            first_protocol=$firstProtocol; second_protocol=$secondProtocol
            first_remote_ip=$host; first_remote_port='${PB_ENDPOINT_B_PORT}'; second_remote_ip=$host; second_remote_port='${PB_ENDPOINT_A_PORT}'
            first_expected_action=$action; second_expected_action=$action; first_expect='echo'; second_expect='echo'
            first_tcp_peer_policy=$(if ($action -eq 'PROXY') { 'record-only' } else { 'exact' })
            second_tcp_peer_policy=$(if ($action -eq 'PROXY') { 'record-only' } else { 'exact' })
            inter_flow_wait_ms=100; bind_retry_count=100; bind_retry_delay_ms=50
        }).GetEnumerator()) { $client | Add-Member -NotePropertyName $property.Key -NotePropertyValue $property.Value }
    }

    return [pscustomobject][ordered]@{
        schema_version=1; scenario_id=$id; title=[string](Get-OptionalValue $Entry 'title' $id); enabled=$enabled
        implementation_status=$implementationStatus; implementation_reason=$implementationReason; profile_expectation=$profileExpectation
        mock_fixture_id=$mockFixtureId; tags=@($tags); requires=@($requires); coverage_group=$coverageGroup
        reset_policy=[string](Get-OptionalValue $Entry 'reset_policy' (Get-OptionalValue $Defaults 'reset_policy' 'rules_only'))
        repeats=[int](Get-OptionalValue $Entry 'repeats' 1); timeout_ms=[int](Get-OptionalValue $Entry 'timeout_ms' 5000)
        independent=[bool](Get-OptionalValue $Entry 'independent' $true); unsupported_status=$unsupportedStatus
        known_defect_id=[string](Get-OptionalValue $Entry 'known_defect_id' ''); parameters=$Entry
        rule_set=@($rules.ToArray()); client=$client
        assertions=@('exit_code','flow_count','same_local_tuple','payload_response_sha','echo_no_echo','expected_action','destination','source_egress','leaks')
        mock=[pscustomobject]@{ expected_status=[string](Get-OptionalValue $Entry 'mock_status' (Get-OptionalValue $Defaults 'mock_status' 'PASS')) }
    }
}

function Assert-ScenarioDefinition {
    param($Scenario, [string]$Source)
    Assert-ObjectProperties -InputObject $Scenario -Names @('schema_version','scenario_id','enabled','implementation_status','tags','requires','coverage_group','reset_policy','rule_set','client','assertions') -DocumentType "Scenario in '$Source'"
    if ($Scenario.schema_version -ne 1) { throw "Unsupported scenario schema_version in '$Source'." }
    if ([string]$Scenario.scenario_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Invalid scenario_id in '$Source'." }
    if ($Scenario.enabled -isnot [bool]) { throw "Scenario '$($Scenario.scenario_id)' enabled must be boolean." }
    if (@('EXECUTABLE','DECLARATIVE_ONLY','UNSUPPORTED_PRODUCT_SCOPE') -notcontains [string]$Scenario.implementation_status) { throw "Scenario '$($Scenario.scenario_id)' has invalid implementation_status." }
    if ([string]$Scenario.implementation_status -eq 'DECLARATIVE_ONLY' -and [string]::IsNullOrWhiteSpace([string]$Scenario.implementation_reason)) { throw "Scenario '$($Scenario.scenario_id)' requires implementation_reason." }
    $tagSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($tag in @($Scenario.tags)) {
        if ([string]::IsNullOrWhiteSpace([string]$tag)) { throw "Scenario '$($Scenario.scenario_id)' has an empty tag." }
        if (-not $tagSet.Add([string]$tag)) { throw "Scenario '$($Scenario.scenario_id)' has duplicate tag '$tag'." }
    }
    foreach ($requirement in @($Scenario.requires)) { if ([string]::IsNullOrWhiteSpace([string]$requirement)) { throw "Scenario '$($Scenario.scenario_id)' has an empty requirement." } }
}

function Import-ScenarioCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScenarioRoot)
    if (-not (Test-Path -LiteralPath $ScenarioRoot -PathType Container)) { throw 'Scenario root not found.' }
    $scenarios = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @(Get-ChildItem -LiteralPath $ScenarioRoot -Recurse -File -Filter '*.json' | Sort-Object FullName)) {
        $document = Read-JsonFile -Path $file.FullName
        $expanded = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $document.PSObject.Properties['scenario_id']) { $expanded.Add($document) }
        elseif ($null -ne $document.PSObject.Properties['catalog_id']) {
            $defaults = Get-OptionalValue $document 'defaults' ([pscustomobject]@{})
            foreach ($entry in @(Get-OptionalValue $document 'scenarios' @())) { $expanded.Add((ConvertTo-CatalogScenario -Entry $entry -Defaults $defaults -CatalogId ([string]$document.catalog_id))) }
            if ($null -ne $document.PSObject.Properties['pairwise']) {
                $cases = @(Get-DeterministicPairwiseCases -Dimensions $document.pairwise.dimensions)
                $index = 0
                foreach ($case in $cases) {
                    $index++
                    $entry = ($document.pairwise.base | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
                    $entry | Add-Member -NotePropertyName id -NotePropertyValue ('{0}-{1:d3}' -f $document.pairwise.id_prefix, $index) -Force
                    foreach ($property in $case.PSObject.Properties) { $entry | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force }
                    $expanded.Add((ConvertTo-CatalogScenario -Entry $entry -Defaults $defaults -CatalogId ([string]$document.catalog_id)))
                }
            }
        }
        else { throw "Unknown scenario document type '$($file.FullName)'." }
        foreach ($scenario in $expanded) {
            Assert-ScenarioDefinition -Scenario $scenario -Source $file.Name
            if (-not $ids.Add([string]$scenario.scenario_id)) { throw "Duplicate scenario ID '$($scenario.scenario_id)'." }
            $scenarios.Add($scenario)
        }
    }
    return $scenarios.ToArray()
}

function Get-KnownDefectMatch {
    param($Scenario, $KnownDefects)
    if ($null -eq $KnownDefects) { return $null }
    foreach ($defect in @($KnownDefects.items)) {
        $idMatch = @($defect.matching.scenario_ids) -contains [string]$Scenario.scenario_id
        $tagMatch = @($defect.matching.tags).Count -gt 0
        foreach ($tag in @($defect.matching.tags)) { if (@($Scenario.tags) -notcontains [string]$tag) { $tagMatch = $false; break } }
        if ($idMatch -or $tagMatch -or [string]$Scenario.known_defect_id -eq [string]$defect.id) { return $defect }
    }
    return $null
}

function Test-ScenarioSelection {
    [CmdletBinding()]
    param($Scenario, $Capabilities, $Suite, $KnownDefects, [ValidateSet('dry-run','mock','real')][string]$RunMode='dry-run')
    if (-not $Scenario.enabled) { return [pscustomobject]@{selected=$false;status='SKIPPED_SELECTION';reason='scenario disabled';known_defect=$null} }
    if ([string]$Scenario.implementation_status -eq 'UNSUPPORTED_PRODUCT_SCOPE') { return [pscustomobject]@{selected=$false;status='UNSUPPORTED_PRODUCT_SCOPE';reason='outside claimed product scope';known_defect=$null} }
    if ($RunMode -eq 'real' -and [string]$Scenario.implementation_status -eq 'DECLARATIVE_ONLY') { return [pscustomobject]@{selected=$false;status='NOT_IMPLEMENTED';reason=[string]$Scenario.implementation_reason;known_defect=$null} }
    foreach ($requirement in @($Scenario.requires)) {
        $capability = $Capabilities.capabilities.PSObject.Properties[[string]$requirement]
        if ($null -eq $capability) { return [pscustomobject]@{selected=$false;status='SKIPPED_CAPABILITY';reason="required capability '$requirement' is not declared";known_defect=$null} }
        if (-not $capability.Value.enabled) { return [pscustomobject]@{selected=$false;status='SKIPPED_CAPABILITY';reason="required capability '$requirement' is disabled: $($capability.Value.reason)";known_defect=$null} }
    }
    $selection = $Suite.selection
    if (@($selection.exclude_scenario_ids) -contains [string]$Scenario.scenario_id) { return [pscustomobject]@{selected=$false;status='SKIPPED_SELECTION';reason='scenario ID excluded';known_defect=$null} }
    if (@($selection.include_scenario_ids).Count -gt 0 -and @($selection.include_scenario_ids) -notcontains [string]$Scenario.scenario_id) { return [pscustomobject]@{selected=$false;status='SKIPPED_SELECTION';reason='scenario ID not included';known_defect=$null} }
    foreach ($tag in @($selection.exclude_tags)) { if (@($Scenario.tags) -contains [string]$tag) { return [pscustomobject]@{selected=$false;status='SKIPPED_SELECTION';reason="excluded tag '$tag'";known_defect=$null} } }
    foreach ($tag in @($selection.include_tags)) { if (@($Scenario.tags) -notcontains [string]$tag) { return [pscustomobject]@{selected=$false;status='SKIPPED_SELECTION';reason="required include tag '$tag' is absent";known_defect=$null} } }
    $defect = Get-KnownDefectMatch -Scenario $Scenario -KnownDefects $KnownDefects
    if ($null -ne $defect -and [string]$defect.policy -eq 'do-not-run') { return [pscustomobject]@{selected=$false;status='BLOCKED_BY_KNOWN_DEFECT';reason=[string]$defect.reason;known_defect=$defect} }
    return [pscustomobject]@{selected=$true;status='SELECTED';reason='selected';known_defect=$defect}
}

Export-ModuleMember -Function Import-ScenarioCatalog, Test-ScenarioSelection, Get-KnownDefectMatch, Assert-ScenarioDefinition
