[CmdletBinding()]
param(
    [string]$EnvPath = (Join-Path $PSScriptRoot '.env'),
    [string]$CapabilitiesPath = (Join-Path $PSScriptRoot 'config/capabilities.json'),
    [string]$SuitePath = (Join-Path $PSScriptRoot 'config/suites.json'),
    [string]$ScenarioRoot = (Join-Path $PSScriptRoot 'scenarios'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'evidence'),
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $DryRun) {
    throw 'RUNTIME_NOT_IMPLEMENTED'
}

Import-Module (Join-Path $PSScriptRoot 'modules/Env.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/Config.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/ProfileAdapter.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/Report.psm1') -Force

try {
    $environment = Import-DotEnv -Path $EnvPath
    $capabilities = Import-CapabilitiesConfig -Path $CapabilitiesPath
    $suite = Import-SuiteConfig -Path $SuitePath
    $scenarios = Import-ScenarioCatalog -ScenarioRoot $ScenarioRoot
}
catch {
    throw "FAIL_CONFIGURATION: $($_.Exception.Message)"
}

$report = New-DryRunReport -OutputRoot $OutputRoot
$summary = Get-EnvironmentSummary -Environment $environment
Write-JsonReport -Value $summary -Path (Join-Path $report.run_root 'environment-summary.json')
Write-JsonReport -Value $suite -Path (Join-Path $report.run_root 'resolved-suite.json')
Write-SafeTranscript -Report $report -Environment $environment -Message "Dry-run started; environment keys loaded: $($summary.Count)."

$generatedProfiles = [System.Collections.Generic.List[object]]::new()
$profileGenerationFailureCount = 0
foreach ($scenario in $scenarios) {
    $decision = Test-ScenarioSelection -Scenario $scenario -Capabilities $capabilities -Suite $suite
    if (-not $decision.selected) {
        Add-SelectionRecord -Report $report -Environment $environment -Record ([pscustomobject]@{
            scenario_id = $scenario.scenario_id
            status      = $decision.status
            reason      = $decision.reason
        })
        Write-SafeTranscript -Report $report -Environment $environment -Message "$($scenario.scenario_id): $($decision.status) ($($decision.reason))."
        continue
    }

    try {
        $profile = New-ResolvedProfile -Scenario $scenario -Environment $environment -TemplatePath (Join-Path $PSScriptRoot 'templates/profile.pbprofile.template')
        $written = Write-ResolvedProfile -Profile $profile -ScenarioId $scenario.scenario_id -OutputDirectory $report.profile_root
        $generatedProfiles.Add($written)
        Add-SelectionRecord -Report $report -Environment $environment -Record ([pscustomobject]@{
            scenario_id   = $scenario.scenario_id
            status        = 'DRY_RUN_READY'
            reason        = 'profile generated'
            profile_sha256 = $written.sha256
        })
        Write-SafeTranscript -Report $report -Environment $environment -Message "$($scenario.scenario_id): DRY_RUN_READY; profile SHA-256 $($written.sha256)."
    }
    catch {
        $profileGenerationFailureCount++
        $safeReason = $_.Exception.Message
        Add-SelectionRecord -Report $report -Environment $environment -Record ([pscustomobject]@{
            scenario_id = $scenario.scenario_id
            status      = 'FAIL_PROFILE_GENERATION'
            reason      = $safeReason
        })
        Write-SafeTranscript -Report $report -Environment $environment -Message "$($scenario.scenario_id): FAIL_PROFILE_GENERATION ($safeReason)."
    }
}

Write-ChecksumReport -Report $report -Profiles $generatedProfiles.ToArray()
Write-SafeTranscript -Report $report -Environment $environment -Message "Dry-run completed; profile generation failures: $profileGenerationFailureCount."
if ($profileGenerationFailureCount -gt 0) {
    throw "FAIL_PROFILE_GENERATION_COUNT=$profileGenerationFailureCount"
}
"DRY_RUN_COMPLETE run_id=$($report.run_id)"
