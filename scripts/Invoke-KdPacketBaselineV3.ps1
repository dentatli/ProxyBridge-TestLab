[CmdletBinding()]
param([ValidateSet('Prepare','Inspect','Run')][string]$Phase='Inspect',
    [string]$PreparationDirectory='',[switch]$DebuggerLoggerEnabled,[switch]$PacketStageReviewed)
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
    $PreparationDirectory=Join-Path $root ('artifacts/diagnostics/pb-kd-packet-baseline-preparation-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
}
$PreparationDirectory=[IO.Path]::GetFullPath($PreparationDirectory)
$prefix=[IO.Path]::GetFullPath((Join-Path $root 'artifacts/diagnostics'))+[IO.Path]::DirectorySeparatorChar
if (-not $PreparationDirectory.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $PreparationDirectory) -notmatch '^pb-kd-packet-baseline-preparation-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') {throw 'KD_BASELINE_DIRECTORY_INVALID'}
Assert-PlainPath $PreparationDirectory
if ($Phase -eq 'Prepare') {
    & $python (Join-Path $root 'src/pb_prepare_kd_packet_baseline_v3.py') --root $root --output $PreparationDirectory --python $python
    if ($LASTEXITCODE -ne 0) {throw 'KD_BASELINE_PREPARATION_FAILED'}
}
$planPath=Join-Path $PreparationDirectory 'runtime-plan.json'
$plan=Read-Json $planPath
if ($plan.schema_version -ne 1 -or $plan.method -cne 'kd-packet-owned-four-v3' -or -not $plan.diagnostic_only -or $plan.performance_comparable -or
    $plan.root -ine $root -or $plan.preparation -ine $PreparationDirectory -or $plan.python -ine $python -or $plan.files.Count -lt 40 -or
    $plan.kd_baseline_policy.connections -ne 4 -or $plan.kd_baseline_policy.hold_seconds -ne 8 -or
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
foreach ($required in @('scripts/Invoke-KdPacketBaselineV3.ps1','src/pb_prepare_kd_packet_baseline_v3.py',
    'scripts/debugger/pb-context-packet-stage-v3.wdbg','scripts/debugger/pb-context-packet-stage-code-gate-v3.wdbg',
    'scripts/debugger/pb-context-packet-stage-body-v3.wdbg','scripts/debugger/pb-context-packet-logger-plan-v2.json',
    'scripts/debugger/pb-context-packet-format-probe-v2.wdbg')) {
    if (-not $seen.ContainsKey((Join-Path $root $required))) {throw 'KD_PACKET_LOGGER_NOT_FROZEN'}
}
$stageReviewFile=Join-Path $root 'artifacts/diagnostics/pb-kd-packet-stage-v3-review-20261008/validation.json'
if (-not $seen.ContainsKey($stageReviewFile)) {throw 'KD_PACKET_STAGE_REVIEW_NOT_FROZEN'}
if (-not $plan.PSObject.Properties['packet_logger_policy']) {throw 'KD_PACKET_POLICY_MISSING'}
$packet=$plan.packet_logger_policy
if ($packet.method -cne 'packet-stage-four-v3' -or $packet.point_count -ne 25 -or
    (@($packet.point_ids) -join ',') -cne ((0..24) -join ',') -or
    $packet.expected_manual_stage_state -cne 'disabled' -or -not $packet.user_stage_review_required -or
    $packet.automatic_debugger_control -or $packet.owned_packet_coverage_verified -or $packet.owned_nonzero_pid_tid_verified -or
    -not $packet.saved_stage_registration_verified -or $packet.actual_point_actions_verified -or
    $packet.saved_stage_log_sha256 -cne 'f26054a9f937849104814437216932006c83a8b1fec8e0e292245147579e43d2' -or
    $packet.stage_review_sha256 -notmatch '^[a-f0-9]{64}$' -or
    (Get-FileHash -LiteralPath $stageReviewFile).Hash -ine $packet.stage_review_sha256 -or
    $packet.stage_entry -cne 'scripts/debugger/pb-context-packet-stage-v3.wdbg' -or
    $packet.stage_sha256 -notmatch '^[a-f0-9]{64}$' -or $packet.manifest_sha256 -notmatch '^[a-f0-9]{64}$' -or
    $packet.format_probe_sha256 -cne '8816e3ec025dc454f64c5f2913636a2ca6c34184855b7b96cd8c38e7dccdedcc' -or
    $packet.format_log_sha256 -cne '8934f1ceb496b281059c9b70b2c8d6cdd628335a6a4f1bdd887f70fdb8651634' -or
    (Get-FileHash -LiteralPath (Join-Path $root $packet.stage_entry)).Hash -ine $packet.stage_sha256 -or
    (Get-FileHash -LiteralPath (Join-Path $root 'scripts/debugger/pb-context-packet-logger-plan-v2.json')).Hash -ine $packet.manifest_sha256) {
    throw 'KD_PACKET_POLICY_INVALID'
}
$kit=Join-Path $PreparationDirectory 'kit'
foreach ($required in @('product.env','redirect-context-diagnostic.json','ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys')) {
    if (-not $seen.ContainsKey((Join-Path $kit $required))) {throw 'KD_BASELINE_KIT_NOT_FROZEN'}
}
$receipt=Read-Json (Join-Path $kit 'redirect-context-diagnostic.json')
if (-not $receipt.PSObject.Properties['packet_logger_policy'] -or
    ($receipt.packet_logger_policy | ConvertTo-Json -Depth 8 -Compress) -cne ($packet | ConvertTo-Json -Depth 8 -Compress)) {throw 'KD_PACKET_RECEIPT_POLICY_DIFFERS'}
if ($receipt.method -cne 'redirect-kd-baseline-v5' -or -not $receipt.PSObject.Properties['components'] -or $receipt.components.Count -ne 3) {throw 'KD_BASELINE_COMPONENT_RECEIPT_INCOMPLETE'}
$componentNames=@{}
foreach ($component in $receipt.components) {
    if ($component.name -cnotin @('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys') -or $componentNames.ContainsKey([string]$component.name) -or
        $component.sha256 -notmatch '^[a-f0-9]{64}$' -or $component.sha256 -cne $receipt.reused_binary_sha256.($component.name) -or
        (Get-FileHash -LiteralPath (Join-Path $kit $component.name)).Hash -ine $component.sha256) {throw 'KD_BASELINE_COMPONENT_RECEIPT_DIFFERS'}
    $componentNames[[string]$component.name]=$true
}
if ($Phase -ne 'Run') {
    [ordered]@{status='KD_PACKET_FILES_VALIDATED';preparation_directory=$PreparationDirectory;files=$plan.files.Count;
        connections=4;load_levels=@();product_started=$false;driver_installed=$false;traffic_generated=$false;
        debugger_coverage_verified=$false;runtime_ready=$false} | ConvertTo-Json
    return
}
if (-not $PacketStageReviewed) {throw 'KD_PACKET_REQUIRES_USER_REVIEWED_DISABLED_STAGE_BEFORE_ENABLE'}
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
    foreach ($pattern in @('tcp-redirect-context-run-*','pb-kd-baseline-run-*','pb-kd-packet-baseline-run-*')) {
        foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/diagnostics') -Directory -Filter $pattern)) {
            $file=Join-Path $directory.FullName 'diagnostic-run.json'
            if (Test-Path -LiteralPath $file) {
                $saved=Read-Json $file
                if ($saved.status -eq 'RUNNING' -and $boot -le [DateTimeOffset]::Parse([string]$saved.started_at_utc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_DIAGNOSTIC'}
            }
        }
    }
    $evidence=Join-Path $root ('artifacts/diagnostics/pb-kd-packet-baseline-run-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $null=New-Item -ItemType Directory -Path $evidence
    $run=[ordered]@{status='RUNNING';diagnostic_only=$true;performance_comparable=$false;started_at_utc=[DateTime]::UtcNow.ToString('o');
        runtime_plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash;workload_directory='workload';debugger_enabled_user_acknowledged=$true;packet_stage_reviewed_user_acknowledged=$true;
        debugger_coverage_verified=$false;driver_installation=$false;error=''}
    Copy-Item -LiteralPath $planPath -Destination (Join-Path $evidence 'runtime-plan.json')
    Copy-Item -LiteralPath (Join-Path $kit 'redirect-context-diagnostic.json') -Destination (Join-Path $evidence 'diagnostic-build.json')
    $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
    try {
        [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','original','Process')
        Write-Host 'Только четыре соединения для проверки WinDbg logger. Нагрузка не запускается. Активные точки приостанавливают всю VM.'
        & (Join-Path $PSScriptRoot 'Invoke-KdContextBaselineWorkload.ps1') -Duration SHORT -Load HIGH -EnvPath (Join-Path $kit 'product.env') -PythonPath $python -EvidenceDirectory (Join-Path $evidence 'workload') -DiagnosticRedirectContext -DiagnosticConnectionCase connectex-32 -DiagnosticFixtureCloseGuard
        $run.status='BASELINE_CONTROLLER_RETURNED_DEBUGGER_PENDING'
    } catch {$run.status='FAILED';$run.error=$_.Exception.Message;throw}
    finally {
        $run['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
        $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
        Write-Host ('KD baseline results / Результаты: '+$evidence)
        Write-Host 'На физическом хосте отключите только наши проверенные точки 0..24, затем отдельно g. Сохраните существующий лог WinDbg.'
    }
} finally {
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE',$previousRoute,'Process')
    if ($lease) {$lease.Dispose()}
    if ($owns) {$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
