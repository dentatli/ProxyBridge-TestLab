#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$EvidenceDirectory='', [switch]$TcpStateTrace, [switch]$TcpAckTrace, [switch]$ProxyNoDelay)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$wpr=Join-Path $env:SystemRoot 'System32/wpr.exe'
$profilePath=Join-Path $root 'config/tcp-pull-diagnostic.wprp'
$profileName='TestLabTcpPull'
$minimumFreeBytes=5GB
$stateEnabled=[bool]($TcpStateTrace -or $TcpAckTrace)
if ($TcpStateTrace) {
    $profilePath=Join-Path $root 'config/tcp-pull-state-diagnostic.wprp'
    $profileName='TestLabTcpPullState'
    $minimumFreeBytes=6GB
}
if ($TcpAckTrace) {
    $profilePath=Join-Path $root 'config/tcp-pull-ack-diagnostic.wprp'
    $profileName='TestLabTcpPullAck'
    $minimumFreeBytes=9GB
}
if (-not (Test-Path -LiteralPath $wpr -PathType Leaf)) { throw 'WPR_NOT_AVAILABLE' }
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw 'BOUNDED_WPR_PROFILE_MISSING' }
if (-not $EvidenceDirectory) { $EvidenceDirectory=Join-Path $root ('artifacts/diagnostics/tcp-pull-trace-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)) }
if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'DIAGNOSTIC_REQUIRES_NEW_DIRECTORY' }
$null=New-Item -ItemType Directory -Path $EvidenceDirectory
$EvidenceDirectory=(Resolve-Path -LiteralPath $EvidenceDirectory).Path
$drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($EvidenceDirectory))
if ($drive.AvailableFreeSpace -lt $minimumFreeBytes) { throw ('DIAGNOSTIC_REQUIRES_FREE_GIB_'+($minimumFreeBytes/1GB)) }
function Qpc-Ms { return [Diagnostics.Stopwatch]::GetTimestamp()*1000.0/[Diagnostics.Stopwatch]::Frequency }
function Save-Receipt {
    $target=Join-Path $EvidenceDirectory 'diagnostic-receipt.json'
    $temporary=Join-Path $EvidenceDirectory 'diagnostic-receipt.tmp'
    [IO.File]::WriteAllText($temporary,($receipt | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($true))
    # Windows PowerShell 5.1 converts $null to an empty string for this .NET overload.
    if (Test-Path -LiteralPath $target) { [IO.File]::Replace($temporary,$target,[Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($temporary,$target) }
}
function Invoke-Wpr([string[]]$Arguments,[string]$LogName) {
    $priorPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $output=@(& $wpr @Arguments 2>&1)
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$priorPreference }
    try { $output | Out-String | Set-Content -LiteralPath (Join-Path $EvidenceDirectory $LogName) -Encoding UTF8 }
    catch { $receipt.wpr_log_errors+=($LogName+': '+$_.Exception.Message) }
    return [pscustomobject]@{exit_code=$code;text=($output | Out-String)}
}
$receipt=[ordered]@{schema_version=3;scope='DIAGNOSTIC_ONLY_NOT_BENCHMARK_COMPARISON';status='PREPARING';started_at_utc=[DateTime]::UtcNow.ToString('o');wpr_profiles=@('TestLabTcpPull');raw_trace_limit_mib=2048;packet_payload_provider_enabled=$false;wpr_log_errors=@();wpr_started=$false;wpr_stopped=$false;trace_saved=$false;workload_exit_code=$null;error='';evidence_directory=$EvidenceDirectory;controller_sha256=(Get-FileHash (Join-Path $PSScriptRoot 'Invoke-LocalTcpLoadedRtt.ps1')).Hash;trace_profile_sha256=(Get-FileHash $profilePath).Hash}
$ownsRecording=$false
$receipt.wpr_profiles=@($profileName)
$receipt['tcp_state_trace_enabled']=$stateEnabled
$receipt['tcp_state_trace_limit_mib']=if ($stateEnabled) {512} else {0}
$receipt['tcp_state_keyword_mask']=if ($stateEnabled) {'0x87'} else {$null}
$receipt['tcp_state_nonpaged_memory']=$stateEnabled
$receipt['tcp_state_event_ids']=if ($stateEnabled) {@(1001,1002,1004,1008,1009,1013,1017,1020,1021,1038,1044,1066,1069,1076,1077,1091,1097,1100,1101,1102,1103,1104,1345,1351)} else {@()}
$receipt['tcp_ack_trace_enabled']=[bool]$TcpAckTrace
$receipt['tcp_ack_trace_limit_mib']=if ($TcpAckTrace) {1024} else {0}
$receipt['tcp_ack_keyword_mask']=if ($TcpAckTrace) {'0x300000000'} else {$null}
$receipt['tcp_ack_event_ids']=if ($TcpAckTrace) {@(1159,1160,1330,1331,1429,1587)} else {@()}
$receipt['tcp_ack_capture_scope']=if ($TcpAckTrace) {'WHOLE_PC_ETW_TCP_METADATA_NOT_RAW_PACKET_HEADERS'} else {$null}
$receipt['tcp_ack_file_mode']=if ($TcpAckTrace) {'Circular'} else {$null}
$receipt['tcp_ack_history_completeness']=if ($TcpAckTrace) {'NOT_CERTIFIED_EARLY_EVENTS_MAY_BE_OVERWRITTEN'} else {$null}
$receipt['proxy_accepted_tcp_nodelay']=[bool]$ProxyNoDelay
$receipt['proxy_helper_sha256']=(Get-FileHash (Join-Path $root $(if ($ProxyNoDelay) {'src/pb_tcp_nodelay_diagnostic.py'} else {'src/pb_controlled_tcp_proxy.py'}))).Hash
$receipt['proxy_base_helper_sha256']=(Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash
Save-Receipt
try {
    $idle=Invoke-Wpr @('-status') 'wpr-status-before.txt'
    if ($idle.exit_code -ne 0 -or $idle.text -notmatch '(?im)^\s*WPR (is not recording|recording is not in progress)\s*\.?\s*$') { throw 'WPR_NOT_CONFIRMED_IDLE_OTHER_RECORDING_PRESERVED' }
    $recordingProfile=Join-Path $EvidenceDirectory 'tcp-pull-diagnostic.wprp'
    Copy-Item -LiteralPath $profilePath -Destination $recordingProfile
    $receipt['start_call_qpc_ms']=Qpc-Ms
    $started=Invoke-Wpr @('-start',($recordingProfile+'!'+$profileName),'-filemode','-recordtempto',$EvidenceDirectory) 'wpr-start.txt'
    # Even an error printed with exit 0 can leave this newly accepted WPR configuration owned.
    $ownsRecording=($started.exit_code -eq 0)
    if ($started.exit_code -ne 0 -or $started.text -match '(?i)0x[c8][0-9a-f]{7}') { throw ('WPR_START_FAILED_'+$started.exit_code+': '+$started.text) }
    $ownsRecording=$true;$receipt.wpr_started=$true;$receipt.status='RECORDING'
    $receipt['recording_ready_qpc_ms']=Qpc-Ms
    Save-Receipt
    Write-Host 'Диагностика download / Download diagnostic: one 8 GiB capped transfer plus RTT; approximately 3–5 minutes. Thread scheduling/TCP metadata; raw trace limit 2 GiB (plus merged output). Diagnostic timings only.'
    Write-Host ('Папка / Directory: '+$EvidenceDirectory)
    if ($stateEnabled) { Write-Host 'TCP state trace: filtered endpoint/TCB/diagnosis events, level 5, keywords 0x87, nonpaged buffers; separate 512 MiB limit. Packet payloads excluded.' }
    if ($TcpAckTrace) { Write-Host 'TCP ACK metadata: posted/transmitted bytes, processed ACK/sequence/send window; six event IDs, nonpaged buffers, separate 1 GiB circular tail. Early ACK events may be overwritten even with lost events=0; kernel/state histories have separate limits. Not raw packet headers or wire-delivery proof; no PktMon filters changed.' }
    if ($ProxyNoDelay) { Write-Host 'Диагностический SOCKS helper: accepted TCP_NODELAY=1; каждое соединение проверяется и журналируется / Each accepted socket option is verified and logged. Default benchmark helper unchanged.' }
    $workloadDirectory=Join-Path $EvidenceDirectory 'workload'
    $receipt['workload_start_qpc_ms']=Qpc-Ms
    $workloadArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Invoke-LocalTcpLoadedRtt.ps1'),'-Profile','STANDARD','-DiagnosticPull','-EvidenceDirectory',$workloadDirectory)
    if ($ProxyNoDelay) { $workloadArguments+='-ProxyNoDelay' }
    & (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') @workloadArguments
    $receipt.workload_exit_code=$LASTEXITCODE
    $receipt['workload_end_qpc_ms']=Qpc-Ms
    # A strict progress assertion can still reject this workload; retain its evidence and trace.
    $receipt.status='WORKLOAD_FINISHED'
} catch { $receipt.status='FAILED';$receipt.error=$_.Exception.Message }
finally {
    if ($ownsRecording) {
        try {
            try { $null=Invoke-Wpr @('-status','collectors') 'wpr-status-before-stop.txt' }
            catch { $receipt['trace_status_error']=$_.Exception.Message }
            try {
                $rawFiles=@(Get-ChildItem -LiteralPath $EvidenceDirectory -File -Filter '*.etl')
                $receipt['raw_trace_bytes_before_stop']=($rawFiles | Measure-Object Length -Sum).Sum
                $receipt['raw_trace_limit_reached']=@($rawFiles | Where-Object { $_.Length -ge 2048MB }).Count -gt 0
                if ($stateEnabled -and @($rawFiles | Where-Object { $_.Name -like '*TCP State*' -and $_.Length -ge 512MB }).Count -gt 0) { $receipt.raw_trace_limit_reached=$true }
                if ($TcpAckTrace) { $receipt['tcp_ack_file_limit_observed']=@($rawFiles | Where-Object { $_.Name -like '*TCP ACK*' -and $_.Length -ge 1024MB }).Count -gt 0 }
            } catch { $receipt['raw_trace_inspection_error']=$_.Exception.Message }
            $trace=Join-Path $EvidenceDirectory 'cpu-network.etl'
            $stopped=Invoke-Wpr @('-stop',$trace,'TestLab isolated TCP download zero-rate diagnosis','-skipPdbGen') 'wpr-stop.txt'
            $receipt.wpr_stopped=($stopped.exit_code -eq 0)
            $receipt.trace_saved=($receipt.wpr_stopped -and (Test-Path -LiteralPath $trace -PathType Leaf) -and (Get-Item -LiteralPath $trace).Length -gt 0)
            if ($receipt.trace_saved) {
                $receipt['trace_bytes']=(Get-Item -LiteralPath $trace).Length
                $receipt['trace_sha256']=(Get-FileHash -LiteralPath $trace).Hash
                if (-not $receipt.error) {
                    $receipt.status='TRACE_SAVED'
                    if ($receipt.Contains('raw_trace_limit_reached') -and $receipt.raw_trace_limit_reached) { $receipt.status='TRACE_SAVED_LIMIT_REACHED' }
                }
            } else { $receipt.status='FAILED';$receipt.error+='; WPR_STOP_OR_TRACE_SAVE_FAILED_'+$stopped.exit_code }
        } catch { $receipt.status='FAILED';$receipt.error+='; WPR_SAVE_ERROR_'+$_.Exception.Message }
    }
    $receipt['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
    Save-Receipt
}
if ($receipt.status -eq 'FAILED') { throw $receipt.error }
Write-Host ('Трасса сохранена / Trace saved: '+(Join-Path $EvidenceDirectory 'cpu-network.etl'))
if ($receipt.status -eq 'TRACE_SAVED_LIMIT_REACHED') { Write-Warning 'Достигнут лимит записи: трасса неполная / Recording size limit reached: incomplete trace.' }
Write-Host ('Код завершения нагрузки / Workload exit: '+$receipt.workload_exit_code+'. Результат нагрузки сохранён в workload; трасса не изменяет его статус и не является парным сравнением / Trace does not change the workload verdict and is not a paired comparison.')
Write-Host ('После завершения сообщите папку результатов / Send the result directory: '+$EvidenceDirectory)
