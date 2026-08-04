Set-StrictMode -Version Latest

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-ProtectedEnvironmentValues {
    param([System.Collections.Generic.IDictionary[string, string]]$Environment)
    $values = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($key in $Environment.Keys) {
        $value = [string]$Environment[$key]
        if ([string]::IsNullOrEmpty($value)) { continue }
        if ($value.Length -ge 4) {
            $null = $values.Add($value)
            $null = $values.Add($value.Replace('\', '\\'))
            $json = $value | ConvertTo-Json -Compress
            if ($json.Length -ge 2) { $null = $values.Add($json.Substring(1, $json.Length - 2)) }
        }
    }
    return @($values | Where-Object { $_.Length -gt 0 } | Sort-Object Length -Descending)
}

function Protect-SensitiveText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment
    )
    $safe = $Text
    foreach ($value in @(Get-ProtectedEnvironmentValues -Environment $Environment)) {
        $safe = $safe.Replace([string]$value, '[REDACTED]')
    }
    $sensitiveKeyNames = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Environment.Keys | Sort-Object Length -Descending)) {
        if ([string]$key -match '(?i)(PASSWORD|USERNAME|_USER$|SECRET|TOKEN|CREDENTIAL|SSH_(KEY|PATH)|_EXE$|_ROOT$|_LOG$|_HOST$|IPV4|IPV6|_IP$)') { $sensitiveKeyNames.Add([regex]::Escape([string]$key)) }
    }
    foreach ($generic in @('Password','Username','User','Secret','Token','Credential','SSH_Key','SSH_Path')) { $sensitiveKeyNames.Add([regex]::Escape($generic)) }
    $names = @($sensitiveKeyNames | Select-Object -Unique) -join '|'
    $prefix = '(?<prefix>"?(?:' + $names + ')"?\s*[:=]\s*)'
    $safe = [regex]::Replace($safe, '(?i)' + $prefix + '"(?:\\.|[^"])*"', '${prefix}"[REDACTED]"')
    $safe = [regex]::Replace($safe, '(?i)' + $prefix + '[^"\s,;}]+' , '${prefix}[REDACTED]')
    return $safe
}

function Write-Utf8Atomic {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { $null = New-Item -ItemType Directory -Path $directory -Force }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $backup = "$Path.$([guid]::NewGuid().ToString('N')).bak"
    [System.IO.File]::WriteAllText($temporary, $Text, $script:Utf8NoBom)
    try {
        if (Test-Path -LiteralPath $Path) { [System.IO.File]::Replace($temporary, $Path, $backup, $true) }
        else { [System.IO.File]::Move($temporary, $Path) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
        if (Test-Path -LiteralPath $backup) { [System.IO.File]::Delete($backup) }
    }
}

function Add-Utf8NoBomLine {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { $null = New-Item -ItemType Directory -Path $directory -Force }
    [System.IO.File]::AppendAllText($Path, $Text + [Environment]::NewLine, $script:Utf8NoBom)
}

function New-RunReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputRoot, [string]$RunId)
    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8)) }
    $root = Join-Path $OutputRoot $RunId
    $profiles = Join-Path $root 'generated-profiles'
    $scenarios = Join-Path $root 'scenarios'
    $null = New-Item -ItemType Directory -Path $profiles -Force
    $null = New-Item -ItemType Directory -Path $scenarios -Force
    $report = [pscustomobject]@{
        run_id = $RunId; run_root = $root; profile_root = $profiles; scenario_root = $scenarios
        transcript_path = Join-Path $root 'transcript.txt'; selection_path = Join-Path $root 'selection.jsonl'
        results_path = Join-Path $root 'results.jsonl'; failures_path = Join-Path $root 'failures.jsonl'
        skipped_path = Join-Path $root 'skipped.jsonl'; checksum_path = Join-Path $root 'SHA256SUMS'
    }
    foreach ($path in @($report.transcript_path, $report.selection_path, $report.results_path, $report.failures_path, $report.skipped_path)) { Write-Utf8Atomic -Path $path -Text '' }
    return $report
}

