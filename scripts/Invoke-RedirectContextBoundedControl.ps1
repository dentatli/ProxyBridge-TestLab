[CmdletBinding()]
param([ValidateSet('Prepare','Inspect','Run')][string]$Phase='Inspect',
    [string]$PreparationDirectory='',[switch]$DebuggerPointsDisabled)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/KdBootSessionEvidence.psm1')
function Assert-PlainPath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'REDIRECT_BOUNDED_CONTROL_REPARSE_PATH'}
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Read-Json([string]$Path) {
    Assert-PlainPath $Path
    if ((Get-Item -LiteralPath $Path).Length -gt 16MB) {throw 'REDIRECT_BOUNDED_CONTROL_JSON_TOO_LARGE'}
    $text=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {return ConvertFrom-Json -InputObject $text -DateKind String}
    return ConvertFrom-Json -InputObject $text
}
if (-not $PreparationDirectory) {
    if ($Phase -ne 'Prepare') {throw 'REDIRECT_BOUNDED_CONTROL_PREPARATION_REQUIRED'}
    $PreparationDirectory=Join-Path $root ('artifacts/diagnostics/pb-redirect-bounded-control-preparation-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
}
$PreparationDirectory=[IO.Path]::GetFullPath($PreparationDirectory)
$prefix=[IO.Path]::GetFullPath((Join-Path $root 'artifacts/diagnostics'))+[IO.Path]::DirectorySeparatorChar
if (-not $PreparationDirectory.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $PreparationDirectory) -notmatch '^pb-redirect-bounded-control-preparation-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') {throw 'REDIRECT_BOUNDED_CONTROL_DIRECTORY_INVALID'}
Assert-PlainPath $PreparationDirectory
if ($Phase -eq 'Prepare') {
    $sourcePython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    $bootInput=Join-Path $root ('artifacts/diagnostics/pb-redirect-bounded-control-boot-input-'+[guid]::NewGuid().ToString('N')+'.json')
    Get-KdBootSessionEvidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $bootInput -Encoding UTF8
    & $sourcePython -B (Join-Path $root 'src/pb_prepare_redirect_bounded_control.py') --root $root --output $PreparationDirectory --python $sourcePython --boot-evidence $bootInput
    if ($LASTEXITCODE -ne 0) {throw 'REDIRECT_BOUNDED_CONTROL_PREPARATION_FAILED'}
}
$planPath=Join-Path $PreparationDirectory 'runtime-plan.json'
$plan=Read-Json $planPath
$python=Join-Path $PreparationDirectory 'runtime/python/python.exe'
if ($plan.schema_version -ne 1 -or $plan.method -cne 'redirect-context-bounded-control-v1' -or -not $plan.diagnostic_only -or $plan.performance_comparable -or
    $plan.root -ine $root -or $plan.preparation -ine $PreparationDirectory -or $plan.python -ine $python -or $plan.files.Count -lt 50) {throw 'REDIRECT_BOUNDED_CONTROL_PLAN_INVALID'}
$policy=$plan.control_policy
if ($policy.method -cne 'redirect-context-bounded-control-v1' -or ($policy.phase_connections -join ',') -cne '4,64,256,4' -or
    $policy.total_connections -ne 328 -or ($policy.load_levels -join ',') -cne '64,256' -or $policy.hold_seconds -ne 8 -or
    $policy.connect_method -cne 'ConnectEx' -or $policy.pending_limit -ne 32 -or -not $policy.original_single_query -or
    $policy.listener_case -cne 'original' -or $policy.listener_delay_ms -ne 0 -or $policy.debugger_points -cne 'disabled' -or
    @($policy.active_point_ids).Count -ne 0 -or ($policy.registered_point_ids -join ',') -cne '2,3' -or ($policy.inactive_point_ids -join ',') -cne '2,3' -or
    $policy.automatic_load_authorized -or $policy.bounded_load_user_ack_required -or $policy.logger_verification_required_before_load -or
    $policy.cohort_budget_ms -ne 240000 -or $policy.client_wait_limit_ms -ne 120000 -or -not $policy.final_four_same_session -or
    $policy.driver_installation -or $policy.automatic_debugger_control -or -not $policy.diagnostic_only -or $policy.performance_comparable) {throw 'REDIRECT_BOUNDED_CONTROL_POLICY_INVALID'}
