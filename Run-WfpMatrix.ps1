[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$CapabilitiesPath,
    [string]$SuitePath,
    [string]$KnownDefectsPath,
    [string]$ClientContractPath,
    [string]$RuntimeConfigPath,
    [ValidateSet('driver','v4.0.0')][string]$ProductProfileContract = 'driver',
    [ValidateSet('','driver','v4.0.0')][string]$ReferenceProfileContract = '',
    [ValidateSet('configured','ip')][string]$ProxyDestinationMode = 'configured',
    [string]$ScenarioRoot,
    [string]$MockFixtureRoot,
    [string]$OutputRoot,
    [string]$CancellationPath,
    [switch]$DryRun,
    [switch]$MockRuntime,
    [switch]$AllowProductRuntime,
    [switch]$PrepareRuntimeEnvironment,
    [switch]$PreflightOnly,
    [string]$VpsEvidenceImportPath,
    [string]$ExpectedDirectEgressIpv4,
    [string]$ExpectedProxyEgressIpv4,
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
# The existing service/driver preparation is WFP-specific. A legacy profile
# serializer must not implicitly authorize running the WinDivert product.
if ($ProductProfileContract -ne 'driver' -and -not $DryRun) { throw 'PRODUCT_PROFILE_CONTRACT_PLANNING_ONLY: v4.0.0 requires -DryRun until its runtime lifecycle is implemented.' }

if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $PSScriptRoot '.env' }
if ([string]::IsNullOrWhiteSpace($CapabilitiesPath)) { $CapabilitiesPath = Join-Path $PSScriptRoot 'config/capabilities.json' }
if ([string]::IsNullOrWhiteSpace($SuitePath)) { $SuitePath = Join-Path $PSScriptRoot 'config/suites/correctness-ipv4.json' }
if ([string]::IsNullOrWhiteSpace($KnownDefectsPath)) { $KnownDefectsPath = Join-Path $PSScriptRoot 'config/known-defects.json' }
if ([string]::IsNullOrWhiteSpace($ClientContractPath)) { $ClientContractPath = Join-Path $PSScriptRoot 'config/client-contract.json' }
if ([string]::IsNullOrWhiteSpace($RuntimeConfigPath)) { $RuntimeConfigPath = Join-Path $PSScriptRoot 'config/runtime.json' }
if ([string]::IsNullOrWhiteSpace($ScenarioRoot)) { $ScenarioRoot = Join-Path $PSScriptRoot 'scenarios' }
if ([string]::IsNullOrWhiteSpace($MockFixtureRoot)) { $MockFixtureRoot = Join-Path $PSScriptRoot 'tests/fixtures/mock' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $PSScriptRoot 'evidence' }

