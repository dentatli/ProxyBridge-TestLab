Set-StrictMode -Version Latest
function Assert-ExternalReceiverPolicy($Policy) {
    $address=$null
    if ($Policy.method -cne 'local-linux-receiver-pair-v1' -or -not $Policy.diagnostic_only -or $Policy.performance_comparable -or
        (@($Policy.cases) -join ',') -cne 'local,linux' -or $Policy.route_case -cne 'original' -or
        $Policy.port -ne 54122 -or $Policy.transfer_bytes -ne 524288 -or $Policy.receiver_sha256 -cne '9df9708a718ab91b08d54d28676b2e96c1201e2f0bd5c81a9e40712801841011' -or
        -not [Net.IPAddress]::TryParse([string]$Policy.host,[ref]$address) -or $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
        [Net.IPAddress]::IsLoopback($address) -or $address.Equals([Net.IPAddress]::Any) -or $address.GetAddressBytes()[0] -ge 224 -or
        [string]$Policy.connection_file -cnotmatch '^[A-Za-z]:[\\/]' -or $Policy.connection_sha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'EXTERNAL_RECEIVER_POLICY_INVALID'
    }
    $connection=Get-Content -LiteralPath $Policy.connection_file -Raw | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath $Policy.connection_file).Hash -ine $Policy.connection_sha256 -or
        $connection.host -cne $Policy.host -or $connection.allowed_source -cne $Policy.allowed_source -or
        $connection.username -cne 'root' -or $connection.host_key_fingerprint -cne $Policy.host_key_fingerprint) {throw 'EXTERNAL_RECEIVER_CONNECTION_BINDING_DIFFERS'}
}
function Invoke-ExternalReceiverCase([ValidateSet('local','linux')][string]$Case,[scriptblock]$Workload) {
    $previous=[Environment]::GetEnvironmentVariable('PB_TESTLAB_RECEIVER_CASE','Process')
    try {
        [Environment]::SetEnvironmentVariable('PB_TESTLAB_RECEIVER_CASE',$Case,'Process')
        Invoke-RouteMatrixCase -Case original -Workload $Workload
    } finally {[Environment]::SetEnvironmentVariable('PB_TESTLAB_RECEIVER_CASE',$previous,'Process')}
}
Export-ModuleMember -Function Assert-ExternalReceiverPolicy,Invoke-ExternalReceiverCase
