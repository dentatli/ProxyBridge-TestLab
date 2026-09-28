[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$root = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $root 'scripts\Build-PerformanceHarness.ps1'
$fixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\performance\offline-request.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# Break caught: removing the worker build boundary means neither validated source
# nor its real self-test/offline JSONL contract can be exercised.
Assert-True (Test-Path -LiteralPath $buildScript -PathType Leaf) 'performance worker build script must exist'

$validation = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildScript -ValidateOnly)
Assert-Equal 0 $LASTEXITCODE 'performance worker source validation exit code'
$validationRecord = ($validation | Where-Object { $_ -match '^\{' } | Select-Object -Last 1) | ConvertFrom-Json
Assert-Equal 'VALIDATED' ([string]$validationRecord.status) 'performance worker validation status'
Assert-Equal 'pb_perf_client.c' ([string]$validationRecord.source_name) 'performance worker validation source'

$compiler = @(Get-Command cl.exe -ErrorAction SilentlyContinue; Get-Command gcc.exe -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($compiler.Count -eq 0 -and -not ($env:CC -and (Test-Path -LiteralPath $env:CC -PathType Leaf))) {
    'BUILD_GATE=NO_COMPILER; source and argument validation completed; binary self-test was not executed.'
    return
}

$build = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildScript)
Assert-Equal 0 $LASTEXITCODE 'performance worker build exit code'
$buildRecord = ($build | Where-Object { $_ -match '^\{' } | Select-Object -Last 1) | ConvertFrom-Json
Assert-Equal 'x64 (0x8664)' ([string]$buildRecord.machine) 'performance worker must be an x64 PE'
$worker = [string]$buildRecord.output
Assert-True (Test-Path -LiteralPath $worker -PathType Leaf) 'performance worker artifact must exist'

$selfTestLines = @(& $worker --self-test)
Assert-Equal 0 $LASTEXITCODE 'performance worker self-test exit code'
$selfTest = @($selfTestLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
Assert-Equal 4 $selfTest.Count 'self-test must emit header, two samples, and summary'
Assert-Equal 'header' ([string]$selfTest[0].record_type) 'self-test header record'
Assert-Equal 1 ([int]$selfTest[0].schema_version) 'self-test schema version'
Assert-Equal 'self-test' ([string]$selfTest[0].mode) 'self-test mode'
Assert-True ([bool]$selfTest[0].non_product_acceptance) 'self-test must never claim product acceptance'
Assert-Equal 'summary' ([string]$selfTest[3].record_type) 'self-test summary record'
Assert-Equal 0 ([int]$selfTest[3].failures) 'self-test summary failures'

$offlineLines = @(& $worker --offline --protocol $fixture.protocol --workload-id $fixture.workload_id --window-id $fixture.window_id --warmup-ms $fixture.warmup_ms --sample-ms $fixture.sample_ms --samples $fixture.samples)
Assert-Equal 0 $LASTEXITCODE 'offline worker exit code'
$offline = @($offlineLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
Assert-Equal 4 $offline.Count 'offline worker must emit header, two samples, and summary'
Assert-Equal 'offline' ([string]$offline[0].mode) 'offline record mode'
Assert-Equal $fixture.workload_id ([string]$offline[0].workload_id) 'offline workload identity'
Assert-Equal $fixture.window_id ([string]$offline[0].window_id) 'offline window identity'
Assert-Equal ([int]$fixture.warmup_ms) ([int]$offline[0].warmup_ms) 'offline warm-up bound'
Assert-Equal ([int]$fixture.sample_ms) ([int]$offline[1].sample_ms) 'offline sample bound'
Assert-True ([Int64]$offline[1].monotonic_end_ticks -gt [Int64]$offline[1].monotonic_start_ticks) 'offline sample timestamps must be monotonic'
Assert-Equal 0 ([int]$offline[3].lost) 'offline TCP loss count'
Assert-True ([Int64]$offline[3].bytes -gt 0) 'offline summary bytes'
Assert-True ([double]$offline[3].rate_bytes_per_second -gt 0) 'offline rate sample'
Assert-True ([double]$offline[3].latency_p99_us -ge [double]$offline[3].latency_p50_us) 'offline latency percentile ordering'

$savedErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $invalidOutput = @(& $worker --offline --protocol icmp --workload-id $fixture.workload_id --window-id $fixture.window_id --warmup-ms 1 --sample-ms 1 --samples 1 2>&1)
    $invalidExitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = $savedErrorActionPreference }
Assert-Equal 2 $invalidExitCode 'invalid offline protocol must fail closed'
Assert-True (($invalidOutput -join "`n") -match 'PERF_ARGUMENT_INVALID: protocol') 'invalid protocol error must be stable'

'PASS: native performance worker self-test and offline contract'
