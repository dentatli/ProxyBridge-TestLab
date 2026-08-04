[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$CapabilitiesPath,
    [string]$SuitePath,
    [string]$KnownDefectsPath,
    [string]$ClientContractPath,
    [string]$ScenarioRoot,
    [string]$MockFixtureRoot,
    [string]$OutputRoot,
    [switch]$DryRun,
    [switch]$MockRuntime,
    [switch]$AllowProductRuntime,
    [switch]$ImportExistingVpsEvidence,
    [string[]]$Only = @(),
    [string]$ResumeFrom,
    [int]$MaxScenarios = 0,
    [switch]$ContinueOnProductFailure,
    [switch]$StopOnInfrastructureFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $DryRun -and -not $MockRuntime -and -not $AllowProductRuntime) { throw 'RUNTIME_NOT_IMPLEMENTED' }
$selectedModeCount = 0
foreach ($runtimeFlag in @($DryRun, $MockRuntime, $AllowProductRuntime)) { if ([bool]$runtimeFlag) { $selectedModeCount++ } }
if ($selectedModeCount -ne 1) { throw 'SELECT_EXACTLY_ONE_RUNTIME_MODE' }
$runMode = $(if ($DryRun) { 'dry-run' } elseif ($MockRuntime) { 'mock' } else { 'real' })

if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $PSScriptRoot '.env' }
if ([string]::IsNullOrWhiteSpace($CapabilitiesPath)) { $CapabilitiesPath = Join-Path $PSScriptRoot 'config/capabilities.json' }
if ([string]::IsNullOrWhiteSpace($SuitePath)) { $SuitePath = Join-Path $PSScriptRoot 'config/suites/correctness-ipv4.json' }
if ([string]::IsNullOrWhiteSpace($KnownDefectsPath)) { $KnownDefectsPath = Join-Path $PSScriptRoot 'config/known-defects.json' }
if ([string]::IsNullOrWhiteSpace($ClientContractPath)) { $ClientContractPath = Join-Path $PSScriptRoot 'config/client-contract.json' }
if ([string]::IsNullOrWhiteSpace($ScenarioRoot)) { $ScenarioRoot = Join-Path $PSScriptRoot 'scenarios' }
if ([string]::IsNullOrWhiteSpace($MockFixtureRoot)) { $MockFixtureRoot = Join-Path $PSScriptRoot 'tests/fixtures/mock' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $PSScriptRoot 'evidence' }

foreach ($module in @(
    'Env','Config','ScenarioCatalog','ProfileAdapter','ProfileValidator','RulePlan','ProcessAdapter','ClientRunner',
    'ProxyBridgeCli','HealthChecks','ProxyBridgeEvidence','VpsEvidence','Assertions','MockRuntime','Report'
)) { Import-Module (Join-Path $PSScriptRoot "modules/$module.psm1") -Force }

function New-ResultRecord {
    param($Scenario, [string]$Status, [string]$Reason, [int]$Attempt, [long]$DurationMs, [bool]$Selected, [string]$ProfileSha256='')
    return [pscustomobject][ordered]@{
        run_mode=$runMode; scenario_id=[string]$Scenario.scenario_id; coverage_group=[string]$Scenario.coverage_group
        implementation_status=[string]$Scenario.implementation_status; selected=$Selected; status=$Status; reason=$Reason
        attempt=$Attempt; duration_ms=$DurationMs; profile_sha256=$ProfileSha256; reset_policy=[string]$Scenario.reset_policy
    }
}

function Get-SafeExceptionMessage {
    param($ErrorRecord, $Environment)
    return Protect-SensitiveText -Text ([string]$ErrorRecord.Exception.Message) -Environment $Environment
}

try {
    $environment = Import-DotEnv -Path $EnvPath
    $capabilities = Import-CapabilitiesConfig -Path $CapabilitiesPath
    $suite = Import-SuiteConfig -Path $SuitePath
    $knownDefects = Import-KnownDefectsConfig -Path $KnownDefectsPath
    $clientContract = Import-ClientContract -Path $ClientContractPath
    $scenarios = @(Import-ScenarioCatalog -ScenarioRoot $ScenarioRoot)
    if ([string]$suite.execution.runtime_mode -ne $runMode) { throw "SUITE_RUNTIME_MODE_MISMATCH expected=$runMode configured=$($suite.execution.runtime_mode)" }
}
catch { throw "FAIL_CONFIGURATION: $($_.Exception.Message)" }

