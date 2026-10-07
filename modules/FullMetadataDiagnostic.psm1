Set-StrictMode -Version Latest

function Assert-FullMetadataPolicy($Policy) {
    if ($Policy.method -cne 'full-wfp-afd-capture-v1' -or -not $Policy.diagnostic_only -or $Policy.performance_comparable -or
        (@($Policy.cases) -join ',') -cne 'original' -or $Policy.baseline_connections -ne 4 -or
        $Policy.raw_trace_limit_mib -ne 64 -or -not $Policy.baseline_coverage_before_load -or
        -not $Policy.recording_gap_declared -or -not $Policy.read_only_wfp_snapshot -or $Policy.private_record_observed -or $Policy.root_cause_proven) {
        throw 'FULL_METADATA_POLICY_INVALID'
    }
}
function Save-FullMetadataReceipt($State) {
    $State.receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $State.directory 'full-metadata-receipt.json') -Encoding UTF8
}
function Invoke-FullMetadataTool($State,[string]$Executable,[string[]]$Arguments,[string]$Label,[int]$TimeoutMs=60000) {
    if ($State.Contains('tool_adapter')) {return & $State.tool_adapter $Executable $Arguments $Label $TimeoutMs}
    Import-Module (Join-Path $PSScriptRoot 'ProcessAdapter.psm1')
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Executable;$info.Arguments=Join-ProcessArguments $Arguments
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($info)
    try {
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMs)) { $process.Kill();$process.WaitForExit();throw ('FULL_METADATA_TOOL_TIMEOUT: '+$Label) }
        $text=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult()
        if ($text.Length+$errorText.Length -gt 8MB) {throw ('FULL_METADATA_TOOL_OUTPUT_BOUND: '+$Label)}
        [IO.File]::WriteAllText((Join-Path $State.directory ($Label+'.out.txt')),$text,[Text.UTF8Encoding]::new($true))
        [IO.File]::WriteAllText((Join-Path $State.directory ($Label+'.err.txt')),$errorText,[Text.UTF8Encoding]::new($true))
        return [pscustomobject]@{exit_code=$process.ExitCode;text=($text+$errorText);stdout=$text}
    } finally {$process.Dispose()}
}
function Start-FullMetadataSegment($State,[string]$Name) {
    if ($State.owns_recording) {throw 'FULL_METADATA_RECORDING_ALREADY_OWNED'}
    $idle=Invoke-FullMetadataTool $State $State.wpr @('-status') ($Name+'-status')
    if ($idle.exit_code -ne 0 -or $idle.text -notmatch '(?im)^\s*WPR (is not recording|recording is not in progress)\s*\.?\s*$') {throw 'FULL_METADATA_OTHER_RECORDING_PRESERVED'}
    $State.segment=$Name
    $segmentDirectory=Join-Path $State.directory $Name
    $null=New-Item -ItemType Directory -Path $segmentDirectory
    $started=Invoke-FullMetadataTool $State $State.wpr @('-start',($State.profile+'!TestLabTcpWfpFullMetadata'),'-filemode','-recordtempto',$segmentDirectory) ($Name+'-start')
    $State.owns_recording=($started.exit_code -eq 0)
    if ($started.exit_code -ne 0 -or $started.text -match '(?i)0x[c8][0-9a-f]{7}') {throw 'FULL_METADATA_WPR_START_FAILED'}
    $State.receipt.segments+=@([ordered]@{name=$Name;start_qpc=[Diagnostics.Stopwatch]::GetTimestamp();frequency=[Diagnostics.Stopwatch]::Frequency;stop_qpc=$null;saved=$false;sha256='';bytes=0;raw_limit_observed=$false})
    Save-FullMetadataReceipt $State
}
function Stop-FullMetadataSegment($State) {
    if (-not $State.owns_recording) {return}
    $entry=@($State.receipt.segments | Where-Object {$_.name -ceq $State.segment})
    $etl=Join-Path $State.directory ($State.segment+'/metadata.etl')
    $raw=@(Get-ChildItem -LiteralPath (Join-Path $State.directory $State.segment) -File -Filter '*.etl')
    $atLimit=@($raw | Where-Object {$_.Length -ge 64MB}).Count -gt 0
    $stop=Invoke-FullMetadataTool $State $State.wpr @('-stop',$etl,'TestLab owned WFP AFD metadata','-skipPdbGen') ($State.segment+'-stop')
    if ($stop.exit_code -ne 0) {throw 'FULL_METADATA_TRACE_STOP_UNCONFIRMED'}
    $State.owns_recording=$false
    if (-not (Test-Path -LiteralPath $etl -PathType Leaf) -or (Get-Item -LiteralPath $etl).Length -le 0) {throw 'FULL_METADATA_TRACE_SAVE_UNCONFIRMED'}
    if ($entry.Count -ne 1) {throw 'FULL_METADATA_SEGMENT_BINDING_INVALID'}
    $entry[0].stop_qpc=[Diagnostics.Stopwatch]::GetTimestamp();$entry[0].saved=$true
    $entry[0].bytes=(Get-Item -LiteralPath $etl).Length;$entry[0].sha256=(Get-FileHash -LiteralPath $etl).Hash.ToLowerInvariant()
    $entry[0].raw_limit_observed=$atLimit -or $entry[0].bytes -gt 192MB
    Save-FullMetadataReceipt $State
    if ($entry[0].raw_limit_observed) {throw 'FULL_METADATA_RAW_TRACE_BOUND'}
}
function Save-FullWfpSnapshot($State,[string]$Name) {
    $path=Join-Path $State.directory ($Name+'-wfp-state.xml')
    $result=Invoke-FullMetadataTool $State (Join-Path $env:SystemRoot 'System32/netsh.exe') @('wfp','show','state',('file='+$path)) ($Name+'-wfp-state')
    if ($result.exit_code -ne 0 -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -gt 32MB) {throw 'FULL_METADATA_WFP_SNAPSHOT_UNCONFIRMED'}
    $State.receipt.snapshots+=@([ordered]@{name=$Name;path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();qpc=[Diagnostics.Stopwatch]::GetTimestamp();read_only=$true})
    Save-FullMetadataReceipt $State
}
function Export-FullMetadataSegment($State,[string]$Name) {
    $dir=Join-Path $State.directory $Name
    $decoded=Invoke-FullMetadataTool $State $State.decoder @((Join-Path $dir 'metadata.etl'),(Join-Path $dir 'events.jsonl')) ($Name+'-decode')
    if ($decoded.exit_code -ne 0) {throw 'FULL_METADATA_ETL_DECODE_FAILED'}
    $summary=$decoded.stdout | ConvertFrom-Json
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dir 'decode-summary.json') -Encoding UTF8
    if ($summary.method -cne 'saved-wfp-afd-etl-v1' -or $summary.events_lost -ne 0 -or $summary.buffers_lost -ne 0 -or
        $summary.bound_exceeded -or $summary.clock_type -ne 1 -or $summary.qpc_frequency -ne [Diagnostics.Stopwatch]::Frequency) {throw 'FULL_METADATA_TRACE_CLOCK_LOSS_OR_BOUND'}
}
function New-FullMetadataPhaseObserver($State) {
    $callback={
        param($Context,$Cli,$Cohort,$Record)
        if (-not $Cli -or $Context.mode -cne 'PROXY') {throw 'FULL_METADATA_REQUIRES_OWN_CLI'}
        if ($Cohort.id -ceq 'baseline') {
            if ($State.receipt.baseline_coverage_confirmed) {throw 'FULL_METADATA_BASELINE_GATE_REPEATED'}
            $State.receipt.owned_cli_pid=$Cli.pid;$State.receipt.owned_baseline_directory=Join-Path $Context.directory 'baseline'
            Save-FullWfpSnapshot $State 'baseline-active'
            $State.receipt.gap_start_qpc=[Diagnostics.Stopwatch]::GetTimestamp()
            Stop-FullMetadataSegment $State
            Export-FullMetadataSegment $State 'baseline'
            $args=@($State.coverage,'--events',(Join-Path $State.directory 'baseline/events.jsonl'),'--summary',(Join-Path $State.directory 'baseline/decode-summary.json'),
                '--baseline',$State.receipt.owned_baseline_directory,'--cli-pid',[string]$Cli.pid,'--state',(Join-Path $State.directory 'baseline-active-wfp-state.xml'),'--output',(Join-Path $State.directory 'baseline-coverage.json'))
            $coverage=Invoke-FullMetadataTool $State $State.python $args 'baseline-coverage'
            if ($coverage.exit_code -ne 0) {throw 'FULL_METADATA_BASELINE_COVERAGE_INCOMPLETE: see baseline-coverage.json'}
            $report=Get-Content -LiteralPath (Join-Path $State.directory 'baseline-coverage.json') -Raw | ConvertFrom-Json
            if ($report.status -cne 'COVERAGE_CONFIRMED' -or @($report.errors).Count -ne 0 -or @($report.matched).Count -ne 4) {throw 'FULL_METADATA_BASELINE_COVERAGE_INVALID'}
            $State.receipt.baseline_coverage_confirmed=$true
            Start-FullMetadataSegment $State 'load'
            $State.receipt.gap_end_qpc=[Diagnostics.Stopwatch]::GetTimestamp()
            Save-FullMetadataReceipt $State
            Write-Host 'Baseline WFP/AFD coverage confirmed; continuing load on the same CLI / Журналы начальных соединений подтверждены; нагрузка продолжается на том же CLI.'
        } elseif ($Cohort.id -ceq 'recovery') {
            if (-not $State.receipt.baseline_coverage_confirmed -or $State.receipt.owned_cli_pid -ne $Cli.pid) {throw 'FULL_METADATA_SAME_CLI_NOT_CONFIRMED'}
            Save-FullWfpSnapshot $State 'recovery-active'
            $State.receipt.recovery_observed=$true;Save-FullMetadataReceipt $State
        }
    }.GetNewClosure()
    return $callback
}
Export-ModuleMember -Function Assert-FullMetadataPolicy,Save-FullMetadataReceipt,Invoke-FullMetadataTool,Start-FullMetadataSegment,Stop-FullMetadataSegment,Save-FullWfpSnapshot,Export-FullMetadataSegment,New-FullMetadataPhaseObserver
