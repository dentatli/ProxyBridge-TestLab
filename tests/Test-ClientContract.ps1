[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
foreach ($module in @('Env','Config','ScenarioCatalog','ProfileAdapter','ProcessAdapter','ClientRunner')) { Import-Module (Join-Path $root "modules/$module.psm1") -Force }

function Get-ExpectedArguments {
    param([string]$Name)
    $document = Get-Content -LiteralPath (Join-Path $PSScriptRoot "fixtures/client-contract/$Name.arguments.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($document | ForEach-Object { [string]$_ })
}

function Get-CanonicalFixture {
    param([string]$Name)
    $raw = @(Import-ClientJsonLinesFile (Join-Path $PSScriptRoot "fixtures/client-jsonl/$Name.jsonl"))
    return @($raw | ConvertTo-CanonicalClientEvidence)
}

$environment = Get-EffectiveRuntimeEnvironment -Environment (Import-DotEnv (Join-Path $PSScriptRoot 'fixtures/.env.test')) -RuntimeConfig (Import-RuntimeConfig (Join-Path $root 'config/runtime.json'))
$contract = Import-ClientContract (Join-Path $root 'config/client-contract.json')
$catalog = @(Import-ScenarioCatalog (Join-Path $root 'scenarios'))
$jsonlPath = 'C:\Fixture\evidence\client.jsonl'

$stage34a = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'issue206-proxy-to-block-abortive') -Variables $environment
$plan34a = New-ClientPlan -Scenario $stage34a -ExecutablePath $environment['PB_CLIENT_EXE'] -RunId 'fixture-run' -JsonlPath $jsonlPath -Contract $contract
Assert-SequenceEqual (Get-ExpectedArguments 'stage34a-proxy-block') @($plan34a.arguments) 'Stage 3.4A exact argument array'

$stage34b = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'issue206-proxy-to-direct-ipv4-abortive') -Variables $environment
$plan34b = New-ClientPlan -Scenario $stage34b -ExecutablePath $environment['PB_CLIENT_EXE'] -RunId 'fixture-run' -JsonlPath $jsonlPath -Contract $contract
Assert-SequenceEqual (Get-ExpectedArguments 'stage34b-proxy-direct') @($plan34b.arguments) 'Stage 3.4B exact argument array'

$base = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-ipv4-direct') -Variables $environment
$basePlan = New-ClientPlan $base $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-SequenceEqual (Get-ExpectedArguments 'base-single-tcp') @($basePlan.arguments) 'base single TCP exact argument array'
$baseProxy = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'tcp-ipv4-proxy') -Variables $environment
$baseProxyPlan = New-ClientPlan $baseProxy $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
$proxyPolicyIndex = [array]::IndexOf(@($baseProxyPlan.arguments), '--tcp-peer-policy')
Assert-Equal 'record-only' $baseProxyPlan.arguments[$proxyPolicyIndex + 1] 'base PROXY TCP must default to record-only peer policy'

$udpConnected = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-ipv4-connected-direct') -Variables $environment
$udpConnectedPlan = New-ClientPlan $udpConnected $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-SequenceEqual (Get-ExpectedArguments 'base-single-udp-connected') @($udpConnectedPlan.arguments) 'base connected UDP exact argument array'

$udpUnconnected = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'udp-ipv4-unconnected-proxy') -Variables $environment
$udpUnconnectedPlan = New-ClientPlan $udpUnconnected $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-SequenceEqual (Get-ExpectedArguments 'base-single-udp-unconnected') @($udpUnconnectedPlan.arguments) 'base unconnected UDP exact argument array'