foreach ($module in @(
    'Env','Config','ScenarioCatalog','ProfileAdapter','ProfileValidator','ProductProfile','ProductBuild','RulePlan','ProcessAdapter','ClientRunner','ProtocolWorker','ProtocolRunner',
    'ProxyBridgeCli','HealthChecks','RuntimeEnvironment','InterceptionState','DirectBaseline','ProxyBridgeEvidence','VpsEvidence','Assertions','MockRuntime','Report'
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

$report = New-RunReport -OutputRoot $OutputRoot
$environment = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
try {
    $rawEnvironment = Import-DotEnv -Path $EnvPath
    $runtimeConfig = Import-RuntimeConfig -Path $RuntimeConfigPath
    if ($runMode -ne 'real') {
        $protocolPorts = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config/server-protocol-ports.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($pair in @(
            @('PB_PROTOCOL_DNS_PORT','dns'),@('PB_PROTOCOL_HTTP_PORT','http'),@('PB_PROTOCOL_TLS_PORT','tls'),@('PB_PROTOCOL_HTTPS_PORT','https')
        )) { if (-not $rawEnvironment.ContainsKey($pair[0])) { $rawEnvironment[$pair[0]] = [string]$protocolPorts.ports.($pair[1]) } }
        $planningArtifacts = @{
            PB_PROTOCOL_PYTHON_EXE=(Join-Path $PSScriptRoot 'bin/protocol-worker/runtime/python/python.exe')
            PB_PROTOCOL_WORKER_ENTRYPOINT=(Join-Path $PSScriptRoot 'src/protocol_worker/pb_protocol_worker.py')
            PB_PROTOCOL_WORKER_MANIFEST=(Join-Path $PSScriptRoot 'src/protocol_worker/plugins/manifest.json')
            PB_PROTOCOL_EVIDENCE_CONTRACT=(Join-Path $PSScriptRoot 'config/protocol-evidence-contract.json')
            PB_PROTOCOL_CA_PEM=(Join-Path $PSScriptRoot 'config/protocol-ca-placeholder.pem')
        }
        foreach ($item in $planningArtifacts.GetEnumerator()) { if (-not $rawEnvironment.ContainsKey($item.Key)) { $rawEnvironment[$item.Key] = [string]$item.Value } }
        foreach ($name in @('PB_EXPECTED_PROTOCOL_PYTHON_SHA256','PB_EXPECTED_PROTOCOL_WORKER_SHA256','PB_EXPECTED_PROTOCOL_MANIFEST_SHA256','PB_EXPECTED_PROTOCOL_EVIDENCE_CONTRACT_SHA256','PB_EXPECTED_PROTOCOL_CA_SHA256')) {
            if (-not $rawEnvironment.ContainsKey($name)) { $rawEnvironment[$name] = ('0' * 64) -join '' }
        }
    }
    $environment = $rawEnvironment
    $environment = Get-EffectiveRuntimeEnvironment -Environment $rawEnvironment -RuntimeConfig $runtimeConfig
    $capabilities = Import-CapabilitiesConfig -Path $CapabilitiesPath
    $suite = Import-SuiteConfig -Path $SuitePath
    $knownDefects = Import-KnownDefectsConfig -Path $KnownDefectsPath
    $clientContract = Import-ClientContract -Path $ClientContractPath
    $protocolRuntimeContracts = Import-ProtocolWorkerRuntimeContract -RuntimeContractPath (Join-Path $PSScriptRoot 'config/protocol-worker-runtime.json') -PluginManifestPath $environment['PB_PROTOCOL_WORKER_MANIFEST']
    $scenarios = @(Import-ScenarioCatalog -ScenarioRoot $ScenarioRoot)
    if ([string]$suite.execution.runtime_mode -ne $runMode) { throw "SUITE_RUNTIME_MODE_MISMATCH expected=$runMode configured=$($suite.execution.runtime_mode)" }
}
catch {
    $safeConfigurationError = Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment
    Write-RedactedJsonReport -Value ([pscustomobject]@{status='FAIL_CONFIGURATION';reason=$safeConfigurationError;remediation='Correct the public/private configuration before runtime.'}) -Path (Join-Path $report.run_root 'configuration-error.json') -Environment $environment
    Write-SafeTranscript -Report $report -Environment $environment -Message "Configuration failed: $safeConfigurationError."
    Complete-RunChecksums -Report $report
    Write-Output "RUN_COMPLETE mode=$runMode run_id=$($report.run_id) scenarios=0 selected=0 status=FAIL_CONFIGURATION"
    Write-Output "EVIDENCE_PATH=$($report.run_root)"
    throw "FAIL_CONFIGURATION: $safeConfigurationError"
}

if ($ContinueOnProductFailure) { $suite.execution.continue_on_product_failure = $true }
if ($StopOnInfrastructureFailure) { $suite.execution.stop_on_infrastructure_failure = $true }
$runtimeEnvironmentPlan = $null
$runtimeEnvironmentAdapter = $null
$directBaseline = $null
$environmentSummary = @(Get-EnvironmentSummary -Environment $environment)
Write-RedactedJsonReport -Value $environmentSummary -Path (Join-Path $report.run_root 'environment-snapshot.json') -Environment $environment
Write-RedactedJsonReport -Value $suite -Path (Join-Path $report.run_root 'resolved-suite.json') -Environment $environment
Write-SafeTranscript -Report $report -Environment $environment -Message "Run started in $runMode mode; catalog entries=$($scenarios.Count)."

function Stop-RunBeforeScenarios {
    param([string]$Status, [string]$Reason)
    Write-SafeTranscript -Report $report -Environment $environment -Message "Run stopped before scenarios; status=$Status; reason=$Reason."
    Write-RunSummary -Report $report -Records @() -AllScenarios $scenarios -Environment $environment -RunMode $runMode -ExecutionComplete $false
    Complete-RunChecksums -Report $report
    Write-Output "RUN_COMPLETE mode=$runMode run_id=$($report.run_id) scenarios=$($scenarios.Count) selected=$selectedCount status=$Status"
    Write-Output "EVIDENCE_PATH=$($report.run_root)"
    throw "$Status`: $Reason"
}

function Save-InterceptionObservation {
    param([Parameter(Mandatory)][string]$Path)
    try { $snapshot = Get-InterceptionStateSnapshot -Environment $rawEnvironment -AllowProductRuntime }
    catch {
        $snapshot = [pscustomobject]@{status='BLOCKED';current_driver_preparation_allowed=$false;blocking_reasons=@('INTERCEPTION_OBSERVATION_FAILED');interception_cleanup_verified=$false;version_switch_ready=$false}
    }
    Write-RedactedJsonReport -Value $snapshot -Path $Path -Environment $buildReportEnvironment
    return $snapshot
}

$initializeRealRuntime = {
if ($runMode -eq 'real') {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'bin/pb_console_host.exe') -PathType Leaf)) {
        Stop-RunBeforeScenarios -Status 'FAIL_CONFIGURATION' -Reason 'CONSOLE_HOST_MISSING: run scripts/Build-ConsoleHost.ps1 before runtime.'
    }
    # Capture the core DLL as well as the executables before any preparation
    # can start the GUI or modify the product's process state.
    try { $productBuild = Get-ProductBuildIdentity -Environment $rawEnvironment -Contract $ProductProfileContract }
    catch {
        $productBuild = [pscustomobject]@{status='FILES_NOT_VERIFIED';files_verified=$false;reason=(Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment)}
    }
    # These public technical identifiers belong in the audit report. Keep all
    # other environment values (including credentials and paths) redacted.
    $buildReportEnvironment = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $environment.Keys) {
        $publicHash = $key -match '^PB_EXPECTED_(PROXYBRIDGE_(CLI|EXE|CORE)|DRIVER|WINDIVERT_(DLL|DRIVER|CTL|OBSERVER_DLL))_SHA256$' -and $environment[$key] -match '^[a-fA-F0-9]{64}$'
        $publicCommit = $key -eq 'PB_PROXYBRIDGE_SOURCE_COMMIT' -and $environment[$key] -match '^[a-fA-F0-9]{40}$'
        if (-not $publicHash -and -not $publicCommit) { $buildReportEnvironment[$key] = $environment[$key] }
    }
    Write-RedactedJsonReport -Value $productBuild -Path (Join-Path $report.run_root 'product-build.json') -Environment $buildReportEnvironment
    if (-not $productBuild.files_verified) {
        Stop-RunBeforeScenarios -Status 'FAIL_CONFIGURATION' -Reason 'PRODUCT_BUILD_NOT_VERIFIED: inspect product-build.json; no product was started.'
    }
    $interceptionBefore = Save-InterceptionObservation -Path (Join-Path $report.run_root 'interception-before.json')
    if (-not $interceptionBefore.current_driver_preparation_allowed) {
        Stop-RunBeforeScenarios -Status 'FAIL_INFRASTRUCTURE' -Reason ($interceptionBefore.blocking_reasons -join ', ')
    }
    try { $runtimeEnvironmentPlan = New-RuntimeEnvironmentPlan -Environment $rawEnvironment -RuntimeConfig $runtimeConfig }
    catch {
        $configurationFailure = [pscustomobject]@{prepared=$false;status='FAIL_CONFIGURATION';reason=(Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment);remediation='Replace example/private placeholders and use absolute verified paths before runtime.'}
        Write-RedactedJsonReport -Value $configurationFailure -Path (Join-Path $report.run_root 'environment-preparation-plan.json') -Environment $environment
        Write-RedactedJsonReport -Value $configurationFailure -Path (Join-Path $report.run_root 'environment-preparation-result.json') -Environment $environment
        Stop-RunBeforeScenarios -Status 'FAIL_CONFIGURATION' -Reason ([string]$configurationFailure.reason)
    }
    Write-RedactedJsonReport -Value $runtimeEnvironmentPlan -Path (Join-Path $report.run_root 'environment-preparation-plan.json') -Environment $environment
    $runtimeEnvironmentAdapter = New-SystemRuntimeEnvironmentAdapter
    try {
        if ($PrepareRuntimeEnvironment) {
            $preparation = Invoke-RuntimeEnvironmentPreparation -Plan $runtimeEnvironmentPlan -Adapter $runtimeEnvironmentAdapter -AllowProductRuntime
        }
        else {
            $cleanObservation = Test-RuntimeEnvironmentClean -Plan $runtimeEnvironmentPlan -Adapter $runtimeEnvironmentAdapter -AllowProductRuntime
            $preparation = [pscustomobject]@{prepared=[bool]$cleanObservation.passed;status=$(if($cleanObservation.passed){'PASS_PREPARED'}else{'FAIL_INFRASTRUCTURE'});reason=[string]$cleanObservation.reason;remediation=[string]$cleanObservation.remediation;transitions=@([pscustomobject]@{event='PREPARATION_EXPLICITLY_SKIPPED'});cleanup=$cleanObservation}
        }
    }
    catch {
        $preparation = [pscustomobject]@{prepared=$false;status='FAIL_INFRASTRUCTURE';reason=(Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment);remediation='Verify access to configured binaries, CIM process paths and the configured service.';transitions=@();cleanup=[pscustomobject]@{verified=$false}}
    }
    Write-RedactedJsonReport -Value $preparation -Path (Join-Path $report.run_root 'environment-preparation-result.json') -Environment $environment
    Write-Output "ENVIRONMENT_PREPARED status=$($preparation.status) run_id=$($report.run_id)"
    if (-not [bool]$preparation.prepared) { Stop-RunBeforeScenarios -Status 'FAIL_INFRASTRUCTURE' -Reason ([string]$preparation.reason) }

    try { $healthResults = @(Invoke-HealthCheckPlan -Plan (New-HealthCheckPlan -Environment $environment) -Environment $environment -AllowProductRuntime) }
    catch { Stop-RunBeforeScenarios -Status 'FAIL_INFRASTRUCTURE' -Reason (Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment) }
    Write-RedactedJsonReport -Value $healthResults -Path (Join-Path $report.run_root 'immutable-preflight.json') -Environment $environment
    $healthSummary = Test-HealthResults -Results $healthResults
    if (-not $healthSummary.passed) { Stop-RunBeforeScenarios -Status 'FAIL_INFRASTRUCTURE' -Reason (@($healthSummary.failures.reason) -join ', ') }

    try { $baselinePlan = New-DirectBaselinePlan -Environment $environment }
    catch { Stop-RunBeforeScenarios -Status 'FAIL_INFRASTRUCTURE' -Reason (Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment) }
    $baselineCollector = {
        param($canonicalRecord)
        $plan = New-VpsDynamicEvidencePlan -Environment $environment -CanonicalRecords @($canonicalRecord) -EvidenceDirectory $report.run_root
        return Invoke-VpsDynamicEvidencePlan -Plan $plan -ProcessAdapter (New-SystemProcessAdapter) -Environment $environment -AllowProductRuntime
    }.GetNewClosure()
    try { $directBaseline = Invoke-DirectBaselineDiscovery -Plan $baselinePlan -Adapter (New-SystemDirectBaselineAdapter) -VpsCollector $baselineCollector -ExpectedDirectEgressIpv4 $ExpectedDirectEgressIpv4 -AllowProductRuntime }
    catch { Stop-RunBeforeScenarios -Status 'FAIL_INFRASTRUCTURE' -Reason (Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment) }
    Write-RedactedJsonReport -Value $directBaseline.client_result -Path (Join-Path $report.run_root 'direct-baseline-client.json') -Environment $environment
    Write-RedactedJsonReport -Value $directBaseline -Path (Join-Path $report.run_root 'direct-baseline-result.json') -Environment $environment
    if (-not [bool]$directBaseline.passed) { Stop-RunBeforeScenarios -Status 'FAIL_INFRASTRUCTURE' -Reason ([string]$directBaseline.reason) }
}
}

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
$preparedProfiles = @{}
if ($ProductProfileContract -ne 'driver' -or -not [string]::IsNullOrWhiteSpace($ReferenceProfileContract)) {
    $compatibilityRecords = [System.Collections.Generic.List[object]]::new()
    $profilesCompatible = $selectedCount -gt 0
    foreach ($item in $decisions) {
        if (-not $item.decision.selected) { continue }
        $scenarioId = [string]$item.scenario.scenario_id
        try {
            $validation = Test-ExpectedProfileValidation -Scenario $item.scenario -Environment $environment -TemplatePath (Join-Path $PSScriptRoot 'templates/profile.pbprofile.template') -ProxyDestinationMode $ProxyDestinationMode
            $preparedProfiles[$scenarioId] = $validation
            $target = $null
            $reference = $null
            if ($validation.may_write) {
                $target = Get-ProductProfileCompatibility -Profile $validation.profile -Contract $ProductProfileContract
                if (-not [string]::IsNullOrWhiteSpace($ReferenceProfileContract)) {
                    $reference = Get-ProductProfileCompatibility -Profile $validation.profile -Contract $ReferenceProfileContract
                }
            }
            $compatible = [bool]$validation.passed -and $(if ($validation.may_write) {
                $target.profile_compatible -and ($null -eq $reference -or $reference.profile_compatible)
            } else { [string]::IsNullOrWhiteSpace($ReferenceProfileContract) })
            if (-not $compatible) { $profilesCompatible = $false }
            $compatibilityRecords.Add([pscustomobject]@{
                scenario_id=$scenarioId; profile_compatible=$compatible
                status=$(if (-not $validation.passed) { 'INVALID_PROFILE' } elseif (-not $validation.may_write) { 'NO_PRODUCT_PROFILE' } elseif ($compatible) { 'PROFILE_COMPATIBLE' } else { 'NOT_COMPARABLE' })
                target=$target; reference=$reference; validation_errors=@($validation.errors)
            })
        }
        catch {
            $profilesCompatible = $false
            $compatibilityRecords.Add([pscustomobject]@{
                scenario_id=$scenarioId; profile_compatible=$false; status='PROFILE_PREPARATION_FAILED'
                reason=(Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment)
            })
        }
    }
    Write-RedactedJsonReport -Value ([pscustomobject]@{
        scope='profile-format-only'; product_profile_contract=$ProductProfileContract
        reference_profile_contract=$ReferenceProfileContract; proxy_destination_mode=$ProxyDestinationMode
        product_identity_verified=$false; route_verified=$false; reference_executed=$false
        profile_compatible=$profilesCompatible
        status=$(if ($selectedCount -eq 0) { 'NO_SELECTED_SCENARIOS' } elseif ($profilesCompatible) { 'PROFILE_COMPATIBLE' } else { 'NOT_COMPARABLE' })
        scenarios=$compatibilityRecords.ToArray()
    }) -Path (Join-Path $report.run_root 'profile-compatibility.json') -Environment $environment
    if (-not $profilesCompatible) { Stop-RunBeforeScenarios -Status 'FAIL_CONFIGURATION' -Reason 'PRODUCT_PROFILE_NOT_COMPARABLE: inspect profile-compatibility.json; no product was started.' }
}
$cancellationRequested = -not [string]::IsNullOrWhiteSpace($CancellationPath) -and (Test-Path -LiteralPath $CancellationPath -PathType Leaf)
if (-not $cancellationRequested) { . $initializeRealRuntime }

