[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/Env.psm1') -Force
Import-Module (Join-Path $root 'modules/Config.psm1') -Force
Import-Module (Join-Path $root 'modules/ProfileAdapter.psm1') -Force
Import-Module (Join-Path $root 'modules/ProfileValidator.psm1') -Force
Import-Module (Join-Path $root 'modules/ScenarioCatalog.psm1') -Force
$environment = Get-EffectiveRuntimeEnvironment -Environment (Import-DotEnv -Path (Join-Path $PSScriptRoot 'fixtures/.env.test')) -RuntimeConfig (Import-RuntimeConfig (Join-Path $root 'config/runtime.json'))
$scenario = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/scenario.test.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$profile = New-ResolvedProfile -Scenario $scenario -Environment $environment -TemplatePath (Join-Path $root 'templates/profile.pbprofile.template')
Assert-True (Test-ProxyBridgeProfile -Profile $profile).valid 'valid generated profile must pass'

function Copy-Profile { return ($profile | ConvertTo-Json -Depth 100 | ConvertFrom-Json) }
$invalid = Copy-Profile; $invalid.ProxyConfigs[0].Type = 'INVALID'; Assert-True (-not (Test-ProxyBridgeProfile $invalid).valid) 'proxy type enum must be enforced'
$invalid = Copy-Profile; $invalid.ProxyConfigs[0].Port = 1080; Assert-True (-not (Test-ProxyBridgeProfile $invalid).valid) 'proxy port must be string'
$invalid = Copy-Profile; $invalid.ProxyRules[1].ProxyConfigId = 1; Assert-True (-not (Test-ProxyBridgeProfile $invalid).valid) 'DIRECT requires ProxyConfigId zero'
$invalid = Copy-Profile; $invalid.ProxyRules[0].ProxyConfigId = 99; Assert-True (-not (Test-ProxyBridgeProfile $invalid).valid) 'PROXY requires an existing config ID'
$invalid = Copy-Profile; $invalid.ProxyRules[0].Protocol = 'ICMP'; Assert-True (-not (Test-ProxyBridgeProfile $invalid).valid) 'protocol enum must be enforced'
$invalid = Copy-Profile; $invalid.ProxyRules[0].IsEnabled = 'true'; Assert-True (-not (Test-ProxyBridgeProfile $invalid).valid) 'IsEnabled must be boolean'
$invalid = Copy-Profile; $invalid.ProxyRules[0].ProcessName = ''; Assert-True (-not (Test-ProxyBridgeProfile $invalid).valid) 'critical fields must not be empty'
$invalid = Copy-Profile; $invalid.ProxyConfigs[0].Port = '70000'; Assert-True (-not (Test-ProxyBridgeProfile $invalid).valid) 'proxy port range must be enforced'
$invalid = Copy-Profile; $invalid.ProxyRules[0].TargetPorts = '41010-41000'; Assert-True (-not (Test-ProxyBridgeProfile $invalid).valid) 'rule port range order must be enforced'
$invalid = Copy-Profile; $invalid.ProxyRules[0].TargetHosts = '${MISSING}'; Assert-True (-not (Test-ProxyBridgeProfile $invalid).valid) 'unresolved placeholders must fail validation'
$negative = Import-ScenarioCatalog (Join-Path $root 'scenarios') | Where-Object scenario_id -eq 'rule-missing-proxy-config'
$negativeValidation = Test-ExpectedProfileValidation -Scenario $negative -Environment $environment -TemplatePath (Join-Path $root 'templates/profile.pbprofile.template')
Assert-True $negativeValidation.passed 'intentional missing proxy config must be rejected as expected'
Assert-True (-not $negativeValidation.may_write) 'invalid profile must never be written for product runtime'
'PASS: profile validation'
