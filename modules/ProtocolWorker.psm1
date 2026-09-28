Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WorkerPropertyValue {
    param($InputObject, [string]$Name, $DefaultValue = $null)
    if ($null -eq $InputObject) { return $DefaultValue }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $DefaultValue
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
}

function Read-WorkerJson {
    param([string]$Path, [string]$ErrorCode)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "${ErrorCode}_MISSING" }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { throw "${ErrorCode}_INVALID" }
}

function Import-ProtocolWorkerRuntimeContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RuntimeContractPath,
        [Parameter(Mandatory)][string]$PluginManifestPath
    )
    $runtime = Read-WorkerJson $RuntimeContractPath 'PROTOCOL_WORKER_RUNTIME_CONTRACT'
    $manifest = Read-WorkerJson $PluginManifestPath 'PROTOCOL_WORKER_PLUGIN_MANIFEST'
    if ([int]$runtime.schema_version -ne 1 -or [int]$manifest.schema_version -ne 1) { throw 'PROTOCOL_WORKER_SCHEMA_UNSUPPORTED' }
    if (-not [bool]$runtime.python.isolated_mode -or -not [bool]$runtime.python.user_site_disabled) { throw 'PROTOCOL_WORKER_PYTHON_ISOLATION_REQUIRED' }
    if ([bool]$runtime.dependency_policy.installation_during_run -or [bool]$runtime.dependency_policy.network_download_during_run) { throw 'PROTOCOL_WORKER_RUNTIME_DOWNLOAD_FORBIDDEN' }
    if (-not [bool]$runtime.dependency_policy.lock_file_required -or -not [bool]$runtime.dependency_policy.hashes_required) { throw 'PROTOCOL_WORKER_DEPENDENCY_LOCK_REQUIRED' }
    $pluginIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($plugin in @($manifest.plugins)) {
        $id = [string](Get-WorkerPropertyValue $plugin 'id' '')
        if ([string]::IsNullOrWhiteSpace($id)) { throw 'PROTOCOL_WORKER_PLUGIN_ID_MISSING' }
        if (-not $pluginIds.Add($id)) { throw "PROTOCOL_WORKER_PLUGIN_DUPLICATE: $id" }
        if ([string]$plugin.implementation_status -eq 'IMPLEMENTED') {
            if ([string]::IsNullOrWhiteSpace([string]$plugin.evidence_profile_id) -or @($plugin.required_evidence_fields).Count -eq 0) { throw "PROTOCOL_WORKER_PLUGIN_EVIDENCE_MISSING: $id" }
        }
    }
    return [pscustomobject][ordered]@{ runtime=$runtime; manifest=$manifest; plugin_ids=$pluginIds }
}

function Assert-WorkerIdentifier {
    param([string]$Value, [string]$Field)
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$') { throw "PROTOCOL_WORKER_PLAN_IDENTIFIER_INVALID: $Field" }
}

function Assert-NoWorkerSecretValue {
    param($Value, [int]$Depth = 0, [ref]$NodeCount)
    if ($Depth -gt 8) { throw 'PROTOCOL_WORKER_PLAN_DEPTH_LIMIT' }
    $NodeCount.Value++
    if ($NodeCount.Value -gt 512) { throw 'PROTOCOL_WORKER_PLAN_NODE_LIMIT' }
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        if ($Value -is [string] -and ([string]$Value).Length -gt 4096) { throw 'PROTOCOL_WORKER_PLAN_SCALAR_LIMIT' }
        return
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) {
            $upper = ([string]$key).ToUpperInvariant()
            if ($upper -match 'PASSWORD|SECRET|TOKEN|CREDENTIAL|PRIVATE_KEY|SSH_KEY' -and $upper -notmatch '(_REF|_ID|_PRESENT)$') { throw 'PROTOCOL_WORKER_PLAN_SECRET_VALUE_FORBIDDEN' }
            Assert-NoWorkerSecretValue -Value $Value[$key] -Depth ($Depth + 1) -NodeCount $NodeCount
        }
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($item in @($Value)) { Assert-NoWorkerSecretValue -Value $item -Depth ($Depth + 1) -NodeCount $NodeCount }
        return
    }
    foreach ($property in @($Value.PSObject.Properties | Where-Object MemberType -in @('NoteProperty','Property'))) {
        $upper = ([string]$property.Name).ToUpperInvariant()
        if ($upper -match 'PASSWORD|SECRET|TOKEN|CREDENTIAL|PRIVATE_KEY|SSH_KEY' -and $upper -notmatch '(_REF|_ID|_PRESENT)$') { throw 'PROTOCOL_WORKER_PLAN_SECRET_VALUE_FORBIDDEN' }
        Assert-NoWorkerSecretValue -Value $property.Value -Depth ($Depth + 1) -NodeCount $NodeCount
    }
}

