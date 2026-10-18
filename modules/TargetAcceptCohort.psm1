Set-StrictMode -Version Latest

function New-TargetAcceptGate {
    $token=[guid]::NewGuid().ToString('N')
    $ready=$null;$release=$null
    try {
        $created=$false
        $ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,('Local\PBTarget-'+$token+'-ready'),[ref]$created)
        if (-not $created) {throw 'TARGET_READY_EVENT_ALREADY_EXISTS'}
        $created=$false
        $release=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,('Local\PBTarget-'+$token+'-release'),[ref]$created)
        if (-not $created) {throw 'TARGET_RELEASE_EVENT_ALREADY_EXISTS'}
        return [pscustomobject]@{token=$token;ready=$ready;release=$release;used=$false}
    } catch {if ($release) {$release.Dispose()};if ($ready) {$ready.Dispose()};throw}
}

function Close-TargetAcceptGate($Gate) {
    try {$null=$Gate.release.Set()} finally {$Gate.release.Dispose();$Gate.ready.Dispose()}
}

function Invoke-TargetAcceptSequence {
    # Callbacks isolate orchestration from OS/network APIs for offline fault tests.
    param([Parameter(Mandatory)]$Gate,[Parameter(Mandatory)][scriptblock]$StartFillers,
          [Parameter(Mandatory)][scriptblock]$WaitFillers,[Parameter(Mandatory)][scriptblock]$StartControl,
          [Parameter(Mandatory)][scriptblock]$WaitControlSyn,[Parameter(Mandatory)][scriptblock]$Hold,
          [Parameter(Mandatory)][scriptblock]$Collect,[Parameter(Mandatory)][scriptblock]$Cleanup)
    if ($Gate.used) {throw 'TARGET_GATE_ALREADY_USED'}
    $Gate.used=$true
    $fillers=$null;$control=$null
    try {
        $fillers=& $StartFillers
        if (-not $Gate.ready.WaitOne(5000)) {throw 'TARGET_CORE_GATE_NOT_READY'}
        & $WaitFillers $fillers
        $control=& $StartControl
        & $WaitControlSyn $control
        & $Hold
        if (-not $Gate.release.Set()) {throw 'TARGET_RELEASE_FAILED'}
        & $Collect $fillers $control
    } finally {
        # Release on every partial-start/error path before stopping any process.
        try {$null=$Gate.release.Set()}
        finally {& $Cleanup $fillers $control}
    }
}

Export-ModuleMember -Function New-TargetAcceptGate,Close-TargetAcceptGate,Invoke-TargetAcceptSequence