function New-DryRunReport { param([Parameter(Mandatory)][string]$OutputRoot) return New-RunReport -OutputRoot $OutputRoot }

function Write-SafeTranscript {
    param($Report, [string]$Message, [System.Collections.Generic.IDictionary[string, string]]$Environment)
    Add-Utf8NoBomLine -Path $Report.transcript_path -Text (Protect-SensitiveText -Text $Message -Environment $Environment)
}

function Write-RedactedJsonReport {
    param($Value, [string]$Path, [System.Collections.Generic.IDictionary[string, string]]$Environment)
    $json = $Value | ConvertTo-Json -Depth 100
    Write-Utf8Atomic -Path $Path -Text ((Protect-SensitiveText -Text $json -Environment $Environment) + [Environment]::NewLine)
}

function Write-JsonReport {
    param($Value, [string]$Path, [System.Collections.Generic.IDictionary[string, string]]$Environment)
    if ($null -eq $Environment) { $Environment = [System.Collections.Generic.Dictionary[string, string]]::new() }
    Write-RedactedJsonReport -Value $Value -Path $Path -Environment $Environment
}

function Add-RedactedJsonLine {
    param([string]$Path, $Record, [System.Collections.Generic.IDictionary[string, string]]$Environment)
    $line = $Record | ConvertTo-Json -Depth 30 -Compress
    Add-Utf8NoBomLine -Path $Path -Text (Protect-SensitiveText -Text $line -Environment $Environment)
}

function Add-SelectionRecord { param($Report, $Record, [System.Collections.Generic.IDictionary[string, string]]$Environment) Add-RedactedJsonLine -Path $Report.selection_path -Record $Record -Environment $Environment }

function Add-ResultRecord {
    param($Report, $Record, [System.Collections.Generic.IDictionary[string, string]]$Environment)
    Add-RedactedJsonLine -Path $Report.results_path -Record $Record -Environment $Environment
    if (@('FAIL_PRODUCT', 'FAIL_HARNESS', 'FAIL_INFRASTRUCTURE', 'CONTAMINATED') -contains [string]$Record.status) { Add-RedactedJsonLine -Path $Report.failures_path -Record $Record -Environment $Environment }
    if ([string]$Record.status -match '^(SKIPPED|BLOCKED|UNSUPPORTED)') { Add-RedactedJsonLine -Path $Report.skipped_path -Record $Record -Environment $Environment }
}

