[CmdletBinding()]
param([ValidateSet('Prepare','Inspect','Run')][string]$Phase='Inspect',
    [string]$PreparationDirectory='',[switch]$DebuggerLoggerEnabled)
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
    $PreparationDirectory=Join-Path $root ('artifacts/diagnostics/pb-kd-baseline-preparation-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
}
$PreparationDirectory=[IO.Path]::GetFullPath($PreparationDirectory)
$prefix=[IO.Path]::GetFullPath((Join-Path $root 'artifacts/diagnostics'))+[IO.Path]::DirectorySeparatorChar
if (-not $PreparationDirectory.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $PreparationDirectory) -notmatch '^pb-kd-baseline-preparation-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') {throw 'KD_BASELINE_DIRECTORY_INVALID'}
Assert-PlainPath $PreparationDirectory
if ($Phase -eq 'Prepare') {
    & $python (Join-Path $root 'src/pb_prepare_kd_baseline.py') --root $root --output $PreparationDirectory --python $python
    if ($LASTEXITCODE -ne 0) {throw 'KD_BASELINE_PREPARATION_FAILED'}
}
$planPath=Join-Path $PreparationDirectory 'runtime-plan.json'
$plan=Read-Json $planPath
if ($plan.schema_version -ne 1 -or $plan.method -cne 'kd-owned-four-v1' -or -not $plan.diagnostic_only -or $plan.performance_comparable -or
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
$kit=Join-Path $PreparationDirectory 'kit'
foreach ($required in @('product.env','redirect-context-diagnostic.json','ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys')) {
    if (-not $seen.ContainsKey((Join-Path $kit $required))) {throw 'KD_BASELINE_KIT_NOT_FROZEN'}
}
$receipt=Read-Json (Join-Path $kit 'redirect-context-diagnostic.json')
if ($receipt.method -cne 'redirect-kd-baseline-v5' -or -not $receipt.PSObject.Properties['components'] -or $receipt.components.Count -ne 3) {throw 'KD_BASELINE_COMPONENT_RECEIPT_INCOMPLETE'}
$componentNames=@{}
foreach ($component in $receipt.components) {
    if ($component.name -cnotin @('ProxyBridge_CLI.exe','ProxyBridgeCore.dll','ProxyBridgeDrv.sys') -or $componentNames.ContainsKey([string]$component.name) -or
        $component.sha256 -notmatch '^[a-f0-9]{64}$' -or $component.sha256 -cne $receipt.reused_binary_sha256.($component.name) -or
        (Get-FileHash -LiteralPath (Join-Path $kit $component.name)).Hash -ine $component.sha256) {throw 'KD_BASELINE_COMPONENT_RECEIPT_DIFFERS'}
    $componentNames[[string]$component.name]=$true
}
if ($Phase -ne 'Run') {
    [ordered]@{status='KD_BASELINE_FILES_VALIDATED';preparation_directory=$PreparationDirectory;files=$plan.files.Count;
        connections=4;load_levels=@();product_started=$false;driver_installed=$false;traffic_generated=$false;
        debugger_coverage_verified=$false;runtime_ready=$false} | ConvertTo-Json
    return
}
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
    foreach ($pattern in @('tcp-redirect-context-run-*','pb-kd-baseline-run-*')) {
        foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/diagnostics') -Directory -Filter $pattern)) {
            $file=Join-Path $directory.FullName 'diagnostic-run.json'
            if (Test-Path -LiteralPath $file) {
                $saved=Read-Json $file
                if ($saved.status -eq 'RUNNING' -and $boot -le [DateTimeOffset]::Parse([string]$saved.started_at_utc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_DIAGNOSTIC'}
            }
        }
    }
    $evidence=Join-Path $root ('artifacts/diagnostics/pb-kd-baseline-run-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $null=New-Item -ItemType Directory -Path $evidence
    $run=[ordered]@{status='RUNNING';diagnostic_only=$true;performance_comparable=$false;started_at_utc=[DateTime]::UtcNow.ToString('o');
        runtime_plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash;workload_directory='workload';debugger_enabled_user_acknowledged=$true;
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
        Write-Host 'На физическом хосте отключите только наши точки 0..13, затем отдельно g. Сохраните существующий лог WinDbg.'
    }
} finally {
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE',$previousRoute,'Process')
    if ($lease) {$lease.Dispose()}
    if ($owns) {$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
