Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ProfileValidator.psm1') -Force
$script:IssuedNegativeConfigIds = [System.Collections.Generic.HashSet[int]]::new()

function Resolve-NegativeTargetAddress {
    param([string]$Value)
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($Value, [ref]$address)) {
        throw 'NEGATIVE_PROFILE_ADDRESS_INVALID'
    }
    if ($address.IsIPv4MappedToIPv6) { $address = $address.MapToIPv4() }
    $bytes = $address.GetAddressBytes()
    if ([System.Net.IPAddress]::IsLoopback($address) -or
        $address.Equals([System.Net.IPAddress]::Any) -or
        $address.Equals([System.Net.IPAddress]::IPv6Any) -or
        $address.IsIPv6Multicast -or ($bytes.Length -eq 16 -and $address.ScopeId -gt 0)) {
        throw 'NEGATIVE_PROFILE_ADDRESS_NOT_UNICAST'
    }
    if ($bytes.Length -eq 4 -and ($bytes[0] -eq 0 -or $bytes[0] -ge 224)) {
        throw 'NEGATIVE_PROFILE_ADDRESS_NOT_UNICAST'
    }
    return $address.ToString()
}

function New-NegativeProxyProfile {
    # Pure offline construction. The profile contains generated private values:
    # never serialize the returned object to public reports. No file is written,
    # receipt is trusted, or capability is enabled by this function.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')][string]$RunId,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')][string]$AttemptId,
        [Parameter(Mandatory)][ValidateSet('failure-proxy-auth','failure-proxy-unavailable')][string]$ScenarioId,
        [Parameter(Mandatory)][string]$ServerAddress,
        [Parameter(Mandatory)][string]$DestinationAddress,
        [Parameter(Mandatory)][ValidateRange(1,65535)][int]$DestinationPort,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-][A-Za-z0-9_.-]*\.exe$')][string]$ProcessBasename
    )
    $ServerAddress = Resolve-NegativeTargetAddress $ServerAddress
    $DestinationAddress = Resolve-NegativeTargetAddress $DestinationAddress
    $catalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config/server-protocol-ports.json'
    $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $authPort = $catalog.ports.negative_proxy
    $unavailablePort = $catalog.ports.negative_proxy_unavailable
    foreach ($port in @($authPort, $unavailablePort)) {
        if ($port -isnot [int] -or $port -lt 1 -or $port -gt 65535) { throw 'NEGATIVE_PROFILE_RESERVED_PORT_INVALID' }
    }
    if ($authPort -eq $unavailablePort) { throw 'NEGATIVE_PROFILE_RESERVED_PORT_COLLISION' }
    $selectedPort = $(if ($ScenarioId -eq 'failure-proxy-auth') { $authPort } else { $unavailablePort })
    $identity = [guid]::NewGuid().ToString('N')
    $principal = 'tl-' + [guid]::NewGuid().ToString('N')
    $secret = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
    # Fresh numeric ID, never obtained from or compared with operator settings.
    # Cross-process identity must still bind the profile GUID and run/attempt.
    $id = 0
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random = New-Object byte[] 4
        for ($probe = 0; $probe -lt 8; $probe++) {
            $rng.GetBytes($random)
            $candidate = [BitConverter]::ToInt32($random, 0) -band [int]::MaxValue
            if ($candidate -gt 0 -and $script:IssuedNegativeConfigIds.Add($candidate)) { $id = $candidate; break }
        }
    } finally { $rng.Dispose() }
    if ($id -eq 0) { throw 'NEGATIVE_PROFILE_ID_ALLOCATION_FAILED' }
    $profile = [pscustomobject][ordered]@{
        Version='1.0'; Name=('TestLab negative ' + $identity)
        LocalhostViaProxy=$false; IsTrafficLoggingEnabled=$true
        AutoClearConnectionLogs=$true; Language='en'; CloseToTray=$true
        ProxyConfigs=@([pscustomobject][ordered]@{
            Id=$id; Name=('TestLab owned ' + $identity); Type='SOCKS5'
            Host=$ServerAddress; Port=[string]$selectedPort
            Username=$principal; Password=$secret; SendDomainToProxy=$false
        })
        ProxyRules=@([pscustomobject][ordered]@{
            Name='TestLab negative exact TCP flow'; ProcessName=$ProcessBasename
            TargetHosts=$DestinationAddress; TargetPorts=[string]$DestinationPort
            TargetDomains=''; Protocol='TCP'; Action='PROXY'; IsEnabled=$true; ProxyConfigId=$id
        })
        LogFilters=@()
    }
    $null = Test-ProxyBridgeProfile -Profile $profile -ThrowOnError
    return [pscustomobject]@{
        profile=$profile
        binding=[pscustomobject]@{
            run_id=$RunId; attempt_id=$AttemptId; scenario_id=$ScenarioId
            profile_identity=$identity; proxy_config_id=$id
            negative_target_identity='testlab-isolated-negative-socks5-v1'
        }
        requires_verified_receipt=$true; runtime_authorized=$false
    }
}

Export-ModuleMember -Function New-NegativeProxyProfile
