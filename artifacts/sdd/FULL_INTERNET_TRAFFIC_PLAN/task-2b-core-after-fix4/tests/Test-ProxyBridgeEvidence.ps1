[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/ProxyBridgeEvidence.psm1') -Force

$records = @(ConvertFrom-ProxyBridgeTextLines -Lines @(
    '2030-01-01T00:00:00Z fixture-browser.exe (PID:6100) from [2001:0DB8:0:0:0:0:0:1]:32001 -> 198.51.100.10:42080 via Direct'
))

Assert-Equal 1 $records.Count 'structured route line count'
Assert-Equal 'ROUTE_DECISION' $records[0].event 'structured route line event'
Assert-Equal '2001:db8::1' $records[0].local_ip 'structured local IP must be normalized'
Assert-Equal 32001 $records[0].local_port 'structured local port must be retained'
Assert-Equal '198.51.100.10' $records[0].destination_ip 'destination IP remains exact'
Assert-Equal 42080 $records[0].destination_port 'destination port remains exact'

$legacy = @(ConvertFrom-ProxyBridgeTextLines -Lines @(
    '2030-01-01T00:00:00Z pb_net_client.exe (4242) -> 198.51.100.10:41001 via Direct'
))
Assert-Equal 'ROUTE_DECISION' $legacy[0].event 'legacy non-browser route remains supported'
Assert-Equal '' $legacy[0].local_ip 'legacy route must not invent a local IP'
Assert-Equal 0 $legacy[0].local_port 'legacy route must not invent a local port'

'PASS: ProxyBridge route parser preserves canonical local endpoint evidence'
