[CmdletBinding()]
param([ValidateSet('Prepare','Inspect','Run')][string]$Phase='Inspect',
    [string]$PreparationDirectory='',[switch]$DebuggerLoggerEnabled,[switch]$MinimalStageReviewed)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$python=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
function Assert-PlainPath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'KD_BASELINE_REPARSE_PATH'}
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Read-Json([string]$Path) {
    Assert-PlainPath $Path
    if ((Get-Item -LiteralPath $Path).Length -gt 1MB) {throw 'KD_BASELINE_JSON_TOO_LARGE'}
    $text=Get-Content -LiteralPath $Path -Raw
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {return ConvertFrom-Json -InputObject $text -DateKind String}
    return ConvertFrom-Json -InputObject $text
}
if (-not $PreparationDirectory) {
    if ($Phase -ne 'Prepare') {throw 'KD_BASELINE_PREPARATION_REQUIRED'}
    $PreparationDirectory=Join-Path $root ('artifacts/diagnostics/pb-kd-minimal-baseline-preparation-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
}
$PreparationDirectory=[IO.Path]::GetFullPath($PreparationDirectory)
$prefix=[IO.Path]::GetFullPath((Join-Path $root 'artifacts/diagnostics'))+[IO.Path]::DirectorySeparatorChar
if (-not $PreparationDirectory.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $PreparationDirectory) -notmatch '^pb-kd-minimal-baseline-preparation-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') {throw 'KD_BASELINE_DIRECTORY_INVALID'}
Assert-PlainPath $PreparationDirectory
if ($Phase -eq 'Prepare') {
    & $python (Join-Path $root 'src/pb_prepare_kd_minimal_baseline.py') --root $root --output $PreparationDirectory --python $python
    if ($LASTEXITCODE -ne 0) {throw 'KD_BASELINE_PREPARATION_FAILED'}
}
$planPath=Join-Path $PreparationDirectory 'runtime-plan.json'
$plan=Read-Json $planPath
if ($plan.schema_version -ne 1 -or $plan.method -cne 'kd-minimal-owned-four-v1' -or -not $plan.diagnostic_only -or $plan.performance_comparable -or
    $plan.root -ine $root -or $plan.preparation -ine $PreparationDirectory -or $plan.python -ine $python -or $plan.files.Count -lt 40 -or
    $plan.kd_baseline_policy.method -cne 'kd-owned-four-v1' -or
    $plan.kd_baseline_policy.connections -ne 4 -or $plan.kd_baseline_policy.hold_seconds -ne 8 -or
    -not $plan.kd_baseline_policy.original_single_query -or $plan.kd_baseline_policy.listener_case -cne 'original' -or
    -not $plan.kd_baseline_policy.diagnostic_only -or $plan.kd_baseline_policy.performance_comparable -or
    $plan.kd_baseline_policy.load_levels.Count -or $plan.kd_baseline_policy.recovery -or $plan.kd_baseline_policy.driver_installation) {throw 'KD_BASELINE_PLAN_INVALID'}
$seen=@{}
foreach ($file in $plan.files) {
    Assert-PlainPath $file.path
    if ($seen.ContainsKey([string]$file.path) -or $file.sha256 -notmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $file.path).Hash -ine $file.sha256) {throw 'KD_BASELINE_FROZEN_FILES_CHANGED'}
    $seen[[string]$file.path]=$true
}
foreach ($required in @('scripts/Invoke-KdContextBaseline.ps1','scripts/Invoke-KdContextBaselineWorkload.ps1',
    'modules/ConnectionLoad.psm1','modules/InterceptionState.psm1','src/pb_kd_baseline_report.py')) {
    if (-not $seen.ContainsKey((Join-Path $root $required))) {throw 'KD_BASELINE_FROZEN_CONTRACT_MISSING'}
}
foreach ($required in @('scripts/Invoke-KdMinimalBaseline.ps1','src/pb_prepare_kd_minimal_baseline.py',
    'scripts/debugger/pb-kd-minimal-stage-20261016.wdbg',
    'scripts/debugger/pb-kd-minimal-stage-profile-20261016.json',
    'scripts/debugger/pb-kd-minimal-format-probe-20261016.wdbg')) {
    if (-not $seen.ContainsKey((Join-Path $root $required))) {throw 'KD_MINIMAL_LOGGER_NOT_FROZEN'}
}
$saved=Join-Path $PreparationDirectory 'debugger-evidence'
foreach ($required in @('registration-review.json','format-probe-review.json','registration-console.txt',
    'format-probe-console.txt','registered-stage.wdbg','registered-profile.json')) {
    if (-not $seen.ContainsKey((Join-Path $saved $required))) {throw 'KD_MINIMAL_REVIEW_NOT_FROZEN'}
}
if (-not $plan.PSObject.Properties['minimal_logger_policy']) {throw 'KD_MINIMAL_POLICY_MISSING'}
$packet=$plan.minimal_logger_policy
if ($packet.method -cne 'minimal-seven-stage-four-v1' -or $packet.point_count -ne 7 -or
    (@($packet.point_ids) -join ',') -cne '0,1,2,3,4,5,6' -or
    $packet.expected_manual_stage_state -cne 'disabled' -or -not $packet.user_stage_review_required -or
    $packet.automatic_debugger_control -or $packet.owned_packet_coverage_verified -or $packet.owned_nonzero_pid_tid_verified -or
    $packet.actual_point_actions_verified -or $packet.gc_behavior_verified -or $packet.core_query_binding_verified -or $packet.root_cause_proven -or
    -not $packet.saved_stage_registration_verified -or $packet.saved_stage_clean -or $packet.saved_stage_comment_error_count -ne 1 -or
    $packet.saved_stage_log_sha256 -cne '0d025fe96d87a5726bba8ee25c479bab69b2c11fe4f6a5ad20b6b72b7936fe1d' -or
    $packet.registered_stage_sha256 -cne 'bfda5c41a138c0351110caeddd9256f0238d66b37b0bbd0a15031632bbd53413' -or
    $packet.source_stage_entry -cne 'scripts/debugger/pb-kd-minimal-stage-20261016.wdbg' -or
    $packet.profile_entry -cne 'scripts/debugger/pb-kd-minimal-stage-profile-20261016.json' -or
    $packet.source_stage_change -cne 'comment-only-do-not-reload-current-session' -or
    $packet.host_capture_method -cne 'user-full-console-paste-no-logopen-required') {throw 'KD_MINIMAL_POLICY_INVALID'}
