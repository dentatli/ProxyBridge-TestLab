[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^plan-[a-f0-9]{32}$')][string]$PlanId,
    [ValidateSet('Inspect','Run')][string]$Phase='Inspect'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$root=Split-Path -Parent $PSScriptRoot
function Assert-NoReparse([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'LAB_PLAN_REPARSE_POINT' }
        }
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Read-Json([string]$Path) {
    Assert-NoReparse $Path
    if ((Get-Item -LiteralPath $Path).Length -gt 1MB) { throw 'LAB_PLAN_JSON_SIZE_LIMIT' }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}
function Assert-Hash([string]$Path,[string]$Expected) {
    Assert-NoReparse $Path
    if ($Expected -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $Path).Hash -ine $Expected) { throw 'LAB_PLAN_FILES_CHANGED_PREPARE_AGAIN' }
}
function Receive-LabControllerOutput($Child,$StdoutWriter,$StderrWriter) {
    $outTask=$Child.StandardOutput.ReadLineAsync();$errTask=$Child.StandardError.ReadLineAsync()
    $drainTimer=$null
    $captureComplete=$true
    while (-not $Child.HasExited -or $null -ne $outTask -or $null -ne $errTask) {
        if ($null -ne $outTask -and $outTask.IsCompleted) {
            $line=$outTask.GetAwaiter().GetResult()
            if ($null -eq $line) { $outTask=$null }
            else {
                try { $StdoutWriter.WriteLine($line) }
                catch { $captureComplete=$false;$StdoutWriter=[IO.TextWriter]::Null;Write-Warning 'Controller stdout log write failed; waiting for controller cleanup.' }
                Write-Host $line;$outTask=$Child.StandardOutput.ReadLineAsync()
            }
        }
        if ($null -ne $errTask -and $errTask.IsCompleted) {
            $line=$errTask.GetAwaiter().GetResult()
            if ($null -eq $line) { $errTask=$null }
            else {
                try { $StderrWriter.WriteLine($line) }
                catch { $captureComplete=$false;$StderrWriter=[IO.TextWriter]::Null;Write-Warning 'Controller stderr log write failed; waiting for controller cleanup.' }
                Write-Host $line -ForegroundColor Red;$errTask=$Child.StandardError.ReadLineAsync()
            }
        }
        if (-not $Child.HasExited) { $null=$Child.WaitForExit(50) }
        elseif ($null -ne $outTask -or $null -ne $errTask) {
            if ($null -eq $drainTimer) { $drainTimer=[Diagnostics.Stopwatch]::StartNew() }
            if ($drainTimer.ElapsedMilliseconds -gt 15000) { return $false }
            Start-Sleep -Milliseconds 10
        }
    }
    $Child.WaitForExit()
    return $captureComplete
}
$plan=Read-Json (Join-Path $root ('artifacts/benchmark-launch/'+$PlanId+'.json'))
if ($plan.schema_version -ne 1 -or $plan.id -ne $PlanId -or $plan.contract -ne 'driver' -or $plan.mode -ne 'local' -or
    $plan.preparation_scope -ne 'files-on-disk' -or $plan.runtime_ready) { throw 'LAB_PLAN_CONTRACT_INVALID' }
