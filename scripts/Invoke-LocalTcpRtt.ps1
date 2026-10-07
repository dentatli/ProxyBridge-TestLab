#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateSet('SMOKE','STANDARD')][string]$Profile='SMOKE',
    [string]$EvidenceDirectory='',
    [string]$EnvPath='',
    [string]$PythonPath='',
    [ValidateSet('driver','v4.0.0')][string]$ProductContract='driver',
    [string]$LegacyIdleDirectory='',
    [string]$LegacySmokeDirectory='',
    [string]$LegacyRttDirectory='',
    [string]$CancellationPath='',
    [switch]$ThreeModes,
    [ValidateSet('SHORT','NORMAL','LONG')][string]$Duration='',
    [ValidateSet('LOW','HIGH')][string]$Load=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$presetMode=[bool]($Duration -or $Load)
$workload=$null
if ($presetMode) {
    if (-not $Duration -or -not $Load -or $ProductContract -ne 'driver' -or $Profile -ne 'SMOKE' -or $LegacyIdleDirectory -or $LegacySmokeDirectory -or $LegacyRttDirectory) { throw 'TCP_RTT_WORKLOAD_REQUIRES_FRESH_DRIVER' }
    Import-Module (Join-Path $root 'modules/BenchmarkWorkload.psm1')
    $workload=Get-BenchmarkWorkload -Duration $Duration -Load $Load
}
foreach ($name in @('Env','ProductBuild','RuntimeEnvironment','InterceptionState','ProxyBridgeCli','ProcessAdapter','ProxyBridgeEvidence')) { Import-Module (Join-Path $root ('modules/'+$name+'.psm1')) }
if ($ProductContract -eq 'v4.0.0' -and -not $LegacyIdleDirectory) { throw 'TCP_LEGACY_REQUIRES_IDLE_EVIDENCE' }
if ($ProductContract -eq 'driver' -and ($LegacyIdleDirectory -or $LegacySmokeDirectory)) { throw 'TCP_DRIVER_MUST_NOT_USE_LEGACY_EVIDENCE' }
if ($ProductContract -eq 'v4.0.0' -and $Profile -eq 'STANDARD' -and -not $LegacySmokeDirectory) { throw 'TCP_LEGACY_STANDARD_REQUIRES_CONFIRMED_SMOKE' }
$pairedDriver=$ProductContract -eq 'driver' -and -not [string]::IsNullOrWhiteSpace($LegacyRttDirectory)
if ($ThreeModes -and ($ProductContract -ne 'driver' -or $Profile -ne 'SMOKE' -or $LegacyRttDirectory -or $LegacyIdleDirectory -or $LegacySmokeDirectory)) { throw 'TCP_THREE_MODES_REQUIRES_DRIVER_SMOKE_WITHOUT_VERSION_REFERENCE' }
if ($LegacyRttDirectory -and (-not $pairedDriver -or $Profile -ne 'STANDARD')) { throw 'TCP_VERSION_DRIVER_REQUIRES_STANDARD_AND_LEGACY_RTT_REFERENCE' }
if (-not $EnvPath) { $EnvPath=Join-Path $root ('artifacts/product-builds/'+$(if ($ProductContract -eq 'driver') {'driver-63be0eb'} else {'v4.0.0-release'})+'-testlab-cli/product.env') }
if (-not $PythonPath) { $PythonPath=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' }
$client=Join-Path $root 'bin/tcp-rtt/pb_tcp_rtt_client.exe'
$receiver=Join-Path $root 'src/pb_net_endpoint.py'
$buildReceipt=Join-Path $root 'bin/tcp-rtt/build-receipt.json'
$wheel=Join-Path $root 'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl'
$packages=Join-Path $root 'bin/tools/psutil-7.2.2/packages'
$samplerWheel=Join-Path $root 'bin/tools/psutil-7.2.2/psutil-7.2.2-cp37-abi3-win_amd64.whl'
foreach ($path in @($EnvPath,$PythonPath,$client,$receiver,$buildReceipt,$wheel,(Join-Path $packages 'psutil/__init__.py'))) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "TCP_DEPENDENCY_MISSING_$path" } }
$engineSha='35D31540D8F6B564839B135BF0C925A224D768519B33C0FAFA9290A3437E8D6A'
foreach ($path in @($client)) { if ((Get-FileHash $path).Hash -ne $engineSha) { throw 'TCP_ENGINE_HASH_MISMATCH' } }
$clientBuild=Get-Content -LiteralPath $buildReceipt -Raw | ConvertFrom-Json
if ($clientBuild.engine_sha256 -ne $engineSha -or $clientBuild.source_sha256 -ne (Get-FileHash (Join-Path $root 'src/pb_net_client.c')).Hash) { throw 'TCP_RTT_SOURCE_BUILD_CHANGED_REBUILD_REQUIRED' }
if ((Get-FileHash $wheel).Hash -ne '5190D3AE00A29325EC9048306FCD8BD08F8E89DDD75C535CC01D1D646F105344' -or (Get-FileHash $samplerWheel).Hash -ne 'EB7E81434C8D223EC4A219B5FC1C47D0417B12BE7EA866E24FB5AD6E84B3D988') { throw 'TCP_LIBRARY_WHEEL_HASH_MISMATCH' }
$environment=Import-DotEnv -Path $EnvPath
$identity=Get-ProductBuildIdentity -Environment $environment -Contract $ProductContract
if (-not $identity.files_verified) { throw 'TCP_PRODUCT_FILES_NOT_VERIFIED' }
$observationEnvironment=$environment
$legacyProfile=''; $legacyProfileHash=''; $legacyIdle=$null
function Get-RttBootIdentity {
    $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop
    return [pscustomobject]@{computer_name=$env:COMPUTERNAME;machine_guid=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid;os_build=[string]$os.BuildNumber;boot_time_utc=([DateTime]$os.LastBootUpTime).ToUniversalTime().ToString('o')}
}
function Assert-PairedDriverBoot {
    $observed=Get-RttBootIdentity
    if ($observed.machine_guid -ne $driverReference.boot_identity.machine_guid -or $observed.os_build -ne $driverReference.boot_identity.os_build) { throw 'TCP_VERSION_DRIVER_MACHINE_CHANGED' }
    if ([DateTimeOffset]::Parse($observed.boot_time_utc) -le [DateTimeOffset]::Parse($driverReference.boot_identity.boot_time_utc)) { throw 'TCP_VERSION_DRIVER_REBOOT_REQUIRED' }
    return $observed
}
function Set-WinDivertObserver($values) {
    $values['PB_WINDIVERT_CTL_EXE']=Join-Path $root 'bin/tools/windivert-2.2.2/windivertctl.exe'
    $values['PB_EXPECTED_WINDIVERT_CTL_SHA256']='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765'
    $values['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
}
function Assert-LegacyBoot {
    $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop
    $machineGuid=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
    if ($machineGuid -ne $legacyIdle.boot_identity.machine_guid -or [string]$os.BuildNumber -ne $legacyIdle.boot_identity.os_build -or
        ([DateTime]$os.LastBootUpTime).ToUniversalTime().ToString('o') -ne $legacyIdle.boot_identity.boot_time_utc) { throw 'TCP_LEGACY_BOOT_OR_MACHINE_CHANGED' }
    return [pscustomobject]@{computer_name=$env:COMPUTERNAME;machine_guid=$machineGuid;os_build=[string]$os.BuildNumber;boot_time_utc=([DateTime]$os.LastBootUpTime).ToUniversalTime().ToString('o')}
}
if ($ProductContract -eq 'v4.0.0') {
    $LegacyIdleDirectory=(Resolve-Path -LiteralPath $LegacyIdleDirectory).Path
    $legacyIdle=Get-Content -LiteralPath (Join-Path $LegacyIdleDirectory 'idle-receipt.json') -Raw | ConvertFrom-Json
    if ($legacyIdle.status -ne 'LEGACY_IDLE_SCOPED_OBSERVED' -or $legacyIdle.contract -ne 'v4.0.0' -or
        -not $legacyIdle.same_version_idle_observed -or -not $legacyIdle.no_compatible_windivert_handles_observed -or
        -not $legacyIdle.known_wfp_detachment_observed -or $legacyIdle.error) { throw 'TCP_LEGACY_IDLE_NOT_CONFIRMED' }
    $null=Assert-LegacyBoot
    $preflightDirectory=Split-Path -Parent $LegacyIdleDirectory
    $preflight=Get-Content -LiteralPath (Join-Path $preflightDirectory 'preflight.json') -Raw | ConvertFrom-Json
    $selected=@($preflight.products | Where-Object contract -eq 'v4.0.0')
    if ($preflight.status -ne 'FILES_AND_PROFILES_PREPARED' -or $preflight.switch_policy -ne 'reboot_between_versions' -or
        $selected.Count -ne 1 -or $selected[0].identity.bundle_sha256 -ne $identity.bundle_sha256 -or
        $identity.declared_cli_variant -ne 'testlab-unbuffered-v1' -or
        $identity.declared_source_commit -ne $selected[0].identity.declared_source_commit -or
        (Get-FileHash (Join-Path (Split-Path -Parent $EnvPath) 'build-receipt.json')).Hash -ine $selected[0].build_receipt_sha256) { throw 'TCP_LEGACY_KIT_OR_PREFLIGHT_CHANGED' }
    $legacyProfile=Join-Path $preflightDirectory 'v4.0.0-tcp.pbprofile'
    $profileEntry=@($preflight.profile_files | Where-Object file_name -eq 'v4.0.0-tcp.pbprofile')
    if ($profileEntry.Count -ne 1 -or (Get-FileHash $legacyProfile).Hash -ine $profileEntry[0].sha256) { throw 'TCP_LEGACY_PROFILE_CHANGED' }
    $legacyProfileHash=$profileEntry[0].sha256
    $observationEnvironment=Import-DotEnv -Path (Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env')
    Set-WinDivertObserver $observationEnvironment
    if ($environment['PB_EXPECTED_WINDIVERT_DLL_SHA256'] -ine $observationEnvironment['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']) { throw 'TCP_LEGACY_OBSERVER_FAMILY_CHANGED' }
    $legacyLoaded=Get-Content -LiteralPath (Join-Path $LegacyIdleDirectory 'loaded-drivers-idle.json') -Raw | ConvertFrom-Json
    if (-not $legacyLoaded.query_complete -or $legacyLoaded.selected_driver_loaded) { throw 'TCP_LEGACY_IDLE_DRIVER_QUERY_INCOMPLETE' }
    if ($Profile -eq 'STANDARD') {
        $LegacySmokeDirectory=(Resolve-Path -LiteralPath $LegacySmokeDirectory).Path
        $smoke=Get-Content -LiteralPath (Join-Path $LegacySmokeDirectory 'comparison-manifest.json') -Raw | ConvertFrom-Json
        $comparison=Get-Content -LiteralPath (Join-Path $LegacySmokeDirectory 'comparison-report.json') -Raw | ConvertFrom-Json
        if ($smoke.status -ne 'COMPLETED' -or $smoke.profile -ne 'SMOKE' -or $smoke.product_contract -ne 'v4.0.0' -or
            $smoke.pair_count -ne 1 -or @($smoke.runs).Count -ne 2 -or $comparison.status -ne 'LIMITED_COMPARISON' -or @($comparison.errors).Count -or
            @($smoke.runs)[0].mode -ne 'OFF' -or @($smoke.runs)[1].mode -ne 'PROXY') { throw 'TCP_LEGACY_SMOKE_NOT_CONFIRMED' }
        foreach ($entry in $smoke.runs) {
            if ($entry.directory -notmatch '^pair-01-(off|proxy)$' -or $entry.status -ne 'COMPLETED') { throw 'TCP_LEGACY_SMOKE_ENTRY_INVALID' }
            $runDirectory=Join-Path $LegacySmokeDirectory $entry.directory
            $report=Get-Content -LiteralPath (Join-Path $runDirectory 'tcp-rtt-report.json') -Raw | ConvertFrom-Json
            $context=Get-Content -LiteralPath (Join-Path $runDirectory 'version-context.json') -Raw | ConvertFrom-Json
            if ($report.status -ne 'MEASURED' -or $report.correctness -ne 'PASS' -or @($report.errors).Count -or $report.mode -ne $entry.mode -or
                $report.bundle_sha256 -ne $identity.bundle_sha256 -or $context.boot_identity.boot_time_utc -ne $legacyIdle.boot_identity.boot_time_utc -or
                $context.boot_identity.machine_guid -ne $legacyIdle.boot_identity.machine_guid -or $context.boot_identity.os_build -ne $legacyIdle.boot_identity.os_build -or
                $context.legacy_idle_directory -ine $LegacyIdleDirectory -or $context.route_profile_sha256 -ine $legacyProfileHash -or
                $report.config.echo_count -ne 128 -or $report.config.warmup_count -ne 16 -or $report.config.message_bytes -ne 512 -or $report.config.pause_ms -ne 20 -or
                $report.config.engine_sha256 -ine $engineSha -or $report.config.receiver_helper_sha256 -ine (Get-FileHash $receiver).Hash -or
                $report.config.proxy_helper_sha256 -ine (Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash -or
                $report.config.sampler_helper_sha256 -ine (Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash -or
                $report.config.python_sha256 -ine (Get-FileHash $PythonPath).Hash) { throw 'TCP_LEGACY_SMOKE_CONDITIONS_CHANGED' }
        }
    }
}
if ($pairedDriver) {
    $LegacyRttDirectory=(Resolve-Path -LiteralPath $LegacyRttDirectory).Path
    $referenceManifest=Get-Content -LiteralPath (Join-Path $LegacyRttDirectory 'comparison-manifest.json') -Raw | ConvertFrom-Json
    $referenceComparison=Get-Content -LiteralPath (Join-Path $LegacyRttDirectory 'comparison-report.json') -Raw | ConvertFrom-Json
    if ($referenceManifest.status -ne 'COMPLETED' -or $referenceManifest.profile -ne 'STANDARD' -or $referenceManifest.product_contract -ne 'v4.0.0' -or
        $referenceManifest.pair_count -ne 3 -or @($referenceManifest.runs).Count -ne 6 -or $referenceComparison.status -ne 'LIMITED_COMPARISON' -or @($referenceComparison.errors).Count) { throw 'TCP_VERSION_LEGACY_RTT_NOT_CONFIRMED' }
    $toolHashes=@{engine_sha256=$engineSha;source_sha256=(Get-FileHash (Join-Path $root 'src/pb_net_client.c')).Hash;receiver_helper_sha256=(Get-FileHash $receiver).Hash;proxy_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;sampler_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash;python_sha256=(Get-FileHash $PythonPath).Hash}
    $driverReference=$null
    $expectedReferenceNames=@('pair-01-off','pair-01-proxy','pair-02-proxy','pair-02-off','pair-03-off','pair-03-proxy')
    $referenceIndex=0
    foreach ($entry in $referenceManifest.runs) {
        if ($entry.directory -cne $expectedReferenceNames[$referenceIndex] -or $entry.mode -ine ($entry.directory.Split('-')[-1]) -or
            $entry.pair -ne ([int][Math]::Floor($referenceIndex/2)+1) -or $entry.status -ne 'COMPLETED') { throw 'TCP_VERSION_LEGACY_RTT_ENTRY_INVALID' }
        $referenceIndex++
        $refDirectory=Join-Path $LegacyRttDirectory $entry.directory
        $report=Get-Content -LiteralPath (Join-Path $refDirectory 'tcp-rtt-report.json') -Raw | ConvertFrom-Json
        $context=Get-Content -LiteralPath (Join-Path $refDirectory 'version-context.json') -Raw | ConvertFrom-Json
        if ($report.status -ne 'MEASURED' -or $report.correctness -ne 'PASS' -or @($report.errors).Count -or $report.mode -ne $entry.mode -or
            $report.config.product_contract -ne 'v4.0.0' -or $report.config.legacy_rtt_stage -ne 'repeat_rtt_v1' -or
            $report.config.echo_count -ne 1000 -or $report.config.warmup_count -ne 200 -or $report.config.message_bytes -ne 512 -or $report.config.pause_ms -ne 20 -or
            $report.config.live_socket_observation_policy -ne 'owned-socket-snapshot-before-measurement-v1') { throw 'TCP_VERSION_LEGACY_RTT_CONDITIONS_INVALID' }
        foreach ($key in $toolHashes.Keys) { if ($report.config.$key -ine $toolHashes[$key]) { throw ('TCP_VERSION_TOOL_CHANGED_'+$key) } }
        if ($null -eq $driverReference) { $driverReference=$context; $referenceBundle=$report.bundle_sha256; $referenceOtherDrivers=$report.other_driver_names_sha256 }
        elseif ($context.boot_identity.boot_time_utc -ne $driverReference.boot_identity.boot_time_utc -or $context.boot_identity.machine_guid -ne $driverReference.boot_identity.machine_guid -or
            $context.boot_identity.os_build -ne $driverReference.boot_identity.os_build -or $context.legacy_idle_directory -ine $driverReference.legacy_idle_directory -or
            $context.route_profile_sha256 -ine $driverReference.route_profile_sha256 -or $report.bundle_sha256 -ne $referenceBundle -or $report.other_driver_names_sha256 -ne $referenceOtherDrivers) { throw 'TCP_VERSION_LEGACY_RTT_SERIES_MIXED' }
    }
    $preflightDirectory=Split-Path -Parent $driverReference.legacy_idle_directory
    $preflight=Get-Content -LiteralPath (Join-Path $preflightDirectory 'preflight.json') -Raw | ConvertFrom-Json
    $selected=@($preflight.products | Where-Object contract -eq 'driver')
    $legacySelected=@($preflight.products | Where-Object contract -eq 'v4.0.0')
    if ($preflight.status -ne 'FILES_AND_PROFILES_PREPARED' -or $preflight.switch_policy -ne 'reboot_between_versions' -or
        $selected.Count -ne 1 -or $legacySelected.Count -ne 1 -or $referenceBundle -ne $legacySelected[0].identity.bundle_sha256 -or
        $selected[0].identity.bundle_sha256 -ne $identity.bundle_sha256 -or $identity.declared_cli_variant -ne 'testlab-unbuffered-v1' -or
        $identity.declared_source_commit -ne $selected[0].identity.declared_source_commit -or
        (Get-FileHash (Join-Path (Split-Path -Parent $EnvPath) 'build-receipt.json')).Hash -ine $selected[0].build_receipt_sha256) { throw 'TCP_VERSION_DRIVER_KIT_OR_PREFLIGHT_CHANGED' }
    $legacyProfile=Join-Path $preflightDirectory 'driver-tcp.pbprofile'
    $profileEntry=@($preflight.profile_files | Where-Object file_name -eq 'driver-tcp.pbprofile')
    $legacyEntry=@($preflight.profile_files | Where-Object file_name -eq 'v4.0.0-tcp.pbprofile')
    if ($profileEntry.Count -ne 1 -or $legacyEntry.Count -ne 1 -or (Get-FileHash $legacyProfile).Hash -ine $profileEntry[0].sha256 -or
        $driverReference.route_profile_sha256 -ine $legacyEntry[0].sha256) { throw 'TCP_VERSION_PINNED_PROFILE_CHANGED' }
    $legacyProfileHash=$profileEntry[0].sha256
    Set-WinDivertObserver $observationEnvironment
    $driverBoot=Assert-PairedDriverBoot
}
if (-not $EvidenceDirectory) { $EvidenceDirectory=Join-Path $root ('artifacts/local-route/tcp-rtt-'+$(if ($ThreeModes) {'three-modes-'} elseif ($ProductContract -eq 'v4.0.0') {'v4.0.0-'} elseif ($pairedDriver) {'driver-version-'} else {''})+$Profile.ToLowerInvariant()+'-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)) }
if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'TCP_RTT_REQUIRES_NEW_DIRECTORY' }
$null=New-Item -ItemType Directory -Path $EvidenceDirectory
$EvidenceDirectory=(Resolve-Path -LiteralPath $EvidenceDirectory).Path
$pairs=$(if ($Profile -eq 'SMOKE') {1} else {3})
$echoCount=$(if ($Profile -eq 'SMOKE') {128} else {1000})
$warmup=$(if ($Profile -eq 'SMOKE') {16} else {100})
if (($ProductContract -eq 'v4.0.0' -and $Profile -eq 'STANDARD') -or $pairedDriver) { $warmup=200 }
if ($ThreeModes) { $warmup=200 }
$messageBytes=512
$pauseMs=20
if ($presetMode) { $echoCount=$workload.echo_count;$warmup=$workload.warmup_count;$messageBytes=$workload.message_bytes;$pauseMs=$workload.pause_ms }
$nativeTimeoutMs=$(if ($presetMode) {$workload.native_timeout_ms} else {120000})
$manifest=[ordered]@{schema_version=1;status='RUNNING';profile=$Profile;scenario_id='tcp_echo_rtt_v1';started_at_utc=[DateTime]::UtcNow.ToString('o');pair_count=$pairs;echo_count=$echoCount;warmup_count=$warmup;message_bytes=$messageBytes;pause_ms=$pauseMs;runs=@();error='';version_switch_ready=$false}
if ($ProductContract -eq 'v4.0.0') { $manifest['product_contract']=$ProductContract; $manifest['readiness_only']=$true }
if ($pairedDriver) { $manifest['product_contract']='driver'; $manifest['legacy_rtt_directory']=$LegacyRttDirectory; $manifest['version_rtt_stage']='repeat_rtt_v1' }
if ($ThreeModes) { $manifest['comparison_stage']='three_modes_readiness_v1';$manifest['product_contract']='driver';$manifest['readiness_only']=$true }
if ($presetMode) {
    $manifest['workload_preset']=$workload;$manifest['readiness_only']=$false
    if ($ThreeModes) { $manifest['comparison_stage']='three_modes_workload_v1' }
}
$helperStopTimeoutMs=15000
function Write-Json($value,[string]$path) { $value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8 }
function Save-Manifest { Write-Json $manifest (Join-Path $EvidenceDirectory 'comparison-manifest.json') }
function Qpc-Ms { return [Diagnostics.Stopwatch]::GetTimestamp()*1000.0/[Diagnostics.Stopwatch]::Frequency }
function Start-Worker([string]$name,[string]$exe,[string[]]$arguments,$workers) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$exe; $info.Arguments=Join-ProcessArguments $arguments; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($info)
    $worker=[pscustomobject]@{name=$name;process=$process;stdout=$process.StandardOutput.ReadToEndAsync();stderr=$process.StandardError.ReadToEndAsync()}
    $workers.Add($worker)
    return $worker
}
function Wait-Event($worker,[string]$path,[int]$expectedCount=1) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt 5000) {
        if ($worker.process.HasExited) { throw "TCP_HELPER_EARLY_EXIT_$($worker.name)" }
        if (Test-Path $path) { if (@(Get-Content $path | Where-Object {$_} | ConvertFrom-Json | Where-Object event -eq 'LISTENING').Count -eq $expectedCount) { return } }
        Start-Sleep -Milliseconds 50
    }
    throw "TCP_HELPER_NOT_READY_$($worker.name)"
}
function Assert-Off {
    $state=Get-InterceptionStateSnapshot -Environment $observationEnvironment -AllowProductRuntime
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    $processes=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe'))
    if ($ProductContract -eq 'v4.0.0') {
        $state | Add-Member -NotePropertyName boot_identity -NotePropertyValue (Assert-LegacyBoot)
        $unexpected=@($loaded.known_interception_drivers | Where-Object { $_ -ine 'WinDivert64.sys' })
        if (-not $state.windivert.files_verified -or -not $state.windivert.capture_complete -or $state.windivert.status -ne 'NO_HANDLES_OBSERVED' -or
            $state.windivert.observed_handle_count -ne 0 -or $loaded.selected_driver_loaded -or $unexpected.Count -or
            $loaded.other_driver_names_sha256 -ne $legacyLoaded.other_driver_names_sha256) { throw 'TCP_LEGACY_IDLE_INTERCEPTION_NOT_CONFIRMED' }
    } elseif (-not $loaded.known_interception_driver_names_absent) { throw 'TCP_REQUIRES_CONFIRMED_PRODUCT_OFF' }
    if ($pairedDriver) {
        $state | Add-Member -NotePropertyName boot_identity -NotePropertyValue (Assert-PairedDriverBoot)
        if (-not $state.windivert.files_verified -or -not $state.windivert.capture_complete -or $state.windivert.status -ne 'NO_HANDLES_OBSERVED' -or
            $state.windivert.observed_handle_count -ne 0 -or $loaded.other_driver_names_sha256 -ne $referenceOtherDrivers) { throw 'TCP_VERSION_DRIVER_IDLE_OR_OTHER_DRIVERS_CHANGED' }
    }
    if (-not $state.current_driver_preparation_allowed -or -not $state.wfp_detachment_observed -or $state.wfp.service_state -ne 'Stopped' -or -not $loaded.query_complete -or $processes.Count) { throw 'TCP_REQUIRES_CONFIRMED_PRODUCT_OFF' }
    return [pscustomobject]@{state=$state;loaded=$loaded}
}
function Invoke-TcpRun([string]$mode,[string]$directory) {
    # A closure's dynamic module does not inherit the enclosing script's inputs
    # when a parent script invokes this controller. Capture these as function locals.
    foreach ($callbackInput in @('client','ProductContract','pairedDriver','observationEnvironment','ThreeModes','presetMode','nativeTimeoutMs')) {
        Set-Variable -Name $callbackInput -Value (Get-Variable -Name $callbackInput -Scope Script -ValueOnly) -Scope Local
    }
    $null=New-Item -ItemType Directory -Path $directory
    $workers=[Collections.Generic.List[object]]::new()
    $receipt=[ordered]@{status='RUNNING';mode=$mode;traffic_generated=$false;workers_stopped=$false;driver_stop_observed=$false;receiver_identity_verified=$false;version_switch_ready=$false;error=''}
    $receipt['helper_stop_timeout_ms']=$helperStopTimeoutMs
    $startedProduct=$false
    $native=$null
    $adapter=New-SystemProcessAdapter
    try {
        $before=Assert-Off
        Write-Json $before.state (Join-Path $directory 'interception-before.json')
        Write-Json $before.loaded (Join-Path $directory 'loaded-drivers-before.json')
        Write-Json $identity (Join-Path $directory 'product-build.json')
        if ($ProductContract -eq 'v4.0.0') {
            Write-Json ([ordered]@{product_contract=$ProductContract;legacy_idle_directory=$LegacyIdleDirectory;boot_identity=$legacyIdle.boot_identity;route_profile_sha256=$legacyProfileHash;readiness_only=$true;reboot_required_before_other_version=$true;version_switch_ready=$false}) (Join-Path $directory 'version-context.json')
            if ($Profile -eq 'STANDARD') {
                $contextPath=Join-Path $directory 'version-context.json'
                $context=Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json
                $context | Add-Member -NotePropertyName legacy_smoke_directory -NotePropertyValue $LegacySmokeDirectory
                Write-Json $context $contextPath
            }
        }
        if ($pairedDriver) {
            Write-Json ([ordered]@{product_contract='driver';legacy_rtt_directory=$LegacyRttDirectory;legacy_boot_identity=$driverReference.boot_identity;boot_identity=$driverBoot;route_profile_sha256=$legacyProfileHash;version_rtt_stage='repeat_rtt_v1';reboot_between_versions_observed=$true;version_switch_ready=$false}) (Join-Path $directory 'version-context.json')
        }
        foreach ($port in @(54122,54123,54125)) { if (@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count) { throw 'TCP_PORT_IN_USE' } }
        $runId=[guid]::NewGuid().ToString()
        $receiverLog=Join-Path $directory 'receiver.jsonl'
        $clientLog=Join-Path $directory 'client.jsonl'
        $common=@('--mode','single','--family','4','--protocol','tcp','--local-ip','127.0.0.1','--local-port','0','--remote-ip','127.0.0.1','--tcp-remote-port','54122','--tcp-rtt','1','--stream-count',"$($echoCount+$warmup)",'--benchmark-message-size',"$messageBytes",'--stream-interval-ms',"$pauseMs",'--test-id','local_tcp_echo_rtt','--run-id',$runId,'--jsonl-log',$clientLog,'--expected-action',$(if ($mode -eq 'PROXY') {'PROXY'} else {'DIRECT'}),'--tcp-peer-policy','record-only','--expect','echo','--timeout-ms','3000')
        $server=Start-Worker 'receiver' $PythonPath @('-u',$receiver,'--jsonl-log',$receiverLog,'--endpoint-a-port','54122','--endpoint-b-port','54125','--control-stdin','--log-flush-mode','BUFFERED','--tcp-nodelay') $workers
        Wait-Event $server $receiverLog 8
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while ($timer.ElapsedMilliseconds -lt 5000) {
            if ($server.process.HasExited) { throw 'TCP_RECEIVER_EARLY_EXIT' }
            if (@(Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort 54122 -State Listen -OwningProcess $server.process.Id -ErrorAction SilentlyContinue).Count -eq 1) { $receipt.receiver_identity_verified=$true; break }
            Start-Sleep -Milliseconds 50
        }
        if (-not $receipt.receiver_identity_verified) { throw 'TCP_RECEIVER_NOT_READY' }
        $proxyLog=Join-Path $directory 'proxy.jsonl'
        $proxy=Start-Worker 'proxy' $PythonPath @('-u',(Join-Path $root 'src/pb_controlled_tcp_proxy.py'),'--wheel',$wheel,'--jsonl-log',$proxyLog,'--port','54123','--receiver-port','54122','--max-duration-seconds',$(if ($presetMode) {'720'} else {'180'})) $workers
        Wait-Event $proxy $proxyLog
        $samplerLog=Join-Path $directory 'pc-samples.jsonl'
        $samplerConfig=Join-Path $directory 'sampler-config.json'
        Write-Json @([ordered]@{role='receiver';pid=$server.process.Id;path=$PythonPath},[ordered]@{role='proxy';pid=$proxy.process.Id;path=$PythonPath}) $samplerConfig
        $sampler=Start-Worker 'sampler' $PythonPath @('-u',(Join-Path $root 'src/pb_pc_sampler.py'),'--packages',$packages,'--config',$samplerConfig,'--jsonl-log',$samplerLog,'--max-duration-seconds',$(if ($presetMode) {'720'} else {'180'})) $workers
        Wait-Event $sampler $samplerLog
        Write-Json ([ordered]@{scenario_id='tcp_echo_rtt_v1';run_id=$runId;echo_count=$echoCount;warmup_count=$warmup;message_bytes=$messageBytes;pause_ms=$pauseMs;connections=1;client_tcp_nodelay=$true;receiver_tcp_nodelay=$true;receiver_log_mode='BUFFERED';receiver_port=54122;proxy_port=54123;proxy_event_loop='_WindowsSelectorEventLoop';engine_sha256=$engineSha;source_sha256=(Get-FileHash (Join-Path $root 'src/pb_net_client.c')).Hash;receiver_helper_sha256=(Get-FileHash $receiver).Hash;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;proxy_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash;sampler_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash;python_sha256=(Get-FileHash $PythonPath).Hash;receiver_pid=$server.process.Id;proxy_pid=$proxy.process.Id;sampler_pid=$sampler.process.Id}) (Join-Path $directory 'benchmark-config.json')
        if ($ThreeModes) {
            $configPath=Join-Path $directory 'benchmark-config.json'
            $config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $config | Add-Member -NotePropertyName comparison_stage -NotePropertyValue 'three_modes_readiness_v1'
            $config | Add-Member -NotePropertyName live_socket_observation_policy -NotePropertyValue 'owned-socket-snapshot-before-measurement-v1'
            Write-Json $config $configPath
        }
        if ($presetMode) {
            $configPath=Join-Path $directory 'benchmark-config.json'
            $config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $config | Add-Member -NotePropertyName workload_preset -NotePropertyValue $workload
            $config | Add-Member -Force -NotePropertyName live_socket_observation_policy -NotePropertyValue 'owned-socket-snapshot-before-measurement-v1'
            if ($ThreeModes) { $config.comparison_stage='three_modes_workload_v1' }
            Write-Json $config $configPath
        }
        if ($ProductContract -eq 'v4.0.0' -or $pairedDriver) {
            $configPath=Join-Path $directory 'benchmark-config.json'
            $config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $config | Add-Member -NotePropertyName product_contract -NotePropertyValue $ProductContract
            $config | Add-Member -NotePropertyName route_profile_sha256 -NotePropertyValue $legacyProfileHash
            $config | Add-Member -NotePropertyName live_socket_observation_policy -NotePropertyValue $(if ($Profile -eq 'STANDARD') {'owned-socket-snapshot-before-measurement-v1'} else {'owned-socket-snapshot-smoke-v1'})
            if ($Profile -eq 'STANDARD') { $config | Add-Member -NotePropertyName legacy_rtt_stage -NotePropertyValue 'repeat_rtt_v1' }
            if ($pairedDriver) {
                $config.PSObject.Properties.Remove('legacy_rtt_stage')
                $config | Add-Member -NotePropertyName version_rtt_stage -NotePropertyValue 'repeat_rtt_v1'
            }
            Write-Json $config $configPath
        }
        $qpcCommand=Get-Command Qpc-Ms -CommandType Function
        $writeJsonCommand=Get-Command Write-Json -CommandType Function
        $loadedObservationCommand=Get-Command Get-LoadedInterceptionDriverObservation -CommandType Function
        $interceptionSnapshotCommand=Get-Command Get-InterceptionStateSnapshot -CommandType Function
        $workload={
            param($cli)
            if ($mode -in @('PROXY','UNRULED')) {
                $active=& $loadedObservationCommand -AllowProductRuntime
                & $writeJsonCommand $active (Join-Path $directory 'loaded-drivers-active.json')
                if ($ProductContract -eq 'v4.0.0') {
                    $activeState=& $interceptionSnapshotCommand -Environment $observationEnvironment -AllowProductRuntime
                    & $writeJsonCommand $activeState (Join-Path $directory 'interception-active.json')
                    $handles=@($activeState.windivert.handles)
                    if (-not $active.query_complete -or $active.selected_driver_loaded -or @($active.known_interception_drivers).Count -ne 1 -or
                        $active.known_interception_drivers[0] -ine 'WinDivert64.sys' -or -not $activeState.wfp_detachment_observed -or
                        -not $activeState.windivert.files_verified -or -not $activeState.windivert.capture_complete -or $handles.Count -ne 1 -or
                        $handles[0].pid -ne $cli.pid -or $handles[0].layer -ne 'NETWORK' -or $handles[0].flags -ne '0') { throw 'TCP_LEGACY_OWNED_ACTIVE_HANDLE_NOT_CONFIRMED' }
                } elseif (-not $active.query_complete -or -not $active.selected_driver_loaded -or $active.known_interception_drivers.Count -ne 1) { throw 'TCP_SELECTED_ACTIVE_DRIVER_NOT_CONFIRMED' }
                if ($ThreeModes) {
                    $activeState=& $interceptionSnapshotCommand -Environment $observationEnvironment -AllowProductRuntime
                    & $writeJsonCommand $activeState (Join-Path $directory 'interception-active.json')
                    if ($activeState.wfp.status -ne 'SERVICE_FILE_VERIFIED' -or $activeState.wfp.service_state -ne 'Running') { throw 'TCP_THREE_MODES_ACTIVE_SERVICE_NOT_CONFIRMED' }
                    $live=$cli.session.Stdout
                    $image=$(if ($mode -eq 'UNRULED') {'pb_testlab_other_app.exe'} else {'pb_tcp_rtt_client.exe'})
                    $watches=@([regex]::Matches($live,'driver: pushed (\d+) watched image\(s\)'))
                    if (-not $watches.Count -or @($watches | Where-Object { $_.Groups[1].Value -ne '1' }).Count -or
                        $live -notmatch ('Added rule ID: \d+ for process '''+[regex]::Escape($image)+'''') -or
                        $live -notmatch '1 added, 0 failed' -or $live -notmatch 'driver: ProxyBridgeDrv active -') { throw 'TCP_THREE_MODES_PROFILE_NOT_CONFIRMED' }
                }
                if ($pairedDriver) {
                    $activeState=& $interceptionSnapshotCommand -Environment $observationEnvironment -AllowProductRuntime
                    & $writeJsonCommand $activeState (Join-Path $directory 'interception-active.json')
                    if (-not $activeState.windivert.files_verified -or -not $activeState.windivert.capture_complete -or $activeState.windivert.status -ne 'NO_HANDLES_OBSERVED' -or
                        $activeState.windivert.observed_handle_count -ne 0 -or $activeState.wfp.status -ne 'SERVICE_FILE_VERIFIED' -or $activeState.wfp.service_state -ne 'Running') { throw 'TCP_VERSION_DRIVER_ACTIVE_STATE_NOT_CONFIRMED' }
                }
                & $writeJsonCommand @(Get-NetTCPConnection -State Listen -OwningProcess $cli.pid | Select-Object LocalAddress,LocalPort,OwningProcess) (Join-Path $directory 'product-tcp-listeners.json')
                $sampler.process.StandardInput.WriteLine(([ordered]@{role='proxybridge_cli';pid=$cli.pid;path=$cli.actual_path} | ConvertTo-Json -Compress));$sampler.process.StandardInput.Flush()
            }
            Start-Sleep -Milliseconds 1000
            $plan=[pscustomobject]@{executable=$client;arguments=$common;timeout_ms=$nativeTimeoutMs}
            if ([string]::IsNullOrWhiteSpace([string]$plan.executable)) { throw 'TCP_RTT_CALLBACK_CLIENT_EXECUTABLE_MISSING' }
            $start=& $qpcCommand
            $native=& $adapter.StartProcess $plan
            try {
                $probe=& $adapter.ProbeActualPath $native 2000 25
                if ($probe.status -ne 'PATH_OBTAINED' -or $native.actual_path -ine $client) { throw 'TCP_CLIENT_IDENTITY_NOT_CONFIRMED' }
                $sampler.process.StandardInput.WriteLine(([ordered]@{role='generator';pid=$native.pid;path=$native.actual_path} | ConvertTo-Json -Compress));$sampler.process.StandardInput.Flush()
                $receipt.traffic_generated=$true
                if ($ProductContract -eq 'v4.0.0' -or $pairedDriver -or $ThreeModes -or $presetMode) {
                    $connectionTimer=[Diagnostics.Stopwatch]::StartNew()
                    $connections=@()
                    $owner=$(if ($mode -eq 'PROXY') {$cli.pid} else {$native.pid})
                    $targetPort=$(if ($mode -eq 'PROXY') {54123} else {54122})
                    do {
                        $connections=@(Get-NetTCPConnection -OwningProcess $owner -State Established -ErrorAction SilentlyContinue | Where-Object { $_.RemoteAddress -eq '127.0.0.1' -and $_.RemotePort -eq $targetPort })
                        if ($connections.Count -or -not $native.session.IsRunning) { break }
                        Start-Sleep -Milliseconds 50
                    } while ($connectionTimer.ElapsedMilliseconds -lt 5000)
                    & $writeJsonCommand @($connections | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,OwningProcess) (Join-Path $directory $(if ($mode -eq 'PROXY') {'product-proxy-connections.json'} else {'generator-direct-connections.json'}))
                    & $writeJsonCommand ([ordered]@{start_qpc_ms=$start;capture_completed_qpc_ms=(& $qpcCommand);query_elapsed_ms=$connectionTimer.ElapsedMilliseconds;owner_pid=$owner;target_port=$targetPort}) (Join-Path $directory 'live-socket-observation.json')
                    if (-not $connections.Count) { throw 'TCP_LEGACY_OWNED_CONNECTION_NOT_OBSERVED' }
                }
                if (-not $native.session.WaitForExit($nativeTimeoutMs)) { $native.timed_out=$true; & $adapter.StopProcess $native; throw 'TCP_CLIENT_TIMEOUT' }
                $end=& $qpcCommand
                $result=& $adapter.GetProcessResult $native
                & $writeJsonCommand $result (Join-Path $directory 'client-process.json')
                & $writeJsonCommand ([ordered]@{start_qpc_ms=$start;end_qpc_ms=$end;client_pid=$native.pid}) (Join-Path $directory 'measurement-window.json')
                if ($result.exit_code -ne 0 -or $result.timed_out -or -not $result.output_capture_complete) { throw 'TCP_CLIENT_FAILED' }
                return $result
            } finally {
                if ($native.session.IsRunning) { & $adapter.StopProcess $native }
                & $adapter.DisposeProcess $native
            }
        }.GetNewClosure()
        if ($mode -in @('PROXY','UNRULED')) {
            if ($ProductContract -eq 'driver') {
                $runtimeConfig=Get-Content (Join-Path $root 'config/runtime.json') -Raw | ConvertFrom-Json
                $runtimePlan=New-RuntimeEnvironmentPlan -Environment $environment -RuntimeConfig $runtimeConfig -ProductOnly
                if ($runtimePlan.service_bootstrap -ne 'driver-service') { throw 'TCP_REQUIRES_HEADLESS_KIT' }
                $startedProduct=$true
                $preparation=Invoke-RuntimeEnvironmentPreparation -Plan $runtimePlan -Adapter (New-SystemRuntimeEnvironmentAdapter) -AllowProductRuntime
                Write-Json $preparation (Join-Path $directory 'preparation-result.json')
                if (-not $preparation.prepared) { throw 'TCP_PRODUCT_PREPARATION_FAILED' }
            }
            $profilePath=Join-Path $directory 'route.pbprofile'
            if ($ProductContract -eq 'v4.0.0' -or $pairedDriver) {
                Copy-Item -LiteralPath $legacyProfile -Destination $profilePath
                if ((Get-FileHash $profilePath).Hash -ine $legacyProfileHash) { throw 'TCP_LEGACY_COPIED_PROFILE_CHANGED' }
            } else {
                Write-Json ([ordered]@{Version='1.0';LocalhostViaProxy=$true;IsTrafficLoggingEnabled=$true;ProxyConfigs=@([ordered]@{Id=1;Name='Controlled TCP SOCKS5';Type='SOCKS5';Host='127.0.0.1';Port='54123';Username='';Password='';SendDomainToProxy=$false});ProxyRules=@([ordered]@{Name='TCP request and response latency';ProcessName='pb_tcp_rtt_client.exe';TargetHosts='127.0.0.1';TargetPorts='54122';TargetDomains='';Protocol='TCP';Action='PROXY';ProxyConfigId=1;IsEnabled=$true})}) $profilePath
                if ($mode -eq 'UNRULED') {
                    $route=Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
                    $route.ProxyRules[0].ProcessName='pb_testlab_other_app.exe'
                    $route.ProxyRules[0].Name='Other application only / Только другое приложение'
                    Write-Json $route $profilePath
                }
            }
            $cliPlan=New-ProxyBridgeCliPlan -ExecutablePath $environment['PB_PROXYBRIDGE_CLI_EXE'] -ProfilePath $profilePath -ProductProfileContract $ProductContract -CliVariant $environment['PB_PROXYBRIDGE_CLI_VARIANT'] -ReadyStableMs 1000 -ReadinessTimeoutMs 10000 -StopTimeoutMs 5000
            $sink={param($value) & $writeJsonCommand $value (Join-Path $directory 'cli-lifecycle.json')}.GetNewClosure()
            $lifecycle=Invoke-ProxyBridgeCliLifecycle -Plan $cliPlan -ProcessAdapter $adapter -AllowProductRuntime -Workload $workload -EvidenceSink $sink
            if (-not $lifecycle.ready -or -not $lifecycle.graceful_stop -or $lifecycle.forced_stop -or -not $lifecycle.post_stop_verified -or $lifecycle.process_result.exit_code -ne 0) { throw 'TCP_CLI_LIFECYCLE_FAILED' }
            $records=@(ConvertFrom-ProxyBridgeTextLines -Lines @($lifecycle.process_result.stdout -split '\r?\n') -DefaultTimestampUtc ([DateTime]::Parse($lifecycle.started_at_utc)))
            Write-Json $records (Join-Path $directory 'route-observations.json')
        } else { $null=& $workload $null }
        $receipt.status='COMPLETED'
    } catch { $receipt.status='FAILED';$receipt.error=$_.Exception.Message }
    finally {
        $clean=$true
        foreach ($worker in $workers) {
            $forced=$false
            try {
                if (-not $worker.process.HasExited) { $worker.process.StandardInput.WriteLine('STOP');$worker.process.StandardInput.Flush() }
                if (-not $worker.process.WaitForExit($helperStopTimeoutMs)) {
                    $receipt.error+='; TCP_HELPER_STOP_TIMEOUT_'+$worker.name+'_'+$helperStopTimeoutMs+'ms'
                    $worker.process.Kill();$worker.process.WaitForExit();$forced=$true
                }
                $out=$worker.stdout.GetAwaiter().GetResult();$err=$worker.stderr.GetAwaiter().GetResult()
                Write-Json ([ordered]@{pid=$worker.process.Id;exit_code=$worker.process.ExitCode;forced_stop=$forced;stdout=$out;stderr=$err;output_capture_complete=$true}) (Join-Path $directory ($worker.name+'-process.json'))
                if ($forced -or $worker.process.ExitCode -ne 0) {
                    $clean=$false
                    $receipt.error+='; TCP_HELPER_EXIT_NOT_CLEAN_'+$worker.name+'_exit'+$worker.process.ExitCode+'_forced'+$forced
                }
            } catch { $clean=$false;$receipt.error+='; helper cleanup: '+$_.Exception.Message }
            finally { if (-not $worker.process.HasExited) { $worker.process.Kill();$worker.process.WaitForExit() };$worker.process.Dispose() }
        }
        $receipt.workers_stopped=$clean
        try {
            if ($startedProduct -and $ProductContract -eq 'driver') {
                $stopState=Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
                if ($stopState.wfp.status -ne 'SERVICE_FILE_VERIFIED') { throw 'TCP_DRIVER_IDENTITY_CHANGED' }
                $scm=[ServiceProcess.ServiceController]::new('ProxyBridgeDrv')
                try { if ($scm.Status -eq [ServiceProcess.ServiceControllerStatus]::Running) { $scm.Stop() };$scm.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(10)) } finally { $scm.Dispose() }
            }
            $after=Assert-Off
            Write-Json $after.state (Join-Path $directory 'interception-after.json')
            Write-Json $after.loaded (Join-Path $directory 'loaded-drivers-after.json')
            $receipt.driver_stop_observed=$true
        } catch { $receipt.error+='; driver cleanup: '+$_.Exception.Message }
        if (-not $receipt.workers_stopped -or -not $receipt.driver_stop_observed) { $receipt.status='FAILED' }
        Write-Json $receipt (Join-Path $directory 'run-receipt.json')
    }
    if ($receipt.status -ne 'COMPLETED') {
        if (-not $receipt.error) { $receipt.error='TCP_RUN_NOT_COMPLETED_WITHOUT_DETAIL';Write-Json $receipt (Join-Path $directory 'run-receipt.json') }
        throw $receipt.error
    }
    & $PythonPath (Join-Path $root 'src/pb_tcp_rtt_report.py') --run-directory $directory
    if ($LASTEXITCODE -ne 0) { throw 'TCP_EVIDENCE_NOT_CONFIRMED' }
}
Write-Host ('TCP request/response RTT: '+$Profile+'; SOCKS5 vs direct; '+$pairs+' pairs; '+$echoCount+' echoes/run + '+$warmup+' warmup; '+$messageBytes+' bytes; pause '+$pauseMs+' ms after reply.')
Write-Host 'Запрос и полный ответ в одном TCP-соединении / Request and complete reply on one TCP connection. TCP_NODELAY, warmup excluded; not ICMP ping, connection setup, fixed offered rate or maximum throughput.'
Write-Host ('Результаты / Results: '+$EvidenceDirectory)
if ($ThreeModes -and -not $presetMode) { Write-Host 'Три режима / Three modes: OFF -> UNRULED -> SOCKS5; 128 measured + 200 warmup/run. Owned socket snapshot before measurement. Около 3–5 минут / Approximately 3–5 minutes; readiness only, no capacity or version comparison.' }
if ($presetMode) { Write-Host ('Профиль / Workload: '+$Duration+' / '+$Load+'; интенсивность запросов, без фоновой передачи / request intensity, no background transfer. Warmup/socket snapshot excluded; duration is exchange volume, not a wall-clock timer.') }
if ($ProductContract -eq 'v4.0.0') {
    Write-Host '4.0.0: WinDivert handles проверяются до/во время/после. Перед Driver нужна перезагрузка / Reboot before Driver; this is not a version comparison.'
    if ($Profile -eq 'STANDARD') { Write-Host 'Три пары, 200 прогревочных обменов; socket snapshot должен завершиться до измерения. Около 5–10 минут / Three pairs, 200 warmup echoes; socket observation must finish before measurement. Approximately 5–10 minutes.' }
    else { Write-Host 'Короткая проверка готовности, около 1–3 минут / Readiness only, approximately 1–3 minutes.' }
}
if ($pairedDriver) { Write-Host 'Driver: условия связаны с указанной серией4.0.0; 200 warmup, socket snapshot до measuredwindow, около5–10мин / Bound legacy reference; approximately 5–10 minutes. New paired-version runtime evidence pending.' }
Save-Manifest
try {
    :runPairs for ($pair=1;$pair -le $pairs;$pair++) {
        $order=$(if ($pair % 2) { @('OFF','PROXY') } else { @('PROXY','OFF') })
        if ($ThreeModes) { $order=@('OFF','UNRULED','PROXY') }
        foreach ($mode in $order) {
            if ($CancellationPath -and (Test-Path -LiteralPath $CancellationPath -PathType Leaf)) {
                $manifest.status='CANCELLED';$manifest['cancellation_requested']=$true
                Write-Host 'Остановлено между прогонами; завершённые данные сохранены / Stopped between runs; completed evidence retained.'
                break runPairs
            }
            $name='pair-{0:d2}-{1}' -f $pair,$mode.ToLowerInvariant()
            $entry=[ordered]@{pair=$pair;mode=$mode;directory=$name;status='RUNNING'}
            $manifest.runs+=$entry;Save-Manifest
            Write-Host ('['+$manifest.runs.Count+'/'+($pairs*$(if ($ThreeModes) {3} else {2}))+'] '+$name)
            Invoke-TcpRun $mode (Join-Path $EvidenceDirectory $name)
            $entry.status='COMPLETED';Save-Manifest
        }
    }
    if ($manifest.status -ne 'CANCELLED') { $manifest.status='COMPLETED' }
} catch { $manifest.status='FAILED';$manifest.error=$(if ($_.Exception.Message) { $_.Exception.Message } else { 'TCP_RTT_SERIES_FAILED_WITHOUT_DETAIL' }) }
finally { $manifest['completed_at_utc']=[DateTime]::UtcNow.ToString('o');Save-Manifest }
if ($manifest.status -eq 'CANCELLED') { return }
if ($manifest.status -ne 'COMPLETED') { throw $manifest.error }
& $PythonPath (Join-Path $root $(if ($ThreeModes) {'src/pb_tcp_three_mode_report.py'} else {'src/pb_tcp_rtt_report.py'})) --evidence-directory $EvidenceDirectory
if ($LASTEXITCODE -ne 0) { throw 'TCP_RTT_COMPARISON_NOT_CONFIRMED' }
Write-Host ('Отчёт / Report: '+(Join-Path $EvidenceDirectory 'summary.md'))
