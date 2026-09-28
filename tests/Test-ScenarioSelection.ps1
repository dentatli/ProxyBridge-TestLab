[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/Config.psm1') -Force
Import-Module (Join-Path $root 'modules/ScenarioCatalog.psm1') -Force
$caps = Import-CapabilitiesConfig (Join-Path $PSScriptRoot 'fixtures/capabilities.test.json')
$suite = Import-SuiteConfig (Join-Path $PSScriptRoot 'fixtures/suite.test.json')
$defects = Import-KnownDefectsConfig (Join-Path $root 'config/known-defects.json')
$scenario = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/scenario.test.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$decision = Test-ScenarioSelection $scenario $caps $suite $defects; Assert-True $decision.selected 'matching scenario must select'
$copy = $scenario | ConvertTo-Json -Depth 100 | ConvertFrom-Json; $copy.requires = @('ipv6'); Assert-Equal 'SKIPPED_CAPABILITY' (Test-ScenarioSelection $copy $caps $suite $defects).status 'disabled capability must skip'
$copy = $scenario | ConvertTo-Json -Depth 100 | ConvertFrom-Json; $copy.tags += 'excluded'; Assert-Equal 'SKIPPED_SELECTION' (Test-ScenarioSelection $copy $caps $suite $defects).status 'exclude tag must skip'
$declarative = $scenario | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$declarative.implementation_status = 'DECLARATIVE_ONLY'; $declarative.implementation_reason = 'fixture executor absent'
Assert-True (Test-ScenarioSelection $declarative $caps $suite $defects -RunMode dry-run).selected 'dry-run must retain declarative inventory'
Assert-Equal 'NOT_IMPLEMENTED' (Test-ScenarioSelection $declarative $caps $suite $defects -RunMode real).status 'real selection must reject declarative scenarios'
$systemCheck = $scenario | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$systemCheck.implementation_status = 'SYSTEM_CHECK'; $systemCheck.implementation_reason = 'enforced globally'
Assert-Equal 'SYSTEM_CHECK' (Test-ScenarioSelection $systemCheck $caps $suite $defects -RunMode real).status 'system checks must never become standalone traffic verdicts'
$capabilityGated = $scenario | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$capabilityGated.implementation_status = 'CAPABILITY_GATED'; $capabilityGated.implementation_reason = 'separate adapter required'
Assert-Equal 'SKIPPED_CAPABILITY' (Test-ScenarioSelection $capabilityGated $caps $suite $defects -RunMode real).status 'capability-gated inventory must not fall through to the native client'
$catalog = Import-ScenarioCatalog (Join-Path $root 'scenarios')
$issue209 = $catalog | Where-Object scenario_id -eq 'issue209-tcp-to-udp'; Assert-Equal 'BLOCKED_BY_KNOWN_DEFECT' (Test-ScenarioSelection $issue209 $caps ([pscustomobject]@{ selection = [pscustomobject]@{ include_tags=@();exclude_tags=@();include_scenario_ids=@();exclude_scenario_ids=@() } }) $defects).status 'do-not-run defect must block'
$temp = New-TestDirectory
try {
    $json = $scenario | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText((Join-Path $temp 'one.json'), $json)
    [IO.File]::WriteAllText((Join-Path $temp 'two.json'), $json)
    Assert-Throws { Import-ScenarioCatalog $temp } 'Duplicate scenario ID' 'duplicate scenario IDs must be rejected'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }
'PASS: scenario selection'