$issue209 = Resolve-JsonVariables -InputObject ($catalog | Where-Object scenario_id -eq 'issue209-tcp-to-udp') -Variables $environment
$issue209Plan = New-ClientPlan $issue209 $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract
Assert-SequenceEqual (Get-ExpectedArguments 'issue209-tcp-to-udp') @($issue209Plan.arguments) 'issue209 exact argument array'
Assert-Equal 'EXECUTABLE' $issue209.implementation_status 'exact issue209 builder and three-record model must be executable'
Assert-Equal 3 @($issue209Plan.expected_records).Count 'issue209 plan must require two flows and held recheck'
$invalidIssue209 = $issue209 | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$invalidIssue209.client.first_expect = 'no-echo'
Assert-Throws { New-ClientPlan $invalidIssue209 $environment['PB_CLIENT_EXE'] 'fixture-run' $jsonlPath $contract } 'CLIENT_ISSUE209_FIRST_EXPECT_MUST_BE_ECHO' 'issue209 first expectation must be echo'

$unsupportedFlags = @('--socket-mode','--remote-port','--payload-size','--second-protocol','--hold-first','--recheck-first')
foreach ($plan in @($basePlan, $baseProxyPlan, $udpConnectedPlan, $udpUnconnectedPlan, $issue209Plan)) {
    foreach ($flag in $unsupportedFlags) { Assert-True (@($plan.arguments) -notcontains $flag) "$($plan.executor) must not emit unsupported $flag" }
}
Assert-Equal 'single' $basePlan.arguments[1] 'base builder must use harness single mode'

$normalized34a = @(Get-CanonicalFixture 'stage34a-issue206-proxy-block')
Assert-Equal 2 $normalized34a.Count 'Stage 3.4A real-format JSONL must normalize two records'
Assert-Equal 0 $normalized34a[0].flow_index 'Stage 3.4A first flow index'
Assert-True $normalized34a[1].no_response 'Stage 3.4A no-echo pass must normalize no_response'
Assert-True ($null -ne $normalized34a[0].raw_record) 'canonical evidence must retain raw record'

$normalized34b = @(Get-CanonicalFixture 'stage34b-issue206-proxy-direct')
Assert-Equal 2 $normalized34b.Count 'Stage 3.4B real-format JSONL must normalize two records'
Assert-Equal 'DIRECT' $normalized34b[1].expected_action 'Stage 3.4B second action must normalize'
Assert-True $normalized34b[1].client_pass 'Stage 3.4B echo pass must normalize client_pass'

$normalized209 = @(Get-CanonicalFixture 'issue209-three-record')
Assert-Equal 3 $normalized209.Count 'issue209 real-format JSONL must normalize three records'
Assert-SequenceEqual @('first_flow','second_flow','held_recheck') @($normalized209.phase) 'issue209 phases must remain ordered'
Assert-Equal 'held_recheck' $normalized209[2].record_kind 'held recheck record kind must normalize explicitly'
Assert-Equal 0 $normalized209[2].flow_index 'held recheck must relate to first flow'

$temp = New-TestDirectory
try {
    $outputPath = Join-Path $temp 'client.jsonl'
    $fixtureLine = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/client-jsonl/stage34a-issue206-proxy-block.jsonl') -Encoding UTF8 | Select-Object -First 1
    Write-TestUtf8NoBom $outputPath $fixtureLine
    $filePlan = [pscustomobject]@{ executable='fixture-client.exe';arguments=@('--mode','single');timeout_ms=100;jsonl_path=$outputPath }
    $processResult = [pscustomobject]@{exit_code=0;timed_out=$false;pid=7;actual_path='fixture-client.exe';stdout='human stdout, not json';stderr='human stderr'}
    $result = Invoke-ClientPlan -Plan $filePlan -ProcessAdapter (New-MockProcessAdapter -InvokeResults @($processResult))
    Assert-Equal 1 @($result.raw_records).Count 'client must preserve raw JSONL records'
    Assert-Equal 1 @($result.canonical_records).Count 'client must return canonical JSONL records'
    Assert-Equal 'human stdout, not json' $result.stdout 'human stdout must be preserved separately'
    Assert-Equal 'human stderr' $result.stderr 'human stderr must be preserved separately'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }

'PASS: client contract'
