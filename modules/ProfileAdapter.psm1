Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProfileValidator.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ProductProfile.psm1') -Force

function Resolve-JsonVariablesInternal {
    param(
        $InputObject,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Variables
    )

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [string]) {
        return [regex]::Replace($InputObject, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}', {
            param($match)
            $name = $match.Groups[1].Value
            if ($Variables.ContainsKey($name)) {
                return $Variables[$name]
            }
            return $match.Value
        })
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = Resolve-JsonVariablesInternal -InputObject $InputObject[$key] -Variables $Variables
        }
        return [pscustomobject]$result
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += ,(Resolve-JsonVariablesInternal -InputObject $item -Variables $Variables)
        }
        return ,$items
    }
    if ($InputObject -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = Resolve-JsonVariablesInternal -InputObject $property.Value -Variables $Variables
        }
        return [pscustomobject]$result
    }
    return $InputObject
}

function Resolve-JsonVariables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Variables,
        [System.Collections.Generic.IDictionary[string, string]]$AdditionalVariables
    )

    $combined = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($key in $Variables.Keys) {
        $combined.Add($key, $Variables[$key])
    }
    if ($null -ne $AdditionalVariables) {
        foreach ($key in $AdditionalVariables.Keys) {
            if ($combined.ContainsKey($key)) {
                throw "Additional variable '$key' conflicts with the environment."
            }
            $combined.Add($key, $AdditionalVariables[$key])
        }
    }

    $resolved = Resolve-JsonVariablesInternal -InputObject $InputObject -Variables $combined
    $serialized = $resolved | ConvertTo-Json -Depth 100 -Compress
    $unresolved = @([regex]::Matches($serialized, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if ($unresolved.Count -gt 0) {
        throw "Unresolved placeholders: $($unresolved -join ', ')."
    }
    return $resolved
}

function ConvertTo-RequiredInteger {
    param($Value, [Parameter(Mandatory)][string]$FieldName)

    $parsed = 0
    if (-not [int]::TryParse(
        [string]$Value,
        [System.Globalization.NumberStyles]::Integer,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    )) {
        throw "$FieldName must be an integer."
    }
    return $parsed
}

function New-ResolvedProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [Parameter(Mandatory)][string]$TemplatePath,
        [switch]$SkipFinalValidation,
        [ValidateSet('configured','ip')][string]$ProxyDestinationMode = 'configured'
    )

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        throw "Profile template not found."
    }
    try {
        $template = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Invalid profile template JSON: $($_.Exception.Message)"
    }

    # The template rules are format examples only. Scenario rule_set is the
    # authoritative source, so do not resolve placeholders from rules that will
    # immediately be replaced.
    $template.ProxyRules = @()

    $intrinsic = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $intrinsic.Add('SCENARIO_ID', [string]$Scenario.scenario_id)
    $profile = Resolve-JsonVariables -InputObject $template -Variables $Environment -AdditionalVariables $intrinsic
    $resolvedScenario = Resolve-JsonVariables -InputObject $Scenario -Variables $Environment

    foreach ($proxyConfig in @($profile.ProxyConfigs)) {
        $proxyConfig.Port = [string]$proxyConfig.Port
        $proxyConfig.Id = ConvertTo-RequiredInteger -Value $proxyConfig.Id -FieldName 'ProxyConfigs[].Id'
        if ($ProxyDestinationMode -eq 'ip') { $proxyConfig.SendDomainToProxy = $false }
    }
    if ($null -ne $resolvedScenario.PSObject.Properties['parameters'] -and
        $null -ne $resolvedScenario.parameters.PSObject.Properties['additional_proxy_config_id']) {
        $additionalId = ConvertTo-RequiredInteger -Value $resolvedScenario.parameters.additional_proxy_config_id -FieldName 'parameters.additional_proxy_config_id'
        if ($additionalId -lt 1) { throw 'parameters.additional_proxy_config_id must be positive.' }
        if (@($profile.ProxyConfigs | Where-Object { [int]$_.Id -eq $additionalId }).Count -gt 0) { throw 'parameters.additional_proxy_config_id duplicates an existing proxy config.' }
        $sourceProxy = @($profile.ProxyConfigs) | Select-Object -First 1
        if ($null -eq $sourceProxy) { throw 'Cannot add a proxy config without a template proxy config.' }
        $additionalProxy = $sourceProxy | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $additionalProxy.Id = $additionalId
        $profile.ProxyConfigs = @($profile.ProxyConfigs) + @($additionalProxy)
    }

    $rules = foreach ($rule in @($resolvedScenario.rule_set)) {
        foreach ($required in @('rule_key', 'application', 'host', 'ports', 'domains', 'protocol', 'action', 'proxy_config_id', 'enabled')) {
            if ($null -eq $rule.PSObject.Properties[$required]) {
                throw "Scenario rule is missing '$required'."
            }
        }
        if ($rule.enabled -isnot [bool]) {
            throw "ProxyRules[].IsEnabled source must be boolean."
        }

        [pscustomobject][ordered]@{
            Name          = "$($resolvedScenario.scenario_id) $($rule.rule_key) rule"
            ProcessName   = [string]$rule.application
            TargetHosts   = [string]$rule.host
            TargetPorts   = [string](@($rule.ports) -join ',')
            TargetDomains = [string](@($rule.domains) -join ',')
            Protocol      = [string]$rule.protocol
            Action        = [string]$rule.action
            IsEnabled     = [bool]$rule.enabled
            ProxyConfigId = ConvertTo-RequiredInteger -Value $rule.proxy_config_id -FieldName 'ProxyRules[].ProxyConfigId'
        }
    }
    $profile.ProxyRules = @($rules)

    # Verify the final object after type normalization and rule replacement.
    $serialized = $profile | ConvertTo-Json -Depth 100 -Compress
    if ($serialized -match '\$\{[A-Za-z_][A-Za-z0-9_]*\}') {
        throw "Generated profile contains unresolved placeholders."
    }
    if (-not $SkipFinalValidation) { $null = Test-ProxyBridgeProfile -Profile $profile -ThrowOnError }
    return $profile
}

