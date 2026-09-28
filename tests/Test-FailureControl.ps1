$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$root = Split-Path -Parent $PSScriptRoot
$python = Get-Command python -ErrorAction SilentlyContinue
Assert-True ($null -ne $python) 'Python is required for the offline failure-control contract test'

$fixture = Join-Path $PSScriptRoot 'fixtures\failure-control\contract_test.py'
Assert-True (Test-Path -LiteralPath $fixture -PathType Leaf) 'failure-control offline fixture must exist'

$output = @(& $python.Source -I -B $fixture $root)
Assert-Equal 0 $LASTEXITCODE 'offline failure-control fixture exit code'
Assert-SequenceEqual @('PASS: offline failure-control contract') @($output) 'failure-control contract result'

'PASS: failure-control'
