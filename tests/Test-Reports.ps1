[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/Env.psm1') -Force
Import-Module (Join-Path $root 'modules/Report.psm1') -Force
$environment = Import-DotEnv (Join-Path $PSScriptRoot 'fixtures/.env.test')
$temp = New-TestDirectory
try {
    $report = New-RunReport -OutputRoot $temp -RunId 'reports'
    $records = @(
        [pscustomobject]@{run_mode='mock';scenario_id='one';coverage_group='group-a';implementation_status='EXECUTABLE';selected=$true;status='MOCK_PASS';reason='ok';attempt=1;duration_ms=1},
        [pscustomobject]@{run_mode='mock';scenario_id='two';coverage_group='group-a';implementation_status='EXECUTABLE';selected=$true;status='MOCK_EXPECTED_FAIL';reason='fixture-secret';attempt=1;duration_ms=2},
        [pscustomobject]@{run_mode='mock';scenario_id='three';coverage_group='group-b';implementation_status='DECLARATIVE_ONLY';selected=$false;status='SKIPPED_CAPABILITY';reason='disabled';attempt=0;duration_ms=0}
    )
    foreach ($record in $records) { Add-ResultRecord -Report $report -Record $record -Environment $environment }
    $scenarios = @(
        [pscustomobject]@{coverage_group='group-a';implementation_status='EXECUTABLE'},
        [pscustomobject]@{coverage_group='group-a';implementation_status='EXECUTABLE'},
        [pscustomobject]@{coverage_group='group-b';implementation_status='DECLARATIVE_ONLY'}
    )
    Write-RunSummary -Report $report -Records $records -AllScenarios $scenarios -Environment $environment -RunMode mock
    Write-SafeTranscript -Report $report -Environment $environment -Message 'complete fixture-secret'
    Write-TestUtf8NoBom (Join-Path $report.scenario_root 'CaseSensitiveName.TXT') 'fixture'
    Complete-RunChecksums $report
    foreach ($file in @('results.jsonl','failures.jsonl','skipped.jsonl','summary.csv','summary.json','coverage.json','attempt-aggregates.json','transcript.txt','SHA256SUMS')) {
        $path = Join-Path $report.run_root $file; Assert-True (Test-Path -LiteralPath $path) "report '$file' must exist"; Assert-NoUtf8Bom $path "report '$file' must have no BOM"
    }
    foreach ($file in @('results.jsonl','failures.jsonl','skipped.jsonl')) { foreach ($line in @(Get-Content -LiteralPath (Join-Path $report.run_root $file) -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) { $null = $line | ConvertFrom-Json } }
    foreach ($file in @('summary.json','coverage.json','attempt-aggregates.json')) { $null = Get-Content -LiteralPath (Join-Path $report.run_root $file) -Raw -Encoding UTF8 | ConvertFrom-Json }
    $mockSummary = Get-Content -LiteralPath (Join-Path $report.run_root 'summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$mockSummary.execution_complete) 'summary must report completed execution independently of verdict'
    Assert-Equal 'EXPECTED_FAILURE_OBSERVED' $mockSummary.product_verdict 'summary must preserve a product verdict distinct from execution completion'
    foreach ($file in @('results.jsonl','failures.jsonl','transcript.txt')) { Assert-True (-not [IO.File]::ReadAllText((Join-Path $report.run_root $file)).Contains('fixture-secret')) 'reports must share redaction boundary' }
    $checksums = @(Get-Content -LiteralPath $report.checksum_path -Encoding UTF8); Assert-True ($checksums.Count -ge 6) 'checksums must cover evidence files'
    Assert-True (($checksums -join "`n") -match 'scenarios/CaseSensitiveName\.TXT') 'checksum paths must preserve filename case'
    $mockCoverage = Get-Content -LiteralPath (Join-Path $report.run_root 'coverage.json') -Raw -Encoding UTF8
    Assert-True ($mockCoverage -match '"run_mode"\s*:\s*"mock"') 'coverage must include run_mode'
    Assert-True ($mockCoverage -notmatch 'TESTED_PASS|TESTED_FAIL') 'mock coverage must never claim tested status'

    $incomplete = New-EvidenceCompletenessMatrix -ScenarioEvidenceRoot (Join-Path $report.scenario_root 'missing') -RunRoot $report.run_root -RunMode real -AssertionResult ([pscustomobject]@{route_evidence_required=$false;contamination=@();harness_errors=@()}) -PostCleanup ([pscustomobject]@{passed=$true})
    Assert-True (-not [bool]$incomplete.overall_complete) 'missing mandatory evidence must fail the completeness matrix'
    Assert-True (@($incomplete.missing_mandatory) -contains 'client_jsonl') 'completeness matrix must identify a missing client channel'
    Assert-True (@($incomplete.missing_mandatory) -contains 'endpoint_jsonl') 'completeness matrix must identify a missing endpoint channel'

    $realReport = New-RunReport -OutputRoot $temp -RunId 'reports-real'
    $realRecords = @(
        [pscustomobject]@{run_mode='real';scenario_id='real-one';coverage_group='group-a';implementation_status='EXECUTABLE';selected=$true;status='PASS';reason='ok';attempt=1;duration_ms=1},
        [pscustomobject]@{run_mode='real';scenario_id='real-two';coverage_group='group-a';implementation_status='EXECUTABLE';selected=$true;status='FAIL_PRODUCT';reason='known product failure';attempt=1;duration_ms=1},
        [pscustomobject]@{run_mode='real';scenario_id='real-repeat';coverage_group='group-a';implementation_status='EXECUTABLE';selected=$true;status='PASS';reason='first attempt';attempt=1;duration_ms=1},
        [pscustomobject]@{run_mode='real';scenario_id='real-repeat';coverage_group='group-a';implementation_status='EXECUTABLE';selected=$true;status='FAIL_PRODUCT';reason='second attempt';attempt=2;duration_ms=1}
    )
    Write-RunSummary -Report $realReport -Records $realRecords -AllScenarios @([pscustomobject]@{coverage_group='group-a';implementation_status='EXECUTABLE'}) -Environment $environment -RunMode real
    $realCoverage = Get-Content -LiteralPath (Join-Path $realReport.run_root 'coverage.json') -Raw -Encoding UTF8
    Assert-True ($realCoverage -match 'TESTED_PASS') 'only real coverage may normalize PASS to TESTED_PASS'
    $realSummary = Get-Content -LiteralPath (Join-Path $realReport.run_root 'summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$realSummary.execution_complete) 'product failure must not imply an incomplete sweep'
    Assert-Equal 'FAIL_PRODUCT' $realSummary.product_verdict 'real product verdict must remain explicit'
    Assert-Equal 1 $realSummary.attempt_aggregates.intermittent 'a mixed repeated result must be exposed as intermittent'
    $realAggregates = @(Get-Content -LiteralPath (Join-Path $realReport.run_root 'attempt-aggregates.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
    $realAggregates = @($realAggregates | ForEach-Object { $_ })
    $repeatAggregate = @($realAggregates | Where-Object { $null -ne $_.PSObject.Properties['scenario_id'] -and [string]$_.scenario_id -eq 'real-repeat' }) | Select-Object -First 1
    Assert-Equal 'INTERMITTENT' $repeatAggregate.aggregate 'a flaky result must never be normalized to PASS'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }
'PASS: reports'
