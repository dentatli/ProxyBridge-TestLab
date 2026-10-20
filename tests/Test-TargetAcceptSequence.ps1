$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../modules/TargetAcceptCohort.psm1') -Force
$checks=0
foreach ($failAt in @('none','start-fillers','ready','fillers','start-control','syn','hold','collect','release')) {
    $trace=[Collections.Generic.List[string]]::new()
    $ready=[pscustomobject]@{pass=($failAt -ne 'ready');trace=$trace}
    $ready | Add-Member ScriptMethod WaitOne {param($milliseconds);$this.trace.Add('ready');return $this.pass}
    $release=[pscustomobject]@{trace=$trace;fail=($failAt -eq 'release')}
    $release | Add-Member ScriptMethod Set {$this.trace.Add('release');if ($this.fail) {throw 'fixture-release'};return $true}
    $gate=[pscustomobject]@{used=$false;ready=$ready;release=$release}
    $startFillers={ $trace.Add('start-fillers');if ($failAt -eq 'start-fillers') {throw 'fixture'};return 'fillers' }.GetNewClosure()
    $waitFillers={param($fillers);$trace.Add('fillers');if ($fillers -ne 'fillers') {throw 'BAD_FILLER_ID'};if ($failAt -eq 'fillers') {throw 'fixture'}}.GetNewClosure()
    $startControl={$trace.Add('start-control');if ($failAt -eq 'start-control') {throw 'fixture'};return 'control'}.GetNewClosure()
    $waitSyn={param($control);$trace.Add('syn');if ($control -ne 'control') {throw 'BAD_CONTROL_ID'};if ($failAt -eq 'syn') {throw 'fixture'}}.GetNewClosure()
    $hold={$trace.Add('hold');if ($failAt -eq 'hold') {throw 'fixture'}}.GetNewClosure()
    $collect={param($fillers,$control);$trace.Add('collect');if ($fillers -ne 'fillers' -or $control -ne 'control') {throw 'BAD_COLLECT_ID'};if ($failAt -eq 'collect') {throw 'fixture'}}.GetNewClosure()
    $cleanup={param($fillers,$control);$trace.Add('cleanup')}.GetNewClosure()
    $failed=$false
    try {Invoke-TargetAcceptSequence $gate $startFillers $waitFillers $startControl $waitSyn $hold $collect $cleanup}
    catch {$failed=$true}
    if ($failed -ne ($failAt -ne 'none')) {throw ('WRONG_OUTCOME_'+$failAt)}
    $last=$trace.Count-1
    if ($trace[$last] -ne 'cleanup' -or $trace[$last-1] -ne 'release') {throw ('RELEASE_BEFORE_CLEANUP_MISSING_'+$failAt)}
    if ($failAt -eq 'none' -and ($trace -join ',') -ne 'start-fillers,ready,fillers,start-control,syn,hold,release,collect,release,cleanup') {throw 'SUCCESS_ORDER_DIFFERS'}
    $before=$trace.Count
    try {Invoke-TargetAcceptSequence $gate $startFillers $waitFillers $startControl $waitSyn $hold $collect $cleanup;throw 'REUSE_ALLOWED'}
    catch {if ($_.Exception.Message -ne 'TARGET_GATE_ALREADY_USED') {throw}}
    if ($trace.Count -ne $before) {throw 'REUSED_GATE_MUTATED'}
    $checks++
}
Write-Output ('TARGET_SEQUENCE_FAKE_9_PASSED: '+$checks)
foreach ($readyFailure in @($false,$true)) {
    $trace=[Collections.Generic.List[string]]::new()
    $ready=[pscustomobject]@{trace=$trace;fail=$readyFailure}
    $ready | Add-Member ScriptMethod WaitOne {
        param($milliseconds)
        $this.trace.Add('ready')
        # Model the real relay dependency: no ready before a client exists.
        return (-not $this.fail) -and $this.trace.Contains('start-control')
    }
    $release=[pscustomobject]@{trace=$trace}
    $release | Add-Member ScriptMethod Set {$this.trace.Add('release');return $true}
    $gate=[pscustomobject]@{used=$false;ready=$ready;release=$release}
    $startFillers={$trace.Add('start-fillers');return $null}.GetNewClosure()
    $waitFillers={param($fillers);if ($null -ne $fillers) {throw 'SINGLE_HAS_FILLERS'};$trace.Add('fillers')}.GetNewClosure()
    $startControl={$trace.Add('start-control');return 'control'}.GetNewClosure()
    $waitSyn={param($control);if ($control -ne 'control') {throw 'CONTROL_LOST'};$trace.Add('syn')}.GetNewClosure()
    $hold={$trace.Add('hold')}.GetNewClosure()
    $collect={param($fillers,$control);if ($null -ne $fillers -or $control -ne 'control') {throw 'SINGLE_COLLECT_OWNERSHIP'};$trace.Add('collect')}.GetNewClosure()
    $cleanup={param($fillers,$control);if ($null -ne $fillers -or $control -ne 'control') {throw 'SINGLE_CLEANUP_OWNERSHIP'};$trace.Add('cleanup')}.GetNewClosure()
    $failed=$false
    try {Invoke-TargetAcceptSequence -Gate $gate -StartFillers $startFillers -WaitFillers $waitFillers -StartControl $startControl -WaitControlSyn $waitSyn -Hold $hold -Collect $collect -Cleanup $cleanup -SingleProbe}
    catch {$failed=$true;if ($_.Exception.Message -ne 'TARGET_CORE_GATE_NOT_READY') {throw}}
    if ($failed -ne $readyFailure) {throw 'SINGLE_READY_DEPENDENCY_FAILED'}
    $expected=if ($readyFailure) {'start-fillers,fillers,start-control,ready,release,cleanup'} else {'start-fillers,fillers,start-control,ready,syn,hold,release,collect,release,cleanup'}
    if (($trace -join ',') -ne $expected) {throw ('SINGLE_ORDER_DIFFERS: '+($trace -join ','))}
}
Write-Output 'TARGET_SINGLE_SEQUENCE_2_PASSED_NO_PROCESSES_OR_TRAFFIC'
