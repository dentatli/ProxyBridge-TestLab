Set-StrictMode -Version Latest

function Get-RuntimeEnvironmentValue {
    param([System.Collections.Generic.IDictionary[string, string]]$Environment, [string]$Name)
    if (-not $Environment.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace([string]$Environment[$Name])) {
        throw "FAIL_CONFIGURATION: RUNTIME_ENVIRONMENT_MISSING_$Name"
    }
    $value = [string]$Environment[$Name]
    if ($value -match '(?i)REPLACE_WITH') { throw "FAIL_CONFIGURATION: RUNTIME_PLACEHOLDER_$Name" }
    return $value
}

function Test-EquivalentRuntimePath {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    try {
        $leftFull = [System.IO.Path]::GetFullPath($Left).TrimEnd('\')
        $rightFull = [System.IO.Path]::GetFullPath($Right).TrimEnd('\')
        return [string]::Equals($leftFull, $rightFull, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Test-DocumentationIpAddress {
    param([string]$Value)
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($Value, [ref]$address)) { return $false }
    if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        $bytes = $address.GetAddressBytes()
        return (($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and $bytes[2] -eq 2) -or
            ($bytes[0] -eq 198 -and $bytes[1] -eq 51 -and $bytes[2] -eq 100) -or
            ($bytes[0] -eq 203 -and $bytes[1] -eq 0 -and $bytes[2] -eq 113))
    }
    $bytes = $address.GetAddressBytes()
    return ($bytes.Length -eq 16 -and $bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and $bytes[2] -eq 0x0d -and $bytes[3] -eq 0xb8)
}

function Assert-LiveIpv4Value {
    param([string]$Name, [string]$Value)
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($Value, [ref]$address) -or $address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "FAIL_CONFIGURATION: RUNTIME_IPV4_INVALID_$Name"
    }
    if (Test-DocumentationIpAddress $Value) { throw "FAIL_CONFIGURATION: RUNTIME_TEST_NET_REJECTED_$Name" }
}

function Assert-LiveHostValue {
    param([string]$Name, [string]$Value)
    if ($Value -match '(?i)(^|\.)(example(?:\.com|\.net|\.org)?|invalid)$') { throw "FAIL_CONFIGURATION: RUNTIME_EXAMPLE_HOST_REJECTED_$Name" }
    $address = $null
    if ([System.Net.IPAddress]::TryParse($Value, [ref]$address) -and (Test-DocumentationIpAddress $Value)) {
        throw "FAIL_CONFIGURATION: RUNTIME_DOCUMENTATION_ADDRESS_REJECTED_$Name"
    }
}

function Assert-RuntimePort {
    param([string]$Name, [string]$Value)
    $port = 0
    if (-not [int]::TryParse($Value, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw "FAIL_CONFIGURATION: RUNTIME_PORT_INVALID_$Name" }
}

function New-RuntimeEnvironmentPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [Parameter(Mandatory)]$RuntimeConfig
    )

    foreach ($name in @('PB_VM_IPV4', 'PB_VPS_IPV4')) { Assert-LiveIpv4Value -Name $name -Value (Get-RuntimeEnvironmentValue $Environment $name) }
    foreach ($name in @('PB_SOCKS_HOST', 'PB_SSH_HOST')) { Assert-LiveHostValue -Name $name -Value (Get-RuntimeEnvironmentValue $Environment $name) }
    foreach ($name in @('PB_ENDPOINT_A_PORT', 'PB_ENDPOINT_B_PORT', 'PB_SOCKS_PORT', 'PB_SSH_PORT')) { Assert-RuntimePort -Name $name -Value (Get-RuntimeEnvironmentValue $Environment $name) }

    foreach ($optionalIp in @('PB_VM_IPV6', 'PB_VPS_IPV6')) {
        if ($Environment.ContainsKey($optionalIp) -and -not [string]::IsNullOrWhiteSpace([string]$Environment[$optionalIp])) {
            $optionalValue = Get-RuntimeEnvironmentValue $Environment $optionalIp
            $optionalAddress = $null
            if (-not [System.Net.IPAddress]::TryParse($optionalValue, [ref]$optionalAddress) -or $optionalAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) { throw "FAIL_CONFIGURATION: RUNTIME_IPV6_INVALID_$optionalIp" }
            if (Test-DocumentationIpAddress $optionalValue) { throw "FAIL_CONFIGURATION: RUNTIME_DOCUMENTATION_ADDRESS_REJECTED_$optionalIp" }
        }
    }

    $binaryDefinitions = @(
        @('client', 'PB_CLIENT_EXE', 'PB_EXPECTED_CLIENT_SHA256', ''),
        @('proxybridge-gui', 'PB_PROXYBRIDGE_EXE', 'PB_EXPECTED_PROXYBRIDGE_EXE_SHA256', 'ProxyBridge.exe'),
        @('proxybridge-cli', 'PB_PROXYBRIDGE_CLI_EXE', 'PB_EXPECTED_PROXYBRIDGE_CLI_SHA256', 'ProxyBridge_CLI.exe'),
        @('driver', 'PB_DRIVER_PATH', 'PB_EXPECTED_DRIVER_SHA256', '')
    )
    $optionalProtocolDefinitions = @(
        @('protocol-python', 'PB_PROTOCOL_PYTHON_EXE', 'PB_EXPECTED_PROTOCOL_PYTHON_SHA256', ''),
        @('protocol-worker', 'PB_PROTOCOL_WORKER_ENTRYPOINT', 'PB_EXPECTED_PROTOCOL_WORKER_SHA256', ''),
        @('protocol-manifest', 'PB_PROTOCOL_WORKER_MANIFEST', 'PB_EXPECTED_PROTOCOL_MANIFEST_SHA256', ''),
        @('protocol-evidence-contract', 'PB_PROTOCOL_EVIDENCE_CONTRACT', 'PB_EXPECTED_PROTOCOL_EVIDENCE_CONTRACT_SHA256', ''),
        @('protocol-ca', 'PB_PROTOCOL_CA_PEM', 'PB_EXPECTED_PROTOCOL_CA_SHA256', '')
    )
    $protocolRuntimeRequested = $false
    foreach ($definition in $optionalProtocolDefinitions) {
        if (($Environment.ContainsKey($definition[1]) -and -not [string]::IsNullOrWhiteSpace([string]$Environment[$definition[1]])) -or
            ($Environment.ContainsKey($definition[2]) -and -not [string]::IsNullOrWhiteSpace([string]$Environment[$definition[2]]))) {
            $protocolRuntimeRequested = $true
            break
        }
    }
    if ($protocolRuntimeRequested) { $binaryDefinitions += $optionalProtocolDefinitions }
    $binaries = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in $binaryDefinitions) {
        $configuredPath = Get-RuntimeEnvironmentValue $Environment $definition[1]
        if (-not [System.IO.Path]::IsPathRooted($configuredPath)) { throw "FAIL_CONFIGURATION: RUNTIME_PATH_NOT_ABSOLUTE_$($definition[1])" }
        try { $configuredPath = [System.IO.Path]::GetFullPath($configuredPath).TrimEnd('\') }
        catch { throw "FAIL_CONFIGURATION: RUNTIME_PATH_INVALID_$($definition[1])" }
        $expectedHash = Get-RuntimeEnvironmentValue $Environment $definition[2]
        if ($expectedHash -notmatch '^[A-Fa-f0-9]{64}$') { throw "FAIL_CONFIGURATION: RUNTIME_HASH_INVALID_$($definition[2])" }
        $binaries.Add([pscustomobject][ordered]@{
            id=$definition[0]; path_key=$definition[1]; hash_key=$definition[2]
            configured_path=$configuredPath; expected_sha256=$expectedHash.ToLowerInvariant(); process_name=$definition[3]
        })
    }
    foreach ($absolutePathKey in @('PB_EVIDENCE_ROOT', 'PB_SSH_KEY')) {
        $absolutePath = Get-RuntimeEnvironmentValue $Environment $absolutePathKey
        if (-not [System.IO.Path]::IsPathRooted($absolutePath)) { throw "FAIL_CONFIGURATION: RUNTIME_PATH_NOT_ABSOLUTE_$absolutePathKey" }
    }
    $null = Get-RuntimeEnvironmentValue $Environment 'PB_SSH_USER'
    $null = Get-RuntimeEnvironmentValue $Environment 'PB_VPS_SERVER_LOG'
    $serviceName = Get-RuntimeEnvironmentValue $Environment 'PB_PROXYBRIDGE_SERVICE'

    return [pscustomobject][ordered]@{
        schema_version=1; action='prepare-configured-proxybridge-runtime'; binaries=$binaries.ToArray()
        process_targets=@($binaries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.process_name) })
        service_name=$serviceName
        stop_timeout_ms=[int]$RuntimeConfig.cli_readiness.stop_timeout_ms
        service_start_timeout_ms=[int]$RuntimeConfig.environment_preparation.service_start_timeout_ms
        poll_interval_ms=[int]$RuntimeConfig.environment_preparation.poll_interval_ms
        allowed_mutations=@('stop exact configured ProxyBridge GUI/CLI process', 'start verified configured GUI only when service is Stopped')
        forbidden_mutations=@('install or remove service/driver', 'change firewall', 'run installer or signing scripts')
    }
}

