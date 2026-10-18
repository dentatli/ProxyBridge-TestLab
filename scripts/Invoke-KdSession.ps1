[CmdletBinding()]
param(
    [ValidateSet('RegisterAssets','Prepare','Inspect','Run')][string]$Phase='Inspect',
    [string]$SeedPlan='',[string]$ExpectedSha='',
    [string]$SharedAssets='',[string]$SharedAssetsSha='',
    [string]$DebuggerProfile='',[string]$RegistrationReview='',
    [ValidateSet('four','bounded256')][string]$Workload='four',
    [string]$PlanPath='',[string]$PlanSha='',
    [switch]$ProfileReviewed,[switch]$DebuggerLoggerEnabled,[switch]$BoundedLoadReviewed,
    [switch]$DebuggerPointsDisabled
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/KdBootSessionEvidence.psm1')
$sourcePython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$entry=Join-Path $root 'src/pb_kd_session.py'
function Assert-PlainPath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'KD_SESSION_REPARSE_PATH'}
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Read-Json([string]$Path) {
    Assert-PlainPath $Path
    if ((Get-Item -LiteralPath $Path).Length -gt 16MB) {throw 'KD_SESSION_JSON_TOO_LARGE'}
    $text=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {return ConvertFrom-Json -InputObject $text -DateKind String}
    return ConvertFrom-Json -InputObject $text
}
function Invoke-SessionFiles($Arguments) {
    $output=& $sourcePython -B $entry @Arguments
    if ($LASTEXITCODE -ne 0) {throw 'KD_SESSION_FILE_VALIDATION_FAILED: product not started'}
    return ($output -join "`n")
}
if ($Phase -eq 'RegisterAssets') {
    if (-not $SeedPlan -or -not $ExpectedSha) {throw 'KD_SESSION_SEED_AND_SHA_REQUIRED'}
    Invoke-SessionFiles @('register-assets','--root',$root,'--seed-plan',$SeedPlan,'--expected-sha',$ExpectedSha)
    return
}
if ($Phase -eq 'Prepare') {
    if (-not $SharedAssets -or -not $SharedAssetsSha -or -not $DebuggerProfile -or -not $RegistrationReview) {throw 'KD_SESSION_ASSETS_PROFILE_REVIEW_REQUIRED'}
    $bootPath=Join-Path $root ('artifacts/diagnostics/pb-kd-session-boot-'+[guid]::NewGuid().ToString('N')+'.json')
    Get-KdBootSessionEvidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $bootPath -Encoding UTF8
    Invoke-SessionFiles @('prepare','--root',$root,'--assets',$SharedAssets,'--assets-sha',$SharedAssetsSha,
        '--profile',$DebuggerProfile,'--review',$RegistrationReview,'--boot',$bootPath,'--workload',$Workload)
    return
}
if (-not $PlanPath -or -not $PlanSha) {throw 'KD_SESSION_PLAN_AND_SHA_REQUIRED'}
$PlanPath=[IO.Path]::GetFullPath($PlanPath)
$validated=Invoke-SessionFiles @('validate','--root',$root,'--plan',$PlanPath,'--expected-sha',$PlanSha)
$plan=Read-Json $PlanPath
$bootEvidence=Read-Json (Join-Path $plan.preparation 'boot-session.json')
Assert-KdBootSessionEvidence -Expected $bootEvidence -Actual $bootEvidence
if ($Phase -eq 'Inspect') {
    [ordered]@{status='KD_SESSION_FILES_VALIDATED';workload=$plan.control_policy.workload;
        connections=$plan.control_policy.total_connections;shared_python=$plan.python;
        product_started=$false;traffic_generated=$false;debugger_control=$false;runtime_ready=$false} | ConvertTo-Json
    return
}
$etwObserver=$plan.control_policy.PSObject.Properties['observer'] -and $plan.control_policy.observer -eq 'etw-tcpip'
if ($etwObserver) {
    if (-not $ProfileReviewed -or -not $DebuggerPointsDisabled -or $DebuggerLoggerEnabled) {throw 'ETW_SESSION_REQUIRES_REVIEW_AND_DISABLED_POINTS'}
    Import-Module (Join-Path $root 'modules/EtwRedirectCapture.psm1')
} elseif (-not $ProfileReviewed -or -not $DebuggerLoggerEnabled -or $DebuggerPointsDisabled) {throw 'KD_SESSION_REQUIRES_USER_PROFILE_AND_ENABLED_POINTS_REVIEW'}
if ($plan.control_policy.workload -ne 'four' -and -not $BoundedLoadReviewed) {throw 'KD_SESSION_BOUNDED_REVIEW_REQUIRED'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'KD_SESSION_RUN_REQUIRES_ADMINISTRATOR'}
if ($etwObserver) {
    # Refuse before consuming a plan or starting helpers; cohort repeats the existing gate.
    $availableBytes=[long](Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5).FreePhysicalMemory*1024
    if ($availableBytes -lt 2147483648L) {throw ('ETW_SESSION_MEMORY_BEFORE_CLAIM: available='+$availableBytes+' required=2147483648; no Run claim or ETW start')}
}
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
    foreach ($pattern in @('pb-kd-session-run-*','tcp-redirect-context-run-*','pb-kd-baseline-run-*','pb-kd-packet-baseline-run-*','pb-kd-minimal-baseline-run-*','pb-redirect-control-run-*','pb-kd-query-probe-run-*','pb-kd-query-session-run-*','pb-kd-query-bounded-run-*','pb-kd-accept-query-run-*','pb-kd-accept-query-bounded-run-*','pb-kd-retrieve-query-run-*','pb-kd-retrieve-query-bounded-run-*','pb-redirect-bounded-control-run-*','pb-kd-lookup-four-run-*','pb-kd-retrieve-null-run-*','pb-kd-retrieve-null-bounded-run-*')) {
        foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'artifacts/diagnostics') -Directory -Filter $pattern)) {
            $file=Join-Path $directory.FullName 'diagnostic-run.json'
            if (Test-Path -LiteralPath $file) {
                $saved=Read-Json $file
                if ($pattern -ceq 'pb-kd-session-run-*' -and $saved.PSObject.Properties['runtime_plan_sha256'] -and
                    $saved.runtime_plan_sha256 -ieq (Get-FileHash -LiteralPath $planPath).Hash) {throw 'KD_SESSION_PLAN_ALREADY_USED'}
                if ($saved.status -eq 'RUNNING' -and $boot -le [DateTimeOffset]::Parse([string]$saved.started_at_utc)) {throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_DIAGNOSTIC'}
            }
        }
    }
    $claim=Join-Path $plan.preparation 'run-claim.json';Assert-PlainPath $claim
    try {
        $claimStream=[IO.File]::Open($claim,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $claimStream.Dispose()
    } catch {throw 'KD_SESSION_PLAN_ALREADY_USED_OR_CLAIM_UNAVAILABLE'}
    $evidence=Join-Path $root ('artifacts/diagnostics/pb-kd-session-run-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $null=New-Item -ItemType Directory -Path $evidence
    $run=[ordered]@{status='RUNNING';method='redirect-kd-session-v1';diagnostic_only=$true;performance_comparable=$false;
        started_at_utc=[DateTime]::UtcNow.ToString('o');runtime_plan_sha256=$PlanSha;
        active_point_ids=$plan.control_policy.active_point_ids;registered_point_ids=$plan.control_policy.registered_point_ids;
        debugger_enabled_user_acknowledged=[bool]$DebuggerLoggerEnabled;profile_reviewed_user_acknowledged=$true;
        frame_reads_runtime_verified=$false;debugger_coverage_verified=$false;driver_installation=$false;error=''}
    Copy-Item -LiteralPath $PlanPath -Destination (Join-Path $evidence 'runtime-plan.json')
    $currentBoot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'boot-session-before-run.json') -Encoding UTF8
    $run | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
    $etwCapture=$null
    try {
        if ($etwObserver) {
            $etwCapture=New-RedirectEtwCapture (Join-Path $evidence 'etw')
            Start-RedirectEtwCapture $etwCapture
        }
        [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','original','Process')
        & (Join-Path $PSScriptRoot 'Invoke-KdSessionWorkload.ps1') -SessionPlan $plan -SessionPlanPath $PlanPath -EvidenceDirectory (Join-Path $evidence 'workload')
        $run.status=if ($etwObserver) {'ETW_SESSION_CONTROLLER_RETURNED_REVIEW_PENDING'} else {'KD_SESSION_CONTROLLER_RETURNED_DEBUGGER_PENDING'}
    } catch {$run.status='FAILED';$run.error=$_.Exception.Message;throw}
    finally {
        if ($etwCapture) {
            try {
                Stop-RedirectEtwCapture $etwCapture
                Export-RedirectEtwCapture $etwCapture
                & $sourcePython -B (Join-Path $root 'src/pb_etw_redirect_report.py') --capture-directory $etwCapture.Directory
                if ($LASTEXITCODE -ne 0) {throw 'ETW_CAPTURE_INCOMPLETE'}
            } catch {$run.status='FAILED';$run.error+='; '+$_.Exception.Message}
        }
        $run['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
        $run | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'diagnostic-run.json') -Encoding UTF8
        Write-Host ('Results: '+$evidence)
        if ($etwObserver) {
            $stopped=($null -ne $etwCapture -and $etwCapture.Stopped)
            Write-Host ('ETW stopped='+$stopped+'; status='+$run.status+'. Review capture/native evidence; leave debugger points disabled; do not repeat Run.')
        }
        else {Write-Host ('Отключить только проверенные IDs: '+($plan.control_policy.active_point_ids -join ', ')+'. Перед Break останавливается вся VM, включая Codex/RDP. Команды по одной; bl, затем отдельно g даже при ошибке. Run не повторять.')}
    }
    if ($run.status -eq 'FAILED') {throw $run.error}
} finally {
    [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE',$previousRoute,'Process')
    if ($lease) {$lease.Dispose()}
    if ($owns) {$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
