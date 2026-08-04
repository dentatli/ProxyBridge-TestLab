Set-StrictMode -Version Latest

function Get-HealthEnvironmentValue {
    param([System.Collections.Generic.IDictionary[string, string]]$Environment, [string]$Name, [switch]$Required)
    if ($Environment.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace([string]$Environment[$Name])) { return [string]$Environment[$Name] }
    if ($Required) { throw "HEALTH_ENVIRONMENT_MISSING_$Name" }
    return ''
}

function New-HealthCheckPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment)

    $checks = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @(
        @('client-binary', 'PB_CLIENT_EXE', 'PB_EXPECTED_CLIENT_SHA256', $true),
        @('proxybridge-cli-binary', 'PB_PROXYBRIDGE_CLI_EXE', 'PB_EXPECTED_PROXYBRIDGE_CLI_SHA256', $true),
        @('proxybridge-gui-binary', 'PB_PROXYBRIDGE_EXE', 'PB_EXPECTED_PROXYBRIDGE_EXE_SHA256', $false),
        @('proxybridge-driver-binary', 'PB_DRIVER_PATH', 'PB_EXPECTED_DRIVER_SHA256', $false)
    )) {
        $checks.Add([pscustomobject][ordered]@{ type='binary'; id=$entry[0]; path_key=$entry[1]; hash_key=$entry[2]; required=[bool]$entry[3] })
    }
    $checks.Add([pscustomobject][ordered]@{ type='tcp-reachability'; id='endpoint-reachability'; host_key='PB_VPS_IPV4'; port_key='PB_ENDPOINT_A_PORT'; required=$true })
    $checks.Add([pscustomobject][ordered]@{ type='tcp-reachability'; id='endpoint-b-reachability'; host_key='PB_VPS_IPV4'; port_key='PB_ENDPOINT_B_PORT'; required=$true })
    $checks.Add([pscustomobject][ordered]@{ type='tcp-reachability'; id='socks-reachability'; host_key='PB_SOCKS_HOST'; port_key='PB_SOCKS_PORT'; required=$true })
    $checks.Add([pscustomobject][ordered]@{ type='tcp-reachability'; id='ssh-reachability'; host_key='PB_SSH_HOST'; port_key='PB_SSH_PORT'; required=$true })
    return [pscustomobject][ordered]@{ schema_version=1; checks=$checks.ToArray(); requires_product_runtime=$true }
}

function New-SystemHealthCheckAdapter {
    [CmdletBinding()]
    param()
    $adapter = [pscustomobject]@{ is_mock=$false }
    $adapter | Add-Member -NotePropertyName FileExists -NotePropertyValue { param($path) return (Test-Path -LiteralPath $path -PathType Leaf) }
    $adapter | Add-Member -NotePropertyName FileHash -NotePropertyValue { param($path) return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    $adapter | Add-Member -NotePropertyName FindProcesses -NotePropertyValue {
        param($names)
        $found = foreach ($name in @($names)) { @(Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ name=$_.ProcessName; pid=$_.Id } }) }
        return @($found)
    }
    $adapter | Add-Member -NotePropertyName GetServiceState -NotePropertyValue {
        param($name)
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -eq $service) { return [pscustomobject]@{ exists=$false; state='MISSING' } }
        return [pscustomobject]@{ exists=$true; state=[string]$service.Status }
    }
    $adapter | Add-Member -NotePropertyName TestTcp -NotePropertyValue {
        param($hostName, $port, $timeoutMs)
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $pending = $client.BeginConnect([string]$hostName, [int]$port, $null, $null)
            if (-not $pending.AsyncWaitHandle.WaitOne([int]$timeoutMs)) { return $false }
            $client.EndConnect($pending)
            return $client.Connected
        }
        catch { return $false }
        finally { $client.Dispose() }
    }
    return $adapter
}