function New-RuntimePreparationFailure {
    param([string]$Reason, [string]$Remediation, $Transitions, $Cleanup, $Validation, $ServiceBefore, $ServiceAfter)
    return [pscustomobject][ordered]@{
        prepared=$false; status='FAIL_INFRASTRUCTURE'; reason=$Reason; remediation=$Remediation
        binary_validation=@($Validation); transitions=@($Transitions); cleanup=$Cleanup
        service_before=$ServiceBefore; service_after=$ServiceAfter
    }
}

function New-SystemRuntimeEnvironmentAdapter {
    [CmdletBinding()]param()
    $adapter = [pscustomobject]@{ is_mock=$false }
    $adapter | Add-Member -NotePropertyName FileExists -NotePropertyValue { param($path) Test-Path -LiteralPath $path -PathType Leaf }
    $adapter | Add-Member -NotePropertyName FileHash -NotePropertyValue { param($path) (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    $adapter | Add-Member -NotePropertyName GetProcesses -NotePropertyValue {
        param($names)
        $wanted = @($names | ForEach-Object { ([string]$_).ToLowerInvariant() })
        $items = foreach ($process in @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)) {
            if ($wanted -notcontains ([string]$process.Name).ToLowerInvariant()) { continue }
            $path = [string]$process.ExecutablePath
            [pscustomobject]@{ name=[string]$process.Name; pid=[int]$process.ProcessId; actual_path=$path; path_status=$(if ([string]::IsNullOrWhiteSpace($path)){'UNREADABLE'}else{'KNOWN'}); running=$true }
        }
        return @($items)
    }
    $adapter | Add-Member -NotePropertyName StopProcess -NotePropertyValue {
        param($record, $timeoutMs)
        try {
            $process = [System.Diagnostics.Process]::GetProcessById([int]$record.pid)
            if ($process.HasExited) { return $true }
            $null = $process.CloseMainWindow()
            return $process.WaitForExit([Math]::Max(1, [int]$timeoutMs))
        }
        catch { return $true }
    }
    $adapter | Add-Member -NotePropertyName KillProcess -NotePropertyValue {
        param($record)
        try { $process=[System.Diagnostics.Process]::GetProcessById([int]$record.pid); if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } catch { }
    }
    $adapter | Add-Member -NotePropertyName IsRunning -NotePropertyValue {
        param($record)
        try { return -not [System.Diagnostics.Process]::GetProcessById([int]$record.pid).HasExited } catch { return $false }
    }
    $adapter | Add-Member -NotePropertyName GetServiceState -NotePropertyValue {
        param($name)
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -eq $service) { return [pscustomobject]@{exists=$false;state='MISSING'} }
        return [pscustomobject]@{exists=$true;state=[string]$service.Status}
    }
    $adapter | Add-Member -NotePropertyName StartGui -NotePropertyValue {
        param($path)
        $info = [System.Diagnostics.ProcessStartInfo]::new()
        $info.FileName = [string]$path; $info.UseShellExecute = $true
        $process = [System.Diagnostics.Process]::Start($info)
        $actual = ''
        try { $actual = [string]$process.MainModule.FileName } catch { }
        return [pscustomobject]@{name='ProxyBridge.exe';pid=[int]$process.Id;actual_path=$actual;path_status=$(if($actual){'KNOWN'}else{'UNREADABLE'});running=$true}
    }
    $adapter | Add-Member -NotePropertyName Sleep -NotePropertyValue { param($milliseconds) Start-Sleep -Milliseconds ([int]$milliseconds) }
    return $adapter
}

