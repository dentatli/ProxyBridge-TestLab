[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/LocalTcpDirectEvidence.psm1') -Force

function New-Socket($Owner,$LocalPort,$RemotePort) {
    [pscustomobject]@{OwningProcess=$Owner;LocalAddress='127.0.0.1';LocalPort=$LocalPort;RemoteAddress='127.0.0.1';RemotePort=$RemotePort}
}
$client = [pscustomobject]@{process_id=101;actual_local_ip='127.0.0.1';actual_local_port=50001;requested_remote_ip='127.0.0.1';requested_remote_port=53121;actual_remote_ip='127.0.0.1';actual_remote_port=53121}
$receiver = [pscustomobject]@{local_ip='127.0.0.1';local_port=53121;remote_ip='127.0.0.1';remote_port=50002}
$route = [pscustomobject]@{event='RELAY_ACCEPTED_REDIRECT';pid=101;destination_ip='127.0.0.1';destination_port=53121;action='DIRECT'}
$rows = @((New-Socket 101 50001 53121),(New-Socket 102 40001 50001),(New-Socket 102 50002 53121),(New-Socket 103 53121 50002))
$parameters = @{Client=$client;Received=$receiver;ClientPid=101;CliPid=102;ReceiverPid=103;ProxyPort=53123;Routes=@($route)}
$snapshot = [pscustomobject]@{connections=$rows}
Assert-Equal 'CORE_RELAY' (Test-LocalTcpDirectSocketPath @parameters -Snapshots @($snapshot)) 'relay DIRECT requires the full owned path'
foreach ($index in 0..3) {
    $remaining = @($rows | Where-Object { $_ -ne $rows[$index] })
    Assert-Equal 'UNCONFIRMED' (Test-LocalTcpDirectSocketPath @parameters -Snapshots @([pscustomobject]@{connections=$remaining})) "missing socket leg $index must not pass"
}
$rows[2].OwningProcess=999
Assert-Equal 'UNCONFIRMED' (Test-LocalTcpDirectSocketPath @parameters -Snapshots @($snapshot)) 'an unrelated process reaching the receiver is not DIRECT proof'
$rows[2].OwningProcess=102
Assert-Equal 'UNCONFIRMED' (Test-LocalTcpDirectSocketPath @parameters -Snapshots @([pscustomobject]@{connections=$rows[0..1]},[pscustomobject]@{connections=$rows[2..3]})) 'legs from different snapshots must not be combined'
Assert-Equal 'UNCONFIRMED' (Test-LocalTcpDirectSocketPath @parameters -Snapshots @([pscustomobject]@{connections=@($rows)+(New-Socket 102 50003 53123)})) 'a simultaneous owned proxy socket blocks DIRECT'
$route.action='PROXY'
Assert-Equal 'UNCONFIRMED' (Test-LocalTcpDirectSocketPath @parameters -Snapshots @($snapshot)) 'proxy action must not pass the DIRECT gate'
$route.action='DIRECT';$route.pid=999
Assert-Equal 'UNCONFIRMED' (Test-LocalTcpDirectSocketPath @parameters -Snapshots @($snapshot)) 'another client route record must not pass'
$route.pid=101
$receiver.remote_port=50004
Assert-Equal 'UNCONFIRMED' (Test-LocalTcpDirectSocketPath @parameters -Snapshots @($snapshot)) 'payload received on an unowned tuple must not pass'
$receiver.remote_port=50001;$route.event='ROUTE_DECISION'
$directRows=@((New-Socket 101 50001 53121),(New-Socket 103 53121 50001))
Assert-Equal 'CLIENT_SOCKET' (Test-LocalTcpDirectSocketPath @parameters -Snapshots @([pscustomobject]@{connections=$directRows})) 'kernel bypass is distinct from Core relay'
'PASS: local TCP DIRECT socket evidence (12 checks; synthetic, no product runtime)'
