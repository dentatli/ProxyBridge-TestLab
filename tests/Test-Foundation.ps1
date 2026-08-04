[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
Import-Module (Join-Path $repoRoot 'modules/Env.psm1') -Force
Import-Module (Join-Path $repoRoot 'modules/Config.psm1') -Force
Import-Module (Join-Path $repoRoot 'modules/ScenarioCatalog.psm1') -Force
Import-Module (Join-Path $repoRoot 'modules/ProfileAdapter.psm1') -Force
Import-Module (Join-Path $repoRoot 'modules/Report.psm1') -Force

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Assert-Equal {
    param($Expected, $Actual, [Parameter(Mandatory)][string]$Message)
    if ($Expected -ne $Actual) { throw "ASSERTION FAILED: $Message" }
}

function Assert-NoUtf8Bom {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Message)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True (-not $hasBom) $Message
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('proxybridge-foundation-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporaryRoot

try {
    foreach ($rootDuplicate in @(
        'Config.psm1', 'Env.psm1', 'ProfileAdapter.psm1', 'Report.psm1',
        'Test-Foundation.ps1', 'capabilities.test.json', 'scenario.test.json', 'suite.test.json'
    )) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $repoRoot $rootDuplicate))) "root duplicate '$rootDuplicate' must be absent"
    }

    $expectedExampleKeys = @(
        'PB_VM_IPV4','PB_VM_IPV6','PB_VPS_IPV4','PB_VPS_IPV6','PB_ENDPOINT_A_PORT','PB_ENDPOINT_B_PORT',
        'PB_SOCKS_HOST','PB_SOCKS_PORT','PB_SOCKS_PROXY_CONFIG_ID','PB_CLIENT_EXE','PB_PROXYBRIDGE_EXE','PB_PROXYBRIDGE_CLI_EXE',
        'PB_DRIVER_PATH','PB_PROXYBRIDGE_SERVICE','PB_EVIDENCE_ROOT','PB_EXPECTED_CLIENT_SHA256','PB_EXPECTED_PROXYBRIDGE_CLI_SHA256',
        'PB_EXPECTED_PROXYBRIDGE_EXE_SHA256','PB_EXPECTED_DRIVER_SHA256','PB_SSH_HOST','PB_SSH_USER','PB_SSH_PORT','PB_SSH_KEY','PB_VPS_SERVER_LOG'
    )
    $examplePath = Join-Path $repoRoot '.env.example'
    $exampleKeys = @(
        foreach ($line in [System.IO.File]::ReadAllLines($examplePath)) {
            if ($line -match '^\s*#?\s*(PB_[A-Z0-9_]+)=') { [string]$Matches[1] }
        }
    )
    Assert-Equal $expectedExampleKeys.Count $exampleKeys.Count '.env.example key count must be exact'
    for ($keyIndex=0; $keyIndex -lt $expectedExampleKeys.Count; $keyIndex++) { Assert-Equal $expectedExampleKeys[$keyIndex] $exampleKeys[$keyIndex] ".env.example key order index=$keyIndex" }
    foreach ($removedKey in @('PB_ENDPOINT_DELAY_PORT','PB_ENDPOINT_ERROR_PORT','PB_RULE_PORT_RANGE','PB_TEST_DOMAIN','PB_VPS_EVIDENCE_IMPORT','PB_RULE_APPLICATION_BASENAME','PB_RULE_APPLICATION_FULLPATH','PB_CLI_READY_REGEX','PB_CLI_READY_STABLE_MS','PB_DIRECT_EGRESS_IPV4','PB_PROXY_EGRESS_IPV4')) {
        Assert-True ($exampleKeys -notcontains $removedKey) "removed example key '$removedKey' must be absent"
    }
    Assert-NoUtf8Bom -Path $examplePath -Message '.env.example must be UTF-8 without BOM'

    $environment = Import-DotEnv -Path (Join-Path $fixtureRoot '.env.test')
    Assert-True (-not $environment.ContainsKey('PB_VPS_EVIDENCE_IMPORT')) 'fixture environment must not provide VPS import path'
    Assert-Equal 'C:\Users\Fixture\.ssh\id_ed25519' $environment['PB_SSH_KEY'] 'Windows backslashes must be preserved'
    Assert-Equal 'left=middle=right' $environment['PB_VALUE_WITH_EQUALS'] 'values may contain additional equals signs'
    $runtimeConfig = Import-RuntimeConfig (Join-Path $repoRoot 'config/runtime.json')
    $environment = Get-EffectiveRuntimeEnvironment -Environment $environment -RuntimeConfig $runtimeConfig
    Assert-Equal 'pb_net_client.exe' $environment['PB_RULE_APPLICATION_BASENAME'] 'rule basename must derive from PB_CLIENT_EXE'
    Assert-Equal 'C:\Fixture\bin\pb_net_client.exe' $environment['PB_RULE_APPLICATION_FULLPATH'] 'rule full path must derive from normalized PB_CLIENT_EXE'
    Assert-Equal '' ([string]$runtimeConfig.cli_readiness.regex) 'beta CLI readiness regex default must be empty'
    Assert-Equal 2000 ([int]$runtimeConfig.cli_readiness.stable_ms) 'beta CLI stable readiness default'
    Assert-Equal 15000 ([int]$runtimeConfig.cli_readiness.readiness_timeout_ms) 'beta CLI readiness timeout default'
    Assert-Equal 5000 ([int]$runtimeConfig.cli_readiness.stop_timeout_ms) 'beta CLI stop timeout default'

    $duplicatePath = Join-Path $temporaryRoot 'duplicate.env'
    [System.IO.File]::WriteAllText($duplicatePath, "DUPLICATE=one`nDUPLICATE=two`n")
    $duplicateRejected = $false
    try { $null = Import-DotEnv -Path $duplicatePath } catch { $duplicateRejected = $_.Exception.Message -match 'Duplicate' }
    Assert-True $duplicateRejected 'duplicate environment keys must be rejected'

    $capabilities = Import-CapabilitiesConfig -Path (Join-Path $fixtureRoot 'capabilities.test.json')
    $suite = Import-SuiteConfig -Path (Join-Path $fixtureRoot 'suite.test.json')
    $scenario = Get-Content -LiteralPath (Join-Path $fixtureRoot 'scenario.test.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    $ipv6Scenario = $scenario | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $ipv6Scenario.requires = @('ipv6')
    $decision = Test-ScenarioSelection -Scenario $ipv6Scenario -Capabilities $capabilities -Suite $suite
    Assert-Equal 'SKIPPED_CAPABILITY' $decision.status 'disabled IPv6 must cause capability skip'

    $decision = Test-ScenarioSelection -Scenario $scenario -Capabilities $capabilities -Suite $suite
    Assert-True $decision.selected 'matching include tags must select the scenario'
    $excludedScenario = $scenario | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $excludedScenario.tags = @($excludedScenario.tags) + 'excluded'
    $decision = Test-ScenarioSelection -Scenario $excludedScenario -Capabilities $capabilities -Suite $suite
    Assert-Equal 'SKIPPED_SELECTION' $decision.status 'exclude tag must skip the scenario'

    $profile = New-ResolvedProfile -Scenario $scenario -Environment $environment -TemplatePath (Join-Path $repoRoot 'templates/profile.pbprofile.template')
    Assert-True (($profile | ConvertTo-Json -Depth 100 -Compress) -notmatch '\$\{') 'generated profile must not contain unresolved placeholders'
    Assert-True ($profile.ProxyConfigs[0].Port -is [string]) 'ProxyConfigs[].Port must be string'
    Assert-True ($profile.ProxyRules[0].TargetPorts -is [string]) 'ProxyRules[].TargetPorts must be string'
    Assert-True ($profile.ProxyRules[0].ProxyConfigId -is [int]) 'ProxyConfigId must be integer'
    Assert-True ($profile.ProxyRules[0].IsEnabled -is [bool]) 'IsEnabled must be boolean'

    $unresolvedRejected = $false
    $unresolvedObject = [pscustomobject]@{
        nested = @([pscustomobject]@{ value = '${PB_EXPLICITLY_MISSING}' })
    }
    try {
        $null = Resolve-JsonVariables -InputObject $unresolvedObject -Variables $environment
    }
    catch {
        $unresolvedRejected = $_.Exception.Message -match 'Unresolved placeholders: PB_EXPLICITLY_MISSING'
    }
    Assert-True $unresolvedRejected 'explicit unresolved placeholder must be rejected'

    $scenarioRoot = Join-Path $temporaryRoot 'scenarios'
    $outputRoot = Join-Path $temporaryRoot 'output'
    $null = New-Item -ItemType Directory -Path $scenarioRoot
    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'scenario.test.json') -Destination $scenarioRoot
    $redactionScenario = $scenario | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $redactionScenario.scenario_id = 'redaction-capability-test'
    $redactionScenario.requires = @('ipv6')
    [System.IO.File]::WriteAllText(
        (Join-Path $scenarioRoot 'redaction-capability-test.json'),
        ($redactionScenario | ConvertTo-Json -Depth 100) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    $runnerOutput = & (Join-Path $repoRoot 'Run-WfpMatrix.ps1') `
        -EnvPath (Join-Path $fixtureRoot '.env.test') `
        -CapabilitiesPath (Join-Path $fixtureRoot 'capabilities.test.json') `
        -SuitePath (Join-Path $fixtureRoot 'suite.test.json') `
        -ScenarioRoot $scenarioRoot `
        -OutputRoot $outputRoot `
        -DryRun 2>&1 | Out-String
    Assert-True ($runnerOutput -match 'RUN_COMPLETE mode=dry-run') 'dry-run runner must complete'
    Assert-True ($runnerOutput -notmatch 'fixture-secret') 'runner output must not expose fixture secret'

    $runRoot = @(Get-ChildItem -LiteralPath $outputRoot -Directory)
    Assert-Equal 1 $runRoot.Count 'dry-run must create exactly one run directory'
    $transcriptPath = Join-Path $runRoot[0].FullName 'transcript.txt'
    $selectionPath = Join-Path $runRoot[0].FullName 'selection.jsonl'
    $testReport = [pscustomobject]@{ transcript_path = $transcriptPath }
    Write-SafeTranscript -Report $testReport -Environment $environment -Message 'Harmless scalar ProxyConfigId=1 remains visible.'
    $transcript = Get-Content -LiteralPath $transcriptPath -Raw -Encoding UTF8
    $selectionJsonl = Get-Content -LiteralPath $selectionPath -Raw -Encoding UTF8
    $environmentSummary = Get-Content -LiteralPath (Join-Path $runRoot[0].FullName 'environment-snapshot.json') -Raw -Encoding UTF8
    foreach ($protectedValue in @(
        'fixture-secret',
        'C:\Users\Fixture\.ssh\id_ed25519',
        '192.0.2.20',
        '198.51.100.10',
        '192.0.2.30'
    )) {
        Assert-True (-not $transcript.Contains($protectedValue)) "transcript must redact protected environment value"
        Assert-True (-not $selectionJsonl.Contains($protectedValue)) "selection JSONL must redact protected environment value"
    }
    Assert-True ($selectionJsonl -match '\[REDACTED\]') 'selection JSONL must apply redaction'
    foreach ($line in @(Get-Content -LiteralPath $selectionPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) { $null = $line | ConvertFrom-Json }
    Assert-True ($transcript -match 'ProxyConfigId=1') 'harmless short scalar must not be globally redacted'
    Assert-True ($environmentSummary -notmatch 'fixture-secret') 'environment summary must not expose fixture secret'
    Assert-NoUtf8Bom -Path $transcriptPath -Message 'transcript must be UTF-8 without BOM'
    Assert-NoUtf8Bom -Path $selectionPath -Message 'selection JSONL must be UTF-8 without BOM'
    Assert-True (Test-Path -LiteralPath (Join-Path $runRoot[0].FullName 'generated-profiles/foundation-profile-test.pbprofile')) 'resolved profile must be generated'
    foreach ($requiredOutput in @('environment-snapshot.json', 'resolved-suite.json', 'selection.jsonl', 'results.jsonl', 'failures.jsonl', 'skipped.jsonl', 'summary.csv', 'coverage.json', 'SHA256SUMS', 'transcript.txt')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $runRoot[0].FullName $requiredOutput)) "required output '$requiredOutput' must exist"
    }
    foreach ($jsonFile in @(Get-ChildItem -LiteralPath $runRoot[0].FullName -Recurse -File -Filter '*.json')) { $null = Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
    foreach ($jsonlFile in @(Get-ChildItem -LiteralPath $runRoot[0].FullName -Recurse -File -Filter '*.jsonl')) { foreach ($line in @(Get-Content -LiteralPath $jsonlFile.FullName -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) { $null = $line | ConvertFrom-Json } }

    $failureScenarioRoot = Join-Path $temporaryRoot 'failure-scenarios'
    $failureOutputRoot = Join-Path $temporaryRoot 'failure-output'
    $null = New-Item -ItemType Directory -Path $failureScenarioRoot
    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'scenario.test.json') -Destination (Join-Path $failureScenarioRoot 'valid-profile.json')
    $invalidScenario = $scenario | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $invalidScenario.scenario_id = 'invalid-profile-test'
    $invalidScenario.rule_set[0].host = '${PB_INVALID_PROFILE_VALUE}'
    [System.IO.File]::WriteAllText(
        (Join-Path $failureScenarioRoot 'invalid-profile.json'),
        ($invalidScenario | ConvertTo-Json -Depth 100) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )

    $failureStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $failureStartInfo.FileName = Join-Path $PSHOME 'powershell.exe'
    $failureStartInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -EnvPath "{1}" -CapabilitiesPath "{2}" -SuitePath "{3}" -ScenarioRoot "{4}" -OutputRoot "{5}" -DryRun' -f @(
        (Join-Path $repoRoot 'Run-WfpMatrix.ps1'),
        (Join-Path $fixtureRoot '.env.test'),
        (Join-Path $fixtureRoot 'capabilities.test.json'),
        (Join-Path $fixtureRoot 'suite.test.json'),
        $failureScenarioRoot,
        $failureOutputRoot
    )
    $failureStartInfo.UseShellExecute = $false
    $failureStartInfo.RedirectStandardOutput = $true
    $failureStartInfo.RedirectStandardError = $true
    $failureProcess = [System.Diagnostics.Process]::new()
    $failureProcess.StartInfo = $failureStartInfo
    try {
        $null = $failureProcess.Start()
        $failureStandardOutput = $failureProcess.StandardOutput.ReadToEnd()
        $failureStandardError = $failureProcess.StandardError.ReadToEnd()
        $failureProcess.WaitForExit()
        $failureExitCode = $failureProcess.ExitCode
        $failureRunnerOutput = $failureStandardOutput + [Environment]::NewLine + $failureStandardError
    }
    finally {
        $failureProcess.Dispose()
    }
    Assert-True ($failureExitCode -ne 0) 'invalid profile generation must return nonzero exit code'
    Assert-True ($failureRunnerOutput -match 'FAIL_PROFILE_GENERATION_COUNT=1') 'runner must report the profile failure count'

    $failureRunRoot = @(Get-ChildItem -LiteralPath $failureOutputRoot -Directory)
    Assert-Equal 1 $failureRunRoot.Count 'failed dry-run must preserve one evidence directory'
    foreach ($requiredFailureOutput in @('selection.jsonl', 'SHA256SUMS', 'transcript.txt')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $failureRunRoot[0].FullName $requiredFailureOutput)) "failed dry-run must finish '$requiredFailureOutput'"
    }
    $failureSelection = @(Get-Content -LiteralPath (Join-Path $failureRunRoot[0].FullName 'selection.jsonl') -Encoding UTF8)
    Assert-True ($failureSelection.Count -ge 2) 'failed dry-run must record every scenario'
    Assert-True (($failureSelection -join "`n") -match 'SELECTED') 'selection must retain successful scenario record'
    Assert-True (($failureSelection -join "`n") -match 'FAIL_PROFILE_GENERATION') 'selection must record invalid profile scenario'
    $failureTranscript = Get-Content -LiteralPath (Join-Path $failureRunRoot[0].FullName 'transcript.txt') -Raw -Encoding UTF8
    Assert-True ($failureTranscript -match 'Run completed; selected=2; profile_failures=1') 'failed dry-run must finalize transcript before throwing'

    $runtimeRejected = $false
    try { $null = & (Join-Path $repoRoot 'Run-WfpMatrix.ps1') } catch { $runtimeRejected = $_.Exception.Message -match 'RUNTIME_NOT_IMPLEMENTED' }
    Assert-True $runtimeRejected 'runner without DryRun must reject runtime execution'

    $realSmokeRejected = $false
    try { $null = & (Join-Path $repoRoot 'scripts/Invoke-RealSmoke.ps1') -ConfirmRealRuntime:$false } catch { $realSmokeRejected = $_.Exception.Message -match 'REAL_RUNTIME_CONFIRMATION_REQUIRED' }
    Assert-True $realSmokeRejected 'real smoke must remain explicitly confirmation-gated'

    $runnerSource = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'Run-WfpMatrix.ps1'))
    $realSmokeSource = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/Invoke-RealSmoke.ps1'))
    Assert-True ($runnerSource -match '\[string\]\$VpsEvidenceImportPath') 'VPS evidence import must be an explicit runner parameter'
    Assert-True ($runnerSource -notmatch 'PB_VPS_EVIDENCE_IMPORT') 'runner must not read VPS import path from environment'
    Assert-True ($realSmokeSource -match 'SkipEnvironmentPreparation') 'real smoke must expose only explicit preparation opt-out'
    $runtimeSources = @((Join-Path $repoRoot 'Run-WfpMatrix.ps1'), (Join-Path $repoRoot 'scripts/Invoke-RealSmoke.ps1')) + @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'modules') -File -Filter '*.psm1' | Select-Object -ExpandProperty FullName)
    $forbiddenMutationPattern = '(?im)\b(New-Service|Remove-Service|Set-Service|Start-Service|Stop-Service|New-NetFirewallRule|Set-NetFirewallRule|Remove-NetFirewallRule|netsh|pnputil|signtool)(?:\.exe)?\b|\bsc(?:\.exe)?\s+(create|delete|start|stop)\b'
    foreach ($sourcePath in $runtimeSources) { Assert-True (-not ([System.IO.File]::ReadAllText($sourcePath) -match $forbiddenMutationPattern)) "forbidden machine mutation call in $(Split-Path -Leaf $sourcePath)" }

    'PASS: Stage 3.1E-1 foundation'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
