#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateSet('SMOKE','STANDARD')][string]$Profile='SMOKE',
    [string]$EvidenceDirectory='',
    [string]$EnvPath='',
    [string]$PythonPath='',
    [switch]$Resume,
    [ValidateSet('driver','v4.0.0')][string]$ProductContract='driver',
    [string]$LegacyIdleDirectory='',
    [switch]$DiagnosticRudeShutdown,
    [switch]$DiagnosticGracefulShutdown,
    [switch]$DiagnosticHalfCloseFixture,
    [switch]$DiagnosticCloseMetadata,
    [switch]$TransferOnly,
    [string]$LegacyTransferDirectory='',
    [string]$DriverSmokeDirectory='',
    [string]$DriverTransferDirectory='',
    [string]$CancellationPath='',
    [ValidateSet('SHORT','NORMAL','LONG')][string]$Duration='',
    [ValidateSet('LOW','HIGH')][string]$Load=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$presetMode=[bool]($Duration -or $Load)
$workload=$null
if ($presetMode) {
    if (-not $Duration -or -not $Load -or $ProductContract -ne 'driver' -or $Profile -ne 'SMOKE' -or -not $TransferOnly -or $Resume -or $LegacyIdleDirectory -or $LegacyTransferDirectory -or $DriverSmokeDirectory -or $DriverTransferDirectory -or $DiagnosticRudeShutdown -or $DiagnosticGracefulShutdown -or $DiagnosticHalfCloseFixture -or $DiagnosticCloseMetadata) { throw 'TCP_WORKLOAD_REQUIRES_FRESH_DRIVER_DATA_ONLY' }
    Import-Module (Join-Path $root 'modules/BenchmarkWorkload.psm1')
    $workload=Get-BenchmarkWorkload -Duration $Duration -Load $Load
}
foreach ($name in @('Env','ProductBuild','RuntimeEnvironment','InterceptionState','ProxyBridgeCli','ProcessAdapter','ProxyBridgeEvidence')) { Import-Module (Join-Path $root ('modules/'+$name+'.psm1')) }
$repeatLegacy=$ProductContract -eq 'v4.0.0' -and -not [string]::IsNullOrWhiteSpace($DriverTransferDirectory)
if ($DriverTransferDirectory -and (-not $repeatLegacy -or $Profile -ne 'STANDARD' -or -not $TransferOnly -or $Resume -or $DriverSmokeDirectory -or $LegacyTransferDirectory)) { throw 'TCP_LEGACY_REPEAT_REQUIRES_FRESH_STANDARD_AND_DRIVER_TRANSFER_SOURCE' }
if ($ProductContract -eq 'v4.0.0' -and (($Profile -ne 'SMOKE' -and -not $repeatLegacy) -or $Resume -or -not $LegacyIdleDirectory)) { throw 'TCP_LEGACY_TRANSFER_REQUIRES_VALIDATED_PROFILE_AND_IDLE_DIRECTORY' }
if ($ProductContract -eq 'driver' -and $LegacyIdleDirectory) { throw 'TCP_LEGACY_IDLE_ARGUMENT_REQUIRES_LEGACY_CONTRACT' }
if ($DiagnosticRudeShutdown -and $DiagnosticGracefulShutdown) { throw 'TCP_SHUTDOWN_DIAGNOSTICS_ARE_MUTUALLY_EXCLUSIVE' }
if ($DiagnosticHalfCloseFixture -and -not $DiagnosticGracefulShutdown) { throw 'TCP_HALFCLOSE_FIXTURE_REQUIRES_ISOLATED_GRACEFUL_DIAGNOSTIC' }
if ($DiagnosticCloseMetadata -and -not $DiagnosticHalfCloseFixture) { throw 'TCP_CLOSE_METADATA_REQUIRES_ISOLATED_HALFCLOSE_DIAGNOSTIC' }
$shutdownDiagnostic=[bool]($DiagnosticRudeShutdown -or $DiagnosticGracefulShutdown)
$repeatDriver=$ProductContract -eq 'driver' -and -not [string]::IsNullOrWhiteSpace($DriverSmokeDirectory)
$boundDriver=$ProductContract -eq 'driver' -and ($repeatDriver -or -not [string]::IsNullOrWhiteSpace($LegacyTransferDirectory))
if ($DriverSmokeDirectory -and (-not $repeatDriver -or -not $TransferOnly -or $Profile -ne 'STANDARD' -or $Resume -or $LegacyTransferDirectory)) { throw 'TCP_DRIVER_REPEATED_TRANSFER_REQUIRES_FRESH_STANDARD_AND_SMOKE_ONLY' }
if ($LegacyTransferDirectory -and (-not $boundDriver -or -not $TransferOnly -or $Profile -ne 'SMOKE' -or $Resume)) { throw 'TCP_DRIVER_TRANSFER_REFERENCE_REQUIRES_FRESH_DATA_SMOKE' }
if ($TransferOnly -and (($Profile -ne 'SMOKE' -and -not $repeatDriver -and -not $repeatLegacy) -or $Resume -or $shutdownDiagnostic -or $DiagnosticHalfCloseFixture -or $DiagnosticCloseMetadata)) { throw 'TCP_TRANSFER_ONLY_REQUIRES_FRESH_VALIDATED_PROFILE_WITHOUT_DIAGNOSTICS' }
if ($shutdownDiagnostic -and ($ProductContract -ne 'v4.0.0' -or $Profile -ne 'SMOKE' -or $Resume)) { throw 'TCP_SHUTDOWN_DIAGNOSTIC_REQUIRES_FRESH_LEGACY_SMOKE' }
$legacyStage=$(if ($repeatLegacy) {'transfer_data_standard_v1'} elseif ($TransferOnly) {'transfer_data_smoke_v1'} elseif ($DiagnosticHalfCloseFixture) {'transfer_graceful_halfclose_diagnostic_v1'} elseif ($DiagnosticRudeShutdown) {'transfer_rude_diagnostic_v1'} elseif ($DiagnosticGracefulShutdown) {'transfer_graceful_diagnostic_v1'} else {'transfer_smoke_v1'})
$shutdownMode=$(if ($DiagnosticRudeShutdown -or $TransferOnly) {'rude'} else {'graceful'})
if ($CancellationPath -and ($ProductContract -ne 'driver' -or $Profile -ne 'SMOKE' -or -not $TransferOnly -or $Resume -or $shutdownDiagnostic)) { throw 'TCP_CANCEL_REQUIRES_FRESH_DRIVER_DATA_SMOKE' }
$consoleVerbosity=$(if ($DiagnosticGracefulShutdown) {6} else {1})
$directions=$(if ($shutdownDiagnostic) {@('push')} else {@('push','pull')})
if (-not $EnvPath) { $EnvPath=Join-Path $root ('artifacts/product-builds/'+$(if ($ProductContract -eq 'driver') {'driver-63be0eb'} else {'v4.0.0-release'})+'-testlab-cli/product.env') }
if (-not $PythonPath) { $PythonPath=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' }
$tool=Join-Path $root 'bin/tools/ctstraffic-2.0.3.9'
$client=Join-Path $tool 'ctsTraffic.exe'
$receiver=Join-Path $tool 'ctsTrafficReceiver.exe'
$wheel=Join-Path $root 'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl'
$proxyLauncher=Join-Path $root $(if ($DiagnosticHalfCloseFixture) {'src/pb_tcp_halfclose_diagnostic.py'} else {'src/pb_controlled_tcp_proxy.py'})
$packages=Join-Path $root 'bin/tools/psutil-7.2.2/packages'
$samplerWheel=Join-Path $root 'bin/tools/psutil-7.2.2/psutil-7.2.2-cp37-abi3-win_amd64.whl'
foreach ($path in @($EnvPath,$PythonPath,$client,$receiver,$wheel,$proxyLauncher,(Join-Path $packages 'psutil/__init__.py'))) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "TCP_DEPENDENCY_MISSING_$path" } }
$engineSha='0548089E59C872306CE2C98E7163E2A717119756010CF64D3CB3DA2854F632CF'
foreach ($path in @($client,$receiver)) { if ((Get-FileHash $path).Hash -ne $engineSha) { throw 'TCP_ENGINE_HASH_MISMATCH' } }
if ((Get-FileHash $wheel).Hash -ne '5190D3AE00A29325EC9048306FCD8BD08F8E89DDD75C535CC01D1D646F105344' -or (Get-FileHash $samplerWheel).Hash -ne 'EB7E81434C8D223EC4A219B5FC1C47D0417B12BE7EA866E24FB5AD6E84B3D988') { throw 'TCP_LIBRARY_WHEEL_HASH_MISMATCH' }
$environment=Import-DotEnv -Path $EnvPath
$identity=Get-ProductBuildIdentity -Environment $environment -Contract $ProductContract
if (-not $identity.files_verified) { throw 'TCP_PRODUCT_FILES_NOT_VERIFIED' }
$closeCaptureHelper=Join-Path $root 'src/pb_tcp_close_metadata.py'
$closeCaptureDll=Join-Path (Split-Path -Parent $environment['PB_PROXYBRIDGE_CLI_EXE']) 'WinDivert.dll'
if ($DiagnosticCloseMetadata) {
    if (-not (Test-Path -LiteralPath $closeCaptureHelper -PathType Leaf) -or
        (Get-FileHash -LiteralPath $closeCaptureDll).Hash -ine $environment['PB_EXPECTED_WINDIVERT_DLL_SHA256']) { throw 'TCP_CLOSE_METADATA_DEPENDENCY_CHANGED' }
}
$observationEnvironment=$environment
$legacyProfile='';$legacyProfileHash='';$legacyIdle=$null;$legacyLoaded=$null
$transferReference=$null;$driverSmokeReference=$null;$driverTransferReference=$null;$driverProfile='';$driverProfileHash=''
$transferStage=$(if ($repeatDriver) {'data-transfer-repeat-v1'} else {'data-transfer-readiness-bound-v1'})
function Assert-BoundDriverBoot {
    $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop
    $observed=[pscustomobject]@{computer_name=$env:COMPUTERNAME;machine_guid=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid;os_build=[string]$os.BuildNumber;boot_time_utc=([DateTime]$os.LastBootUpTime).ToUniversalTime().ToString('o')}
    foreach ($key in @('computer_name','machine_guid','os_build')) {
        if ($observed.$key -ne $transferReference.legacy_boot_identity.$key) { throw 'TCP_DRIVER_TRANSFER_MACHINE_CHANGED' }
    }
    if ([DateTimeOffset]::Parse($observed.boot_time_utc) -le [DateTimeOffset]::Parse($transferReference.legacy_completed_at_utc)) { throw 'TCP_DRIVER_TRANSFER_REBOOT_REQUIRED' }
    if ($repeatDriver -and $observed.boot_time_utc -ne $driverSmokeReference.boot_identity.boot_time_utc) { throw 'TCP_DRIVER_REPEATED_TRANSFER_REQUIRES_SMOKE_BOOT' }
    return $observed
}
function Assert-LegacyTransferBoot {
    $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop
    $observed=[pscustomobject]@{computer_name=$env:COMPUTERNAME;machine_guid=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid;os_build=[string]$os.BuildNumber;boot_time_utc=([DateTime]$os.LastBootUpTime).ToUniversalTime().ToString('o')}
    foreach ($key in @('computer_name','machine_guid','os_build','boot_time_utc')) {
        if ($observed.$key -ne $legacyIdle.boot_identity.$key) { throw 'TCP_LEGACY_TRANSFER_BOOT_OR_MACHINE_CHANGED' }
    }
    if ($repeatLegacy -and $null -ne $driverTransferReference) {
        foreach ($key in @('computer_name','machine_guid','os_build')) { if ($observed.$key -ne $driverTransferReference.driver_boot_identity.$key) { throw 'TCP_LEGACY_REPEAT_MACHINE_CHANGED' } }
        if ([DateTimeOffset]::Parse($observed.boot_time_utc) -le [DateTimeOffset]::Parse($driverTransferReference.driver_completed_at_utc)) { throw 'TCP_LEGACY_REPEAT_REBOOT_REQUIRED' }
    }
    return $observed
}
if ($ProductContract -eq 'v4.0.0') {
    $LegacyIdleDirectory=(Resolve-Path -LiteralPath $LegacyIdleDirectory).Path
    $legacyIdle=Get-Content -LiteralPath (Join-Path $LegacyIdleDirectory 'idle-receipt.json') -Raw | ConvertFrom-Json
    if ($legacyIdle.status -ne 'LEGACY_IDLE_SCOPED_OBSERVED' -or $legacyIdle.contract -ne 'v4.0.0' -or $legacyIdle.error -or
        -not $legacyIdle.same_version_idle_observed -or -not $legacyIdle.no_compatible_windivert_handles_observed -or -not $legacyIdle.known_wfp_detachment_observed) { throw 'TCP_LEGACY_TRANSFER_IDLE_NOT_CONFIRMED' }
    $null=Assert-LegacyTransferBoot
    $preflightDirectory=Split-Path -Parent $LegacyIdleDirectory
    $preflight=Get-Content -LiteralPath (Join-Path $preflightDirectory 'preflight.json') -Raw | ConvertFrom-Json
    $selected=@($preflight.products | Where-Object contract -eq 'v4.0.0')
    if ($preflight.status -ne 'FILES_AND_PROFILES_PREPARED' -or $preflight.switch_policy -ne 'reboot_between_versions' -or $selected.Count -ne 1 -or
        $selected[0].identity.bundle_sha256 -ne $identity.bundle_sha256 -or $identity.declared_cli_variant -ne 'testlab-unbuffered-v1' -or
        $selected[0].identity.declared_source_commit -ne $identity.declared_source_commit -or
        (Get-FileHash (Join-Path (Split-Path -Parent $EnvPath) 'build-receipt.json')).Hash -ine $selected[0].build_receipt_sha256) { throw 'TCP_LEGACY_TRANSFER_KIT_OR_PREFLIGHT_CHANGED' }
    $legacyProfile=Join-Path $preflightDirectory 'v4.0.0-transfer.pbprofile'
    $entry=@($preflight.profile_files | Where-Object file_name -eq 'v4.0.0-transfer.pbprofile')
    if ($entry.Count -ne 1 -or (Get-FileHash $legacyProfile).Hash -ine $entry[0].sha256) { throw 'TCP_LEGACY_TRANSFER_PROFILE_CHANGED' }
    $legacyProfileHash=$entry[0].sha256
    $legacyLoaded=Get-Content -LiteralPath (Join-Path $LegacyIdleDirectory 'loaded-drivers-idle.json') -Raw | ConvertFrom-Json
    if (-not $legacyLoaded.query_complete -or $legacyLoaded.selected_driver_loaded) { throw 'TCP_LEGACY_TRANSFER_IDLE_INVENTORY_INCOMPLETE' }
    $observationEnvironment=Import-DotEnv -Path (Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env')
    $observationEnvironment['PB_WINDIVERT_CTL_EXE']=Join-Path $root 'bin/tools/windivert-2.2.2/windivertctl.exe'
    $observationEnvironment['PB_EXPECTED_WINDIVERT_CTL_SHA256']='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765'
    $observationEnvironment['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
    if ($environment['PB_EXPECTED_WINDIVERT_DLL_SHA256'] -ine $observationEnvironment['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']) { throw 'TCP_LEGACY_TRANSFER_OBSERVER_FAMILY_CHANGED' }
}
if ($repeatLegacy) {
    $DriverTransferDirectory=(Resolve-Path -LiteralPath $DriverTransferDirectory).Path
    $referenceText=& $PythonPath (Join-Path $root 'src/pb_tcp_transfer_reference.py') --driver-repeat $DriverTransferDirectory
    if ($LASTEXITCODE -ne 0) { throw 'TCP_LEGACY_REPEAT_DRIVER_SOURCE_NOT_CONFIRMED' }
    $driverTransferReference=$referenceText | ConvertFrom-Json
    $selected=$driverTransferReference.legacy_product
    if ($preflightDirectory -ine $driverTransferReference.preflight_directory -or $identity.bundle_sha256 -ne $selected.identity.bundle_sha256 -or
        $identity.declared_source_commit -ne $selected.identity.declared_source_commit -or $legacyProfileHash -ine $driverTransferReference.profiles.'v4.0.0'.sha256 -or
        $legacyLoaded.other_driver_names_sha256 -ne $driverTransferReference.other_driver_names_sha256) { throw 'TCP_LEGACY_REPEAT_KIT_PROFILE_OR_INVENTORY_CHANGED' }
    $toolHashes=@{engine_sha256=$engineSha;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;proxy_helper_sha256=(Get-FileHash $proxyLauncher).Hash;sampler_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash;python_sha256=(Get-FileHash $PythonPath).Hash;proxy_event_loop='_WindowsSelectorEventLoop'}
    foreach ($key in $toolHashes.Keys) { if ($toolHashes[$key] -ine $driverTransferReference.common_tools.$key) { throw ('TCP_LEGACY_REPEAT_TOOL_CHANGED_'+$key) } }
    $null=Assert-LegacyTransferBoot
}
if ($boundDriver) {
    if ($repeatDriver) {
        $DriverSmokeDirectory=(Resolve-Path -LiteralPath $DriverSmokeDirectory).Path
        $referenceText=& $PythonPath (Join-Path $root 'src/pb_tcp_transfer_reference.py') --driver-smoke $DriverSmokeDirectory
    } else {
        $LegacyTransferDirectory=(Resolve-Path -LiteralPath $LegacyTransferDirectory).Path
        $referenceText=& $PythonPath (Join-Path $root 'src/pb_tcp_transfer_reference.py') --source $LegacyTransferDirectory
    }
    if ($LASTEXITCODE -ne 0) { throw 'TCP_DRIVER_TRANSFER_SOURCE_NOT_CONFIRMED' }
    $decodedReference=$referenceText | ConvertFrom-Json
    if ($repeatDriver) { $transferReference=$decodedReference.legacy_reference;$driverSmokeReference=$decodedReference.driver_smoke_reference;$LegacyTransferDirectory=$transferReference.source_directory }
    else { $transferReference=$decodedReference }
    $selected=$transferReference.driver_product
    if ($identity.bundle_sha256 -ne $selected.identity.bundle_sha256 -or $identity.declared_source_commit -ne $selected.identity.declared_source_commit -or
        $identity.declared_cli_variant -ne 'testlab-unbuffered-v1' -or
        (Get-FileHash (Join-Path (Split-Path -Parent $EnvPath) 'build-receipt.json')).Hash -ine $selected.build_receipt_sha256) { throw 'TCP_DRIVER_TRANSFER_SELECTED_KIT_CHANGED' }
    $toolHashes=@{engine_sha256=$engineSha;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;proxy_helper_sha256=(Get-FileHash $proxyLauncher).Hash;sampler_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash;python_sha256=(Get-FileHash $PythonPath).Hash;proxy_event_loop='_WindowsSelectorEventLoop'}
    foreach ($key in $toolHashes.Keys) { if ($toolHashes[$key] -ine $transferReference.common_tools.$key) { throw ('TCP_DRIVER_TRANSFER_TOOL_CHANGED_'+$key) } }
    $driverProfile=$transferReference.profiles.driver.path;$driverProfileHash=$transferReference.profiles.driver.sha256
    $observationEnvironment['PB_WINDIVERT_CTL_EXE']=Join-Path $root 'bin/tools/windivert-2.2.2/windivertctl.exe'
    $observationEnvironment['PB_EXPECTED_WINDIVERT_CTL_SHA256']='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765'
    $observationEnvironment['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
    $null=Assert-BoundDriverBoot
}
if ($Resume -and -not $EvidenceDirectory) { throw 'TCP_RESUME_REQUIRES_EVIDENCE_DIRECTORY' }
if (-not $EvidenceDirectory) { $EvidenceDirectory=Join-Path $root ('artifacts/local-route/tcp-socks5-'+$(if ($TransferOnly) {$(if ($ProductContract -eq 'v4.0.0') {'4.0.0'} else {'driver'})+'-data-'} elseif ($shutdownDiagnostic) {'v4.0.0-'+$shutdownMode+'-diagnostic-'} elseif ($ProductContract -eq 'v4.0.0') {'v4.0.0-'} else {''})+$Profile.ToLowerInvariant()+'-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)) }
if ($Resume) {
    if (-not (Test-Path -LiteralPath (Join-Path $EvidenceDirectory 'comparison-manifest.json') -PathType Leaf)) { throw 'TCP_RESUME_MANIFEST_MISSING' }
} else {
    if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'TCP_REQUIRES_NEW_DIRECTORY' }
    $null=New-Item -ItemType Directory -Path $EvidenceDirectory
}
$EvidenceDirectory=(Resolve-Path -LiteralPath $EvidenceDirectory).Path
$pairs=$(if ($Profile -eq 'SMOKE') {1} else {3})
$bytes=$(if ($Profile -eq 'SMOKE') {16777216} else {536870912})
if ($ProductContract -eq 'v4.0.0' -or $TransferOnly) { $bytes=67108864 } # Same data-only SMOKE size for both versions; readiness only.
$rate=$(if ($Profile -eq 'SMOKE') {8388608} else {67108864})
if ($repeatDriver -or $repeatLegacy) { $bytes=2147483648 } # Same bounded transfer in both repeated version stages.
if ($presetMode) { $bytes=$workload.transfer_bytes;$rate=$workload.rate_limit_bytes_per_s }
$nativeTimeoutMs=$(if ($presetMode) {$workload.native_timeout_ms} else {120000})
$manifest=[ordered]@{schema_version=1;status='RUNNING';profile=$Profile;started_at_utc=[DateTime]::UtcNow.ToString('o');pair_count=$pairs;transfer_bytes=$bytes;rate_limit_bytes_per_s=$rate;connections=1;buffer_bytes=65536;verify='data';directions=@('push','pull');runs=@();error='';version_switch_ready=$false}
if ($ProductContract -eq 'v4.0.0') { $manifest['product_contract']=$ProductContract;$manifest['readiness_only']=$true;$manifest['legacy_transfer_stage']=$legacyStage;$manifest['legacy_idle_directory']=$LegacyIdleDirectory }
if ($shutdownDiagnostic) { $manifest['diagnostic_only']=$true;$manifest['shutdown_mode']=$shutdownMode;$manifest['console_verbosity']=$consoleVerbosity;$manifest['directions']=@('push');$manifest['readiness_only']=$false }
if ($DiagnosticHalfCloseFixture) { $manifest['tcp_fixture_revision']='halfclose_diagnostic_v1' }
if ($DiagnosticCloseMetadata) { $manifest['close_metadata_capture']='passive_control_headers_v1' }
if ($TransferOnly) { $manifest['transfer_only']=$true;$manifest['shutdown_mode']='rude';$manifest['tcp_shutdown_policy']='data-transfer-only-v1';$manifest['normal_tcp_close_verified']=$false;$manifest['readiness_only']=$true;$manifest['product_label']=$(if ($ProductContract -eq 'v4.0.0') {'4.0.0'} else {'driver'}) }
if ($boundDriver) { $manifest['product_contract']='driver';$manifest['legacy_transfer_directory']=$LegacyTransferDirectory;$manifest['version_transfer_stage']=$transferStage;$transferReference | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'legacy-transfer-reference.json') -Encoding UTF8 }
if ($repeatDriver) { $manifest['driver_smoke_directory']=$DriverSmokeDirectory;$manifest['readiness_only']=$false;$driverSmokeReference | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'driver-smoke-reference.json') -Encoding UTF8 }
if ($repeatLegacy) { $manifest['driver_transfer_directory']=$DriverTransferDirectory;$manifest['version_transfer_stage']='data-transfer-repeat-legacy-v1';$manifest['readiness_only']=$false;$driverTransferReference | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'driver-transfer-reference.json') -Encoding UTF8 }
$helperStopTimeoutMs=15000
if ($presetMode) { $manifest['workload_preset']=$workload;$manifest['readiness_only']=$false }
$retryOriginalName=''
$retrySuffix=''
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
function Wait-Event($worker,[string]$path) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt 5000) {
        if ($worker.process.HasExited) { throw "TCP_HELPER_EARLY_EXIT_$($worker.name)" }
        if (Test-Path $path) { if (@(Get-Content $path | Where-Object {$_} | ConvertFrom-Json | Where-Object event -eq 'LISTENING').Count -eq 1) { return } }
        Start-Sleep -Milliseconds 50
    }
    throw "TCP_HELPER_NOT_READY_$($worker.name)"
}
function Assert-Off {
    $state=Get-InterceptionStateSnapshot -Environment $observationEnvironment -AllowProductRuntime
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    $processes=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe'))
    if ($ProductContract -eq 'v4.0.0') {
        $state | Add-Member -NotePropertyName boot_identity -NotePropertyValue (Assert-LegacyTransferBoot)
        if (-not $state.windivert.files_verified -or -not $state.windivert.capture_complete -or $state.windivert.status -ne 'NO_HANDLES_OBSERVED' -or
            $state.windivert.observed_handle_count -ne 0 -or $loaded.selected_driver_loaded -or
            @($loaded.known_interception_drivers | Where-Object { $_ -ine 'WinDivert64.sys' }).Count -or
            $loaded.other_driver_names_sha256 -ne $legacyLoaded.other_driver_names_sha256) { throw 'TCP_LEGACY_TRANSFER_IDLE_INTERCEPTION_NOT_CONFIRMED' }
    } elseif (-not $loaded.known_interception_driver_names_absent) { throw 'TCP_REQUIRES_CONFIRMED_PRODUCT_OFF' }
    if ($boundDriver) {
        $state | Add-Member -NotePropertyName boot_identity -NotePropertyValue (Assert-BoundDriverBoot)
        if (-not $state.windivert.files_verified -or -not $state.windivert.capture_complete -or $state.windivert.status -ne 'NO_HANDLES_OBSERVED' -or
            $state.windivert.observed_handle_count -ne 0 -or @($state.windivert.handles).Count -or
            $loaded.other_driver_names_sha256 -ne $transferReference.other_driver_names_sha256) { throw 'TCP_DRIVER_TRANSFER_IDLE_OR_OTHER_DRIVERS_CHANGED' }
    }
    if (-not $state.current_driver_preparation_allowed -or -not $state.wfp_detachment_observed -or $state.wfp.service_state -ne 'Stopped' -or -not $loaded.query_complete -or $processes.Count) { throw 'TCP_REQUIRES_CONFIRMED_PRODUCT_OFF' }
    return [pscustomobject]@{state=$state;loaded=$loaded}
}
function Invoke-TcpRun([string]$mode,[string]$direction,[string]$directory) {
    # GetNewClosure copies function locals, not the enclosing script's variables.
    # Materialize every script input used by the callback before it enters the
    # dynamic module (also when the controller is called by another script).
    foreach ($callbackInput in @('client','ProductContract','observationEnvironment','legacyLoaded',
        'boundDriver','transferReference','DiagnosticCloseMetadata','PythonPath','closeCaptureHelper',
        'closeCaptureDll','shutdownMode','shutdownDiagnostic','TransferOnly','consoleVerbosity','nativeTimeoutMs')) {
        Set-Variable -Name $callbackInput -Value (Get-Variable -Name $callbackInput -Scope Script -ValueOnly) -Scope Local
    }
    $null=New-Item -ItemType Directory -Path $directory
    $workers=[Collections.Generic.List[object]]::new()
    $receipt=[ordered]@{status='RUNNING';mode=$mode;direction=$direction;traffic_generated=$false;workers_stopped=$false;driver_stop_observed=$false;receiver_identity_verified=$false;version_switch_ready=$false;error=''}
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
            $context=[ordered]@{product_contract=$ProductContract;legacy_idle_directory=$LegacyIdleDirectory;boot_identity=$before.state.boot_identity;route_profile_sha256=$legacyProfileHash;legacy_transfer_stage=$legacyStage;readiness_only=(-not $shutdownDiagnostic);reboot_required_before_other_version=$true;version_switch_ready=$false}
            if ($shutdownDiagnostic) { $context['diagnostic_only']=$true;$context['shutdown_mode']=$shutdownMode }
            if ($DiagnosticHalfCloseFixture) { $context['tcp_fixture_revision']='halfclose_diagnostic_v1' }
            if ($DiagnosticCloseMetadata) { $context['close_metadata_capture']='passive_control_headers_v1' }
            if ($TransferOnly) { $context['transfer_only']=$true;$context['tcp_shutdown_policy']='data-transfer-only-v1' }
            if ($repeatLegacy) { $context['driver_transfer_directory']=$DriverTransferDirectory;$context['driver_boot_identity']=$driverTransferReference.driver_boot_identity;$context['version_transfer_stage']='data-transfer-repeat-legacy-v1';$context['readiness_only']=$false;$context['reboot_between_versions_observed']=$true }
            Write-Json $context (Join-Path $directory 'version-context.json')
        }
        if ($boundDriver) {
            $context=[ordered]@{product_contract='driver';legacy_transfer_directory=$LegacyTransferDirectory;legacy_boot_identity=$transferReference.legacy_boot_identity;boot_identity=$before.state.boot_identity;route_profile_sha256=$driverProfileHash;version_transfer_stage=$transferStage;reboot_between_versions_observed=$true;readiness_only=(-not $repeatDriver);version_switch_ready=$false}
            if ($repeatDriver) { $context['driver_smoke_directory']=$DriverSmokeDirectory }
            Write-Json $context (Join-Path $directory 'version-context.json')
        }
        foreach ($port in @(54122,54123)) { if (@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count) { throw 'TCP_PORT_IN_USE' } }
        $common=@('-protocol:tcp',('-pattern:'+$direction),('-transfer:'+$bytes),('-ratelimit:'+$rate),'-verify:data','-port:54122','-buffer:65536',('-consoleverbosity:'+$consoleVerbosity),'-statusupdate:250')
        $server=Start-Worker 'receiver' $receiver (@('-listen:127.0.0.1','-serverexitlimit:1',('-connectionfilename:'+(Join-Path $directory 'receiver.csv')),('-statusfilename:'+(Join-Path $directory 'receiver-status.csv')))+$common) $workers
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while ($timer.ElapsedMilliseconds -lt 5000) {
            if ($server.process.HasExited) { throw 'TCP_RECEIVER_EARLY_EXIT' }
            if (@(Get-NetTCPConnection -LocalPort 54122 -State Listen -OwningProcess $server.process.Id -ErrorAction SilentlyContinue).Count -eq 1) { $receipt.receiver_identity_verified=$true; break }
            Start-Sleep -Milliseconds 50
        }
        if (-not $receipt.receiver_identity_verified) { throw 'TCP_RECEIVER_NOT_READY' }
        $proxyLog=Join-Path $directory 'proxy.jsonl'
        $proxy=Start-Worker 'proxy' $PythonPath @('-u',$proxyLauncher,'--wheel',$wheel,'--jsonl-log',$proxyLog,'--port','54123','--receiver-port','54122','--max-duration-seconds',$(if ($presetMode) {'720'} else {'180'})) $workers
        Wait-Event $proxy $proxyLog
        $samplerLog=Join-Path $directory 'pc-samples.jsonl'
        $samplerConfig=Join-Path $directory 'sampler-config.json'
        Write-Json @([ordered]@{role='receiver';pid=$server.process.Id;path=$receiver},[ordered]@{role='proxy';pid=$proxy.process.Id;path=$PythonPath}) $samplerConfig
        $sampler=Start-Worker 'sampler' $PythonPath @('-u',(Join-Path $root 'src/pb_pc_sampler.py'),'--packages',$packages,'--config',$samplerConfig,'--jsonl-log',$samplerLog,'--max-duration-seconds',$(if ($presetMode) {'720'} else {'180'})) $workers
        Wait-Event $sampler $samplerLog
        $benchmarkConfig=[ordered]@{transfer_bytes=$bytes;rate_limit_bytes_per_s=$rate;direction=$direction;connections=1;verify='data';buffer_bytes=65536;receiver_port=54122;proxy_port=54123;proxy_event_loop='_WindowsSelectorEventLoop';engine_sha256=$engineSha;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;proxy_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash;sampler_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash;python_sha256=(Get-FileHash $PythonPath).Hash;receiver_pid=$server.process.Id;proxy_pid=$proxy.process.Id;sampler_pid=$sampler.process.Id}
        if ($ProductContract -eq 'v4.0.0') { $benchmarkConfig['product_contract']=$ProductContract;$benchmarkConfig['route_profile_sha256']=$legacyProfileHash;$benchmarkConfig['legacy_transfer_stage']=$legacyStage;$benchmarkConfig['live_socket_observation_policy']='owned-socket-snapshot-transfer-smoke-v1' }
        if ($shutdownDiagnostic) { $benchmarkConfig['diagnostic_only']=$true;$benchmarkConfig['shutdown_mode']=$shutdownMode }
        if ($DiagnosticGracefulShutdown) { $benchmarkConfig['console_verbosity']=$consoleVerbosity }
        if ($DiagnosticHalfCloseFixture) { $benchmarkConfig['tcp_fixture_revision']='halfclose_diagnostic_v1';$benchmarkConfig['proxy_launcher_sha256']=(Get-FileHash $proxyLauncher).Hash }
        if ($DiagnosticCloseMetadata) { $benchmarkConfig['close_metadata_capture']='passive_control_headers_v1';$benchmarkConfig['close_capture_helper_sha256']=(Get-FileHash $closeCaptureHelper).Hash;$benchmarkConfig['close_capture_dll_sha256']=(Get-FileHash $closeCaptureDll).Hash }
        if ($TransferOnly) { $benchmarkConfig['transfer_only']=$true;$benchmarkConfig['shutdown_mode']='rude';$benchmarkConfig['tcp_shutdown_policy']='data-transfer-only-v1';$benchmarkConfig['console_verbosity']=1;$benchmarkConfig['product_label']=$(if ($ProductContract -eq 'v4.0.0') {'4.0.0'} else {'driver'}) }
        if ($presetMode) { $benchmarkConfig['workload_preset']=$workload }
        if ($boundDriver) { $benchmarkConfig['product_contract']='driver';$benchmarkConfig['legacy_transfer_directory']=$LegacyTransferDirectory;$benchmarkConfig['version_transfer_stage']=$transferStage;$benchmarkConfig['route_profile_sha256']=$driverProfileHash;$benchmarkConfig['live_socket_observation_policy']='owned-socket-snapshot-transfer-smoke-v1' }
        if ($repeatDriver) { $benchmarkConfig['driver_smoke_directory']=$DriverSmokeDirectory;$benchmarkConfig['transfer_profile']='STANDARD' }
        if ($repeatLegacy) { $benchmarkConfig['driver_transfer_directory']=$DriverTransferDirectory;$benchmarkConfig['transfer_profile']='STANDARD';$benchmarkConfig['version_transfer_stage']='data-transfer-repeat-legacy-v1' }
        Write-Json $benchmarkConfig (Join-Path $directory 'benchmark-config.json')
        # GetNewClosure creates a module that cannot reliably resolve functions
        # from this script when a parent script invokes the controller.
        $qpcCommand=Get-Command Qpc-Ms -CommandType Function
        $writeJsonCommand=Get-Command Write-Json -CommandType Function
        $loadedObservationCommand=Get-Command Get-LoadedInterceptionDriverObservation -CommandType Function
        $interceptionSnapshotCommand=Get-Command Get-InterceptionStateSnapshot -CommandType Function
        $startWorkerCommand=Get-Command Start-Worker -CommandType Function
        $waitEventCommand=Get-Command Wait-Event -CommandType Function
        $workload={
            param($cli)
            if ($mode -eq 'PROXY') {
                $active=& $loadedObservationCommand -AllowProductRuntime
                & $writeJsonCommand $active (Join-Path $directory 'loaded-drivers-active.json')
                if ($ProductContract -eq 'v4.0.0') {
                    $activeState=& $interceptionSnapshotCommand -Environment $observationEnvironment -AllowProductRuntime
                    & $writeJsonCommand $activeState (Join-Path $directory 'interception-active.json')
                    $handles=@($activeState.windivert.handles)
                    if (-not $active.query_complete -or $active.selected_driver_loaded -or @($active.known_interception_drivers).Count -ne 1 -or $active.known_interception_drivers[0] -ine 'WinDivert64.sys' -or
                        $active.other_driver_names_sha256 -ne $legacyLoaded.other_driver_names_sha256 -or -not $activeState.wfp_detachment_observed -or -not $activeState.windivert.files_verified -or
                        -not $activeState.windivert.capture_complete -or $handles.Count -ne 1 -or $handles[0].pid -ne $cli.pid -or $handles[0].layer -ne 'NETWORK' -or $handles[0].flags -ne '0') { throw 'TCP_LEGACY_TRANSFER_OWNED_ACTIVE_HANDLE_NOT_CONFIRMED' }
                } elseif (-not $active.query_complete -or -not $active.selected_driver_loaded -or $active.known_interception_drivers.Count -ne 1) { throw 'TCP_SELECTED_ACTIVE_DRIVER_NOT_CONFIRMED' }
                if ($boundDriver) {
                    $activeState=& $interceptionSnapshotCommand -Environment $observationEnvironment -AllowProductRuntime
                    & $writeJsonCommand $activeState (Join-Path $directory 'interception-active.json')
                    if ($active.other_driver_names_sha256 -ne $transferReference.other_driver_names_sha256 -or
                        $activeState.wfp.status -ne 'SERVICE_FILE_VERIFIED' -or $activeState.wfp.service_state -ne 'Running' -or
                        -not $activeState.windivert.files_verified -or -not $activeState.windivert.capture_complete -or
                        $activeState.windivert.status -ne 'NO_HANDLES_OBSERVED' -or $activeState.windivert.observed_handle_count -ne 0 -or @($activeState.windivert.handles).Count) { throw 'TCP_DRIVER_TRANSFER_ACTIVE_INTERCEPTION_NOT_CONFIRMED' }
                }
                $sampler.process.StandardInput.WriteLine(([ordered]@{role='proxybridge_cli';pid=$cli.pid;path=$cli.actual_path} | ConvertTo-Json -Compress));$sampler.process.StandardInput.Flush()
            }
            if ($DiagnosticCloseMetadata) {
                # Open passive handles only after the unchanged single product-handle gate.
                if ($handles[0].priority -ne 123) { throw 'TCP_CLOSE_METADATA_PRODUCT_PRIORITY_CHANGED' }
                $captureLog=Join-Path $directory 'close-metadata.jsonl'
                $capture=& $startWorkerCommand 'close-capture' $PythonPath @('-u',$closeCaptureHelper,'--dll',$closeCaptureDll,'--jsonl-log',$captureLog,'--max-duration-seconds','150') $workers
                & $waitEventCommand $capture $captureLog
                $benchmarkConfig['close_capture_pid']=$capture.process.Id
                & $writeJsonCommand $benchmarkConfig (Join-Path $directory 'benchmark-config.json')
                $captureState=& $interceptionSnapshotCommand -Environment $observationEnvironment -AllowProductRuntime
                & $writeJsonCommand $captureState (Join-Path $directory 'interception-close-capture.json')
                $allHandles=@($captureState.windivert.handles)
                $ownCapture=@($allHandles | Where-Object pid -eq $capture.process.Id)
                $ownProduct=@($allHandles | Where-Object pid -eq $cli.pid)
                if (-not $captureState.windivert.files_verified -or -not $captureState.windivert.capture_complete -or -not $captureState.wfp_detachment_observed -or
                    $allHandles.Count -ne 3 -or $ownCapture.Count -ne 2 -or $ownProduct.Count -ne 1 -or
                    $ownProduct[0].flags -ne '0' -or $ownProduct[0].layer -ne 'NETWORK' -or $ownProduct[0].priority -ne 123) { throw 'TCP_CLOSE_METADATA_OWNED_HANDLES_NOT_CONFIRMED' }
                foreach ($handle in $ownCapture) {
                    $flags=@($handle.flags -split '\|' | Sort-Object)
                    if ($handle.layer -ne 'NETWORK' -or $handle.priority -notin @(124,122) -or
                        ($flags -join '|') -ne 'NO_INSTALL|RECV_ONLY|SNIFF') { throw 'TCP_CLOSE_METADATA_PASSIVE_FLAGS_NOT_CONFIRMED' }
                }
                if (@($ownCapture | Where-Object priority -eq 124).Count -ne 1 -or @($ownCapture | Where-Object priority -eq 122).Count -ne 1) { throw 'TCP_CLOSE_METADATA_PRIORITIES_NOT_CONFIRMED' }
            }
            Start-Sleep -Milliseconds 1000
            $plan=[pscustomobject]@{executable=$client;arguments=(@('-target:127.0.0.1','-connections:1','-iterations:1',('-shutdown:'+$shutdownMode),('-connectionfilename:'+(Join-Path $directory 'client.csv')),('-statusfilename:'+(Join-Path $directory 'client-status.csv')))+$common);timeout_ms=$nativeTimeoutMs}
            if ([string]::IsNullOrWhiteSpace([string]$plan.executable)) { throw 'TCP_CALLBACK_CLIENT_EXECUTABLE_MISSING' }
            $start=& $qpcCommand
            $native=& $adapter.StartProcess $plan
            try {
                $probe=& $adapter.ProbeActualPath $native 2000 25
                if ($probe.status -ne 'PATH_OBTAINED' -or $native.actual_path -ine $client) { throw 'TCP_CLIENT_IDENTITY_NOT_CONFIRMED' }
                if ($shutdownDiagnostic -or $TransferOnly) {
                    $observed=Get-CimInstance Win32_Process -Filter ('ProcessId='+$native.pid) -OperationTimeoutSec 5 -ErrorAction Stop
                    & $writeJsonCommand ([ordered]@{pid=$native.pid;expected_executable=$client;expected_arguments=@($plan.arguments);observed_executable=$observed.ExecutablePath;observed_command_line=$observed.CommandLine;capture_qpc_ms=(& $qpcCommand)}) (Join-Path $directory 'client-launch.json')
                    $options=[regex]::Matches([string]$observed.CommandLine,'(?i)(?:^|\s)-shutdown:([^\s"]+)')
                    $verbosity=[regex]::Matches([string]$observed.CommandLine,'(?i)(?:^|\s)-consoleverbosity:([^\s"]+)')
                    if ($observed.ExecutablePath -ine $client -or $options.Count -ne 1 -or $options[0].Groups[1].Value -ine $shutdownMode -or
                        $verbosity.Count -ne 1 -or $verbosity[0].Groups[1].Value -ne [string]$consoleVerbosity) { throw 'TCP_SHUTDOWN_DIAGNOSTIC_LIVE_OPTIONS_NOT_CONFIRMED' }
                }
                $sampler.process.StandardInput.WriteLine(([ordered]@{role='generator';pid=$native.pid;path=$native.actual_path} | ConvertTo-Json -Compress));$sampler.process.StandardInput.Flush()
                $receipt.traffic_generated=$true
                if ($ProductContract -eq 'v4.0.0' -or $boundDriver) {
                    $owner=$(if ($mode -eq 'PROXY') { $cli.pid } else { $native.pid })
                    $target=$(if ($mode -eq 'PROXY') { 54123 } else { 54122 })
                    $captureStart=& $qpcCommand
                    $query=[Diagnostics.Stopwatch]::StartNew();$connections=@()
                    do {
                        $connections=@(Get-NetTCPConnection -State Established -OwningProcess $owner -RemoteAddress '127.0.0.1' -RemotePort $target -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,OwningProcess)
                        if ($connections.Count -or -not $native.session.IsRunning) { break }
                        Start-Sleep -Milliseconds 25
                    } while ($query.ElapsedMilliseconds -lt 5000)
                    if (-not $connections.Count) { throw 'TCP_LEGACY_TRANSFER_OWNED_SOCKET_NOT_OBSERVED' }
                    & $writeJsonCommand $connections (Join-Path $directory $(if ($mode -eq 'PROXY') {'product-proxy-connections.json'} else {'generator-direct-connections.json'}))
                    & $writeJsonCommand ([ordered]@{start_qpc_ms=$captureStart;capture_completed_qpc_ms=(& $qpcCommand);query_elapsed_ms=$query.ElapsedMilliseconds;owner_pid=$owner;target_port=$target}) (Join-Path $directory 'live-socket-observation.json')
                }
                if (-not $native.session.WaitForExit($nativeTimeoutMs)) { $native.timed_out=$true; & $adapter.StopProcess $native; throw 'TCP_CLIENT_TIMEOUT' }
                $end=& $qpcCommand
                $result=& $adapter.GetProcessResult $native
                & $writeJsonCommand $result (Join-Path $directory 'client-process.json')
                & $writeJsonCommand ([ordered]@{start_qpc_ms=$start;end_qpc_ms=$end;client_pid=$native.pid}) (Join-Path $directory 'measurement-window.json')
                if ($result.exit_code -ne 0 -or $result.timed_out -or -not $result.output_capture_complete) { throw 'TCP_CLIENT_FAILED' }
                if (-not $server.process.WaitForExit(10000) -or $server.process.ExitCode -ne 0) { throw 'TCP_RECEIVER_FAILED' }
                return $result
            } finally {
                if ($native.session.IsRunning) { & $adapter.StopProcess $native }
                & $adapter.DisposeProcess $native
            }
        }.GetNewClosure()
        if ($mode -eq 'PROXY') {
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
            if ($ProductContract -eq 'v4.0.0') { Copy-Item -LiteralPath $legacyProfile -Destination $profilePath; if ((Get-FileHash $profilePath).Hash -ine $legacyProfileHash) { throw 'TCP_LEGACY_TRANSFER_PROFILE_COPY_CHANGED' } }
            elseif ($boundDriver) { Copy-Item -LiteralPath $driverProfile -Destination $profilePath; if ((Get-FileHash $profilePath).Hash -ine $driverProfileHash) { throw 'TCP_DRIVER_TRANSFER_PROFILE_COPY_CHANGED' } }
            else {
            Write-Json ([ordered]@{Version='1.0';LocalhostViaProxy=$true;IsTrafficLoggingEnabled=$true;ProxyConfigs=@([ordered]@{Id=1;Name='Controlled TCP SOCKS5';Type='SOCKS5';Host='127.0.0.1';Port='54123';Username='';Password='';SendDomainToProxy=$false});ProxyRules=@([ordered]@{Name='TCP benchmark';ProcessName='ctsTraffic.exe';TargetHosts='127.0.0.1';TargetPorts='54122';TargetDomains='';Protocol='TCP';Action='PROXY';ProxyConfigId=1;IsEnabled=$true})}) $profilePath
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
                if (-not $worker.process.HasExited -and $worker.name -ne 'receiver') { $worker.process.StandardInput.WriteLine('STOP');$worker.process.StandardInput.Flush() }
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
        if ($DiagnosticCloseMetadata -and (Test-Path -LiteralPath (Join-Path $directory 'close-metadata.jsonl'))) {
            try {
                $events=@(Get-Content -LiteralPath (Join-Path $directory 'close-metadata.jsonl') | Where-Object {$_} | ConvertFrom-Json)
                $ready=@($events | Where-Object event -eq 'LISTENING')
                $stopped=@($events | Where-Object event -eq 'STOPPED')
                $summaries=@($events | Where-Object event -eq 'CAPTURE_SUMMARY')
                if ($ready.Count -ne 1 -or $stopped.Count -ne 1 -or $summaries.Count -ne 2 -or
                    $ready[0].process_id -ne $benchmarkConfig['close_capture_pid'] -or $ready[0].flags -ne 21 -or
                    $ready[0].helper_sha256 -ine $benchmarkConfig['close_capture_helper_sha256'] -or
                    $ready[0].dll_sha256 -ine $benchmarkConfig['close_capture_dll_sha256'] -or
                    $stopped[0].process_id -ne $benchmarkConfig['close_capture_pid'] -or -not $stopped[0].capture_success -or
                    -not $stopped[0].handles_closed -or $stopped[0].reason -ne 'STDIN_STOP' -or $stopped[0].packet_injection -or
                    @($summaries | Where-Object { $_.errors.Count -or $_.critical_limit_reached -or $_.file_limit_reached -or $_.received -eq 0 }).Count -or
                    @($summaries | Where-Object side -eq 'before_product').Count -ne 1 -or @($summaries | Where-Object side -eq 'after_product').Count -ne 1) { throw 'TCP_CLOSE_METADATA_CAPTURE_NOT_CONFIRMED' }
            } catch { $clean=$false;$receipt.error+='; close metadata: '+$_.Exception.Message }
        }
        $receipt.workers_stopped=$clean
        try {
            if ($startedProduct) {
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
        if ($ProductContract -eq 'v4.0.0') {
            try {
                & $PythonPath (Join-Path $root 'src/pb_tcp_close_notice.py') --directory $directory | Out-Null
                if ($LASTEXITCODE -ne 0) { Write-Warning 'Не удалось сформировать пояснение к ошибке TCP / TCP failure notice unavailable.' }
                elseif (Test-Path -LiteralPath (Join-Path $directory 'known-problems.md')) { Write-Host ('Итоги / Results: '+(Join-Path $directory 'known-problems.md')) }
            } catch { Write-Warning ('Пояснение TCP не сохранено / TCP notice not saved: '+$_.Exception.Message) }
        }
        throw $receipt.error
    }
    & $PythonPath (Join-Path $root 'src/pb_tcp_benchmark_report.py') --run-directory $directory
    if ($LASTEXITCODE -ne 0) { throw 'TCP_EVIDENCE_NOT_CONFIRMED' }
}
if ($Resume) {
    $saved=Get-Content -LiteralPath (Join-Path $EvidenceDirectory 'comparison-manifest.json') -Raw | ConvertFrom-Json
    if ($saved.schema_version -ne 1 -or $saved.status -ne 'FAILED' -or $saved.runs.Count -lt 3 -or $saved.runs.Count -ge $pairs*4 -or $saved.runs.Count % 2 -ne 1) { throw 'TCP_RESUME_REQUIRES_FAILED_FIRST_RUN_OF_PAIR' }
    foreach ($key in @('profile','pair_count','transfer_bytes','rate_limit_bytes_per_s','connections','buffer_bytes','verify')) {
        if ($saved.$key -ne $manifest[$key]) { throw "TCP_RESUME_PARAMETER_MISMATCH_$key" }
    }
    if (($saved.directions -join ',') -ne 'push,pull') { throw 'TCP_RESUME_DIRECTIONS_MISMATCH' }
    $expected=@()
    foreach ($direction in @('push','pull')) {
        for ($pair=1;$pair -le $pairs;$pair++) {
            $order=$(if ($pair % 2) { @('OFF','PROXY') } else { @('PROXY','OFF') })
            foreach ($mode in $order) { $expected+=[pscustomobject]@{direction=$direction;pair=$pair;mode=$mode;name=('{0}-pair-{1:d2}-{2}' -f $direction,$pair,$mode.ToLowerInvariant())} }
        }
    }
    $staticChecks=@{engine_sha256=$engineSha;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;proxy_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash;sampler_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash;python_sha256=(Get-FileHash $PythonPath).Hash}
    $inventory=$null
    for ($index=0;$index -lt $saved.runs.Count;$index++) {
        $entry=$saved.runs[$index];$want=$expected[$index]
        if ($entry.direction -ne $want.direction -or $entry.pair -ne $want.pair -or $entry.mode -ne $want.mode -or $entry.directory -ne $want.name) { throw 'TCP_RESUME_RUN_PREFIX_INVALID' }
        $path=Join-Path $EvidenceDirectory $entry.directory
        $config=Get-Content (Join-Path $path 'benchmark-config.json') -Raw | ConvertFrom-Json
        $build=Get-Content (Join-Path $path 'product-build.json') -Raw | ConvertFrom-Json
        $after=Get-Content (Join-Path $path 'loaded-drivers-after.json') -Raw | ConvertFrom-Json
        if ($config.direction -ne $want.direction -or $config.transfer_bytes -ne $bytes -or $config.rate_limit_bytes_per_s -ne $rate -or $config.connections -ne 1 -or $config.verify -ne 'data' -or $config.buffer_bytes -ne 65536 -or $config.receiver_port -ne 54122 -or $config.proxy_port -ne 54123 -or $build.bundle_sha256 -ne $identity.bundle_sha256) { throw 'TCP_RESUME_TRAFFIC_OR_PRODUCT_CHANGED' }
        foreach ($key in $staticChecks.Keys) { if ($config.$key -ne $staticChecks[$key]) { throw "TCP_RESUME_TOOL_CHANGED_$key" } }
        if (-not $after.query_complete -or -not $after.known_interception_driver_names_absent) { throw 'TCP_RESUME_STOPPED_DRIVER_NOT_CONFIRMED' }
        if ($null -eq $inventory) { $inventory=$after.other_driver_names_sha256 }
        if ($after.other_driver_names_sha256 -ne $inventory) { throw 'TCP_RESUME_OTHER_DRIVERS_CHANGED' }
        $receipt=Get-Content (Join-Path $path 'run-receipt.json') -Raw | ConvertFrom-Json
        if ($index -lt $saved.runs.Count-1) {
            $report=Get-Content (Join-Path $path 'tcp-benchmark-report.json') -Raw | ConvertFrom-Json
            if ($entry.status -ne 'COMPLETED' -or $receipt.status -ne 'COMPLETED' -or -not $receipt.workers_stopped -or -not $receipt.driver_stop_observed -or $report.status -ne 'MEASURED' -or $report.errors.Count -ne 0 -or $report.mode -ne $want.mode -or $report.direction -ne $want.direction -or $report.verified_payload_bytes -ne $bytes) { throw 'TCP_RESUME_COMPLETED_RUN_NOT_CONFIRMED' }
        } else {
            if ($entry.status -eq 'COMPLETED' -or $receipt.status -ne 'FAILED' -or -not $receipt.traffic_generated -or $receipt.workers_stopped -or -not $receipt.driver_stop_observed -or -not $receipt.receiver_identity_verified) { throw 'TCP_RESUME_REQUIRES_PROXY_CLEANUP_FAILURE' }
            if ($receipt.error -or $saved.error) { throw 'TCP_RESUME_ONLY_SUPPORTS_OBSERVED_LEGACY_CLEANUP_FAILURE' }
            foreach ($name in @('client','receiver','sampler')) {
                $process=Get-Content (Join-Path $path ($name+'-process.json')) -Raw | ConvertFrom-Json
                if ($process.exit_code -ne 0 -or -not $process.output_capture_complete) { throw 'TCP_RESUME_NON_PROXY_PROCESS_FAILED' }
                if ($process.PSObject.Properties['forced_stop'] -and $process.forced_stop) { throw 'TCP_RESUME_NON_PROXY_PROCESS_FORCED' }
                if ($process.PSObject.Properties['timed_out'] -and $process.timed_out) { throw 'TCP_RESUME_CLIENT_TIMED_OUT' }
            }
            $process=Get-Content (Join-Path $path 'proxy-process.json') -Raw | ConvertFrom-Json
            if (-not $process.forced_stop -or $process.exit_code -eq 0 -or -not $process.output_capture_complete) { throw 'TCP_RESUME_PROXY_FAILURE_NOT_OBSERVED' }
            $c=@(Import-Csv -LiteralPath (Join-Path $path 'client.csv'));$s=@(Import-Csv -LiteralPath (Join-Path $path 'receiver.csv'))
            $clientField=$(if ($want.direction -eq 'push') {'SendBytes'} else {'RecvBytes'});$serverField=$(if ($want.direction -eq 'push') {'RecvBytes'} else {'SendBytes'})
            if ($c.Count -ne 1 -or $s.Count -ne 1 -or $c[0].Result -ne 'Succeeded' -or $s[0].Result -ne 'Succeeded' -or $c[0].ConnectionId -ne $s[0].ConnectionId -or [long]$c[0].$clientField -ne $bytes -or [long]$s[0].$serverField -ne $bytes) { throw 'TCP_RESUME_FAILED_TRANSFER_NOT_VERIFIED' }
            if ($want.mode -ne 'PROXY') { throw 'TCP_RESUME_REQUIRES_ROUTED_CLEANUP_FAILURE' }
            $cli=Get-Content (Join-Path $path 'cli-lifecycle.json') -Raw | ConvertFrom-Json
            if (-not $cli.ready -or -not $cli.graceful_stop -or $cli.forced_stop -or -not $cli.post_stop_verified -or $cli.error) { throw 'TCP_RESUME_FAILED_CLI_NOT_CLEAN' }
        }
    }
    $now=Assert-Off
    if ($now.loaded.other_driver_names_sha256 -ne $inventory) { throw 'TCP_RESUME_CURRENT_OTHER_DRIVERS_CHANGED' }
    $retryOriginalName=$expected[$saved.runs.Count-1].name
    $retrySuffix='-retry-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)
    Copy-Item -LiteralPath (Join-Path $EvidenceDirectory 'comparison-manifest.json') -Destination (Join-Path $EvidenceDirectory ('comparison-manifest-before'+$retrySuffix+'.json'))
    $manifest=[ordered]@{}
    foreach ($property in $saved.PSObject.Properties) { $manifest[$property.Name]=$property.Value }
    $last=$saved.runs[-1]
    $manifest['failed_attempts']=@([ordered]@{directory=$last.directory;mode=$last.mode;pair=$last.pair;direction=$last.direction;original_error=$saved.error;observed_failure='PROXY_FORCED_STOP_AFTER_VERIFIED_TRANSFER';traffic_generated=$true;excluded_from_comparison=$true})
    $manifest.runs=@($saved.runs[0..($saved.runs.Count-2)])
    $manifest.status='RUNNING';$manifest.error='';$manifest.Remove('completed_at_utc')
    $manifest['resumed_at_utc']=[DateTime]::UtcNow.ToString('o')
    $manifest['retained_completed_runs']=$manifest.runs.Count
    $manifest['helper_stop_timeout_change']=[ordered]@{previous_ms=5000;current_ms=$helperStopTimeoutMs;scope='After measurement only; traffic/helper bytes unchanged'}
    Write-Host ('Возобновление / Resume: '+$manifest.runs.Count+' completed runs retained; failed transfer remains excluded; '+($pairs*4-$manifest.runs.Count)+' runs remaining.')
}
if ($shutdownDiagnostic) { Write-Host ('Диагностика 4.0.0 / Diagnostic: one PROXY upload; ctsTraffic -shutdown:'+$shutdownMode+'; consoleverbosity '+$consoleVerbosity+'; 64 MiB @ 8 MiB/s; verify:data. Около 1–2 минут / Approximately 1–2 minutes. Не является сравнением / Not a comparison.') }
else { Write-Host ('TCP SOCKS5 vs напрямую / direct: '+$Profile+'; push + pull; '+$pairs+' pairs/direction; '+$bytes+' bytes/connection; send rate cap '+$rate+' bytes/s; verify:data.') }
Write-Host 'Контролируемый получатель / Controlled receiver; one connection/run. Ограниченный темп, не maximum throughput; RTT/ping этим профилем не измеряются / This profile does not measure RTT/ping.'
Write-Host ('Результаты / Results: '+$EvidenceDirectory)
if ($DiagnosticGracefulShutdown) { Write-Host 'Подробные журналы клиента/получателя сохраняются в client-process.json/receiver-process.json. Повтор ошибки возможен и нужен для диагностики; это не повод продолжать failed run / Debug output saved; a reproduced failure remains failed.' }
if ($DiagnosticHalfCloseFixture) { Write-Host 'Отдельный SOCKS5-стенд: исправлена только передача EOF; копирование данных прежнее. ProxyBridge/Core/driver исходные. Не смешивать с прежними измерениями / Isolated half-close fixture; product unchanged; do not pool timings with legacy fixture.' }
if ($DiagnosticCloseMetadata) { Write-Host 'Пассивная запись TCP-заголовков до/после перенаправления: SYN/FIN/RST и хвост ACK, без сохранения содержимого пакетов. До 3 MiB метаданных, без ETL; диагностический темп / Passive control headers; ACK tail only; no payload files or benchmark comparison.' }
if ($TransferOnly) { Write-Host ($manifest.product_label+': передача данных без ожидания FIN; ctsTraffic -shutdown:rude, verify:data. Штатное закрытие TCP не проверяется; прежние ошибки сохранены / Data-only transfer; normal TCP close is not tested. Not a version comparison.') }
if ($boundDriver -and -not $repeatDriver) { Write-Host 'driver: параметры связаны с завершённой серией 4.0.0; новая загрузка Windows проверяется. Четыре коротких прогона, около 2–4 минут; проверка готовности, не сравнение максимальной скорости / Bound 4.0.0 reference and new boot required; four readiness runs, approximately 2–4 minutes, not a capacity comparison.' }
if ($repeatDriver) { Write-Host 'driver STANDARD: 3 чередующиеся пары на направление; 12 x 2 GiB в памяти, без файлов содержимого; 64 MiB/s. Около 8–12 минут. Та же загрузка Windows, что в SMOKE; перезагрузка сейчас не нужна. Запрос сокетов внутри переноса, прогрев не исключён; темп ограничен, не предел скорости / Counterbalanced pairs, capped load and process CPU/RAM, socket observation during transfer; no excluded warmup or capacity claim. Same successful readiness boot required.' }
if ($repeatLegacy) { Write-Host '4.0.0 STANDARD: те же 3 чередующиеся пары на направление, 12 x 2 GiB @ 64 MiB/s, verify:data и shutdown:rude; параметры связаны с завершённой серией driver. Около 10–15 минут, без файлов содержимого. Запрос сокетов внутри переноса, прогрев не исключён; темп ограничен, не предел скорости / Equivalent rate-capped repeated transfers, instrumentation included. Historical normal-close failure retained. Reboot before driver.' }
if ($ProductContract -eq 'v4.0.0' -and -not $shutdownDiagnostic -and -not $repeatLegacy) { Write-Host '4.0.0: короткая проверка upload/download, 4 x 64 MiB; около 2–4 минут. Socket query выполняется во время переноса: диагностический темп, не сравнение версий / Transfer readiness only; socket observation overlaps transfer. Reboot before driver.' }
Save-Manifest
try {
    :transferSeries foreach ($direction in @($directions)) {
        for ($pair=1;$pair -le $pairs;$pair++) {
            $order=$(if ($shutdownDiagnostic) { @('PROXY') } elseif ($pair % 2) { @('OFF','PROXY') } else { @('PROXY','OFF') })
            foreach ($mode in $order) {
                if ($CancellationPath -and (Test-Path -LiteralPath $CancellationPath -PathType Leaf)) {
                    $manifest.status='CANCELLED';$manifest['cancellation_requested']=$true
                    Write-Host 'Остановлено между прогонами; завершённые данные сохранены / Stopped between runs; completed evidence retained.'
                    break transferSeries
                }
                $name='{0}-pair-{1:d2}-{2}' -f $direction,$pair,$mode.ToLowerInvariant()
                if ($Resume -and @($manifest.runs | Where-Object { $_.direction -eq $direction -and $_.pair -eq $pair -and $_.mode -eq $mode -and $_.status -eq 'COMPLETED' }).Count) { continue }
                if ($name -eq $retryOriginalName) { $name+=$retrySuffix }
                $entry=[ordered]@{direction=$direction;pair=$pair;mode=$mode;directory=$name;status='RUNNING'}
                $manifest.runs+=$entry;Save-Manifest
                Write-Host ('['+$manifest.runs.Count+'/'+$(if ($shutdownDiagnostic) {1} else {$pairs*4})+'] '+$name)
                Invoke-TcpRun $mode $direction (Join-Path $EvidenceDirectory $name)
                $entry.status='COMPLETED';Save-Manifest
            }
        }
    }
    if ($manifest.status -ne 'CANCELLED') { $manifest.status='COMPLETED' }
} catch { $manifest.status='FAILED';$manifest.error=$(if ($_.Exception.Message) { $_.Exception.Message } else { 'TCP_SERIES_FAILED_WITHOUT_EXCEPTION_MESSAGE' }) }
finally { $manifest['completed_at_utc']=[DateTime]::UtcNow.ToString('o');Save-Manifest }
if ($manifest.status -eq 'CANCELLED') { return }
if ($manifest.status -ne 'COMPLETED') { throw $manifest.error }
if ($shutdownDiagnostic) {
    Write-Host ('Диагностический отчёт / Diagnostic report: '+(Join-Path $EvidenceDirectory 'push-pair-01-proxy/diagnostic-summary.md'))
    Write-Host 'Диагностика не исправляет исходный сброс и не входит в сравнение версий / Diagnostic completion does not fix the original reset or enter version comparisons.'
    return
}
& $PythonPath (Join-Path $root 'src/pb_tcp_benchmark_report.py') --evidence-directory $EvidenceDirectory
if ($LASTEXITCODE -ne 0) { throw 'TCP_COMPARISON_NOT_CONFIRMED' }
Write-Host ('Отчёт / Report: '+(Join-Path $EvidenceDirectory 'summary.md'))
