[CmdletBinding()]
param([Parameter(Mandatory)][string]$DiagnosticDirectory,
    [ValidateSet('Prepare','Inspect','Install','Run')][string]$Phase='Inspect')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$inner=Join-Path $PSScriptRoot 'Invoke-KernelContextDiagnostic.ps1'
$profile=Join-Path $root 'config/tcp-context-status-diagnostic.wprp'
$wpr=Join-Path $env:SystemRoot 'System32/wpr.exe'
$DiagnosticDirectory=[IO.Path]::GetFullPath($DiagnosticDirectory)
$planPath=Join-Path $DiagnosticDirectory 'tcp-context-status-plan.json'
function Read-SetupJson([string]$Path) {
    if ((Get-Item -LiteralPath $Path).Length -gt 1MB) {throw 'TCP_SETUP_JSON_TOO_LARGE'}
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}
function Assert-SetupPlainPath([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'TCP_SETUP_REPARSE_POINT'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
}
Assert-SetupPlainPath $DiagnosticDirectory
& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase $(if ($Phase -eq 'Prepare') {'Prepare'} else {'Inspect'})
if ($Phase -eq 'Prepare') {
    if (Test-Path -LiteralPath $planPath) {throw 'TCP_SETUP_PLAN_ALREADY_EXISTS'}
    $files=@($PSCommandPath,$profile,$wpr,(Join-Path $DiagnosticDirectory 'runtime-plan.json'),(Join-Path $env:SystemRoot 'System32/mswsock.dll'),(Join-Path $env:SystemRoot 'System32/drivers/tcpip.sys'),(Join-Path $env:SystemRoot 'System32/drivers/afd.sys'))
    $hashes=@($files | ForEach-Object {Assert-SetupPlainPath $_;[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})
    [ordered]@{schema_version=1;method='tcp-context-status-etw-v1';diagnostic_only=$true;performance_comparable=$false;packet_payload_provider_enabled=$false;
        winsock_status_provider='ac7ff34d-58da-490c-843e-57baeb1bafef';winsock_status_event_id=11;winsock_status_keyword='0x2';winsock_trace_guid='97dcf1eb-61bd-3c9f-e009-df6b3349ea30';winsock_payload_bytes=20;event_ids=@(1004,1008,1009,1014,1015,1016,1017,1033,1055,1063,1186,1214,1315,1416,1477,1553);raw_trace_limit_mib=32;profile_name='TestLabTcpContextStatus';files=$hashes} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $planPath -Encoding UTF8
}
Assert-SetupPlainPath $planPath
$plan=Read-SetupJson $planPath
if ($plan.schema_version -ne 1 -or $plan.method -cne 'tcp-context-status-etw-v1' -or -not $plan.diagnostic_only -or $plan.performance_comparable -or
    $plan.winsock_status_provider -cne 'ac7ff34d-58da-490c-843e-57baeb1bafef' -or $plan.winsock_status_event_id -ne 11 -or $plan.winsock_status_keyword -cne '0x2' -or $plan.winsock_trace_guid -cne '97dcf1eb-61bd-3c9f-e009-df6b3349ea30' -or $plan.winsock_payload_bytes -ne 20 -or $plan.packet_payload_provider_enabled -or $plan.raw_trace_limit_mib -ne 32 -or $plan.profile_name -cne 'TestLabTcpContextStatus' -or
    (@($plan.event_ids) -join ',') -cne '1004,1008,1009,1014,1015,1016,1017,1033,1055,1063,1186,1214,1315,1416,1477,1553' -or $plan.files.Count -ne 7) {throw 'TCP_SETUP_PLAN_INVALID'}
$expectedPaths=@($PSCommandPath,$profile,$wpr,(Join-Path $DiagnosticDirectory 'runtime-plan.json'),(Join-Path $env:SystemRoot 'System32/mswsock.dll'),(Join-Path $env:SystemRoot 'System32/drivers/tcpip.sys'),(Join-Path $env:SystemRoot 'System32/drivers/afd.sys'))
if ((@($plan.files.path | Sort-Object) -join '|') -ine (@($expectedPaths | Sort-Object) -join '|')) {throw 'TCP_SETUP_FROZEN_PATH_BINDING_INVALID'}
foreach ($file in $plan.files) {Assert-SetupPlainPath $file.path;if ($file.sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $file.path).Hash -ine $file.sha256) {throw 'TCP_SETUP_FROZEN_FILES_CHANGED'}}
if ($Phase -in @('Prepare','Inspect')) {Write-Host 'TCP setup trace files validated; no trace/product started.';return}
if ($Phase -eq 'Install') {& $inner -DiagnosticDirectory $DiagnosticDirectory -Phase Install;return}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'TCP_SETUP_REQUIRES_ADMINISTRATOR'}
$traceDirectory=Join-Path $root ('artifacts/diagnostics/tcp-context-status-trace-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
Assert-SetupPlainPath $traceDirectory
$null=New-Item -ItemType Directory -Path $traceDirectory
$receipt=[ordered]@{schema_version=1;method='tcp-context-status-etw-v1';diagnostic_only=$true;performance_comparable=$false;status='PREPARING';
    diagnostic_directory=$DiagnosticDirectory;trace_directory=$traceDirectory;started_at_utc=[DateTime]::UtcNow.ToString('o');
    setup_plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash.ToLowerInvariant();runtime_plan_sha256=(Get-FileHash -LiteralPath (Join-Path $DiagnosticDirectory 'runtime-plan.json')).Hash.ToLowerInvariant();
    event_ids=@($plan.event_ids);winsock_status_provider=$plan.winsock_status_provider;winsock_status_event_id=11;winsock_status_keyword='0x2';winsock_trace_guid=$plan.winsock_trace_guid;winsock_payload_bytes=20;winsock_status_emission_verified=$false;owned_query_status_correlation_verified=$false;packet_payload_provider_enabled=$false;capture_scope='selected whole-PC TCP and Winsock error metadata; provider/trace-GUID/20-byte payload/PID/TID/QPC query matching required';
    raw_trace_limit_mib=32;wpr_started=$false;wpr_stopped=$false;trace_saved=$false;raw_limit_observed=$false;
    native_verdict_overridden=$false;capture_completeness_verified=$false;root_cause_proven=$false;workload_result_directory='';workload_error='';error='';log_errors=@()}
function Save-SetupReceipt {$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $traceDirectory 'tcp-context-status-receipt.json') -Encoding UTF8}
function Get-SetupClock {
    $before=[Diagnostics.Stopwatch]::GetTimestamp();$utc=[DateTime]::UtcNow.ToFileTimeUtc();$after=[Diagnostics.Stopwatch]::GetTimestamp()
    [ordered]@{qpc_before=$before;utc_filetime=$utc;qpc_after=$after;frequency=[Diagnostics.Stopwatch]::Frequency}
}
function Invoke-SetupWpr([string[]]$Arguments,[string]$LogName) {
    $prior=$ErrorActionPreference
    try {$ErrorActionPreference='Continue';$output=@(& $wpr @Arguments 2>&1);$code=$LASTEXITCODE} finally {$ErrorActionPreference=$prior}
    $text=$output | Out-String
    try {$text | Set-Content -LiteralPath (Join-Path $traceDirectory $LogName) -Encoding UTF8} catch {$receipt.log_errors+=($LogName+': '+$_.Exception.Message)}
    [pscustomobject]@{exit_code=$code;text=$text}
}
function Invoke-SetupCapture {
    $ownsRecording=$false;$lines=[Collections.Generic.List[string]]::new()
    try {
        $idle=Invoke-SetupWpr @('-status') 'wpr-status-before.txt'
        if ($idle.exit_code -ne 0 -or $idle.text -notmatch '(?im)^\s*WPR (is not recording|recording is not in progress)\s*\.?\s*$') {throw 'TCP_SETUP_OTHER_RECORDING_PRESERVED'}
        $copiedProfile=Join-Path $traceDirectory 'tcp-context-status-diagnostic.wprp'
        Copy-Item -LiteralPath $profile -Destination $copiedProfile
        $receipt['clock_before_start']=Get-SetupClock
        $started=Invoke-SetupWpr @('-start',($copiedProfile+'!TestLabTcpContextStatus'),'-filemode','-recordtempto',$traceDirectory) 'wpr-start.txt'
        # WPR can accept a configuration with exit 0 and print an error; stop only this newly accepted recording.
        $ownsRecording=($started.exit_code -eq 0)
        if ($started.exit_code -ne 0 -or $started.text -match '(?i)0x[c8][0-9a-f]{7}') {throw 'TCP_SETUP_WPR_START_FAILED'}
        $receipt.wpr_started=$true;$receipt.status='RECORDING';$receipt['clock_recording_ready']=Get-SetupClock;Save-SetupReceipt
        Write-Host 'TCP setup + original Winsock status before 10022: selected event 11/keyword 2; same Core/kernel and three route cases. Approximately 6–12 minutes plus trace save. Absence of an event is not proof of absent context; not a performance comparison.'
        try {
            & $inner -DiagnosticDirectory $DiagnosticDirectory -Phase Run *>&1 | ForEach-Object {$lines.Add($_.ToString());Write-Host $_.ToString()}
        } catch {$receipt.workload_error=$_.Exception.Message;$lines.Add($_.ToString())}
        $receipt['clock_workload_finished']=Get-SetupClock
        [IO.File]::WriteAllLines((Join-Path $traceDirectory 'workload-output.txt'),$lines,[Text.UTF8Encoding]::new($true))
        $resultMatches=@([regex]::Matches(($lines -join "`n"),'(?im)^(?:Diagnostic results / Диагностические результаты):\s*(C:\\src\\ProxyBridge-TestLab\\artifacts\\diagnostics\\tcp-redirect-context-run-[0-9]{8}-[0-9]{6}-[a-f0-9]{8})\s*$'))
        if ($resultMatches.Count -eq 1) {$receipt.workload_result_directory=$resultMatches[0].Groups[1].Value}
        else {throw 'TCP_SETUP_WORKLOAD_RESULT_BINDING_MISSING'}
        $receipt.status='WORKLOAD_FINISHED'
    } catch {$receipt.status='FAILED';$receipt.error=$_.Exception.Message}
    finally {
        if ($ownsRecording) {
            try {
                $rawFiles=@(Get-ChildItem -LiteralPath $traceDirectory -File -Filter '*.etl')
                $receipt.raw_limit_observed=@($rawFiles | Where-Object {$_.Length -ge 32MB}).Count -gt 0
                $null=Invoke-SetupWpr @('-status','collectors') 'wpr-collectors-before-stop.txt'
                $trace=Join-Path $traceDirectory 'tcp-context-status.etl'
                $stop=Invoke-SetupWpr @('-stop',$trace,'TestLab owned TCP setup metadata diagnosis','-skipPdbGen') 'wpr-stop.txt'
                $receipt.wpr_stopped=($stop.exit_code -eq 0)
                $receipt.trace_saved=$receipt.wpr_stopped -and (Test-Path -LiteralPath $trace -PathType Leaf) -and (Get-Item -LiteralPath $trace).Length -gt 0
                if (-not $receipt.trace_saved) {throw 'TCP_SETUP_TRACE_SAVE_UNCONFIRMED'}
                $receipt['trace_bytes']=(Get-Item -LiteralPath $trace).Length;$receipt['trace_sha256']=(Get-FileHash -LiteralPath $trace).Hash.ToLowerInvariant()
                if ($receipt.trace_bytes -gt 128MB) {$receipt.raw_limit_observed=$true}
                if (-not $receipt.error) {$receipt.status=if ($receipt.raw_limit_observed) {'TRACE_SAVED_LIMIT_OBSERVED'} else {'TRACE_SAVED_ANALYSIS_PENDING'}}
            } catch {$receipt.status='FAILED';$receipt.error+='; '+$_.Exception.Message}
        }
        $receipt['clock_after_stop']=Get-SetupClock;$receipt['completed_at_utc']=[DateTime]::UtcNow.ToString('o');Save-SetupReceipt
    }
}
$traceMutex=[Threading.Mutex]::new($false,'Global\ProxyBridgeTestLabTcpContextStatusTrace');$ownsMutex=$false
Save-SetupReceipt
try {
    try {$ownsMutex=$traceMutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$ownsMutex=$true}
    if (-not $ownsMutex) {throw 'TCP_SETUP_TRACE_ALREADY_ACTIVE'}
    Invoke-SetupCapture
} catch {
    $receipt.status='FAILED';$receipt.error+='; '+$_.Exception.Message;Save-SetupReceipt
} finally {if ($ownsMutex) {$traceMutex.ReleaseMutex()};$traceMutex.Dispose()}
Write-Host ('TCP context status trace results / Результаты статуса TCP context: '+$traceDirectory)
if ($receipt.status -eq 'FAILED') {throw $receipt.error}
if ($receipt.workload_error) {throw $receipt.workload_error}
Write-Host 'Trace saved; status emission, payload, loss/clock and exact owned query correlation remain to be checked. Native errors remain errors.'
