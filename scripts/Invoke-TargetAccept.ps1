#Requires -RunAsAdministrator
[CmdletBinding()]
param([ValidateSet('Prepare','Inspect','Run')][string]$Phase='Inspect',
      [string]$BuildDirectory='', [string]$PlanPath='', [string]$PlanSha='',
      [string]$DebuggerProfile='', [string]$RegistrationReview='', [switch]$DebuggerLoggerEnabled,
      [switch]$CreateTarget, [string]$PositiveCapture='', [string]$PositiveConsole='', [switch]$BoundedLoadReviewed,
      [switch]$ManualHostWindow, [switch]$DebuggerPointsDisabled, [switch]$RetrieveTarget, [switch]$RetrieveProbe,
      [switch]$FlowTarget, [switch]$FlowProfileRegisteredDisabled, [switch]$RemovalTarget,
      [string]$CommandParserProof='', [switch]$RetryTarget, [switch]$FlagTarget, [switch]$FlagProbe, [switch]$FlagCreateArmed, [switch]$FlagAccept64, [switch]$FlagHealthyProbe, [switch]$EndpointWatch)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$sourcePython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
foreach ($name in @('TargetAcceptCohort','TargetAcceptNative','KdBootSessionEvidence','KdResidentDriver',
    'ProcessAdapter','ProxyBridgeCli','ProductBuild','InterceptionState','EtwRedirectCapture')) {
    Import-Module (Join-Path $root ('modules/'+$name+'.psm1'))
}
function Read-TargetJson([string]$Path) {Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json}
function Assert-TargetPlain([string]$Path) {
    $part=[IO.Path]::GetFullPath($Path)
    while ($part) {
        if ((Test-Path -LiteralPath $part) -and ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'TARGET_REPARSE_PATH'}
        $part=[IO.Path]::GetDirectoryName($part)
    }
}
$entry=Join-Path $root 'src/pb_target_accept_plan.py'
if ($Phase -eq 'Prepare') {
    if (-not $BuildDirectory) {throw 'TARGET_BUILD_REQUIRED'}
    $directory=Join-Path $root ('artifacts/diagnostics/pb-target-accept-plan-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    Assert-TargetPlain $directory
    $null=New-Item -ItemType Directory -Path $directory
    Write-TargetJson (Get-KdBootSessionEvidence) (Join-Path $directory 'boot-session.json')
    $prepareArgs=@('prepare','--root',$root,'--build',$BuildDirectory,'--output',$directory)
    if ($DebuggerProfile -or $RegistrationReview) {$prepareArgs+=@('--debugger-profile',$DebuggerProfile,'--registration-review',$RegistrationReview)}
    if ($CreateTarget) {$prepareArgs+=@('--create-target')}
    if ($RetrieveTarget) {$prepareArgs+=@('--retrieve-target')}
    if ($RetrieveProbe) {$prepareArgs+=@('--retrieve-probe')}
    if ($FlowTarget) {$prepareArgs+=@('--flow-target')}
    if ($RemovalTarget) {$prepareArgs+=@('--removal-target')}
    if ($RetryTarget) {$prepareArgs+=@('--retry-target')}
    if ($FlagTarget) {$prepareArgs+=@('--flag-target')}
    if ($FlagProbe) {$prepareArgs+=@('--flag-probe')}
    if ($FlagCreateArmed) {$prepareArgs+=@('--flag-create-armed')}
    if ($FlagAccept64) {$prepareArgs+=@('--flag-accept64')}
    if ($FlagHealthyProbe) {$prepareArgs+=@('--flag-healthy-probe')}
    if ($EndpointWatch) {$prepareArgs+=@('--endpoint-watch')}
    if ($CommandParserProof) {$prepareArgs+=@('--command-parser-proof',$CommandParserProof)}
    if ($ManualHostWindow) {$prepareArgs+=@('--manual-host-window')}
    if ($PositiveCapture) {$prepareArgs+=@('--positive-capture',$PositiveCapture)}
    if ($PositiveConsole) {$prepareArgs+=@('--positive-console',$PositiveConsole)}
    $output=@(& $sourcePython -B $entry @prepareArgs 2>&1)
    $code=$LASTEXITCODE
    $output | Out-String | Set-Content -LiteralPath (Join-Path $directory 'prepare-output.txt') -Encoding UTF8
    Write-TargetJson ([ordered]@{status=$(if ($code -eq 0) {'PREPARED_NOT_RUN'} else {'FAILED'});
        exit_code=$code;plan_path=(Join-Path $directory 'runtime-plan.json');
        plan_sha256=$(if ($code -eq 0) {(Get-FileHash -LiteralPath (Join-Path $directory 'runtime-plan.json')).Hash} else {''});
        product_started=$false;traffic_generated=$false}) (Join-Path $directory 'prepare-result.json')
    if ($code -ne 0) {throw 'TARGET_PREPARATION_FAILED_NO_RUNTIME'}
    Write-Output $output
    return
}
if (-not $PlanPath -or -not $PlanSha) {throw 'TARGET_PLAN_AND_SHA_REQUIRED'}
& $sourcePython -B $entry validate --root $root --plan $PlanPath --sha $PlanSha
if ($LASTEXITCODE -ne 0) {throw 'TARGET_PLAN_VALIDATION_FAILED_NO_RUNTIME'}
$plan=Read-TargetJson $PlanPath
$bootEvidence=Read-TargetJson (Join-Path $plan.preparation 'boot-session.json')
Assert-KdBootSessionEvidence -Expected $bootEvidence -Actual (Get-KdBootSessionEvidence)
if ($Phase -eq 'Inspect') {Write-Output 'TARGET_PLAN_INSPECTED_NO_RUNTIME';return}
$flowObserver=$plan.policy.PSObject.Properties['observer'] -and $plan.policy.observer -in @('etw+kd-target-flow','etw+kd-target-removal','etw+kd-target-retry','etw+kd-target-flag')
if ([bool]$FlowProfileRegisteredDisabled -ne [bool]$flowObserver) {throw 'TARGET_FLOW_REGISTRATION_ACK_MUST_MATCH_PLAN_NO_RUNTIME'}
$kdObserver=$plan.policy.PSObject.Properties['observer'] -and $plan.policy.observer -in @('etw+kd-target-create','etw+kd-target-retrieve','etw+kd-target-flow','etw+kd-target-removal','etw+kd-target-retry','etw+kd-target-flag')
$stagedHost=$kdObserver -and $plan.policy.workload -in @('create-target-201-staged','retrieve-target-201-staged','flow-target-201-staged','removal-target-201-staged','retry-target-201-staged','flag-target-201-staged')
$createTarget=$kdObserver -and $plan.policy.workload -in @('create-target-201','create-target-201-staged','retrieve-target-201-staged','flow-target-201-staged','removal-target-201-staged','retry-target-201-staged','flag-target-201-staged')
$fourProbe=$kdObserver -and $plan.policy.workload -in @('create-four-probe','retrieve-four-probe','flag-four-probe')
if ($stagedHost) {
    if (-not $DebuggerPointsDisabled -or $DebuggerLoggerEnabled) {throw 'TARGET_STAGED_INITIAL_POINTS_MUST_BE_DISABLED_NO_RUNTIME'}
    if ([Console]::IsInputRedirected -or $Host.Name -ne 'ConsoleHost') {throw 'TARGET_INTERACTIVE_CONSOLE_REQUIRED_NO_RUNTIME'}
} elseif ([bool]$DebuggerLoggerEnabled -ne [bool]$kdObserver -or $DebuggerPointsDisabled) {throw 'TARGET_DEBUGGER_ACTIVATION_ACK_MUST_MATCH_PLAN_NO_RUNTIME'}
if ($createTarget -and -not $BoundedLoadReviewed) {throw 'TARGET_CREATE_BOUNDED_LOAD_ACK_REQUIRED_NO_RUNTIME'}

function Assert-TargetHistory($Boot) {
    # Preserve the existing legacy/interrupted-run stop gates; no Resume.
    $bootTime=[DateTimeOffset]::Parse([string]$Boot.identity.start_time_utc)
    $history=@()
    foreach ($dir in @(Get-ChildItem (Join-Path $root 'artifacts/local-route') -Directory)) {
        if ($dir.Name -match '(?:4\.0\.0|v4\.0\.0)') {
            $p=Join-Path $dir.FullName 'comparison-manifest.json';if (Test-Path $p) {$history+=$p}
        }
    }
    foreach ($dir in @(Get-ChildItem (Join-Path $root 'artifacts/version-comparison') -Directory -Filter 'preflight-*')) {
        foreach ($child in @(Get-ChildItem $dir.FullName -Directory -Filter 'legacy-lifecycle-*')) {
            $p=Join-Path $child.FullName 'lifecycle-receipt.json';if (Test-Path $p) {$history+=$p}
        }
    }
    foreach ($p in $history) {
        $saved=Read-TargetJson $p
        foreach ($key in @('started_at_utc','completed_at_utc')) {
            if ($saved.PSObject.Properties[$key] -and $saved.$key -and $bootTime -le [DateTimeOffset]::Parse([string]$saved.$key)) {throw 'TARGET_REBOOT_REQUIRED_AFTER_LEGACY'}
        }
        if ($bootTime -le [DateTimeOffset](Get-Item $p).LastWriteTimeUtc) {throw 'TARGET_REBOOT_REQUIRED_AFTER_LEGACY_WRITE'}
    }
    foreach ($dir in @(Get-ChildItem (Join-Path $root 'artifacts/benchmark-launch') -Directory -Filter '*-control')) {
        $p=Join-Path $dir.FullName 'job.json'
        if (Test-Path $p) {
            $saved=Read-TargetJson $p
            if ($saved.status -in @('STARTING','RUNNING','STOPPING','INTERRUPTED') -and $bootTime -le [DateTimeOffset]::Parse([string]$saved.updatedAtUtc)) {throw 'TARGET_INTERRUPTED_RUN_REQUIRES_REBOOT'}
        }
    }
    foreach ($dir in @(Get-ChildItem (Join-Path $root 'artifacts/diagnostics') -Directory)) {
        $p=Join-Path $dir.FullName 'diagnostic-run.json'
        if (Test-Path $p) {
            $saved=Read-TargetJson $p
            if ($saved.status -eq 'RUNNING' -and $bootTime -le [DateTimeOffset]::Parse([string]$saved.started_at_utc)) {throw 'TARGET_INTERRUPTED_DIAGNOSTIC_REQUIRES_REBOOT'}
        }
    }
}

$registered=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/ProxyBridgeDrv.sys'
$driverSha='3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e'
$cliPath=Join-Path $plan.build 'kit/ProxyBridge_CLI.exe'
$environment=[Collections.Generic.Dictionary[string,string]]::new()
$environment['PB_PROXYBRIDGE_CLI_EXE']=$cliPath
$environment['PB_DRIVER_PATH']=$registered
$environment['PB_PROXYBRIDGE_SERVICE']='ProxyBridgeDrv'
$environment['PB_EXPECTED_PROXYBRIDGE_CLI_SHA256']='ad83b3aad22252be0ab20a6c26470f7c364930af35089e9904f1dd0d29bb40ca'
$environment['PB_EXPECTED_PROXYBRIDGE_CORE_SHA256']=$plan.core_sha256
$environment['PB_EXPECTED_DRIVER_SHA256']=$driverSha
$environment['PB_WINDIVERT_CTL_EXE']=Join-Path $root 'bin/tools/windivert-2.2.2/windivertctl.exe'
$environment['PB_EXPECTED_WINDIVERT_CTL_SHA256']='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765'
$environment['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
function Assert-TargetOff([string]$Directory,[string]$Stage) {
    $state=Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    Write-TargetJson $state (Join-Path $Directory ('interception-'+$Stage+'.json'))
    Write-TargetJson $loaded (Join-Path $Directory ('loaded-drivers-'+$Stage+'.json'))
    if (-not $state.current_driver_preparation_allowed -or $state.wfp.service_state -ne 'Running' -or
        -not $loaded.query_complete -or -not $loaded.selected_driver_loaded -or @($loaded.known_interception_drivers).Count -ne 1 -or
        -not $state.windivert.configured -or -not $state.windivert.files_verified -or -not $state.windivert.capture_complete -or
        $state.windivert.status -ne 'NO_HANDLES_OBSERVED' -or $state.windivert.observed_handle_count -ne 0) {throw 'TARGET_RESIDENT_OFF_NOT_CONFIRMED'}
    if (@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe')).Count) {throw 'TARGET_PRODUCT_PROCESS_EXISTS'}
}

$mutex=[Threading.Mutex]::new($false,'Global\ProxyBridgeTestLabPlannedBenchmark')
$owns=$false;$lease=$null;$gate=$null;$resident=$null;$capture=$null;$receiver=$null;$proxy=$null
$adapter=New-SystemProcessAdapter
$oldRoute=[Environment]::GetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','Process')
$oldGate=[Environment]::GetEnvironmentVariable('PB_TESTLAB_TARGET_GATE','Process')
$evidence='';$run=$null
function Invoke-TargetCleanupStep([scriptblock]$Action) {
    try {& $Action} catch {$run.cleanup_errors+=@($_.Exception.Message)}
}
try {
    try {$owns=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$owns=$true}
    if (-not $owns) {throw 'TARGET_OTHER_RUN_ACTIVE'}
    $leasePath=Join-Path $root 'artifacts/benchmark-launch/execution.lock';Assert-TargetPlain $leasePath
    $lease=[IO.File]::Open($leasePath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    Assert-TargetHistory (Get-KdBootSessionEvidence)
    $identity=Get-ProductBuildIdentity -Environment $environment -Contract driver
    if (-not $identity.files_verified) {throw 'TARGET_PRODUCT_IDENTITY_FAILED'}
    $available=[long](Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5).FreePhysicalMemory*1024
    if ($available -lt 2147483648L -or (Get-PSDrive C).Free -lt 536870912L) {throw 'TARGET_RESOURCE_BOUND_NO_CLAIM'}
    Initialize-TargetTcpTable
    $occupied=@([PBTargetTcpTable]::Read() | Where-Object {$_.LocalPort -in @(34010,54122,54123) -or ($_.LocalPort -ge 42001 -and $_.LocalPort -le 42201)})
    if ($occupied.Count) {throw 'TARGET_RESERVED_PORT_OCCUPIED_NO_CLAIM'}
    $claim=Join-Path $plan.preparation 'run-claim.json';Assert-TargetPlain $claim
    $stream=[IO.File]::Open($claim,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Dispose()
    $evidence=Join-Path $root ('artifacts/diagnostics/pb-target-accept-run-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $null=New-Item -ItemType Directory -Path $evidence
    $run=[ordered]@{method='target-accept-session-v1';status='RUNNING';started_at_utc=[DateTime]::UtcNow.ToString('o');
        plan_sha256=$PlanSha;error='';cleanup_errors=@();resident_disabled_after=$false;debugger_control=$false;driver_installation=$false;free_memory_before=$available}
    $run['debugger_observer']=[bool]$kdObserver
    if ($flowObserver) {$run['flow_registration_acknowledged']=$true}
    $run['debugger_console_pending']=[bool]$kdObserver
    Write-TargetJson $run (Join-Path $evidence 'diagnostic-run.json')
    Copy-Item -LiteralPath $PlanPath -Destination (Join-Path $evidence 'runtime-plan.json')
    Assert-TargetOff $evidence 'before'
    $resident=Open-KdResidentDriver
    $session=[guid]::NewGuid().ToString('N')
    Write-TargetJson (Disable-KdResidentDriver -Handle $resident -SessionId $session -Phase before) (Join-Path $evidence 'resident-disable-before.json')
    $gate=New-TargetAcceptGate
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','original','Process')
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_TARGET_GATE',$gate.token,'Process')
    $capture=New-RedirectEtwCapture (Join-Path $evidence 'etw');Start-RedirectEtwCapture $capture
    $client=Join-Path $root 'bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe'
    $server=Join-Path $root 'bin/tools/ctstraffic-2.0.3.9/ctsTrafficReceiver.exe'
    $singleProbe=$plan.policy.PSObject.Properties['single_probe'] -and $plan.policy.single_probe
    $serverLimit=if ($singleProbe) {1} elseif ($fourProbe) {4} else {201}
    $serverPlan=[pscustomobject]@{executable=$server;arguments=@('-listen:127.0.0.1',('-serverexitlimit:'+$serverLimit),
        '-protocol:tcp','-pattern:push','-transfer:524288','-ratelimit:65536','-verify:data','-port:54122',
        '-buffer:65536','-consoleverbosity:1','-statusupdate:250',('-connectionfilename:'+(Join-Path $evidence 'receiver.csv')));
        console_host_path=(Join-Path $root 'bin/pb_console_host.exe');console_identity_ack=$true;stop_timeout_ms=5000}
    $receiver=& $adapter.StartProcess $serverPlan
    $probe=& $adapter.ProbeActualPath $receiver 2000 25
    if ($probe.status -ne 'PATH_OBTAINED' -or $receiver.actual_path -ine $server) {throw 'TARGET_RECEIVER_IDENTITY_FAILED'}
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while (-not @([PBTargetTcpTable]::Read() | Where-Object {$_.Pid -eq $receiver.pid -and $_.State -eq 2 -and $_.LocalPort -eq 54122}).Count) {
        if (-not $receiver.session.IsRunning -or $timer.ElapsedMilliseconds -ge 5000) {throw 'TARGET_RECEIVER_NOT_LISTENING'}
        Start-Sleep -Milliseconds 10
    }
    $proxyLog=Join-Path $evidence 'proxy.jsonl'
    $proxyInfo=[Diagnostics.ProcessStartInfo]::new();$proxyInfo.FileName=$plan.python
    $proxyInfo.Arguments=Join-ProcessArguments @('-B','-u',(Join-Path $root 'src/pb_controlled_tcp_proxy.py'),
        '--wheel',(Join-Path $root 'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl'),
        '--jsonl-log',$proxyLog,'--port','54123','--receiver-port','54122','--event-loop','proactor',
        '--shutdown-diagnostics','--bounded-shutdown','--max-duration-seconds','120','--guard-proactor-close-reset')
    $proxyInfo.UseShellExecute=$false;$proxyInfo.CreateNoWindow=$true
    $proxyInfo.RedirectStandardInput=$true;$proxyInfo.RedirectStandardOutput=$true;$proxyInfo.RedirectStandardError=$true
    $proxy=[Diagnostics.Process]::Start($proxyInfo)
    $proxyOut=$proxy.StandardOutput.ReadToEndAsync();$proxyErr=$proxy.StandardError.ReadToEndAsync()
    $timer.Restart()
    do {
        if ($proxy.HasExited) {throw 'TARGET_PROXY_EARLY_EXIT'}
        $ready=0
        if (Test-Path $proxyLog) {$ready=@(Get-Content $proxyLog | Where-Object {$_} | ConvertFrom-Json | Where-Object event -eq 'LISTENING').Count}
        if ($ready -eq 1) {break}
        if ($ready -gt 1 -or $timer.ElapsedMilliseconds -ge 5000) {throw 'TARGET_PROXY_NOT_READY'}
        Start-Sleep -Milliseconds 25
    } while ($true)
    $profile=Join-Path $evidence 'route.pbprofile'
    Write-TargetJson ([ordered]@{Version='1.0';LocalhostViaProxy=$true;IsTrafficLoggingEnabled=$true;
        ProxyConfigs=@([ordered]@{Id=1;Name='Target accept';Type='SOCKS5';Host='127.0.0.1';Port='54123';Username='';Password='';SendDomainToProxy=$false});
        ProxyRules=@([ordered]@{Name='Target accept';ProcessName='ctsTraffic.exe';TargetHosts='127.0.0.1';TargetPorts='54122';TargetDomains='';Protocol='TCP';Action='PROXY';ProxyConfigId=1;IsEnabled=$true})}) $profile
    $context=[pscustomobject]@{root=$root;directory=$evidence;adapter=$adapter;client=$client;
        single_probe=[bool]$singleProbe;probe_only=[bool]$fourProbe;manual_host_window=[bool]$stagedHost;flow_observer=[bool]$flowObserver;debugger_point_ids=@($plan.policy.debugger_points)}
    if ($plan.policy.PSObject.Properties['host_enable_debugger_points']) {
        $context | Add-Member -NotePropertyName host_enable_debugger_points -NotePropertyValue @($plan.policy.host_enable_debugger_points)
    }
    $cohortCommand=Get-Command Invoke-TargetNativeCohort
    $writeCommand=Get-Command Write-TargetJson
    $workload={param($cli)
        try {
        $modules=@((Get-Process -Id $cli.pid).Modules | Where-Object ModuleName -ieq 'ProxyBridgeCore.dll')
        if ($modules.Count -ne 1 -or $modules[0].FileName -ine (Join-Path $plan.build 'kit/ProxyBridgeCore.dll') -or
            (Get-FileHash -LiteralPath $modules[0].FileName).Hash -ine $plan.core_sha256) {throw 'TARGET_LOADED_CORE_BINDING_FAILED'}
        & $writeCommand ([ordered]@{pid=$cli.pid;path=$modules[0].FileName;sha256=$plan.core_sha256}) (Join-Path $evidence 'loaded-core.json')
        $free=[long](Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5).FreePhysicalMemory*1024
        & $writeCommand ([ordered]@{free_bytes=$free;minimum_bytes=2147483648L}) (Join-Path $evidence 'memory-before-fillers.json')
        if ($free -lt 2147483648L) {throw 'TARGET_MEMORY_BEFORE_FILLERS_BOUND'}
        & $cohortCommand -Context $context -Gate $gate
        } finally {$null=$gate.release.Set()}
    }.GetNewClosure()
    $sink={param($v);& $writeCommand $v (Join-Path $evidence 'cli-lifecycle.json')}.GetNewClosure()
    $cliPlan=New-ProxyBridgeCliPlan -ExecutablePath $cliPath -ProfilePath $profile -ProductProfileContract driver -CliVariant 'testlab-unbuffered-v1' -ReadyStableMs 1000 -ReadinessTimeoutMs 10000 -StopTimeoutMs 5000
    $lifecycle=Invoke-ProxyBridgeCliLifecycle -Plan $cliPlan -ProcessAdapter $adapter -AllowProductRuntime -Workload $workload -EvidenceSink $sink
    # The return object has process_result; error belongs only to EvidenceSink.
    # Invoke-ProxyBridgeCliLifecycle itself throws on primary/cleanup errors.
    if (-not $lifecycle.ready -or -not $lifecycle.graceful_stop -or $lifecycle.forced_stop -or -not $lifecycle.post_stop_verified -or $lifecycle.process_result.exit_code -ne 0) {throw 'TARGET_CLI_LIFECYCLE_INCOMPLETE'}
    $run.status='COLLECTED'
} catch {
    if ($run) {$run.status='FAILED';$run.error=$_.Exception.Message} else {throw}
} finally {
    if ($run) {
        if ($gate) {try {Close-TargetAcceptGate $gate} catch {$run.cleanup_errors+=@($_.Exception.Message)}}
        Invoke-TargetCleanupStep {if ($receiver) {
            try {
                if (-not $receiver.session.WaitForExit(1000)) {$stopped=& $adapter.StopProcess $receiver 5000;if (-not $stopped) {throw 'TARGET_RECEIVER_CONTROLLED_STOP_FAILED'}}
            } catch {$run.cleanup_errors+=@($_.Exception.Message)}
            finally {
                if ($receiver.session.IsRunning) {& $adapter.KillProcess $receiver;$run.cleanup_errors+=@('TARGET_RECEIVER_FORCED_STOP')}
                try {Write-TargetJson (& $adapter.GetProcessResult $receiver) (Join-Path $evidence 'receiver-process.json')}
                finally {& $adapter.DisposeProcess $receiver}
            }
        }}
        Invoke-TargetCleanupStep {if ($proxy) {
            try {
                if (-not $proxy.HasExited) {$proxy.StandardInput.WriteLine('STOP');$proxy.StandardInput.Flush()}
                if (-not $proxy.WaitForExit(15000)) {$proxy.Kill();$proxy.WaitForExit();throw 'TARGET_PROXY_FORCED_STOP'}
                if ($proxy.ExitCode -ne 0) {throw 'TARGET_PROXY_EXIT_FAILED'}
            } catch {$run.cleanup_errors+=@($_.Exception.Message)}
            finally {
                try {Write-TargetJson ([ordered]@{pid=$proxy.Id;exit_code=$proxy.ExitCode;stdout=$proxyOut.Result;stderr=$proxyErr.Result}) (Join-Path $evidence 'proxy-process.json')}
                finally {$proxy.Dispose()}
            }
        }}
        Invoke-TargetCleanupStep {if ($resident) {
            try {
                Write-TargetJson (Disable-KdResidentDriver -Handle $resident -SessionId $session -Phase after) (Join-Path $evidence 'resident-disable-after.json')
                Assert-TargetOff $evidence 'after';$run.resident_disabled_after=$true
            } catch {$run.cleanup_errors+=@($_.Exception.Message)}
            finally {$resident.Dispose()}
        }}
        Invoke-TargetCleanupStep {if ($capture) {
            try {Stop-RedirectEtwCapture $capture;Export-RedirectEtwCapture $capture}
            catch {$run.cleanup_errors+=@($_.Exception.Message)}
        }}
        $run['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
        if ($run.cleanup_errors.Count) {$run.status='FAILED'}
        Invoke-TargetCleanupStep {Write-TargetJson $run (Join-Path $evidence 'diagnostic-run.json')}
        Write-Host ('Results: '+$evidence)
        if ($plan.policy.PSObject.Properties['endpoint_retry_chain'] -and $plan.policy.endpoint_retry_chain) {Write-Host 'Host recovery: Break pauses the entire VM including Codex/RDP. bd2, bd3, bd4, dx @$scriptContents.pbcStop(), then separate g. Preserve PBC CONFIG/CREATE/SKIP/ACCEPT/FINAL. No repeat Run.'}
        elseif ($plan.policy.PSObject.Properties['endpoint_accept_pair'] -and $plan.policy.endpoint_accept_pair) {Write-Host 'Host recovery: Break pauses the entire VM including Codex/RDP. bd2, bd3, dx @$scriptContents.pbaStop(), then separate g. Preserve PBA CONFIG/PRE/POST/FINAL. No repeat Run.'}
        elseif ($plan.policy.PSObject.Properties['endpoint_retry_epochs'] -and $plan.policy.endpoint_retry_epochs) {Write-Host 'Host recovery: Break pauses the entire VM including Codex/RDP. bd2, then dx @$scriptContents.pbRetryStop(), then .if (@$t8 != 0) { bc3; r @$t8 = 0; }, then .if (@$t9 != 0) { bc4; r @$t9 = 0; }, then separate g. Preserve console from this Run. No repeat Run.'}
        elseif ($plan.policy.PSObject.Properties['endpoint_nbl_context'] -and $plan.policy.endpoint_nbl_context) {Write-Host 'Host recovery: Break pauses the entire VM including Codex/RDP. bd2, then dx @$scriptContents.pbNblStop(), then .if (@$t8 != 0) { bc3; r @$t8 = 0; }, then bd4, then separate g. Preserve console from this Run. No repeat Run.'}
        elseif ($plan.policy.PSObject.Properties['endpoint_data_watch'] -and $plan.policy.endpoint_data_watch) {Write-Host 'Host recovery: Break pauses the entire VM including Codex/RDP. bd2, then .if (@$t8 != 0) { bc3; r @$t8 = 0; }, then bd4, then separate g. Preserve console from this Run. No repeat Run.'}
        elseif ($flowObserver) {Write-Host ('Host recovery: Break pauses the entire VM including Codex/RDP. '+(($plan.policy.debugger_points | ForEach-Object {'bd'+$_}) -join ', ')+', then separate g. Preserve console from this Run. No repeat Run.')}
        elseif ($kdObserver) {Write-Host 'Host recovery: Break pauses the entire VM including Codex/RDP. bd2 then separate g. Preserve console from this Run. No repeat Run.'}
    }
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE',$oldRoute,'Process')
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_TARGET_GATE',$oldGate,'Process')
    if ($lease) {$lease.Dispose()}
    if ($owns) {$mutex.ReleaseMutex()};$mutex.Dispose()
}
& $sourcePython -B (Join-Path $root 'src/pb_target_accept_report.py') --evidence-directory $evidence
if ($LASTEXITCODE -ne 0 -or $run.status -ne 'COLLECTED') {throw 'TARGET_CAPTURE_INCOMPLETE_NO_REPEAT'}
if ($kdObserver) {Write-Host 'TARGET_NATIVE_CAPTURE_DEBUGGER_CONSOLE_PENDING: no kernel coverage verdict yet'}
