[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$root = Split-Path -Parent $PSScriptRoot
$temp = New-TestDirectory
$scenarioIds = @(
    'protocol-dns-udp-direct',
    'protocol-dns-udp-block',
    'protocol-dns-udp-proxy'
)

try {
    $runnerOutput = @(& (Join-Path $root 'Run-WfpMatrix.ps1') `
        -EnvPath (Join-Path $PSScriptRoot 'fixtures/.env.test') `
        -CapabilitiesPath (Join-Path $root 'config/capabilities.json') `
        -SuitePath (Join-Path $root 'config/suites/mock-full.json') `
        -ScenarioRoot (Join-Path $root 'scenarios') `
        -MockFixtureRoot (Join-Path $PSScriptRoot 'fixtures/mock') `
        -OutputRoot $temp `
        -Only $scenarioIds `
        -MockRuntime)

    $pathLine = @($runnerOutput | Where-Object { [string]$_ -like 'EVIDENCE_PATH=*' }) | Select-Object -Last 1
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$pathLine)) 'protocol matrix run must publish its evidence path'
    $runRoot = ([string]$pathLine).Substring('EVIDENCE_PATH='.Length)
    Assert-True (Test-Path -LiteralPath $runRoot -PathType Container) 'protocol matrix evidence root must exist'

    $results = @(Get-Content -LiteralPath (Join-Path $runRoot 'results.jsonl') -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
    $selectedResults = @($results | Where-Object { [bool]$_.selected })
    Assert-Equal 3 $selectedResults.Count 'protocol matrix selection must execute exactly three requested scenarios'
    Assert-SequenceEqual $scenarioIds @($selectedResults.scenario_id) 'protocol matrix results must preserve deterministic selection order'
    $unexpected = @($selectedResults | Where-Object { [string]$_.status -ne 'MOCK_PASS' } | ForEach-Object { "$($_.scenario_id)=$($_.status):$($_.reason)" }) -join ' | '
    Assert-True ([string]::IsNullOrWhiteSpace($unexpected)) "DIRECT, BLOCK, and PROXY protocol mock scenarios must all pass exact evidence assertions; unexpected=$unexpected"

    $summary = Get-Content -LiteralPath (Join-Path $runRoot 'summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$summary.execution_complete) 'protocol matrix execution must complete independently of product verdict handling'
    foreach ($scenarioId in $scenarioIds) {
        $scenarioRoot = Join-Path (Join-Path $runRoot 'scenarios') $scenarioId
        foreach ($name in @('client-plan.json','client-result.json','proxybridge-evidence.json','vps-evidence.json','assertions.json','evidence-completeness.json')) {
            Assert-True (Test-Path -LiteralPath (Join-Path $scenarioRoot $name) -PathType Leaf) "$scenarioId must emit standard $name evidence"
        }
    }

    'PASS: protocol matrix orchestration integration'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