$controllers=@{
    tcp_transfer=@('Invoke-LocalTcpBenchmark.ps1','SMOKE')
    tcp_rtt=@('Invoke-LocalTcpRtt.ps1','SMOKE')
    tcp_rtt_three_modes=@('Invoke-LocalTcpRtt.ps1','SMOKE')
    tcp_connections=@('Invoke-LocalTcpConnections.ps1','SMOKE')
    tcp_loaded_rtt=@('Invoke-LocalTcpLoadedRtt.ps1','SMOKE')
    udp_echo=@('Invoke-LocalUdpSoak.ps1','MULTI_TARGET')
}
if (-not $controllers.ContainsKey([string]$plan.scenario)) { throw 'LAB_PLAN_SCENARIO_INVALID' }
$definition=$controllers[[string]$plan.scenario]
if ($plan.controller_file -ne $definition[0] -or $plan.profile -ne $definition[1]) { throw 'LAB_PLAN_CONTROLLER_INVALID' }
$controller=Join-Path $PSScriptRoot $definition[0]
$kit=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli'
$envPath=Join-Path $kit 'product.env'
Assert-Hash $controller $plan.controller_sha256
Assert-Hash $PSCommandPath $plan.entry_sha256
$controllerHost=Join-Path $PSScriptRoot 'Invoke-BenchmarkControllerHost.ps1'
Assert-Hash $controllerHost $plan.host_sha256
Assert-Hash $envPath $plan.env_sha256
$workload=$null
if ($plan.scenario -eq 'tcp_connections' -and (-not $plan.PSObject.Properties['workload_preset'] -or $null -eq $plan.workload_preset)) { throw 'LAB_WORKLOAD_INVALID' }
if ($plan.PSObject.Properties['workload_preset'] -and $null -ne $plan.workload_preset) {
    if ($plan.scenario -notin @('tcp_transfer','tcp_rtt','tcp_rtt_three_modes','tcp_connections')) { throw 'LAB_WORKLOAD_INVALID' }
    $catalogPath=Join-Path $root 'config/benchmark-workloads.json'
    $modulePath=Join-Path $root $(if ($plan.scenario -eq 'tcp_connections') {'modules/ConnectionLoad.psm1'} else {'modules/BenchmarkWorkload.psm1'})
    if ($plan.scenario -ne 'tcp_connections') { Assert-Hash $catalogPath $plan.workload_catalog_sha256 }
    else { Assert-Hash (Join-Path $root 'src/pb_controlled_tcp_proxy.py') $plan.connection_proxy_sha256;Assert-Hash (Join-Path $root 'src/pb_tcp_connections_report.py') $plan.connection_report_sha256 }
    Assert-Hash $modulePath $plan.workload_module_sha256
    Import-Module $modulePath
    $workload=$(if ($plan.scenario -eq 'tcp_connections') {Get-ConnectionLoadPreset -Duration $plan.workload_preset.duration -Load $plan.workload_preset.load} else {Get-BenchmarkWorkload -Duration $plan.workload_preset.duration -Load $plan.workload_preset.load})
    if (@($plan.workload_preset.PSObject.Properties).Count -ne $workload.Count) { throw 'LAB_WORKLOAD_INVALID' }
    foreach ($key in $workload.Keys) {
        if (-not $plan.workload_preset.PSObject.Properties[$key] -or [string]$plan.workload_preset.$key -cne [string]$workload[$key]) { throw 'LAB_WORKLOAD_INVALID' }
    }
}
Import-Module (Join-Path $root 'modules/Env.psm1')
Import-Module (Join-Path $root 'modules/ProductBuild.psm1')
$environment=Import-DotEnv $envPath
if ($environment['PB_PROXYBRIDGE_CLI_EXE'] -ine (Join-Path $kit 'ProxyBridge_CLI.exe') -or
    $environment['PB_DRIVER_PATH'] -ine (Join-Path $kit 'ProxyBridgeDrv.sys') -or
    $environment['PB_PROXYBRIDGE_SERVICE'] -ne 'ProxyBridgeDrv' -or
    $environment['PB_PROXYBRIDGE_SOURCE_COMMIT'] -ne '63be0ebf9bec92bfba95ef3d6729c375aa9af84e' -or
    $environment['PB_PROXYBRIDGE_CLI_VARIANT'] -ne 'testlab-unbuffered-v1' -or $environment['PB_PROXYBRIDGE_EXE']) { throw 'LAB_PLAN_KIT_CONFIGURATION_CHANGED' }
