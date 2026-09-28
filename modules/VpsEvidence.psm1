Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProcessAdapter.psm1')
Import-Module (Join-Path $PSScriptRoot 'Report.psm1')

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function New-VpsEvidencePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ImportPath)
    return [pscustomobject][ordered]@{ mode='import-existing'; import_path=$ImportPath; requires_network=$false }
}

function New-VpsSshEvidencePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$OutputPath,
        [int]$TimeoutMs = 10000
    )
    return [pscustomobject][ordered]@{
        mode='ssh'; executable=$ExecutablePath; arguments=@($Arguments); output_path=$OutputPath
        timeout_ms=$TimeoutMs; requires_network=$true
    }
}

function Get-VpsEnvironmentValue {
    param([System.Collections.Generic.IDictionary[string, string]]$Environment, [string]$Name)
    if (-not $Environment.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace([string]$Environment[$Name])) { throw "VPS_ENVIRONMENT_MISSING_$Name" }
    return [string]$Environment[$Name]
}

function ConvertTo-PosixSingleQuoted {
    param([Parameter(Mandatory)][string]$Value)
    $quote = [string][char]39
    $escapedQuote = $quote + [string][char]92 + $quote + $quote
    return $quote + $Value.Replace($quote, $escapedQuote) + $quote
}

function New-VpsLogCursorPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [string]$SshExecutablePath = 'ssh.exe',
        [int]$TimeoutMs = 10000
    )
    if ($TimeoutMs -lt 1) { throw 'VPS_SSH_TIMEOUT_INVALID' }
    $hostName = Get-VpsEnvironmentValue $Environment 'PB_SSH_HOST'
    $userName = Get-VpsEnvironmentValue $Environment 'PB_SSH_USER'
    $keyPath = Get-VpsEnvironmentValue $Environment 'PB_SSH_KEY'
    $knownHosts = Get-VpsEnvironmentValue $Environment 'PB_SSH_KNOWN_HOSTS'
    $serverLog = Get-VpsEnvironmentValue $Environment 'PB_VPS_SERVER_LOG'
    if ($hostName -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]*$') { throw 'VPS_SSH_HOST_INVALID' }
    if ($userName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'VPS_SSH_USER_INVALID' }
    $port = 0
    if (-not [int]::TryParse((Get-VpsEnvironmentValue $Environment 'PB_SSH_PORT'), [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'VPS_SSH_PORT_INVALID' }
    $quotedLog = ConvertTo-PosixSingleQuoted $serverLog
    $remoteCommand = "inode=`$(stat -c %i -- $quotedLog) && size=`$(stat -c %s -- $quotedLog) && printf 'INODE=%s\nOFFSET=%s\n' `"`$inode`" `"`$size`""
    return [pscustomobject][ordered]@{
        mode='dynamic-ssh-cursor'; requires_network=$true
        process_plan=[pscustomobject][ordered]@{
            executable=$SshExecutablePath
            arguments=@('-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o',("UserKnownHostsFile=$knownHosts"),'-p',[string]$port,'-i',$keyPath,("$userName@$hostName"),$remoteCommand)
            timeout_ms=$TimeoutMs
        }
    }
}

function Invoke-VpsLogCursorPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$ProcessAdapter,
        [switch]$AllowProductRuntime
    )
    if ([string]$Plan.mode -ne 'dynamic-ssh-cursor') { throw 'VPS_CURSOR_PLAN_REQUIRED' }
    $result = Invoke-ProcessPlan -Plan $Plan.process_plan -ProcessAdapter $ProcessAdapter -AllowProductRuntime:$AllowProductRuntime
    if ([bool]$result.timed_out) { throw 'VPS_CURSOR_TIMEOUT' }
    if ([int]$result.exit_code -ne 0) { throw 'VPS_CURSOR_FAILED' }
    $values = @{}
    foreach ($line in @(([string]$result.stdout) -split "`r?`n")) {
        if ($line -match '^(INODE|OFFSET)=([0-9]+)$') { $values[$Matches[1]] = $Matches[2] }
    }
    if (-not $values.ContainsKey('INODE') -or -not $values.ContainsKey('OFFSET')) { throw 'VPS_CURSOR_OUTPUT_INVALID' }
    $offset = 0L
    if (-not [long]::TryParse([string]$values.OFFSET, [ref]$offset) -or $offset -lt 0) { throw 'VPS_CURSOR_OFFSET_INVALID' }
    return [pscustomobject][ordered]@{ inode=[string]$values.INODE; offset=$offset; captured_at_utc=[datetime]::UtcNow.ToString('o') }
}

