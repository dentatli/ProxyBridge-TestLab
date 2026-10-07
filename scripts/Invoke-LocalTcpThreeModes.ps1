[CmdletBinding()]
param([ValidateSet('Inspect','Run')][string]$Phase='Inspect')
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
# Fixed existing kit and controller; no arbitrary paths/versions or resume.
Import-Module (Join-Path $root 'modules/Env.psm1')
Import-Module (Join-Path $root 'modules/ProductBuild.psm1')
$envPath=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env'
Assert-NoReparse $envPath
$identity=Get-ProductBuildIdentity -Environment (Import-DotEnv -Path $envPath) -Contract driver
if (-not $identity.files_verified -or $identity.declared_source_commit -ne '63be0ebf9bec92bfba95ef3d6729c375aa9af84e' -or $identity.declared_cli_variant -ne 'testlab-unbuffered-v1') { throw 'TCP_THREE_MODES_KNOWN_KIT_REQUIRED' }
$files=@('scripts/Invoke-LocalTcpThreeModes.ps1','scripts/Invoke-LocalTcpRtt.ps1','src/pb_tcp_rtt_report.py','src/pb_tcp_three_mode_report.py','src/pb_net_client.c','src/pb_net_endpoint.py','src/pb_controlled_tcp_proxy.py','src/pb_pc_sampler.py','bin/tcp-rtt/pb_tcp_rtt_client.exe','bin/tcp-rtt/build-receipt.json')
$fingerprints=[ordered]@{}
foreach ($relative in $files) {
    $file=Join-Path $root $relative
    Assert-NoReparse $file
    $fingerprints[$relative]=(Get-FileHash -LiteralPath $file).Hash
}
$receipt=[ordered]@{schema_version=1;comparison_stage='three_modes_readiness_v1';status='FILES_PREPARED';bundle_sha256=$identity.bundle_sha256;source_sha256=$fingerprints;product_started=$false;traffic_generated=$false;runtime_state_observed=$false;global_interception_proof=$false}
if ($Phase -eq 'Inspect') { $receipt | ConvertTo-Json -Depth 4;return }
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'TCP_THREE_MODES_ADMIN_REQUIRED' }
$launchRoot=Join-Path $root 'artifacts/benchmark-launch'
Assert-NoReparse $launchRoot
$null=New-Item -ItemType Directory -Path $launchRoot -Force
$mutex=[Threading.Mutex]::new($false,'Global\ProxyBridgeTestLabPlannedBenchmark')
$ownsMutex=$false;$executionLease=$null;$evidence=$null
try {
    try { $ownsMutex=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex=$true }
    if (-not $ownsMutex) { throw 'LAB_PLANNED_RUN_ALREADY_ACTIVE' }
    $leasePath=Join-Path $launchRoot 'execution.lock'
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
        $stateFile=Join-Path $control.FullName 'job.json'
        if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
            $state=Read-Json $stateFile
            if ($state.status -in @('STARTING','RUNNING','STOPPING','INTERRUPTED') -and $boot -le [DateTimeOffset]::Parse([string]$state.updatedAtUtc)) {
                throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_RUN'
            }
        }
    }
    foreach ($previous in @(Get-ChildItem -LiteralPath $localRoot -Directory -Filter 'tcp-rtt-three-modes-smoke-*')) {
        $file=Join-Path $previous.FullName 'comparison-manifest.json'
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $old=Read-Json $file
            if ($old.status -eq 'RUNNING' -and $boot -le [DateTimeOffset](Get-Item -LiteralPath $file).LastWriteTimeUtc) { throw 'LAB_REBOOT_REQUIRED_AFTER_INTERRUPTED_THREE_MODE_RUN' }
        }
    }
    foreach ($relative in $files) {
        $file=Join-Path $root $relative;Assert-NoReparse $file
        if ((Get-FileHash -LiteralPath $file).Hash -ine $fingerprints[$relative]) { throw 'TCP_THREE_MODES_SOURCE_CHANGED' }
    }
    $receipt['boot_time_utc']=$boot.ToString('o')
    $receipt['guard_checked_at_utc']=[DateTime]::UtcNow.ToString('o')
    $receipt.status='RUNTIME_GUARD_PASSED'
    $receipt.Remove('product_started');$receipt.Remove('traffic_generated')
    $receipt['scope']='files-and-pre-controller-guard; workload verdict is in run receipts'
    $evidence=Join-Path $localRoot ('tcp-rtt-three-modes-smoke-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    Assert-NoReparse $evidence
    # Existing controller owns product lifecycle and cleanup; lease lasts through cleanup.
    & (Join-Path $root 'scripts/Invoke-LocalTcpRtt.ps1') -Profile SMOKE -ProductContract driver -ThreeModes -EnvPath $envPath -EvidenceDirectory $evidence
} finally {
    try {
        if ($evidence -and (Test-Path -LiteralPath $evidence -PathType Container)) {
            $receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'launch-preflight.json') -Encoding UTF8
        }
    } finally {
        if ($null -ne $executionLease) { $executionLease.Dispose() }
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