$checks=@(
    @((Join-Path $saved 'registration-console.txt'),$packet.saved_stage_log_sha256),
    @((Join-Path $saved 'registered-stage.wdbg'),$packet.registered_stage_sha256),
    @((Join-Path $saved 'registration-review.json'),$packet.stage_review_sha256),
    @((Join-Path $saved 'format-probe-review.json'),$packet.probe_review_sha256),
    @((Join-Path $root $packet.source_stage_entry),$packet.source_stage_sha256),
    @((Join-Path $root $packet.profile_entry),$packet.profile_sha256),
    @((Join-Path $root 'scripts/debugger/pb-kd-minimal-format-probe-20261016.wdbg'),$packet.format_probe_sha256))
foreach ($check in $checks) {
    if ($check[1] -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $check[0]).Hash -ine $check[1]) {throw 'KD_MINIMAL_POLICY_HASH_DIFFERS'}
}
$review=Read-Json (Join-Path $saved 'registration-review.json')
if ($review.status -cne 'USER_SEVEN_DISABLED_POINTS_CONFIRMED_WITH_STAGE_COMMENT_ERROR_ACTIONS_PENDING' -or
    $review.source_sha256 -cne $packet.saved_stage_log_sha256 -or
    (@($review.point_ids) -join ',') -cne '0,1,2,3,4,5,6' -or $review.points_after -ne 7 -or
    -not $review.all_points_disabled -or -not $review.addresses_and_bodies_exact -or -not $review.bpcmds_exact -or
    -not $review.outer_g_separate -or $review.stage_clean -or @($review.stage_comment_errors).Count -ne 1 -or
    $review.bp_registration_errors -or $review.actual_point_actions_verified -or $review.gc_behavior_verified -or
    $review.owned_packet_coverage_verified -or $review.core_query_binding_verified -or $review.root_cause_proven) {throw 'KD_MINIMAL_REVIEW_INVALID'}
$current=Read-Json (Join-Path $root $packet.profile_entry)
$registered=Read-Json (Join-Path $saved 'registered-profile.json')
$expected=@('tcpip!AlepCreateRedirectRecord+0x396','tcpip!WfpAleAuthorizeAccept+0xcaf',
    'tcpip!WfpAleAuthorizeAccept+0xcbe','tcpip!WfpAleProcessSocketOption+0x2c4',
    'tcpip!WfpAleProcessSocketOption+0x47b','tcpip!AleRedirectRecordFree+0xd','tcpip!AleRedirectRecordFree+0x76')
if ($current.points.Count -ne 7 -or $registered.points.Count -ne 7) {throw 'KD_MINIMAL_POINT_COUNT_INVALID'}
for ($i=0;$i -lt 7;$i++) {
    if ($current.points[$i].proposed_id -ne $i -or $current.points[$i].target -cne $expected[$i] -or
        $current.points[$i].registration_command -cne $registered.points[$i].registration_command -or
        $current.points[$i].runtime_action_verified) {throw 'KD_MINIMAL_REGISTERED_ACTION_DIFFERS'}
}
$kit=Join-Path $PreparationDirectory 'kit'
foreach ($required in @('product.env','redirect-context-diagnostic.json','ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys')) {
    if (-not $seen.ContainsKey((Join-Path $kit $required))) {throw 'KD_BASELINE_KIT_NOT_FROZEN'}
}
$receipt=Read-Json (Join-Path $kit 'redirect-context-diagnostic.json')
if (-not $receipt.PSObject.Properties['minimal_logger_policy'] -or
    ($receipt.minimal_logger_policy | ConvertTo-Json -Depth 8 -Compress) -cne ($packet | ConvertTo-Json -Depth 8 -Compress)) {throw 'KD_MINIMAL_RECEIPT_POLICY_DIFFERS'}
