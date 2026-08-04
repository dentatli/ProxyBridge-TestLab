[CmdletBinding()]
param(
    [string]$OutputRoot,
    [switch]$FixtureMode,
    [int]$MaxScenarios = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot 'evidence/mock' }
$envPath = $(if ($FixtureMode) { Join-Path $repoRoot 'tests/fixtures/.env.test' } else { Join-Path $repoRoot '.env' })
& (Join-Path $repoRoot 'Run-WfpMatrix.ps1') `
    -EnvPath $envPath `
    -CapabilitiesPath (Join-Path $repoRoot 'config/capabilities.json') `
    -SuitePath (Join-Path $repoRoot 'config/suites/mock-full.json') `
    -KnownDefectsPath (Join-Path $repoRoot 'config/known-defects.json') `
    -ScenarioRoot (Join-Path $repoRoot 'scenarios') `
    -OutputRoot $OutputRoot `
    -MaxScenarios $MaxScenarios `
    -MockRuntime
