#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('tcp_transfer','tcp_upload','tcp_download','tcp_rtt','tcp_rtt_three_modes','tcp_connections','tcp_loaded_rtt','udp_echo')][string]$Scenario,
    [Parameter(Mandatory)][ValidateSet('SMOKE','MULTI_TARGET')][string]$Profile,
    [Parameter(Mandatory)][string]$EnvPath,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [string]$CancellationPath='',
    [ValidateSet('SHORT','NORMAL','LONG')][string]$Duration='',
    [ValidateSet('LOW','HIGH')][string]$Load=''
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$parameters=@{Profile=$Profile;EnvPath=$EnvPath;EvidenceDirectory=$EvidenceDirectory}
switch ($Scenario) {
    'tcp_transfer' { $file='Invoke-LocalTcpBenchmark.ps1';$parameters['ProductContract']='driver';$parameters['TransferOnly']=$true }
    'tcp_upload' { $file='Invoke-LocalTcpBenchmark.ps1';$parameters['ProductContract']='driver';$parameters['TransferOnly']=$true;$parameters['Direction']='push' }
    'tcp_download' { $file='Invoke-LocalTcpBenchmark.ps1';$parameters['ProductContract']='driver';$parameters['TransferOnly']=$true;$parameters['Direction']='pull' }
    'tcp_rtt' { $file='Invoke-LocalTcpRtt.ps1';$parameters['ProductContract']='driver' }
    'tcp_rtt_three_modes' { $file='Invoke-LocalTcpRtt.ps1';$parameters['ProductContract']='driver';$parameters['ThreeModes']=$true }
    'tcp_connections' { $file='Invoke-LocalTcpConnections.ps1' }
    'tcp_loaded_rtt' { $file='Invoke-LocalTcpLoadedRtt.ps1';$parameters['ProxyNoDelay']=$true }
    'udp_echo' { $file='Invoke-LocalUdpBenchmark.ps1' }
}
if ($Profile -ne 'SMOKE') { throw 'LAB_CONTROLLER_PROFILE_INVALID' }
if ($CancellationPath) {
    if ($Scenario -notin @('tcp_rtt','tcp_transfer','tcp_upload','tcp_download','tcp_rtt_three_modes','tcp_connections','udp_echo','tcp_loaded_rtt')) { throw 'LAB_CANCELLATION_SCENARIO_NOT_SUPPORTED' }
    $parameters['CancellationPath']=$CancellationPath
}
if ($Duration -or $Load) {
    if (-not $Duration -or -not $Load -or $Scenario -notin @('tcp_rtt','tcp_transfer','tcp_upload','tcp_download','tcp_rtt_three_modes','tcp_connections','udp_echo','tcp_loaded_rtt')) { throw 'LAB_WORKLOAD_INVALID' }
    $parameters['Duration']=$Duration;$parameters['Load']=$Load
}
& (Join-Path $PSScriptRoot $file) @parameters