if ($receipt.method -cne 'redirect-kd-baseline-v5' -or -not $receipt.PSObject.Properties['components'] -or $receipt.components.Count -ne 3) {throw 'KD_BASELINE_COMPONENT_RECEIPT_INCOMPLETE'}
$componentNames=@{}
foreach ($component in $receipt.components) {
    if ($component.name -cnotin @('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys') -or $componentNames.ContainsKey([string]$component.name) -or
        $component.sha256 -notmatch '^[a-f0-9]{64}$' -or $component.sha256 -cne $receipt.reused_binary_sha256.($component.name) -or
        (Get-FileHash -LiteralPath (Join-Path $kit $component.name)).Hash -ine $component.sha256) {throw 'KD_BASELINE_COMPONENT_RECEIPT_DIFFERS'}
    $componentNames[[string]$component.name]=$true
}
if ($Phase -ne 'Run') {
    [ordered]@{status='KD_MINIMAL_FILES_VALIDATED';preparation_directory=$PreparationDirectory;files=$plan.files.Count;
        connections=4;load_levels=@();product_started=$false;driver_installed=$false;traffic_generated=$false;
        debugger_coverage_verified=$false;runtime_ready=$false} | ConvertTo-Json
    return
}
if (-not $MinimalStageReviewed) {throw 'KD_MINIMAL_REQUIRES_USER_REVIEWED_DISABLED_STAGE_BEFORE_ENABLE'}
if (-not $DebuggerLoggerEnabled) {throw 'KD_BASELINE_REQUIRES_USER_ENABLED_LOGGER_AND_HOST_RESUME_PLAN'}
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
    foreach ($pattern in @('tcp-redirect-context-run-*','pb-kd-baseline-run-*','pb-kd-packet-baseline-run-*','pb-kd-minimal-baseline-run-*')) {
        foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/diagnostics') -Directory -Filter $pattern)) {
            $file=Join-Path $directory.FullName 'diagnostic-run.json'
            if (Test-Path -LiteralPath $file) {
                $saved=Read-Json $file
                if ($saved.status -eq 'RUNNING' -and $boot -le [DateTimeOffset]::Parse([string]$saved.started_at_utc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_DIAGNOSTIC'}
            }
        }
    }
    $evidence=Join-Path $root ('artifacts/diagnostics/pb-kd-minimal-baseline-run-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $null=New-Item -ItemType Directory -Path $evidence
    $run=[ordered]@{status='RUNNING';diagnostic_only=$true;performance_comparable=$false;started_at_utc=[DateTime]::UtcNow.ToString('o');
        runtime_plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash;workload_directory='workload';debugger_enabled_user_acknowledged=$true;minimal_stage_reviewed_user_acknowledged=$true;
        debugger_coverage_verified=$false;driver_installation=$false;error=''}
    Copy-Item -LiteralPath $planPath -Destination (Join-Path $evidence 'runtime-plan.json')
    Copy-Item -LiteralPath (Join-Path $kit 'redirect-context-diagnostic.json') -Destination (Join-Path $evidence 'diagnostic-build.json')
    $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
    try {
        [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','original','Process')
        Write-Host 'Только проба на четырёх TCP-соединениях. Точки WinDbg могут замедлить всю VM.'
        & (Join-Path $PSScriptRoot 'Invoke-KdContextBaselineWorkload.ps1') -Duration SHORT -Load HIGH -EnvPath (Join-Path $kit 'product.env') -PythonPath $python -EvidenceDirectory (Join-Path $evidence 'workload') -DiagnosticRedirectContext -DiagnosticConnectionCase connectex-32 -DiagnosticFixtureCloseGuard
        $run.status='BASELINE_CONTROLLER_RETURNED_DEBUGGER_PENDING'
    } catch {$run.status='FAILED';$run.error=$_.Exception.Message;throw}
    finally {
        $run['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
        $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
        Write-Host ('KD baseline results / Результаты: '+$evidence)
        Write-Host 'На физическом хосте отключите только наши проверенные точки 0..6, затем отдельно g. Пришлите полный console WinDbg.'
    }
} finally {
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE',$previousRoute,'Process')
    if ($lease) {$lease.Dispose()}
    if ($owns) {$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
