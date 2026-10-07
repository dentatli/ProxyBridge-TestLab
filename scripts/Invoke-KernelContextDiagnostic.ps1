[CmdletBinding()]
param([Parameter(Mandatory)][string]$DiagnosticDirectory,
    [ValidateSet('Prepare','Inspect','Install','Run','Restore')][string]$Phase='Inspect',
    [scriptblock]$DiagnosticPhaseObserver)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$DiagnosticDirectory=[IO.Path]::GetFullPath($DiagnosticDirectory)
$inner=Join-Path $PSScriptRoot 'Invoke-TcpRedirectContextDiagnostic.ps1'
# Files-only validation also checks the workspace boundary, reparse points and frozen dependencies.
if ($Phase -eq 'Prepare') {& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase Prepare;return}
& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase Inspect
$kit=Join-Path $DiagnosticDirectory 'kit'
$receiptPath=Join-Path $kit 'redirect-context-diagnostic.json'
$build=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
if ($build.method -ne 'redirect-kernel-context-v4') {throw 'KERNEL_CANDIDATE_METHOD_REQUIRED'}
$validation=Get-Content -LiteralPath (Join-Path $DiagnosticDirectory 'verification/validation.json') -Raw | ConvertFrom-Json
if ($validation.status -ne 'PREPARED_STATIC_CHECKS_PASSED_RUNTIME_PENDING' -or $validation.kernel_sha256 -ine (Get-FileHash -LiteralPath (Join-Path $kit 'ProxyBridgeDrv.sys')).Hash -or
    $validation.core_sha256 -ine (Get-FileHash -LiteralPath (Join-Path $kit 'ProxyBridgeCore.dll')).Hash) {throw 'KERNEL_CANDIDATE_VALIDATION_INVALID'}
