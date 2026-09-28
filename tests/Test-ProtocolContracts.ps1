[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/ProtocolContracts.psm1') -Force
Import-Module (Join-Path $root 'modules/ScenarioCatalog.psm1') -Force

$contracts = Import-TrafficProtocolContracts -ConfigRoot (Join-Path $root 'config')
Assert-Equal 24 $contracts.capability_count 'traffic capability count'
Assert-Equal 24 $contracts.evidence_profile_count 'protocol evidence profile count'
Assert-Equal 38 $contracts.family_count 'protocol family count'
Assert-Equal 37 $contracts.roadmap_count 'every deferred scenario must have one roadmap entry'

$families = @($contracts.family_catalog.families)
Assert-Equal 2 @($families | Where-Object delivery_status -eq 'EXISTING_EXECUTABLE').Count 'native transport families remain executable'
Assert-Equal 28 @($families | Where-Object delivery_status -eq 'PLANNED_EXECUTABLE').Count 'planned supported protocol families'
Assert-Equal 1 @($families | Where-Object delivery_status -eq 'CAPABILITY_GATED').Count 'honestly gated protocol families'
Assert-Equal 7 @($families | Where-Object delivery_status -eq 'UNSUPPORTED_PRODUCT_SCOPE').Count 'unsupported network families remain explicit'
Assert-Equal 0 @($families | Where-Object { [bool]$_.external_account_required }).Count 'authoritative automation must not require third-party accounts'

$catalog = @(Import-ScenarioCatalog (Join-Path $root 'scenarios'))
$roadmapIds = @($contracts.roadmap.entries | Select-Object -ExpandProperty scenario_id | Sort-Object)
Assert-Equal 37 @($roadmapIds | Sort-Object -Unique).Count 'deferred baseline roadmap IDs must remain unique'
foreach ($scenarioId in $roadmapIds) {
    Assert-Equal 1 @($catalog | Where-Object scenario_id -eq $scenarioId).Count "$scenarioId roadmap entry must reference one live catalog scenario"
}
$remainingDeclarativeIds = @($catalog | Where-Object implementation_status -eq 'DECLARATIVE_ONLY' | Select-Object -ExpandProperty scenario_id)
foreach ($scenarioId in $remainingDeclarativeIds) {
    Assert-True ($roadmapIds -contains $scenarioId) "$scenarioId remaining work must stay on the approved roadmap"
}
$resolvedSystemIds = @($catalog | Where-Object implementation_status -eq 'SYSTEM_CHECK' | Select-Object -ExpandProperty scenario_id | Sort-Object)
$roadmapSystemIds = @($contracts.roadmap.entries | Where-Object resolution -eq 'SYSTEM_CHECK' | Select-Object -ExpandProperty scenario_id | Sort-Object)
Assert-SequenceEqual $roadmapSystemIds $resolvedSystemIds 'system-check resolution must match the live catalog'

$discord = $contracts.roadmap.entries | Where-Object scenario_id -eq 'canary-discord-voice'
Assert-Equal 'CONTROLLED_EQUIVALENCE' $discord.resolution 'closed third-party voice must use a controlled standards-based equivalent'
$receiveOnly = $contracts.roadmap.entries | Where-Object scenario_id -eq 'udp-receive-only'
Assert-True ([string]$receiveOnly.note -match 'registration' -and [string]$receiveOnly.note -match 'NAT') 'receive-only UDP roadmap must preserve the NAT registration boundary'
$systemChecks = @($contracts.roadmap.entries | Where-Object resolution -eq 'SYSTEM_CHECK')
Assert-Equal 5 $systemChecks.Count 'orchestrator lifecycle entries must remain system checks rather than product traffic verdicts'

foreach ($path in @(
    'config/traffic-capability-model.json',
    'config/protocol-evidence-contract.json',
    'config/protocol-families.json',
    'config/traffic-run-profiles.json',
    'config/deferred-scenario-roadmap.json',
    'docs/FULL_INTERNET_TRAFFIC_PLAN.md'
)) { Assert-NoUtf8Bom (Join-Path $root $path) "$path must be UTF-8 without BOM" }

$temp = New-TestDirectory
try {
    foreach ($name in @('traffic-capability-model.json','protocol-evidence-contract.json','protocol-families.json','traffic-run-profiles.json','deferred-scenario-roadmap.json')) {
        Copy-Item -LiteralPath (Join-Path (Join-Path $root 'config') $name) -Destination (Join-Path $temp $name)
    }

    $tamperedFamilies = Get-Content -LiteralPath (Join-Path $temp 'protocol-families.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    ($tamperedFamilies.families | Where-Object id -eq 'http1').evidence_profile_id = 'missing-profile'
    Write-TestUtf8NoBom (Join-Path $temp 'protocol-families.json') (($tamperedFamilies | ConvertTo-Json -Depth 30) + [Environment]::NewLine)
    Assert-Throws { Import-TrafficProtocolContracts -ConfigRoot $temp } 'TRAFFIC_EVIDENCE_PROFILE_UNKNOWN' 'unknown protocol evidence profile must fail closed'

    Copy-Item -LiteralPath (Join-Path $root 'config/protocol-families.json') -Destination (Join-Path $temp 'protocol-families.json') -Force
    $tamperedFamilies = Get-Content -LiteralPath (Join-Path $temp 'protocol-families.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    ($tamperedFamilies.families | Where-Object id -eq 'browser-web').external_account_required = $true
    Write-TestUtf8NoBom (Join-Path $temp 'protocol-families.json') (($tamperedFamilies | ConvertTo-Json -Depth 30) + [Environment]::NewLine)
    Assert-Throws { Import-TrafficProtocolContracts -ConfigRoot $temp } 'TRAFFIC_EXTERNAL_ACCOUNT_FORBIDDEN' 'third-party account dependency must fail authoritative automation'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

'PASS: protocol taxonomy, capability and evidence contracts'
