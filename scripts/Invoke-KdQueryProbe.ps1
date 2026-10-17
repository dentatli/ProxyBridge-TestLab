[CmdletBinding()]
param([ValidateSet('Prepare','Inspect','Run')][string]$Phase='Inspect',
    [string]$PreparationDirectory='',[switch]$QueryProfileReviewed,[switch]$DebuggerLoggerEnabled)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
function Assert-PlainPath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'KD_QUERY_PROBE_REPARSE_PATH'}
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Read-Json([string]$Path) {
    Assert-PlainPath $Path
    if ((Get-Item -LiteralPath $Path).Length -gt 16MB) {throw 'KD_QUERY_PROBE_JSON_TOO_LARGE'}
    $text=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {return ConvertFrom-Json -InputObject $text -DateKind String}
    return ConvertFrom-Json -InputObject $text
}
if (-not $PreparationDirectory) {
    if ($Phase -ne 'Prepare') {throw 'KD_QUERY_PROBE_PREPARATION_REQUIRED'}
    $PreparationDirectory=Join-Path $root ('artifacts/diagnostics/pb-kd-query-probe-preparation-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
}
$PreparationDirectory=[IO.Path]::GetFullPath($PreparationDirectory)
$prefix=[IO.Path]::GetFullPath((Join-Path $root 'artifacts/diagnostics'))+[IO.Path]::DirectorySeparatorChar
if (-not $PreparationDirectory.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $PreparationDirectory) -notmatch '^pb-kd-query-probe-preparation-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') {throw 'KD_QUERY_PROBE_DIRECTORY_INVALID'}
Assert-PlainPath $PreparationDirectory
if ($Phase -eq 'Prepare') {
    $sourcePython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    & $sourcePython -B (Join-Path $root 'src/pb_prepare_kd_query_probe.py') --root $root --output $PreparationDirectory --python $sourcePython
    if ($LASTEXITCODE -ne 0) {throw 'KD_QUERY_PROBE_PREPARATION_FAILED'}
}
$planPath=Join-Path $PreparationDirectory 'runtime-plan.json'
$plan=Read-Json $planPath
$python=Join-Path $PreparationDirectory 'runtime/python/python.exe'
if ($plan.schema_version -ne 1 -or $plan.method -cne 'redirect-kd-query-four-v1' -or -not $plan.diagnostic_only -or $plan.performance_comparable -or
    $plan.root -ine $root -or $plan.preparation -ine $PreparationDirectory -or $plan.python -ine $python -or $plan.files.Count -lt 50) {throw 'KD_QUERY_PROBE_PLAN_INVALID'}
$policy=$plan.control_policy
if ($policy.method -cne 'redirect-kd-query-four-v1' -or ($policy.phase_connections -join ',') -cne '4' -or
    $policy.total_connections -ne 4 -or @($policy.load_levels).Count -ne 0 -or $policy.hold_seconds -ne 8 -or
    $policy.connect_method -cne 'ConnectEx' -or $policy.pending_limit -ne 32 -or -not $policy.original_single_query -or
    $policy.listener_case -cne 'original' -or $policy.listener_delay_ms -ne 0 -or $policy.debugger_points -cne 'query-read-status-only' -or
    ($policy.active_point_ids -join ',') -cne '3,4' -or ($policy.registered_point_ids -join ',') -cne '0,1,2,3,4,5,6' -or
    $policy.load_authorized -or -not $policy.logger_verification_required_before_load -or
    $policy.cohort_budget_ms -ne 180000 -or $policy.client_wait_limit_ms -ne 60000 -or $policy.final_four_same_session -or
    $policy.driver_installation -or $policy.automatic_debugger_control -or -not $policy.diagnostic_only -or $policy.performance_comparable) {throw 'KD_QUERY_PROBE_POLICY_INVALID'}
