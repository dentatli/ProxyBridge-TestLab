#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvPath,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [Parameter(Mandatory)][string]$UdpProxyPythonPath,
    [ValidateSet('UNRULED','ROUTED','LOGGING')][string]$ComparisonMode = 'UNRULED',
    [ValidateSet('FLUSH_EACH','BUFFERED')][string]$EvidenceLogMode = 'FLUSH_EACH',
    [ValidateRange(1,8)][int]$PairCount = 3,
    [ValidateRange(16,40000)][int]$PacketCount = 64,
    [ValidateRange(0,200)][int]$IntervalMs = 100,
    [ValidateRange(0,1200)][int]$MessageSize = 0,
    [ValidateRange(8,1000)][int]$WarmupPackets = 8,
    [ValidateRange(1,4)][int]$Streams = 1,
    [ValidateSet('SHARED','DISTINCT')][string]$DestinationMode = 'SHARED',
    [switch]$AllowProductRuntime,
    [switch]$Resume
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $AllowProductRuntime) { throw 'PRODUCT_RUNTIME_NOT_ALLOWED' }
if ($ComparisonMode -eq 'LOGGING' -and ($Resume -or $Streams -ne 2 -or $DestinationMode -ne 'DISTINCT')) { throw 'LOGGING_REQUIRES_NEW_TWO_DESTINATION_SERIES' }
if ($ComparisonMode -eq 'LOGGING' -and $EvidenceLogMode -ne 'FLUSH_EACH') { throw 'LOGGING_SELECTS_POLICY_PER_VARIANT' }
if ($DestinationMode -eq 'DISTINCT' -and $Streams -ne 2) { throw 'DISTINCT_DESTINATIONS_REQUIRE_TWO_STREAMS' }
if ($PacketCount % $Streams -ne 0 -or $PacketCount/$Streams -le $WarmupPackets) { throw 'COMPARISON_REQUIRES_PACKETS_AFTER_WARMUP_PER_STREAM' }
if ($PacketCount/$Streams -gt 20000) { throw 'COMPARISON_MAXIMUM_20000_PACKETS_PER_STREAM' }
if ($MessageSize -gt 0 -and $MessageSize -lt 256) { throw 'IDENTIFIED_MESSAGE_SIZE_REQUIRES_256_TO_1200_BYTES' }
if ($Resume) {
    if (-not (Test-Path -LiteralPath (Join-Path $EvidenceDirectory 'comparison-manifest.json') -PathType Leaf)) { throw 'RESUME_MANIFEST_MISSING' }
} else {
    if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'COMPARISON_REQUIRES_NEW_DIRECTORY' }
    $null = New-Item -ItemType Directory -Path $EvidenceDirectory
}
$EvidenceDirectory = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
$manifest = [ordered]@{schema_version=1;status='RUNNING';started_at_utc=[DateTime]::UtcNow.ToString('o');comparison_mode=$ComparisonMode;pair_count=$PairCount;packet_count=$PacketCount;interval_ms=$IntervalMs;message_size_bytes=$MessageSize;warmup_packets=$WarmupPackets;runs=@();error='';version_switch_ready=$false}
$resumeSuffix = ''
$manifest['stream_count'] = $Streams
$manifest['destination_mode'] = $DestinationMode
$manifest['helper_log_flush_mode'] = $(if ($ComparisonMode -eq 'LOGGING') { 'PER_VARIANT' } else { $EvidenceLogMode })
if ($Resume) {
    $saved = Get-Content -LiteralPath (Join-Path $EvidenceDirectory 'comparison-manifest.json') -Raw | ConvertFrom-Json
    if (-not $saved.PSObject.Properties['stream_count']) { $saved | Add-Member -NotePropertyName stream_count -NotePropertyValue 1 }
    if (-not $saved.PSObject.Properties['destination_mode']) { $saved | Add-Member -NotePropertyName destination_mode -NotePropertyValue 'SHARED' }
    if (-not $saved.PSObject.Properties['helper_log_flush_mode']) { $saved | Add-Member -NotePropertyName helper_log_flush_mode -NotePropertyValue 'FLUSH_EACH' }
    if ($saved.status -ne 'FAILED' -or $saved.schema_version -ne 1 -or $saved.runs.Count -ne $PairCount*2) { throw 'RESUME_REQUIRES_ONLY_FINAL_RUN_PENDING' }
    foreach ($key in @('comparison_mode','pair_count','packet_count','interval_ms','message_size_bytes','warmup_packets','stream_count','destination_mode','helper_log_flush_mode')) {
        if ($saved.$key -ne $manifest[$key]) { throw "RESUME_PARAMETER_MISMATCH_$key" }
    }
    $expected = @()
    $onMode = $(if ($ComparisonMode -eq 'ROUTED') { 'PROXY' } else { 'UNRULED' })
    for ($pair=1; $pair -le $PairCount; $pair++) {
        $order = $(if ($pair % 2 -eq 1) { @('OFF',$onMode) } else { @($onMode,'OFF') })
        foreach ($mode in $order) { $expected += [pscustomobject]@{pair=$pair;mode=$mode;name=('pair-{0:d2}-{1}' -f $pair,$mode.ToLowerInvariant())} }
    }
    for ($index=0; $index -lt $saved.runs.Count-1; $index++) {
        $run = $saved.runs[$index]
        if ($run.status -ne 'COMPLETED' -or $run.directory -ne $expected[$index].name -or $run.pair -ne $expected[$index].pair -or $run.mode -ne $expected[$index].mode) { throw 'RESUME_COMPLETED_PREFIX_INVALID' }
        $report = Get-Content -LiteralPath (Join-Path $EvidenceDirectory ($run.directory+'/udp-benchmark-report.json')) -Raw | ConvertFrom-Json
        $config = Get-Content -LiteralPath (Join-Path $EvidenceDirectory ($run.directory+'/benchmark-config.json')) -Raw | ConvertFrom-Json
        if ($config.parallelism -ne $Streams -or $config.packet_count -ne $PacketCount -or $config.warmup_packets -ne $WarmupPackets*$Streams -or $config.interval_ms -ne $IntervalMs -or $config.message_size_bytes -ne $MessageSize) { throw 'RESUME_COMPLETED_CONFIGURATION_MISMATCH' }
        $savedDestinationMode = $(if ($config.PSObject.Properties['destination_mode']) { $config.destination_mode } else { 'SHARED' })
        if ($savedDestinationMode -ne $DestinationMode) { throw 'RESUME_COMPLETED_DESTINATION_MISMATCH' }
        $savedLogMode = $(if ($config.PSObject.Properties['helper_log_flush_mode']) { $config.helper_log_flush_mode } else { 'FLUSH_EACH' })
        if ($savedLogMode -ne $EvidenceLogMode) { throw 'RESUME_COMPLETED_LOG_POLICY_MISMATCH' }
        if ($EvidenceLogMode -eq 'BUFFERED' -and (-not $report.PSObject.Properties['logging_policy_verified'] -or $report.logging_policy_verified -ne $true -or $report.helper_log_flush_mode -ne $EvidenceLogMode)) { throw 'RESUME_BUFFERED_LOG_POLICY_NOT_CONFIRMED' }
        $confirmed = $report.correctness_status -eq 'PASS' -and $report.performance_status -eq 'MEASURED'
        if ($run.mode -eq 'PROXY') { $confirmed = $confirmed -or ($report.correctness_status -eq 'SOURCE_ENDPOINT_MISMATCH' -and $report.performance_status -eq 'MEASURED_WITH_SOURCE_DEFECT' -and $report.response_sources.OWNED_RELAY -gt 0 -and $report.response_sources.UNEXPECTED -eq 0) }
        if (-not $confirmed -or $report.pc_metrics.status -ne 'OBSERVED' -or -not $report.pc_metrics.PSObject.Properties['receiver_identity_verified'] -or $report.pc_metrics.receiver_identity_verified -ne $true -or $report.planned_packets -ne $PacketCount -or [bool]$report.routed_udp_source_regression_covered -ne ($run.mode -eq 'PROXY')) { throw 'RESUME_COMPLETED_RUN_NOT_CONFIRMED' }
    }
    $last = $saved.runs[-1]
    $pending = $expected[-1]
    $safeName = '^'+[regex]::Escape($pending.name)+'(?:-retry-[0-9]{8}-[0-9]{6}-[0-9a-f]{6})?$'
    if ($last.status -eq 'COMPLETED' -or $last.pair -ne $pending.pair -or $last.mode -ne $pending.mode -or $last.directory -notmatch $safeName) { throw 'RESUME_FINAL_RUN_INVALID' }
    $failedPath = Join-Path $EvidenceDirectory $last.directory
    $receipt = Get-Content -LiteralPath (Join-Path $failedPath 'route-probe-receipt.json') -Raw | ConvertFrom-Json
    $after = Get-Content -LiteralPath (Join-Path $failedPath 'loaded-drivers-after.json') -Raw | ConvertFrom-Json
    if ($receipt.traffic_generated -ne $false -or $receipt.cases.Count -ne 0 -or $receipt.workers_stopped -ne $true -or $receipt.driver_stop_observed -ne $true -or $after.query_complete -ne $true -or $after.known_interception_driver_names_absent -ne $true) { throw 'RESUME_REQUIRES_NO_WORKLOAD_AND_OBSERVED_CLEANUP' }
    $resumeSuffix = '-retry-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)
    Copy-Item -LiteralPath (Join-Path $EvidenceDirectory 'comparison-manifest.json') -Destination (Join-Path $EvidenceDirectory ('comparison-manifest-before'+$resumeSuffix+'.json'))
    $manifest = [ordered]@{}
    foreach ($property in $saved.PSObject.Properties) { $manifest[$property.Name] = $property.Value }
    if (-not $manifest.Contains('failed_attempts')) { $manifest['failed_attempts'] = @() }
    $manifest.failed_attempts = @($manifest.failed_attempts) + [ordered]@{pair=$last.pair;mode=$last.mode;directory=$last.directory;error=$saved.error;traffic_generated=$false}
    $manifest.runs = @($saved.runs[0..($saved.runs.Count-2)])
    $manifest['resumed_from_error'] = $saved.error
    $manifest['resumed_at_utc'] = [DateTime]::UtcNow.ToString('o')
    $manifest.status = 'RUNNING'
    $manifest.error = ''
    $manifest.Remove('completed_at_utc')
    Write-Host ('Возобновление / Resume: {0} completed runs retained; only {1} will run.' -f $manifest.runs.Count,$pending.name)
}
function Save-Manifest {
    $manifest | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $EvidenceDirectory 'comparison-manifest.json') -Encoding UTF8
}
Save-Manifest
try {
    for ($pair=1; $pair -le $PairCount; $pair++) {
        $baseMode = $(if ($ComparisonMode -eq 'LOGGING') { 'FLUSH_EACH' } else { 'OFF' })
        $onMode = $(if ($ComparisonMode -eq 'LOGGING') { 'BUFFERED' } elseif ($ComparisonMode -eq 'ROUTED') { 'PROXY' } else { 'UNRULED' })
        $order = $(if ($pair % 2 -eq 1) { @($baseMode,$onMode) } else { @($onMode,$baseMode) })
        foreach ($mode in $order) {
            $name = 'pair-{0:d2}-{1}' -f $pair,$mode.ToLowerInvariant()
            if ($Resume -and @($manifest.runs | Where-Object { $_.pair -eq $pair -and $_.mode -eq $mode -and $_.status -eq 'COMPLETED' }).Count) { continue }
            if ($Resume) { $name += $resumeSuffix }
            $entry = [ordered]@{pair=$pair;mode=$mode;directory=$name;status='RUNNING'}
            $manifest.runs += $entry
            Save-Manifest
            $routedMode = $mode -in @('PROXY','FLUSH_EACH','BUFFERED')
            $probeMode = $(if ($routedMode) { 'RULES' } else { $mode })
            $logMode = $(if ($ComparisonMode -eq 'LOGGING') { $mode } else { $EvidenceLogMode })
            Write-Host ('[{0}/{1}] {2}: {3} UDP echo, {4} bytes, pause {5} ms / UDP-обмены, байты, пауза' -f $manifest.runs.Count,($PairCount*2),$name,$PacketCount,$(if ($MessageSize) { $MessageSize } else { 'auto' }),$IntervalMs)
            & (Join-Path $PSScriptRoot 'Invoke-WfpLocalRouteProbe.ps1') -EnvPath $EnvPath -EvidenceDirectory (Join-Path $EvidenceDirectory $name) -TrafficMode $probeMode -Actions PROXY -Protocol UDP -UdpBenchmark -MatchedComparisonWorkload:($ComparisonMode -in @('ROUTED','LOGGING')) -BenchmarkPacketCount $PacketCount -BenchmarkIntervalMs $IntervalMs -BenchmarkMessageSize $MessageSize -BenchmarkWarmupPackets $WarmupPackets -BenchmarkStreams $Streams -BenchmarkDestinationMode $DestinationMode -EvidenceLogMode $logMode -UdpProxyPythonPath $UdpProxyPythonPath -AllowProductRuntime
            $report = Get-Content (Join-Path $EvidenceDirectory ($name + '/udp-benchmark-report.json')) -Raw | ConvertFrom-Json
            if ($report.logging_policy_verified -ne $true -or $report.helper_log_flush_mode -ne $logMode) { throw "COMPARISON_LOG_POLICY_NOT_CONFIRMED_$name" }
            $confirmed = $report.correctness_status -eq 'PASS' -and $report.performance_status -eq 'MEASURED'
            if ($routedMode) {
                $confirmed = $confirmed -or ($report.correctness_status -eq 'SOURCE_ENDPOINT_MISMATCH' -and $report.performance_status -eq 'MEASURED_WITH_SOURCE_DEFECT' -and $report.response_sources.OWNED_RELAY -gt 0 -and $report.response_sources.UNEXPECTED -eq 0)
            }
            $pcStatus = 'MISSING'
            $incompleteRoles = ''
            $systemIncomplete = 'unknown'
            if ($null -ne $report.pc_metrics) {
                $pcStatus = $report.pc_metrics.status
                if ($report.pc_metrics.PSObject.Properties['incomplete_roles']) { $incompleteRoles = $report.pc_metrics.incomplete_roles -join ',' }
                if ($report.pc_metrics.PSObject.Properties['system_coverage_incomplete']) { $systemIncomplete = $report.pc_metrics.system_coverage_incomplete }
            }
            if (-not $confirmed -or $pcStatus -ne 'OBSERVED' -or [bool]$report.routed_udp_source_regression_covered -ne $routedMode) {
                throw ("COMPARISON_RUN_NOT_CONFIRMED_{0}: correctness={1}; performance={2}; pc_metrics={3}; incomplete_roles={4}; system_coverage_incomplete={5}" -f $name,$report.correctness_status,$report.performance_status,$pcStatus,$incompleteRoles,$systemIncomplete)
            }
            $entry.status='COMPLETED'
            Save-Manifest
        }
    }
    $manifest.status='COMPLETED'
} catch {
    $manifest.status='FAILED'
    $manifest.error=$_.Exception.Message
} finally {
    $manifest['completed_at_utc']=[DateTime]::UtcNow.ToString('o')
    Save-Manifest
}
if ($manifest.status -ne 'COMPLETED') { throw $manifest.error }
$reportScript = $(if ($ComparisonMode -eq 'LOGGING') { 'src/pb_udp_logging_report.py' } else { 'src/pb_unruled_comparison_report.py' })
& $UdpProxyPythonPath (Join-Path (Split-Path -Parent $PSScriptRoot) $reportScript) --evidence-directory $EvidenceDirectory
if ($LASTEXITCODE -ne 0) { throw 'COMPARISON_REPORT_FAILED' }
