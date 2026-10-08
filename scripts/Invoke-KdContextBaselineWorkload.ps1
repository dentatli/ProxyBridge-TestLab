#Requires -RunAsAdministrator
[CmdletBinding()]
param([ValidateSet('SMOKE')][string]$Profile='SMOKE',[string]$EvidenceDirectory='',
    [string]$EnvPath='',[string]$PythonPath='',[string]$CancellationPath='',
    [ValidateSet('SHORT','NORMAL','LONG')][string]$Duration='SHORT',
    [ValidateSet('LOW','HIGH')][string]$Load='LOW',[switch]$DiagnosticRedirectContext,
    [ValidateSet('','connectex-32','connectex-1','connect-32','connect-1')][string]$DiagnosticConnectionCase='',
    [switch]$DiagnosticFixtureCloseGuard,
    [ValidateSet('','original','backlog1024','backlog1024-delay650')][string]$DiagnosticRouteCase='',
    [ValidateSet('','local','linux')][string]$DiagnosticReceiverCase='',
    [scriptblock]$DiagnosticPhaseObserver)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach ($name in @('Env','ProductBuild','RuntimeEnvironment','InterceptionState','ProxyBridgeCli','ProcessAdapter','ProxyBridgeEvidence','ConnectionLoad')) { Import-Module (Join-Path $root ('modules/'+$name+'.psm1')) }