function New-MockHealthCheckAdapter {
    [CmdletBinding()]
    param(
        [hashtable]$Files = @{},
        [object[]]$Processes = @(),
        $ServiceState = $null,
        [hashtable]$TcpResults = @{}
    )
    $state = [pscustomobject]@{ files=$Files; processes=@($Processes); service=$ServiceState; tcp=$TcpResults }
    $adapter = [pscustomobject]@{ is_mock=$true; state=$state }
    $adapter | Add-Member -NotePropertyName FileExists -NotePropertyValue ({ param($path) return $state.files.ContainsKey([string]$path) }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName FileHash -NotePropertyValue ({ param($path) return [string]$state.files[[string]$path] }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName FindProcesses -NotePropertyValue ({ param($names) return @($state.processes) }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName GetServiceState -NotePropertyValue ({ param($name) if ($null -eq $state.service) { return [pscustomobject]@{exists=$false;state='MISSING'} }; return $state.service }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName TestTcp -NotePropertyValue ({
        param($hostName, $port, $timeoutMs)
        $key = "${hostName}:$port"
        return ($state.tcp.ContainsKey($key) -and [bool]$state.tcp[$key])
    }.GetNewClosure())
    return $adapter
}

function Invoke-HealthCheckPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [switch]$AllowProductRuntime,
        $Adapter,
        [int]$NetworkTimeoutMs = 2000
    )
    if ($null -eq $Adapter) {
        if (-not $AllowProductRuntime) { throw 'REAL_HEALTH_CHECKS_NOT_ALLOWED' }
        $Adapter = New-SystemHealthCheckAdapter
    }
    if (-not [bool]$Adapter.is_mock -and -not $AllowProductRuntime) { throw 'REAL_HEALTH_CHECKS_NOT_ALLOWED' }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($check in @($Plan.checks)) {
        try {
            switch ([string]$check.type) {
                'binary' {
                    $path = Get-HealthEnvironmentValue -Environment $Environment -Name ([string]$check.path_key) -Required:$check.required
                    $expected = Get-HealthEnvironmentValue -Environment $Environment -Name ([string]$check.hash_key) -Required:$check.required
                    if ([string]::IsNullOrWhiteSpace($path) -and -not $check.required) { $results.Add([pscustomobject]@{id=$check.id;status='PASS';reason='optional binary not configured';observed='NOT_CONFIGURED'}); break }
                    if ($expected -notmatch '^[A-Fa-f0-9]{64}$') { $results.Add([pscustomobject]@{id=$check.id;status='FAIL_INFRASTRUCTURE';reason="invalid expected hash in $($check.hash_key)";observed='INVALID_HASH'}); break }
                    if (-not (& $Adapter.FileExists $path)) { $results.Add([pscustomobject]@{id=$check.id;status='FAIL_INFRASTRUCTURE';reason="binary missing: $($check.path_key)";observed='MISSING'}); break }
                    $actual = [string](& $Adapter.FileHash $path)
                    if (-not [string]::Equals($expected, $actual, [System.StringComparison]::OrdinalIgnoreCase)) { $results.Add([pscustomobject]@{id=$check.id;status='FAIL_INFRASTRUCTURE';reason="hash mismatch: $($check.hash_key)";observed='HASH_MISMATCH'}); break }
                    $results.Add([pscustomobject]@{id=$check.id;status='PASS';reason='binary exists and hash matches';observed='HASH_MATCH'})
                }
                'process-conflict' {
                    $found = @(& $Adapter.FindProcesses @($check.names))
                    if ($found.Count -gt 0) { $results.Add([pscustomobject]@{id=$check.id;status='FAIL_INFRASTRUCTURE';reason='conflicting ProxyBridge process is active';observed_count=$found.Count}) }
                    else { $results.Add([pscustomobject]@{id=$check.id;status='PASS';reason='no conflicting process';observed_count=0}) }
                }
                'service-observation' {
                    $serviceName = Get-HealthEnvironmentValue -Environment $Environment -Name ([string]$check.service_key)
                    if ([string]::IsNullOrWhiteSpace($serviceName)) { $results.Add([pscustomobject]@{id=$check.id;status='PASS';reason='optional service observation not configured';observed='NOT_CONFIGURED'}); break }
                    $service = & $Adapter.GetServiceState $serviceName
                    if (-not [bool]$service.exists) { $results.Add([pscustomobject]@{id=$check.id;status='FAIL_INFRASTRUCTURE';reason='configured driver service was not found';observed=[string]$service.state;exists=$false}) }
                    else { $results.Add([pscustomobject]@{id=$check.id;status='PASS';reason='service state observed without mutation';observed=[string]$service.state;exists=$true}) }
                }
                'tcp-reachability' {
                    $hostName = Get-HealthEnvironmentValue -Environment $Environment -Name ([string]$check.host_key) -Required:$check.required
                    $portText = Get-HealthEnvironmentValue -Environment $Environment -Name ([string]$check.port_key) -Required:$check.required
                    $port = 0
                    if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { $results.Add([pscustomobject]@{id=$check.id;status='FAIL_INFRASTRUCTURE';reason="invalid port in $($check.port_key)";observed='INVALID_PORT'}); break }
                    if (& $Adapter.TestTcp $hostName $port $NetworkTimeoutMs) { $results.Add([pscustomobject]@{id=$check.id;status='PASS';reason='TCP endpoint reachable';observed='REACHABLE'}) }
                    else { $results.Add([pscustomobject]@{id=$check.id;status='FAIL_INFRASTRUCTURE';reason="TCP endpoint unreachable: $($check.host_key)/$($check.port_key)";observed='UNREACHABLE'}) }
                }
                default { $results.Add([pscustomobject]@{id=$check.id;status='FAIL_INFRASTRUCTURE';reason="unsupported health check type '$($check.type)'";observed='UNSUPPORTED'}) }
            }
        }
        catch { $results.Add([pscustomobject]@{id=$check.id;status='FAIL_INFRASTRUCTURE';reason=$_.Exception.Message;observed='CHECK_EXCEPTION'}) }
    }
    foreach ($result in $results) {
        if ($null -ne $result.PSObject.Properties['remediation']) { continue }
        $remediation = ''
        if ([string]$result.status -ne 'PASS') {
            if ([string]$result.id -match 'binary') { $remediation = 'Correct the configured absolute binary path or exact SHA-256 before runtime.' }
            elseif ([string]$result.id -match 'reachability') { $remediation = 'Verify the configured endpoint listener and existing route outside the harness; no firewall change is attempted.' }
            else { $remediation = 'Correct the immutable runtime prerequisite and retry.' }
        }
        $result | Add-Member -NotePropertyName remediation -NotePropertyValue $remediation
    }
    return $results.ToArray()
}

function Test-HealthResults {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Results)
    $failed = @($Results | Where-Object { [string]$_.status -ne 'PASS' })
    return [pscustomobject]@{ passed=($failed.Count -eq 0); failures=$failed; total=@($Results).Count }
}

Export-ModuleMember -Function New-HealthCheckPlan, New-SystemHealthCheckAdapter, New-MockHealthCheckAdapter, Invoke-HealthCheckPlan, Test-HealthResults