$seen=@{}
foreach ($file in $plan.files) {
    Assert-PlainPath $file.path
    if ($seen.ContainsKey([string]$file.path) -or $file.sha256 -notmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $file.path).Hash -ine $file.sha256) {throw 'REDIRECT_BOUNDED_CONTROL_FROZEN_FILE_CHANGED'}
    $seen[[string]$file.path]=$true
}
foreach ($required in @('scripts/Invoke-RedirectContextBoundedControl.ps1','scripts/Invoke-RedirectContextBoundedControlWorkload.ps1',
    'modules/KdQueryBoundedConnectionLoad.psm1','modules/InterceptionState.psm1','src/pb_prepare_redirect_bounded_control.py',
    'src/pb_tcp_redirect_bounded_control_report.py','src/pb_tcp_redirect_context_report.py')) {
    if (-not $seen.ContainsKey((Join-Path $root $required))) {throw 'REDIRECT_BOUNDED_CONTROL_CONTRACT_NOT_FROZEN'}
}
$runtimeRoot=Join-Path $PreparationDirectory 'runtime/python'
$runtimeManifestPath=Join-Path $PreparationDirectory 'runtime/manifest.json'
if (-not $seen.ContainsKey($runtimeManifestPath) -or $plan.runtime_manifest_sha256 -notmatch '^[a-f0-9]{64}$' -or
    (Get-FileHash -LiteralPath $runtimeManifestPath).Hash -ine $plan.runtime_manifest_sha256) {throw 'REDIRECT_BOUNDED_CONTROL_RUNTIME_MANIFEST_CHANGED'}
$runtimeManifest=Read-Json $runtimeManifestPath
$runtimeEntries=@($runtimeManifest.files.PSObject.Properties)
$actualRuntime=@(Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File -Force)
if ($runtimeEntries.Count -ne $runtimeManifest.copied_files -or $actualRuntime.Count -ne $runtimeEntries.Count -or
    -not $runtimeManifest.isolated_pth -or $runtimeManifest.import_site -or $runtimeManifest.source_runtime_reused_at_run) {throw 'REDIRECT_BOUNDED_CONTROL_RUNTIME_INVENTORY_CHANGED'}