function Test-ExpectedProfileValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [Parameter(Mandatory)][string]$TemplatePath,
        [ValidateSet('configured','ip')][string]$ProxyDestinationMode = 'configured'
    )
    $expectation = $(if ($null -ne $Scenario.PSObject.Properties['profile_expectation']) { [string]$Scenario.profile_expectation } else { 'valid' })
    $profile = New-ResolvedProfile -Scenario $Scenario -Environment $Environment -TemplatePath $TemplatePath -SkipFinalValidation -ProxyDestinationMode $ProxyDestinationMode
    $validation = Test-ProxyBridgeProfile -Profile $profile
    switch ($expectation) {
        'valid' { return [pscustomobject]@{ passed=[bool]$validation.valid; expectation=$expectation; errors=@($validation.errors); profile=$profile; may_write=[bool]$validation.valid } }
        'invalid-missing-proxy-config' {
            $matched = (-not $validation.valid -and (@($validation.errors) -join ' | ') -match 'missing ProxyConfigId')
            return [pscustomobject]@{ passed=$matched; expectation=$expectation; errors=@($validation.errors); profile=$profile; may_write=$false }
        }
        default { throw "PROFILE_EXPECTATION_UNSUPPORTED: $expectation" }
    }
}

function Get-ExpectedProfileValidationDisposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Validation,
        [Parameter(Mandatory)][ValidateSet('dry-run','mock','real')][string]$RunMode
    )
    if (-not [bool]$Validation.passed -or [bool]$Validation.may_write -or [string]$Validation.expectation -eq 'valid') {
        throw 'PROFILE_REJECTION_DISPOSITION_REQUIRES_EXPECTED_INVALID_PROFILE'
    }
    $status = switch ($RunMode) { 'dry-run' { 'DRY_RUN_READY' } 'mock' { 'MOCK_PASS' } 'real' { 'PASS' } }
    return [pscustomobject]@{ status=$status; reason='intentional invalid profile was rejected before product start'; product_started=$false }
}

function Write-ResolvedProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)][string]$ScenarioId,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [ValidateSet('driver','v4.0.0')][string]$ProductProfileContract = 'driver'
    )

    if ($ScenarioId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Invalid scenario ID for profile output."
    }
    $productProfile = ConvertTo-ProductProfile -Profile $Profile -Contract $ProductProfileContract
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $path = Join-Path $OutputDirectory "$ScenarioId.pbprofile"
    $json = $productProfile | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    return [pscustomobject]@{ path = $path; sha256 = $hash; product_profile_contract = $ProductProfileContract }
}

Export-ModuleMember -Function Resolve-JsonVariables, New-ResolvedProfile, Test-ExpectedProfileValidation, Get-ExpectedProfileValidationDisposition, Write-ResolvedProfile
