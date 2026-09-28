[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ScenarioRoot,
    [Parameter(Mandatory)][string]$KnownDefectsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\modules\Config.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\modules\ScenarioCatalog.psm1') -Force

$scenarios = @(Import-ScenarioCatalog -ScenarioRoot $ScenarioRoot)
$knownDefects = Import-KnownDefectsConfig -Path $KnownDefectsPath

$projection = foreach ($scenario in $scenarios) {
    $knownDefect = Get-KnownDefectMatch -Scenario $scenario -KnownDefects $knownDefects
    [pscustomobject][ordered]@{
        scenario_id = [string]$scenario.scenario_id
        title = [string]$scenario.title
        enabled = [bool]$scenario.enabled
        implementation_status = [string]$scenario.implementation_status
        implementation_reason = [string]$scenario.implementation_reason
        coverage_group = [string]$scenario.coverage_group
        executor_kind = [string]$(if ($null -eq $scenario.PSObject.Properties['executor_kind']) { 'native-client' } else { $scenario.executor_kind })
        protocol_family = [string]$(if ($null -eq $scenario.PSObject.Properties['protocol_worker'] -or $null -eq $scenario.protocol_worker) { '' } else { $scenario.protocol_worker.protocol_family })
        evidence_profile_id = [string]$(if ($null -eq $scenario.PSObject.Properties['protocol_worker'] -or $null -eq $scenario.protocol_worker) { 'raw-stream' } else { $scenario.protocol_worker.evidence_profile_id })
        protocol = [string]$scenario.client.protocol
        family = [int]$scenario.client.family
        action = [string]$scenario.client.expected_action
        socket_mode = [string]$scenario.client.socket_mode
        independent = [bool]$scenario.independent
        reset_policy = [string]$scenario.reset_policy
        known_defect = $(if ($null -eq $knownDefect) { $null } else {
            [pscustomobject][ordered]@{
                id = [string]$knownDefect.id
                policy = [string]$knownDefect.policy
                expected_status = [string]$knownDefect.expected_status
                reason = [string]$knownDefect.reason
            }
        })
        tags = @($scenario.tags | ForEach-Object { [string]$_ })
        requires = @($scenario.requires | ForEach-Object { [string]$_ })
        assertions = @($scenario.assertions | ForEach-Object { [string]$_ })
    }
}

ConvertTo-Json -InputObject @($projection) -Depth 12 -Compress