if ($ContinueOnProductFailure) { $suite.execution.continue_on_product_failure = $true }
if ($StopOnInfrastructureFailure) { $suite.execution.stop_on_infrastructure_failure = $true }
$report = New-RunReport -OutputRoot $OutputRoot
$environmentSummary = @(Get-EnvironmentSummary -Environment $environment)
Write-RedactedJsonReport -Value $environmentSummary -Path (Join-Path $report.run_root 'environment-snapshot.json') -Environment $environment
Write-RedactedJsonReport -Value $suite -Path (Join-Path $report.run_root 'resolved-suite.json') -Environment $environment
Write-SafeTranscript -Report $report -Environment $environment -Message "Run started in $runMode mode; catalog entries=$($scenarios.Count)."

$decisions = [System.Collections.Generic.List[object]]::new()
$resumeReached = [string]::IsNullOrWhiteSpace($ResumeFrom)
$selectedCount = 0
foreach ($scenario in $scenarios) {
    $decision = Test-ScenarioSelection -Scenario $scenario -Capabilities $capabilities -Suite $suite -KnownDefects $knownDefects -RunMode $runMode
    if ($decision.selected -and @($Only).Count -gt 0 -and @($Only) -notcontains [string]$scenario.scenario_id) { $decision = [pscustomobject]@{selected=$false;status='SKIPPED_SELECTION';reason='not selected by -Only';known_defect=$null} }
    if ($decision.selected -and -not $resumeReached) {
        if ([string]$scenario.scenario_id -eq $ResumeFrom) { $resumeReached = $true }
        else { $decision = [pscustomobject]@{selected=$false;status='SKIPPED_SELECTION';reason='before -ResumeFrom';known_defect=$null} }
    }
    if ($decision.selected -and $MaxScenarios -gt 0 -and $selectedCount -ge $MaxScenarios) { $decision = [pscustomobject]@{selected=$false;status='SKIPPED_SELECTION';reason='MaxScenarios limit';known_defect=$null} }
    if ($decision.selected) { $selectedCount++ }
    $decisions.Add([pscustomobject]@{scenario=$scenario;decision=$decision})
    Add-SelectionRecord -Report $report -Environment $environment -Record ([pscustomobject][ordered]@{
        run_mode=$runMode;scenario_id=$scenario.scenario_id;coverage_group=$scenario.coverage_group
        implementation_status=$scenario.implementation_status;selected=$decision.selected;status=$decision.status;reason=$decision.reason
    })
}
if (-not $resumeReached) { throw 'RESUME_SCENARIO_NOT_FOUND' }