foreach ($entry in $runtimeEntries) {
    $path=[IO.Path]::GetFullPath((Join-Path $runtimeRoot $entry.Name))
    if (-not $path.StartsWith(([IO.Path]::GetFullPath($runtimeRoot)+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or
        -not $seen.ContainsKey($path) -or $entry.Value -notmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $path).Hash -ine $entry.Value) {throw 'REDIRECT_BOUNDED_CONTROL_RUNTIME_FILE_CHANGED'}
}
$bootEvidencePath=Join-Path $PreparationDirectory 'debugger-evidence/boot-session.json'
if ($plan.boot_binding.method -cne 'kernel-general-12-and-prefetch-bootid-v1' -or
    $plan.boot_binding.path -ine $bootEvidencePath -or -not $seen.ContainsKey($bootEvidencePath) -or
    -not $seen.ContainsKey((Join-Path $root 'modules/KdBootSessionEvidence.psm1')) -or
    (Get-FileHash -LiteralPath $bootEvidencePath).Hash -ine $plan.boot_binding.sha256) {throw 'KD_BOOT_BINDING_NOT_FROZEN'}
$bootEvidence=Read-Json $bootEvidencePath
Assert-KdBootSessionEvidence -Expected $bootEvidence -Actual $bootEvidence
$kit=Join-Path $PreparationDirectory 'kit'
$receipt=Read-Json (Join-Path $kit 'redirect-context-diagnostic.json')
if ($receipt.method -cne 'redirect-context-bounded-control-v1' -or
    ($receipt.control_policy | ConvertTo-Json -Depth 8 -Compress) -cne ($policy | ConvertTo-Json -Depth 8 -Compress)) {throw 'REDIRECT_BOUNDED_CONTROL_RECEIPT_POLICY_DIFFERS'}
$pinned=@{'ProxyBridge_CLI.exe'='ad83b3aad22252be0ab20a6c26470f7c364930af35089e9904f1dd0d29bb40ca';
    'ProxyBridgeCore.dll'='7dc8952e7562ac4dff3cf278136d1fe8fd44474885f707c93c220f94e9f624ed';
    'ProxyBridgeDrv.sys'='3cd79cfc2a9ec6e45a11b2c225d11cb18c504fec3535e3ef1cb730e0e7732c9e'}
if ($receipt.components.Count -ne 3) {throw 'REDIRECT_BOUNDED_CONTROL_COMPONENT_COUNT_INVALID'}
$components=@{}
foreach ($component in $receipt.components) {
    if (-not $pinned.ContainsKey([string]$component.name) -or $components.ContainsKey([string]$component.name) -or
        $component.sha256 -cne $pinned[[string]$component.name] -or
        (Get-FileHash -LiteralPath (Join-Path $kit $component.name)).Hash -ine $component.sha256) {throw 'REDIRECT_BOUNDED_CONTROL_COMPONENT_DIFFERS'}
    $components[[string]$component.name]=$true
}
foreach ($name in @('product.env','redirect-context-diagnostic.json','ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys')) {
    if (-not $seen.ContainsKey((Join-Path $kit $name))) {throw 'REDIRECT_BOUNDED_CONTROL_KIT_NOT_FROZEN'}
}
if ($Phase -ne 'Run') {
    [ordered]@{status='REDIRECT_BOUNDED_CONTROL_FILES_VALIDATED';preparation_directory=$PreparationDirectory;files=$plan.files.Count;
        runtime_files=$runtimeEntries.Count;connections=328;product_started=$false;driver_installed=$false;
        traffic_generated=$false;debugger_control=$false;runtime_ready=$false} | ConvertTo-Json
    return
}
if (-not $DebuggerPointsDisabled) {throw 'REDIRECT_BOUNDED_CONTROL_REQUIRES_USER_CONFIRMED_DISABLED_POINTS'}
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
    foreach ($pattern in @('tcp-redirect-context-run-*','pb-kd-baseline-run-*','pb-kd-packet-baseline-run-*','pb-kd-minimal-baseline-run-*','pb-redirect-control-run-*','pb-kd-query-probe-run-*','pb-kd-query-session-run-*','pb-kd-query-bounded-run-*','pb-kd-accept-query-run-*','pb-kd-accept-query-bounded-run-*','pb-kd-retrieve-query-run-*','pb-kd-retrieve-query-bounded-run-*','pb-redirect-bounded-control-run-*')) {
        foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/diagnostics') -Directory -Filter $pattern)) {
            $file=Join-Path $directory.FullName 'diagnostic-run.json'
            if (Test-Path -LiteralPath $file) {
                $saved=Read-Json $file
                if ($saved.status -eq 'RUNNING' -and $boot -le [DateTimeOffset]::Parse([string]$saved.started_at_utc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_DIAGNOSTIC'}
            }
        }
    }
    $evidence=Join-Path $root ('artifacts/diagnostics/pb-redirect-bounded-control-run-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $null=New-Item -ItemType Directory -Path $evidence
    $run=[ordered]@{status='RUNNING';diagnostic_only=$true;performance_comparable=$false;started_at_utc=[DateTime]::UtcNow.ToString('o');
        runtime_plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash;workload_directory='workload';debugger_disabled_user_acknowledged=$true;active_point_ids=@();registered_point_ids=@(2,3);inactive_point_ids=@(2,3);
        debugger_coverage_verified=$false;driver_installation=$false;error=''}
    $currentBoot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'boot-session-before-run.json') -Encoding UTF8
    Copy-Item -LiteralPath $planPath -Destination (Join-Path $evidence 'runtime-plan.json')
    Copy-Item -LiteralPath (Join-Path $kit 'redirect-context-diagnostic.json') -Destination (Join-Path $evidence 'diagnostic-build.json')
    $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
    try {
        [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','original','Process')
        Write-Host 'Redirect bounded control: 4 -> 64 -> 256 -> 4 (328), точки WinDbg отключены. Вся VM может замедлиться или остановиться.'
        & (Join-Path $PSScriptRoot 'Invoke-RedirectContextBoundedControlWorkload.ps1') -Duration SHORT -Load HIGH -EnvPath (Join-Path $kit 'product.env') -PythonPath $python -EvidenceDirectory (Join-Path $evidence 'workload') -DiagnosticRedirectContext -DiagnosticConnectionCase connectex-32 -DiagnosticFixtureCloseGuard -DebuggerPointsDisabled
        $run.status='REDIRECT_BOUNDED_CONTROL_CONTROLLER_RETURNED'
    } catch {$run.status='FAILED';$run.error=$_.Exception.Message;throw}
    finally {
        $run['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
        $run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
        Write-Host ('Redirect bounded control results / Результаты: '+$evidence)
        Write-Host 'Точки WinDbg оставить отключёнными. Сохраните весь вывод и каталог результатов. Не повторять Run до разбора.'
    }
} finally {
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE',$previousRoute,'Process')
    if ($lease) {$lease.Dispose()}
    if ($owns) {$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
