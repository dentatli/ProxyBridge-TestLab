[CmdletBinding()]
param([ValidateSet('Prepare','Inspect','Run')][string]$Phase='Inspect',
    [string]$PreparationDirectory='',[switch]$AcceptQueryProfileReviewed,[switch]$DebuggerLoggerEnabled)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/KdBootSessionEvidence.psm1')
function Assert-PlainPath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'KD_ACCEPT_QUERY_REPARSE_PATH'}
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Read-Json([string]$Path) {
    Assert-PlainPath $Path
    if ((Get-Item -LiteralPath $Path).Length -gt 16MB) {throw 'KD_ACCEPT_QUERY_JSON_TOO_LARGE'}
    $text=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {return ConvertFrom-Json -InputObject $text -DateKind String}
    return ConvertFrom-Json -InputObject $text
}
if (-not $PreparationDirectory) {
    if ($Phase -ne 'Prepare') {throw 'KD_ACCEPT_QUERY_PREPARATION_REQUIRED'}
    $PreparationDirectory=Join-Path $root ('artifacts/diagnostics/pb-kd-accept-query-preparation-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
}
$PreparationDirectory=[IO.Path]::GetFullPath($PreparationDirectory)
$prefix=[IO.Path]::GetFullPath((Join-Path $root 'artifacts/diagnostics'))+[IO.Path]::DirectorySeparatorChar
if (-not $PreparationDirectory.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $PreparationDirectory) -notmatch '^pb-kd-accept-query-preparation-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') {throw 'KD_ACCEPT_QUERY_DIRECTORY_INVALID'}
Assert-PlainPath $PreparationDirectory
if ($Phase -eq 'Prepare') {
    $sourcePython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    $bootInput=Join-Path $root ('artifacts/diagnostics/pb-kd-accept-query-boot-input-'+[guid]::NewGuid().ToString('N')+'.json')
    Get-KdBootSessionEvidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $bootInput -Encoding UTF8
    & $sourcePython -B (Join-Path $root 'src/pb_prepare_kd_accept_query.py') --root $root --output $PreparationDirectory --python $sourcePython --boot-evidence $bootInput
    if ($LASTEXITCODE -ne 0) {throw 'KD_ACCEPT_QUERY_PREPARATION_FAILED'}
}
$planPath=Join-Path $PreparationDirectory 'runtime-plan.json'
$plan=Read-Json $planPath
$python=Join-Path $PreparationDirectory 'runtime/python/python.exe'
if ($plan.schema_version -ne 1 -or $plan.method -cne 'redirect-kd-accept-query-four-v1' -or -not $plan.diagnostic_only -or $plan.performance_comparable -or
    $plan.root -ine $root -or $plan.preparation -ine $PreparationDirectory -or $plan.python -ine $python -or $plan.files.Count -lt 50) {throw 'KD_ACCEPT_QUERY_PLAN_INVALID'}
$policy=$plan.control_policy
if ($policy.method -cne 'redirect-kd-accept-query-four-v1' -or ($policy.phase_connections -join ',') -cne '4' -or
    $policy.total_connections -ne 4 -or @($policy.load_levels).Count -ne 0 -or $policy.hold_seconds -ne 8 -or
    $policy.connect_method -cne 'ConnectEx' -or $policy.pending_limit -ne 32 -or -not $policy.original_single_query -or
    $policy.listener_case -cne 'original' -or $policy.listener_delay_ms -ne 0 -or $policy.debugger_points -cne 'accept-state-query-read-only' -or
    ($policy.active_point_ids -join ',') -cne '2,3' -or ($policy.registered_point_ids -join ',') -cne '2,3,4' -or ($policy.inactive_point_ids -join ',') -cne '4' -or
    $policy.load_authorized -or -not $policy.logger_verification_required_before_load -or
    $policy.cohort_budget_ms -ne 180000 -or $policy.client_wait_limit_ms -ne 60000 -or $policy.final_four_same_session -or
    $policy.driver_installation -or $policy.automatic_debugger_control -or -not $policy.diagnostic_only -or $policy.performance_comparable) {throw 'KD_ACCEPT_QUERY_POLICY_INVALID'}
