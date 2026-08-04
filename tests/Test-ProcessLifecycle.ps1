[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
foreach ($module in @('ProcessAdapter','ProxyBridgeCli','ClientRunner')) { Import-Module (Join-Path $root "modules/$module.psm1") -Force }

$systemAdapter = New-SystemProcessAdapter
Assert-True (-not [bool]$systemAdapter.is_mock) 'system adapter type must compile without starting a process'

$cliPath = 'C:\Fixture\ProxyBridge_CLI.exe'
$defaultPlan = New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath 'C:\Fixture\one.pbprofile' -ReadyRegex 'fixture ready'
Assert-Equal 2000 $defaultPlan.actual_path_timeout_ms 'actual path probe default timeout must be 2000 ms'
Assert-Equal 25 $defaultPlan.actual_path_probe_interval_ms 'actual path probe interval must be within the required range'
$plan = New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath 'C:\Fixture\one.pbprofile' -ReadyRegex 'fixture ready' -ReadyStableMs 25 -ReadinessTimeoutMs 100 -StopTimeoutMs 100 -ActualPathTimeoutMs 50
Assert-Throws { New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath 'C:\Fixture\one.pbprofile' -ReadyRegex '[' } 'CLI_READINESS_REGEX_INVALID' 'invalid configured readiness regex must fail before process start'
Assert-Throws { New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath 'C:\Fixture\one.pbprofile' -ReadyRegex '' -ReadyStableMs 0 } 'CLI_READINESS_SIGNAL_REQUIRED' 'empty readiness regex requires a stable-process window'
Assert-Throws { New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath 'C:\Fixture\one.pbprofile' -ReadyRegex 'fixture' -ActualPathTimeoutMs 0 } 'CLI_TIMEOUT_CONFIGURATION_INVALID' 'actual path timeout must be positive'

$readinessEvidence = [System.Collections.Generic.List[object]]::new()
$readinessAdapter = New-MockProcessAdapter -Ready $false -StableReady $true -GracefulStop $true -ActualPath $cliPath
$readinessSink = { param($record) $readinessEvidence.Add($record) }.GetNewClosure()
Assert-Throws { Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter $readinessAdapter -EvidenceSink $readinessSink } 'CLI_READINESS_TIMEOUT' 'readiness timeout must fail precisely'
Assert-Equal 1 $readinessAdapter.state.stop_count 'readiness timeout must stop process in finally'
Assert-Equal 1 $readinessAdapter.state.dispose_count 'readiness timeout must dispose process'
Assert-Equal 1 $readinessEvidence.Count 'readiness timeout must save lifecycle evidence'
Assert-Equal 'PATH_OBTAINED' $readinessEvidence[0].actual_path_probe_status 'readiness evidence must retain path probe status'
Assert-Equal 1 $readinessEvidence[0].actual_path_probe_attempts 'immediate path probe must take one attempt'

$stablePlan = New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath 'C:\Fixture\one.pbprofile' -ReadyRegex '' -ReadyStableMs 25 -ReadinessTimeoutMs 100 -StopTimeoutMs 100
$stableAdapter = New-MockProcessAdapter -Ready $false -StableReady $true -GracefulStop $true -ActualPath $cliPath
$stableResult = Invoke-ProxyBridgeCliLifecycle -Plan $stablePlan -ProcessAdapter $stableAdapter -Workload { 'stable fallback' }
Assert-True $stableResult.ready 'empty readiness regex may use stable-process fallback'

$delayedEvidence = [System.Collections.Generic.List[object]]::new()
$delayedAdapter = New-MockProcessAdapter -Ready $true -GracefulStop $true -ActualPathProbeSequence @('', '', $cliPath)
$delayedSink = { param($record) $delayedEvidence.Add($record) }.GetNewClosure()
$delayedResult = Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter $delayedAdapter -EvidenceSink $delayedSink
Assert-True $delayedResult.ready 'actual path unavailable for first probes then correct must pass'
Assert-Equal 'PATH_OBTAINED' $delayedResult.actual_path_probe_status 'delayed path probe status'
Assert-Equal 3 $delayedResult.actual_path_probe_attempts 'delayed path probe attempt count'
Assert-Equal 50 $delayedResult.actual_path_probe_elapsed_ms 'delayed path probe elapsed time'
Assert-Equal 1 $delayedEvidence.Count 'delayed path probe must emit evidence'

$timeoutEvidence = [System.Collections.Generic.List[object]]::new()
$timeoutAdapter = New-MockProcessAdapter -Ready $true -GracefulStop $true -ActualPath $cliPath -ActualPathProbeSequence @('', '', '')
$timeoutSink = { param($record) $timeoutEvidence.Add($record) }.GetNewClosure()
Assert-Throws { Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter $timeoutAdapter -EvidenceSink $timeoutSink } 'CLI_ACTUAL_PATH_QUERY_TIMEOUT' 'unavailable actual path until timeout must fail explicitly'
Assert-Equal 1 $timeoutAdapter.state.stop_count 'path query timeout must still stop process in finally'
Assert-Equal 'QUERY_TIMEOUT' $timeoutEvidence[0].actual_path_probe_status 'path query timeout evidence status'
Assert-Equal '' $timeoutEvidence[0].actual_path 'path query timeout must not fall back to requested path'

$wrongPathEvidence = [System.Collections.Generic.List[object]]::new()
$wrongPathAdapter = New-MockProcessAdapter -Ready $true -GracefulStop $true -ActualPathProbeSequence @('C:\Fixture\Unexpected.exe')
$wrongPathSink = { param($record) $wrongPathEvidence.Add($record) }.GetNewClosure()
Assert-Throws { Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter $wrongPathAdapter -EvidenceSink $wrongPathSink } 'CLI_PATH_VERIFICATION_FAILED' 'obtained wrong path must fail verification'
Assert-Equal 'PATH_OBTAINED' $wrongPathEvidence[0].actual_path_probe_status 'wrong path must remain distinct from query failure'

$exitEvidence = [System.Collections.Generic.List[object]]::new()
$exitAdapter = New-MockProcessAdapter -Ready $true -GracefulStop $true -ActualPathProbeSequence @('', '__PROCESS_EXITED__')
$exitSink = { param($record) $exitEvidence.Add($record) }.GetNewClosure()
Assert-Throws { Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter $exitAdapter -EvidenceSink $exitSink } 'CLI_ACTUAL_PATH_PROCESS_EXITED' 'process exit before actual path must fail explicitly'
Assert-Equal 'PROCESS_EXITED' $exitEvidence[0].actual_path_probe_status 'early process exit evidence status'
Assert-Equal 0 $exitAdapter.state.stop_count 'already-exited process must not be stopped again'
Assert-True $exitEvidence[0].post_stop_verified 'already-exited process must still pass cleanup verification'

$workloadAdapter = New-MockProcessAdapter -Ready $true -GracefulStop $true -ActualPath $cliPath
Assert-Throws { Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter $workloadAdapter -Workload { throw 'FIXTURE_WORKLOAD_EXCEPTION' } } 'FIXTURE_WORKLOAD_EXCEPTION' 'workload exception must propagate'
Assert-Equal 1 $workloadAdapter.state.stop_count 'workload exception must stop CLI'
Assert-Equal 1 $workloadAdapter.state.dispose_count 'workload exception must dispose CLI'

$forcedAdapter = New-MockProcessAdapter -Ready $true -GracefulStop $false -ActualPath $cliPath
$forcedResult = Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter $forcedAdapter -Workload { 'fixture workload' }
Assert-True $forcedResult.forced_stop 'failed graceful stop must force stop'
Assert-Equal 1 $forcedAdapter.state.kill_count 'forced stop must kill exactly once'
Assert-True $forcedResult.post_stop_verified 'forced stop must verify stopped state'
Assert-Equal 1 $forcedAdapter.state.dispose_count 'forced stop must dispose process'

$largeStdout = 'O' * 200000
$largeStderr = 'E' * 200000
$largeResult = [pscustomobject]@{exit_code=0;timed_out=$false;pid=8;actual_path='fixture.exe';stdout=$largeStdout;stderr=$largeStderr}
$captured = Invoke-ProcessPlan -Plan ([pscustomobject]@{executable='fixture.exe';arguments=@();timeout_ms=100}) -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($largeResult))
Assert-Equal $largeStdout.Length $captured.stdout.Length 'pipe-heavy stdout must be drained'
Assert-Equal $largeStderr.Length $captured.stderr.Length 'pipe-heavy stderr must be drained'

$timeoutResult = [pscustomobject]@{exit_code=-1;timed_out=$true;pid=9;actual_path='fixture-client.exe';stdout='partial';stderr='timeout'}
$timeoutPlan = [pscustomobject]@{executable='fixture-client.exe';arguments=@();timeout_ms=10;jsonl_path='unused-on-timeout.jsonl'}
$clientTimeout = Invoke-ClientPlan -Plan $timeoutPlan -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($timeoutResult))
Assert-True $clientTimeout.timed_out 'client timeout must be returned without blocking on JSONL'
Assert-Equal 0 @($clientTimeout.records).Count 'timed-out client must not parse absent JSONL'

'PASS: process lifecycle'