function Write-RunSummary {
    param(
        $Report,
        [object[]]$Records,
        [object[]]$AllScenarios,
        [System.Collections.Generic.IDictionary[string, string]]$Environment,
        [ValidateSet('dry-run','mock','real')][string]$RunMode = 'dry-run'
    )
    $csv = [System.Collections.Generic.List[string]]::new()
    $csv.Add('run_mode,scenario_id,implementation_status,status,attempt,duration_ms')
    foreach ($record in $Records) { $csv.Add(('"{0}","{1}","{2}","{3}",{4},{5}' -f $RunMode, $record.scenario_id, $record.implementation_status, $record.status, $record.attempt, $record.duration_ms)) }
    Write-Utf8Atomic -Path (Join-Path $Report.run_root 'summary.csv') -Text ((Protect-SensitiveText -Text ($csv -join [Environment]::NewLine) -Environment $Environment) + [Environment]::NewLine)

    $catalogSummary = [pscustomobject][ordered]@{
        declared = @($AllScenarios).Count
        executable = @($AllScenarios | Where-Object { [string]$_.implementation_status -eq 'EXECUTABLE' }).Count
        declarative = @($AllScenarios | Where-Object { [string]$_.implementation_status -eq 'DECLARATIVE_ONLY' }).Count
        unsupported = @($AllScenarios | Where-Object { [string]$_.implementation_status -eq 'UNSUPPORTED_PRODUCT_SCOPE' }).Count
        selected = @($Records | Where-Object { $null -ne $_.PSObject.Properties['selected'] -and [bool]$_.selected } | Select-Object -ExpandProperty scenario_id -Unique).Count
        dry_run_records = @($Records | Where-Object { [string]$_.status -in @('DRY_RUN_READY','NOT_IMPLEMENTED') }).Count
        mock_records = @($Records | Where-Object { [string]$_.status -match '^MOCK_' }).Count
        real_records = $(if ($RunMode -eq 'real') { @($Records | Where-Object { [int]$_.attempt -gt 0 }).Count } else { 0 })
    }
    $summary = [pscustomobject][ordered]@{
        schema_version = 1
        run_mode = $RunMode
        catalog = $catalogSummary
        statuses = @($Records | Group-Object status | Sort-Object Name | ForEach-Object { [pscustomobject]@{ status=$_.Name; count=$_.Count; run_mode=$RunMode } })
    }
    Write-RedactedJsonReport -Value $summary -Path (Join-Path $Report.run_root 'summary.json') -Environment $Environment

    $coverage = foreach ($group in @($AllScenarios | Group-Object coverage_group | Sort-Object Name)) {
        $groupRecords = @($Records | Where-Object { $_.coverage_group -eq $group.Name })
        $normalized = foreach ($record in $groupRecords) {
            $coverageStatus = [string]$record.status
            if ($RunMode -eq 'real') {
                if ($coverageStatus -eq 'PASS') { $coverageStatus = 'TESTED_PASS' }
                elseif ($coverageStatus -eq 'FAIL_PRODUCT') { $coverageStatus = 'TESTED_FAIL' }
            }
            [pscustomobject]@{ status=$coverageStatus; implementation_status=[string]$record.implementation_status; run_mode=$RunMode }
        }
        [pscustomobject][ordered]@{
            group=$group.Name; run_mode=$RunMode; declared=$group.Count
            executable=@($group.Group | Where-Object { [string]$_.implementation_status -eq 'EXECUTABLE' }).Count
            declarative=@($group.Group | Where-Object { [string]$_.implementation_status -eq 'DECLARATIVE_ONLY' }).Count
            unsupported=@($group.Group | Where-Object { [string]$_.implementation_status -eq 'UNSUPPORTED_PRODUCT_SCOPE' }).Count
            selected=@($groupRecords | Where-Object { $null -ne $_.PSObject.Properties['selected'] -and [bool]$_.selected } | Select-Object -ExpandProperty scenario_id -Unique).Count
            results=@($normalized | Group-Object status | Sort-Object Name | ForEach-Object { [pscustomobject]@{status=$_.Name;count=$_.Count;run_mode=$RunMode} })
        }
    }
    Write-RedactedJsonReport -Value ([pscustomobject]@{schema_version=1;run_mode=$RunMode;catalog=$catalogSummary;groups=@($coverage)}) -Path (Join-Path $Report.run_root 'coverage.json') -Environment $Environment
}

function Write-ChecksumReport {
    param($Report, [object[]]$Profiles)
    $lines = foreach ($profile in @($Profiles)) { "$($profile.sha256)  generated-profiles/$(Split-Path -Leaf $profile.path)" }
    Write-Utf8Atomic -Path $Report.checksum_path -Text ($(if (@($lines).Count -gt 0) { (@($lines) -join [Environment]::NewLine) + [Environment]::NewLine } else { '' }))
}

function Complete-RunChecksums {
    param($Report)
    $lines = foreach ($file in @(Get-ChildItem -LiteralPath $Report.run_root -Recurse -File | Where-Object { $_.FullName -ne $Report.checksum_path } | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($Report.run_root.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
    Write-Utf8Atomic -Path $Report.checksum_path -Text ((@($lines) -join [Environment]::NewLine) + [Environment]::NewLine)
}

Export-ModuleMember -Function Protect-SensitiveText, New-RunReport, New-DryRunReport, Write-SafeTranscript, Write-JsonReport, Write-RedactedJsonReport, Add-RedactedJsonLine, Add-SelectionRecord, Add-ResultRecord, Write-RunSummary, Write-ChecksumReport, Complete-RunChecksums
