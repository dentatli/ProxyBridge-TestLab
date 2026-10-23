Set-StrictMode -Version Latest

function Test-LocalTcpDirectSocketPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)]$Received,
        [Parameter(Mandatory)][object[]]$Snapshots,
        [Parameter(Mandatory)][int]$ClientPid,
        [Parameter(Mandatory)][int]$CliPid,
        [Parameter(Mandatory)][int]$ReceiverPid,
        [Parameter(Mandatory)][int]$ProxyPort,
        [Parameter(Mandatory)][object[]]$Routes
    )
    # A DIRECT log alone cannot prove a route. Each candidate below must have
    # all owned socket legs in the SAME live observation, plus verified payload
    # and absence of proxy flows at the caller. No historical socket is reused.
    $ownedRoutes = @($Routes | Where-Object { $_.pid -eq $ClientPid -and
        $_.destination_ip -eq $Client.requested_remote_ip -and $_.destination_port -eq $Client.requested_remote_port })
    if (@($ownedRoutes | Where-Object { $_.action -in @('PROXY','BLOCK') }).Count) { return 'UNCONFIRMED' }
    $direct = @($ownedRoutes | Where-Object { $_.action -eq 'DIRECT' })
    if (-not $direct.Count -or $Client.process_id -ne $ClientPid -or
        $Client.actual_remote_ip -ne $Client.requested_remote_ip -or
        $Client.actual_remote_port -ne $Client.requested_remote_port) { return 'UNCONFIRMED' }
    foreach ($snapshot in $Snapshots) {
        $rows = @($snapshot.connections)
        if (@($rows | Where-Object { $_.OwningProcess -eq $CliPid -and $_.RemoteAddress -eq '127.0.0.1' -and $_.RemotePort -eq $ProxyPort }).Count) { continue }
        $clientSockets = @($rows | Where-Object { $_.OwningProcess -eq $ClientPid -and
            $_.LocalAddress -eq $Client.actual_local_ip -and $_.LocalPort -eq $Client.actual_local_port })
        $receiverSockets = @($rows | Where-Object { $_.OwningProcess -eq $ReceiverPid -and
            $_.LocalAddress -eq $Received.local_ip -and $_.LocalPort -eq $Received.local_port -and
            $_.RemoteAddress -eq $Received.remote_ip -and $_.RemotePort -eq $Received.remote_port })
        if ($clientSockets.Count -ne 1 -or $receiverSockets.Count -ne 1) { continue }
        if ($Received.remote_ip -eq $Client.actual_local_ip -and $Received.remote_port -eq $Client.actual_local_port -and
            $clientSockets[0].RemoteAddress -eq $Received.local_ip -and $clientSockets[0].RemotePort -eq $Received.local_port -and
            -not @($direct | Where-Object event -eq 'RELAY_ACCEPTED_REDIRECT').Count) { return 'CLIENT_SOCKET' }
        $outgoing = @($rows | Where-Object { $_.OwningProcess -eq $CliPid -and
            $_.LocalAddress -eq $Received.remote_ip -and $_.LocalPort -eq $Received.remote_port -and
            $_.RemoteAddress -eq $Received.local_ip -and $_.RemotePort -eq $Received.local_port })
        $incoming = @($rows | Where-Object { $_.OwningProcess -eq $CliPid -and
            $_.RemoteAddress -eq $Client.actual_local_ip -and $_.RemotePort -eq $Client.actual_local_port })
        if ($outgoing.Count -ne 1 -or $incoming.Count -ne 1 -or
            -not @($direct | Where-Object event -eq 'RELAY_ACCEPTED_REDIRECT').Count) { continue }
        # WFP may expose the original destination on the client-side socket.
        $peer = $clientSockets[0]
        if (($peer.RemoteAddress -eq $incoming[0].LocalAddress -and $peer.RemotePort -eq $incoming[0].LocalPort) -or
            ($peer.RemoteAddress -eq $Client.requested_remote_ip -and $peer.RemotePort -eq $Client.requested_remote_port)) { return 'CORE_RELAY' }
    }
    return 'UNCONFIRMED'
}

Export-ModuleMember -Function Test-LocalTcpDirectSocketPath
