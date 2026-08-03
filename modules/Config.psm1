Set-StrictMode -Version Latest

function Read-JsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON configuration file not found."
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON configuration: $($_.Exception.Message)"
    }
}

function Assert-Properties {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string[]]$Names,
        [Parameter(Mandatory)][string]$DocumentType
    )

    foreach ($name in $Names) {
        if ($null -eq $InputObject.PSObject.Properties[$name]) {
            throw "$DocumentType is missing required section '$name'."
        }
    }
}

function Import-CapabilitiesConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $config = Read-JsonFile -Path $Path
    Assert-Properties -InputObject $config -Names @('schema_version', 'capabilities') -DocumentType 'Capabilities configuration'
    if ($config.schema_version -ne 1) {
        throw "Unsupported capabilities schema_version '$($config.schema_version)'."
    }
    if ($config.capabilities -isnot [pscustomobject]) {
        throw "Capabilities configuration section 'capabilities' must be an object."
    }

    foreach ($property in $config.capabilities.PSObject.Properties) {
        Assert-Properties -InputObject $property.Value -Names @('enabled', 'reason') -DocumentType "Capability '$($property.Name)'"
        if ($property.Value.enabled -isnot [bool]) {
            throw "Capability '$($property.Name)' enabled value must be boolean."
        }
    }
    return $config
}

function Import-SuiteConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $config = Read-JsonFile -Path $Path
    Assert-Properties -InputObject $config -Names @('schema_version', 'suite_id', 'selection') -DocumentType 'Suite configuration'
    if ($config.schema_version -ne 1) {
        throw "Unsupported suite schema_version '$($config.schema_version)'."
    }
    Assert-Properties -InputObject $config.selection -Names @(
        'include_tags', 'exclude_tags', 'include_scenario_ids', 'exclude_scenario_ids'
    ) -DocumentType 'Suite selection'
    return $config
}

function Import-ScenarioCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScenarioRoot)

    if (-not (Test-Path -LiteralPath $ScenarioRoot -PathType Container)) {
        throw "Scenario root not found."
    }

    $scenarios = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $files = @(Get-ChildItem -LiteralPath $ScenarioRoot -Recurse -File -Filter '*.json' | Sort-Object FullName)

    foreach ($file in $files) {
        $scenario = Read-JsonFile -Path $file.FullName
        Assert-Properties -InputObject $scenario -Names @(
            'schema_version', 'scenario_id', 'enabled', 'tags', 'requires', 'rule_set'
        ) -DocumentType 'Scenario'
        if ($scenario.schema_version -ne 1) {
            throw "Unsupported scenario schema_version in '$($file.Name)'."
        }
        if ([string]::IsNullOrWhiteSpace([string]$scenario.scenario_id) -or
            [string]$scenario.scenario_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
            throw "Scenario has an invalid scenario_id."
        }
        if (-not $ids.Add([string]$scenario.scenario_id)) {
            throw "Duplicate scenario ID '$($scenario.scenario_id)'."
        }
        if ($scenario.enabled -isnot [bool]) {
            throw "Scenario '$($scenario.scenario_id)' enabled value must be boolean."
        }
        $scenarios.Add($scenario)
    }

    return ,$scenarios.ToArray()
}

function Test-ScenarioSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)]$Capabilities,
        [Parameter(Mandatory)]$Suite
    )

    $id = [string]$Scenario.scenario_id
    if (-not $Scenario.enabled) {
        return [pscustomobject]@{ selected = $false; status = 'SKIPPED_SELECTION'; reason = 'scenario disabled' }
    }

    foreach ($requirement in @($Scenario.requires)) {
        $capability = $Capabilities.capabilities.PSObject.Properties[[string]$requirement]
        if ($null -eq $capability) {
            return [pscustomobject]@{
                selected = $false
                status   = 'SKIPPED_CAPABILITY'
                reason   = "required capability '$requirement' is not declared"
            }
        }
        if (-not $capability.Value.enabled) {
            $detail = [string]$capability.Value.reason
            $reason = "required capability '$requirement' is disabled"
            if (-not [string]::IsNullOrWhiteSpace($detail)) {
                $reason += ": $detail"
            }
            return [pscustomobject]@{ selected = $false; status = 'SKIPPED_CAPABILITY'; reason = $reason }
        }
    }

    $selection = $Suite.selection
    if (@($selection.exclude_scenario_ids) -contains $id) {
        return [pscustomobject]@{ selected = $false; status = 'SKIPPED_SELECTION'; reason = 'scenario ID excluded' }
    }
    if (@($selection.include_scenario_ids).Count -gt 0 -and @($selection.include_scenario_ids) -notcontains $id) {
        return [pscustomobject]@{ selected = $false; status = 'SKIPPED_SELECTION'; reason = 'scenario ID not included' }
    }

    $scenarioTags = @($Scenario.tags)
    foreach ($tag in @($selection.exclude_tags)) {
        if ($scenarioTags -contains $tag) {
            return [pscustomobject]@{ selected = $false; status = 'SKIPPED_SELECTION'; reason = "excluded tag '$tag'" }
        }
    }
    foreach ($tag in @($selection.include_tags)) {
        if ($scenarioTags -notcontains $tag) {
            return [pscustomobject]@{ selected = $false; status = 'SKIPPED_SELECTION'; reason = "required include tag '$tag' is absent" }
        }
    }

    return [pscustomobject]@{ selected = $true; status = 'DRY_RUN_READY'; reason = 'selected' }
}

Export-ModuleMember -Function Import-CapabilitiesConfig, Import-SuiteConfig, Import-ScenarioCatalog, Test-ScenarioSelection
