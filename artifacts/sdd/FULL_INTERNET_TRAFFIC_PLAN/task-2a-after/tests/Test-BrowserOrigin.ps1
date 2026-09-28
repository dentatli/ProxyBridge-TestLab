$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$root = Split-Path -Parent $PSScriptRoot
$python = Get-Command python -ErrorAction SilentlyContinue
Assert-True ($null -ne $python) 'Python is required for the offline browser-origin contract test'

$fixture = Join-Path $PSScriptRoot 'fixtures\browser-origin\contract_test.py'
Assert-True (Test-Path -LiteralPath $fixture -PathType Leaf) 'browser-origin offline fixture must exist'

$output = @(& $python.Source -I -B $fixture $root)
Assert-Equal 0 $LASTEXITCODE 'offline browser-origin fixture exit code'
Assert-SequenceEqual @('PASS: offline browser-origin contract') @($output) 'browser-origin contract result'

'PASS: browser-origin'
