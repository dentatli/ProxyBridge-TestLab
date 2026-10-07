[CmdletBinding()]
param([ValidateSet('Prepare','Inspect','Run')][string]$Phase='Inspect',
    [string]$PreparationDirectory='', [string]$ConnectionFile='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$method='linux-cts-data-compatibility-v2'
$engine=Join-Path $root 'bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe'
$engineHash='0548089e59c872306ce2c98e7163e2a717119756010cf64d3cb3da2854f632cf'
$envPath=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env'
$python=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
function Assert-NoReparse([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'LINUX_COMPAT_REPARSE_POINT'}
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Read-Json([string]$Path) {
    Assert-NoReparse $Path
    if ((Get-Item -LiteralPath $Path).Length -gt 1MB) {throw 'LINUX_COMPAT_JSON_BOUND'}
    return (Read-JsonText (Get-Content -LiteralPath $Path -Raw))
}
function Read-JsonText($Text) {
    $value=$Text -join [Environment]::NewLine
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {return ($value | ConvertFrom-Json -DateKind String)}
    return ($value | ConvertFrom-Json)
}
function Write-Json($Value,[string]$Path) {ConvertTo-Json -InputObject $Value -Depth 25 | Set-Content -LiteralPath $Path -Encoding UTF8}
function File-Hash([string]$Path) {Assert-NoReparse $Path;return (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()}
function Assert-PreparationPath([string]$Path) {
    Assert-NoReparse $Path
    $full=[IO.Path]::GetFullPath($Path)
    $parent=[IO.Path]::GetFullPath((Join-Path $root 'artifacts/diagnostics'))
    if ([IO.Path]::GetDirectoryName($full) -ine $parent -or [IO.Path]::GetFileName($full) -cnotmatch '^linux-cts-compatibility-preparation-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$') {throw 'LINUX_COMPAT_PREPARATION_PATH_INVALID'}
    return $full
}
$files=@('scripts/Invoke-LinuxCtsCompatibility.ps1','scripts/Invoke-LinuxCtsReceiver.ps1',
    'src/pb_cts_push_receiver.py','src/pb_linux_cts_control.py','src/pb_linux_cts_compatibility_report.py',
    'modules/ProcessAdapter.psm1','modules/Env.psm1','modules/ProductBuild.psm1','modules/InterceptionState.psm1',
    'src/pb_service_query.cs','src/pb_loaded_drivers.cs',
    'bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe','bin/tools/windivert-2.2.2/windivertctl.exe',
    'bin/tools/windivert-2.2.2/WinDivert.dll',
    'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env',
    'artifacts/product-builds/driver-63be0eb-testlab-cli/ProxyBridgeDrv.sys',
    'artifacts/product-builds/driver-63be0eb-testlab-cli/ProxyBridgeCore.dll',
    'artifacts/product-builds/driver-63be0eb-testlab-cli/ProxyBridge_CLI.exe')
$hashes=[ordered]@{}
foreach ($file in $files) {$hashes[$file]=File-Hash (Join-Path $root $file)}
if ($hashes['bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe'] -cne $engineHash) {throw 'LINUX_COMPAT_ENGINE_CHANGED'}
if ($Phase -eq 'Prepare') {
    if (-not $ConnectionFile) {$ConnectionFile=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ProxyBridge-TestLab/config/linux-receiver-connection.json'}
    $ConnectionFile=[IO.Path]::GetFullPath($ConnectionFile)
    $connection=Read-Json $ConnectionFile
    $hostIp=$null;$sourceIp=$null
    if ($connection.schema_version -ne 1 -or $connection.username -cne 'root' -or
        -not [Net.IPAddress]::TryParse([string]$connection.host,[ref]$hostIp) -or
        -not [Net.IPAddress]::TryParse([string]$connection.allowed_source,[ref]$sourceIp) -or
        $hostIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or $sourceIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
        [Net.IPAddress]::IsLoopback($hostIp) -or [Net.IPAddress]::IsLoopback($sourceIp) -or
        $hostIp.Equals($sourceIp) -or $hostIp.ToString() -eq '0.0.0.0' -or $sourceIp.ToString() -eq '0.0.0.0') {throw 'LINUX_COMPAT_EXTERNAL_TOPOLOGY_REQUIRED'}
    if (-not $PreparationDirectory) {$PreparationDirectory=Join-Path $root ('artifacts/diagnostics/linux-cts-compatibility-preparation-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
    $PreparationDirectory=Assert-PreparationPath $PreparationDirectory
    if (Test-Path -LiteralPath $PreparationDirectory) {throw 'LINUX_COMPAT_PREPARE_REQUIRES_FRESH_DIRECTORY'}
    $plan=[ordered]@{schema_version=1;method=$method;status='FILES_PREPARED_RUNTIME_PENDING';
        preparation_directory=$PreparationDirectory;created_at_utc=[DateTime]::UtcNow.ToString('o');
        connection_file=$ConnectionFile;connection_sha256=(File-Hash $ConnectionFile);
        known_hosts_sha256=(File-Hash $connection.known_hosts_path);
        public_key_sha256=(File-Hash ($connection.private_key_path+'.pub'));
        host=[string]$connection.host;allowed_source=[string]$connection.allowed_source;port=54122;
        requested_connections=4;transfer_bytes=524288;rate_bytes_per_second=65536;receiver_duration_seconds=120;endpoint_policy='guid-correlated';
        engine_sha256=$engineHash;receiver_sha256=$hashes['src/pb_cts_push_receiver.py'];control_sha256=$hashes['src/pb_linux_cts_control.py'];
        python_path=$python;python_sha256=(File-Hash $python);source_sha256=$hashes;
        product_started=$false;traffic_generated=$false;runtime_state_observed=$false;native_client_compatibility_verified=$false}
    $null=New-Item -ItemType Directory -Path $PreparationDirectory
    Write-Json $plan (Join-Path $PreparationDirectory 'plan.json')
    Write-Host ('Подготовлено: '+$PreparationDirectory)
    return
}
if (-not $PreparationDirectory) {throw 'LINUX_COMPAT_PREPARATION_DIRECTORY_REQUIRED'}
$PreparationDirectory=Assert-PreparationPath $PreparationDirectory
$planPath=Join-Path $PreparationDirectory 'plan.json'
$plan=Read-Json $planPath
if ($plan.schema_version -ne 1 -or $plan.method -cne $method -or $plan.status -cne 'FILES_PREPARED_RUNTIME_PENDING' -or
    $plan.preparation_directory -ine $PreparationDirectory -or $plan.engine_sha256 -cne $engineHash -or
    $plan.requested_connections -ne 4 -or $plan.transfer_bytes -ne 524288 -or $plan.rate_bytes_per_second -ne 65536 -or
    $plan.port -ne 54122 -or $plan.receiver_duration_seconds -ne 120 -or $plan.endpoint_policy -cne 'guid-correlated' -or $plan.python_path -ine $python -or
    $plan.python_sha256 -cne (File-Hash $python)) {throw 'LINUX_COMPAT_PLAN_BINDING_DIFFERS'}
if (@($plan.source_sha256.PSObject.Properties).Count -ne $hashes.Count) {throw 'LINUX_COMPAT_FROZEN_SET_DIFFERS'}
foreach ($file in $files) {
    if (-not $plan.source_sha256.PSObject.Properties[$file] -or $plan.source_sha256.$file -cne $hashes[$file]) {throw ('LINUX_COMPAT_FROZEN_FILE_CHANGED: '+$file)}
}
if ($plan.receiver_sha256 -cne $hashes['src/pb_cts_push_receiver.py'] -or $plan.control_sha256 -cne $hashes['src/pb_linux_cts_control.py'] -or
    (File-Hash $plan.connection_file) -cne $plan.connection_sha256) {throw 'LINUX_COMPAT_CONNECTION_OR_RECEIVER_CHANGED'}
$connection=Read-Json $plan.connection_file
if ($connection.host -cne $plan.host -or $connection.allowed_source -cne $plan.allowed_source -or
    (File-Hash $connection.known_hosts_path) -cne $plan.known_hosts_sha256 -or
    (File-Hash ($connection.private_key_path+'.pub')) -cne $plan.public_key_sha256) {throw 'LINUX_COMPAT_PRIVATE_CONNECTION_CHANGED'}
if ($Phase -eq 'Inspect') {
    [ordered]@{schema_version=1;status='FILES_VALIDATED';method=$method;plan_sha256=(File-Hash $planPath);
        product_started=$false;traffic_generated=$false;runtime_state_observed=$false;native_client_compatibility_verified=$false} | ConvertTo-Json
    return
}
# No state observation, process adapter construction, receiver or traffic before this gate.
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'LINUX_COMPAT_REQUIRES_USER_ADMINISTRATOR'}
Import-Module (Join-Path $root 'modules/Env.psm1')
Import-Module (Join-Path $root 'modules/ProductBuild.psm1')
Import-Module (Join-Path $root 'modules/InterceptionState.psm1')
Import-Module (Join-Path $root 'modules/ProcessAdapter.psm1')
$environment=Import-DotEnv $envPath
$identity=Get-ProductBuildIdentity -Environment $environment -Contract driver
if (-not $identity.files_verified -or $identity.declared_source_commit -cne '63be0ebf9bec92bfba95ef3d6729c375aa9af84e') {throw 'LINUX_COMPAT_BASELINE_KIT_REQUIRED'}
$environment['PB_WINDIVERT_CTL_EXE']=Join-Path $root 'bin/tools/windivert-2.2.2/windivertctl.exe'
$environment['PB_EXPECTED_WINDIVERT_CTL_SHA256']='f27980b00d97e3f6a590cf4fad04f30f4c61c72324d52af2442afdcf69f31765'
$environment['PB_EXPECTED_WINDIVERT_OBSERVER_DLL_SHA256']='c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
function Assert-Off([string]$Directory,[string]$Stage) {
    $state=Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    $processes=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe'))
    Write-Json $state (Join-Path $Directory ('interception-'+$Stage+'.json'))
    Write-Json $loaded (Join-Path $Directory ('loaded-drivers-'+$Stage+'.json'))
    Write-Json @($processes | Select-Object ProcessId,Name,ExecutablePath) (Join-Path $Directory ('product-processes-'+$Stage+'.json'))
    if (-not $state.current_driver_preparation_allowed -or -not $state.wfp_detachment_observed -or $state.wfp.service_state -ne 'Stopped' -or
        -not $state.windivert.configured -or -not $state.windivert.files_verified -or -not $state.windivert.capture_complete -or
        $state.windivert.status -ne 'NO_HANDLES_OBSERVED' -or $state.windivert.observed_handle_count -ne 0 -or
        -not $loaded.query_complete -or -not $loaded.known_interception_driver_names_absent -or $processes.Count) {throw 'LINUX_COMPAT_REQUIRES_CONFIRMED_PRODUCT_OFF'}
}
function Assert-RebootHistory {
    $boot=[DateTimeOffset](([DateTime](Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5).LastBootUpTime).ToUniversalTime())
    $diagnostics=Join-Path $root 'artifacts/diagnostics'
    foreach ($directory in @(Get-ChildItem -LiteralPath $diagnostics -Directory -Filter 'tcp-redirect-context-preparation-*')) {
        $path=Join-Path $directory.FullName 'kernel-installation.json'
        if (-not (Test-Path -LiteralPath $path)) {continue}
        $record=Read-Json $path
        if ($record.status -ne 'RESTORED_BASELINE_REBOOT_RECOMMENDED' -or
            $boot -le [DateTimeOffset]::Parse([string]$record.completed_at_utc)) {throw 'LINUX_COMPAT_REBOOT_AFTER_DIAGNOSTIC_RESTORE_REQUIRED'}
    }
    $history=@(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/local-route') -Directory | Where-Object Name -match '(?:4\.0\.0|v4\.0\.0)')
    foreach ($directory in $history) {
        $file=Join-Path $directory.FullName 'comparison-manifest.json'
        if ((Test-Path -LiteralPath $file) -and $boot -le [DateTimeOffset](Get-Item -LiteralPath $file).LastWriteTimeUtc) {throw 'LINUX_COMPAT_REBOOT_AFTER_LEGACY_REQUIRED'}
    }
    foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/benchmark-launch') -Directory -Filter 'plan-*-control')) {
        $file=Join-Path $directory.FullName 'job.json'
        if (-not (Test-Path -LiteralPath $file)) {continue}
        $job=Read-Json $file
        if ($job.status -in @('STARTING','RUNNING','STOPPING','INTERRUPTED') -and $boot -le [DateTimeOffset]::Parse([string]$job.updatedAtUtc)) {throw 'LINUX_COMPAT_REBOOT_AFTER_INTERRUPTED_RUN_REQUIRED'}
    }
}
$launchRoot=Join-Path $root 'artifacts/benchmark-launch'
Assert-NoReparse $launchRoot
$null=New-Item -ItemType Directory -Path $launchRoot -Force
$mutex=[Threading.Mutex]::new($false,'Global\ProxyBridgeTestLabPlannedBenchmark')
$owns=$false;$lease=$null;$evidence=$null;$startAttempted=$false;$manifest=$null
try {
    try {$owns=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$owns=$true}
    if (-not $owns) {throw 'LAB_PLANNED_RUN_ALREADY_ACTIVE'}
    $leasePath=Join-Path $launchRoot 'execution.lock';Assert-NoReparse $leasePath
    $lease=[IO.File]::Open($leasePath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    Assert-RebootHistory
    $runId='compat-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $evidence=Join-Path $root ('artifacts/diagnostics/linux-cts-'+$runId)
    Assert-NoReparse $evidence
    $null=New-Item -ItemType Directory -Path $evidence
    Copy-Item -LiteralPath $planPath -Destination (Join-Path $evidence 'sealed-plan.json')
    $manifest=[ordered]@{schema_version=1;method=$method;status='RUNNING';started_at_utc=[DateTime]::UtcNow.ToString('o');
        receiver_run_id=$runId;plan_sha256=(File-Hash $planPath);product_started=$false;errors=@()}
    Write-Json $manifest (Join-Path $evidence 'run-manifest.json')
    try {
        Assert-Off $evidence 'before'
        $inspect=Read-JsonText (& (Join-Path $PSScriptRoot 'Invoke-LinuxCtsReceiver.ps1') -Phase Inspect -ConnectionFile $plan.connection_file)
        Write-Json $inspect (Join-Path $evidence 'receiver-inspect.json')
        $startAttempted=$true
        $started=Read-JsonText (& (Join-Path $PSScriptRoot 'Invoke-LinuxCtsReceiver.ps1') -Phase Start -ConnectionFile $plan.connection_file -RunId $runId -TransferBytes 524288 -MaxConnections 4 -MaxTotalConnections 4 -MaxDurationSeconds 120)
        Write-Json $started (Join-Path $evidence 'receiver-start.json')
        $csv=Join-Path $evidence 'client.csv'
        $arguments=@(('-target:'+$plan.host),'-port:54122','-protocol:tcp','-pattern:push','-transfer:524288','-ratelimit:65536','-buffer:65536','-verify:data','-connections:4','-iterations:1','-throttleconnections:32','-conn:ConnectEx','-shutdown:rude','-consoleverbosity:1','-statusupdate:250',('-connectionfilename:'+$csv))
        Write-Json ([ordered]@{executable=$engine;engine_sha256=$engineHash;arguments=$arguments;csv_path=$csv}) (Join-Path $evidence 'client-launch.json')
        $adapter=New-SystemProcessAdapter
        $client=& $adapter.Invoke ([pscustomobject]@{executable=$engine;arguments=$arguments;timeout_ms=60000;stop_timeout_ms=5000;actual_path_timeout_ms=2000})
        $client | Add-Member -NotePropertyName forced_stop -NotePropertyValue ([bool]$client.timed_out)
        $client | Add-Member -NotePropertyName actual_executable_sha256 -NotePropertyValue $(if ($client.actual_path -and (Test-Path -LiteralPath $client.actual_path)) {File-Hash $client.actual_path} else {''})
        Write-Json $client (Join-Path $evidence 'client-process.json')
        if ($client.exit_code -ne 0 -or $client.timed_out -or -not $client.output_capture_complete) {throw 'LINUX_COMPAT_NATIVE_FAILED_OR_CAPTURE_INCOMPLETE'}
    } catch {$manifest.errors+=([string]$_.Exception.Message)}
    finally {
        if ($startAttempted) {
            try {
                $stopped=Read-JsonText (& (Join-Path $PSScriptRoot 'Invoke-LinuxCtsReceiver.ps1') -Phase Stop -ConnectionFile $plan.connection_file -RunId $runId)
                Write-Json $stopped (Join-Path $evidence 'receiver-stop.json')
            } catch {$manifest.errors+=('STOP: '+$_.Exception.Message)}
            try {$null=& (Join-Path $PSScriptRoot 'Invoke-LinuxCtsReceiver.ps1') -Phase Collect -ConnectionFile $plan.connection_file -RunId $runId -EvidenceDirectory (Join-Path $evidence 'receiver')}
            catch {$manifest.errors+=('COLLECT: '+$_.Exception.Message)}
        }
        try {Assert-Off $evidence 'after'} catch {$manifest.errors+=('AFTER: '+$_.Exception.Message)}
        $manifest.status=$(if ($manifest.errors.Count) {'FAILED'} else {'COMPLETED'})
        $manifest['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
        Write-Json $manifest (Join-Path $evidence 'run-manifest.json')
    }
    & $python -B (Join-Path $root 'src/pb_linux_cts_compatibility_report.py') --evidence $evidence --endpoint-policy guid-correlated
    $reportExit=$LASTEXITCODE
    Write-Host ('Отчёт: '+(Join-Path $evidence 'summary.md'))
    if ($reportExit -ne 0) {throw 'LINUX_COMPATIBILITY_NOT_CONFIRMED'}
} finally {
    if ($lease) {$lease.Dispose()}
    if ($owns) {$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
