Set-StrictMode -Version Latest

function Import-DotEnv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Environment file not found."
    }

    $variables = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($line in [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path))) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }

        $separatorIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 0) {
            throw "Invalid environment entry: expected NAME=VALUE."
        }

        $name = $line.Substring(0, $separatorIndex).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Environment variable name cannot be empty."
        }
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid environment variable name '$name'."
        }
        if ($variables.ContainsKey($name)) {
            throw "Duplicate environment variable '$name'."
        }

        # Deliberately do not unquote, expand, or normalize the value. This keeps
        # Windows backslashes and any additional '=' characters byte-for-byte.
        $variables.Add($name, $line.Substring($separatorIndex + 1))
    }

    return ,$variables
}

function Get-EnvironmentValueCategory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    switch -Regex ($Name) {
        '(?i)(PASSWORD|USERNAME|SECRET|TOKEN|CREDENTIAL)' { return 'credential' }
        '(?i)(SSH_KEY|PATH|_EXE$|_ROOT$|_LOG$)' { return 'path' }
        '(?i)(_PORT$)' { return 'port' }
        '(?i)(IPV4|IPV6|_IP$)' { return 'address' }
        '(?i)(_HOST$)' { return 'host' }
        '(?i)(SHA256|_HASH$)' { return 'hash' }
        default { return 'string' }
    }
}

function Get-EnvironmentSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.IDictionary[string, string]]$Environment
    )

    $summary = foreach ($name in ($Environment.Keys | Sort-Object)) {
        [pscustomobject]@{
            key      = $name
            present  = -not [string]::IsNullOrEmpty($Environment[$name])
            category = Get-EnvironmentValueCategory -Name $name
        }
    }

    return ,@($summary)
}

Export-ModuleMember -Function Import-DotEnv, Get-EnvironmentSummary
