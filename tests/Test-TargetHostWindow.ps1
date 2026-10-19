$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TargetHostWindow.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../modules/TargetAcceptCohort.psm1') -Force
$checks=0
foreach ($case in @('confirmed','expired-before','expired-wait','expired-validation','readiness-changed')) {
    $state=[pscustomobject]@{ms=$(if($case -eq 'expired-before'){15000}else{1000});checks=0;released=0;cleaned=0;started=0}
    $elapsed={$state.ms}.GetNewClosure()
    $confirmed={$case -ne 'expired-wait'}.GetNewClosure()
    $validate={
        $state.checks++
        if($case -eq 'expired-validation'){$state.ms=15000}
        if($case -eq 'readiness-changed'){throw 'TARGET_PREFILL_CHANGED_NO_CONTROL'}
    }.GetNewClosure()
    $sleep={$state.ms+=1000}.GetNewClosure()
    $ready=[pscustomobject]@{}
    $ready | Add-Member ScriptMethod WaitOne {param($ms);return $true}
    $release=[pscustomobject]@{state=$state}
    $release | Add-Member ScriptMethod Set {$this.state.released++;return $true}
    $gate=[pscustomobject]@{used=$false;ready=$ready;release=$release}
    $windowCommand=Get-Command Wait-TargetHostWindow
    $before={param($f)
        if($f -ne 'fillers'){throw 'WRONG_FILLERS'}
        $null=& $windowCommand -Elapsed $elapsed -Confirmed $confirmed -ValidateReady $validate -PollSleep $sleep
    }.GetNewClosure()
    $start={$state.started++;return 'control'}.GetNewClosure()
    $cleanup={param($f,$c);$state.cleaned++;if($state.released -lt 1){throw 'CLEANUP_BEFORE_RELEASE'}}.GetNewClosure()
    $failed=$false
    try {Invoke-TargetAcceptSequence -Gate $gate -StartFillers {'fillers'} -WaitFillers {} -StartControl $start -WaitControlSyn {} -Hold {} -Collect {} -Cleanup $cleanup -BeforeControl $before}
    catch {$failed=$true}
    if($failed -ne ($case -ne 'confirmed')){throw ('BAD_VERDICT_'+$case)}
    if($state.started -ne $(if($case -eq 'confirmed'){1}else{0})){throw ('CONTROL_STARTED_WITHOUT_VALID_WINDOW_'+$case)}
    if($state.cleaned -ne 1 -or $state.released -lt 1){throw ('CLEANUP_MISSING_'+$case)}
    $checks++
}
Write-Output ('TARGET_HOST_WINDOW_5_FAULT_CASES_PASSED_NO_TRAFFIC: '+$checks)
