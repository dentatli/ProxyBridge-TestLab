[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/Pairwise.psm1') -Force
$dimensions = [pscustomobject][ordered]@{
    payload = @(1, 64, 1200)
    close = @('graceful', 'abortive')
    selector = @('basename', 'full-path')
    endpoint = @('echo', 'delayed', 'refused')
}
$first = @(Get-DeterministicPairwiseCases $dimensions)
$second = @(Get-DeterministicPairwiseCases $dimensions)
Assert-True ($first.Count -lt 36) 'pairwise set must be smaller than Cartesian product'
Assert-Equal ($first | ConvertTo-Json -Depth 20 -Compress) ($second | ConvertTo-Json -Depth 20 -Compress) 'pairwise output must be deterministic'
$coverage = Test-PairwiseCoverage -Dimensions $dimensions -Cases $first
Assert-True $coverage.covered 'every value pair must be covered'
'PASS: pairwise'
