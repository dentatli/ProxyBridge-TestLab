Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProfileValidator.psm1') -Force

# Contracts audited against Driver 63be0eb and v4.0.0 22e5344.
# This checks representability of a profile, not the installed product or route.
function Get-ProductProfileCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)][ValidateSet('driver','v4.0.0')][string]$Contract
    )

    $issues = [System.Collections.Generic.List[object]]::new()
    $validation = Test-ProxyBridgeProfile -Profile $Profile
    if (-not $validation.valid) {
        $issues.Add([pscustomobject]@{
            code='INVALID_CANONICAL_PROFILE'; field='profile'
            message_ru='Исправьте исходный профиль перед проверкой совместимости.'
            message_en='Correct the source profile before checking compatibility.'
        })
    }
    else {
        if (@($Profile.ProxyRules).Count -eq 0) {
            $issues.Add([pscustomobject]@{
                code='CLI_RULES_REQUIRED'; field='ProxyRules'
                message_ru='Для запуска CLI требуется хотя бы одно правило.'
                message_en='At least one rule is required to start the CLI.'
            })
        }
        # Both CLIs silently stop reading at these limits.
        if (@($Profile.ProxyConfigs).Count -gt 16 -or @($Profile.ProxyRules).Count -gt 256) {
            $issues.Add([pscustomobject]@{
                code='CLI_PROFILE_LIMIT_EXCEEDED'; field='profile'
                message_ru='CLI поддерживает не более 16 прокси и 256 правил.'
                message_en='The CLI supports at most 16 proxies and 256 rules.'
            })
        }
        if ($Contract -eq 'v4.0.0') {
            for ($index = 0; $index -lt @($Profile.ProxyRules).Count; $index++) {
                $domains = [string]$Profile.ProxyRules[$index].TargetDomains
                if (-not [string]::IsNullOrEmpty($domains) -and $domains -cne '*') {
                    $issues.Add([pscustomobject]@{
                        code='DOMAIN_RULE_UNSUPPORTED'; field="ProxyRules[$index].TargetDomains"
                        message_ru='CLI 4.0.0 не применяет доменное ограничение этого правила.'
                        message_en='The 4.0.0 CLI does not apply this domain rule constraint.'
                    })
                }
            }
            for ($index = 0; $index -lt @($Profile.ProxyConfigs).Count; $index++) {
                if ($Profile.ProxyConfigs[$index].SendDomainToProxy) {
                    $issues.Add([pscustomobject]@{
                        code='DOMAIN_FORWARDING_UNSUPPORTED'; field="ProxyConfigs[$index].SendDomainToProxy"
                        message_ru='Для общего сравнения явно выберите передачу IP-адресов прокси.'
                        message_en='Explicitly select IP destinations for a common comparison profile.'
                    })
                }
            }
        }
    }

    return [pscustomobject][ordered]@{
        contract=$Contract.ToLowerInvariant()
        scope='profile-format-only'
        profile_compatible=($issues.Count -eq 0)
        status=$(if ($issues.Count -eq 0) { 'PROFILE_COMPATIBLE' } else { 'NOT_COMPARABLE' })
        issues=$issues.ToArray()
        validation_errors=@($validation.errors)
        product_identity_verified=$false
        route_verified=$false
    }
}

function ConvertTo-ProductProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)][ValidateSet('driver','v4.0.0')][string]$Contract
    )

    $compatibility = Get-ProductProfileCompatibility -Profile $Profile -Contract $Contract
    if (-not $compatibility.profile_compatible) {
        throw "PRODUCT_PROFILE_NOT_COMPARABLE: $(@($compatibility.issues.code) -join ',')"
    }
    # Preserve the canonical object used by RulePlan and evidence assertions.
    $productProfile = $Profile | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    if ($Contract -eq 'v4.0.0') {
        foreach ($rule in @($productProfile.ProxyRules)) { $rule.PSObject.Properties.Remove('TargetDomains') }
        foreach ($proxy in @($productProfile.ProxyConfigs)) { $proxy.PSObject.Properties.Remove('SendDomainToProxy') }
    }
    return $productProfile
}

Export-ModuleMember -Function Get-ProductProfileCompatibility, ConvertTo-ProductProfile
