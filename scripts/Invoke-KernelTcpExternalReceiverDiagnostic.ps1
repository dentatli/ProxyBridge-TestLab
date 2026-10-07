[CmdletBinding()]
param([Parameter(Mandatory)][string]$DiagnosticDirectory,
    [ValidateSet('Prepare','Inspect','Install','Run','Restore')][string]$Phase='Inspect')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/ExternalReceiverDiagnostic.psm1')
$DiagnosticDirectory=[IO.Path]::GetFullPath($DiagnosticDirectory)
$build=Get-Content -LiteralPath (Join-Path $DiagnosticDirectory 'kit/redirect-context-diagnostic.json') -Raw | ConvertFrom-Json
Assert-ExternalReceiverPolicy $build.external_receiver_policy
if ($Phase -eq 'Restore') {& (Join-Path $PSScriptRoot 'Invoke-KernelContextDiagnostic.ps1') -DiagnosticDirectory $DiagnosticDirectory -Phase Restore;return}
& (Join-Path $PSScriptRoot 'Invoke-KernelTcpContextStatusTrace.ps1') -DiagnosticDirectory $DiagnosticDirectory -Phase $Phase