function Test-ProtocolWorkerPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$RuntimeContracts
    )
    if ([int](Get-WorkerPropertyValue $Plan 'schema_version' 0) -ne 1) { throw 'PROTOCOL_WORKER_PLAN_SCHEMA_UNSUPPORTED' }
    foreach ($field in @('run_id','scenario_id','attempt_id','flow_id','plugin_id','protocol_family')) {
        Assert-WorkerIdentifier ([string](Get-WorkerPropertyValue $Plan $field '')) $field
    }
    $implemented = @($RuntimeContracts.manifest.plugins | Where-Object { [string]$_.implementation_status -eq 'IMPLEMENTED' -and [string]$_.id -eq [string]$Plan.plugin_id })
    if ($implemented.Count -ne 1) { throw 'PROTOCOL_WORKER_PLUGIN_NOT_IMPLEMENTED' }
    if (@('NONE','TCP','UDP') -notcontains [string]$Plan.transport) { throw 'PROTOCOL_WORKER_PLAN_TRANSPORT_INVALID' }
    $timeout = [long](Get-WorkerPropertyValue $Plan 'operation_timeout_ms' 0)
    if ($timeout -le 0 -or $timeout -gt [long]$RuntimeContracts.runtime.worker.max_operation_timeout_ms) { throw 'PROTOCOL_WORKER_PLAN_TIMEOUT_INVALID' }
    $parameters = Get-WorkerPropertyValue $Plan 'parameters' $null
    $expected = Get-WorkerPropertyValue $Plan 'expected' $null
    if ($null -eq $parameters -or $null -eq $expected) { throw 'PROTOCOL_WORKER_PLAN_OBJECT_MISSING' }
    $nodes = 0
    Assert-NoWorkerSecretValue -Value $Plan -NodeCount ([ref]$nodes)
    return $true
}

function New-ProtocolWorkerPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ScenarioId,
        [Parameter(Mandatory)][string]$AttemptId,
        [Parameter(Mandatory)][string]$FlowId,
        [Parameter(Mandatory)][string]$PluginId,
        [Parameter(Mandatory)][string]$ProtocolFamily,
        [ValidateSet('NONE','TCP','UDP')][string]$Transport,
        [Parameter(Mandatory)][int]$OperationTimeoutMs,
        $Parameters = ([pscustomobject]@{}),
        $Expected = ([pscustomobject]@{}),
        [string[]]$Capabilities = @(),
        [Parameter(Mandatory)]$RuntimeContracts
    )
    $plan = [pscustomobject][ordered]@{
        schema_version=1
        run_id=$RunId
        scenario_id=$ScenarioId
        attempt_id=$AttemptId
        flow_id=$FlowId
        plugin_id=$PluginId
        protocol_family=$ProtocolFamily
        transport=$Transport
        operation_timeout_ms=$OperationTimeoutMs
        parameters=$Parameters
        expected=$Expected
        capabilities=@($Capabilities)
    }
    $null = Test-ProtocolWorkerPlan -Plan $plan -RuntimeContracts $RuntimeContracts
    return $plan
}

function Write-ProtocolWorkerPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$RuntimeContracts)
    $null = Test-ProtocolWorkerPlan -Plan $Plan -RuntimeContracts $RuntimeContracts
    if (Test-Path -LiteralPath $Path) { throw 'PROTOCOL_WORKER_PLAN_OUTPUT_EXISTS' }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [System.IO.File]::WriteAllText($Path, (($Plan | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

function Read-ProtocolWorkerEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$RuntimeContracts,
        [Parameter(Mandatory)][string]$EvidenceContractPath
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'PROTOCOL_WORKER_EVIDENCE_MISSING' }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'PROTOCOL_WORKER_EVIDENCE_BOM_FORBIDDEN' }
    $evidenceContract = Read-WorkerJson $EvidenceContractPath 'PROTOCOL_WORKER_EVIDENCE_CONTRACT'
    $matchingPlugins = @($RuntimeContracts.manifest.plugins | Where-Object { [string]$_.id -eq [string]$Plan.plugin_id })
    if ($matchingPlugins.Count -ne 1) { throw 'PROTOCOL_WORKER_PLUGIN_NOT_IMPLEMENTED' }
    $plugin = $matchingPlugins[0]
    $required = @($evidenceContract.common_required_fields) + @($plugin.required_evidence_fields)
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $record = $line | ConvertFrom-Json }
        catch { throw 'PROTOCOL_WORKER_EVIDENCE_JSON_INVALID' }
        foreach ($field in $required) {
            if ($null -eq $record.PSObject.Properties[[string]$field]) { throw "PROTOCOL_WORKER_EVIDENCE_FIELD_MISSING: $field" }
        }
        foreach ($field in @('run_id','scenario_id','attempt_id','flow_id')) {
            if ([string]$record.$field -ne [string]$Plan.$field) { throw "PROTOCOL_WORKER_EVIDENCE_IDENTITY_MISMATCH: $field" }
        }
        if ([string]$record.protocol_family -ne [string]$Plan.protocol_family -or [string]$record.transport -ne [string]$Plan.transport) { throw 'PROTOCOL_WORKER_EVIDENCE_PROTOCOL_MISMATCH' }
        if ([string]$record.payload_sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'PROTOCOL_WORKER_EVIDENCE_HASH_INVALID' }
        $records.Add($record)
    }
    if ($records.Count -eq 0) { throw 'PROTOCOL_WORKER_EVIDENCE_EMPTY' }
    return $records.ToArray()
}

function Read-ProtocolServerEvidenceSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$RuntimeContracts,
        [Parameter(Mandatory)][string]$EvidenceContractPath
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'PROTOCOL_SERVER_EVIDENCE_MISSING' }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'PROTOCOL_SERVER_EVIDENCE_BOM_FORBIDDEN' }
    $evidenceContract = Read-WorkerJson $EvidenceContractPath 'PROTOCOL_WORKER_EVIDENCE_CONTRACT'
    $matchingPlugins = @($RuntimeContracts.manifest.plugins | Where-Object { [string]$_.id -eq [string]$Plan.plugin_id })
    if ($matchingPlugins.Count -ne 1) { throw 'PROTOCOL_WORKER_PLUGIN_NOT_IMPLEMENTED' }
    $required = @($evidenceContract.common_required_fields) + @($matchingPlugins[0].required_evidence_fields)
    $matchingRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $record = $line | ConvertFrom-Json }
        catch { throw 'PROTOCOL_SERVER_EVIDENCE_JSON_INVALID' }
        $identityMatches = $true
        foreach ($field in @('run_id','scenario_id','attempt_id','flow_id')) {
            if ($null -eq $record.PSObject.Properties[$field] -or [string]$record.$field -ne [string]$Plan.$field) { $identityMatches = $false; break }
        }
        if (-not $identityMatches) { continue }
        foreach ($field in $required) {
            if ($null -eq $record.PSObject.Properties[[string]$field]) { throw "PROTOCOL_SERVER_EVIDENCE_FIELD_MISSING: $field" }
        }
        if ([string]$record.phase -ne 'server') { throw 'PROTOCOL_SERVER_EVIDENCE_PHASE_INVALID' }
        if ([string]$record.protocol_family -ne [string]$Plan.protocol_family -or [string]$record.transport -ne [string]$Plan.transport) { throw 'PROTOCOL_SERVER_EVIDENCE_PROTOCOL_MISMATCH' }
        if ([string]$record.payload_sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'PROTOCOL_SERVER_EVIDENCE_HASH_INVALID' }
        $matchingRecords.Add($record)
    }
    return $matchingRecords.ToArray()
}

function Read-ProtocolServerEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$RuntimeContracts,
        [Parameter(Mandatory)][string]$EvidenceContractPath
    )
    $matchingRecords = @(Read-ProtocolServerEvidenceSet -Path $Path -Plan $Plan -RuntimeContracts $RuntimeContracts -EvidenceContractPath $EvidenceContractPath)
    if ($matchingRecords.Count -eq 0) { throw 'PROTOCOL_SERVER_EVIDENCE_IDENTITY_MISSING' }
    if ($matchingRecords.Count -ne 1) { throw 'PROTOCOL_SERVER_EVIDENCE_IDENTITY_DUPLICATE' }
    return $matchingRecords[0]
}

function Get-ProtocolWorkerLaunchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PythonExecutablePath,
        [Parameter(Mandatory)][string]$EntrypointPath,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$OutputJsonlPath,
        [Parameter(Mandatory)][int]$ProcessTimeoutMs
    )
    foreach ($path in @($PythonExecutablePath,$EntrypointPath,$ManifestPath,$PlanPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "PROTOCOL_WORKER_LAUNCH_ARTIFACT_MISSING: $path" }
    }
    if (Test-Path -LiteralPath $OutputJsonlPath) { throw 'PROTOCOL_WORKER_EVIDENCE_OUTPUT_EXISTS' }
    if ($ProcessTimeoutMs -le 0) { throw 'PROTOCOL_WORKER_PROCESS_TIMEOUT_INVALID' }
    return [pscustomobject][ordered]@{
        executable_path=[System.IO.Path]::GetFullPath($PythonExecutablePath)
        argument_list=@('-I','-B',$EntrypointPath,'--plan',$PlanPath,'--output-jsonl',$OutputJsonlPath,'--manifest',$ManifestPath)
        process_timeout_ms=$ProcessTimeoutMs
        expected_exit_code=0
        actual_path_required=$true
        environment_policy='allowlist'
    }
}

Export-ModuleMember -Function Import-ProtocolWorkerRuntimeContract, Test-ProtocolWorkerPlan, New-ProtocolWorkerPlan, Write-ProtocolWorkerPlan, Read-ProtocolWorkerEvidence, Read-ProtocolServerEvidenceSet, Read-ProtocolServerEvidence, Get-ProtocolWorkerLaunchPlan