if ($PreflightOnly) {
    if ($runMode -ne 'real') { throw 'PREFLIGHT_ONLY_REQUIRES_REAL_MODE' }
    Write-RunSummary -Report $report -Records @() -AllScenarios $scenarios -Environment $environment -RunMode $runMode -ExecutionComplete $false
    Write-SafeTranscript -Report $report -Environment $environment -Message "Immutable preflight completed for $selectedCount selected scenario(s); no scenario was started."
    Complete-RunChecksums -Report $report
    Write-Output "PREFLIGHT_COMPLETE run_id=$($report.run_id) selected=$selectedCount status=PASS"
    Write-Output "EVIDENCE_PATH=$($report.run_root)"
    return
}

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
    if (-not $cancellationRequested -and -not [string]::IsNullOrWhiteSpace($CancellationPath) -and (Test-Path -LiteralPath $CancellationPath -PathType Leaf)) {
        $cancellationRequested = $true
        Write-SafeTranscript -Report $report -Environment $environment -Message 'Cooperative cancellation was requested; future scenarios will not run.'
    }
    if ($cancellationRequested) {
        $record = New-ResultRecord -Scenario $scenario -Status 'SKIPPED_SELECTION' -Reason 'run cancellation requested before scenario execution' -Attempt 0 -DurationMs 0 -Selected $false
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
        $profileValidation = $(if ($preparedProfiles.ContainsKey([string]$scenario.scenario_id)) {
            $preparedProfiles[[string]$scenario.scenario_id]
        } else {
            Test-ExpectedProfileValidation -Scenario $scenario -Environment $environment -TemplatePath (Join-Path $PSScriptRoot 'templates/profile.pbprofile.template') -ProxyDestinationMode $ProxyDestinationMode
        })
        if (-not $profileValidation.passed) { throw "PROFILE_EXPECTATION_FAILED: $($profileValidation.errors -join ' | ')" }
        $profile = $profileValidation.profile
        if ($profileValidation.may_write) { $writtenProfile = Write-ResolvedProfile -Profile $profile -ScenarioId $scenario.scenario_id -OutputDirectory $report.profile_root -ProductProfileContract $ProductProfileContract }
        Write-RedactedJsonReport -Value ([pscustomobject]@{run_mode=$runMode;expectation=$profileValidation.expectation;passed=$profileValidation.passed;errors=@($profileValidation.errors);profile_written=($null -ne $writtenProfile);product_profile_contract=$ProductProfileContract;proxy_destination_mode=$ProxyDestinationMode}) -Path (Join-Path $scenarioEvidence 'profile-validation.json') -Environment $environment
    }
    catch {
        $profileFailures++
        $safe = Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment
        Add-SelectionRecord -Report $report -Environment $environment -Record ([pscustomobject]@{run_mode=$runMode;scenario_id=$scenario.scenario_id;coverage_group=$scenario.coverage_group;implementation_status=$scenario.implementation_status;selected=$false;status='FAIL_PROFILE_GENERATION';reason=$safe})
        $record = New-ResultRecord -Scenario $scenario -Status 'FAIL_HARNESS' -Reason $safe -Attempt 0 -DurationMs 0 -Selected $true
        $records.Add($record); Add-ResultRecord -Report $report -Record $record -Environment $environment
        Write-SafeTranscript -Report $report -Environment $environment -Message "$($scenario.scenario_id): FAIL_PROFILE_GENERATION ($safe)."
        if ($runMode -eq 'real') { Write-RedactedJsonReport -Value (Test-RuntimeEnvironmentClean -Plan $runtimeEnvironmentPlan -Adapter $runtimeEnvironmentAdapter -AllowProductRuntime) -Path (Join-Path $scenarioEvidence 'post-run-cleanup.json') -Environment $environment }
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
        elseif ([string]$resolvedScenario.executor_kind -eq 'protocol-worker') {
            $clientPlan = New-ProtocolExecutionPlan -Scenario $resolvedScenario -Environment $environment -RunId $report.run_id -Attempt 1 -EvidenceDirectory $scenarioEvidence -RuntimeContracts $protocolRuntimeContracts -OperationTimeoutCapMs ([int]$suite.execution.timeout_ms) -ProcessExitGraceMs ([int]$runtimeConfig.client_process_exit_grace_ms) -ActualPathTimeoutMs ([int]$runtimeConfig.protocol_worker_actual_path_timeout_ms) -PlanningOnly:($runMode -ne 'real')
        }
        else {
            $clientExecutable = $(if ($environment.ContainsKey('PB_CLIENT_EXE')) { $environment['PB_CLIENT_EXE'] } else { 'pb_net_client.exe' })
            $clientPlan = New-ClientPlan -Scenario $resolvedScenario -ExecutablePath $clientExecutable -RunId $report.run_id -JsonlPath $clientJsonlPath -Contract $clientContract -ExpectedSha256 $environment['PB_EXPECTED_CLIENT_SHA256'] -OperationTimeoutCapMs ([int]$suite.execution.timeout_ms) -ProcessExitGraceMs ([int]$runtimeConfig.client_process_exit_grace_ms)
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
        if ($runMode -eq 'real') { Write-RedactedJsonReport -Value (Test-RuntimeEnvironmentClean -Plan $runtimeEnvironmentPlan -Adapter $runtimeEnvironmentAdapter -AllowProductRuntime) -Path (Join-Path $scenarioEvidence 'post-run-cleanup.json') -Environment $environment }
        if ($suite.execution.stop_on_harness_failure) { $stopRun = $true }
        continue
    }

    $profileSha = $(if ($null -ne $writtenProfile) { [string]$writtenProfile.sha256 } else { '' })
    $attempts = $(if ($DryRun -or [string]$scenario.implementation_status -eq 'DECLARATIVE_ONLY' -or -not $profileValidation.may_write) { 1 } else { [Math]::Max([int]$scenario.repeats, [int]$suite.execution.repeats) })
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $attemptTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $status = ''
        $reason = ''
        $assertion = $null
        $postCleanup = $null
        if ($attempt -gt 1 -and [string]$resolvedScenario.executor_kind -eq 'protocol-worker') {
            $clientPlan = New-ProtocolExecutionPlan -Scenario $resolvedScenario -Environment $environment -RunId $report.run_id -Attempt $attempt -EvidenceDirectory $scenarioEvidence -RuntimeContracts $protocolRuntimeContracts -OperationTimeoutCapMs ([int]$suite.execution.timeout_ms) -ProcessExitGraceMs ([int]$runtimeConfig.client_process_exit_grace_ms) -ActualPathTimeoutMs ([int]$runtimeConfig.protocol_worker_actual_path_timeout_ms) -PlanningOnly:($runMode -ne 'real')
            Write-RedactedJsonReport -Value $clientPlan -Path (Join-Path $scenarioEvidence "client-plan-attempt-$attempt.json") -Environment $environment
        }
        if ($suiteTimer.ElapsedMilliseconds -ge [long]$suite.execution.suite_timeout_ms) { $status='SKIPPED_SELECTION';$reason='suite timeout reached' }
        elseif (-not $profileValidation.may_write) {
            $disposition = Get-ExpectedProfileValidationDisposition -Validation $profileValidation -RunMode $runMode
            $status = [string]$disposition.status
            $reason = [string]$disposition.reason
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
                $isProtocolScenario = [string]$resolvedScenario.executor_kind -eq 'protocol-worker'
                $mock = $(if ($isProtocolScenario) {
                    Invoke-MockProtocolScenario -Scenario $resolvedScenario -ExecutionPlan $clientPlan -FixtureRoot $MockFixtureRoot
                } else {
                    Invoke-MockScenario -Scenario $resolvedScenario -ClientPlan $clientPlan -FixtureRoot $MockFixtureRoot -EvidenceDirectory $scenarioEvidence -Environment $environment
                })
                Write-RedactedJsonReport -Value $mock.client_result -Path (Join-Path $scenarioEvidence 'client-result.json') -Environment $environment
                Write-RedactedJsonReport -Value $mock.proxybridge_records -Path (Join-Path $scenarioEvidence 'proxybridge-evidence.json') -Environment $environment
                $mockServerRecords = @()
                if ($isProtocolScenario) { $mockServerRecords = @($mock.server_records) }
                else { $mockServerRecords = @($mock.vps_records) }
                Write-RedactedJsonReport -Value $mockServerRecords -Path (Join-Path $scenarioEvidence 'vps-evidence.json') -Environment $environment
                $assertion = $(if ($isProtocolScenario) {
                    Test-ProtocolScenarioAssertions -Scenario $resolvedScenario -ExecutionPlan $clientPlan -ClientResult $mock.client_result -ServerRecords $mockServerRecords -ProxyBridgeRecords $mock.proxybridge_records -EvidenceContext $mock.evidence_context -RunMode mock
                } else {
                    Test-ScenarioAssertions -Scenario $resolvedScenario -ClientPlan $clientPlan -ClientResult $mock.client_result -VpsRecords $mockServerRecords -ProxyBridgeRecords $mock.proxybridge_records -EvidenceContext $mock.evidence_context -RunMode mock
                })
                Write-RedactedJsonReport -Value $assertion -Path (Join-Path $scenarioEvidence 'assertions.json') -Environment $environment
                $status = Get-ClassifiedStatus -AssertionResult $assertion -KnownDefect $decision.known_defect -RunMode mock -MockExpectation ([string]$scenario.mock.expected_status)
                $reason = $(if ($assertion.passed) { 'fixture evidence satisfied orchestration contract' } else { @($assertion.errors) -join ', ' })
            }
            catch { $status='MOCK_HOLD';$reason="mock harness: $(Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment)" }
        }
        else {
            try {
                $isProtocolScenario = [string]$resolvedScenario.executor_kind -eq 'protocol-worker'
                $vpsCursor = $null
                if ($isProtocolScenario) {
                    if (-not [string]::IsNullOrWhiteSpace($VpsEvidenceImportPath)) { throw 'PROTOCOL_SERVER_IMPORT_NOT_SUPPORTED' }
                    $vpsCursorPlan = New-ProtocolLogCursorPlan -Environment $environment
                    Write-RedactedJsonReport -Value $vpsCursorPlan -Path (Join-Path $scenarioEvidence 'vps-cursor-plan.json') -Environment $environment
                    $vpsCursor = Invoke-ProtocolLogCursorPlan -Plan $vpsCursorPlan -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime
                    Write-RedactedJsonReport -Value $vpsCursor -Path (Join-Path $scenarioEvidence 'vps-cursor-result.json') -Environment $environment
                }
                elseif ([string]::IsNullOrWhiteSpace($VpsEvidenceImportPath)) {
                    $vpsCursorPlan = New-VpsLogCursorPlan -Environment $environment
                    Write-RedactedJsonReport -Value $vpsCursorPlan -Path (Join-Path $scenarioEvidence 'vps-cursor-plan.json') -Environment $environment
                    $vpsCursor = Invoke-VpsLogCursorPlan -Plan $vpsCursorPlan -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime
                    Write-RedactedJsonReport -Value $vpsCursor -Path (Join-Path $scenarioEvidence 'vps-cursor-result.json') -Environment $environment
                }
                $readyRegex = $(if ($environment.ContainsKey('PB_CLI_READY_REGEX')) { $environment['PB_CLI_READY_REGEX'] } else { [string]$runtimeConfig.cli_readiness.regex })
                $readyStableMs = $(if ($environment.ContainsKey('PB_CLI_READY_STABLE_MS')) { [int]$environment['PB_CLI_READY_STABLE_MS'] } else { [int]$runtimeConfig.cli_readiness.stable_ms })
                $readinessTimeoutMs = $(if ($environment.ContainsKey('PB_CLI_READINESS_TIMEOUT_MS')) { [int]$environment['PB_CLI_READINESS_TIMEOUT_MS'] } else { [int]$runtimeConfig.cli_readiness.readiness_timeout_ms })
                $stopTimeoutMs = $(if ($environment.ContainsKey('PB_CLI_STOP_TIMEOUT_MS')) { [int]$environment['PB_CLI_STOP_TIMEOUT_MS'] } else { [int]$runtimeConfig.cli_readiness.stop_timeout_ms })
                $cliVariant = $(if ($environment.ContainsKey('PB_PROXYBRIDGE_CLI_VARIANT')) { [string]$environment['PB_PROXYBRIDGE_CLI_VARIANT'] } else { 'upstream' })
                $cliPlan = New-ProxyBridgeCliPlan -ExecutablePath $environment['PB_PROXYBRIDGE_CLI_EXE'] -ProfilePath $writtenProfile.path -ProductProfileContract $ProductProfileContract -CliVariant $cliVariant -ReadyRegex $readyRegex -ReadyStableMs $readyStableMs -ReadinessTimeoutMs $readinessTimeoutMs -StopTimeoutMs $stopTimeoutMs -ActualPathTimeoutMs ([int]$runtimeConfig.cli_actual_path_timeout_ms)
                Write-RedactedJsonReport -Value $cliPlan -Path (Join-Path $scenarioEvidence 'cli-plan.json') -Environment $environment
                $clientAdapter = New-SystemProcessAdapter
                $workload = $(if ($isProtocolScenario) {
                    { Invoke-ProtocolExecutionPlan -Plan $clientPlan -RuntimeContracts $protocolRuntimeContracts -ProcessAdapter $clientAdapter -AllowProductRuntime }.GetNewClosure()
                } else {
                    { Invoke-ClientPlan -Plan $clientPlan -ProcessAdapter $clientAdapter -AllowProductRuntime }.GetNewClosure()
                })
                $sink = { param($evidence) Write-RedactedJsonReport -Value $evidence -Path (Join-Path $scenarioEvidence 'cli-lifecycle.json') -Environment $environment }.GetNewClosure()
                $lifecycle = Invoke-ProxyBridgeCliLifecycle -Plan $cliPlan -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime -Workload $workload -EvidenceSink $sink
                $clientResult = $lifecycle.workload_result
                $lifecycleStart = [datetime]::Parse([string]$lifecycle.started_at_utc).ToUniversalTime()
                $lifecycleEnd = [datetime]::Parse([string]$lifecycle.completed_at_utc).ToUniversalTime()
                $proxyBridgeLines = @(([string]$lifecycle.process_result.stdout) -split "`r?`n") + @(([string]$lifecycle.process_result.stderr) -split "`r?`n")
                # Render terminal observations with pyte. Their deduplicated
                # screen rows are advisory, not a complete source event log.
                $plainLogCapture = $null -ne $lifecycle.process_result.PSObject.Properties['output_format'] -and [string]$lifecycle.process_result.output_format -eq 'separate-text-streams'
                $terminalDecode = $null
                $proxyBridgeRecords = @()
                if ($plainLogCapture) { $proxyBridgeRecords = @(ConvertFrom-ProxyBridgeTextLines -Lines $proxyBridgeLines -DefaultTimestampUtc $lifecycleStart) }
                elseif ([string]$lifecycle.process_result.output_format -eq 'terminal-vt-merged') {
                    $terminalDecode = ConvertFrom-ProxyBridgeTerminalCapture -RawText ([string]$lifecycle.process_result.stdout) -EvidenceDirectory $scenarioEvidence -Environment $environment -DefaultTimestampUtc $lifecycleStart
                    $proxyBridgeRecords = @($terminalDecode.records)
                    Write-RedactedJsonReport -Value $terminalDecode -Path (Join-Path $scenarioEvidence 'proxybridge-terminal-decode.json') -Environment $environment
                }
                if ($isProtocolScenario) {
                    $vpsPlan = New-ProtocolServerCollectionPlan -Environment $environment -ExecutionPlan $clientPlan -Cursor $vpsCursor
                    Write-RedactedJsonReport -Value $vpsPlan -Path (Join-Path $scenarioEvidence 'vps-collection-plan.json') -Environment $environment
                    $vpsCollection = Invoke-ProtocolServerCollectionPlan -Plan $vpsPlan -ExecutionPlan $clientPlan -RuntimeContracts $protocolRuntimeContracts -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime
                    $vpsCollection | Add-Member -NotePropertyName complete_shas -NotePropertyValue @($clientResult.records | ForEach-Object { [string]$_.payload_sha256 } | Sort-Object -Unique)
                    $vpsCollection | Add-Member -NotePropertyName query_results -NotePropertyValue @([pscustomobject]@{mode='protocol-log-cursor';success=$true;record_count=@($vpsCollection.records).Count})
                }
                elseif (-not [string]::IsNullOrWhiteSpace($VpsEvidenceImportPath)) {
                    $expectedShas = @($clientResult.canonical_records | ForEach-Object { [string]$_.payload_sha256 } | Sort-Object -Unique)
                    $vpsCollection = Invoke-VpsImportEvidencePlan -Plan (New-VpsEvidencePlan -ImportPath $VpsEvidenceImportPath) -ExpectedShas $expectedShas
                }
                else {
                    $vpsPlan = New-VpsDynamicEvidencePlan -Environment $environment -CanonicalRecords @($clientResult.canonical_records) -EvidenceDirectory $scenarioEvidence -Cursor $vpsCursor
                    Write-RedactedJsonReport -Value $vpsPlan -Path (Join-Path $scenarioEvidence 'vps-collection-plan.json') -Environment $environment
                    $vpsCollection = Invoke-VpsDynamicEvidencePlan -Plan $vpsPlan -ProcessAdapter (New-SystemProcessAdapter) -Environment $environment -AllowProductRuntime
                }
                $vpsRecords = @($vpsCollection.records); $vpsCaptureComplete = [bool]$vpsCollection.capture_complete; $vpsCompleteShas = @($vpsCollection.complete_shas)
                Write-RedactedJsonReport -Value $vpsCollection.query_results -Path (Join-Path $scenarioEvidence 'vps-collection-result.json') -Environment $environment
                if (-not $vpsCaptureComplete) { throw 'VPS_SSH_COLLECTION_INCOMPLETE' }
                Write-RedactedJsonReport -Value $clientResult -Path (Join-Path $scenarioEvidence 'client-result.json') -Environment $environment
                Write-RedactedJsonReport -Value $proxyBridgeRecords -Path (Join-Path $scenarioEvidence 'proxybridge-evidence.json') -Environment $environment
                Write-RedactedJsonReport -Value $vpsRecords -Path (Join-Path $scenarioEvidence 'vps-evidence.json') -Environment $environment
                $context = [pscustomobject]@{
                    vps_capture_complete=$vpsCaptureComplete;vps_capture_complete_shas=$vpsCompleteShas;server_capture_complete=$vpsCaptureComplete
                    channel_capture_completed=([bool]$lifecycle.process_result.output_capture_complete -and $plainLogCapture);records_found=(@($proxyBridgeRecords).Count -gt 0)
                    proxybridge_log_format=[string]$lifecycle.process_result.output_format
                    proxybridge_source_event_stream_complete=$false
                    proxybridge_log_decoder_status=$(if($plainLogCapture){'PLAIN_TEXT'}elseif($null -ne $terminalDecode){[string]$terminalDecode.status}else{'UNSUPPORTED_FORMAT'})
                    direct_egress_ip=[string]$directBaseline.direct_egress_ip;proxy_egress_ip=$ExpectedProxyEgressIpv4
                    expected_process=$(if($isProtocolScenario){[string]$clientPlan.expected_process}else{[System.IO.Path]::GetFileName($environment['PB_CLIENT_EXE'])});start_time_utc=$lifecycleStart;end_time_utc=$lifecycleEnd
                }
                $assertion = $(if ($isProtocolScenario) {
                    Test-ProtocolScenarioAssertions -Scenario $resolvedScenario -ExecutionPlan $clientPlan -ClientResult $clientResult -ServerRecords $vpsRecords -ProxyBridgeRecords $proxyBridgeRecords -EvidenceContext $context -RunMode real
                } else {
                    Test-ScenarioAssertions -Scenario $resolvedScenario -ClientPlan $clientPlan -ClientResult $clientResult -VpsRecords $vpsRecords -ProxyBridgeRecords $proxyBridgeRecords -EvidenceContext $context -RunMode real
                })
                Write-RedactedJsonReport -Value $assertion -Path (Join-Path $scenarioEvidence 'assertions.json') -Environment $environment
                $status = Get-ClassifiedStatus -AssertionResult $assertion -KnownDefect $decision.known_defect -RunMode real
                $reason = $(if ($assertion.passed) { "evidence passed: $($assertion.evidence_basis)" } else { @($assertion.errors) -join ', ' })
            }
            catch {
                $safe = Get-SafeExceptionMessage -ErrorRecord $_ -Environment $environment
                if ($safe -match 'CLI_CLEANUP_FAILED|POST_STOP_VERIFICATION|PROCESS_FORCE_STOP_TIMEOUT|CONSOLE_HOST_CHILD_STOP_TIMEOUT') { $status='CONTAMINATED';$stopRun=$true }
                elseif ($safe -match 'CONSOLE_HOST') { $status='FAIL_INFRASTRUCTURE';$stopRun=$true }
                elseif ($safe -match 'READINESS|ACTUAL_PATH|PATH_VERIFICATION|CLIENT_PRELAUNCH|START_FAILED|PROCESS_START') { $status='FAIL_INFRASTRUCTURE' }
                elseif ($safe -match 'PROTOCOL_(PRELAUNCH|PATH_QUERY_TIMEOUT|PATH_VERIFICATION|SSH_|CURSOR_|SERVER_COLLECTION_|ENVIRONMENT_MISSING_)') { $status='FAIL_INFRASTRUCTURE' }
                elseif ($safe -match 'VPS_(SSH_(COLLECTION_INCOMPLETE|TIMEOUT|FAILED|PROCESS_FAILED|HOST_INVALID|USER_INVALID|PORT_INVALID|EXECUTABLE_MISSING)|CURSOR_(TIMEOUT|FAILED|OUTPUT_INVALID|OFFSET_INVALID|INVALID))|VPS_ENVIRONMENT_MISSING_') { $status='FAIL_INFRASTRUCTURE' }
                elseif ($safe -match 'VPS_EVIDENCE_IMPORT_NOT_FOUND') { $status='HOLD_AMBIGUOUS' }
                else { $status='FAIL_HARNESS' }
                $reason=$safe
            }
        }

        if ($runMode -eq 'real') {
            $interceptionAfter = Save-InterceptionObservation -Path (Join-Path $scenarioEvidence 'interception-after.json')
            if (-not $interceptionAfter.current_driver_preparation_allowed) {
                $status='CONTAMINATED';$reason=($interceptionAfter.blocking_reasons -join ', ');$stopRun=$true
            }
            $postCleanup = Test-RuntimeEnvironmentClean -Plan $runtimeEnvironmentPlan -Adapter $runtimeEnvironmentAdapter -AllowProductRuntime
            Write-RedactedJsonReport -Value $postCleanup -Path (Join-Path $scenarioEvidence 'post-run-cleanup.json') -Environment $environment
            if (-not $postCleanup.passed) { $status='CONTAMINATED';$reason=[string]$postCleanup.reason;$stopRun=$true }
        }

        $completeness = New-EvidenceCompletenessMatrix -ScenarioEvidenceRoot $scenarioEvidence -RunRoot $report.run_root -RunMode $runMode -AssertionResult $assertion -PostCleanup $postCleanup
        Write-RedactedJsonReport -Value $completeness -Path (Join-Path $scenarioEvidence 'evidence-completeness.json') -Environment $environment
        if ($runMode -eq 'real' -and $null -ne $assertion -and $status -in @('PASS','FAIL_PRODUCT','EXPECTED_FAIL') -and -not [bool]$completeness.overall_complete) {
            $status='HOLD_AMBIGUOUS';$reason="mandatory evidence incomplete: $(@($completeness.missing_mandatory) -join ', ')"
        }

        $attemptTimer.Stop()
        $record = New-ResultRecord -Scenario $scenario -Status $status -Reason $reason -Attempt $attempt -DurationMs $attemptTimer.ElapsedMilliseconds -Selected $true -ProfileSha256 $profileSha
        $records.Add($record); Add-ResultRecord -Report $report -Record $record -Environment $environment
        if ($stopRun) { break }
        if ($runMode -eq 'real' -and $status -eq 'FAIL_PRODUCT') { $consecutiveProductFailures++ }
        elseif ($runMode -eq 'real') { $consecutiveProductFailures = 0 }
        if ($runMode -eq 'real' -and (Test-ShouldStopRun -Status $status -Suite $suite -ConsecutiveProductFailures $consecutiveProductFailures -Independent $scenario.independent)) { $stopRun=$true;break }
    }
}

$suiteTimer.Stop()
Write-RunSummary -Report $report -Records $records.ToArray() -AllScenarios $scenarios -Environment $environment -RunMode $runMode -ExecutionComplete (-not $stopRun -and -not $cancellationRequested)
Write-SafeTranscript -Report $report -Environment $environment -Message "Run completed; selected=$selectedCount; profile_failures=$profileFailures; mode=$runMode."
Complete-RunChecksums -Report $report
"RUN_COMPLETE mode=$runMode run_id=$($report.run_id) scenarios=$($scenarios.Count) selected=$selectedCount status=$(if($profileFailures -gt 0){'FAIL_HARNESS'}else{'COMPLETE'})"
"EVIDENCE_PATH=$($report.run_root)"
if ($profileFailures -gt 0) { throw "FAIL_PROFILE_GENERATION_COUNT=$profileFailures" }
