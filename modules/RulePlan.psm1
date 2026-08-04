Set-StrictMode -Version Latest

function New-RulePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Scenario, [Parameter(Mandatory)]$Profile)
    $rules = foreach ($rule in @($Profile.ProxyRules)) {
        [pscustomobject][ordered]@{
            name = $rule.Name; process_name = $rule.ProcessName; target_hosts = $rule.TargetHosts
            target_ports = $rule.TargetPorts; target_domains = $rule.TargetDomains
            protocol = $rule.Protocol; action = $rule.Action; enabled = $rule.IsEnabled; proxy_config_id = $rule.ProxyConfigId
        }
    }
    return [pscustomobject]@{
        scenario_id = $Scenario.scenario_id; reset_policy = $Scenario.reset_policy
        operation = 'replace-exact-rule-set'; rules = @($rules); readback_required = $true
    }
}

function Test-RulePlanEquivalent {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Expected, [Parameter(Mandatory)]$Actual)
    return (($Expected.rules | ConvertTo-Json -Depth 30 -Compress) -ceq ($Actual.rules | ConvertTo-Json -Depth 30 -Compress))
}

Export-ModuleMember -Function New-RulePlan, Test-RulePlanEquivalent
