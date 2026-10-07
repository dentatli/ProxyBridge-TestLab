Set-StrictMode -Version Latest
function Assert-RouteMatrixPolicy($Policy) {
    if ($Policy.method -cne 'listener-route-matrix-v1' -or -not $Policy.diagnostic_only -or $Policy.performance_comparable -or
        (@($Policy.cases) -join ',') -cne 'original,backlog1024,backlog1024-delay650' -or
        $Policy.selector -cne 'PB_TESTLAB_ROUTE_CASE' -or $Policy.delay_ms -ne 650 -or
        $Policy.only_changed_source -cne 'Windows/src/relay/pb_relay_tcp.c' -or
        -not $Policy.original_single_query_preserved -or -not $Policy.payload_pump_unchanged -or
        -not $Policy.wsa_state_preserved -or $Policy.payload_recorded -or $Policy.raw_kernel_pointers_recorded -or
        $Policy.route_leg_metadata -cne 'incoming-to-upstream-ipv4-status-qpc-v1') {
        throw 'ROUTE_MATRIX_POLICY_INVALID'
    }
}
function Invoke-RouteMatrixCase([Alias('Case')][string]$RouteSelection, [scriptblock]$Workload) {
    if ($RouteSelection -cnotin @('original','backlog1024','backlog1024-delay650')) {throw 'ROUTE_MATRIX_CASE_INVALID'}
    $previous=[Environment]::GetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE','Process')
    try {
        [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE',$RouteSelection,'Process')
        & $Workload
    } finally {
        [Environment]::SetEnvironmentVariable('PB_TESTLAB_ROUTE_CASE',$previous,'Process')
    }
}
Export-ModuleMember -Function Assert-RouteMatrixPolicy,Invoke-RouteMatrixCase