$records = [System.Collections.Generic.List[object]]::new()
$profileFailures = 0
$consecutiveProductFailures = 0
$stopRun = $false
$suiteTimer = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($item in $decisions) {
    $scenario = $item.scenario
    $decision = $item.decision
    if (-not $decision.selected) {
        $record = New-ResultRecord -Scenario $scenario -Status $decision.status -Reason $decision.reason -Attempt 0 -DurationMs 0 -Selected $false
        $records.Add($record); Add-ResultRecord -Report $report -Record $record -Environment $environment
        continue
    }
    if ($stopRun -or $suiteTimer.ElapsedMilliseconds -ge [long]$suite.execution.suite_timeout_ms) {
        $reason = $(if ($stopRun) { 'run stopped by failure policy' } else { 'suite timeout reached' })
        $record = New-ResultRecord -Scenario $scenario -Status 'SKIPPED_SELECTION' -Reason $reason -Attempt 0 -DurationMs 0 -Selected $false
        $records.Add($record); Add-ResultRecord -Report $report -Record $record -Environment $environment
        continue
    }

    $scenarioEvidence = Join-Path $report.scenario_root ([string]$scenario.scenario_id)
    $null = New-Item -ItemType Directory -Path $scenarioEvidence -Force
    $resolvedScenario = $null
    $profileValidation = $null
    $profile = $null
    $writtenProfile = $null
    $clientPlan = $null
    try {
        $resolvedScenario = Resolve-JsonVariables -InputObject $scenario -Variables $environment
        $profileValidation = Test-ExpectedProfileValidation -Scenario $scenario -Environment $environment -TemplatePath (Join-Path $PSScriptRoot 'templates/profile.pbprofile.template')
        if (-not $profileValidation.passed) { throw "PROFILE_EXPECTATION_FAILED: $($profileValidation.errors -join ' | ')" }
        $profile = $profileValidation.profile
        if ($profileValidation.may_write) { $writtenProfile = Write-ResolvedProfile -Profile $profile -ScenarioId $scenario.scenario_id -OutputDirectory $report.profile_root }
        Write-RedactedJsonReport -Value ([pscustomobject]@{run_mode=$runMode;expectation=$profileValidation.expectation;passed=$profileValidation.passed;errors=@($profileValidation.errors);profile_written=($null -ne $writtenProfile)}) -Path (Join-Path $scenarioEvidence 'profile-validation.json') -Environment $environment
    }
    catch {
        $profileFailures++
        $safe = Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment
        Add-SelectionRecord -Report $report -Environment $environment -Record ([pscustomobject]@{run_mode=$runMode;scenario_id=$scenario.scenario_id;coverage_group=$scenario.coverage_group;implementation_status=$scenario.implementation_status;selected=$false;status='FAIL_PROFILE_GENERATION';reason=$safe})
        $record = New-ResultRecord -Scenario $scenario -Status 'FAIL_HARNESS' -Reason $safe -Attempt 0 -DurationMs 0 -Selected $true
        $records.Add($record); Add-ResultRecord -Report $report -Record $record -Environment $environment
        Write-SafeTranscript -Report $report -Environment $environment -Message "$($scenario.scenario_id): FAIL_PROFILE_GENERATION ($safe)."
        if ($suite.execution.stop_on_harness_failure) { $stopRun = $true }
        continue
    }

    try {
        $rulePlan = New-RulePlan -Scenario $resolvedScenario -Profile $profile
        $effectiveResetPolicy = [string]$suite.execution.reset_policy
        if ([string]::IsNullOrWhiteSpace($effectiveResetPolicy)) { $effectiveResetPolicy = [string]$resolvedScenario.reset_policy }
        $resetPlan = New-ResetPlan -Policy $effectiveResetPolicy
        if ($runMode -eq 'real' -and [bool]$resetPlan.manual_only) { throw "RESET_POLICY_MANUAL_ONLY: $effectiveResetPolicy" }
        $clientJsonlPath = Join-Path $scenarioEvidence 'client.jsonl'
        if ([string]$scenario.implementation_status -eq 'DECLARATIVE_ONLY') {
            $clientPlan = [pscustomobject][ordered]@{
                contract_id=[string]$clientContract.contract_id;executor='not-implemented';executable='';arguments=@()
                timeout_ms=[int]$suite.execution.timeout_ms;scenario_id=[string]$scenario.scenario_id
                run_id=$report.run_id;jsonl_path=$clientJsonlPath;flows=@()
                implementation_status='DECLARATIVE_ONLY';implementation_reason=[string]$scenario.implementation_reason
            }
        }
        else {
            $clientExecutable = $(if ($environment.ContainsKey('PB_CLIENT_EXE')) { $environment['PB_CLIENT_EXE'] } else { 'pb_net_client.exe' })
            $clientPlan = New-ClientPlan -Scenario $resolvedScenario -ExecutablePath $clientExecutable -RunId $report.run_id -JsonlPath $clientJsonlPath -Contract $clientContract
            $clientPlan.timeout_ms = [Math]::Min([int]$clientPlan.timeout_ms, [int]$suite.execution.timeout_ms)
        }
        Write-RedactedJsonReport -Value $rulePlan -Path (Join-Path $scenarioEvidence 'rule-plan.json') -Environment $environment
        Write-RedactedJsonReport -Value $resetPlan -Path (Join-Path $scenarioEvidence 'reset-plan.json') -Environment $environment
        Write-RedactedJsonReport -Value $clientPlan -Path (Join-Path $scenarioEvidence 'client-plan.json') -Environment $environment
    }
    catch {
        $safe = Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment
        $record = New-ResultRecord -Scenario $scenario -Status 'FAIL_HARNESS' -Reason "plan generation: $safe" -Attempt 0 -DurationMs 0 -Selected $true
        $records.Add($record); Add-ResultRecord -Report $report -Record $record -Environment $environment
        Write-SafeTranscript -Report $report -Environment $environment -Message "$($scenario.scenario_id): FAIL_HARNESS plan generation ($safe)."
        if ($suite.execution.stop_on_harness_failure) { $stopRun = $true }
        continue
    }

    $profileSha = $(if ($null -ne $writtenProfile) { [string]$writtenProfile.sha256 } else { '' })
    $attempts = $(if ($DryRun -or [string]$scenario.implementation_status -eq 'DECLARATIVE_ONLY' -or -not $profileValidation.may_write) { 1 } else { [Math]::Max([int]$scenario.repeats, [int]$suite.execution.repeats) })
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $attemptTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $status = ''
        $reason = ''
        if ($suiteTimer.ElapsedMilliseconds -ge [long]$suite.execution.suite_timeout_ms) { $status='SKIPPED_SELECTION';$reason='suite timeout reached' }
        elseif (-not $profileValidation.may_write) {
            $status = $(if ($DryRun) { 'DRY_RUN_READY' } elseif ($MockRuntime) { 'MOCK_PASS' } else { 'FAIL_HARNESS' })
            $reason = 'intentional invalid profile was rejected before product start'
        }
        elseif ([string]$scenario.implementation_status -eq 'DECLARATIVE_ONLY') {
            $status = $(if ($DryRun) { 'NOT_IMPLEMENTED' } else { 'MOCK_HOLD' })
            $reason = [string]$scenario.implementation_reason
        }
        elseif ($DryRun) {
            $status = 'DRY_RUN_READY'
            $reason = 'validated profile and exact command/reset plans are ready'
        }
        elseif ($MockRuntime) {
            try {
                $mock = Invoke-MockScenario -Scenario $resolvedScenario -ClientPlan $clientPlan -FixtureRoot $MockFixtureRoot -EvidenceDirectory $scenarioEvidence -Environment $environment
                Write-RedactedJsonReport -Value $mock.client_result -Path (Join-Path $scenarioEvidence 'client-result.json') -Environment $environment
                Write-RedactedJsonReport -Value $mock.proxybridge_records -Path (Join-Path $scenarioEvidence 'proxybridge-evidence.json') -Environment $environment
                Write-RedactedJsonReport -Value $mock.vps_records -Path (Join-Path $scenarioEvidence 'vps-evidence.json') -Environment $environment
                $assertion = Test-ScenarioAssertions -Scenario $resolvedScenario -ClientPlan $clientPlan -ClientResult $mock.client_result -VpsRecords $mock.vps_records -ProxyBridgeRecords $mock.proxybridge_records -EvidenceContext $mock.evidence_context -RunMode mock
                Write-RedactedJsonReport -Value $assertion -Path (Join-Path $scenarioEvidence 'assertions.json') -Environment $environment
                $status = Get-ClassifiedStatus -AssertionResult $assertion -KnownDefect $decision.known_defect -RunMode mock -MockExpectation ([string]$scenario.mock.expected_status)
                $reason = $(if ($assertion.passed) { 'fixture evidence satisfied orchestration contract' } else { @($assertion.errors) -join ', ' })
            }
            catch { $status='MOCK_HOLD';$reason="mock harness: $(Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment)" }
        }
        else {
            $healthResults = $null
            try {
                $healthResults = @(Invoke-HealthCheckPlan -Plan (New-HealthCheckPlan -Environment $environment) -Environment $environment -AllowProductRuntime)
                Write-RedactedJsonReport -Value $healthResults -Path (Join-Path $scenarioEvidence 'health-preflight.json') -Environment $environment
                $healthSummary = Test-HealthResults -Results $healthResults
                if (-not $healthSummary.passed) { $status='FAIL_INFRASTRUCTURE';$reason=@($healthSummary.failures.reason) -join ', ' }
            }
            catch { $status='FAIL_INFRASTRUCTURE';$reason=Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment }

            if ([string]::IsNullOrWhiteSpace($status)) {
                try {
                    $readyRegex = $(if ($environment.ContainsKey('PB_CLI_READY_REGEX')) { $environment['PB_CLI_READY_REGEX'] } else { '' })
                    $readyStableMs = $(if ($environment.ContainsKey('PB_CLI_READY_STABLE_MS')) { [int]$environment['PB_CLI_READY_STABLE_MS'] } else { 1000 })
                    $cliPlan = New-ProxyBridgeCliPlan -ExecutablePath $environment['PB_PROXYBRIDGE_CLI_EXE'] -ProfilePath $writtenProfile.path -ReadyRegex $readyRegex -ReadyStableMs $readyStableMs
                    Write-RedactedJsonReport -Value $cliPlan -Path (Join-Path $scenarioEvidence 'cli-plan.json') -Environment $environment
                    $clientAdapter = New-SystemProcessAdapter
                    $workload = { Invoke-ClientPlan -Plan $clientPlan -ProcessAdapter $clientAdapter -AllowProductRuntime }.GetNewClosure()
                    $sink = { param($evidence) Write-RedactedJsonReport -Value $evidence -Path (Join-Path $scenarioEvidence 'cli-lifecycle.json') -Environment $environment }.GetNewClosure()
                    $lifecycle = Invoke-ProxyBridgeCliLifecycle -Plan $cliPlan -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime -Workload $workload -EvidenceSink $sink
                    $clientResult = $lifecycle.workload_result
                    $lifecycleStart = [datetime]::Parse([string]$lifecycle.started_at_utc).ToUniversalTime()
                    $lifecycleEnd = [datetime]::Parse([string]$lifecycle.completed_at_utc).ToUniversalTime()
                    $proxyBridgeRecords = @(ConvertFrom-ProxyBridgeTextLines -Lines @(([string]$lifecycle.process_result.stdout) -split "`r?`n") -DefaultTimestampUtc $lifecycleStart)
                    $vpsCaptureComplete = $false
                    $vpsCompleteShas = @()
                    if ($ImportExistingVpsEvidence) {
                        if (-not $environment.ContainsKey('PB_VPS_EVIDENCE_IMPORT')) { throw 'VPS_EVIDENCE_IMPORT_NOT_CONFIGURED' }
                        $expectedShas = @($clientResult.canonical_records | ForEach-Object { [string]$_.payload_sha256 } | Sort-Object -Unique)
                        $vpsCollection = Invoke-VpsImportEvidencePlan -Plan (New-VpsEvidencePlan -ImportPath $environment['PB_VPS_EVIDENCE_IMPORT']) -ExpectedShas $expectedShas
                        $vpsRecords = @($vpsCollection.records)
                        $vpsCaptureComplete = [bool]$vpsCollection.capture_complete
                        $vpsCompleteShas = @($vpsCollection.complete_shas)
                    }
                    else {
                        $vpsPlan = New-VpsDynamicEvidencePlan -Environment $environment -CanonicalRecords @($clientResult.canonical_records) -EvidenceDirectory $scenarioEvidence
                        Write-RedactedJsonReport -Value $vpsPlan -Path (Join-Path $scenarioEvidence 'vps-collection-plan.json') -Environment $environment
                        $vpsCollection = Invoke-VpsDynamicEvidencePlan -Plan $vpsPlan -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime
                        $vpsRecords = @($vpsCollection.records)
                        $vpsCaptureComplete = [bool]$vpsCollection.capture_complete
                        $vpsCompleteShas = @($vpsCollection.complete_shas)
                    }
                    Write-RedactedJsonReport -Value $vpsCollection.query_results -Path (Join-Path $scenarioEvidence 'vps-collection-result.json') -Environment $environment
                    if (-not $vpsCaptureComplete) { throw 'VPS_SSH_COLLECTION_INCOMPLETE' }
                    Write-RedactedJsonReport -Value $clientResult -Path (Join-Path $scenarioEvidence 'client-result.json') -Environment $environment
                    Write-RedactedJsonReport -Value $proxyBridgeRecords -Path (Join-Path $scenarioEvidence 'proxybridge-evidence.json') -Environment $environment
                    Write-RedactedJsonReport -Value $vpsRecords -Path (Join-Path $scenarioEvidence 'vps-evidence.json') -Environment $environment
                    $context = [pscustomobject]@{
                        vps_capture_complete=$vpsCaptureComplete;vps_capture_complete_shas=$vpsCompleteShas;proxybridge_capture_complete=$true
                        direct_egress_ip=$(if ($environment.ContainsKey('PB_DIRECT_EGRESS_IPV4')){$environment['PB_DIRECT_EGRESS_IPV4']}else{''})
                        proxy_egress_ip=$(if ($environment.ContainsKey('PB_PROXY_EGRESS_IPV4')){$environment['PB_PROXY_EGRESS_IPV4']}else{''})
                        expected_process=[System.IO.Path]::GetFileName($environment['PB_CLIENT_EXE'])
                        start_time_utc=$lifecycleStart;end_time_utc=$lifecycleEnd
                    }
                    $assertion = Test-ScenarioAssertions -Scenario $resolvedScenario -ClientPlan $clientPlan -ClientResult $clientResult -VpsRecords $vpsRecords -ProxyBridgeRecords $proxyBridgeRecords -EvidenceContext $context -RunMode real
                    Write-RedactedJsonReport -Value $assertion -Path (Join-Path $scenarioEvidence 'assertions.json') -Environment $environment
                    $status = Get-ClassifiedStatus -AssertionResult $assertion -KnownDefect $decision.known_defect -RunMode real
                    $reason = $(if ($assertion.passed) { 'real client, ProxyBridge and VPS evidence passed' } else { @($assertion.errors) -join ', ' })
                    if ($status -eq 'FAIL_PRODUCT') {
                        $postHealth = @(Invoke-HealthCheckPlan -Plan (New-HealthCheckPlan -Environment $environment) -Environment $environment -AllowProductRuntime)
                        Write-RedactedJsonReport -Value $postHealth -Path (Join-Path $scenarioEvidence 'health-post-failure.json') -Environment $environment
                        if (-not (Test-HealthResults -Results $postHealth).passed -or -not $lifecycle.post_stop_verified) { $status='CONTAMINATED';$reason='post-failure state is not clean' }
                    }
                }
                catch {
                    $safe = Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment
                    if ($safe -match 'CLI_CLEANUP_FAILED|POST_STOP_VERIFICATION') { $status='CONTAMINATED' }
                    elseif ($safe -match 'READINESS|PATH_VERIFICATION|START_FAILED|PROCESS_START') { $status='FAIL_INFRASTRUCTURE' }
                    elseif ($safe -match 'VPS_SSH_(COLLECTION_INCOMPLETE|TIMEOUT|FAILED|PROCESS_FAILED|HOST_INVALID|USER_INVALID|PORT_INVALID|EXECUTABLE_MISSING)|VPS_ENVIRONMENT_MISSING_') { $status='FAIL_INFRASTRUCTURE' }
                    elseif ($safe -match 'VPS_EVIDENCE_IMPORT_NOT_CONFIGURED|VPS_EVIDENCE_IMPORT_NOT_FOUND') { $status='HOLD_AMBIGUOUS' }
                    else { $status='FAIL_HARNESS' }
                    $reason=$safe
                }
            }
        }

        $attemptTimer.Stop()
        $record = New-ResultRecord -Scenario $scenario -Status $status -Reason $reason -Attempt $attempt -DurationMs $attemptTimer.ElapsedMilliseconds -Selected $true -ProfileSha256 $profileSha
        $records.Add($record); Add-ResultRecord -Report $report -Record $record -Environment $environment
        if ($runMode -eq 'real' -and $status -eq 'FAIL_PRODUCT') { $consecutiveProductFailures++ }
        elseif ($runMode -eq 'real') { $consecutiveProductFailures = 0 }
        if ($runMode -eq 'real' -and (Test-ShouldStopRun -Status $status -Suite $suite -ConsecutiveProductFailures $consecutiveProductFailures -Independent $scenario.independent)) { $stopRun=$true;break }
    }
}

$suiteTimer.Stop()
Write-RunSummary -Report $report -Records $records.ToArray() -AllScenarios $scenarios -Environment $environment -RunMode $runMode
Write-SafeTranscript -Report $report -Environment $environment -Message "Run completed; selected=$selectedCount; profile_failures=$profileFailures; mode=$runMode."
Complete-RunChecksums -Report $report
if ($profileFailures -gt 0) { throw "FAIL_PROFILE_GENERATION_COUNT=$profileFailures" }
"RUN_COMPLETE mode=$runMode run_id=$($report.run_id) scenarios=$($scenarios.Count) selected=$selectedCount"
