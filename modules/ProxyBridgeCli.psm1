Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProcessAdapter.psm1')

function New-ProxyBridgeCliPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string]$ProfilePath,
        [string]$ReadyRegex = '',
        [int]$ReadyStableMs = 1000,
        [int]$ReadinessTimeoutMs = 10000,
        [int]$StopTimeoutMs = 5000
    )
    if ($ReadinessTimeoutMs -lt 1 -or $StopTimeoutMs -lt 1 -or $ReadyStableMs -lt 0) { throw 'CLI_TIMEOUT_CONFIGURATION_INVALID' }
    if ([string]::IsNullOrWhiteSpace($ReadyRegex) -and $ReadyStableMs -lt 1) { throw 'CLI_READINESS_SIGNAL_REQUIRED' }
    if (-not [string]::IsNullOrWhiteSpace($ReadyRegex)) {
        try { $null = [regex]::new($ReadyRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
        catch { throw 'CLI_READINESS_REGEX_INVALID' }
    }
    return [pscustomobject][ordered]@{
        executable = $ExecutablePath
        arguments = @('--profile', $ProfilePath, '--verbose', '3')
        expected_path = $ExecutablePath
        readiness_regex = $ReadyRegex
        readiness_stable_ms = $ReadyStableMs
        readiness_timeout_ms = $ReadinessTimeoutMs
        stop_timeout_ms = $StopTimeoutMs
        timeout_ms = $ReadinessTimeoutMs + $StopTimeoutMs
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
    foreach ($member in @('StartProcess', 'WaitForReadiness', 'StopProcess', 'KillProcess', 'IsRunning', 'GetProcessResult', 'DisposeProcess')) {
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
    $startedAt = (Get-Date).ToUniversalTime()
    $completedAt = $null

    try {
        $process = & $ProcessAdapter.StartProcess $Plan
        if ($null -eq $process -or [int]$process.pid -le 0) { throw 'CLI_START_FAILED' }
        if (-not (Test-EquivalentExecutablePath -Expected ([string]$Plan.expected_path) -Actual ([string]$process.actual_path))) { throw 'CLI_PATH_VERIFICATION_FAILED' }
        $ready = [bool](& $ProcessAdapter.WaitForReadiness $process $Plan.readiness_regex $Plan.readiness_timeout_ms $Plan.readiness_stable_ms)
        if (-not $ready) { throw 'CLI_READINESS_TIMEOUT' }
        if ($null -ne $Workload) { $workloadResult = & $Workload }
    }
    catch { $primaryError = $_ }
    finally {
        if ($null -ne $process) {
            try {
                if (& $ProcessAdapter.IsRunning $process) {
                    $gracefulStop = [bool](& $ProcessAdapter.StopProcess $process $Plan.stop_timeout_ms)
                    if (-not $gracefulStop -or (& $ProcessAdapter.IsRunning $process)) {
                        $forcedStop = $true
                        & $ProcessAdapter.KillProcess $process
                    }
                }
                else { $gracefulStop = $true }
                $postStopVerified = -not [bool](& $ProcessAdapter.IsRunning $process)
                if (-not $postStopVerified) { throw 'CLI_POST_STOP_VERIFICATION_FAILED' }
                $processResult = & $ProcessAdapter.GetProcessResult $process
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
            ready = $ready
            graceful_stop = $gracefulStop
            forced_stop = $forcedStop
            post_stop_verified = $postStopVerified
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
