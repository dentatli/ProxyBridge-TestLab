[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvPath,
    [Parameter(Mandatory)][string]$ScenarioRoot,
    [Parameter(Mandatory)][string]$RuntimeConfigPath,
    [Parameter(Mandatory)][string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'modules\Config.psm1') -Force
Import-Module (Join-Path $repositoryRoot 'modules\Env.psm1') -Force
Import-Module (Join-Path $repositoryRoot 'modules\ProfileAdapter.psm1') -Force
Import-Module (Join-Path $repositoryRoot 'modules\ScenarioCatalog.psm1') -Force
Import-Module (Join-Path $repositoryRoot 'modules\ProtocolWorker.psm1') -Force
Import-Module (Join-Path $repositoryRoot 'modules\ProtocolRunner.psm1') -Force
Import-Module (Join-Path $repositoryRoot 'modules\ProcessAdapter.psm1') -Force

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$scenarioIds = @(
    'protocol-dns-udp-direct',
    'protocol-dns-tcp-direct',
    'protocol-tls-direct',
    'protocol-http-direct',
    'protocol-https-direct'
)
$smokeStage = 'INITIALIZE'
$activeScenarioId = ''

function Assert-SmokeClientResult {
    param($Result, [string]$ScenarioId)
    if ([bool]$Result.timed_out) { throw "PROTOCOL_SMOKE_CLIENT_TIMEOUT:$ScenarioId" }
    if ([int]$Result.exit_code -ne 0) { throw "PROTOCOL_SMOKE_CLIENT_EXIT:$ScenarioId" }
    if (-not [bool]$Result.prelaunch_verified -or -not [bool]$Result.stdout_status_valid -or -not [bool]$Result.stderr_empty) {
        throw "PROTOCOL_SMOKE_CLIENT_CONTRACT:$ScenarioId"
    }
    if (@($Result.records).Count -ne 1 -or [string]$Result.records[0].result -ne 'PASS') {
        throw "PROTOCOL_SMOKE_CLIENT_EVIDENCE:$ScenarioId"
    }
}

try {
    if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) { $null = New-Item -ItemType Directory -Path $OutputRoot -Force }
    $runtime = Import-RuntimeConfig -Path $RuntimeConfigPath
    $rawEnvironment = Import-DotEnv -Path $EnvPath
    $environment = $rawEnvironment
    $runtimeContracts = Import-ProtocolWorkerRuntimeContract `
        -RuntimeContractPath (Join-Path $repositoryRoot 'config\protocol-worker-runtime.json') `
        -PluginManifestPath $environment['PB_PROTOCOL_WORKER_MANIFEST']
    $catalog = @(Import-ScenarioCatalog -ScenarioRoot $ScenarioRoot)
    $runId = 'protocol-smoke-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($scenarioId in $scenarioIds) {
        $activeScenarioId = $scenarioId
        $smokeStage = 'SCENARIO_LOOKUP'
        $matches = @($catalog | Where-Object { [string]$_.scenario_id -eq $scenarioId })
        if ($matches.Count -ne 1 -or [string]$matches[0].implementation_status -ne 'EXECUTABLE' -or [string]$matches[0].executor_kind -ne 'protocol-worker') {
            throw "PROTOCOL_SMOKE_SCENARIO_CONTRACT:$scenarioId"
        }
        $scenarioTemplate = $matches[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $scenarioTemplate.client.local_ip = ''
        $smokeStage = 'SCENARIO_RESOLUTION'
        $scenario = Resolve-JsonVariables -InputObject $scenarioTemplate -Variables $environment
        $evidenceRoot = Join-Path $OutputRoot $scenarioId
        $null = New-Item -ItemType Directory -Path $evidenceRoot -Force
        $smokeStage = 'SERVER_CURSOR'
        $cursorPlan = New-ProtocolLogCursorPlan -Environment $environment
        $cursor = Invoke-ProtocolLogCursorPlan -Plan $cursorPlan -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime
        $smokeStage = 'CLIENT_PLAN'
        $plan = New-ProtocolExecutionPlan -Scenario $scenario -Environment $environment -RunId $runId -Attempt 1 `
            -EvidenceDirectory $evidenceRoot -RuntimeContracts $runtimeContracts -OperationTimeoutCapMs 10000 `
            -ProcessExitGraceMs ([int]$runtime.client_process_exit_grace_ms) `
            -ActualPathTimeoutMs ([int]$runtime.protocol_worker_actual_path_timeout_ms)
        $smokeStage = 'CLIENT_EXECUTION'
        $client = Invoke-ProtocolExecutionPlan -Plan $plan -RuntimeContracts $runtimeContracts -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime
        Assert-SmokeClientResult -Result $client -ScenarioId $scenarioId
        $smokeStage = 'SERVER_COLLECTION'
        $collectionPlan = New-ProtocolServerCollectionPlan -Environment $environment -ExecutionPlan $plan -Cursor $cursor
        $server = Invoke-ProtocolServerCollectionPlan -Plan $collectionPlan -ExecutionPlan $plan -RuntimeContracts $runtimeContracts -ProcessAdapter (New-SystemProcessAdapter) -AllowProductRuntime
        $smokeStage = 'EVIDENCE_ASSERTION'
        if (-not [bool]$server.capture_complete -or @($server.records).Count -ne 1) { throw "PROTOCOL_SMOKE_SERVER_EVIDENCE:$scenarioId" }
        $clientRecord = $client.records[0]
        $serverRecord = $server.records[0]
        foreach ($identity in @('run_id','scenario_id','attempt_id','flow_id','payload_sha256','protocol_family','transport')) {
            if ([string]$clientRecord.$identity -ne [string]$serverRecord.$identity) { throw "PROTOCOL_SMOKE_IDENTITY_MISMATCH:$scenarioId/$identity" }
        }
        if ([string]$serverRecord.result -ne 'PASS') { throw "PROTOCOL_SMOKE_SERVER_RESULT:$scenarioId" }
        $results.Add([pscustomobject][ordered]@{
            scenario_id=$scenarioId
            status='PASS'
            client_records=1
            server_records=1
            identities_matched=$true
            payload_hash_matched=$true
        })
    }

    $summary = [pscustomobject][ordered]@{
        schema_version=1
        state='PASS'
        smoke_kind='protocol-endpoint-without-product'
        proxybridge_started=$false
        scenario_count=$results.Count
        passed=$results.Count
        failed=0
        results=$results.ToArray()
    }
    $summaryPath = Join-Path $OutputRoot 'protocol-smoke-summary.json'
    [System.IO.File]::WriteAllText($summaryPath, (($summary | ConvertTo-Json -Depth 10) + [Environment]::NewLine), $utf8NoBom)
    $summary | ConvertTo-Json -Depth 10 -Compress
    exit 0
}
catch {
    $safeScenario = ''
    $rawError = [string]$_.Exception.Message
    if ($rawError -match ':(protocol-[A-Za-z0-9-]+)') { $safeScenario = $Matches[1] }
    $safeFailureCode = 'UNCLASSIFIED'
    if ($rawError -match '^PROTOCOL_PRELAUNCH_(?:PATH_MISSING|HASH_FAILED)_(python|entrypoint|manifest|evidence-contract|ca)$') {
        $safeFailureCode = ([regex]::Replace($rawError.ToUpperInvariant(), '[^A-Z0-9_]', '_')).TrimEnd([char]'_')
    }
    elseif ($rawError -match '^((?:PROTOCOL|PROCESS)_[A-Z0-9_]+)') {
        $safeFailureCode = ([regex]::Replace([string]$Matches[1], '[^A-Z0-9_]', '')).TrimEnd([char]'_')
    }
    if ($activeScenarioId -match '^protocol-[a-z0-9-]+$') {
        $safeFailureCode += '_' + ([regex]::Replace($activeScenarioId.ToUpperInvariant(), '[^A-Z0-9_]', '_'))
    }
    [pscustomobject][ordered]@{
        schema_version=1
        state='FAIL'
        smoke_kind='protocol-endpoint-without-product'
        proxybridge_started=$false
        failed_scenario=$safeScenario
        error='PROTOCOL_ONLY_SMOKE_FAILED'
        error_code=$smokeStage
        failure_code=$safeFailureCode
    } | ConvertTo-Json -Compress
    exit 1
}
