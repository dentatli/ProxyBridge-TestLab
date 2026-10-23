Set-StrictMode -Version Latest
function Get-LocalUdpWorkload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('SHORT','NORMAL','LONG')][string]$Duration,
        [Parameter(Mandatory)][ValidateSet('LOW','HIGH')][string]$Load)
    $echoes = switch ($Duration) { SHORT {128} NORMAL {1500} LONG {6000} }
    $streams = if ($Load -eq 'HIGH') {2} else {1}
    [ordered]@{method='controlled-udp-workload-v1';duration=$Duration;load=$Load;echo_count_per_stream=$echoes;
        packet_count=($echoes+100)*$streams;warmup_per_stream=100;streams=$streams;interval_ms=$(if($Load -eq 'HIGH'){10}else{20});
        message_bytes=512;destination_mode='SHARED';pair_count=1;helper_log_flush_mode='BUFFERED'}
}
Export-ModuleMember -Function Get-LocalUdpWorkload