function New-MockRuntimeEnvironmentAdapter {
    [CmdletBinding()]
    param(
        [hashtable]$Files=@{},
        [object[]]$Processes=@(),
        [object[]]$ServiceStates=@([pscustomobject]@{exists=$true;state='Running'}),
        [bool]$BootstrapStarts=$true,
        [bool]$BootstrapGracefulStop=$true
    )
    $processList = [System.Collections.Generic.List[object]]::new()
    foreach ($process in @($Processes)) {
        if ($null -eq $process.PSObject.Properties['running']) { $process | Add-Member -NotePropertyName running -NotePropertyValue $true }
        if ($null -eq $process.PSObject.Properties['path_status']) { $process | Add-Member -NotePropertyName path_status -NotePropertyValue $(if([string]::IsNullOrWhiteSpace([string]$process.actual_path)){'UNREADABLE'}else{'KNOWN'}) }
        if ($null -eq $process.PSObject.Properties['graceful_success']) { $process | Add-Member -NotePropertyName graceful_success -NotePropertyValue $true }
        if ($null -eq $process.PSObject.Properties['force_success']) { $process | Add-Member -NotePropertyName force_success -NotePropertyValue $true }
        $processList.Add($process)
    }
    $state = [pscustomobject]@{
        files=$Files; processes=$processList; service_states=@($ServiceStates); service_index=0
        stop_count=0; kill_count=0; bootstrap_count=0; bootstrap_starts=$BootstrapStarts
        bootstrap_graceful_stop=$BootstrapGracefulStop; stopped_pids=[System.Collections.Generic.List[int]]::new(); killed_pids=[System.Collections.Generic.List[int]]::new()
    }
    $adapter = [pscustomobject]@{is_mock=$true;state=$state}
    $adapter | Add-Member -NotePropertyName FileExists -NotePropertyValue ({param($path) $state.files.ContainsKey([string]$path)}.GetNewClosure())
    $adapter | Add-Member -NotePropertyName FileHash -NotePropertyValue ({param($path) [string]$state.files[[string]$path]}.GetNewClosure())
    $adapter | Add-Member -NotePropertyName GetProcesses -NotePropertyValue ({
        param($names)
        $wanted=@($names|ForEach-Object{([string]$_).ToLowerInvariant()})
        return @($state.processes | Where-Object {[bool]$_.running -and $wanted -contains ([string]$_.name).ToLowerInvariant()})
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName StopProcess -NotePropertyValue ({
        param($record,$timeoutMs)
        $state.stop_count++;$state.stopped_pids.Add([int]$record.pid)
        if ([bool]$record.graceful_success) {$record.running=$false;return $true};return $false
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName KillProcess -NotePropertyValue ({
        param($record)
        $state.kill_count++;$state.killed_pids.Add([int]$record.pid);if([bool]$record.force_success){$record.running=$false}
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName IsRunning -NotePropertyValue ({param($record) [bool]$record.running}.GetNewClosure())
    $adapter | Add-Member -NotePropertyName GetServiceState -NotePropertyValue ({
        param($name)
        if (@($state.service_states).Count -eq 0) {return [pscustomobject]@{exists=$false;state='MISSING'}}
        $index=[Math]::Min([int]$state.service_index,@($state.service_states).Count-1);$value=$state.service_states[$index]
        if($state.service_index -lt @($state.service_states).Count-1){$state.service_index++}
        if($value -is [string]){return [pscustomobject]@{exists=([string]$value -ne 'MISSING');state=[string]$value}};return $value
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName StartGui -NotePropertyValue ({
        param($path)
        $state.bootstrap_count++
        if(-not $state.bootstrap_starts){throw 'MOCK_GUI_START_FAILED'}
        $record=[pscustomobject]@{name='ProxyBridge.exe';pid=9000+$state.bootstrap_count;actual_path=[string]$path;path_status='KNOWN';running=$true;graceful_success=[bool]$state.bootstrap_graceful_stop;force_success=$true}
        $state.processes.Add($record);return $record
    }.GetNewClosure())
    $adapter | Add-Member -NotePropertyName Sleep -NotePropertyValue {param($milliseconds)}
    return $adapter
}

function Test-RuntimeEnvironmentClean {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Adapter, [switch]$AllowProductRuntime)
    if (-not [bool]$Adapter.is_mock -and -not $AllowProductRuntime) { throw 'RUNTIME_ENVIRONMENT_ACTION_NOT_ALLOWED' }
    $names=@($Plan.process_targets|ForEach-Object{[string]$_.process_name})
    $processes=@(& $Adapter.GetProcesses $names)
    $service=& $Adapter.GetServiceState ([string]$Plan.service_name)
    $passed=($processes.Count -eq 0 -and [bool]$service.exists -and [string]$service.state -eq 'Running')
    $reason=$(if($processes.Count -gt 0){'ProxyBridge GUI/CLI process remains active'}elseif(-not [bool]$service.exists){'configured driver service is missing'}elseif([string]$service.state -ne 'Running'){"configured driver service state is $($service.state)"}else{'GUI/CLI absent and service Running'})
    return [pscustomobject][ordered]@{passed=$passed;status=$(if($passed){'PASS_CLEAN'}else{'CONTAMINATED'});reason=$reason;remediation=$(if($passed){''}else{'Close only the configured ProxyBridge GUI/CLI binaries and verify the configured service is Running.'});processes=@($processes);service=$service}
}

function Invoke-RuntimeEnvironmentPreparation {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Adapter,[switch]$AllowProductRuntime)
    if (-not [bool]$Adapter.is_mock -and -not $AllowProductRuntime) { throw 'RUNTIME_ENVIRONMENT_ACTION_NOT_ALLOWED' }
    foreach($member in @('FileExists','FileHash','GetProcesses','StopProcess','KillProcess','IsRunning','GetServiceState','StartGui','Sleep')){if($null -eq $Adapter.PSObject.Properties[$member]){throw "RUNTIME_ENVIRONMENT_ADAPTER_MISSING_$($member.ToUpperInvariant())"}}
    $validation=[System.Collections.Generic.List[object]]::new();$transitions=[System.Collections.Generic.List[object]]::new()
    $cleanup=[pscustomobject]@{attempted=$false;graceful=$false;forced=$false;verified=$false}
    $serviceBefore=$null;$serviceAfter=$null

    foreach($binary in @($Plan.binaries)){
        if(-not (& $Adapter.FileExists ([string]$binary.configured_path))){$validation.Add([pscustomobject]@{id=$binary.id;status='MISSING'});return New-RuntimePreparationFailure 'configured binary is missing' "Correct $($binary.path_key) before runtime." $transitions $cleanup $validation $serviceBefore $serviceAfter}
        $actualHash=[string](& $Adapter.FileHash ([string]$binary.configured_path))
        if(-not [string]::Equals($actualHash,[string]$binary.expected_sha256,[System.StringComparison]::OrdinalIgnoreCase)){$validation.Add([pscustomobject]@{id=$binary.id;status='HASH_MISMATCH'});return New-RuntimePreparationFailure 'configured binary hash mismatch' "Correct $($binary.hash_key) or restore the exact binary before runtime." $transitions $cleanup $validation $serviceBefore $serviceAfter}
        $validation.Add([pscustomobject]@{id=$binary.id;status='HASH_MATCH'})
    }

    $targets=@($Plan.process_targets);$names=@($targets|ForEach-Object{[string]$_.process_name});$found=@(& $Adapter.GetProcesses $names)
    $unknown=[System.Collections.Generic.List[object]]::new();$exact=[System.Collections.Generic.List[object]]::new()
    foreach($process in $found){
        $target=@($targets|Where-Object{[string]$_.process_name -ieq [string]$process.name})|Select-Object -First 1
        $known=([string]$process.path_status -eq 'KNOWN' -and -not [string]::IsNullOrWhiteSpace([string]$process.actual_path))
        if($null -eq $target -or -not $known -or -not (Test-EquivalentRuntimePath ([string]$target.configured_path) ([string]$process.actual_path))){$unknown.Add([pscustomobject]@{name=[string]$process.name;pid=[int]$process.pid;path_status=[string]$process.path_status;actual_path=[string]$process.actual_path})}else{$exact.Add($process)}
    }
    if($unknown.Count -gt 0){$transitions.Add([pscustomobject]@{event='UNKNOWN_PROXYBRIDGE_PROCESS_CONFLICT';processes=$unknown.ToArray()});return New-RuntimePreparationFailure 'UNKNOWN_PROXYBRIDGE_PROCESS_CONFLICT' 'Close or identify the same-name process manually; it was not terminated.' $transitions $cleanup $validation $serviceBefore $serviceAfter}
    foreach($process in $exact){
        $graceful=[bool](& $Adapter.StopProcess $process ([int]$Plan.stop_timeout_ms));$forced=$false
        if(-not $graceful -or (& $Adapter.IsRunning $process)){$forced=$true;& $Adapter.KillProcess $process}
        $verified=-not [bool](& $Adapter.IsRunning $process)
        $transitions.Add([pscustomobject]@{event='CONFIGURED_PROCESS_STOP';name=[string]$process.name;pid=[int]$process.pid;graceful=$graceful;forced=$forced;verified=$verified})
        if(-not $verified){return New-RuntimePreparationFailure 'configured ProxyBridge process cleanup failed' 'Stop the exact configured process and retry.' $transitions $cleanup $validation $serviceBefore $serviceAfter}
    }

    $serviceBefore=& $Adapter.GetServiceState ([string]$Plan.service_name)
    if(-not [bool]$serviceBefore.exists){return New-RuntimePreparationFailure 'configured driver service is missing' 'Install/repair the product outside this harness, then retry.' $transitions $cleanup $validation $serviceBefore $serviceAfter}
    if([string]$serviceBefore.state -eq 'Running'){$transitions.Add([pscustomobject]@{event='SERVICE_ALREADY_RUNNING';state='Running'})}
    elseif([string]$serviceBefore.state -eq 'Stopped'){
        $guiTarget=@($targets|Where-Object{[string]$_.process_name -ieq 'ProxyBridge.exe'})|Select-Object -First 1;$bootstrap=$null;$becameRunning=$false
        try{
            $bootstrap=& $Adapter.StartGui ([string]$guiTarget.configured_path)
            if($null -eq $bootstrap -or -not (Test-EquivalentRuntimePath ([string]$guiTarget.configured_path) ([string]$bootstrap.actual_path))){throw 'GUI_BOOTSTRAP_PATH_VERIFICATION_FAILED'}
            $transitions.Add([pscustomobject]@{event='GUI_BOOTSTRAP_STARTED';pid=[int]$bootstrap.pid;path_status=[string]$bootstrap.path_status})
            $elapsed=0
            while($elapsed -lt [int]$Plan.service_start_timeout_ms){
                $observed=& $Adapter.GetServiceState ([string]$Plan.service_name)
                if([bool]$observed.exists -and [string]$observed.state -eq 'Running'){$becameRunning=$true;break}
                & $Adapter.Sleep ([int]$Plan.poll_interval_ms);$elapsed += [int]$Plan.poll_interval_ms
            }
        }
        catch{$transitions.Add([pscustomobject]@{event='GUI_BOOTSTRAP_ERROR';reason=$_.Exception.Message})}
        finally{
            if($null -ne $bootstrap){$cleanup.attempted=$true;$cleanup.graceful=[bool](& $Adapter.StopProcess $bootstrap ([int]$Plan.stop_timeout_ms));if(-not $cleanup.graceful -or (& $Adapter.IsRunning $bootstrap)){$cleanup.forced=$true;& $Adapter.KillProcess $bootstrap};$cleanup.verified=-not [bool](& $Adapter.IsRunning $bootstrap)}
        }
        if(-not $becameRunning){return New-RuntimePreparationFailure 'GUI_BOOTSTRAP_SERVICE_TIMEOUT' 'Start or repair the configured driver service outside this harness; bootstrap GUI was cleaned up.' $transitions $cleanup $validation $serviceBefore $serviceAfter}
        if(-not $cleanup.verified){return New-RuntimePreparationFailure 'GUI_BOOTSTRAP_CLEANUP_FAILED' 'Close the verified configured GUI process before retrying.' $transitions $cleanup $validation $serviceBefore $serviceAfter}
        $transitions.Add([pscustomobject]@{event='SERVICE_BOOTSTRAPPED';state='Running'})
    }
    else{return New-RuntimePreparationFailure "configured driver service state is $($serviceBefore.state)" 'Bring the configured service to Stopped or Running outside this harness.' $transitions $cleanup $validation $serviceBefore $serviceAfter}

    $clean=Test-RuntimeEnvironmentClean -Plan $Plan -Adapter $Adapter -AllowProductRuntime:$AllowProductRuntime;$serviceAfter=$clean.service
    if(-not $clean.passed){return New-RuntimePreparationFailure $clean.reason $clean.remediation $transitions $cleanup $validation $serviceBefore $serviceAfter}
    return [pscustomobject][ordered]@{prepared=$true;status='PASS_PREPARED';reason='configured binaries validated; GUI/CLI absent; service Running';remediation='';binary_validation=$validation.ToArray();transitions=$transitions.ToArray();cleanup=$cleanup;service_before=$serviceBefore;service_after=$serviceAfter}
}

Export-ModuleMember -Function New-RuntimeEnvironmentPlan, Invoke-RuntimeEnvironmentPreparation, Test-RuntimeEnvironmentClean, New-SystemRuntimeEnvironmentAdapter, New-MockRuntimeEnvironmentAdapter
