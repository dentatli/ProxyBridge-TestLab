[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
foreach ($module in @('ProcessAdapter','ProxyBridgeCli','ClientRunner')) { Import-Module (Join-Path $root "modules/$module.psm1") -Force }

$systemAdapter = New-SystemProcessAdapter
Assert-True (-not [bool]$systemAdapter.is_mock) 'system adapter type must compile without starting a process'

$cliPath = 'C:\Fixture\ProxyBridge_CLI.exe'
$plan = New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath 'C:\Fixture\one.pbprofile' -ReadyRegex 'fixture ready' -ReadyStableMs 25 -ReadinessTimeoutMs 100 -StopTimeoutMs 100
Assert-Throws { New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath 'C:\Fixture\one.pbprofile' -ReadyRegex '[' } 'CLI_READINESS_REGEX_INVALID' 'invalid configured readiness regex must fail before process start'
Assert-Throws { New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath 'C:\Fixture\one.pbprofile' -ReadyRegex '' -ReadyStableMs 0 } 'CLI_READINESS_SIGNAL_REQUIRED' 'empty readiness regex requires a stable-process window'

$readinessEvidence = [System.Collections.Generic.List[object]]::new()
$readinessAdapter = New-MockProcessAdapter -Ready $false -StableReady $true -GracefulStop $true -ActualPath $cliPath
$readinessSink = { param($record) $readinessEvidence.Add($record) }.GetNewClosure()
Assert-Throws { Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter $readinessAdapter -EvidenceSink $readinessSink } 'CLI_READINESS_TIMEOUT' 'readiness timeout must fail precisely'
Assert-Equal 1 $readinessAdapter.state.stop_count 'readiness timeout must stop process in finally'
Assert-Equal 1 $readinessAdapter.state.dispose_count 'readiness timeout must dispose process'
Assert-Equal 1 $readinessEvidence.Count 'readiness timeout must save lifecycle evidence'

$stablePlan = New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath 'C:\Fixture\one.pbprofile' -ReadyRegex '' -ReadyStableMs 25 -ReadinessTimeoutMs 100 -StopTimeoutMs 100
$stableAdapter = New-MockProcessAdapter -Ready $false -StableReady $true -GracefulStop $true -ActualPath $cliPath
$stableResult = Invoke-ProxyBridgeCliLifecycle -Plan $stablePlan -ProcessAdapter $stableAdapter -Workload { 'stable fallback' }
Assert-True $stableResult.ready 'empty readiness regex may use stable-process fallback'

$unknownPathAdapter = New-MockProcessAdapter -Ready $true -GracefulStop $true -ActualPath ''
Assert-Throws { Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter $unknownPathAdapter } 'CLI_PATH_VERIFICATION_FAILED' 'ActualPath query failure must not fall back to requested path'
Assert-Equal 1 $unknownPathAdapter.state.stop_count 'path verification failure must still stop process in finally'

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
