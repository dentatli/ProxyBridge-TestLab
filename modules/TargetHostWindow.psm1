Set-StrictMode -Version Latest

function Wait-TargetHostWindow {
    # All times are relative to the native cohort start, before the Core gate.
    param([Parameter(Mandatory)][scriptblock]$Elapsed,
          [Parameter(Mandatory)][scriptblock]$Confirmed,
          [Parameter(Mandatory)][scriptblock]$ValidateReady,
          [scriptblock]$PollSleep={Start-Sleep -Milliseconds 10})
    $opened=[long](& $Elapsed)
    if ($opened -ge 15000) {throw 'TARGET_HOST_WINDOW_EXPIRED_NO_CONTROL'}
    do {
        if ([long](& $Elapsed) -ge 15000) {throw 'TARGET_HOST_WINDOW_EXPIRED_NO_CONTROL'}
        if (& $Confirmed) {
            & $ValidateReady
            $accepted=[long](& $Elapsed)
            if ($accepted -ge 15000) {throw 'TARGET_HOST_WINDOW_EXPIRED_NO_CONTROL'}
            return [pscustomobject]@{opened_ms=$opened;confirmed_ms=$accepted;deadline_ms=15000;
                source='user-console-C-after-host-g';independent_host_verification=$false}
        }
        & $PollSleep
    } while ($true)
}

Export-ModuleMember -Function Wait-TargetHostWindow
