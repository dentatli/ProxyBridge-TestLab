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
    'Test-EndpointEvidence.ps1',
    'Test-AcceptedSmoke.ps1',
    'Test-PreparedRealSmoke.ps1',
    'Test-MockRuntime.ps1',
    'Test-Reports.ps1',
    'Test-Catalog.ps1'
    'Test-ProtocolContracts.ps1'
    'Test-ProtocolWorker.ps1'
    'Test-ProtocolVerticalSlice.ps1'
    'Test-ProtocolRunner.ps1'
    'Test-ProtocolMatrixIntegration.ps1'
    'Test-UiShell.ps1'
    'Test-UiSettings.ps1'
    'Test-ServerProvisioning.ps1'
    'Test-RunOrchestration.ps1'
    'Test-Packaging.ps1'
)
$passed = 0
foreach ($test in $tests) {
    $path = Join-Path $PSScriptRoot $test
    & $path
    $passed++
}
"PASS: Run-All ($passed targeted tests)"
