[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tests = @(
    'Test-Foundation.ps1',
    'Test-ProfileValidation.ps1',
    'Test-Redaction.ps1',
    'Test-ScenarioSelection.ps1',
    'Test-Pairwise.ps1',
    'Test-ClientContract.ps1',
    'Test-ProcessLifecycle.ps1',
    'Test-RuntimePreparation.ps1',
    'Test-DirectBaseline.ps1',
    'Test-EvidenceAssertions.ps1',
    'Test-AcceptedSmoke.ps1',
    'Test-PreparedRealSmoke.ps1',
    'Test-MockRuntime.ps1',
    'Test-Reports.ps1',
    'Test-Catalog.ps1'
)
$passed = 0
foreach ($test in $tests) {
    $path = Join-Path $PSScriptRoot $test
    & $path
    $passed++
}
"PASS: Run-All ($passed targeted tests)"