$seen=@{}
foreach ($file in $plan.files) {
    Assert-PlainPath $file.path
    if ($seen.ContainsKey([string]$file.path) -or $file.sha256 -notmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $file.path).Hash -ine $file.sha256) {throw 'KD_ACCEPT_QUERY_FROZEN_FILE_CHANGED'}
    $seen[[string]$file.path]=$true
}
foreach ($required in @('scripts/Invoke-KdAcceptQuery.ps1','scripts/Invoke-KdAcceptQueryWorkload.ps1',
    'modules/KdQueryProbeConnectionLoad.psm1','modules/InterceptionState.psm1','src/pb_prepare_kd_accept_query.py',
    'src/pb_kd_accept_query_report.py','src/pb_tcp_redirect_context_report.py')) {
    if (-not $seen.ContainsKey((Join-Path $root $required))) {throw 'KD_ACCEPT_QUERY_CONTRACT_NOT_FROZEN'}
}
$runtimeRoot=Join-Path $PreparationDirectory 'runtime/python'
$runtimeManifestPath=Join-Path $PreparationDirectory 'runtime/manifest.json'
if (-not $seen.ContainsKey($runtimeManifestPath) -or $plan.runtime_manifest_sha256 -notmatch '^[a-f0-9]{64}$' -or
    (Get-FileHash -LiteralPath $runtimeManifestPath).Hash -ine $plan.runtime_manifest_sha256) {throw 'KD_ACCEPT_QUERY_RUNTIME_MANIFEST_CHANGED'}
$runtimeManifest=Read-Json $runtimeManifestPath
$runtimeEntries=@($runtimeManifest.files.PSObject.Properties)
$actualRuntime=@(Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File -Force)
if ($runtimeEntries.Count -ne $runtimeManifest.copied_files -or $actualRuntime.Count -ne $runtimeEntries.Count -or
    -not $runtimeManifest.isolated_pth -or $runtimeManifest.import_site -or $runtimeManifest.source_runtime_reused_at_run) {throw 'KD_ACCEPT_QUERY_RUNTIME_INVENTORY_CHANGED'}