function New-VpsDynamicEvidencePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$CanonicalRecords,
        [Parameter(Mandatory)][string]$EvidenceDirectory,
        [string]$SshExecutablePath = 'ssh.exe',
        [int]$TimeoutMs = 10000,
        $Cursor
    )
    if ($TimeoutMs -lt 1) { throw 'VPS_SSH_TIMEOUT_INVALID' }
    $hostName = Get-VpsEnvironmentValue $Environment 'PB_SSH_HOST'
    $userName = Get-VpsEnvironmentValue $Environment 'PB_SSH_USER'
    $keyPath = Get-VpsEnvironmentValue $Environment 'PB_SSH_KEY'
    $knownHosts = Get-VpsEnvironmentValue $Environment 'PB_SSH_KNOWN_HOSTS'
    $serverLog = Get-VpsEnvironmentValue $Environment 'PB_VPS_SERVER_LOG'
    if ($hostName -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]*$') { throw 'VPS_SSH_HOST_INVALID' }
    if ($userName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'VPS_SSH_USER_INVALID' }
    if ([string]::IsNullOrWhiteSpace($SshExecutablePath)) { throw 'VPS_SSH_EXECUTABLE_MISSING' }
    $port = 0
    if (-not [int]::TryParse((Get-VpsEnvironmentValue $Environment 'PB_SSH_PORT'), [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'VPS_SSH_PORT_INVALID' }
    $queries = [System.Collections.Generic.List[object]]::new()
    $identities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($record in @($CanonicalRecords | Sort-Object { [int]$_.sequence })) {
        $sha = ([string]$record.payload_sha256).ToLowerInvariant()
        if ($sha -notmatch '^[a-f0-9]{64}$') { throw 'VPS_QUERY_PAYLOAD_SHA_INVALID' }
        $phase = ([string]$record.phase).ToLowerInvariant()
        $sequence = [int]$record.sequence
        $identityKey = "$phase-$sequence"
        if ($phase -notmatch '^[a-z0-9_-]+$' -or $sequence -lt 1 -or -not $identities.Add($identityKey)) { throw "VPS_QUERY_IDENTITY_INVALID: $identityKey" }
        $outputPath = Join-Path $EvidenceDirectory ($identityKey + '-vps.jsonl')
        $quotedSha = ConvertTo-PosixSingleQuoted $sha
        $quotedLog = ConvertTo-PosixSingleQuoted $serverLog
        $remoteCommand = "grep -F -- $quotedSha $quotedLog; rc=`$?; if [ `$rc -eq 1 ]; then exit 0; else exit `$rc; fi"
        if ($null -ne $Cursor) {
            if ([string]$Cursor.inode -notmatch '^[0-9]+$' -or [long]$Cursor.offset -lt 0) { throw 'VPS_CURSOR_INVALID' }
            $startByte = [long]$Cursor.offset + 1
            $remoteCommand = "inode=`$(stat -c %i -- $quotedLog) && [ `"`$inode`" = '$($Cursor.inode)' ] && size=`$(stat -c %s -- $quotedLog) && [ `"`$size`" -ge '$($Cursor.offset)' ] && tail -c +$startByte -- $quotedLog | grep -F -- $quotedSha; rc=`$?; if [ `$rc -eq 1 ]; then exit 0; else exit `$rc; fi"
        }
        $arguments = @(
            '-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o',("UserKnownHostsFile=$knownHosts"),'-p',[string]$port,
            '-i',$keyPath,("$userName@$hostName"),$remoteCommand
        )
        $queries.Add([pscustomobject][ordered]@{
            phase=$phase; sequence=$sequence; test_id=[string]$record.test_id; run_id=[string]$record.run_id
            family=[string]$record.family; protocol=[string]$record.protocol
            sha256=$sha; expected_action=[string]$record.expected_action; output_path=$outputPath
            process_plan=[pscustomobject][ordered]@{ executable=$SshExecutablePath; arguments=$arguments; timeout_ms=$TimeoutMs }
        })
    }
    return [pscustomobject][ordered]@{ mode='dynamic-ssh'; requires_network=$true; cursor=$Cursor; queries=$queries.ToArray() }
}

function Assert-VpsEvidenceRecord {
    param($Record, [int]$LineNumber)
    foreach ($field in @('timestamp_utc', 'monotonic_ns', 'event', 'family', 'protocol', 'sha256', 'local_ip', 'local_port', 'remote_ip', 'remote_port', 'bytes', 'error', 'test_id', 'run_id', 'phase', 'sequence')) {
        if ($null -eq $Record.PSObject.Properties[$field]) { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber missing=$field" }
    }
    $timestamp = [datetimeoffset]::MinValue
    if ($Record.timestamp_utc -is [datetimeoffset]) { $timestamp = [datetimeoffset]$Record.timestamp_utc }
    elseif ($Record.timestamp_utc -is [datetime]) { $timestamp = [datetimeoffset]([datetime]$Record.timestamp_utc).ToUniversalTime() }
    elseif (-not [datetimeoffset]::TryParse([string]$Record.timestamp_utc, [ref]$timestamp)) { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber timestamp_utc" }
    $Record.timestamp_utc = $timestamp.UtcDateTime.ToString('o')
    $monotonic = 0L
    if (-not [long]::TryParse([string]$Record.monotonic_ns, [ref]$monotonic) -or $monotonic -lt 1) { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber monotonic_ns" }
    if ([string]$Record.event -notmatch '^[A-Z][A-Z0-9_]*$') { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber event" }
    if ([string]$Record.family -notin @('IPv4', 'IPv6')) { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber family" }
    if ([string]$Record.protocol -notin @('TCP', 'UDP')) { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber protocol" }
    if ([string]$Record.sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber sha256" }
    foreach ($identityField in @('test_id', 'run_id')) {
        if ([string]$Record.$identityField -notmatch '^[A-Za-z0-9._-]{1,128}$') { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber $identityField" }
    }
    if ([string]$Record.phase -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber phase" }
    $sequence = 0
    if (-not [int]::TryParse([string]$Record.sequence, [ref]$sequence) -or $sequence -lt 1) { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber sequence" }
    foreach ($portField in @('local_port', 'remote_port')) {
        $port = 0
        if (-not [int]::TryParse([string]$Record.$portField, [ref]$port) -or $port -lt 0 -or $port -gt 65535) { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber $portField" }
    }
    $bytes = 0L
    if (-not [long]::TryParse([string]$Record.bytes, [ref]$bytes) -or $bytes -lt 0) { throw "VPS_EVIDENCE_SCHEMA_INVALID line=$LineNumber bytes" }
}

function ConvertFrom-VpsJsonLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        $ExpectedIdentity
    )
    $records = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in $Lines) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $record = $line | ConvertFrom-Json }
        catch { throw "VPS_EVIDENCE_JSONL_INVALID line=$lineNumber" }
        if ($null -ne $ExpectedIdentity) {
            $payloadIdentityPresent = -not [string]::IsNullOrWhiteSpace([string]$record.test_id) -or
                -not [string]::IsNullOrWhiteSpace([string]$record.run_id) -or
                -not [string]::IsNullOrWhiteSpace([string]$record.phase) -or [int]$record.sequence -gt 0
            if (-not $payloadIdentityPresent) {
                foreach ($field in @('test_id','run_id','phase','sequence')) {
                    $record | Add-Member -NotePropertyName $field -NotePropertyValue $ExpectedIdentity.$field -Force
                }
                $record | Add-Member -NotePropertyName identity_source -NotePropertyValue 'cursor_exact_sha' -Force
            }
            elseif ($null -eq $record.PSObject.Properties['identity_source']) {
                $record | Add-Member -NotePropertyName identity_source -NotePropertyValue 'payload' -Force
            }
        }
        Assert-VpsEvidenceRecord -Record $record -LineNumber $lineNumber
        $records.Add($record)
    }
    return $records.ToArray()
}

function Import-VpsEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'VPS_EVIDENCE_IMPORT_NOT_FOUND' }
    return @(ConvertFrom-VpsJsonLines -Lines @([System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path))))
}

function Invoke-VpsImportEvidencePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExpectedShas
    )
    if ([string]$Plan.mode -ne 'import-existing') { throw 'VPS_IMPORT_PLAN_REQUIRED' }
    $records = @(Import-VpsEvidence -Path $Plan.import_path)
    return [pscustomobject][ordered]@{
        capture_complete=$true
        complete_shas=@($ExpectedShas | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
        records=$records
        query_results=@([pscustomobject]@{mode='import-existing';success=$true;record_count=$records.Count})
    }
}

function Invoke-VpsDynamicEvidencePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$ProcessAdapter,
        [System.Collections.Generic.IDictionary[string, string]]$Environment,
        [switch]$AllowProductRuntime
    )
    if ([string]$Plan.mode -ne 'dynamic-ssh') { throw 'VPS_DYNAMIC_PLAN_REQUIRED' }
    $allRecords = [System.Collections.Generic.List[object]]::new()
    $queryResults = [System.Collections.Generic.List[object]]::new()
    $completeShas = [System.Collections.Generic.List[string]]::new()
    foreach ($query in @($Plan.queries)) {
        try {
            $result = Invoke-ProcessPlan -Plan $query.process_plan -ProcessAdapter $ProcessAdapter -AllowProductRuntime:$AllowProductRuntime
        }
        catch {
            throw "VPS_SSH_PROCESS_FAILED: $($_.Exception.Message)"
        }
        $success = -not [bool]$result.timed_out -and [int]$result.exit_code -eq 0
        $recordCount = 0
        if ($success) {
            $directory = Split-Path -Parent ([string]$query.output_path)
            if (-not (Test-Path -LiteralPath $directory)) { $null = New-Item -ItemType Directory -Path $directory -Force }
            $records = @(ConvertFrom-VpsJsonLines -Lines @(([string]$result.stdout) -split "`r?`n") -ExpectedIdentity $query)
            [System.IO.File]::WriteAllText([string]$query.output_path, '', $script:Utf8NoBom)
            foreach ($record in $records) {
                if (-not [string]::Equals([string]$record.sha256, [string]$query.sha256, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'VPS_QUERY_NONEXACT_SHA_RECORD' }
                $allRecords.Add($record)
                if ($null -ne $Environment) { Add-RedactedJsonLine -Path ([string]$query.output_path) -Record $record -Environment $Environment }
                else { [System.IO.File]::AppendAllText([string]$query.output_path, (($record | ConvertTo-Json -Depth 30 -Compress) + [Environment]::NewLine), $script:Utf8NoBom) }
            }
            $recordCount = $records.Count
            $completeShas.Add(([string]$query.sha256).ToLowerInvariant())
        }
        $queryResults.Add([pscustomobject][ordered]@{
            phase=[string]$query.phase; sha256=[string]$query.sha256; success=$success
            timed_out=[bool]$result.timed_out; exit_code=[int]$result.exit_code; record_count=$recordCount
            output_path=[string]$query.output_path
        })
    }
    $complete = @($Plan.queries).Count -eq @($queryResults | Where-Object { [bool]$_.success }).Count
    return [pscustomobject][ordered]@{
        capture_complete=$complete; complete_shas=$completeShas.ToArray(); records=$allRecords.ToArray()
        query_results=$queryResults.ToArray()
    }
}

function Invoke-VpsEvidencePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        $ProcessAdapter,
        [switch]$AllowProductRuntime
    )
    switch ([string]$Plan.mode) {
        'import-existing' { return @(Import-VpsEvidence -Path $Plan.import_path) }
        'ssh' {
            if (-not $AllowProductRuntime) { throw 'VPS_SSH_RUNTIME_NOT_ALLOWED' }
            if ($null -eq $ProcessAdapter) { throw 'VPS_SSH_PROCESS_ADAPTER_REQUIRED' }
            $processPlan = [pscustomobject]@{ executable=$Plan.executable; arguments=@($Plan.arguments); timeout_ms=[int]$Plan.timeout_ms }
            $result = Invoke-ProcessPlan -Plan $processPlan -ProcessAdapter $ProcessAdapter -AllowProductRuntime
            if ($result.timed_out) { throw 'VPS_SSH_TIMEOUT' }
            if ([int]$result.exit_code -ne 0) { throw 'VPS_SSH_FAILED' }
            return @(Import-VpsEvidence -Path $Plan.output_path)
        }
        default { throw "VPS_EVIDENCE_MODE_UNSUPPORTED: $($Plan.mode)" }
    }
}

