#Requires -RunAsAdministrator
[CmdletBinding()]
param([ValidateSet('SMOKE')][string]$Profile='SMOKE',
    [Parameter(Mandatory)][string]$EnvPath,[Parameter(Mandatory)][string]$EvidenceDirectory,
    [Parameter(Mandatory)][ValidateSet('SHORT','NORMAL','LONG')][string]$Duration,
    [Parameter(Mandatory)][ValidateSet('LOW','HIGH')][string]$Load,[string]$CancellationPath='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/UdpWorkload.psm1')
$workload=Get-LocalUdpWorkload -Duration $Duration -Load $Load
Import-Module (Join-Path $root 'modules/LocalRuntime.psm1')
$python=Get-LocalPythonExecutable -Root $root
& (Join-Path $PSScriptRoot 'Invoke-WfpUnruledComparison.ps1') -EnvPath $EnvPath -EvidenceDirectory $EvidenceDirectory `
    -UdpProxyPythonPath $python -ComparisonMode ROUTED -EvidenceLogMode BUFFERED -PairCount 1 `
    -PacketCount $workload.packet_count -IntervalMs $workload.interval_ms -MessageSize $workload.message_bytes `
    -WarmupPackets $workload.warmup_per_stream -Streams $workload.streams -DestinationMode SHARED `
    -Duration $Duration -Load $Load -CancellationPath $CancellationPath -AllowProductRuntime
