[CmdletBinding()]param([switch]$EmitSummary)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root=Split-Path -Parent $PSScriptRoot
foreach($module in @('Env','Config','RuntimeEnvironment')){Import-Module (Join-Path $root "modules/$module.psm1") -Force}

function Copy-Environment {
    param([System.Collections.Generic.IDictionary[string,string]]$Source)
    $copy=[System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($key in $Source.Keys){$copy[[string]$key]=[string]$Source[$key]}
    return ,$copy
}

$environment=Copy-Environment (Import-DotEnv (Join-Path $PSScriptRoot 'fixtures/.env.test'))
$environment['PB_VM_IPV4']='10.20.0.20';$environment['PB_VPS_IPV4']='10.30.0.10';$environment['PB_SOCKS_HOST']='10.40.0.10';$environment['PB_SSH_HOST']='fixture-vps.internal'
$null=$environment.Remove('PB_VM_IPV6');$null=$environment.Remove('PB_VPS_IPV6')
$runtime=Import-RuntimeConfig (Join-Path $root 'config/runtime.json')
$plan=New-RuntimeEnvironmentPlan -Environment $environment -RuntimeConfig $runtime
$files=@{};foreach($binary in @($plan.binaries)){$files[[string]$binary.configured_path]=[string]$binary.expected_sha256}

$placeholder=Copy-Environment $environment;$placeholder['PB_VPS_IPV4']='198.51.100.10'
Assert-Throws {New-RuntimeEnvironmentPlan -Environment $placeholder -RuntimeConfig $runtime} 'RUNTIME_TEST_NET_REJECTED_PB_VPS_IPV4' 'TEST-NET required live endpoint must be rejected'
$exampleHost=Copy-Environment $environment;$exampleHost['PB_SSH_HOST']='fixture.invalid'
Assert-Throws {New-RuntimeEnvironmentPlan -Environment $exampleHost -RuntimeConfig $runtime} 'RUNTIME_EXAMPLE_HOST_REJECTED_PB_SSH_HOST' 'example live host must be rejected'
$relativePath=Copy-Environment $environment;$relativePath['PB_CLIENT_EXE']='bin\pb_net_client.exe'
Assert-Throws {New-RuntimeEnvironmentPlan -Environment $relativePath -RuntimeConfig $runtime} 'RUNTIME_PATH_NOT_ABSOLUTE_PB_CLIENT_EXE' 'relative executable must be rejected'

$gui=@($plan.process_targets|Where-Object process_name -eq 'ProxyBridge.exe')[0]
$cli=@($plan.process_targets|Where-Object process_name -eq 'ProxyBridge_CLI.exe')[0]
$exactProcesses=@(
    [pscustomobject]@{name='ProxyBridge.exe';pid=101;actual_path=$gui.configured_path;path_status='KNOWN';running=$true;graceful_success=$true;force_success=$true},
    [pscustomobject]@{name='ProxyBridge_CLI.exe';pid=102;actual_path=$cli.configured_path;path_status='KNOWN';running=$true;graceful_success=$false;force_success=$true}
)
$badFiles=@{};foreach($key in $files.Keys){$badFiles[$key]=$files[$key]};$badFiles[[string]$gui.configured_path]=('f' * 64)
$badHashProcess=[pscustomobject]@{name='ProxyBridge.exe';pid=100;actual_path=$gui.configured_path;path_status='KNOWN';running=$true;graceful_success=$true;force_success=$true}
$badHashAdapter=New-MockRuntimeEnvironmentAdapter -Files $badFiles -Processes @($badHashProcess) -ServiceStates @('Running')
$badHashResult=Invoke-RuntimeEnvironmentPreparation -Plan $plan -Adapter $badHashAdapter
Assert-True (-not $badHashResult.prepared) 'hash mismatch must fail preparation'
Assert-Equal 0 $badHashAdapter.state.stop_count 'hash mismatch must occur before any process stop'
Assert-True $badHashProcess.running 'hash mismatch must leave process untouched'

$exactAdapter=New-MockRuntimeEnvironmentAdapter -Files $files -Processes $exactProcesses -ServiceStates @('Running')
$exactResult=Invoke-RuntimeEnvironmentPreparation -Plan $plan -Adapter $exactAdapter
Assert-True $exactResult.prepared 'exact configured GUI/CLI processes must be prepared'
Assert-Equal 2 $exactAdapter.state.stop_count 'each exact configured process must get graceful stop first'
Assert-Equal 1 $exactAdapter.state.kill_count 'failed graceful stop must use one bounded force fallback'
Assert-Equal 'PASS_PREPARED' $exactResult.status 'exact process preparation status'

$foreign=[pscustomobject]@{name='ProxyBridge.exe';pid=201;actual_path='D:\Foreign\ProxyBridge.exe';path_status='KNOWN';running=$true;graceful_success=$true;force_success=$true}
$foreignAdapter=New-MockRuntimeEnvironmentAdapter -Files $files -Processes @($foreign) -ServiceStates @('Running')
$foreignResult=Invoke-RuntimeEnvironmentPreparation -Plan $plan -Adapter $foreignAdapter
Assert-True (-not $foreignResult.prepared) 'same-name different-path process must block preparation'
Assert-Equal 'UNKNOWN_PROXYBRIDGE_PROCESS_CONFLICT' $foreignResult.reason 'different path conflict must be precise'
Assert-Equal 0 $foreignAdapter.state.stop_count 'foreign process must not be stopped'
Assert-Equal 0 $foreignAdapter.state.kill_count 'foreign process must not be killed'
Assert-True $foreign.running 'foreign process state must remain untouched'

$runningAdapter=New-MockRuntimeEnvironmentAdapter -Files $files -ServiceStates @('Running')
$runningResult=Invoke-RuntimeEnvironmentPreparation -Plan $plan -Adapter $runningAdapter
Assert-True $runningResult.prepared 'already Running service must pass preparation'
Assert-Equal 0 $runningAdapter.state.bootstrap_count 'already Running service must not bootstrap GUI'

$bootstrapAdapter=New-MockRuntimeEnvironmentAdapter -Files $files -ServiceStates @('Stopped','Running','Running')
$bootstrapResult=Invoke-RuntimeEnvironmentPreparation -Plan $plan -Adapter $bootstrapAdapter
Assert-True $bootstrapResult.prepared 'Stopped service must be bootstrapped by verified GUI'
Assert-Equal 1 $bootstrapAdapter.state.bootstrap_count 'Stopped service must start GUI once'
Assert-Equal 1 $bootstrapAdapter.state.stop_count 'bootstrap GUI must be closed'
$bootstrapClean=Test-RuntimeEnvironmentClean -Plan $plan -Adapter $bootstrapAdapter
Assert-True $bootstrapClean.passed 'post-bootstrap state must have no GUI/CLI and service Running'

$timeoutAdapter=New-MockRuntimeEnvironmentAdapter -Files $files -ServiceStates @('Stopped')
$timeoutResult=Invoke-RuntimeEnvironmentPreparation -Plan $plan -Adapter $timeoutAdapter
Assert-True (-not $timeoutResult.prepared) 'bootstrap service timeout must fail preparation'
Assert-Equal 'GUI_BOOTSTRAP_SERVICE_TIMEOUT' $timeoutResult.reason 'bootstrap timeout reason must be precise'
Assert-True $timeoutResult.cleanup.verified 'bootstrap timeout must clean GUI'
$processNames=@('ProxyBridge.exe','ProxyBridge_CLI.exe')
Assert-Equal 0 @(& $timeoutAdapter.GetProcesses $processNames).Count 'bootstrap timeout must leave no GUI/CLI'

if($EmitSummary){
    "EXACT_PROCESS_PREPARATION=$($exactResult.status) forced_fallback=$($exactAdapter.state.kill_count)"
    "FOREIGN_PROCESS_CONFLICT=$($foreignResult.reason) killed=$($foreignAdapter.state.kill_count)"
    "SERVICE_RUNNING_BOOTSTRAP_COUNT=$($runningAdapter.state.bootstrap_count)"
    "SERVICE_STOPPED_PREPARATION=$($bootstrapResult.status) cleanup=$($bootstrapResult.cleanup.verified)"
    "SERVICE_TIMEOUT=$($timeoutResult.status) cleanup=$($timeoutResult.cleanup.verified)"
}
'PASS: runtime environment preparation'
