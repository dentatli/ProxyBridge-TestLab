[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'src\server_agent\performance_origin.py'
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures\performance-origin'
$fixture = Join-Path $fixtureRoot 'origin-fixture.json'
$exercise = Join-Path $fixtureRoot 'exercise_performance_origin.py'

# Break caught: removing the pure origin state machine prevents validation of
# bounded interval evidence and turns protocol metrics into unchecked data.
Assert-True (Test-Path -LiteralPath $source -PathType Leaf) 'performance-origin source must exist'
$python = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1
Assert-True ($null -ne $python) 'Python is required for the offline performance-origin test'

$output = @(& $python.Source -I -B $exercise (Split-Path -Parent $source) $fixture)
Assert-Equal 0 $LASTEXITCODE 'performance-origin fixture exit code'
$result = (($output | Where-Object { $_ -match '^\{' } | Select-Object -Last 1) | ConvertFrom-Json)
$records = @($result.records)
Assert-Equal 4 $records.Count 'origin must emit begin, two samples, and end'
Assert-Equal 'begin' ([string]$records[0].record_type) 'origin begin record'
Assert-Equal 1 ([int]$records[0].schema_version) 'origin schema version'
Assert-Equal 'fixture-workload' ([string]$records[0].workload_id) 'origin workload identity'
Assert-Equal 'fixture-window' ([string]$records[0].window_id) 'origin window identity'
Assert-Equal 400 ([Int64]$records[1].tcp_bytes) 'first monotonic TCP interval'
Assert-Equal 600 ([Int64]$records[2].tcp_bytes) 'second monotonic TCP interval'
Assert-Equal 1000 ([Int64]$records[3].tcp_bytes) 'end record must aggregate interval counters'
Assert-Equal 0 ([Int64]$records[3].udp_bytes) 'typed UDP byte counter must be retained for TCP windows'
Assert-Equal 0 ([Int64]$records[3].udp_datagrams) 'typed UDP datagram counter must be retained for TCP windows'
Assert-Equal 'ENDPOINT_ONLY_NOT_PRODUCT_ATTRIBUTION' ([string]$records[3].resource_attribution) 'endpoint counters must not claim local product attribution'

Assert-Equal 'PERF_ORIGIN_DUPLICATE_BEGIN' ([string]$result.errors.duplicate_begin) 'duplicate begin must fail closed'
Assert-Equal 'PERF_ORIGIN_WINDOW_MISMATCH' ([string]$result.errors.window_mismatch) 'wrong window must fail closed'
Assert-Equal 'PERF_ORIGIN_CLOCK_NOT_MONOTONIC' ([string]$result.errors.clock) 'non-monotonic snapshot clock must fail closed'
Assert-Equal 'PERF_ORIGIN_IDENTITY_MISMATCH' ([string]$result.errors.identity) 'peer/process identity change must fail closed'
Assert-Equal 'PERF_ORIGIN_COUNTER_REGRESSION' ([string]$result.errors.counter) 'counter regression must fail closed'
Assert-Equal 'PERF_ORIGIN_INCOMPLETE_WINDOW' ([string]$result.errors.incomplete) 'short window must fail closed'
Assert-Equal 'PERF_ORIGIN_DUPLICATE_END' ([string]$result.errors.duplicate_end) 'duplicate end must fail closed'

'PASS: offline performance-origin evidence state machine'