$seen=@{}
foreach ($file in $plan.files) {
    Assert-PlainPath $file.path
    if ($seen.ContainsKey([string]$file.path) -or $file.sha256 -notmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $file.path).Hash -ine $file.sha256) {throw 'KD_QUERY_PROBE_FROZEN_FILE_CHANGED'}
    $seen[[string]$file.path]=$true
}
foreach ($required in @('scripts/Invoke-KdQueryProbe.ps1','scripts/Invoke-KdQueryProbeWorkload.ps1',
    'modules/KdQueryProbeConnectionLoad.psm1','modules/InterceptionState.psm1','src/pb_prepare_kd_query_probe.py',
    'src/pb_kd_query_probe_report.py','src/pb_tcp_redirect_context_report.py')) {
    if (-not $seen.ContainsKey((Join-Path $root $required))) {throw 'KD_QUERY_PROBE_CONTRACT_NOT_FROZEN'}
}
$runtimeRoot=Join-Path $PreparationDirectory 'runtime/python'
$runtimeManifestPath=Join-Path $PreparationDirectory 'runtime/manifest.json'
if (-not $seen.ContainsKey($runtimeManifestPath) -or $plan.runtime_manifest_sha256 -notmatch '^[a-f0-9]{64}$' -or
    (Get-FileHash -LiteralPath $runtimeManifestPath).Hash -ine $plan.runtime_manifest_sha256) {throw 'KD_QUERY_PROBE_RUNTIME_MANIFEST_CHANGED'}
$runtimeManifest=Read-Json $runtimeManifestPath
$runtimeEntries=@($runtimeManifest.files.PSObject.Properties)
$actualRuntime=@(Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File -Force)
if ($runtimeEntries.Count -ne $runtimeManifest.copied_files -or $actualRuntime.Count -ne $runtimeEntries.Count -or
    -not $runtimeManifest.isolated_pth -or $runtimeManifest.import_site -or $runtimeManifest.source_runtime_reused_at_run) {throw 'KD_QUERY_PROBE_RUNTIME_INVENTORY_CHANGED'}
