[CmdletBinding()]
param(
    [ValidateSet('Prepare','LegacyLifecycle','LegacyIdleObservation','LegacyTransferReadiness','LegacyTransferComparison')][string]$Phase='Prepare',
    [string]$EvidenceDirectory='',
    [string]$DriverTransferDirectory=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($DriverTransferDirectory -and $Phase -ne 'LegacyTransferComparison') { throw 'VERSION_DRIVER_TRANSFER_REFERENCE_REQUIRES_COMPARISON_PHASE' }
$root=Split-Path -Parent $PSScriptRoot
foreach ($name in @('Env','ProductBuild','ProductProfile','InterceptionState','ProxyBridgeCli','ProcessAdapter')) {
    Import-Module (Join-Path $root ('modules/'+$name+'.psm1'))
}
function Read-Json([string]$path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
function Write-Json($value,[string]$path) {
    $value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $path -Encoding UTF8
}
function Get-BootIdentity {
    $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop
    [ordered]@{
        computer_name=$env:COMPUTERNAME
        machine_guid=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
        boot_time_utc=([DateTime]$os.LastBootUpTime).ToUniversalTime().ToString('o')
        os_build=[string]$os.BuildNumber
    }
}
function Assert-Hash([string]$path,[string]$expected) {
    if ($expected -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $expected) {
        throw ('VERSION_PREFLIGHT_FILE_CHANGED_'+[IO.Path]::GetFileName($path))
    }
}
function Get-KitEvidence([string]$contract) {
    $buildRoot=Join-Path $root 'artifacts/product-builds'
    if ($contract -eq 'driver') {
        $baseName='driver-63be0eb'; $commit='63be0ebf9bec92bfba95ef3d6729c375aa9af84e'
        $sourceSha='679464cb81e236f2119af913206d8e8a78a5eac3a50864069851441f486c9d2d'
    } else {
        $baseName='v4.0.0-release'; $commit='22e53445e44481fad0f63c2a088aa91c0deda3af'
        $sourceSha='0d117b6a7be27625607b3df6b3e3ed3396e93fd9dfdde1480fb6417aa8c7c593'
    }
    $base=Join-Path $buildRoot $baseName; $kit=$base+'-testlab-cli'
    $envPath=Join-Path $kit 'product.env'; $environment=Import-DotEnv -Path $envPath
    $identity=Get-ProductBuildIdentity -Environment $environment -Contract $contract
    if (-not $identity.files_verified) { throw ('VERSION_PREFLIGHT_KIT_NOT_VERIFIED_'+$contract) }
    $receiptPath=Join-Path $kit 'build-receipt.json'; $receipt=Read-Json $receiptPath
    $baseReceiptPath=Join-Path $base 'build-receipt.json'; $baseReceipt=Read-Json $baseReceiptPath
    if ($receipt.contract -ne $contract -or $receipt.cli_variant -ne 'testlab-unbuffered-v1' -or
        $receipt.cli_source_commit -ne $commit -or $identity.declared_source_commit -ne $commit -or
        $receipt.upstream_cli_source_sha256 -ine $sourceSha -or $identity.declared_cli_variant -ne $receipt.cli_variant) {
        throw 'VERSION_PREFLIGHT_RECEIPT_CONTRACT_CHANGED'
    }
    Assert-Hash $baseReceiptPath $receipt.base_receipt_sha256
    $source=Join-Path $buildRoot ('ProxyBridge-'+$commit+'/Windows/cli/main.c')
    Assert-Hash $source $sourceSha
    Assert-Hash (Join-Path $kit 'main.testlab.c') $receipt.patched_cli_source_sha256
    $archive=Join-Path $buildRoot ($commit+'.zip')
    Assert-Hash $archive $baseReceipt.source_archive_sha256
    foreach ($component in @($receipt.components)) {
        if ([IO.Path]::GetFileName([string]$component.name) -cne [string]$component.name) { throw 'VERSION_PREFLIGHT_COMPONENT_NAME_INVALID' }
        Assert-Hash (Join-Path $kit $component.name) $component.sha256
        if ($component.name -ne 'ProxyBridge_CLI.exe') {
            if (-not $component.unchanged_from_base) { throw 'VERSION_PREFLIGHT_CORE_OR_DRIVER_CHANGED' }
            Assert-Hash (Join-Path $base $component.name) $component.sha256
        }
    }
    if ($contract -eq 'v4.0.0') {
        Assert-Hash (Join-Path $buildRoot 'ProxyBridge-Setup-4.0.0.exe') $baseReceipt.installer_sha256
    }
    [ordered]@{
        contract=$contract; env_path=$envPath; identity=$identity
        receipt_chain_verified=$true; base_components_unchanged=$true
        cli_source_sha256=$sourceSha; archive_sha256=$baseReceipt.source_archive_sha256
        build_receipt_sha256=(Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant()
        cli_changes=@($receipt.changes)
        limitations=@('Checks stored receipts and files, not an independent reproduction of the build.',
            'Declared source revisions are pinned; current upstream HEAD is not checked.',
            'Loaded modules, actual route and benchmark comparability require runtime evidence.')
    }
}
if ($Phase -eq 'Prepare') {
    if (-not $EvidenceDirectory) {
        $EvidenceDirectory=Join-Path $root ('artifacts/version-comparison/preflight-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    }
    if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'VERSION_PREFLIGHT_REQUIRES_NEW_DIRECTORY' }
    $null=New-Item -ItemType Directory -Path $EvidenceDirectory
    $EvidenceDirectory=(Resolve-Path -LiteralPath $EvidenceDirectory).Path
    $report=[ordered]@{schema_version=1;status='PREPARING';created_at_utc=[DateTime]::UtcNow.ToString('o');boot_identity=(Get-BootIdentity);products=@();profile_files=@();switch_policy='reboot_between_versions';profile_format_compatible=$false;product_runtime_started=$false;route_verified=$false;benchmark_ready=$false;version_switch_ready=$false;error=''}
    try {
        foreach ($contract in @('driver','v4.0.0')) { $report.products+=,(Get-KitEvidence $contract) }
        if (($report.products[0].cli_changes -join "`n") -cne ($report.products[1].cli_changes -join "`n")) { throw 'VERSION_PREFLIGHT_CLI_VARIANTS_DIFFER' }
        $profile=[ordered]@{
            Version='1.0'; Name='TCP version comparison'; LocalhostViaProxy=$true; IsTrafficLoggingEnabled=$true
            AutoClearConnectionLogs=$false; Language='en'; CloseToTray=$false; LogFilters=@()
            ProxyConfigs=@([ordered]@{Id=1;Name='Controlled TCP SOCKS5';Type='SOCKS5';Host='127.0.0.1';Port='54123';Username='';Password='';SendDomainToProxy=$false})
            ProxyRules=@(
                [ordered]@{Name='TCP request and response latency';ProcessName='pb_tcp_rtt_client.exe';TargetHosts='127.0.0.1';TargetPorts='54122';TargetDomains='';Protocol='TCP';Action='PROXY';ProxyConfigId=1;IsEnabled=$true},
                [ordered]@{Name='Concurrent TCP transfer';ProcessName='ctsTraffic.exe';TargetHosts='127.0.0.1';TargetPorts='54126';TargetDomains='';Protocol='TCP';Action='PROXY';ProxyConfigId=1;IsEnabled=$true})
        } | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        Write-Json $profile (Join-Path $EvidenceDirectory 'canonical-tcp.pbprofile')
        foreach ($contract in @('driver','v4.0.0')) {
            $compatible=Get-ProductProfileCompatibility -Profile $profile -Contract $contract
            Write-Json $compatible (Join-Path $EvidenceDirectory ($contract+'-profile-compatibility.json'))
            $adapted=ConvertTo-ProductProfile -Profile $profile -Contract $contract
            Write-Json $adapted (Join-Path $EvidenceDirectory ($contract+'-tcp.pbprofile'))
        }
        $transferProfile=$profile | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $transferProfile.Name='TCP transfer version comparison'
        $transferProfile.ProxyRules=@($transferProfile.ProxyRules | Where-Object ProcessName -eq 'ctsTraffic.exe')
        $transferProfile.ProxyRules[0].Name='TCP upload and download'
        $transferProfile.ProxyRules[0].TargetPorts='54122'
        foreach ($contract in @('driver','v4.0.0')) {
            Write-Json (ConvertTo-ProductProfile -Profile $transferProfile -Contract $contract) (Join-Path $EvidenceDirectory ($contract+'-transfer.pbprofile'))
        }
        $lifecycleProfile=[ordered]@{Version='1.0';Name='CLI lifecycle';LocalhostViaProxy=$false;IsTrafficLoggingEnabled=$false;AutoClearConnectionLogs=$false;Language='en';CloseToTray=$false;LogFilters=@();ProxyConfigs=@();ProxyRules=@([ordered]@{Name='Unused process lifecycle rule';ProcessName='ProxyBridge_TestLab_Lifecycle_Probe.exe';TargetHosts='127.0.0.1';TargetPorts='54122';TargetDomains='';Protocol='TCP';Action='DIRECT';ProxyConfigId=0;IsEnabled=$true})} | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        Write-Json (ConvertTo-ProductProfile -Profile $lifecycleProfile -Contract 'v4.0.0') (Join-Path $EvidenceDirectory 'v4.0.0-lifecycle.pbprofile')
        foreach ($name in @('driver-tcp.pbprofile','v4.0.0-tcp.pbprofile','v4.0.0-lifecycle.pbprofile','driver-transfer.pbprofile','v4.0.0-transfer.pbprofile')) {
            $report.profile_files+=,[ordered]@{file_name=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $EvidenceDirectory $name)).Hash.ToLowerInvariant()}
        }
        $report.profile_format_compatible=$true
        $report.status='FILES_AND_PROFILES_PREPARED'
    } catch { $report.status='FAILED'; $report.error=$_.Exception.Message }
    Write-Json $report (Join-Path $EvidenceDirectory 'preflight.json')
    if ($report.status -eq 'FAILED') { throw $report.error }
    Write-Host ('Комплекты и общий TCP-профиль проверены / Kits and common TCP profile checked: '+$EvidenceDirectory)
    Write-Host 'Следующий этап — LegacyLifecycle после перезагрузки, без трафика / Next: LegacyLifecycle after reboot, no generated traffic. Benchmark not ready.'
    return
}
if ($Phase -eq 'LegacyTransferComparison') {
    if (-not $DriverTransferDirectory) { throw 'VERSION_LEGACY_REPEAT_REQUIRES_DRIVER_TRANSFER_DIRECTORY' }
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'VERSION_LEGACY_REPEAT_REQUIRES_ADMIN' }
    $DriverTransferDirectory=(Resolve-Path -LiteralPath $DriverTransferDirectory).Path
    $taskPython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    $text=& $taskPython (Join-Path $root 'src/pb_tcp_transfer_reference.py') --driver-repeat $DriverTransferDirectory
    if ($LASTEXITCODE -ne 0) { throw 'VERSION_DRIVER_REPEATED_TRANSFER_NOT_CONFIRMED' }
    $binding=$text | ConvertFrom-Json
    if (-not $EvidenceDirectory) { $EvidenceDirectory=$binding.preflight_directory }
    $EvidenceDirectory=(Resolve-Path -LiteralPath $EvidenceDirectory).Path
    if ($EvidenceDirectory -ine $binding.preflight_directory) { throw 'VERSION_LEGACY_REPEAT_PREFLIGHT_CHANGED' }
    $boot=Get-BootIdentity
    foreach ($key in @('computer_name','machine_guid','os_build')) {
        if ($boot[$key] -ne $binding.driver_boot_identity.$key) { throw 'VERSION_LEGACY_REPEAT_MACHINE_CHANGED' }
    }
    if ([DateTimeOffset]::Parse($boot.boot_time_utc) -le [DateTimeOffset]::Parse($binding.driver_completed_at_utc)) { throw 'VERSION_LEGACY_REPEAT_REBOOT_REQUIRED' }
    $before=@(Get-ChildItem -LiteralPath $EvidenceDirectory -Directory -Filter 'legacy-idle-*' | Select-Object -ExpandProperty FullName)
    Write-Host '4.0.0: подготовка после driver — проверка запуска/остановки, наблюдение покоя, затем 12 переносов по 2 GiB @ 64 MiB/s. Около 10–15 минут; содержимое передаётся в памяти. Сравнение версий будет составлено после проверки результата / Reboot verified; lifecycle, idle observation and equivalent repeated transfers; version aggregation pending.'
    & $PSCommandPath -Phase LegacyLifecycle -EvidenceDirectory $EvidenceDirectory
    & $PSCommandPath -Phase LegacyIdleObservation -EvidenceDirectory $EvidenceDirectory
    $created=@(Get-ChildItem -LiteralPath $EvidenceDirectory -Directory -Filter 'legacy-idle-*' | Where-Object { $_.FullName -notin $before })
    if ($created.Count -ne 1) { throw 'VERSION_LEGACY_REPEAT_IDLE_DIRECTORY_NOT_UNIQUE' }
    & (Join-Path $PSScriptRoot 'Invoke-LocalTcpBenchmark.ps1') -Profile STANDARD -ProductContract v4.0.0 -TransferOnly -LegacyIdleDirectory $created[0].FullName -DriverTransferDirectory $DriverTransferDirectory
    return
}
if (-not $EvidenceDirectory) { throw 'VERSION_LIFECYCLE_REQUIRES_PREFLIGHT_DIRECTORY' }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'VERSION_LIFECYCLE_REQUIRES_ADMINISTRATOR' }
$EvidenceDirectory=(Resolve-Path -LiteralPath $EvidenceDirectory).Path
if ($Phase -eq 'LegacyTransferReadiness') {
    # Each existing phase retains its own boot, file, process and interception guards.
    $prepared=Read-Json (Join-Path $EvidenceDirectory 'preflight.json')
    if ($prepared.status -ne 'FILES_AND_PROFILES_PREPARED' -or $prepared.switch_policy -ne 'reboot_between_versions') { throw 'VERSION_TRANSFER_PREFLIGHT_NOT_CONFIRMED' }
    foreach ($name in @('driver-transfer.pbprofile','v4.0.0-transfer.pbprofile')) {
        $entry=@($prepared.profile_files | Where-Object file_name -eq $name)
        if ($entry.Count -ne 1) { throw 'VERSION_TRANSFER_PROFILE_NOT_PINNED' }
        Assert-Hash (Join-Path $EvidenceDirectory $name) $entry[0].sha256
    }
    $before=@(Get-ChildItem -LiteralPath $EvidenceDirectory -Directory -Filter 'legacy-idle-*' | Select-Object -ExpandProperty FullName)
    & $PSCommandPath -Phase LegacyLifecycle -EvidenceDirectory $EvidenceDirectory
    & $PSCommandPath -Phase LegacyIdleObservation -EvidenceDirectory $EvidenceDirectory
    $created=@(Get-ChildItem -LiteralPath $EvidenceDirectory -Directory -Filter 'legacy-idle-*' | Where-Object { $_.FullName -notin $before })
    if ($created.Count -ne 1) { throw 'VERSION_TRANSFER_EXPECTED_ONE_NEW_IDLE_OBSERVATION' }
    & (Join-Path $PSScriptRoot 'Invoke-LocalTcpBenchmark.ps1') -Profile SMOKE -ProductContract v4.0.0 -LegacyIdleDirectory $created[0].FullName
    return
}
$preflight=Read-Json (Join-Path $EvidenceDirectory 'preflight.json')
if ($preflight.status -ne 'FILES_AND_PROFILES_PREPARED' -or $preflight.switch_policy -ne 'reboot_between_versions') { throw 'VERSION_PREFLIGHT_NOT_CONFIRMED' }
$boot=Get-BootIdentity
if ($boot.machine_guid -ne $preflight.boot_identity.machine_guid -or $boot.os_build -ne $preflight.boot_identity.os_build) { throw 'VERSION_LIFECYCLE_MACHINE_CHANGED' }
if ([DateTimeOffset]::Parse($boot.boot_time_utc) -le [DateTimeOffset]::Parse($preflight.boot_identity.boot_time_utc)) { throw 'VERSION_LIFECYCLE_REBOOT_REQUIRED' }
$current=@()
foreach ($contract in @('driver','v4.0.0')) { $current+=,(Get-KitEvidence $contract) }
for ($index=0;$index -lt 2;$index++) {
    if ($current[$index].identity.bundle_sha256 -ne $preflight.products[$index].identity.bundle_sha256 -or
        $current[$index].build_receipt_sha256 -ne $preflight.products[$index].build_receipt_sha256) { throw 'VERSION_LIFECYCLE_KIT_CHANGED_SINCE_PREFLIGHT' }
}
foreach ($name in @('driver-tcp.pbprofile','v4.0.0-tcp.pbprofile','v4.0.0-lifecycle.pbprofile')) {
    $selected=@($preflight.profile_files | Where-Object file_name -eq $name)
    if ($selected.Count -ne 1) { throw 'VERSION_LIFECYCLE_PROFILE_NOT_PINNED' }
    Assert-Hash (Join-Path $EvidenceDirectory $name) $selected[0].sha256
}
if ($Phase -eq 'LegacyIdleObservation') {
    $directory=Join-Path $EvidenceDirectory ('legacy-idle-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    $null=New-Item -ItemType Directory -Path $directory
    $receipt=[ordered]@{schema_version=1;status='PREPARING';started_at_utc=[DateTime]::UtcNow.ToString('o');boot_identity=$boot;contract='v4.0.0';lifecycle_directory='';product_runtime_started=$false;traffic_generated=$false;observer_mode='list';observer_dll_matches_selected_kit=$false;no_compatible_windivert_handles_observed=$false;known_wfp_detachment_observed=$false;same_version_idle_observed=$false;reboot_required_before_other_version=$true;interception_cleanup_verified=$false;version_switch_ready=$false;route_verified=$false;benchmark_ready=$false;error=''}
    try {
        $candidates=@()
        foreach ($folder in @(Get-ChildItem -LiteralPath $EvidenceDirectory -Directory -Filter 'legacy-lifecycle-*')) {
            $receiptPath=Join-Path $folder.FullName 'lifecycle-receipt.json'
            if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { continue }
            $saved=Read-Json $receiptPath
            if ($saved.status -eq 'START_STOP_OBSERVED_REBOOT_REQUIRED' -and $saved.startup_shutdown_verified -and
                $saved.contract -eq 'v4.0.0' -and $saved.boot_identity.boot_time_utc -eq $boot.boot_time_utc -and
                $saved.boot_identity.machine_guid -eq $boot.machine_guid -and $saved.boot_identity.os_build -eq $boot.os_build) {
                $candidates+=,$folder.FullName
            }
        }
        if ($candidates.Count -ne 1) { throw 'VERSION_IDLE_REQUIRES_ONE_SUCCESSFUL_LEGACY_LIFECYCLE_ON_CURRENT_BOOT' }
        $receipt.lifecycle_directory=$candidates[0]
        $cli=Read-Json (Join-Path $candidates[0] 'cli-lifecycle.json')
        if (-not $cli.ready -or -not $cli.graceful_stop -or -not $cli.post_stop_verified -or
            $cli.forced_stop -or -not $cli.output_capture_complete -or $cli.primary_error -or $cli.cleanup_error -or $cli.error -or
            $cli.actual_path_probe_status -ne 'PATH_OBTAINED') {
            throw 'VERSION_IDLE_LEGACY_CLI_STOP_NOT_CONFIRMED'
        }
        $legacyEnv=Import-DotEnv -Path $current[1].env_path
        if (-not [string]::Equals([IO.Path]::GetFullPath($cli.actual_path),[IO.Path]::GetFullPath($legacyEnv['PB_PROXYBRIDGE_CLI_EXE']),[StringComparison]::OrdinalIgnoreCase)) {
            throw 'VERSION_IDLE_LEGACY_CLI_PATH_CHANGED'
        }
        $previousLoaded=Read-Json (Join-Path $candidates[0] 'loaded-drivers-after.json')
        if (-not $previousLoaded.query_complete) { throw 'VERSION_IDLE_PREVIOUS_DRIVER_QUERY_INCOMPLETE' }
        $active=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { $_.Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe') })
        if ($active.Count) { throw 'VERSION_IDLE_PRODUCT_PROCESS_CONFLICT' }
        $toolDirectory=Join-Path $root 'bin/tools/windivert-2.2.2'
        $observer=Join-Path $toolDirectory 'windivertctl.exe'
        $observerDll=Join-Path $toolDirectory 'WinDivert.dll'
        $observerHash='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765'
        $dllHash='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
        Assert-Hash $observer $observerHash
        Assert-Hash $observerDll $dllHash
        Assert-Hash (Join-Path (Split-Path -Parent $legacyEnv['PB_PROXYBRIDGE_CLI_EXE']) 'WinDivert.dll') $dllHash
        $receipt.observer_dll_matches_selected_kit=$true
        $observationEnv=Import-DotEnv -Path $current[0].env_path
        $observationEnv['PB_WINDIVERT_CTL_EXE']=$observer
        $observationEnv['PB_EXPECTED_WINDIVERT_CTL_SHA256']=$observerHash
        $observationEnv['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']=$dllHash
        $state=Get-InterceptionStateSnapshot -Environment $observationEnv -TimeoutMs 10000 -AllowProductRuntime
        $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
        Write-Json $state (Join-Path $directory 'interception-idle.json')
        Write-Json $loaded (Join-Path $directory 'loaded-drivers-idle.json')
        $receipt.no_compatible_windivert_handles_observed=$state.windivert.files_verified -and $state.windivert.capture_complete -and
            $state.windivert.status -eq 'NO_HANDLES_OBSERVED' -and $state.windivert.observed_handle_count -eq 0
        $receipt.known_wfp_detachment_observed=$state.wfp_detachment_observed -and $state.wfp_objects.query_complete -and
            $state.wfp.status -eq 'SERVICE_FILE_VERIFIED' -and $state.wfp.service_state -eq 'Stopped'
        if (-not $receipt.no_compatible_windivert_handles_observed) { throw ('VERSION_IDLE_WINDIVERT_'+$state.windivert.status) }
        if (-not $receipt.known_wfp_detachment_observed) { throw 'VERSION_IDLE_KNOWN_WFP_NOT_DETACHED' }
        $unexpected=@($loaded.known_interception_drivers | Where-Object { $_ -ine 'WinDivert64.sys' })
        if (-not $loaded.query_complete -or $loaded.selected_driver_loaded -or $unexpected.Count -or
            $loaded.other_driver_names_sha256 -ne $previousLoaded.other_driver_names_sha256) { throw 'VERSION_IDLE_DRIVER_INVENTORY_CHANGED_OR_INCOMPLETE' }
        $active=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { $_.Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe') })
        if ($active.Count) { throw 'VERSION_IDLE_PRODUCT_PROCESS_CONFLICT_AFTER_OBSERVATION' }
        $receipt.same_version_idle_observed=$true
        $receipt.status='LEGACY_IDLE_SCOPED_OBSERVED'
    } catch { $receipt.status='BLOCKED'; $receipt.error=$_.Exception.Message }
    $receipt['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
    Write-Json $receipt (Join-Path $directory 'idle-receipt.json')
    Write-Host ('Результаты / Results: '+$directory)
    if ($receipt.status -eq 'BLOCKED') { throw $receipt.error }
    Write-Host 'Открытых дескрипторов совместимого WinDivert не обнаружено; известный WFP отключён / No compatible WinDivert handles observed; known WFP detached.'
    Write-Host 'Это наблюдение покоя той же 4.0.0, не проверка маршрута/скорости и не глобальная очистка. Перед Driver нужна перезагрузка / Same-version idle snapshot only; reboot before Driver.'
    return
}
$directory=Join-Path $EvidenceDirectory ('legacy-lifecycle-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
$null=New-Item -ItemType Directory -Path $directory
$receipt=[ordered]@{schema_version=1;status='PREPARING';started_at_utc=[DateTime]::UtcNow.ToString('o');boot_identity=$boot;contract='v4.0.0';product_runtime_attempted=$false;product_runtime_started=$false;traffic_generated=$false;startup_shutdown_verified=$false;known_driver_names_absent_after=$false;reboot_required_before_other_version=$true;interception_cleanup_verified=$false;version_switch_ready=$false;route_verified=$false;benchmark_ready=$false;error=''}
$driverEnv=Import-DotEnv -Path $current[0].env_path
try {
    $active=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { $_.Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe') })
    if ($active.Count) { throw 'VERSION_LIFECYCLE_PRODUCT_PROCESS_CONFLICT' }
    $before=Get-InterceptionStateSnapshot -Environment $driverEnv -AllowProductRuntime
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    Write-Json $before (Join-Path $directory 'interception-before.json')
    Write-Json $loaded (Join-Path $directory 'loaded-drivers-before.json')
    if (-not $before.wfp_detachment_observed -or -not $before.wfp_objects.query_complete -or
        -not $loaded.query_complete -or -not $loaded.known_interception_driver_names_absent) { throw 'VERSION_LIFECYCLE_REQUIRES_NEW_BOOT_WITHOUT_KNOWN_INTERCEPTORS' }
    $profilePath=Join-Path $directory 'lifecycle.pbprofile'
    Copy-Item -LiteralPath (Join-Path $EvidenceDirectory 'v4.0.0-lifecycle.pbprofile') -Destination $profilePath
    $legacyEnv=Import-DotEnv -Path $current[1].env_path
    $plan=New-ProxyBridgeCliPlan -ExecutablePath $legacyEnv['PB_PROXYBRIDGE_CLI_EXE'] -ProfilePath $profilePath -ProductProfileContract 'v4.0.0' -CliVariant 'testlab-unbuffered-v1' -ReadyStableMs 1000 -ReadinessTimeoutMs 10000 -StopTimeoutMs 10000
    $sink={param($value) $value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $directory 'cli-lifecycle.json') -Encoding UTF8}.GetNewClosure()
    $receipt.product_runtime_attempted=$true
    $lifecycle=Invoke-ProxyBridgeCliLifecycle -Plan $plan -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime -EvidenceSink $sink
    $receipt.product_runtime_started=$lifecycle.ready
    $receipt.startup_shutdown_verified=$lifecycle.ready -and $lifecycle.graceful_stop -and $lifecycle.post_stop_verified -and $lifecycle.process_result.output_capture_complete -and $lifecycle.process_result.exit_code -eq 0
    if (-not $receipt.startup_shutdown_verified) { throw 'VERSION_LIFECYCLE_START_STOP_NOT_VERIFIED' }
    $receipt.status='START_STOP_OBSERVED_REBOOT_REQUIRED'
} catch { $receipt.status='FAILED'; $receipt.error=$_.Exception.Message }
finally {
    try {
        if (Test-Path -LiteralPath (Join-Path $directory 'cli-lifecycle.json')) {
            $observedCli=Read-Json (Join-Path $directory 'cli-lifecycle.json')
            $receipt.product_runtime_started=[bool]$observedCli.ready
        }
        Write-Json (Get-InterceptionStateSnapshot -Environment $driverEnv -AllowProductRuntime) (Join-Path $directory 'interception-after.json')
        $after=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
        Write-Json $after (Join-Path $directory 'loaded-drivers-after.json')
        $receipt.known_driver_names_absent_after=$after.query_complete -and $after.known_interception_driver_names_absent
    } catch { $receipt.status='FAILED'; $receipt.error+='; after-state: '+$_.Exception.Message }
    $receipt['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
    Write-Json $receipt (Join-Path $directory 'lifecycle-receipt.json')
}
Write-Host ('Результаты / Results: '+$directory)
if ($receipt.status -eq 'FAILED') { throw $receipt.error }
Write-Host 'Запуск и штатная остановка 4.0.0 подтверждены; маршруты и скорость пока не проверены / 4.0.0 start/stop observed; route and speed not checked.'
Write-Host 'Перед другой версией требуется новая перезагрузка / Another reboot is required before the other version.'
