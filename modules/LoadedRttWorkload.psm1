Set-StrictMode -Version Latest
function Get-LoadedRttWorkload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('SHORT','NORMAL','LONG')][string]$Duration,
        [Parameter(Mandatory)][ValidateSet('LOW','HIGH')][string]$Load)
    $echoes = switch ($Duration) { SHORT {128} NORMAL {1500} LONG {6000} }
    $rate = if ($Load -eq 'HIGH') {67108864L} else {8388608L}
    $seconds = [int][Math]::Ceiling(($echoes+100)*0.02)+20
    [ordered]@{method='controlled-loaded-rtt-v1';duration=$Duration;load=$Load;echo_count=$echoes;warmup_count=100;
        message_bytes=512;pause_ms=20;rate_limit_bytes_per_s=$rate;transfer_bytes=$seconds*$rate;nominal_transfer_seconds=$seconds;pair_count=1}
}
Export-ModuleMember -Function Get-LoadedRttWorkload