foreach ($component in @('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys')) { Assert-NoReparse (Join-Path $kit $component) }
$identity=Get-ProductBuildIdentity -Environment $environment -Contract driver
if (-not $identity.files_verified -or $identity.bundle_sha256 -ne $plan.bundle_sha256) { throw 'LAB_PLAN_SELECTED_KIT_CHANGED' }
if ($Phase -eq 'Inspect') {
    [ordered]@{status='PLAN_FILES_VALIDATED';plan_id=$PlanId;scenario=$plan.scenario;profile=$plan.profile;files_observed=$true;
        runtime_ready=$false;product_started=$false;traffic_generated=$false;driver_state_observed=$false} | ConvertTo-Json -Compress
    return
}
# Only an explicit Run phase can query runtime or invoke the existing controller.
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'LAB_RUN_REQUIRES_ADMINISTRATOR' }
$mutex=[Threading.Mutex]::new($false,'Global\ProxyBridgeTestLabPlannedBenchmark')
$ownsMutex=$false
$executionLease=$null
try {
    try { $ownsMutex=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex=$true }
    if (-not $ownsMutex) { throw 'LAB_PLANNED_RUN_ALREADY_ACTIVE' }
    $leasePath=Join-Path $root 'artifacts/benchmark-launch/execution.lock'
    Assert-NoReparse $leasePath
    try { $executionLease=[IO.File]::Open($leasePath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { throw 'LAB_OTHER_REAL_RUN_ACTIVE_OR_LEASE_UNAVAILABLE' }
    # Preserve the reboot policy against recorded 4.0.0 activity, including failed attempts.
    # This is a scoped history check, not proof about unrecorded external product launches.
    $history=[Collections.Generic.List[string]]::new()
    $localRoot=Join-Path $root 'artifacts/local-route'
    Assert-NoReparse $localRoot
    foreach ($directory in @(Get-ChildItem -LiteralPath $localRoot -Directory)) {
        if ($directory.Name -match '(?:4\.0\.0|v4\.0\.0)') {
            $file=Join-Path $directory.FullName 'comparison-manifest.json'
            if (Test-Path -LiteralPath $file -PathType Leaf) { $history.Add($file) }
        }
    }
    $versionRoot=Join-Path $root 'artifacts/version-comparison'
    Assert-NoReparse $versionRoot
    foreach ($preflight in @(Get-ChildItem -LiteralPath $versionRoot -Directory -Filter 'preflight-*')) {
        Assert-NoReparse $preflight.FullName
        foreach ($lifecycle in @(Get-ChildItem -LiteralPath $preflight.FullName -Directory -Filter 'legacy-lifecycle-*')) {
            $file=Join-Path $lifecycle.FullName 'lifecycle-receipt.json'
            if (Test-Path -LiteralPath $file -PathType Leaf) { $history.Add($file) }
        }
    }
    $latestLegacy=[DateTimeOffset]::MinValue
    foreach ($file in $history) {
        $record=Read-Json $file
        foreach ($property in @('started_at_utc','completed_at_utc')) {
            if ($record.PSObject.Properties[$property] -and $record.$property) {
                $timestamp=[DateTimeOffset]::Parse([string]$record.$property)
                if ($timestamp -gt $latestLegacy) { $latestLegacy=$timestamp }
            }
        }
        # A receipt can be written after product execution; include interrupted attempts.
        $written=[DateTimeOffset](Get-Item -LiteralPath $file).LastWriteTimeUtc
        if ($written -gt $latestLegacy) { $latestLegacy=$written }
    }
    $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5
    $boot=[DateTimeOffset](([DateTime]$os.LastBootUpTime).ToUniversalTime())
    if ($boot -le $latestLegacy) { throw 'LAB_REBOOT_REQUIRED_AFTER_RECORDED_4_0_0' }
    foreach ($control in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/benchmark-launch') -Directory -Filter 'plan-*-control')) {
        if ($control.Name -eq $PlanId+'-control') { continue }
        $stateFile=Join-Path $control.FullName 'job.json'
        if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
            $state=Read-Json $stateFile
            if ($state.status -in @('STARTING','RUNNING','STOPPING','INTERRUPTED') -and $boot -le [DateTimeOffset]::Parse([string]$state.updatedAtUtc)) {
                throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_RUN'
            }
        }
    }
    foreach ($control in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/benchmark-launch') -Directory -Filter 'suite-*-control')) {
        $stateFile=Join-Path $control.FullName 'job.json'
        if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
            $state=Read-Json $stateFile
            if ($state.status -eq 'INTERRUPTED' -and $boot -le [DateTimeOffset]::Parse([string]$state.updatedAtUtc)) {
                throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_RUN'
            }
        }
    }
    $evidence=Join-Path $localRoot ('lab-'+$plan.scenario+'-'+$plan.profile.ToLowerInvariant()+'-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$PlanId.Substring(5,8))
    if (Test-Path -LiteralPath $evidence) { throw 'LAB_PLAN_ALREADY_EXECUTED_PREPARE_AGAIN' }
    # A durable one-use claim prevents a second execution of this plan under a new timestamp.
    $attemptRoot=Join-Path $root ('artifacts/benchmark-launch/'+$PlanId+'-run')
    Assert-NoReparse $attemptRoot
    $null=New-Item -ItemType Directory -Path $attemptRoot -ErrorAction Stop
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$controllerHost,'-Scenario',[string]$plan.scenario,'-Profile',[string]$plan.profile,'-EnvPath',$envPath,'-EvidenceDirectory',$evidence)
    if ($workload) { $arguments+=@('-Duration',[string]$workload.duration,'-Load',[string]$workload.load) }
    if ($plan.scenario -in @('tcp_rtt','tcp_transfer','tcp_rtt_three_modes','tcp_connections')) {
        $cancelPath=Join-Path $root ('artifacts/benchmark-launch/'+$PlanId+'-control/cancel.request')
        Assert-NoReparse $cancelPath
        $arguments+=@('-CancellationPath',$cancelPath)
    }
    Import-Module (Join-Path $root 'modules/ProcessAdapter.psm1')
    $hostRoot=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0'
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=Join-Path $hostRoot 'powershell.exe'
    $info.Arguments=Join-ProcessArguments $arguments
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true
    $info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
    $info.WorkingDirectory=$root
    $info.EnvironmentVariables['PSModulePath']=Join-Path $hostRoot 'Modules'
    Write-Host ('Results / Результаты: '+$evidence)
    Write-Host 'Existing controller checks remain mandatory / Все проверки контроллера сохранены.'
    $stdoutWriter=[IO.StreamWriter]::new((Join-Path $attemptRoot 'controller-stdout.log'),$false,[Text.UTF8Encoding]::new($false))
    $stderrWriter=[IO.StreamWriter]::new((Join-Path $attemptRoot 'controller-stderr.log'),$false,[Text.UTF8Encoding]::new($false))
    $stdoutWriter.AutoFlush=$true;$stderrWriter.AutoFlush=$true
    $processReceipt=[ordered]@{plan_id=$PlanId;scenario=$plan.scenario;evidence_directory=$evidence;started_at_utc=[DateTime]::UtcNow.ToString('o');completed_at_utc=$null;pid=$null;status='STARTING';exit_code=$null;output_capture_complete=$false;error=''}
    $receiptPath=Join-Path $attemptRoot 'controller-process.json'
    $processReceipt | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    try {
        $child=[Diagnostics.Process]::Start($info)
        $processReceipt.status='RUNNING'
        $processReceipt.pid=$child.Id
        $processReceipt | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding UTF8
        $captured=Receive-LabControllerOutput $child $stdoutWriter $stderrWriter
        $processReceipt.exit_code=$child.ExitCode
        $processReceipt.output_capture_complete=$captured
        $processReceipt.status=$(if (-not $captured) {'OUTPUT_INCOMPLETE'} elseif ($child.ExitCode -eq 0) {'EXITED'} else {'CONTROLLER_FAILED'})
    }
    catch { $processReceipt.status='OUTPUT_OR_START_FAILED';$processReceipt.error=$_.Exception.Message;throw }
    finally {
        $processReceipt.completed_at_utc=[DateTime]::UtcNow.ToString('o')
        $stdoutWriter.Dispose();$stderrWriter.Dispose()
        $processReceipt | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    }
    Write-Host ('Controller exit / Код завершения контроллера: '+$processReceipt.exit_code)
    $summaryPath=Join-Path $evidence 'summary.md'
    if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { Write-Host ('Report / Отчёт: '+$summaryPath) }
    else { Write-Host 'Данные сохранены в папке запуска; итог сравнения не составлен / Evidence retained; no comparison summary.' }
    # Exit code and workload verdict stay distinct; the saved evaluator remains authoritative.
    if (-not $processReceipt.output_capture_complete) { throw 'LAB_CONTROLLER_OUTPUT_CAPTURE_INCOMPLETE' }
    exit $processReceipt.exit_code
}
finally {
    if ($null -ne $executionLease) { $executionLease.Dispose() }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