foreach ($entry in $runtimeEntries) {
    $path=[IO.Path]::GetFullPath((Join-Path $runtimeRoot $entry.Name))
    if (-not $path.StartsWith(([IO.Path]::GetFullPath($runtimeRoot)+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or
        -not $seen.ContainsKey($path) -or $entry.Value -notmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $path).Hash -ine $entry.Value) {throw 'KD_QUERY_PROBE_RUNTIME_FILE_CHANGED'}
}
$profilePath=Join-Path $root 'scripts/debugger/pb-kd-query-profile-20261017.json'
if (-not $seen.ContainsKey($profilePath)) {throw 'KD_QUERY_PROBE_PROFILE_NOT_FROZEN'}
$profile=Read-Json $profilePath
if ($profile.method -cne 'redirect-kd-query-four-v1' -or ($profile.active_point_ids -join ',') -cne '3,4' -or
    ($profile.expected_registered_ids -join ',') -cne '0,1,2,3,4,5,6' -or $profile.stage_reload_allowed -or
    $profile.current_host_inventory_verified -or $profile.reduced_profile_run_verified -or $profile.lifecycle_coverage_verified -or
    $profile.points.Count -ne 2 -or ($profile.disabled_point_ids -join ',') -cne '0,1,2,5,6' -or
    ($profile.control_policy | ConvertTo-Json -Depth 8 -Compress) -cne ($policy | ConvertTo-Json -Depth 8 -Compress)) {throw 'KD_QUERY_PROBE_PROFILE_INVALID'}
$saved=Join-Path $PreparationDirectory 'debugger-evidence'
foreach ($name in @('registration-console.txt','four-connection-console.txt','registered-profile.json')) {
    if (-not $seen.ContainsKey((Join-Path $saved $name))) {throw 'KD_QUERY_PROBE_HISTORICAL_EVIDENCE_NOT_FROZEN'}
}
if ((Get-FileHash -LiteralPath (Join-Path $saved 'registration-console.txt')).Hash -ine '0d025fe96d87a5726bba8ee25c479bab69b2c11fe4f6a5ad20b6b72b7936fe1d' -or
    (Get-FileHash -LiteralPath (Join-Path $saved 'four-connection-console.txt')).Hash -ine '8f99491a32a0c3f9aa0292acdb885f1b57a5c2825cbc08d5d91c532d6039c71c') {throw 'KD_QUERY_PROBE_HISTORICAL_EVIDENCE_DIFFERS'}
$registered=Read-Json (Join-Path $saved 'registered-profile.json')
for ($index=0;$index -lt 2;$index++) {
    $id=@(3,4)[$index]
    if ($profile.points[$index].id -ne $id -or $profile.points[$index].action -cne $registered.points[$id].action -or
        $profile.points[$index].target -cne $registered.points[$id].target) {throw 'KD_QUERY_PROBE_SELECTED_ACTION_DIFFERS'}
}
$kit=Join-Path $PreparationDirectory 'kit'
$receipt=Read-Json (Join-Path $kit 'redirect-context-diagnostic.json')
if ($receipt.method -cne 'redirect-kd-query-four-v1' -or
    ($receipt.control_policy | ConvertTo-Json -Depth 8 -Compress) -cne ($policy | ConvertTo-Json -Depth 8 -Compress)) {throw 'KD_QUERY_PROBE_RECEIPT_POLICY_DIFFERS'}
$pinned=@{'ProxyBridge_CLI.exe'='ad83b3aad22252be0ab20a6c26470f7c364930af35089e9904f1dd0d29bb40ca';
    'ProxyBridgeCore.dll'='7dc8952e7562ac4dff3cf278136d1fe8fd44474885f707c93c220f94e9f624ed';
    'ProxyBridgeDrv.sys'='3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e'}
if ($receipt.components.Count -ne 3) {throw 'KD_QUERY_PROBE_COMPONENT_COUNT_INVALID'}
$components=@{}
foreach ($component in $receipt.components) {
    if (-not $pinned.ContainsKey([string]$component.name) -or $components.ContainsKey([string]$component.name) -or
        $component.sha256 -cne $pinned[[string]$component.name] -or
        (Get-FileHash -LiteralPath (Join-Path $kit $component.name)).Hash -ine $component.sha256) {throw 'KD_QUERY_PROBE_COMPONENT_DIFFERS'}
    $components[[string]$component.name]=$true
}
foreach ($name in @('product.env','redirect-context-diagnostic.json','ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys')) {
    if (-not $seen.ContainsKey((Join-Path $kit $name))) {throw 'KD_QUERY_PROBE_KIT_NOT_FROZEN'}
}
if ($Phase -ne 'Run') {
    [ordered]@{status='KD_QUERY_PROBE_FILES_VALIDATED';preparation_directory=$PreparationDirectory;files=$plan.files.Count;
        runtime_files=$runtimeEntries.Count;connections=4;product_started=$false;driver_installed=$false;
        traffic_generated=$false;debugger_control=$false;runtime_ready=$false} | ConvertTo-Json
    return
}
if (-not $QueryProfileReviewed -or -not $DebuggerLoggerEnabled) {throw 'KD_QUERY_PROBE_REQUIRES_USER_REVIEWED_PROFILE_AND_ENABLED_3_4'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'KD_BASELINE_RUN_REQUIRES_ADMINISTRATOR'}
$mutex=[Threading.Mutex]::new($false,'Global\ProxyBridgeTestLabPlannedBenchmark')
$owns=$false;$lease=$null
$previousRoute=[Environment]::GetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','Process')
try {
    try {$owns=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$owns=$true}
    if (-not $owns) {throw 'LAB_PLANNED_RUN_ALREADY_ACTIVE'}
    $leasePath=Join-Path $root 'artifacts/benchmark-launch/execution.lock';Assert-PlainPath $leasePath
    try {$lease=[IO.File]::Open($leasePath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch {throw 'LAB_OTHER_REAL_RUN_ACTIVE_OR_LEASE_UNAVAILABLE'}
    # Retain the existing cross-boot legacy/interrupted-run gates.
    $history=@()
    foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/local-route') -Directory)) {
        if ($directory.Name -match '(?:4\.0\.0|v4\.0\.0)') {
            $file=Join-Path $directory.FullName 'comparison-manifest.json'
            if (Test-Path -LiteralPath $file) {$history+=$file}
        }
    }
    foreach ($preflight in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/version-comparison') -Directory -Filter 'preflight-*')) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $preflight.FullName -Directory -Filter 'legacy-lifecycle-*')) {
            $file=Join-Path $directory.FullName 'lifecycle-receipt.json'
            if (Test-Path -LiteralPath $file) {$history+=$file}
        }
    }
    $latestLegacy=[DateTimeOffset]::MinValue
    foreach ($file in $history) {
        $saved=Read-Json $file
        foreach ($name in @('started_at_utc','completed_at_utc')) {
            if ($saved.PSObject.Properties[$name] -and $saved.$name) {
                $time=[DateTimeOffset]::Parse([string]$saved.$name);if ($time -gt $latestLegacy) {$latestLegacy=$time}
            }
        }
        $written=[DateTimeOffset](Get-Item -LiteralPath $file).LastWriteTimeUtc
        if ($written -gt $latestLegacy) {$latestLegacy=$written}
    }
    $boot=[DateTimeOffset](([DateTime](Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5).LastBootUpTime).ToUniversalTime())
    if ($boot -le $latestLegacy) {throw 'LAB_REBOOT_REQUIRED_AFTER_RECORDED_4_0_0'}
    foreach ($control in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/benchmark-launch') -Directory -Filter '*-control')) {
        $file=Join-Path $control.FullName 'job.json'
        if (Test-Path -LiteralPath $file) {
            $saved=Read-Json $file
            if ($saved.status -in @('STARTING','RUNNING','STOPPING','INTERRUPTED') -and $boot -le [DateTimeOffset]::Parse([string]$saved.updatedAtUtc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_RUN'}
        }
    }
    foreach ($pattern in @('tcp-redirect-context-run-*','pb-kd-baseline-run-*','pb-kd-packet-baseline-run-*','pb-kd-minimal-baseline-run-*','pb-redirect-control-run-*','pb-kd-query-probe-run-*')) {
        foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/diagnostics') -Directory -Filter $pattern)) {
            $file=Join-Path $directory.FullName 'diagnostic-run.json'
            if (Test-Path -LiteralPath $file) {
                $saved=Read-Json $file
                if ($saved.status -eq 'RUNNING' -and $boot -le [DateTimeOffset]::Parse([string]$saved.started_at_utc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_DIAGNOSTIC'}
            }
        }
    }
    $evidence=Join-Path $root ('artifacts/diagnostics/pb-kd-query-probe-run-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $null=New-Item -ItemType Directory -Path $evidence
    $run=[ordered]@{status='RUNNING';diagnostic_only=$true;performance_comparable=$false;started_at_utc=[DateTime]::UtcNow.ToString('o');
        runtime_plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash;workload_directory='workload';debugger_enabled_user_acknowledged=$true;query_profile_reviewed_user_acknowledged=$true;active_point_ids=@(3,4);
        debugger_coverage_verified=$false;driver_installation=$false;error=''}
    Copy-Item -LiteralPath $planPath -Destination (Join-Path $evidence 'runtime-plan.json')
    Copy-Item -LiteralPath (Join-Path $kit 'redirect-context-diagnostic.json') -Destination (Join-Path $evidence 'diagnostic-build.json')
    $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
    try {
        [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','original','Process')
        Write-Host 'KD query probe: только 4 соединения, ожидаются только точки WinDbg 3/4. Вся VM может замедлиться или остановиться.'
        & (Join-Path $PSScriptRoot 'Invoke-KdQueryProbeWorkload.ps1') -Duration SHORT -Load HIGH -EnvPath (Join-Path $kit 'product.env') -PythonPath $python -EvidenceDirectory (Join-Path $evidence 'workload') -DiagnosticRedirectContext -DiagnosticConnectionCase connectex-32 -DiagnosticFixtureCloseGuard -DebuggerLoggerEnabled
        $run.status='KD_QUERY_PROBE_CONTROLLER_RETURNED_DEBUGGER_PENDING'
    } catch {$run.status='FAILED';$run.error=$_.Exception.Message;throw}
    finally {
        $run['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
        $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
        Write-Host ('KD query probe results / Результаты: '+$evidence)
        Write-Host 'На физическом хосте отключите только проверенные точки 3/4 по отдельности, затем bl и отдельно g даже при ошибке. Пришлите весь console WinDbg. Не запускать нагрузку.'
    }
} finally {
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE',$previousRoute,'Process')
    if ($lease) {$lease.Dispose()}
    if ($owns) {$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
