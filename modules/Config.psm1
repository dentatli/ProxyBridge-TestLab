Set-StrictMode -Version Latest

function Read-JsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'JSON configuration file not found.'
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON configuration: $($_.Exception.Message)"
    }
}

function Assert-ObjectProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string[]]$Names,
        [Parameter(Mandatory)][string]$DocumentType
    )

    foreach ($name in $Names) {
        if ($null -eq $InputObject -or $null -eq $InputObject.PSObject.Properties[$name]) {
            throw "$DocumentType is missing required section '$name'."
        }
    }
}

function Add-DefaultProperty {
    param($InputObject, [string]$Name, $Value)
    if ($null -eq $InputObject.PSObject.Properties[$Name]) {
        $InputObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Import-CapabilitiesConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $config = Read-JsonFile -Path $Path
    Assert-ObjectProperties -InputObject $config -Names @('schema_version', 'capabilities') -DocumentType 'Capabilities configuration'
    if ($config.schema_version -ne 1) { throw "Unsupported capabilities schema_version '$($config.schema_version)'." }
    if ($config.capabilities -isnot [pscustomobject]) { throw "Capabilities section must be an object." }
    foreach ($property in $config.capabilities.PSObject.Properties) {
        Assert-ObjectProperties -InputObject $property.Value -Names @('enabled', 'reason') -DocumentType "Capability '$($property.Name)'"
        if ($property.Value.enabled -isnot [bool]) { throw "Capability '$($property.Name)' enabled value must be boolean." }
    }
    return $config
}

function Import-SuiteConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $config = Read-JsonFile -Path $Path
    Assert-ObjectProperties -InputObject $config -Names @('schema_version', 'suite_id', 'selection') -DocumentType 'Suite configuration'
    if ($config.schema_version -ne 1) { throw "Unsupported suite schema_version '$($config.schema_version)'." }
    Assert-ObjectProperties -InputObject $config.selection -Names @('include_tags', 'exclude_tags', 'include_scenario_ids', 'exclude_scenario_ids') -DocumentType 'Suite selection'
    foreach ($name in @('include_tags', 'exclude_tags', 'include_scenario_ids', 'exclude_scenario_ids')) {
        if ($config.selection.$name -is [string]) { throw "Suite selection '$name' must be an array." }
    }

    Add-DefaultProperty -InputObject $config -Name 'execution' -Value ([pscustomobject]@{})
    $defaults = [ordered]@{
        repeats                            = 1
        timeout_ms                         = 5000
        suite_timeout_ms                   = 300000
        continue_on_product_failure        = $true
        continue_on_expected_failure       = $true
        continue_on_ambiguous_hold         = $false
        stop_on_harness_failure             = $true
        stop_on_infrastructure_failure      = $true
        stop_on_state_contamination         = $true
        max_consecutive_product_failures    = 5
        reset_policy                        = 'rules_only'
        runtime_mode                        = 'dry-run'
        dry_run                             = $true
        mock_runtime                        = $false
    }
    foreach ($entry in $defaults.GetEnumerator()) {
        Add-DefaultProperty -InputObject $config.execution -Name $entry.Key -Value $entry.Value
    }
    if ([int]$config.execution.repeats -lt 1) { throw 'Suite repeats must be at least 1.' }
    if ([int]$config.execution.timeout_ms -lt 1) { throw 'Suite timeout_ms must be positive.' }
    if ([int]$config.execution.suite_timeout_ms -lt 1) { throw 'Suite suite_timeout_ms must be positive.' }
    if ([int]$config.execution.max_consecutive_product_failures -lt 1) { throw 'Suite max_consecutive_product_failures must be at least 1.' }
    if (@('dry-run', 'mock', 'real') -notcontains [string]$config.execution.runtime_mode) { throw 'Suite runtime_mode is invalid.' }
    if (@('none', 'rules_only', 'profile', 'process', 'driver', 'vm') -notcontains [string]$config.execution.reset_policy) { throw 'Suite reset_policy is invalid.' }
    return $config
}

function Import-KnownDefectsConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $config = Read-JsonFile -Path $Path
    Assert-ObjectProperties -InputObject $config -Names @('schema_version', 'items') -DocumentType 'Known defects configuration'
    if ($config.schema_version -ne 1) { throw "Unsupported known-defects schema_version '$($config.schema_version)'." }
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($config.items)) {
        Assert-ObjectProperties -InputObject $item -Names @('id', 'matching', 'expected_status', 'reason', 'policy') -DocumentType 'Known defect'
        if (-not $ids.Add([string]$item.id)) { throw "Duplicate known-defect ID '$($item.id)'." }
        if (@('do-not-run', 'run-as-regression') -notcontains [string]$item.policy) { throw "Known defect '$($item.id)' has invalid policy." }
        if (@('EXPECTED_FAIL', 'BLOCKED_BY_KNOWN_DEFECT') -notcontains [string]$item.expected_status) { throw "Known defect '$($item.id)' has invalid expected_status." }
        Add-DefaultProperty -InputObject $item.matching -Name 'scenario_ids' -Value @()
        Add-DefaultProperty -InputObject $item.matching -Name 'tags' -Value @()
    }
    return $config
}

function Import-RuntimeConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $config = Read-JsonFile -Path $Path
    Assert-ObjectProperties -InputObject $config -Names @('schema_version', 'cli_actual_path_timeout_ms', 'client_process_exit_grace_ms', 'cli_readiness', 'environment_preparation', 'scenario_defaults') -DocumentType 'Runtime configuration'
    if ($config.schema_version -ne 1) { throw "Unsupported runtime schema_version '$($config.schema_version)'." }
    Assert-ObjectProperties -InputObject $config.cli_readiness -Names @('regex', 'stable_ms', 'readiness_timeout_ms', 'stop_timeout_ms') -DocumentType 'Runtime CLI readiness'
    Assert-ObjectProperties -InputObject $config.environment_preparation -Names @('service_start_timeout_ms', 'poll_interval_ms') -DocumentType 'Runtime environment preparation'
    Assert-ObjectProperties -InputObject $config.scenario_defaults -Names @('endpoint_delay_port', 'endpoint_error_port', 'rule_port_range', 'test_domain') -DocumentType 'Runtime scenario defaults'
    if ([int]$config.cli_actual_path_timeout_ms -lt 1) { throw 'Runtime CLI actual path timeout must be positive.' }
    if ([int]$config.client_process_exit_grace_ms -lt 1) { throw 'Runtime client process exit grace must be positive.' }
    if ([int]$config.cli_readiness.stable_ms -lt 1 -or [int]$config.cli_readiness.readiness_timeout_ms -lt 1 -or [int]$config.cli_readiness.stop_timeout_ms -lt 1) { throw 'Runtime CLI readiness timeouts must be positive.' }
    if ([int]$config.environment_preparation.service_start_timeout_ms -lt 1 -or [int]$config.environment_preparation.poll_interval_ms -lt 1) { throw 'Runtime environment preparation timeouts must be positive.' }
    if (-not [string]::IsNullOrWhiteSpace([string]$config.cli_readiness.regex)) {
        try { $null = [regex]::new([string]$config.cli_readiness.regex) }
        catch { throw 'Runtime CLI readiness regex is invalid.' }
    }
    return $config
}

Export-ModuleMember -Function Read-JsonFile, Assert-ObjectProperties, Import-CapabilitiesConfig, Import-SuiteConfig, Import-KnownDefectsConfig, Import-RuntimeConfig
