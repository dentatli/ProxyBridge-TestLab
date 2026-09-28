[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/NegativeProxyProfile.psm1') -Force
Import-Module (Join-Path $root 'modules/ProfileValidator.psm1') -Force
$arguments = @{
    RunId='fixture-run-1'; AttemptId='fixture-attempt-1'; ScenarioId='failure-proxy-auth'
    ServerAddress='192.0.2.10'; DestinationAddress='192.0.2.20'; DestinationPort=41001
    ProcessBasename='fixture-client.exe'
}
$first = New-NegativeProxyProfile @arguments
$second = New-NegativeProxyProfile @arguments
Assert-True (Test-ProxyBridgeProfile $first.profile).valid 'isolated profile format'
Assert-Equal 1 @($first.profile.ProxyConfigs).Count 'one owned config only'
Assert-Equal 1 @($first.profile.ProxyRules).Count 'one exact rule only'
$proxy = $first.profile.ProxyConfigs[0]
$rule = $first.profile.ProxyRules[0]
Assert-Equal 'PROXY' $rule.Action 'must not fall back to DIRECT'
Assert-Equal $proxy.Id $rule.ProxyConfigId 'owned identity reference'
Assert-True ($proxy.Id -ne $second.profile.ProxyConfigs[0].Id) 'fresh numeric config identity'
Assert-Equal '192.0.2.20' $rule.TargetHosts 'exact destination'
Assert-Equal '' $rule.TargetDomains 'no wildcard domain selector'
Assert-Equal '42702' $proxy.Port 'reserved auth port'
Assert-True ($proxy.Username -ne $second.profile.ProxyConfigs[0].Username) 'fresh principal'
Assert-True ($proxy.Password -ne $second.profile.ProxyConfigs[0].Password) 'fresh secret'
Assert-True ($first.profile.Name -ne $second.profile.Name) 'fresh profile identity'
Assert-Equal 'fixture-run-1' $first.binding.run_id 'run binding'
Assert-Equal 'fixture-attempt-1' $first.binding.attempt_id 'attempt binding'
Assert-True $first.requires_verified_receipt 'construction cannot confer readiness'
Assert-True (-not $first.runtime_authorized) 'unverified plan cannot authorize runtime'
Assert-True (($first.binding | ConvertTo-Json -Compress) -notmatch [regex]::Escape($proxy.Password)) 'binding excludes secret'
$arguments.ScenarioId = 'failure-proxy-unavailable'
$unavailable = New-NegativeProxyProfile @arguments
Assert-Equal '42704' $unavailable.profile.ProxyConfigs[0].Port 'independent unavailable port'
$canonicalArguments = $arguments.Clone()
$canonicalArguments.ServerAddress = '::ffff:192.0.2.10'
$canonicalArguments.DestinationAddress = '::ffff:192.0.2.20'
$canonical = New-NegativeProxyProfile @canonicalArguments
Assert-Equal '192.0.2.10' $canonical.profile.ProxyConfigs[0].Host 'canonical server address'
Assert-Equal '192.0.2.20' $canonical.profile.ProxyRules[0].TargetHosts 'canonical exact destination'
function Assert-Rejected($Key, $Value) {
    $copy = $arguments.Clone(); $copy[$Key] = $Value
    $rejected = $false
    try { $null = New-NegativeProxyProfile @copy } catch { $rejected = $true }
    Assert-True $rejected ('reject invalid ' + $Key)
}
Assert-Rejected 'ScenarioId' 'tcp-ipv4-proxy'
Assert-Rejected 'RunId' '../escape'
Assert-Rejected 'AttemptId' 'invalid attempt'
Assert-Rejected 'ServerAddress' '127.0.0.1'
Assert-Rejected 'ServerAddress' '::1'
Assert-Rejected 'ServerAddress' '0.0.0.0'
Assert-Rejected 'DestinationAddress' '*'
Assert-Rejected 'DestinationPort' 0
Assert-Rejected 'ProcessBasename' '*'
Assert-Rejected 'ProcessBasename' 'C:\operator.exe'
$command = Get-Command New-NegativeProxyProfile
foreach ($forbidden in @('Environment','TemplatePath','ProxyConfig','Username','Password','ProxyPort')) {
    Assert-True (-not $command.Parameters.ContainsKey($forbidden)) 'no operator configuration input'
}
'PASS: isolated negative-proxy profile (offline, unpromoted)'