if ($Phase -eq 'Inspect') {return}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'KERNEL_DIAGNOSTIC_REQUIRES_ADMINISTRATOR'}
Import-Module (Join-Path $root 'modules/Env.psm1')
Import-Module (Join-Path $root 'modules/InterceptionState.psm1')
Import-Module (Join-Path $root 'modules/ConnectionLoad.psm1')
$candidateEnvironment=Import-DotEnv (Join-Path $kit 'product.env')
$baseEnvironment=Import-DotEnv (Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env')
$baseline=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/ProxyBridgeDrv.sys'
$candidate=Join-Path $kit 'ProxyBridgeDrv.sys'
$baselineHash='3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e'
if ($baseEnvironment['PB_PROXYBRIDGE_SERVICE'] -cne 'ProxyBridgeDrv' -or $candidateEnvironment['PB_PROXYBRIDGE_SERVICE'] -cne 'ProxyBridgeDrv' -or
    (Get-FileHash -LiteralPath $baseline).Hash -ine $baselineHash -or $baseEnvironment['PB_DRIVER_PATH'] -ine $baseline -or
    $candidateEnvironment['PB_DRIVER_PATH'] -ine $candidate) {throw 'KERNEL_CANDIDATE_BASE_BINDING_INVALID'}
foreach ($file in @($baseline,$candidate)) {
    $signature=Get-AuthenticodeSignature -LiteralPath $file
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ine '4544323109A45FC4761819E079BBDBD5E0BFE8D6') {throw 'KERNEL_CANDIDATE_SIGNATURE_INVALID'}
}
$installationPath=Join-Path $DiagnosticDirectory 'kernel-installation.json'
function Save-Installation($Value) {$Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $installationPath -Encoding UTF8}
function Read-Installation {
    $current=$DiagnosticDirectory
    while ($current) {
        if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'KERNEL_INSTALLATION_REPARSE_POINT'}
        $current=[IO.Path]::GetDirectoryName($current)
    }
    $file=Get-Item -LiteralPath $installationPath -Force
    if ($file.Length -gt 1MB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'KERNEL_INSTALLATION_FILE_INVALID'}
    $saved=Get-Content -LiteralPath $installationPath -Raw | ConvertFrom-Json
    if ($saved.schema_version -ne 1 -or $saved.service_name -cne 'ProxyBridgeDrv' -or $saved.baseline_path -ine $baseline -or
        $saved.baseline_sha256 -ine $baselineHash -or $saved.candidate_path -ine $candidate -or
        $saved.candidate_sha256 -ine $candidateEnvironment['PB_EXPECTED_DRIVER_SHA256'] -or $saved.build_receipt_sha256 -ine (Get-FileHash -LiteralPath $receiptPath).Hash -or
        $saved.runtime_plan_sha256 -ine (Get-FileHash -LiteralPath (Join-Path $DiagnosticDirectory 'runtime-plan.json')).Hash) {throw 'KERNEL_INSTALLATION_BINDING_INVALID'}
    $originalPath=[string]$saved.original_service_settings.ImagePath
    if ($originalPath.StartsWith('\??\')) {$originalPath=$originalPath.Substring(4)}
    if ($originalPath -ine $baseline) {throw 'KERNEL_RESTORE_ORIGINAL_PATH_INVALID'}
    return $saved
}
function Assert-Idle($Environment,[string]$Stage) {
    $observer=[Collections.Generic.Dictionary[string,string]]::new();foreach ($key in $Environment.Keys) {$observer[$key]=$Environment[$key]}
    $observer['PB_WINDIVERT_CTL_EXE']=Join-Path $root 'bin/tools/windivert-2.2.2/windivertctl.exe'
    $observer['PB_EXPECTED_WINDIVERT_CTL_SHA256']='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765'
    $observer['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
    $state=Get-InterceptionStateSnapshot -Environment $observer -AllowProductRuntime
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    $processes=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe'))
    [ordered]@{state=$state;loaded=$loaded;product_processes=@($processes | Select-Object ProcessId,Name,ExecutablePath)} | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath (Join-Path $DiagnosticDirectory ('kernel-registration-'+$Stage+'-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fffffff')+'.json')) -Encoding UTF8
    if (-not $state.current_driver_preparation_allowed -or -not $state.wfp_detachment_observed -or $state.wfp.status -ne 'SERVICE_FILE_VERIFIED' -or $state.wfp.service_state -ne 'Stopped' -or
        -not $state.windivert.configured -or -not $state.windivert.files_verified -or -not $state.windivert.capture_complete -or $state.windivert.status -ne 'NO_HANDLES_OBSERVED' -or
        $state.windivert.observed_handle_count -ne 0 -or -not $loaded.query_complete -or -not $loaded.known_interception_driver_names_absent -or $processes.Count) {throw 'KERNEL_REGISTRATION_REQUIRES_CONFIRMED_IDLE'}
}
function Read-ServiceSettings {
    $key=Get-Item -LiteralPath 'HKLM:/SYSTEM/CurrentControlSet/Services/ProxyBridgeDrv'
    $values=[ordered]@{}
    foreach ($name in @('ImagePath','Type','Start','ErrorControl','ObjectName','Group','DependOnService')) {
        $values[$name]=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    return $values
}
function Assert-OtherSettings($Before,$After) {
    foreach ($name in @('Type','Start','ErrorControl','ObjectName','Group','DependOnService')) {
        if (($Before.$name | ConvertTo-Json -Compress) -cne ($After.$name | ConvertTo-Json -Compress)) {throw 'KERNEL_REGISTRATION_OTHER_SETTINGS_CHANGED'}
    }
}
function Set-ServicePath([string]$Path) {
    if ($Path -match '["\r\n]' -or $Path.Length -gt 1024) {throw 'KERNEL_REGISTRATION_IMAGE_PATH_INVALID'}
    $output=& (Join-Path $env:SystemRoot 'System32/sc.exe') config ProxyBridgeDrv binPath= $Path 2>&1
    if ($LASTEXITCODE -ne 0) {throw ('KERNEL_REGISTRATION_CONFIG_FAILED: '+($output -join ' '))}
}
function Invoke-Registration([string]$Action) {
    $mutex=[Threading.Mutex]::new($false,'Global\ProxyBridgeTestLabPlannedBenchmark');$owns=$false;$lease=$null
    try {
        try {$owns=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$owns=$true}
        if (-not $owns) {throw 'LAB_PLANNED_RUN_ALREADY_ACTIVE'}
        $leasePath=Join-Path $root 'artifacts/benchmark-launch/execution.lock'
        $leaseCheck=$leasePath
        while ($leaseCheck) {
            if ((Test-Path -LiteralPath $leaseCheck) -and ((Get-Item -LiteralPath $leaseCheck -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'KERNEL_LEASE_REPARSE_POINT'}
            $leaseCheck=[IO.Path]::GetDirectoryName($leaseCheck)
        }
        $lease=[IO.File]::Open($leasePath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if ($Action -eq 'Install') {
            if (Test-Path -LiteralPath $installationPath) {throw 'KERNEL_INSTALLATION_RECEIPT_ALREADY_EXISTS'}
            # Refuse resource-bound experiments before changing the registered driver path.
            $resourcePreset=Get-ConnectionLoadPreset -Duration SHORT -Load HIGH
            $resources=Get-ConnectionResourceObservation -Directory $DiagnosticDirectory -MinimumAvailableBytes $resourcePreset.minimum_available_bytes
            Write-ConnectionJson $resources (Join-Path $DiagnosticDirectory ('kernel-resources-before-install-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fffffff')+'.json'))
            if ($resources.status -ne 'AVAILABLE') {throw ('KERNEL_DIAGNOSTIC_RESOURCES_NOT_READY: memory_bytes='+$resources.free_physical_bytes+' required='+$resources.minimum_available_bytes+' disk_bytes='+$resources.disk_free_bytes+' required='+$resources.minimum_disk_free_bytes+' status='+$resources.status)}
            Assert-Idle $baseEnvironment 'before-install'
            $before=Read-ServiceSettings
            if ($before.Type -ne 1 -or $before.Start -ne 3) {throw 'KERNEL_SERVICE_TYPE_OR_START_DIFFERS'}
            $record=[ordered]@{schema_version=1;status='PREPARED_NOT_INSTALLED';service_name='ProxyBridgeDrv';baseline_path=$baseline;baseline_sha256=$baselineHash;
                candidate_path=$candidate;candidate_sha256=$candidateEnvironment['PB_EXPECTED_DRIVER_SHA256'];original_service_settings=$before;
                build_receipt_sha256=(Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant();runtime_plan_sha256=(Get-FileHash -LiteralPath (Join-Path $DiagnosticDirectory 'runtime-plan.json')).Hash.ToLowerInvariant();
                installed_at_utc='';completed_at_utc='';driver_load_requested=$false;product_start_requested=$false;trust_changed=$false;testsigning_changed=$false;error=''}
            Save-Installation $record
            try {
                Set-ServicePath $candidate
                $record.status='REGISTRATION_CHANGED_READBACK_PENDING';Save-Installation $record
                $after=Read-ServiceSettings;Assert-OtherSettings $before $after
                Assert-Idle $candidateEnvironment 'after-install'
                $record.status='INSTALLED_REBOOT_REQUIRED';$record.installed_at_utc=[DateTime]::UtcNow.ToString('o')
            } catch {$record.status='INSTALLATION_FAILED_RESTORE_REQUIRED';$record.error=$_.Exception.Message;throw}
            finally {$record.completed_at_utc=[DateTime]::UtcNow.ToString('o');Save-Installation $record}
            Write-Host 'Диагностический путь зарегистрирован; драйвер не загружался. Перезагрузите Windows, затем выполните эту команду с -Phase Run.'
        } else {
            $record=Read-Installation
            if ($record.status -eq 'RESTORED_BASELINE_REBOOT_RECOMMENDED') {Assert-Idle $baseEnvironment 'restore-already-completed';Write-Host 'Путь исходного драйвера уже восстановлен.';return}
            if ($record.status -notin @('PREPARED_NOT_INSTALLED','INSTALLED_REBOOT_REQUIRED','REGISTRATION_CHANGED_READBACK_PENDING','INSTALLATION_FAILED_RESTORE_REQUIRED')) {throw 'KERNEL_RESTORE_RECEIPT_STATE_INVALID'}
            $registered=Read-ServiceSettings
            $currentPath=[string]$registered.ImagePath
            if ($currentPath.StartsWith('\??\')) {$currentPath=$currentPath.Substring(4)}
            if ($currentPath -ieq $baseline) {Assert-Idle $baseEnvironment 'before-restore-already-baseline'}
            elseif ($currentPath -ieq $candidate) {Assert-Idle $candidateEnvironment 'before-restore'}
            else {throw 'KERNEL_RESTORE_FOREIGN_REGISTRATION'}
            $before=Read-ServiceSettings;Assert-OtherSettings $record.original_service_settings $before
            Set-ServicePath ([string]$record.original_service_settings.ImagePath)
            $after=Read-ServiceSettings;Assert-OtherSettings $record.original_service_settings $after
            if ($after.ImagePath -cne $record.original_service_settings.ImagePath) {throw 'KERNEL_RESTORE_IMAGE_PATH_READBACK_DIFFERS'}
            Assert-Idle $baseEnvironment 'after-restore'
            $record.status='RESTORED_BASELINE_REBOOT_RECOMMENDED';$record.completed_at_utc=[DateTime]::UtcNow.ToString('o');Save-Installation $record
            Write-Host 'Путь исходного драйвера восстановлен и проверен. Перед контрольными измерениями перезагрузите Windows.'
        }
    } finally {if ($lease) {$lease.Dispose()};if ($owns) {$mutex.ReleaseMutex()};$mutex.Dispose()}
}
if ($Phase -eq 'Run') {
    $installed=Read-Installation
    if ($installed.status -ne 'INSTALLED_REBOOT_REQUIRED') {throw 'KERNEL_DIAGNOSTIC_INSTALL_FIRST'}
    $boot=([DateTime](Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5).LastBootUpTime).ToUniversalTime()
    if ($boot -le ([DateTime]$installed.installed_at_utc).ToUniversalTime()) {throw 'KERNEL_DIAGNOSTIC_REBOOT_REQUIRED'}
    try {& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase Run -DiagnosticPhaseObserver $DiagnosticPhaseObserver}
    finally {
        try {Invoke-Registration 'Restore'} catch {Write-Warning ('Возврат к исходному пути не подтверждён: '+$_.Exception.Message+'. После штатного завершения выполните -Phase Restore.');throw}
    }
} else {Invoke-Registration $Phase}
