Set-StrictMode -Version Latest

function Get-BenchmarkWorkload([string]$Duration,[string]$Load) {
    if ($Duration -notin @('SHORT','NORMAL','LONG') -or $Load -notin @('LOW','HIGH')) { throw 'LAB_WORKLOAD_INVALID' }
    $Duration=$Duration.ToUpperInvariant();$Load=$Load.ToUpperInvariant()
    $catalogPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'config/benchmark-workloads.json'
    $catalog=Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    if ($catalog.schema_version -ne 1 -or $catalog.method -ne 'controlled-workload-v1') { throw 'LAB_WORKLOAD_CATALOG_INVALID' }
    $durationRow=$catalog.durations.$Duration
    $loadRow=$catalog.loads.$Load
    $expectedSeconds=@{SHORT=8;NORMAL=32;LONG=120}[$Duration]
    $expectedEchoes=@{SHORT=128;NORMAL=1500;LONG=6000}[$Duration]
    if ($durationRow.transfer_seconds -ne $expectedSeconds -or $durationRow.rtt_low_echoes -ne $expectedEchoes -or $durationRow.rtt_high_echoes -ne 2*$expectedEchoes -or
        $loadRow.rate_limit_bytes_per_s -ne $(if ($Load -eq 'LOW') {8388608} else {67108864}) -or $loadRow.pause_ms -ne $(if ($Load -eq 'LOW') {20} else {10}) -or
        $catalog.rtt_warmup_count -ne 1000 -or $catalog.rtt_message_bytes -ne 512 -or $catalog.connections -ne 1 -or $catalog.native_timeout_ms -ne 600000) { throw 'LAB_WORKLOAD_CATALOG_INVALID' }
    return [ordered]@{
        method=$catalog.method;duration=$Duration;load=$Load;
        transfer_bytes=[long]$durationRow.transfer_seconds*[long]$loadRow.rate_limit_bytes_per_s;
        rate_limit_bytes_per_s=[long]$loadRow.rate_limit_bytes_per_s;
        nominal_transfer_seconds=[int]$durationRow.transfer_seconds;
        echo_count=[int]$(if ($Load -eq 'LOW') {$durationRow.rtt_low_echoes} else {$durationRow.rtt_high_echoes});
        warmup_count=[int]$catalog.rtt_warmup_count;message_bytes=[int]$catalog.rtt_message_bytes;
        pause_ms=[int]$loadRow.pause_ms;connections=[int]$catalog.connections;
        native_timeout_ms=[int]$catalog.native_timeout_ms
    }
}
Export-ModuleMember -Function Get-BenchmarkWorkload
