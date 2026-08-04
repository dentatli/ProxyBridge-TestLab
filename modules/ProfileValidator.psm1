Set-StrictMode -Version Latest

function Test-UnresolvedPlaceholder {
    param($Value)
    return (($Value | ConvertTo-Json -Depth 100 -Compress) -match '\$\{[A-Za-z_][A-Za-z0-9_]*\}')
}

function Test-PortExpression {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    foreach ($part in @($Value -split ',')) {
        if ($part -notmatch '^(?<first>[0-9]{1,5})(?:-(?<second>[0-9]{1,5}))?$') { return $false }
        $first = [int]$Matches.first
        $hasSecond = $Matches.ContainsKey('second') -and -not [string]::IsNullOrWhiteSpace([string]$Matches['second'])
        $second = $(if ($hasSecond) { [int]$Matches['second'] } else { $first })
        if ($first -lt 1 -or $first -gt 65535 -or $second -lt 1 -or $second -gt 65535 -or $first -gt $second) { return $false }
    }
    return $true
}

function Test-ProxyBridgeProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Profile,
        [switch]$ThrowOnError
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $requiredTopLevel = @('Version', 'Name', 'LocalhostViaProxy', 'IsTrafficLoggingEnabled', 'AutoClearConnectionLogs', 'Language', 'CloseToTray', 'ProxyConfigs', 'ProxyRules', 'LogFilters')
    foreach ($field in $requiredTopLevel) {
        if ($null -eq $Profile.PSObject.Properties[$field]) { $errors.Add("Missing top-level field '$field'.") }
    }
    if ($errors.Count -eq 0) {
        if ([string]$Profile.Version -ne '1.0') { $errors.Add("Version must be '1.0'.") }
        if ([string]::IsNullOrWhiteSpace([string]$Profile.Name)) { $errors.Add('Name must not be empty.') }
        foreach ($field in @('LocalhostViaProxy', 'IsTrafficLoggingEnabled', 'AutoClearConnectionLogs', 'CloseToTray')) {
            if ($Profile.$field -isnot [bool]) { $errors.Add("$field must be boolean.") }
        }
        if ([string]::IsNullOrWhiteSpace([string]$Profile.Language)) { $errors.Add('Language must not be empty.') }
        if ($null -eq $Profile.ProxyConfigs) { $errors.Add('ProxyConfigs must be an array.') }
        if ($null -eq $Profile.ProxyRules) { $errors.Add('ProxyRules must be an array.') }
    }

    $proxyIds = [System.Collections.Generic.HashSet[int]]::new()
    $proxyConfigs = $(if ($null -ne $Profile.PSObject.Properties['ProxyConfigs']) { @($Profile.ProxyConfigs) } else { @() })
    foreach ($config in $proxyConfigs) {
        $missing = $false
        foreach ($field in @('Id', 'Name', 'Type', 'Host', 'Port', 'Username', 'Password', 'SendDomainToProxy')) {
            if ($null -eq $config.PSObject.Properties[$field]) { $errors.Add("ProxyConfigs[] is missing '$field'."); $missing = $true }
        }
        if ($missing) { continue }
        if ($null -ne $config.PSObject.Properties['Id']) {
            if ($config.Id -isnot [int] -or [int]$config.Id -lt 1) { $errors.Add('ProxyConfigs[].Id must be a positive integer.') }
            elseif (-not $proxyIds.Add([int]$config.Id)) { $errors.Add("Duplicate ProxyConfigs[].Id '$($config.Id)'.") }
        }
        if (@('SOCKS5', 'HTTP') -notcontains [string]$config.Type) { $errors.Add('ProxyConfigs[].Type must be SOCKS5 or HTTP.') }
        if ([string]::IsNullOrWhiteSpace([string]$config.Name)) { $errors.Add('ProxyConfigs[].Name must not be empty.') }
        if ([string]::IsNullOrWhiteSpace([string]$config.Host)) { $errors.Add('ProxyConfigs[].Host must not be empty.') }
        if ($config.Port -isnot [string] -or -not (Test-PortExpression -Value ([string]$config.Port)) -or [string]$config.Port -match '-') { $errors.Add('ProxyConfigs[].Port must be a numeric string in range 1..65535.') }
        if ($config.SendDomainToProxy -isnot [bool]) { $errors.Add('ProxyConfigs[].SendDomainToProxy must be boolean.') }
    }

    $proxyRules = $(if ($null -ne $Profile.PSObject.Properties['ProxyRules']) { @($Profile.ProxyRules) } else { @() })
    foreach ($rule in $proxyRules) {
        $missing = $false
        foreach ($field in @('Name', 'ProcessName', 'TargetHosts', 'TargetPorts', 'TargetDomains', 'Protocol', 'Action', 'IsEnabled', 'ProxyConfigId')) {
            if ($null -eq $rule.PSObject.Properties[$field]) { $errors.Add("ProxyRules[] is missing '$field'."); $missing = $true }
        }
        if ($missing) { continue }
        foreach ($field in @('Name', 'ProcessName', 'TargetPorts')) {
            if ([string]::IsNullOrWhiteSpace([string]$rule.$field)) { $errors.Add("ProxyRules[].$field must not be empty.") }
        }
        if ([string]::IsNullOrWhiteSpace([string]$rule.TargetHosts) -and [string]::IsNullOrWhiteSpace([string]$rule.TargetDomains)) { $errors.Add('ProxyRules[] requires TargetHosts or TargetDomains.') }
        if (@('TCP', 'UDP', 'BOTH') -notcontains [string]$rule.Protocol) { $errors.Add('ProxyRules[].Protocol is invalid.') }
        if (@('DIRECT', 'BLOCK', 'PROXY') -notcontains [string]$rule.Action) { $errors.Add('ProxyRules[].Action is invalid.') }
        if ($rule.TargetPorts -isnot [string] -or -not (Test-PortExpression -Value ([string]$rule.TargetPorts))) { $errors.Add('ProxyRules[].TargetPorts must be a valid port/range string.') }
        if ($rule.IsEnabled -isnot [bool]) { $errors.Add('ProxyRules[].IsEnabled must be boolean.') }
        if ($rule.ProxyConfigId -isnot [int]) { $errors.Add('ProxyRules[].ProxyConfigId must be integer.') }
        elseif (([string]$rule.Action -eq 'PROXY') -and -not $proxyIds.Contains([int]$rule.ProxyConfigId)) { $errors.Add("PROXY rule references missing ProxyConfigId '$($rule.ProxyConfigId)'.") }
        elseif ((@('DIRECT', 'BLOCK') -contains [string]$rule.Action) -and [int]$rule.ProxyConfigId -ne 0) { $errors.Add("$($rule.Action) rule requires ProxyConfigId=0.") }
    }
    if (Test-UnresolvedPlaceholder -Value $Profile) { $errors.Add('Profile contains unresolved placeholders.') }

    $result = [pscustomobject]@{ valid = ($errors.Count -eq 0); errors = $errors.ToArray() }
    if ($ThrowOnError -and -not $result.valid) { throw "PROFILE_VALIDATION_FAILED: $($result.errors -join ' | ')" }
    return $result
}

Export-ModuleMember -Function Test-ProxyBridgeProfile