function Test-VpsPayloadEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records,
        [Parameter(Mandatory)][string]$Sha256,
        [ValidateSet('', 'TCP', 'UDP')][string]$Protocol = '',
        [int]$ExpectedReceived,
        [int]$ExpectedEchoed,
        [int]$ExpectedDestinationPort = 0,
        [string]$ExpectedSourceIp = '',
        [string]$ForbiddenSourceIp = '',
        [ValidateSet('', 'DIRECT', 'PROXY')][string]$ExpectedRoute = '',
        [string]$DirectEgressIp = '',
        [string]$ProxyEgressIp = ''
    )
    $matches = @($Records | Where-Object { [string]$_.sha256 -ieq $Sha256 })
    $receivedEvent = $(if ($Protocol -eq 'UDP') { 'RECEIVED' } elseif ($Protocol -eq 'TCP') { 'MESSAGE_RECEIVED' } else { '' })
    $receivedRecords = @($matches | Where-Object { [string]$_.event -eq $receivedEvent -or ([string]::IsNullOrWhiteSpace($receivedEvent) -and [string]$_.event -in @('MESSAGE_RECEIVED','RECEIVED')) })
    $echoedRecords = @($matches | Where-Object { [string]$_.event -eq 'ECHOED' })
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($receivedRecords.Count -ne $ExpectedReceived) { $errors.Add("received=$($receivedRecords.Count) expected=$ExpectedReceived") }
    if ($echoedRecords.Count -ne $ExpectedEchoed) { $errors.Add("echoed=$($echoedRecords.Count) expected=$ExpectedEchoed") }
    if ($ExpectedDestinationPort -gt 0 -and @($matches | Where-Object { [int]$_.local_port -ne $ExpectedDestinationPort }).Count -gt 0) { $errors.Add('destination port mismatch') }
    if ($ExpectedSourceIp -and @($matches | Where-Object { [string]$_.remote_ip -ne $ExpectedSourceIp }).Count -gt 0) { $errors.Add('source IP mismatch') }
    if ($ForbiddenSourceIp -and @($matches | Where-Object { [string]$_.remote_ip -eq $ForbiddenSourceIp }).Count -gt 0) { $errors.Add('forbidden source IP observed') }
    if ($ExpectedRoute -eq 'DIRECT') {
        if ([string]::IsNullOrWhiteSpace($DirectEgressIp)) { $errors.Add('direct egress proof unavailable') }
        elseif (@($receivedRecords | Where-Object { [string]$_.remote_ip -ne $DirectEgressIp }).Count -gt 0) { $errors.Add('wrong direct egress') }
    }
    if ($ExpectedRoute -eq 'PROXY') {
        if ([string]::IsNullOrWhiteSpace($ProxyEgressIp)) { $errors.Add('proxy egress proof unavailable') }
        elseif (@($receivedRecords | Where-Object { [string]$_.remote_ip -ne $ProxyEgressIp }).Count -gt 0) { $errors.Add('wrong proxy egress') }
        if ($DirectEgressIp -and @($receivedRecords | Where-Object { [string]$_.remote_ip -eq $DirectEgressIp }).Count -gt 0) { $errors.Add('direct leak') }
    }
    return [pscustomobject][ordered]@{
        passed=($errors.Count -eq 0); received=$receivedRecords.Count; echoed=$echoedRecords.Count
        matches=$matches; errors=$errors.ToArray()
    }
}

Export-ModuleMember -Function New-VpsEvidencePlan, New-VpsSshEvidencePlan, New-VpsLogCursorPlan, Invoke-VpsLogCursorPlan, New-VpsDynamicEvidencePlan, ConvertFrom-VpsJsonLines, Import-VpsEvidence, Invoke-VpsEvidencePlan, Invoke-VpsImportEvidencePlan, Invoke-VpsDynamicEvidencePlan, Test-VpsPayloadEvidence
