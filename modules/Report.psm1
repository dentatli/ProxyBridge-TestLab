Set-StrictMode -Version Latest

function New-DryRunReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputRoot)

    $runId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $runRoot = Join-Path $OutputRoot $runId
    $profileRoot = Join-Path $runRoot 'generated-profiles'
    $null = New-Item -ItemType Directory -Path $profileRoot -Force
    $transcriptPath = Join-Path $runRoot 'transcript.txt'
    $selectionPath = Join-Path $runRoot 'selection.jsonl'
    [System.IO.File]::WriteAllText($transcriptPath, '', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($selectionPath, '', [System.Text.UTF8Encoding]::new($false))

    return [pscustomobject]@{
        run_id             = $runId
        run_root           = $runRoot
        profile_root       = $profileRoot
        transcript_path    = $transcriptPath
        selection_path     = $selectionPath
        checksum_path      = Join-Path $runRoot 'SHA256SUMS'
    }
}

function Protect-SensitiveText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment
    )

    $safe = $Text
    $protectedValues = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($key in $Environment.Keys) {
        $value = [string]$Environment[$key]
        if ([string]::IsNullOrEmpty($value)) {
            continue
        }

        $alwaysProtect = [string]$key -match '(?i)(PASSWORD|USERNAME|SECRET|TOKEN|CREDENTIAL|SSH_(KEY|PATH)|(^|_)PATH$|_EXE$|_ROOT$|_LOG$|_HOST$|IPV4|IPV6|_IP$)'
        if ($alwaysProtect -or $value.Length -ge 4) {
            $null = $protectedValues.Add($value)
        }
    }

    foreach ($value in @($protectedValues | Sort-Object Length -Descending)) {
        $safe = $safe.Replace([string]$value, '[REDACTED]')
    }
    $safe = [regex]::Replace($safe, '(?i)\b(Username|Password)\s*[:=]\s*[^\s,;]+', '$1=[REDACTED]')
    $safe = [regex]::Replace($safe, '(?i)\b(SSH[_ -]?(Key|Path))\s*[:=]\s*[^\s,;]+', '$1=[REDACTED]')
    return $safe
}

function Add-Utf8NoBomLine {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
        try {
            $writer.WriteLine($Text)
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Write-SafeTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment
    )

    $safe = Protect-SensitiveText -Text $Message -Environment $Environment
    Add-Utf8NoBomLine -Path $Report.transcript_path -Text $safe
}

function Write-JsonReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    $json = $Value | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Add-SelectionRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment
    )

    $line = $Record | ConvertTo-Json -Depth 20 -Compress
    $safe = Protect-SensitiveText -Text $line -Environment $Environment
    Add-Utf8NoBomLine -Path $Report.selection_path -Text $safe
}

function Write-ChecksumReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Profiles
    )

    $lines = foreach ($profile in $Profiles) {
        $leaf = Split-Path -Leaf $profile.path
        "$($profile.sha256)  generated-profiles/$leaf"
    }
    [System.IO.File]::WriteAllLines($Report.checksum_path, @($lines), [System.Text.UTF8Encoding]::new($false))
}

Export-ModuleMember -Function New-DryRunReport, Write-SafeTranscript, Write-JsonReport, Add-SelectionRecord, Write-ChecksumReport
