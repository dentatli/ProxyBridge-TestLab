#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)]$SessionPlan,[Parameter(Mandatory)][string]$SessionPlanPath,
      [Parameter(Mandatory)][string]$EvidenceDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$policy=$SessionPlan.control_policy
$residentDriver=$policy.PSObject.Properties['driver_lifecycle'] -and $policy.driver_lifecycle -eq 'resident-disabled'
if ($residentDriver) {
    if ($policy.workload -ne 'four') {throw 'KD_SESSION_RESIDENT_FOUR_ONLY'}
    Import-Module (Join-Path $root 'modules/KdResidentDriver.psm1')
}
if ($SessionPlan.method -cne 'redirect-kd-session-v1' -or
    $policy.cohort_module -notin @('KdQueryProbeConnectionLoad','KdQueryBoundedConnectionLoad')) {throw 'KD_SESSION_ENGINE_CONTRACT_INVALID'}
foreach ($name in @('Env','ProductBuild','RuntimeEnvironment','InterceptionState','ProxyBridgeCli','ProcessAdapter','ProxyBridgeEvidence',$policy.cohort_module)) {
    Import-Module (Join-Path $root ('modules/'+$name+'.psm1'))
}
$PythonPath=$SessionPlan.python
$EnvPath=Join-Path $SessionPlan.preparation 'kit/product.env'
$diagnosticReceiptPath=Join-Path $SessionPlan.preparation 'kit/redirect-context-diagnostic.json'
$kdReceipt=Get-Content -LiteralPath $diagnosticReceiptPath -Raw | ConvertFrom-Json
$diagnosticReceipt=$kdReceipt
$environment=Import-DotEnv $EnvPath
$observationEnvironment=Import-DotEnv $EnvPath
$observationEnvironment['PB_WINDIVERT_CTL_EXE']=Join-Path $root 'bin/tools/windivert-2.2.2/windivertctl.exe'
$observationEnvironment['PB_EXPECTED_WINDIVERT_CTL_SHA256']='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765'
$observationEnvironment['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
$identity=Get-ProductBuildIdentity -Environment $environment -Contract driver
if (-not $identity.files_verified) {throw 'KD_SESSION_PRODUCT_FILES_NOT_VERIFIED'}
$diagnosticRegisteredDriverPath=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/ProxyBridgeDrv.sys'
if ((Get-FileHash -LiteralPath $diagnosticRegisteredDriverPath).Hash -ine $environment['PB_EXPECTED_DRIVER_SHA256']) {throw 'KD_SESSION_REGISTERED_DRIVER_DIFFERS'}
$observationEnvironment['PB_DRIVER_PATH']=$diagnosticRegisteredDriverPath
$DiagnosticRedirectContext=$true;$DiagnosticFixtureCloseGuard=$true
$DiagnosticRouteCase='';$DiagnosticReceiverCase='';$DiagnosticPhaseObserver=$null;$CancellationPath=''
$receiverPolicy=$null;$receiverTarget='127.0.0.1';$kernelDiagnostic=$false
$diagnosticCase=[ordered]@{id='connectex-32';connect_method='ConnectEx';pending_limit=32}
$preset=Get-ConnectionLoadPreset -Duration SHORT -Load HIGH
$preset.method='redirect-kd-session-v1'
if (($preset.levels -join ',') -cne ($policy.load_levels -join ',') -or $preset.native_timeout_ms -ne $policy.client_wait_limit_ms) {throw 'KD_SESSION_PRESET_DIFFERS'}
$client=Join-Path $root 'bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe'
$receiver=Join-Path $root 'bin/tools/ctstraffic-2.0.3.9/ctsTrafficReceiver.exe'
$wheel=Join-Path $root 'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl'
$packages=Join-Path $root 'bin/tools/psutil-7.2.2/packages'
foreach ($exe in @($client,$receiver)) { if ((Get-FileHash $exe).Hash -ne '0548089E59C872306CE2C98E7163E2A717119756010CF64D3CB3DA2854F632CF') { throw 'CONNECTION_NATIVE_ENGINE_CHANGED' } }
if ((Get-FileHash $wheel).Hash -ne '5190D3AE00A29325EC9048306FCD8BD08F8E89DDD75C535CC01D1D646F105344') { throw 'CONNECTION_PROXY_LIBRARY_CHANGED' }
if (-not $EvidenceDirectory) { $EvidenceDirectory=Join-Path $root ('artifacts/local-route/tcp-connections-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)) }
if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'CONNECTION_EVIDENCE_REQUIRES_FRESH_DIRECTORY' }
$null=New-Item -ItemType Directory -Path $EvidenceDirectory
$manifest=[ordered]@{schema_version=1;status='RUNNING';scenario='tcp_connections';method='tcp-connection-load-v1';profile='SMOKE';product_contract='driver';workload_preset=$preset;started_at_utc=[DateTime]::UtcNow.ToString('o');runs=@();error='';table_occupancy_observed=$false;maximum_capacity_verified=$false;version_switch_ready=$false}
if ($DiagnosticRedirectContext) {
    $manifest.method='tcp-redirect-context-diagnostic-v1';$manifest.scenario='tcp_redirect_context_diagnostic'
    $manifest['diagnostic_only']=$true;$manifest['performance_comparable']=$false
    $manifest['diagnostic_build_receipt_sha256']=(Get-FileHash -LiteralPath $diagnosticReceiptPath).Hash.ToLowerInvariant()
    if ($diagnosticReceipt.method -eq 'redirect-context-followup-v2') {$manifest.method='tcp-redirect-context-diagnostic-v2'}
    if ($diagnosticCase) {$manifest.method='tcp-redirect-context-matrix-case-v1';$manifest['diagnostic_connection_case']=$diagnosticCase}
    if ($DiagnosticFixtureCloseGuard) {$manifest.method='tcp-redirect-context-matrix-case-v2';$manifest['fixture_close_guard']='pinned-proactor-shutdown-reset-close-v1'}
    if ($diagnosticReceipt.method -eq 'redirect-context-probes-v3') {$manifest.method='tcp-redirect-context-probes-v3';$manifest['probe_policy']=$diagnosticReceipt.probe_policy}
    if ($diagnosticReceipt.method -eq 'redirect-kernel-context-v4') {$manifest.method='tcp-redirect-kernel-context-v4';$manifest['kernel_observation_policy']=$diagnosticReceipt.observation_policy}
    $manifest.method='tcp-redirect-kd-session-v1';$manifest['control_policy']=$kdReceipt.control_policy
    if ($DiagnosticRouteCase) {$manifest['route_case']=$DiagnosticRouteCase;$manifest['route_matrix_policy']=$diagnosticReceipt.route_matrix_policy}
}
if ($receiverPolicy) {$manifest['external_receiver_policy']=$receiverPolicy;$manifest['receiver_case']=$DiagnosticReceiverCase}
function Save-Manifest { Write-ConnectionJson $manifest (Join-Path $EvidenceDirectory 'comparison-manifest.json') }
function Assert-ConnectionOff([string]$Directory,[ValidateSet('before','after')][string]$Phase) {
    $state=Get-InterceptionStateSnapshot -Environment $observationEnvironment -AllowProductRuntime
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    $processes=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe'))
    # Persist observations before refusing, so a blocked preflight remains diagnosable.
    Write-ConnectionJson $state (Join-Path $Directory ('interception-'+$Phase+'.json'))
    Write-ConnectionJson $loaded (Join-Path $Directory ('loaded-drivers-'+$Phase+'.json'))
    Write-ConnectionJson @($processes | Select-Object ProcessId,Name,ExecutablePath) (Join-Path $Directory ('product-processes-'+$Phase+'.json'))
    $driverReady=if ($residentDriver) {
        $state.wfp.service_state -eq 'Running' -and $loaded.selected_driver_loaded -and @($loaded.known_interception_drivers).Count -eq 1
    } else {
        $state.wfp_detachment_observed -and $state.wfp.service_state -eq 'Stopped' -and $loaded.known_interception_driver_names_absent
    }
    if (-not $state.current_driver_preparation_allowed -or -not $driverReady -or
        -not $state.windivert.configured -or -not $state.windivert.files_verified -or -not $state.windivert.capture_complete -or $state.windivert.status -ne 'NO_HANDLES_OBSERVED' -or $state.windivert.observed_handle_count -ne 0 -or
        -not $loaded.query_complete -or $processes.Count) { throw 'CONNECTION_REQUIRES_CONFIRMED_PRODUCT_OFF_OR_RESIDENT_DISABLED' }
    return [pscustomobject]@{state=$state;loaded=$loaded}
}
function Start-ConnectionWorker($Name,$Arguments,$Workers) {
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$PythonPath;$info.Arguments=Join-ProcessArguments (@('-B')+$Arguments);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($info)
    $worker=[pscustomobject]@{name=$Name;process=$process;stdout=$process.StandardOutput.ReadToEndAsync();stderr=$process.StandardError.ReadToEndAsync()};$Workers.Add($worker)
    return $worker
}
function Wait-ConnectionWorker($Worker,$Path) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $observation=[ordered]@{schema_version=1;worker=$Worker.name;pid=$Worker.process.Id;timeout_ms=5000;
        status='WAITING';elapsed_ms=0;listening_events=0;process_exited=$false;error='';debugger_pause_observed=$false}
    try {
        while ($true) {
            $observation.process_exited=$Worker.process.HasExited
            if ($observation.process_exited) { throw ('CONNECTION_HELPER_EARLY_EXIT_'+$Worker.name) }
            $observation.listening_events=0
            if (Test-Path -LiteralPath $Path) {
                $observation.listening_events=@(Get-Content -LiteralPath $Path | Where-Object {$_} | ConvertFrom-Json | Where-Object event -eq 'LISTENING').Count
            }
            if ($observation.listening_events -gt 1) {throw ('CONNECTION_HELPER_DUPLICATE_READY_'+$Worker.name)}
            # After a guest debugger pause, inspect readiness before testing elapsed time.
            # This final observation does not extend the timeout or prove a debugger pause.
            if ($observation.listening_events -eq 1) {$observation.status='READY';return}
            if ($timer.ElapsedMilliseconds -ge $observation.timeout_ms) {throw ('CONNECTION_HELPER_NOT_READY_'+$Worker.name)}
            Start-Sleep -Milliseconds 50
        }
    } catch {
        $observation.status='FAILED';$observation.error=$_.Exception.Message
        throw
    } finally {
        $observation.elapsed_ms=$timer.ElapsedMilliseconds
        Write-ConnectionJson $observation ($Path+'.readiness.json')
    }
}
function Invoke-ConnectionMode($Mode,$Directory) {
    $null=New-Item -ItemType Directory -Path $Directory
    $workers=[Collections.Generic.List[object]]::new();$startedProduct=$false
    $residentHandle=$null;$residentSession=[guid]::NewGuid().ToString('N')
    $receipt=[ordered]@{schema_version=1;mode=$Mode;status='RUNNING';phases=@();workers_stopped=$false;driver_stop_observed=$false;version_switch_ready=$false;error=''}
    $adapter=New-SystemProcessAdapter
    try {
        $before=Assert-ConnectionOff -Directory $Directory -Phase before
        if ($residentDriver) {
            # Never enable interception here. Keep a device handle through this run.
            $residentHandle=Open-KdResidentDriver
            Write-ConnectionJson (Disable-KdResidentDriver -Handle $residentHandle -SessionId $residentSession -Phase before) (Join-Path $Directory 'resident-disable-before.json')
        }
        Write-ConnectionJson $identity (Join-Path $Directory 'product-build.json')
        foreach ($port in @(54122,54123)) { if (@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue).Count) { throw 'CONNECTION_PORT_IN_USE' } }
        $proxyLog=Join-Path $Directory 'proxy.jsonl'
        $proxyArguments=@('-u',(Join-Path $root 'src/pb_controlled_tcp_proxy.py'),'--wheel',$wheel,'--jsonl-log',$proxyLog,'--port','54123','--receiver-port','54122','--event-loop','proactor','--shutdown-diagnostics','--bounded-shutdown','--max-duration-seconds','720')
        if ($receiverPolicy) {$proxyArguments+=@('--receiver-host',$receiverTarget)}
        if ($DiagnosticFixtureCloseGuard) {$proxyArguments+='--guard-proactor-close-reset'}
        $proxy=Start-ConnectionWorker 'proxy' $proxyArguments $workers
        Wait-ConnectionWorker $proxy $proxyLog
        $samplerConfig=Join-Path $Directory 'sampler-config.json'
        Write-ConnectionJson @([ordered]@{role='proxy';pid=$proxy.process.Id;path=$PythonPath}) $samplerConfig
        $samplerLog=Join-Path $Directory 'pc-samples.jsonl'
        $sampler=Start-ConnectionWorker 'sampler' @('-u',(Join-Path $root 'src/pb_pc_sampler.py'),'--packages',$packages,'--config',$samplerConfig,'--jsonl-log',$samplerLog,'--max-duration-seconds','720') $workers
        Wait-ConnectionWorker $sampler $samplerLog
        $context=[pscustomobject]@{root=$root;directory=$Directory;mode=$Mode;preset=$preset;receiver=$receiver;client=$client;adapter=$adapter;sampler=$sampler;receipt=$receipt;cancellation_path=$CancellationPath}
        $context | Add-Member -NotePropertyName full_metadata_identity_ack -NotePropertyValue $true
        $config=[ordered]@{method='tcp-connection-load-v1';workload_preset=$preset;proxy_pid=$proxy.process.Id;sampler_pid=$sampler.process.Id;engine_sha256=(Get-FileHash $client).Hash;proxy_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;sampler_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash;connection_module_sha256=(Get-FileHash (Join-Path $root ('modules/'+$policy.cohort_module+'.psm1'))).Hash;python_sha256=(Get-FileHash $PythonPath).Hash;proxy_event_loop='ProactorEventLoop';proxy_shutdown_diagnostics='task-metadata-after-stop-v1';proxy_shutdown_policy='bounded-task-drain-reset-finalization-after-stop-v2';shutdown_mode='rude';verify='data';table_occupancy_observed=$false}
        if ($diagnosticCase) {
            $context | Add-Member -NotePropertyName diagnostic_case -NotePropertyValue $diagnosticCase
            $context | Add-Member -NotePropertyName diagnostic_only -NotePropertyValue $true
            $config.method='tcp-redirect-context-matrix-case-v1';$config['diagnostic_connection_case']=$diagnosticCase
            if ($DiagnosticFixtureCloseGuard) {
                $config.method='tcp-redirect-context-matrix-case-v2';$config['fixture_close_guard']='pinned-proactor-shutdown-reset-close-v1'
                $config['fixture_close_guard_sha256']=(Get-FileHash (Join-Path $root 'src/pb_proactor_close_guard.py')).Hash.ToLowerInvariant()
                $config['proactor_runtime_sha256']=(Get-FileHash (Join-Path (Split-Path -Parent $PythonPath) 'Lib/asyncio/proactor_events.py')).Hash.ToLowerInvariant()
            }
        }
        $config.method='tcp-redirect-kd-session-v1';$config['control_policy']=$kdReceipt.control_policy
        Write-ConnectionJson $config (Join-Path $Directory 'benchmark-config.json')
        if ($receiverPolicy) {
            $config['external_receiver_policy']=$receiverPolicy;$config['receiver_case']=$DiagnosticReceiverCase
            Write-ConnectionJson $config (Join-Path $Directory 'benchmark-config.json')
            if ($DiagnosticReceiverCase -eq 'linux') {$context | Add-Member -NotePropertyName external_receiver -NotePropertyValue $receiverPolicy}
        }
        $cohortCommand=Get-Command Invoke-ConnectionCohorts -CommandType Function
        $loadedCommand=Get-Command Get-LoadedInterceptionDriverObservation -CommandType Function
        $interceptionCommand=Get-Command Get-InterceptionStateSnapshot -CommandType Function
        $capturedObservationEnvironment=$observationEnvironment
        $writeCommand=Get-Command Write-ConnectionJson -CommandType Function
        $workerCommand=Get-Command Start-ConnectionWorker -CommandType Function
        $workerReadyCommand=Get-Command Wait-ConnectionWorker -CommandType Function
        $capturedCollector=Join-Path $root 'src/pb_kernel_context_collector.py'
        $capturedPhaseObserver=$DiagnosticPhaseObserver
        $workload={
            param($cli)
            if ($cli) {
                $active=& $loadedCommand -AllowProductRuntime
                & $writeCommand $active (Join-Path $context.directory 'loaded-drivers-active.json')
                if (-not $active.query_complete -or -not $active.selected_driver_loaded -or @($active.known_interception_drivers).Count -ne 1) { throw 'CONNECTION_SELECTED_DRIVER_NOT_CONFIRMED' }
                $activeState=& $interceptionCommand -Environment $capturedObservationEnvironment -AllowProductRuntime
                & $writeCommand $activeState (Join-Path $context.directory 'interception-active.json')
                if ($activeState.wfp.status -ne 'SERVICE_FILE_VERIFIED' -or $activeState.wfp.service_state -ne 'Running' -or -not $activeState.windivert.files_verified -or -not $activeState.windivert.capture_complete -or $activeState.windivert.status -ne 'NO_HANDLES_OBSERVED' -or $activeState.windivert.observed_handle_count -ne 0) { throw 'CONNECTION_ACTIVE_INTERCEPTION_NOT_CONFIRMED' }
            }
            & $cohortCommand -Context $context -Cli $cli -DiagnosticPhaseObserver $null
        }.GetNewClosure()
        if ($Mode -eq 'PROXY') {
            $runtimeConfig=Get-Content (Join-Path $root 'config/runtime.json') -Raw | ConvertFrom-Json
            $runtimePlan=New-RuntimeEnvironmentPlan -Environment $environment -RuntimeConfig $runtimeConfig -ProductOnly
            if ($runtimePlan.service_bootstrap -ne 'driver-service') { throw 'CONNECTION_REQUIRES_HEADLESS_KIT' }
            if ($DiagnosticRedirectContext) {
                $runtimeDrivers=@($runtimePlan.binaries | Where-Object id -eq 'driver')
                if ($runtimeDrivers.Count -ne 1 -or $runtimeDrivers[0].expected_sha256 -ine $environment['PB_EXPECTED_DRIVER_SHA256']) {throw 'CONNECTION_REDIRECT_DIAGNOSTIC_RUNTIME_BINDING_INVALID'}
                $runtimeDrivers[0].configured_path=$diagnosticRegisteredDriverPath
                $binding=[ordered]@{diagnostic_only=$true;registered_driver_path=$diagnosticRegisteredDriverPath;kit_driver_path=$environment['PB_DRIVER_PATH'];expected_driver_sha256=$runtimeDrivers[0].expected_sha256;service_registration_changed=$false}
                Write-ConnectionJson $binding (Join-Path $Directory 'diagnostic-driver-binding.json')
            }
            $startedProduct=$true
            $preparation=Invoke-RuntimeEnvironmentPreparation -Plan $runtimePlan -Adapter (New-SystemRuntimeEnvironmentAdapter) -AllowProductRuntime
            Write-ConnectionJson $preparation (Join-Path $Directory 'preparation-result.json')
            if (-not $preparation.prepared) { throw 'CONNECTION_PRODUCT_PREPARATION_FAILED' }
            $profilePath=Join-Path $Directory 'route.pbprofile'
            Write-ConnectionJson ([ordered]@{Version='1.0';LocalhostViaProxy=$true;IsTrafficLoggingEnabled=$true;ProxyConfigs=@([ordered]@{Id=1;Name='Connection load SOCKS5';Type='SOCKS5';Host='127.0.0.1';Port='54123';Username='';Password='';SendDomainToProxy=$false});ProxyRules=@([ordered]@{Name='Connection load';ProcessName='ctsTraffic.exe';TargetHosts=$receiverTarget;TargetPorts='54122';TargetDomains='';Protocol='TCP';Action='PROXY';ProxyConfigId=1;IsEnabled=$true})}) $profilePath
            $plan=New-ProxyBridgeCliPlan -ExecutablePath $environment['PB_PROXYBRIDGE_CLI_EXE'] -ProfilePath $profilePath -ProductProfileContract driver -CliVariant $environment['PB_PROXYBRIDGE_CLI_VARIANT'] -ReadyStableMs 1000 -ReadinessTimeoutMs 10000 -StopTimeoutMs 5000
            $sink={param($value) & $writeCommand $value (Join-Path $context.directory 'cli-lifecycle.json')}.GetNewClosure()
            $lifecycle=Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter $adapter -AllowProductRuntime -Workload $workload -EvidenceSink $sink
            if (-not $lifecycle.ready -or -not $lifecycle.graceful_stop -or $lifecycle.forced_stop -or -not $lifecycle.post_stop_verified -or $lifecycle.process_result.exit_code -ne 0) { throw 'CONNECTION_CLI_LIFECYCLE_FAILED' }
            $records=@(ConvertFrom-ProxyBridgeTextLines -Lines @($lifecycle.process_result.stdout -split '\r?\n') -DefaultTimestampUtc ([DateTime]::Parse($lifecycle.started_at_utc)))
            Write-ConnectionJson $records (Join-Path $Directory 'route-observations.json')
        } else { & $workload $null }
        if ($receipt.status -ne 'CANCELLED') { $receipt.status='COMPLETED' }
    } catch { $receipt.status='FAILED';$receipt.error=$_.Exception.Message }
    finally {
        $clean=$true
        foreach ($worker in $workers) {
            $forced=$false
            try {
                if (-not $worker.process.HasExited) { $worker.process.StandardInput.WriteLine('STOP');$worker.process.StandardInput.Flush() }
                if (-not $worker.process.WaitForExit(15000)) { $worker.process.Kill();$worker.process.WaitForExit();$forced=$true }
                $out=$worker.stdout.GetAwaiter().GetResult();$err=$worker.stderr.GetAwaiter().GetResult()
                Write-ConnectionJson ([ordered]@{pid=$worker.process.Id;exit_code=$worker.process.ExitCode;forced_stop=$forced;stdout=$out;stderr=$err;output_capture_complete=$true}) (Join-Path $Directory ($worker.name+'-process.json'))
                if ($forced -or $worker.process.ExitCode -ne 0) {
                    $clean=$false
                    $receipt.error+=('; CONNECTION_HELPER_EXIT_NOT_CLEAN_'+$worker.name+'_exit'+$worker.process.ExitCode+'_forced'+$forced)
                }
            } catch { $clean=$false;$receipt.error+='; '+$_.Exception.Message }
            finally { if (-not $worker.process.HasExited) {$worker.process.Kill();$worker.process.WaitForExit()};$worker.process.Dispose() }
        }
        $receipt.workers_stopped=$clean
        try {
            if ($residentDriver) {
                if ($null -eq $residentHandle) {throw 'KD_RESIDENT_HANDLE_NOT_OPENED'}
                Write-ConnectionJson (Disable-KdResidentDriver -Handle $residentHandle -SessionId $residentSession -Phase after) (Join-Path $Directory 'resident-disable-after.json')
            } elseif ($startedProduct) { $service=Get-Service -Name $environment['PB_PROXYBRIDGE_SERVICE'];if ($service.Status -ne 'Stopped') { Stop-Service -Name $service.Name -Force;$service.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(10)) } }
            $after=Assert-ConnectionOff -Directory $Directory -Phase after
            if ($residentDriver) {$receipt['resident_disable_observed']=$true;$receipt['driver_lifecycle']='resident-disabled'}
            else {$receipt.driver_stop_observed=$true}
        } catch { $receipt.error+='; '+$_.Exception.Message }
        finally {if ($null -ne $residentHandle) {$residentHandle.Dispose()}}
        $driverClean=if ($residentDriver) {$receipt.Contains('resident_disable_observed') -and $receipt.resident_disable_observed} else {$receipt.driver_stop_observed}
        if (-not $receipt.workers_stopped -or -not $driverClean) { $receipt.status='FAILED' }
        Write-ConnectionJson $receipt (Join-Path $Directory 'run-receipt.json')
    }
    if ($receipt.status -eq 'FAILED') { throw ('CONNECTION_RUN_FAILED: '+$receipt.error) }
    return $receipt
}
Save-Manifest
Write-Host ('KD session: '+($policy.phase_connections -join ' -> ')+', active IDs '+($policy.active_point_ids -join ',')+'. Один исходный query, 512 KiB. Вся VM может замедлиться или остановиться.')
Write-Host ('Results / Результаты: '+$EvidenceDirectory)
try {
    $selectedModes=$(if ($DiagnosticRedirectContext) {@('PROXY')} else {@('OFF','PROXY')})
    foreach ($mode in $selectedModes) {
        if ($CancellationPath -and (Test-Path -LiteralPath $CancellationPath)) { $manifest.status='CANCELLED';break }
        $name=$mode.ToLowerInvariant();$entry=[ordered]@{mode=$mode;directory=$name;status='RUNNING'};$manifest.runs+=@($entry);Save-Manifest
        $result=Invoke-ConnectionMode $mode (Join-Path $EvidenceDirectory $name)
        $entry.status=$result.status;Save-Manifest
        if ($result.status -eq 'CANCELLED') {$manifest.status='CANCELLED';break}
    }
    if ($manifest.status -ne 'CANCELLED') {
        $manifest.status='COMPLETED';Save-Manifest
        if (-not $DiagnosticRedirectContext) {
            & $PythonPath -B (Join-Path $root 'src/pb_tcp_connections_report.py') --evidence-directory $EvidenceDirectory
            if ($LASTEXITCODE -ne 0) { throw 'CONNECTION_EVIDENCE_NOT_CONFIRMED' }
        }
    }
} catch {
    $manifest.status='FAILED';$manifest.error=$_.Exception.Message
    if ($manifest.runs.Count -and $manifest.runs[-1].status -eq 'RUNNING') { $manifest.runs[-1].status='FAILED' }
}
$manifest['completed_at_utc']=[DateTime]::UtcNow.ToString('o');Save-Manifest
if ($DiagnosticRedirectContext) {
    $reportEntry=$(if ($diagnosticReceipt.method -eq 'redirect-context-followup-v2') {'pb_tcp_redirect_context_extended_report.py'} else {'pb_tcp_redirect_context_report.py'})
    $reportArgs=@('--evidence-directory',$EvidenceDirectory)
    if ($diagnosticCase) {$reportEntry='pb_tcp_redirect_context_matrix_report.py';$reportArgs+=@('--case')}
    if ($diagnosticReceipt.method -eq 'redirect-context-probes-v3') {$reportEntry='pb_tcp_redirect_context_probes_report.py';$reportArgs=@('--evidence-directory',$EvidenceDirectory)}
    if ($diagnosticReceipt.method -eq 'redirect-kernel-context-v4') {$reportEntry='pb_tcp_kernel_context_report.py';$reportArgs=@('--evidence-directory',$EvidenceDirectory)}
    if ($receiverPolicy) {$reportEntry='pb_tcp_external_receiver_report.py';$reportArgs=@('--evidence-directory',$EvidenceDirectory,'--case')}
    $reportEntry='pb_kd_session_report.py';$reportArgs=@('--evidence-directory',$EvidenceDirectory,'--plan',$SessionPlanPath)
    & $PythonPath -B (Join-Path $root ('src/'+$reportEntry)) @reportArgs
    if ($LASTEXITCODE -ne 0 -and $manifest.status -ne 'FAILED') {throw 'CONNECTION_REDIRECT_DIAGNOSTIC_CAPTURE_INCOMPLETE'}
}
if ($manifest.status -eq 'FAILED') {throw $manifest.error}