foreach ($entry in $runtimeEntries) {
    $path=[IO.Path]::GetFullPath((Join-Path $runtimeRoot $entry.Name))
    if (-not $path.StartsWith(([IO.Path]::GetFullPath($runtimeRoot)+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or
        -not $seen.ContainsKey($path) -or $entry.Value -notmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $path).Hash -ine $entry.Value) {throw 'KD_ACCEPT_QUERY_RUNTIME_FILE_CHANGED'}
}
$profilePath=Join-Path $root 'scripts/debugger/pb-kd-accept-query-candidate-20261017.json'
$stagePath=Join-Path $root 'scripts/debugger/pb-kd-accept-query-add-disabled-20261017.wdbg'
if (-not $seen.ContainsKey($profilePath) -or -not $seen.ContainsKey($stagePath)) {throw 'KD_ACCEPT_QUERY_PROFILE_NOT_FROZEN'}
$profile=Read-Json $profilePath
if ($profile.method -cne 'kd-accept-query-pair-candidate-v1' -or $profile.point_count_active -ne 2 -or
    ($profile.registered_after_candidate -join ',') -cne '2,3,4' -or ($profile.active_candidate -join ',') -cne '2,3' -or
    ($profile.inactive_candidate -join ',') -cne '4' -or $profile.load_authorized -or $profile.outer_g_included -or
    $profile.automatic_debugger_control -or $profile.live_accept_port_read_verified -or $profile.tuple_binding_verified -or
    (Get-FileHash -LiteralPath $stagePath).Hash -ine $profile.stage_sha256) {throw 'KD_ACCEPT_QUERY_PROFILE_INVALID'}
$saved=Join-Path $PreparationDirectory 'debugger-evidence'
foreach ($name in @('registration-console.txt','registration-review.json','registered-profile.json','registered-stage.wdbg','live-review.json','user-live-selected-bytes.txt','static-validation.json')) {
    if (-not $seen.ContainsKey((Join-Path $saved $name))) {throw 'KD_ACCEPT_QUERY_EVIDENCE_NOT_FROZEN'}
}
if ((Get-FileHash -LiteralPath (Join-Path $saved 'registration-console.txt')).Hash -ine 'edb949cf7e157d572e1221b35614ddcbd5562448bbccbaf44dae327a27f63c6b' -or
    (Get-FileHash -LiteralPath (Join-Path $saved 'registration-review.json')).Hash -ine '3e36b6463ab8685230f458dfb98c492a967a970b1bc371248490dd7dab6396f4') {throw 'KD_ACCEPT_QUERY_REGISTRATION_DIFFERS'}
$review=Read-Json (Join-Path $saved 'registration-review.json')
if ($review.status -cne 'ACCEPT_QUERY_THREE_DISABLED_POINTS_REGISTERED_ACTIONS_PENDING' -or
    ($review.point_ids -join ',') -cne '2,3,4' -or $review.points_after -ne 3 -or
    ($review.initial_point_ids -join ',') -cne '3,4' -or -not $review.initial_all_disabled -or -not $review.initial_slot2_absent -or
    -not $review.all_points_disabled -or -not $review.addresses_and_bodies_exact -or -not $review.bpcmds_exact -or
    -not $review.outer_g_separate -or @($review.registration_errors).Count -ne 0 -or
    $review.actual_point_actions_verified -or $review.gc_behavior_verified -or $review.port_filter_runtime_verified -or
    $review.flow_binding_verified -or $review.lifecycle_coverage_verified -or $review.root_cause_proven -or
    (Get-FileHash -LiteralPath $stagePath).Hash -ine $review.stage_sha256 -or
    (Get-FileHash -LiteralPath $profilePath).Hash -ine $review.profile_sha256) {throw 'KD_ACCEPT_QUERY_REVIEW_INVALID'}
$registered=Read-Json (Join-Path $saved 'registered-profile.json')
if (($registered | ConvertTo-Json -Depth 12 -Compress) -cne ($profile | ConvertTo-Json -Depth 12 -Compress)) {throw 'KD_ACCEPT_QUERY_PROFILE_SNAPSHOT_DIFFERS'}
$bootEvidencePath=Join-Path $PreparationDirectory 'debugger-evidence/boot-session.json'
if ($plan.boot_binding.method -cne 'kernel-general-12-and-prefetch-bootid-v1' -or
    $plan.boot_binding.path -ine $bootEvidencePath -or -not $seen.ContainsKey($bootEvidencePath) -or
    -not $seen.ContainsKey((Join-Path $root 'modules/KdBootSessionEvidence.psm1')) -or
    (Get-FileHash -LiteralPath $bootEvidencePath).Hash -ine $plan.boot_binding.sha256) {throw 'KD_BOOT_BINDING_NOT_FROZEN'}
$bootEvidence=Read-Json $bootEvidencePath
Assert-KdBootSessionEvidence -Expected $bootEvidence -Actual $bootEvidence
$kit=Join-Path $PreparationDirectory 'kit'
$receipt=Read-Json (Join-Path $kit 'redirect-context-diagnostic.json')
if ($receipt.method -cne 'redirect-kd-accept-query-four-v1' -or
    ($receipt.control_policy | ConvertTo-Json -Depth 8 -Compress) -cne ($policy | ConvertTo-Json -Depth 8 -Compress)) {throw 'KD_ACCEPT_QUERY_RECEIPT_POLICY_DIFFERS'}
$pinned=@{'ProxyBridge_CLI.exe'='ad83b3aad22252be0ab20a6c26470f7c364930af35089e9904f1dd0d29bb40ca';
    'ProxyBridgeCore.dll'='7dc8952e7562ac4dff3cf278136d1fe8fd44474885f707c93c220f94e9f624ed';
    'ProxyBridgeDrv.sys'='3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e'}
if ($receipt.components.Count -ne 3) {throw 'KD_ACCEPT_QUERY_COMPONENT_COUNT_INVALID'}
$components=@{}
foreach ($component in $receipt.components) {
    if (-not $pinned.ContainsKey([string]$component.name) -or $components.ContainsKey([string]$component.name) -or
        $component.sha256 -cne $pinned[[string]$component.name] -or
        (Get-FileHash -LiteralPath (Join-Path $kit $component.name)).Hash -ine $component.sha256) {throw 'KD_ACCEPT_QUERY_COMPONENT_DIFFERS'}
    $components[[string]$component.name]=$true
}
foreach ($name in @('product.env','redirect-context-diagnostic.json','ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys')) {
    if (-not $seen.ContainsKey((Join-Path $kit $name))) {throw 'KD_ACCEPT_QUERY_KIT_NOT_FROZEN'}
}
if ($Phase -ne 'Run') {
    [ordered]@{status='KD_ACCEPT_QUERY_FILES_VALIDATED';preparation_directory=$PreparationDirectory;files=$plan.files.Count;
        runtime_files=$runtimeEntries.Count;connections=4;product_started=$false;driver_installed=$false;
        traffic_generated=$false;debugger_control=$false;runtime_ready=$false} | ConvertTo-Json
    return
}
if (-not $AcceptQueryProfileReviewed -or -not $DebuggerLoggerEnabled) {throw 'KD_ACCEPT_QUERY_REQUIRES_USER_REVIEWED_PROFILE_AND_ENABLED_2_3_WITH_4_DISABLED'}
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
    $currentBoot=Get-KdBootSessionEvidence
    Assert-KdBootSessionEvidence -Expected $bootEvidence -Actual $currentBoot
    $boot=[DateTimeOffset]::Parse([string]$currentBoot.identity.start_time_utc)
    if ($boot -le $latestLegacy) {throw 'LAB_REBOOT_REQUIRED_AFTER_RECORDED_4_0_0'}
    foreach ($control in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/benchmark-launch') -Directory -Filter '*-control')) {
        $file=Join-Path $control.FullName 'job.json'
        if (Test-Path -LiteralPath $file) {
            $saved=Read-Json $file
            if ($saved.status -in @('STARTING','RUNNING','STOPPING','INTERRUPTED') -and $boot -le [DateTimeOffset]::Parse([string]$saved.updatedAtUtc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_RUN'}
        }
    }
    foreach ($pattern in @('tcp-redirect-context-run-*','pb-kd-baseline-run-*','pb-kd-packet-baseline-run-*','pb-kd-minimal-baseline-run-*','pb-redirect-control-run-*','pb-kd-query-probe-run-*','pb-kd-query-session-run-*','pb-kd-query-bounded-run-*','pb-kd-accept-query-run-*')) {
        foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/diagnostics') -Directory -Filter $pattern)) {
            $file=Join-Path $directory.FullName 'diagnostic-run.json'
            if (Test-Path -LiteralPath $file) {
                $saved=Read-Json $file
                if ($saved.status -eq 'RUNNING' -and $boot -le [DateTimeOffset]::Parse([string]$saved.started_at_utc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_DIAGNOSTIC'}
            }
        }
    }
    $evidence=Join-Path $root ('artifacts/diagnostics/pb-kd-accept-query-run-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $null=New-Item -ItemType Directory -Path $evidence
    $run=[ordered]@{status='RUNNING';diagnostic_only=$true;performance_comparable=$false;started_at_utc=[DateTime]::UtcNow.ToString('o');
        runtime_plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash;workload_directory='workload';debugger_enabled_user_acknowledged=$true;query_profile_reviewed_user_acknowledged=$true;active_point_ids=@(2,3);registered_point_ids=@(2,3,4);inactive_point_ids=@(4);
        debugger_coverage_verified=$false;driver_installation=$false;error=''}
    $currentBoot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'boot-session-before-run.json') -Encoding UTF8
    Copy-Item -LiteralPath $planPath -Destination (Join-Path $evidence 'runtime-plan.json')
    Copy-Item -LiteralPath (Join-Path $kit 'redirect-context-diagnostic.json') -Destination (Join-Path $evidence 'diagnostic-build.json')
    $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
    try {
        [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','original','Process')
        Write-Host 'KD accept/query: только 4 соединения, активны только 2/3, точка 4 отключена. Вся VM может замедлиться или остановиться.'
        & (Join-Path $PSScriptRoot 'Invoke-KdAcceptQueryWorkload.ps1') -Duration SHORT -Load HIGH -EnvPath (Join-Path $kit 'product.env') -PythonPath $python -EvidenceDirectory (Join-Path $evidence 'workload') -DiagnosticRedirectContext -DiagnosticConnectionCase connectex-32 -DiagnosticFixtureCloseGuard -DebuggerLoggerEnabled -AcceptQueryProfileReviewed
        $run.status='KD_ACCEPT_QUERY_CONTROLLER_RETURNED_DEBUGGER_PENDING'
    } catch {$run.status='FAILED';$run.error=$_.Exception.Message;throw}
    finally {
        $run['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
        $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
        Write-Host ('KD accept/query results / Результаты: '+$evidence)
        Write-Host 'На физическом хосте отключите только проверенные точки 2/3 по отдельности, затем bl и отдельно g даже при ошибке. Пришлите весь console WinDbg. Точку 4 оставить отключённой. Не повторять Run и не увеличивать нагрузку.'
    }
} finally {
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE',$previousRoute,'Process')
    if ($lease) {$lease.Dispose()}
    if ($owns) {$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
