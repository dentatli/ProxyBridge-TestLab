Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ProcessAdapter.psm1')

function Get-WfpServiceState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$Name, [switch]$AllowProductRuntime)
    if (-not $AllowProductRuntime) { throw 'SERVICE_OBSERVATION_RUNTIME_NOT_ALLOWED' }
    if (-not ('ProxyBridge.TestLab.DriverServiceQuery' -as [type])) {
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'src/pb_service_query.cs'))) -ErrorAction Stop
    }
    $record = [ProxyBridge.TestLab.DriverServiceQuery]::Read($Name)
    $state = $(if (-not $record.Exists) { 'MISSING' } elseif ($record.State -eq 1) { 'Stopped' } elseif ($record.State -eq 4) { 'Running' } else { 'PendingOrUnsettled' })
    return [pscustomobject]@{exists=$record.Exists;state=$state;service_type=$record.ServiceType;path=$record.BinaryPath;source='windows-scm'}
}

function Resolve-DriverServicePath {
    param([string]$Value)
    $path = $Value.Trim()
    if ($path.StartsWith('"') -and $path.EndsWith('"')) { $path = $path.Substring(1, $path.Length - 2) }
    if ($path.StartsWith('\??\')) { $path = $path.Substring(4) }
    if ($path -match '^(?i)\\SystemRoot\\') { $path = Join-Path $env:SystemRoot $path.Substring(12) }
    elseif ($path -match '^(?i)%SystemRoot%\\') { $path = Join-Path $env:SystemRoot $path.Substring(13) }
    elseif ($path -match '^(?i)System32\\') { $path = Join-Path $env:SystemRoot $path }
    # Do not hash UNC/device paths or interpret service command-line arguments.
    if ($path -notmatch '^[A-Za-z]:\\[^"\r\n]+\.sys$') { throw 'DRIVER_SERVICE_PATH_UNSUPPORTED' }
    return [IO.Path]::GetFullPath($path)
}

function Get-WfpServiceObservation {
    param([System.Collections.Generic.IDictionary[string, string]]$Environment)
    $result = [pscustomobject][ordered]@{
        scope='service-configuration-and-file-on-disk'; status='UNOBSERVED'; service_state='UNKNOWN'
        service_exists=$null; configured_file_matches=$false; file_hash_matches=$false
        observed_file_sha256=''; file_path=''; loaded_binary_verified=$false; filter_state_verified=$false
    }
    foreach ($key in @('PB_PROXYBRIDGE_SERVICE','PB_DRIVER_PATH','PB_EXPECTED_DRIVER_SHA256')) {
        if (-not $Environment.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($Environment[$key])) {
            $result.status = 'CONFIGURATION_MISSING'; return $result
        }
    }
    try {
        $driver = Get-WfpServiceState -Name $Environment['PB_PROXYBRIDGE_SERVICE'] -AllowProductRuntime
        if (-not $driver.exists) { $result.service_exists=$false; $result.status='SERVICE_MISSING'; return $result }
        $result.service_exists = $true
        if ($driver.service_type -ne 1) { $result.status='SERVICE_NOT_KERNEL_DRIVER'; return $result }
        $result.service_state = [string]$driver.state
        $result.file_path = Resolve-DriverServicePath ([string]$driver.path)
        $expectedPath = Resolve-DriverServicePath $Environment['PB_DRIVER_PATH']
        $result.configured_file_matches = [string]::Equals($result.file_path, $expectedPath, [StringComparison]::OrdinalIgnoreCase)
        if (-not $result.configured_file_matches) { $result.status='SERVICE_BINARY_PATH_MISMATCH'; return $result }
        $expectedHash = $Environment['PB_EXPECTED_DRIVER_SHA256']
        if ($expectedHash -notmatch '^[a-fA-F0-9]{64}$') { $result.status='EXPECTED_HASH_INVALID'; return $result }
        $result.observed_file_sha256 = (Get-FileHash -LiteralPath $result.file_path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $result.file_hash_matches = $result.observed_file_sha256 -eq $expectedHash
        if (-not $result.file_hash_matches) { $result.status='SERVICE_BINARY_HASH_MISMATCH'; return $result }
        if ($result.service_state -notin @('Running','Stopped')) { $result.status='SERVICE_STATE_UNSETTLED'; return $result }
        $result.status = 'SERVICE_FILE_VERIFIED'
    }
    catch { $result.status='QUERY_FAILED' }
    return $result
}

function Get-WinDivertHandleObservation {
    param([System.Collections.Generic.IDictionary[string, string]]$Environment, [int]$TimeoutMs)
    $result = [pscustomobject][ordered]@{
        observer_contract='windivertctl-v2.2.2-list-text'; scope='observer-compatible-driver-family-at-snapshot'
        configured=$false; status='NOT_CONFIGURED'; capture_complete=$false; observed_handle_count=$null
        handles=@(); observer_sha256=''; observer_dll_sha256=''; files_verified=$false
        loaded_driver_identity_verified=$false; all_driver_families_observed=$false
    }
    $keys = @('PB_WINDIVERT_CTL_EXE','PB_EXPECTED_WINDIVERT_CTL_SHA256','PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256')
    foreach ($key in $keys) {
        if ($Environment.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($Environment[$key])) { $result.configured=$true }
    }
    if (-not $result.configured) { return $result }
    foreach ($key in $keys) {
        if (-not $Environment.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($Environment[$key])) {
            $result.status='CONFIGURATION_INCOMPLETE'; return $result
        }
    }
    $locks = [System.Collections.Generic.List[System.IO.FileStream]]::new()
    try {
        $exe = $Environment['PB_WINDIVERT_CTL_EXE']
        if ($exe -notmatch '^[A-Za-z]:[\\/]' -or [IO.Path]::GetFileName($exe) -ine 'windivertctl.exe') {
            $result.status='OBSERVER_PATH_INVALID'; return $result
        }
        $exe = [IO.Path]::GetFullPath($exe)
        $dll = Join-Path ([IO.Path]::GetDirectoryName($exe)) 'WinDivert.dll'
        $artifacts = @(
            @($exe, 'PB_EXPECTED_WINDIVERT_CTL_SHA256', 'observer_sha256'),
            @($dll, 'PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256', 'observer_dll_sha256')
        )
        foreach ($artifact in $artifacts) {
            $expected = $Environment[$artifact[1]]
            if ($expected -notmatch '^[a-fA-F0-9]{64}$') { $result.status='OBSERVER_EXPECTED_HASH_INVALID'; return $result }
            # Keep both files locked against replacement until the child exits.
            $stream = [IO.File]::Open($artifact[0], [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $locks.Add($stream)
            $hasher = [Security.Cryptography.SHA256]::Create()
            try { $hash = ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
            finally { $hasher.Dispose() }
            $result.($artifact[2]) = $hash
            if ($hash -ne $expected) { $result.status='OBSERVER_HASH_MISMATCH'; return $result }
        }
        $result.files_verified = $true
        # Fixed list mode: no user-supplied filters, watch, kill or uninstall.
        $plan = [pscustomobject]@{executable=$exe;arguments=@('list');process_timeout_ms=$TimeoutMs;actual_path_timeout_ms=500}
        $adapter = New-SystemProcessAdapter
        $execution = & $adapter.Invoke $plan
        if ($execution.timed_out) { $result.status='OBSERVER_TIMEOUT'; return $result }
        if ($execution.exit_code -ne 0) { $result.status='OBSERVER_EXIT_FAILED'; return $result }
        if (-not $execution.output_capture_complete) { $result.status='OBSERVER_CAPTURE_INCOMPLETE'; return $result }
        if (-not [string]::IsNullOrWhiteSpace([string]$execution.stderr)) { $result.status='OBSERVER_STDERR'; return $result }
        # Short-lived list commands may exit before a path query. Launch used
        # an absolute executable path with its file locked throughout.
        if ($execution.actual_path_probe_status -eq 'PATH_OBTAINED' -and
            -not [string]::Equals([IO.Path]::GetFullPath($execution.actual_path), $exe, [StringComparison]::OrdinalIgnoreCase)) {
            $result.status='OBSERVER_PROCESS_PATH_MISMATCH'; return $result
        }
        $records = [System.Collections.Generic.List[object]]::new()
        $pattern = '^OPEN time=-?[0-9]+\.[0-9]{3}s pid=(?<pid>[0-9]+) exe=.+ layer=(?<layer>NETWORK|NETWORK_FORWARD|FLOW|SOCKET|REFLECT) flags=(?<flags>0|(?:SNIFF|DROP|RECV_ONLY|SEND_ONLY|NO_INSTALL)(?:\|(?:SNIFF|DROP|RECV_ONLY|SEND_ONLY|NO_INSTALL))*) priority=(?<priority>-?[0-9]+) filter=".*"$'
        foreach ($line in ([string]$execution.stdout -split '\r?\n')) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $match = [regex]::Match($line, $pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant, [TimeSpan]::FromMilliseconds(250))
            if (-not $match.Success) { $result.status='OBSERVER_OUTPUT_UNRECOGNIZED'; return $result }
            $owner = [uint32]::Parse($match.Groups['pid'].Value, [Globalization.CultureInfo]::InvariantCulture)
            $priority = [int16]::Parse($match.Groups['priority'].Value, [Globalization.CultureInfo]::InvariantCulture)
            # Do not export process paths or filter contents, which can contain private endpoints.
            $records.Add([pscustomobject]@{pid=$owner;layer=$match.Groups['layer'].Value;flags=$match.Groups['flags'].Value;priority=$priority})
        }
        $result.handles = $records.ToArray()
        $result.observed_handle_count = $records.Count
        $result.capture_complete = $true
        $result.status = $(if ($records.Count -eq 0) { 'NO_HANDLES_OBSERVED' } else { 'HANDLES_OBSERVED' })
    }
    catch { $result.status='OBSERVER_QUERY_FAILED' }
    finally { foreach ($stream in $locks) { $stream.Dispose() } }
    return $result
}

function Get-WfpObjectObservation {
    param([int]$TimeoutMs)
    $result = [pscustomobject][ordered]@{
        scope='known-proxybridge-management-guids'; source_revision='63be0ebf9bec92bfba95ef3d6729c375aa9af84e'
        status='UNOBSERVED'; query_complete=$false; visibility_complete=$false; observer_sha256=''
        win32_error=$null; provider_present=$null; sublayer_present=$null; known_callout_count=$null
        visible_filter_count=$null; matching_filter_count=$null; no_known_objects_observed=$false
    }
    $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin/pb_wfp_state.exe'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $result.status='OBSERVER_MISSING'; return $result }
    $stream = $null
    try {
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $result.observer_sha256 = ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $hasher.Dispose() }
        $adapter = New-SystemProcessAdapter
        $execution = & $adapter.Invoke ([pscustomobject]@{executable=$path;arguments=@();process_timeout_ms=$TimeoutMs;actual_path_timeout_ms=500})
        if ($execution.timed_out) { $result.status='OBSERVER_TIMEOUT'; return $result }
        if (-not $execution.output_capture_complete) { $result.status='OBSERVER_CAPTURE_INCOMPLETE'; return $result }
        if (-not [string]::IsNullOrWhiteSpace([string]$execution.stderr)) { $result.status='OBSERVER_STDERR'; return $result }
        $data = [string]$execution.stdout | ConvertFrom-Json -ErrorAction Stop
        if ($data.schema_version -ne 1 -or $data.query_complete -isnot [bool]) { throw 'INVALID_SCHEMA' }
        if (-not $data.query_complete -or $execution.exit_code -ne 0) {
            $result.win32_error = [uint32]$data.win32_error
            $result.status='OBSERVER_QUERY_FAILED'; return $result
        }
        foreach ($name in @('provider_present','sublayer_present','visibility_complete')) {
            if ($data.$name -isnot [bool]) { throw 'INVALID_BOOLEAN' }
        }
        # Native enumeration respects object ACLs; never promote its visibility.
        if ($data.visibility_complete -or [long]$data.win32_error -ne 0) { throw 'INVALID_VISIBILITY' }
        foreach ($name in @('known_callout_count','visible_filter_count','matching_filter_count')) {
            if ([string]$data.$name -notmatch '^\d+$' -or [long]$data.$name -gt 1000256) { throw 'INVALID_COUNT' }
        }
        if ($data.known_callout_count -gt 4 -or $data.matching_filter_count -gt $data.visible_filter_count) { throw 'INVALID_COUNTS' }
        foreach ($name in @('provider_present','sublayer_present','known_callout_count','visible_filter_count','matching_filter_count','win32_error')) { $result.$name = $data.$name }
        $result.query_complete = $true
        $result.no_known_objects_observed = -not $data.provider_present -and -not $data.sublayer_present -and $data.known_callout_count -eq 0 -and $data.matching_filter_count -eq 0
        $result.status = $(if ($result.no_known_objects_observed) { 'NO_KNOWN_OBJECTS_OBSERVED' } else { 'KNOWN_OBJECTS_PRESENT' })
    }
    catch { $result.status='OBSERVER_OUTPUT_OR_QUERY_FAILED' }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
    return $result
}

function Get-InterceptionStateSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [ValidateRange(1000,30000)][int]$TimeoutMs = 5000,
        [switch]$AllowProductRuntime
    )
    if (-not $AllowProductRuntime) { throw 'INTERCEPTION_OBSERVATION_RUNTIME_NOT_ALLOWED' }
    $started = [DateTime]::UtcNow.ToString('o')
    $wfp = Get-WfpServiceObservation -Environment $Environment
    $wfpObjects = Get-WfpObjectObservation -TimeoutMs $TimeoutMs
    $windivert = Get-WinDivertHandleObservation -Environment $Environment -TimeoutMs $TimeoutMs
    $blockers = [System.Collections.Generic.List[string]]::new()
    if ($wfp.status -ne 'SERVICE_FILE_VERIFIED') { $blockers.Add("WFP_$($wfp.status)") }
    if (-not $wfpObjects.query_complete) { $blockers.Add("WFP_OBJECTS_$($wfpObjects.status)") }
    elseif ($wfp.service_state -eq 'Stopped' -and -not $wfpObjects.no_known_objects_observed) { $blockers.Add('WFP_OBJECTS_REMAIN_WHILE_SERVICE_STOPPED') }
    if ($windivert.configured) {
        if (-not $windivert.capture_complete) { $blockers.Add("WINDIVERT_$($windivert.status)") }
        elseif ($windivert.observed_handle_count -gt 0) { $blockers.Add('WINDIVERT_HANDLES_PRESENT') }
    }
    return [pscustomobject][ordered]@{
        schema_version=1; started_at_utc=$started; completed_at_utc=[DateTime]::UtcNow.ToString('o')
        status=$(if ($blockers.Count) { 'BLOCKED' } else { 'PARTIAL_OBSERVATION' })
        current_driver_preparation_allowed=($blockers.Count -eq 0); blocking_reasons=$blockers.ToArray()
        wfp=$wfp; wfp_objects=$wfpObjects; windivert=$windivert
        wfp_detachment_observed=(($wfp.service_state -eq 'Stopped' -or $wfp.service_exists -eq $false) -and $wfpObjects.no_known_objects_observed)
        interception_cleanup_verified=$false; version_switch_ready=$false
        version_switch_blockers=@('WFP_VISIBILITY_AND_SOURCE_BINDING_UNVERIFIED','LOADED_DRIVER_IDENTITY_UNVERIFIED','WINDIVERT_ALL_FAMILIES_UNVERIFIED')
    }
}

function Get-LoadedInterceptionDriverObservation {
    [CmdletBinding()]
    param([switch]$AllowProductRuntime)
    if (-not $AllowProductRuntime) { throw 'DRIVER_OBSERVATION_RUNTIME_NOT_ALLOWED' }
    if (-not ('ProxyBridge.TestLab.LoadedDriverQuery' -as [type])) {
        Add-Type -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/pb_loaded_drivers.cs')
    }
    $names = @([ProxyBridge.TestLab.LoadedDriverQuery]::GetNames())
    $known = @($names | Where-Object { $_ -match '(?i)proxybridge|windivert' })
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($names -join "`n")))).Replace('-','').ToLowerInvariant()
        $otherNames = @($names | Where-Object { $_ -notmatch '(?i)proxybridge|windivert' })
        $otherDigest = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($otherNames -join "`n")))).Replace('-','').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
    [pscustomobject]@{schema_version=1;observed_at_utc=[DateTime]::UtcNow.ToString('o');query_complete=$true;scope='loaded-driver-names';loaded_driver_count=$names.Count;driver_names_sha256=$digest;other_driver_names_sha256=$otherDigest;known_interception_drivers=$known;selected_driver_loaded=@($names | Where-Object { $_ -ieq 'ProxyBridgeDrv.sys' }).Count -gt 0;known_interception_driver_names_absent=$known.Count -eq 0;all_interception_absent_verified=$false}
}

Export-ModuleMember -Function Get-InterceptionStateSnapshot, Get-WfpServiceState, Get-LoadedInterceptionDriverObservation
