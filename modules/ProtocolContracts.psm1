Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProtocolPropertyValue {
    param($InputObject, [string]$Name, $DefaultValue = $null)
    if ($null -eq $InputObject) { return $DefaultValue }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
}

function Read-ProtocolContractJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "TRAFFIC_CONTRACT_FILE_MISSING: $Path" }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { throw "TRAFFIC_CONTRACT_JSON_INVALID: $Path; $($_.Exception.Message)" }
}

function Add-UniqueProtocolId {
    param(
        [System.Collections.Generic.HashSet[string]]$Set,
        [string]$Value,
        [string]$MissingCode,
        [string]$DuplicateCode
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { throw $MissingCode }
    if (-not $Set.Add($Value)) { throw "${DuplicateCode}: $Value" }
}

function Import-TrafficProtocolContracts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigRoot)

    $root = [System.IO.Path]::GetFullPath($ConfigRoot)
    $capabilityModel = Read-ProtocolContractJson (Join-Path $root 'traffic-capability-model.json')
    $evidenceContract = Read-ProtocolContractJson (Join-Path $root 'protocol-evidence-contract.json')
    $familyCatalog = Read-ProtocolContractJson (Join-Path $root 'protocol-families.json')
    $runProfiles = Read-ProtocolContractJson (Join-Path $root 'traffic-run-profiles.json')
    $roadmap = Read-ProtocolContractJson (Join-Path $root 'deferred-scenario-roadmap.json')

    foreach ($document in @($capabilityModel, $evidenceContract, $familyCatalog, $runProfiles, $roadmap)) {
        if ([int](Get-ProtocolPropertyValue $document 'schema_version' 0) -ne 1) { throw 'TRAFFIC_CONTRACT_SCHEMA_UNSUPPORTED' }
    }

    $capabilityIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($capability in @($capabilityModel.capabilities)) {
        $id = [string](Get-ProtocolPropertyValue $capability 'id' '')
        Add-UniqueProtocolId $capabilityIds $id 'TRAFFIC_CAPABILITY_ID_MISSING' 'TRAFFIC_CAPABILITY_DUPLICATE'
        if (@('local','server','control','topology','product') -notcontains [string]$capability.scope) { throw "TRAFFIC_CAPABILITY_SCOPE_INVALID: $id" }
        if ([string]::IsNullOrWhiteSpace([string]$capability.probe) -or [string]::IsNullOrWhiteSpace([string]$capability.evidence)) { throw "TRAFFIC_CAPABILITY_PROBE_INCOMPLETE: $id" }
    }

    $profileIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($profile in @($evidenceContract.profiles)) {
        $id = [string](Get-ProtocolPropertyValue $profile 'id' '')
        Add-UniqueProtocolId $profileIds $id 'TRAFFIC_EVIDENCE_PROFILE_ID_MISSING' 'TRAFFIC_EVIDENCE_PROFILE_DUPLICATE'
        $requiredFields = @($profile.required_fields | ForEach-Object { [string]$_ })
        if ($requiredFields.Count -eq 0) { throw "TRAFFIC_EVIDENCE_PROFILE_EMPTY: $id" }
        if (@($requiredFields | Sort-Object -Unique).Count -ne $requiredFields.Count) { throw "TRAFFIC_EVIDENCE_FIELD_DUPLICATE: $id" }
        if (@($requiredFields | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw "TRAFFIC_EVIDENCE_FIELD_EMPTY: $id" }
    }

    $commonFields = @($evidenceContract.common_required_fields | ForEach-Object { [string]$_ })
    if (@($commonFields | Sort-Object -Unique).Count -ne $commonFields.Count) { throw 'TRAFFIC_COMMON_EVIDENCE_FIELD_DUPLICATE' }
    foreach ($field in @('run_id','scenario_id','attempt_id','flow_id','process_id','socket_id','payload_sha256','timestamp_utc','monotonic_ms')) {
        if ($commonFields -notcontains $field) { throw "TRAFFIC_COMMON_EVIDENCE_FIELD_MISSING: $field" }
    }
    $mandatoryChannels = @($evidenceContract.mandatory_channels | ForEach-Object { [string]$_ })
    foreach ($channel in @('client','server','route','lifecycle','cleanup')) {
        if ($mandatoryChannels -notcontains $channel) { throw "TRAFFIC_MANDATORY_CHANNEL_MISSING: $channel" }
    }

    $allowedStatuses = @($familyCatalog.delivery_statuses | ForEach-Object { [string]$_ })
    $familyIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $familyById = @{}
    foreach ($family in @($familyCatalog.families)) {
        $id = [string](Get-ProtocolPropertyValue $family 'id' '')
        Add-UniqueProtocolId $familyIds $id 'TRAFFIC_PROTOCOL_FAMILY_ID_MISSING' 'TRAFFIC_PROTOCOL_FAMILY_DUPLICATE'
        $familyById[$id] = $family
        $status = [string](Get-ProtocolPropertyValue $family 'delivery_status' '')
        if ($allowedStatuses -notcontains $status) { throw "TRAFFIC_PROTOCOL_STATUS_INVALID: $id" }
        if ([bool](Get-ProtocolPropertyValue $family 'external_account_required' $false)) { throw "TRAFFIC_EXTERNAL_ACCOUNT_FORBIDDEN: $id" }
        if ($status -eq 'UNSUPPORTED_PRODUCT_SCOPE') {
            if (-not [string]::IsNullOrWhiteSpace([string]$family.worker_id) -or -not [string]::IsNullOrWhiteSpace([string]$family.server_plugin_id)) { throw "TRAFFIC_UNSUPPORTED_HAS_WORKER: $id" }
            if ([string]::IsNullOrWhiteSpace([string](Get-ProtocolPropertyValue $family 'reason' ''))) { throw "TRAFFIC_UNSUPPORTED_REASON_MISSING: $id" }
            continue
        }
        foreach ($field in @('worker_id','server_plugin_id','evidence_profile_id')) {
            if ([string]::IsNullOrWhiteSpace([string](Get-ProtocolPropertyValue $family $field ''))) { throw "TRAFFIC_PROTOCOL_EXECUTION_FIELD_MISSING: $id/$field" }
        }
        if (-not $profileIds.Contains([string]$family.evidence_profile_id)) { throw "TRAFFIC_EVIDENCE_PROFILE_UNKNOWN: $id/$($family.evidence_profile_id)" }
        foreach ($capabilityId in @($family.required_capabilities | ForEach-Object { [string]$_ })) {
            if (-not $capabilityIds.Contains($capabilityId)) { throw "TRAFFIC_CAPABILITY_UNKNOWN: $id/$capabilityId" }
        }
        if ($status -eq 'PLANNED_EXECUTABLE' -and ([int]$family.milestone -lt 9 -or [int]$family.milestone -gt 20)) { throw "TRAFFIC_PROTOCOL_MILESTONE_INVALID: $id" }
    }

    $runProfileIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $previousDuration = 0
    foreach ($profile in @($runProfiles.profiles)) {
        $id = [string](Get-ProtocolPropertyValue $profile 'id' '')
        Add-UniqueProtocolId $runProfileIds $id 'TRAFFIC_RUN_PROFILE_ID_MISSING' 'TRAFFIC_RUN_PROFILE_DUPLICATE'
        $duration = [int](Get-ProtocolPropertyValue $profile 'max_duration_minutes' 0)
        if ($duration -le $previousDuration -or $duration -gt 4320) { throw "TRAFFIC_RUN_PROFILE_DURATION_INVALID: $id" }
        if (-not [bool](Get-ProtocolPropertyValue $profile 'resume_enabled' $false)) { throw "TRAFFIC_RUN_PROFILE_RESUME_REQUIRED: $id" }
        if (@($profile.includes).Count -eq 0) { throw "TRAFFIC_RUN_PROFILE_CONTENT_EMPTY: $id" }
        $previousDuration = $duration
    }

    $roadmapScenarioIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $allowedResolutions = @('PROTOCOL_TRAFFIC','CONTROLLED_EQUIVALENCE','FAILURE_INJECTION','SYSTEM_CHECK','PERFORMANCE','PRODUCT_CONTRACT_REQUIRED','CAPABILITY_GATED')
    foreach ($entry in @($roadmap.entries)) {
        $scenarioId = [string](Get-ProtocolPropertyValue $entry 'scenario_id' '')
        Add-UniqueProtocolId $roadmapScenarioIds $scenarioId 'TRAFFIC_ROADMAP_SCENARIO_ID_MISSING' 'TRAFFIC_ROADMAP_SCENARIO_DUPLICATE'
        $familyId = [string](Get-ProtocolPropertyValue $entry 'target_family' '')
        if (-not $familyIds.Contains($familyId)) { throw "TRAFFIC_ROADMAP_FAMILY_UNKNOWN: $scenarioId/$familyId" }
        if ([string]$familyById[$familyId].delivery_status -eq 'UNSUPPORTED_PRODUCT_SCOPE') { throw "TRAFFIC_ROADMAP_FAMILY_UNSUPPORTED: $scenarioId/$familyId" }
        if ($allowedResolutions -notcontains [string]$entry.resolution) { throw "TRAFFIC_ROADMAP_RESOLUTION_INVALID: $scenarioId" }
        if ([int]$entry.target_milestone -lt 9 -or [int]$entry.target_milestone -gt 20) { throw "TRAFFIC_ROADMAP_MILESTONE_INVALID: $scenarioId" }
        foreach ($capabilityId in @((Get-ProtocolPropertyValue $entry 'required_capabilities' @()) | ForEach-Object { [string]$_ })) {
            if (-not $capabilityIds.Contains($capabilityId)) { throw "TRAFFIC_ROADMAP_CAPABILITY_UNKNOWN: $scenarioId/$capabilityId" }
        }
    }

    return [pscustomobject][ordered]@{
        capability_model = $capabilityModel
        evidence_contract = $evidenceContract
        family_catalog = $familyCatalog
        run_profiles = $runProfiles
        roadmap = $roadmap
        capability_count = $capabilityIds.Count
        evidence_profile_count = $profileIds.Count
        family_count = $familyIds.Count
        roadmap_count = $roadmapScenarioIds.Count
    }
}

Export-ModuleMember -Function Import-TrafficProtocolContracts
