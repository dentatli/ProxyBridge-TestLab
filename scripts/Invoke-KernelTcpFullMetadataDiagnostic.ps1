[CmdletBinding()]
param([Parameter(Mandatory)][string]$DiagnosticDirectory,
    [ValidateSet('Prepare','Inspect','Install','Run','Restore')][string]$Phase='Inspect')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$DiagnosticDirectory=[IO.Path]::GetFullPath($DiagnosticDirectory)
$inner=Join-Path $PSScriptRoot 'Invoke-KernelContextDiagnostic.ps1'
$profile=Join-Path $root 'config/tcp-wfp-full-metadata.wprp'
$module=Join-Path $root 'modules/FullMetadataDiagnostic.psm1'
$decoder=Join-Path $root 'bin/pb_read_wfp_etl.exe'
$coverage=Join-Path $root 'src/pb_wfp_full_coverage.py'
$planPath=Join-Path $DiagnosticDirectory 'full-metadata-plan.json'
function Assert-FullPlainPath([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'FULL_METADATA_REPARSE_POINT'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
}
Assert-FullPlainPath $DiagnosticDirectory
$build=Get-Content -LiteralPath (Join-Path $DiagnosticDirectory 'kit/redirect-context-diagnostic.json') -Raw | ConvertFrom-Json
if (-not $build.PSObject.Properties['full_metadata_policy']) {throw 'FULL_METADATA_KIT_REQUIRED'}
Import-Module $module
Assert-FullMetadataPolicy $build.full_metadata_policy
& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase $(if ($Phase -eq 'Prepare') {'Prepare'} else {'Inspect'})
$paths=@($PSCommandPath,$module,$profile,$decoder,$coverage,(Join-Path $root 'src/pb_read_wfp_etl.cpp'),(Join-Path $DiagnosticDirectory 'runtime-plan.json'),
    (Join-Path $env:SystemRoot 'System32/wpr.exe'),(Join-Path $env:SystemRoot 'System32/netsh.exe'),(Join-Path $env:SystemRoot 'System32/mswsock.dll'),
    (Join-Path $env:SystemRoot 'System32/drivers/tcpip.sys'),(Join-Path $env:SystemRoot 'System32/drivers/afd.sys'),(Join-Path $env:SystemRoot 'System32/drivers/NETIO.SYS'))
foreach ($path in $paths) {Assert-FullPlainPath $path}
if ($Phase -eq 'Prepare') {
    if (Test-Path -LiteralPath $planPath) {throw 'FULL_METADATA_PLAN_ALREADY_EXISTS'}
    [ordered]@{schema_version=1;method='full-wfp-afd-capture-v1';policy=$build.full_metadata_policy;
        profile_name='TestLabTcpWfpFullMetadata';winsock_trace_guid='97dcf1eb-61bd-3c9f-e009-df6b3349ea30';winsock_payload_bytes=4;
        wfp_provider='00e7ee66-5b24-5c41-22cb-af98f63e2f90';afd_provider='e53c6823-7bb8-44bb-90dc-3f86090d48a6';
        files=@($paths | ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8
}
Assert-FullPlainPath $planPath
$plan=Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
if ($plan.schema_version -ne 1 -or $plan.method -cne 'full-wfp-afd-capture-v1' -or $plan.profile_name -cne 'TestLabTcpWfpFullMetadata' -or
    $plan.winsock_payload_bytes -ne 4 -or $plan.winsock_trace_guid -cne '97dcf1eb-61bd-3c9f-e009-df6b3349ea30' -or
    $plan.wfp_provider -cne '00e7ee66-5b24-5c41-22cb-af98f63e2f90' -or $plan.afd_provider -cne 'e53c6823-7bb8-44bb-90dc-3f86090d48a6' -or
    @($plan.files).Count -ne $paths.Count -or (@($plan.files.path | Sort-Object) -join '|') -ine (@($paths | Sort-Object) -join '|') -or
    ($plan.policy | ConvertTo-Json -Depth 6 -Compress) -cne ($build.full_metadata_policy | ConvertTo-Json -Depth 6 -Compress)) {throw 'FULL_METADATA_PLAN_INVALID'}
foreach ($file in $plan.files) {Assert-FullPlainPath $file.path;if ($file.sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $file.path).Hash -ine $file.sha256) {throw 'FULL_METADATA_FROZEN_FILES_CHANGED'}}
if ($Phase -in @('Prepare','Inspect')) {Write-Host 'Full metadata files validated. Actual WFP/AFD emission, load capture and root cause pending; no session, product or traffic started.';return}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'FULL_METADATA_REQUIRES_ADMINISTRATOR'}
if ($Phase -in @('Install','Restore')) {& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase $Phase;return}
$directory=Join-Path $root ('artifacts/diagnostics/tcp-wfp-full-trace-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
Assert-FullPlainPath $directory;$null=New-Item -ItemType Directory -Path $directory
$copiedProfile=Join-Path $directory 'tcp-wfp-full-metadata.wprp';Copy-Item -LiteralPath $profile -Destination $copiedProfile
$runtime=Get-Content -LiteralPath (Join-Path $DiagnosticDirectory 'runtime-plan.json') -Raw | ConvertFrom-Json
$state=[ordered]@{directory=$directory;profile=$copiedProfile;wpr=(Join-Path $env:SystemRoot 'System32/wpr.exe');decoder=$decoder;coverage=$coverage;python=$runtime.python;owns_recording=$false;segment='';
    receipt=[ordered]@{schema_version=1;method='full-wfp-afd-capture-v1';diagnostic_only=$true;performance_comparable=$false;status='PREPARING';
        diagnostic_directory=$DiagnosticDirectory;plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash.ToLowerInvariant();segments=@();snapshots=@();
        started_at_utc=[DateTime]::UtcNow.ToString('o');baseline_coverage_confirmed=$false;owned_cli_pid=0;owned_baseline_directory='';
        gap_start_qpc=$null;gap_end_qpc=$null;recording_gap_declared=$true;gap_contains_new_test_cohort=$false;recovery_observed=$false;
        workload_result_directory='';workload_error='';error='';cleanup_errors=@();native_verdict_overridden=$false;
        load_loss_clock_checked=$false;exact_load_object_correlation_verified=$false;private_record_transfer_free_observed=$false;root_cause_proven=$false}}
$mutex=[Threading.Mutex]::new($false,'Global\ProxyBridgeTestLabTcpContextStatusTrace');$ownsMutex=$false
$lines=[Collections.Generic.List[string]]::new()
Save-FullMetadataReceipt $state
try {
    try {$ownsMutex=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$ownsMutex=$true}
    if (-not $ownsMutex) {throw 'FULL_METADATA_CAPTURE_ALREADY_ACTIVE'}
    Save-FullWfpSnapshot $state 'before'
    Start-FullMetadataSegment $state 'baseline'
    $observer=New-FullMetadataPhaseObserver $state
    $state.receipt.status='RECORDING';Save-FullMetadataReceipt $state
    try {& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase Run -DiagnosticPhaseObserver $observer *>&1 | ForEach-Object {$lines.Add($_.ToString());Write-Host $_.ToString()}}
    catch {$state.receipt.workload_error=$_.Exception.Message;$lines.Add($_.ToString())}
    [IO.File]::WriteAllLines((Join-Path $directory 'workload-output.txt'),$lines,[Text.UTF8Encoding]::new($true))
    $matches=@([regex]::Matches(($lines -join "`n"),'(?im)^(?:Diagnostic results / Диагностические результаты):\s*(C:\\src\\ProxyBridge-TestLab\\artifacts\\diagnostics\\tcp-redirect-context-run-[0-9]{8}-[0-9]{6}-[a-f0-9]{8})\s*$'))
    if ($matches.Count -eq 1) {$state.receipt.workload_result_directory=$matches[0].Groups[1].Value} else {throw 'FULL_METADATA_WORKLOAD_BINDING_MISSING'}
    $state.receipt.status='WORKLOAD_FINISHED'
} catch {$state.receipt.error=$_.Exception.Message;$state.receipt.status='FAILED'}
finally {
    if ($ownsMutex) {
        try {Stop-FullMetadataSegment $state} catch {$state.receipt.cleanup_errors+=('trace: '+$_.Exception.Message)}
        try {Save-FullWfpSnapshot $state 'after'} catch {$state.receipt.cleanup_errors+=('snapshot: '+$_.Exception.Message)}
        if ($state.receipt.baseline_coverage_confirmed -and @($state.receipt.segments | Where-Object {$_.name -ceq 'load' -and $_.saved}).Count -eq 1) {
            try {Export-FullMetadataSegment $state 'load';$state.receipt.load_loss_clock_checked=$true} catch {$state.receipt.cleanup_errors+=('decode: '+$_.Exception.Message)}
        }
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose();$state.receipt['recording_stop_confirmed']=-not $state.owns_recording
    $state.receipt['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
    if ($state.receipt.error -or $state.receipt.workload_error -or $state.receipt.cleanup_errors.Count -gt 0 -or -not $state.receipt.baseline_coverage_confirmed -or -not $state.receipt.recovery_observed -or -not $state.receipt.load_loss_clock_checked) {$state.receipt.status='CAPTURE_INCOMPLETE'}
    else {$state.receipt.status='TRACE_SAVED_LOAD_CORRELATION_PENDING'}
    Save-FullMetadataReceipt $state
}
Write-Host ('Full WFP/AFD trace results / Результаты полной WFP/AFD трассы: '+$directory)
Write-Host 'Original errors preserved. Saved events require exact load object correlation; private record loss and root cause are not proved.'
if ($state.receipt.status -eq 'CAPTURE_INCOMPLETE') {throw ('FULL_METADATA_CAPTURE_INCOMPLETE: '+$state.receipt.error+'; '+$state.receipt.workload_error+'; '+($state.receipt.cleanup_errors -join '; '))}
