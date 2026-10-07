Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProcessAdapter.psm1')

function New-ProxyBridgeCliPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string]$ProfilePath,
        [string]$ReadyRegex = '',
        [int]$ReadyStableMs = 2000,
        [int]$ReadinessTimeoutMs = 15000,
        [int]$StopTimeoutMs = 5000,
        [int]$ActualPathTimeoutMs = 2000,
        [ValidateSet('driver','v4.0.0')][string]$ProductProfileContract = 'driver',
        [ValidateSet('upstream','testlab-unbuffered-v1')][string]$CliVariant = 'upstream'
    )
    # Both pinned CLIs print this after g_Start succeeds and installing their
    # control handler. Surviving a fixed interval is not a startup signal.
    if ($ProductProfileContract -eq 'v4.0.0' -or [string]::IsNullOrWhiteSpace($ReadyRegex)) { $ReadyRegex = '(?m)^ProxyBridge is running\. Press Ctrl\+C to stop\.\r?$' }
    if ($StopTimeoutMs -gt 60000) { throw 'CLI_STOP_TIMEOUT_EXCEEDS_60000_MS' }
    if ($ReadinessTimeoutMs -lt 1 -or $StopTimeoutMs -lt 1 -or $ActualPathTimeoutMs -lt 1 -or $ReadyStableMs -lt 0) { throw 'CLI_TIMEOUT_CONFIGURATION_INVALID' }
    if ([string]::IsNullOrWhiteSpace($ReadyRegex) -and $ReadyStableMs -lt 1) { throw 'CLI_READINESS_SIGNAL_REQUIRED' }
    if (-not [string]::IsNullOrWhiteSpace($ReadyRegex)) {
        try { $null = [regex]::new($ReadyRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
        catch { throw 'CLI_READINESS_REGEX_INVALID' }
    }
    return [pscustomobject][ordered]@{
        executable = $ExecutablePath
        console_host_path = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin/pb_console_host.exe'
        console_output_mode = $(if ($CliVariant -eq 'testlab-unbuffered-v1') { 'pipe' } else { 'terminal' })
        declared_cli_variant = $CliVariant
        product_profile_contract = $ProductProfileContract.ToLowerInvariant()
        arguments = @('--profile', $ProfilePath, '--verbose', '3')
        expected_path = $ExecutablePath
        readiness_regex = $ReadyRegex
        readiness_stable_ms = $ReadyStableMs
        readiness_timeout_ms = $ReadinessTimeoutMs
        stop_timeout_ms = $StopTimeoutMs
        actual_path_timeout_ms = $ActualPathTimeoutMs
        actual_path_probe_interval_ms = 25
        timeout_ms = $ActualPathTimeoutMs + $ReadinessTimeoutMs + $StopTimeoutMs
    }
}

function Test-EquivalentExecutablePath {
    param([string]$Expected, [string]$Actual)
    if ([string]::IsNullOrWhiteSpace($Expected) -or [string]::IsNullOrWhiteSpace($Actual)) { return $false }
    try {
        $expectedFull = [System.IO.Path]::GetFullPath($Expected).TrimEnd('\')
        $actualFull = [System.IO.Path]::GetFullPath($Actual).TrimEnd('\')
        return [string]::Equals($expectedFull, $actualFull, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Invoke-ProxyBridgeCliLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$ProcessAdapter,
        [switch]$AllowProductRuntime,
        [scriptblock]$Workload,
        [scriptblock]$EvidenceSink
    )

    if (-not [bool]$ProcessAdapter.is_mock -and -not $AllowProductRuntime) { throw 'PRODUCT_RUNTIME_NOT_ALLOWED' }
    foreach ($member in @('StartProcess', 'ProbeActualPath', 'WaitForReadiness', 'StopProcess', 'KillProcess', 'IsRunning', 'GetProcessResult', 'DisposeProcess')) {
        if ($null -eq $ProcessAdapter.PSObject.Properties[$member]) { throw "PROCESS_ADAPTER_MISSING_$($member.ToUpperInvariant())" }
    }

    $process = $null
    $workloadResult = $null
    $primaryError = $null
    $cleanupError = $null
    $ready = $false
    $gracefulStop = $false
    $forcedStop = $false
    $postStopVerified = $false
    $processResult = $null
    $actualPathProbeStatus = 'NOT_STARTED'
    $actualPathProbeAttempts = 0
    $actualPathProbeElapsedMs = 0
    $startedAt = (Get-Date).ToUniversalTime()
    $completedAt = $null

    try {
        $process = & $ProcessAdapter.StartProcess $Plan
        if ($null -eq $process -or [int]$process.pid -le 0) { throw 'CLI_START_FAILED' }
        $pathProbe = & $ProcessAdapter.ProbeActualPath $process $Plan.actual_path_timeout_ms $Plan.actual_path_probe_interval_ms
        $actualPathProbeStatus = [string]$pathProbe.status
        $actualPathProbeAttempts = [int]$pathProbe.attempts
        $actualPathProbeElapsedMs = [int]$pathProbe.elapsed_ms
        if ($actualPathProbeStatus -eq 'PROCESS_EXITED') { throw 'CLI_ACTUAL_PATH_PROCESS_EXITED' }
        if ($actualPathProbeStatus -eq 'QUERY_TIMEOUT') { throw 'CLI_ACTUAL_PATH_QUERY_TIMEOUT' }
        if ($actualPathProbeStatus -ne 'PATH_OBTAINED') { throw 'CLI_ACTUAL_PATH_PROBE_FAILED' }
        if (-not (Test-EquivalentExecutablePath -Expected ([string]$Plan.expected_path) -Actual ([string]$pathProbe.actual_path))) { throw 'CLI_PATH_VERIFICATION_FAILED' }
        $ready = [bool](& $ProcessAdapter.WaitForReadiness $process $Plan.readiness_regex $Plan.readiness_timeout_ms $Plan.readiness_stable_ms)
        if (-not $ready) { throw 'CLI_READINESS_TIMEOUT' }
        if ($null -ne $Workload) { $workloadResult = & $Workload $process }
    }
    catch { $primaryError = $_ }
    finally {
        if ($null -ne $process) {
            try {
                if (& $ProcessAdapter.IsRunning $process) {
                    $gracefulStop = [bool](& $ProcessAdapter.StopProcess $process $Plan.stop_timeout_ms)
                    if (& $ProcessAdapter.IsRunning $process) {
                        $forcedStop = $true
                        & $ProcessAdapter.KillProcess $process
                    }
                }
                $postStopVerified = -not [bool](& $ProcessAdapter.IsRunning $process)
                if (-not $postStopVerified) { throw 'CLI_POST_STOP_VERIFICATION_FAILED' }
                $processResult = & $ProcessAdapter.GetProcessResult $process
                if ($null -ne $processResult.PSObject.Properties['stop_transport']) {
                    $transport = [string]$processResult.stop_transport
                    if ($transport -eq 'forced-job-termination') { $forcedStop = $true }
                    if ($forcedStop -or $transport -eq 'console-host-error' -or $transport -eq 'console-host-running') {
                        throw 'CLI_CONTROLLED_SHUTDOWN_FAILED'
                    }
                    if ($ready -and (-not $gracefulStop -or [int]$processResult.exit_code -ne 0)) {
                        throw 'CLI_EXPECTED_SHUTDOWN_NOT_OBSERVED'
                    }
                }
            }
            catch { $cleanupError = $_ }
            finally {
                try { & $ProcessAdapter.DisposeProcess $process }
                catch { if ($null -eq $cleanupError) { $cleanupError = $_ } }
            }
        }

        $completedAt = (Get-Date).ToUniversalTime()
        $evidence = [pscustomobject][ordered]@{
            event = 'CLI_LIFECYCLE'
            started_at_utc = $startedAt.ToString('o')
            completed_at_utc = $completedAt.ToString('o')
            pid = $(if ($null -ne $process) { [int]$process.pid } else { 0 })
            actual_path = $(if ($null -ne $process) { [string]$process.actual_path } else { '' })
            actual_path_probe_status = $actualPathProbeStatus
            actual_path_probe_attempts = $actualPathProbeAttempts
            actual_path_probe_elapsed_ms = $actualPathProbeElapsedMs
            ready = $ready
            graceful_stop = $gracefulStop
            forced_stop = $forcedStop
            post_stop_verified = $postStopVerified
            cleanup_scope = 'owned-cli-process'
            interception_cleanup_verified = $false
            output_format = $(if ($null -ne $processResult -and $null -ne $processResult.PSObject.Properties['output_format']) { [string]$processResult.output_format } else { 'UNOBSERVED' })
            output_capture_complete = $(if ($null -ne $processResult -and $null -ne $processResult.PSObject.Properties['output_capture_complete']) { [bool]$processResult.output_capture_complete } else { $false })
            stop_transport = $(if ($null -ne $processResult -and $null -ne $processResult.PSObject.Properties['stop_transport']) { [string]$processResult.stop_transport } else { 'UNOBSERVED' })
            stdout = $(if ($null -ne $processResult) { [string]$processResult.stdout } else { '' })
            stderr = $(if ($null -ne $processResult) { [string]$processResult.stderr } else { '' })
            primary_error = $(if ($null -ne $primaryError) { [string]$primaryError.Exception.Message } else { '' })
            cleanup_error = $(if ($null -ne $cleanupError) { [string]$cleanupError.Exception.Message } else { '' })
            error = $(if ($null -ne $cleanupError) { "CLI_CLEANUP_FAILED: $([string]$cleanupError.Exception.Message)" } elseif ($null -ne $primaryError) { [string]$primaryError.Exception.Message } else { '' })
        }
        if ($null -ne $EvidenceSink) { & $EvidenceSink $evidence }
    }

    if ($null -ne $cleanupError) {
        $primarySuffix = $(if ($null -ne $primaryError) { "; primary=$([string]$primaryError.Exception.Message)" } else { '' })
        throw "CLI_CLEANUP_FAILED: $([string]$cleanupError.Exception.Message)$primarySuffix"
    }
    if ($null -ne $primaryError) { throw $primaryError }
    return [pscustomobject][ordered]@{
        pid = [int]$process.pid
        started_at_utc = $startedAt.ToString('o')
        completed_at_utc = $completedAt.ToString('o')
        ready = $ready
        graceful_stop = $gracefulStop
        forced_stop = $forcedStop
        post_stop_verified = $postStopVerified
        cleanup_scope = 'owned-cli-process'
        interception_cleanup_verified = $false
        actual_path_probe_status = $actualPathProbeStatus
        actual_path_probe_attempts = $actualPathProbeAttempts
        actual_path_probe_elapsed_ms = $actualPathProbeElapsedMs
        workload_result = $workloadResult
        process_result = $processResult
    }
}

function New-ResetPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Policy)
    switch ($Policy) {
        'none' { return [pscustomobject]@{ policy='none'; supported=$true; operation='no-additional-reset'; manual_only=$false } }
        'process' { return [pscustomobject]@{ policy='process'; supported=$true; operation='stop-cli-and-start-next-profile'; manual_only=$false } }
        'profile' { return [pscustomobject]@{ policy='profile'; supported=$true; operation='stop-cli-and-start-next-profile'; manual_only=$false } }
        'rules_only' { return [pscustomobject]@{ policy='rules_only'; supported=$true; operation='new-cli-profile-boundary'; manual_only=$false } }
        'driver' { return [pscustomobject]@{ policy='driver'; supported=$false; operation='manual-driver-reset'; manual_only=$true } }
        'vm' { return [pscustomobject]@{ policy='vm'; supported=$false; operation='manual-vm-reset'; manual_only=$true } }
        default { throw "RESET_POLICY_UNKNOWN: $Policy" }
    }
}

Export-ModuleMember -Function New-ProxyBridgeCliPlan, Invoke-ProxyBridgeCliLifecycle, New-ResetPlan
