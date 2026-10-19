$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$module=Import-Module (Join-Path $root 'modules/TargetAcceptNative.psm1') -Force -PassThru
& $module {
    function script:Initialize-TargetTcpTable {}
    function script:Get-CimInstance {param($Filter,$OperationTimeoutSec);[pscustomobject]@{ExecutablePath='C:\fake\ctsTraffic.exe';CommandLine='fixture'}}
    function script:Write-TargetJson($Value,$Path) {
        if ($script:fault -eq 'save' -and $Path -like '*-process.json') {throw 'fixture-save-failed'}
    }
    function script:Invoke-TargetAcceptSequence {
        param($Gate,$StartFillers,$WaitFillers,$StartControl,$WaitControlSyn,$Hold,$Collect,$Cleanup)
        $f=$null;$c=$null
        try {$f=& $StartFillers;$c=& $StartControl;& $Collect $f $c}
        finally {& $Cleanup $f $c}
    }
    foreach ($probeOnly in @($false,$true)) {
    foreach ($script:fault in @('none','path','wait','save','dispose')) {
        $script:launches=[Collections.Generic.List[object]]::new()
        $script:disposed=0
        $adapter=[pscustomobject]@{
            StartProcess={param($plan)
                $script:launches.Add($plan)
                $session=[pscustomobject]@{IsRunning=$false}
                $session | Add-Member ScriptMethod WaitForExit {param($ms);return $script:fault -ne 'wait'}
                [pscustomobject]@{pid=(900+$script:launches.Count);actual_path='C:\fake\ctsTraffic.exe';session=$session}
            }
            ProbeActualPath={param($child,$timeout,$interval)
                [pscustomobject]@{status=$(if ($script:fault -eq 'path') {'MISSING'} else {'PATH_OBTAINED'})}
            }
            KillProcess={param($child);throw 'UNEXPECTED_KILL'}
            GetProcessResult={param($child);[pscustomobject]@{pid=$child.pid;exit_code=0}}
            DisposeProcess={param($child);$script:disposed++;if ($script:fault -eq 'dispose') {throw 'fixture-dispose-failed'}}
        }
        $context=[pscustomobject]@{client='C:\fake\ctsTraffic.exe';directory='C:\fixture';adapter=$adapter;probe_only=$probeOnly}
        $failed=$false
        try {Invoke-TargetNativeCohort -Context $context -Gate ([pscustomobject]@{})} catch {$failed=$true}
        if ($failed -ne ($script:fault -ne 'none')) {throw ('FAULT_VERDICT_DIFFERS_'+$script:fault)}
        $expected=$(if ($script:fault -eq 'path') {1} else {2})
        if ($script:disposed -ne $expected) {throw ('PARTIAL_CHILD_OWNERSHIP_LOST_'+$script:fault)}
        if ($script:fault -eq 'none') {
            $expectedCount=if ($probeOnly) {3} else {200}
            $expectedRange=if ($probeOnly) {'-LocalPort:[42001,42003]'} else {'-LocalPort:[42001,42200]'}
            if ($expectedRange -notin $script:launches[0].arguments -or
                '-LocalPort:42201' -notin $script:launches[1].arguments -or
                ('-connections:'+$expectedCount) -notin $script:launches[0].arguments -or
                '-connections:1' -notin $script:launches[1].arguments) {throw 'NATIVE_ROLE_ARGUMENTS_DIFFERS'}
        }
    }
    }
}
Write-Output 'TARGET_NATIVE_FAULTS_10_PASSED_NO_PROCESSES_OR_TRAFFIC'