if (-not $EnvPath) { $EnvPath=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env' }
if (-not $PythonPath) { $PythonPath=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' }
$environment=Import-DotEnv $EnvPath
$observationEnvironment=Import-DotEnv $EnvPath
# Use the same pinned, list-only observer as the existing three-mode controller.
# The product environment does not configure this diagnostic tool by default.
$observationEnvironment['PB_WINDIVERT_CTL_EXE']=Join-Path $root 'bin/tools/windivert-2.2.2/windivertctl.exe'
$observationEnvironment['PB_EXPECTED_WINDIVERT_CTL_SHA256']='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765'
$observationEnvironment['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
$identity=Get-ProductBuildIdentity -Environment $environment -Contract driver
if (-not $identity.files_verified) { throw 'CONNECTION_PRODUCT_FILES_NOT_VERIFIED' }
$diagnosticReceiptPath=Join-Path (Split-Path -Parent $environment['PB_PROXYBRIDGE_CLI_EXE']) 'redirect-context-diagnostic.json'
# This separate copy accepts only the fresh four-connection KD contract.
if (-not $DiagnosticRedirectContext -or $Duration -ne 'SHORT' -or $Load -ne 'HIGH' -or
    $DiagnosticConnectionCase -cne 'connectex-32' -or -not $DiagnosticFixtureCloseGuard -or
    $DiagnosticRouteCase -or $DiagnosticReceiverCase -or $DiagnosticPhaseObserver -or $CancellationPath) {
    throw 'KD_BASELINE_CONTROLLER_CONTRACT_INVALID'
}
if ([Environment]::GetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','Process') -cne 'original') {throw 'KD_BASELINE_ORIGINAL_LISTENER_REQUIRED'}
$kdReceipt=Get-Content -LiteralPath $diagnosticReceiptPath -Raw | ConvertFrom-Json
if ($kdReceipt.method -cne 'redirect-kd-baseline-v5' -or $kdReceipt.kd_baseline_policy.method -cne 'kd-owned-four-v1' -or
    $kdReceipt.kd_baseline_policy.connections -ne 4 -or $kdReceipt.kd_baseline_policy.hold_seconds -ne 8 -or
    $kdReceipt.kd_baseline_policy.load_levels.Count -ne 0 -or $kdReceipt.kd_baseline_policy.driver_installation -or
    $environment['PB_EXPECTED_PROXYBRIDGE_CLI_SHA256'] -cne 'ad83b3aad22252be0ab20a6c26470f7c364930af35089e9904f1dd0d29bb40ca' -or
    $environment['PB_EXPECTED_PROXYBRIDGE_CORE_SHA256'] -cne '7dc8952e7562ac4dff3cf278136d1fe8fd44474885f707c93c220f94e9f624ed' -or
    $environment['PB_EXPECTED_DRIVER_SHA256'] -cne '3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e') {
    throw 'KD_BASELINE_PINNED_FILES_OR_POLICY_INVALID'
}
$hasDiagnosticMarker=$environment.ContainsKey('PB_TESTLAB_REDIRECT_CONTEXT_DIAGNOSTIC') -or (Test-Path -LiteralPath $diagnosticReceiptPath)
if ($DiagnosticPhaseObserver -and -not $DiagnosticRedirectContext) {throw 'CONNECTION_PHASE_OBSERVER_REQUIRES_DIAGNOSTIC'}
if ($hasDiagnosticMarker -and -not $DiagnosticRedirectContext) { throw 'CONNECTION_DIAGNOSTIC_KIT_NOT_A_BENCHMARK' }
if ($DiagnosticRedirectContext) {
    if (-not $hasDiagnosticMarker -or $Duration -ne 'SHORT' -or $Load -ne 'HIGH' -or $CancellationPath) {throw 'CONNECTION_REDIRECT_DIAGNOSTIC_CONTRACT_INVALID'}
    $diagnosticReceipt=Get-Content -LiteralPath $diagnosticReceiptPath -Raw | ConvertFrom-Json
    if ($DiagnosticPhaseObserver) {
        if (-not $diagnosticReceipt.PSObject.Properties['full_metadata_policy']) {throw 'CONNECTION_FULL_METADATA_POLICY_MISSING'}
        Import-Module (Join-Path $root 'modules/FullMetadataDiagnostic.psm1')
        Assert-FullMetadataPolicy $diagnosticReceipt.full_metadata_policy
    }
    if ($diagnosticReceipt.method -notin @('redirect-context-logging-v1','redirect-context-followup-v2','redirect-context-probes-v3','redirect-kernel-context-v4','redirect-kd-baseline-v5') -or
        $environment['PB_TESTLAB_REDIRECT_CONTEXT_DIAGNOSTIC'] -ne $diagnosticReceipt.method -or -not $diagnosticReceipt.diagnostic_only -or $diagnosticReceipt.performance_comparable -or
        $diagnosticReceipt.status -ne 'DIAGNOSTIC_BUILD_PREPARED' -or $diagnosticReceipt.source_commit -ne '63be0ebf9bec92bfba95ef3d6729c375aa9af84e') {throw 'CONNECTION_REDIRECT_DIAGNOSTIC_RECEIPT_INVALID'}
    if ($diagnosticReceipt.method -in @('redirect-context-followup-v2','redirect-context-probes-v3') -and (-not $diagnosticReceipt.followup_only_after_api_failure -or -not $diagnosticReceipt.original_verdict_preserved -or
        $diagnosticReceipt.followup_buffer_capacity -ne 1024 -or $diagnosticReceipt.followup_queries_per_failure -ne 3 -or $diagnosticReceipt.followup_payload_recorded)) {throw 'CONNECTION_REDIRECT_DIAGNOSTIC_FOLLOWUP_CONTRACT_INVALID'}
    if ($diagnosticReceipt.method -eq 'redirect-context-probes-v3' -and ($diagnosticReceipt.probe_policy.positive_first_sequences -ne 4 -or $diagnosticReceipt.probe_policy.positive_sequence_stride -ne 128 -or
    $diagnosticReceipt.probe_policy.positive_limit -ne 16 -or (@($diagnosticReceipt.probe_policy.delayed_targets_ms) -join ',') -ne '5,25,100' -or $diagnosticReceipt.probe_policy.delayed_failure_limit -ne 1000 -or
    $diagnosticReceipt.probe_policy.probe_buffer_capacity -ne 1024 -or $diagnosticReceipt.probe_policy.socket_metadata -ne 'type-and-endpoints-no-so-error-v1' -or
    -not $diagnosticReceipt.probe_policy.original_verdict_preserved -or $diagnosticReceipt.probe_policy.probe_payload_recorded)) {throw 'REDIRECT_DIAGNOSTIC_PROBE_POLICY_INVALID'}
    foreach ($component in $diagnosticReceipt.components) {
        $file=Join-Path (Split-Path -Parent $environment['PB_PROXYBRIDGE_CLI_EXE']) $component.name
        if ((Get-FileHash -LiteralPath $file).Hash -ine $component.sha256) {throw 'CONNECTION_REDIRECT_DIAGNOSTIC_FILES_CHANGED'}
    }
    # Core is isolated; the byte-identical kernel driver remains registered at its baseline path.
    $diagnosticBaseKit=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli'
    if ([IO.Path]::GetFullPath([string]$diagnosticReceipt.base_kit) -ine [IO.Path]::GetFullPath($diagnosticBaseKit)) {throw 'CONNECTION_REDIRECT_DIAGNOSTIC_BASE_PATH_INVALID'}
    $diagnosticRegisteredDriverPath=Join-Path $diagnosticBaseKit 'ProxyBridgeDrv.sys'
    if ((Get-FileHash -LiteralPath $diagnosticRegisteredDriverPath).Hash -ine '3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e') {throw 'CONNECTION_REDIRECT_DIAGNOSTIC_BASE_DRIVER_CHANGED'}
    if ($diagnosticReceipt.method -eq 'redirect-kernel-context-v4') {
        # Only this separate candidate can use a different sys; ordinary/Core-only paths retain baseline binding.
        $installationPath=Join-Path (Split-Path -Parent (Split-Path -Parent $diagnosticReceiptPath)) 'kernel-installation.json'
        $installationFile=Get-Item -LiteralPath $installationPath -Force
        if ($installationFile.Length -gt 1MB -or ($installationFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'CONNECTION_KERNEL_INSTALLATION_FILE_INVALID'}
        $installation=Get-Content -LiteralPath $installationPath -Raw | ConvertFrom-Json
        $signature=Get-AuthenticodeSignature -LiteralPath $environment['PB_DRIVER_PATH']
        $boot=([DateTime](Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5).LastBootUpTime).ToUniversalTime()
        if ($installation.status -ne 'INSTALLED_REBOOT_REQUIRED' -or $installation.baseline_path -ine $diagnosticRegisteredDriverPath -or
            $installation.candidate_path -ine $environment['PB_DRIVER_PATH'] -or $installation.candidate_sha256 -ine $environment['PB_EXPECTED_DRIVER_SHA256'] -or
            $installation.build_receipt_sha256 -ine (Get-FileHash -LiteralPath $diagnosticReceiptPath).Hash -or
            $signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ine '4544323109A45FC4761819E079BBDBD5E0BFE8D6' -or
            $boot -le ([DateTime]$installation.installed_at_utc).ToUniversalTime()) {throw 'CONNECTION_KERNEL_CANDIDATE_INSTALL_OR_REBOOT_UNCONFIRMED'}
        if (-not $diagnosticReceipt.observation_policy.original_actions_preserved -or -not $diagnosticReceipt.observation_policy.original_query_only -or
            -not $diagnosticReceipt.observation_policy.no_delayed_queries -or $diagnosticReceipt.observation_policy.payload_recorded -or
            $diagnosticReceipt.observation_policy.raw_kernel_pointers_recorded -or $diagnosticReceipt.observation_policy.ring_capacity -ne 8192) {throw 'CONNECTION_KERNEL_POLICY_INVALID'}
        $diagnosticRegisteredDriverPath=$environment['PB_DRIVER_PATH']
    } elseif ((Get-FileHash -LiteralPath $environment['PB_DRIVER_PATH']).Hash -ine (Get-FileHash -LiteralPath $diagnosticRegisteredDriverPath).Hash) {
        throw 'CONNECTION_REDIRECT_DIAGNOSTIC_REGISTERED_DRIVER_DIFFERS'
    }
    $observationEnvironment['PB_DRIVER_PATH']=$diagnosticRegisteredDriverPath
}
$receiverPolicy=$null;$receiverTarget='127.0.0.1'
if ($DiagnosticReceiverCase -or ($DiagnosticRedirectContext -and $diagnosticReceipt.PSObject.Properties['external_receiver_policy'])) {
    if (-not $DiagnosticRedirectContext -or -not $DiagnosticReceiverCase -or $DiagnosticRouteCase -cne 'original' -or
        $DiagnosticConnectionCase -cne 'connectex-32' -or -not $DiagnosticFixtureCloseGuard -or
        [Environment]::GetEnvironmentVariable('PB_TESTLAB_RECEIVER_CASE','Process') -cne $DiagnosticReceiverCase) {throw 'CONNECTION_EXTERNAL_CASE_BINDING_INVALID'}
    Import-Module (Join-Path $root 'modules/ExternalReceiverDiagnostic.psm1')
    $receiverPolicy=$diagnosticReceipt.external_receiver_policy
    Assert-ExternalReceiverPolicy $receiverPolicy
    if ($DiagnosticReceiverCase -eq 'linux') {$receiverTarget=[string]$receiverPolicy.host}
}
$diagnosticCase=$null
if ($DiagnosticRouteCase -or ($DiagnosticRedirectContext -and $diagnosticReceipt.PSObject.Properties['route_matrix_policy'])) {
    if (-not $DiagnosticRedirectContext -or $diagnosticReceipt.method -ne 'redirect-kernel-context-v4' -or -not $DiagnosticRouteCase -or
        $DiagnosticConnectionCase -ne 'connectex-32' -or -not $DiagnosticFixtureCloseGuard -or
        [Environment]::GetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','Process') -cne $DiagnosticRouteCase) {throw 'CONNECTION_ROUTE_CASE_BINDING_INVALID'}
    Import-Module (Join-Path $root 'modules/RouteMatrixDiagnostic.psm1')
    Assert-RouteMatrixPolicy $diagnosticReceipt.route_matrix_policy
}
if ($DiagnosticConnectionCase) {
    if (-not $DiagnosticRedirectContext -or $diagnosticReceipt.method -notin @('redirect-context-followup-v2','redirect-context-probes-v3','redirect-kernel-context-v4','redirect-kd-baseline-v5')) {throw 'CONNECTION_MATRIX_REQUIRES_FOLLOWUP_DIAGNOSTIC'}
    $parts=$DiagnosticConnectionCase.Split('-')
    $diagnosticCase=[ordered]@{id=$DiagnosticConnectionCase;connect_method=$(if ($parts[0] -eq 'connectex') {'ConnectEx'} else {'connect'});pending_limit=[int]$parts[1]}
}
if ($DiagnosticRedirectContext -and $diagnosticReceipt.method -in @('redirect-context-probes-v3','redirect-kernel-context-v4') -and ($DiagnosticConnectionCase -ne 'connectex-32' -or -not $DiagnosticFixtureCloseGuard)) {throw 'CONNECTION_PROBES_REQUIRES_PINNED_CASE_AND_CLOSE_GUARD'}
$preset=Get-ConnectionLoadPreset -Duration $Duration -Load $Load
$preset.levels=@();$preset.minimum_available_bytes=536870912L
$preset.method='kd-owned-four-v1'
if ($DiagnosticFixtureCloseGuard -and -not $diagnosticCase) {throw 'CONNECTION_CLOSE_GUARD_REQUIRES_DIAGNOSTIC_MATRIX'}
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
    $manifest.method='tcp-kd-baseline-v1';$manifest['kd_baseline_policy']=$kdReceipt.kd_baseline_policy
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
    if (-not $state.current_driver_preparation_allowed -or -not $state.wfp_detachment_observed -or $state.wfp.service_state -ne 'Stopped' -or
        -not $state.windivert.configured -or -not $state.windivert.files_verified -or -not $state.windivert.capture_complete -or $state.windivert.status -ne 'NO_HANDLES_OBSERVED' -or $state.windivert.observed_handle_count -ne 0 -or
        -not $loaded.query_complete -or -not $loaded.known_interception_driver_names_absent -or $processes.Count) { throw 'CONNECTION_REQUIRES_CONFIRMED_PRODUCT_OFF' }
    return [pscustomobject]@{state=$state;loaded=$loaded}
}
function Start-ConnectionWorker($Name,$Arguments,$Workers) {
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$PythonPath;$info.Arguments=Join-ProcessArguments $Arguments;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($info)
    $worker=[pscustomobject]@{name=$Name;process=$process;stdout=$process.StandardOutput.ReadToEndAsync();stderr=$process.StandardError.ReadToEndAsync()};$Workers.Add($worker)
    return $worker
}
function Wait-ConnectionWorker($Worker,$Path) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt 5000) {
        if ($Worker.process.HasExited) { throw ('CONNECTION_HELPER_EARLY_EXIT_'+$Worker.name) }
        if ((Test-Path $Path) -and @(Get-Content $Path | Where-Object {$_} | ConvertFrom-Json | Where-Object event -eq 'LISTENING').Count -eq 1) { return }
        Start-Sleep -Milliseconds 50
    }
    throw ('CONNECTION_HELPER_NOT_READY_'+$Worker.name)
}
function Invoke-ConnectionMode($Mode,$Directory) {
    $null=New-Item -ItemType Directory -Path $Directory
    $workers=[Collections.Generic.List[object]]::new();$startedProduct=$false
    $receipt=[ordered]@{schema_version=1;mode=$Mode;status='RUNNING';phases=@();workers_stopped=$false;driver_stop_observed=$false;version_switch_ready=$false;error=''}
    $adapter=New-SystemProcessAdapter
    try {
        $before=Assert-ConnectionOff -Directory $Directory -Phase before
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
        $config=[ordered]@{method='tcp-connection-load-v1';workload_preset=$preset;proxy_pid=$proxy.process.Id;sampler_pid=$sampler.process.Id;engine_sha256=(Get-FileHash $client).Hash;proxy_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;sampler_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash;connection_module_sha256=(Get-FileHash (Join-Path $root 'modules/ConnectionLoad.psm1')).Hash;python_sha256=(Get-FileHash $PythonPath).Hash;proxy_event_loop='ProactorEventLoop';proxy_shutdown_diagnostics='task-metadata-after-stop-v1';proxy_shutdown_policy='bounded-task-drain-reset-finalization-after-stop-v2';shutdown_mode='rude';verify='data';table_occupancy_observed=$false}
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
        if ($DiagnosticRedirectContext -and $diagnosticReceipt.method -eq 'redirect-context-probes-v3') {$config.method='tcp-redirect-context-probes-v3';$config['probe_policy']=$diagnosticReceipt.probe_policy}
        $kernelDiagnostic=$DiagnosticRedirectContext -and $diagnosticReceipt.method -eq 'redirect-kernel-context-v4'
        if ($kernelDiagnostic) {
            $config.method='tcp-redirect-kernel-context-v4';$config['kernel_collector_sha256']=(Get-FileHash -LiteralPath (Join-Path $root 'src/pb_kernel_context_collector.py')).Hash.ToLowerInvariant()
            $config['kernel_installation_sha256']=(Get-FileHash -LiteralPath $installationPath).Hash.ToLowerInvariant()
            $config['kernel_boot_time_utc']=$boot.ToString('o')
            Copy-Item -LiteralPath $installationPath -Destination (Join-Path $Directory 'kernel-installation.json')
        }
        if ($kernelDiagnostic -and $diagnosticReceipt.PSObject.Properties['timing_policy']) {$config['kernel_timing_policy']=$diagnosticReceipt.timing_policy}
        $config.method='tcp-kd-baseline-v1';$config['kd_baseline_policy']=$kdReceipt.kd_baseline_policy
        Write-ConnectionJson $config (Join-Path $Directory 'benchmark-config.json')
        if ($receiverPolicy) {
            $config['external_receiver_policy']=$receiverPolicy;$config['receiver_case']=$DiagnosticReceiverCase
            Write-ConnectionJson $config (Join-Path $Directory 'benchmark-config.json')
            if ($DiagnosticReceiverCase -eq 'linux') {$context | Add-Member -NotePropertyName external_receiver -NotePropertyValue $receiverPolicy}
        }
        # Bind to the existing module's private cohort implementation, with exactly one phase.
        # Ordinary Invoke-ConnectionCohorts and all saved full-series plans are untouched.
        $cohortModule=Get-Module ConnectionLoad
        $cohortCommand=$cohortModule.NewBoundScriptBlock({
            param($Context,$Cli,$DiagnosticPhaseObserver)
            if (-not $Cli -or $DiagnosticPhaseObserver -or $Context.mode -cne 'PROXY' -or -not $Context.diagnostic_only) {throw 'KD_BASELINE_CONTEXT_INVALID'}
            $Context.sampler.process.StandardInput.WriteLine(([ordered]@{role='proxybridge_cli';pid=$Cli.pid;path=$Cli.actual_path} | ConvertTo-Json -Compress))
            $Context.sampler.process.StandardInput.Flush()
            $phase=[pscustomobject]@{id='baseline';phase='baseline';connections=4;seconds=8}
            Write-Host 'KD baseline / 4 соединения, без уровней нагрузки и recovery'
            $record=Invoke-ConnectionCohort -Context $Context -Phase $phase -Cli $Cli
            $Context.receipt.phases+=@($record)
            Write-ConnectionJson $Context.receipt (Join-Path $Context.directory 'run-receipt.json')
            if ($record.error) {throw ('KD_BASELINE_COHORT_INCOMPLETE: '+$record.error)}
            if ($record.client_forced_stop -or $record.server_forced_stop) {throw 'KD_BASELINE_CLEANUP_INCOMPLETE'}
        })
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
            $collector=$null
            try {
                if ($kernelDiagnostic) {
                    if (-not $cli) {throw 'CONNECTION_KERNEL_COLLECTOR_REQUIRES_OWN_CLI'}
                    $collector=& $workerCommand 'kernel-collector' @('-u',$capturedCollector,'--jsonl-log',(Join-Path $context.directory 'kernel-context.jsonl')) $workers
                    & $workerReadyCommand $collector (Join-Path $context.directory 'kernel-context.jsonl')
                }
                & $cohortCommand -Context $context -Cli $cli -DiagnosticPhaseObserver $capturedPhaseObserver
            } finally {
                # Drain while the same CLI still owns the running driver; unloading first loses the ring tail.
                if ($collector) {
                    if (-not $collector.process.HasExited) {$collector.process.StandardInput.WriteLine('STOP');$collector.process.StandardInput.Flush()}
                    if (-not $collector.process.WaitForExit(10000)) {throw 'CONNECTION_KERNEL_COLLECTOR_STOP_TIMEOUT'}
                    if ($collector.process.ExitCode -ne 0) {throw 'CONNECTION_KERNEL_COLLECTOR_FAILED'}
                }
            }
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
                if ($kernelDiagnostic) {$binding['registered_via_diagnostic_installation']=$true;$binding['installation_receipt_sha256']=$config.kernel_installation_sha256}
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
            if ($startedProduct) { $service=Get-Service -Name $environment['PB_PROXYBRIDGE_SERVICE'];if ($service.Status -ne 'Stopped') { Stop-Service -Name $service.Name -Force;$service.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(10)) } }
            $after=Assert-ConnectionOff -Directory $Directory -Phase after
            $receipt.driver_stop_observed=$true
        } catch { $receipt.error+='; '+$_.Exception.Message }
        if (-not $receipt.workers_stopped -or -not $receipt.driver_stop_observed) { $receipt.status='FAILED' }
        Write-ConnectionJson $receipt (Join-Path $Directory 'run-receipt.json')
    }
    if ($receipt.status -eq 'FAILED') { throw ('CONNECTION_RUN_FAILED: '+$receipt.error) }
    return $receipt
}
Save-Manifest
Write-Host 'KD baseline: только 4 соединения, 512 KiB на соединение, один исходный query. Это не тест скорости или ёмкости.'
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
            & $PythonPath (Join-Path $root 'src/pb_tcp_connections_report.py') --evidence-directory $EvidenceDirectory
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
    $reportEntry='pb_kd_baseline_report.py';$reportArgs=@('--evidence-directory',$EvidenceDirectory)
    & $PythonPath (Join-Path $root ('src/'+$reportEntry)) @reportArgs
    if ($LASTEXITCODE -ne 0 -and $manifest.status -ne 'FAILED') {throw 'CONNECTION_REDIRECT_DIAGNOSTIC_CAPTURE_INCOMPLETE'}
}
if ($manifest.status -eq 'FAILED') {throw $manifest.error}
