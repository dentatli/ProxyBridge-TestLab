Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ProcessAdapter.psm1')

function ConvertFrom-ProxyBridgeDestination {
    param([string]$Destination)
    $ip = $Destination
    $port = 0
    if ($Destination -match '^\[(?<ip>[^\]]+)\]:(?<port>[0-9]{1,5})$') {
        $ip = $Matches.ip; $port = [int]$Matches.port
    }
    elseif ($Destination -match '^(?<ip>.+):(?<port>[0-9]{1,5})$') {
        $ip = $Matches.ip; $port = [int]$Matches.port
    }
    return [pscustomobject]@{ ip=$ip; port=$port }
}

function ConvertFrom-ProxyBridgeLocalEndpoint {
    param([string]$Endpoint)
    if ([string]::IsNullOrWhiteSpace($Endpoint)) { return [pscustomobject]@{ ip=''; port=0 } }
    $parsedEndpoint = ConvertFrom-ProxyBridgeDestination -Destination $Endpoint
    $parsedIp = $null
    if ([int]$parsedEndpoint.port -lt 1 -or [int]$parsedEndpoint.port -gt 65535 -or
        -not [System.Net.IPAddress]::TryParse([string]$parsedEndpoint.ip, [ref]$parsedIp)) {
        return [pscustomobject]@{ ip=''; port=0 }
    }
    return [pscustomobject]@{ ip=$parsedIp.ToString(); port=[int]$parsedEndpoint.port }
}

function Get-ProxyBridgeLineMetadata {
    param([string]$Line, [datetime]$DefaultTimestampUtc)
    $text = $Line.Trim()
    $timestamp = $DefaultTimestampUtc
    $localTime = ''
    if ($text -match '^(?<timestamp>[0-9]{4}-[0-9]{2}-[0-9]{2}T[^\s]+Z)\s+(?<rest>.+)$') {
        $parsedTimestamp = [datetime]::MinValue
        if ([datetime]::TryParse($Matches.timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsedTimestamp)) { $timestamp = $parsedTimestamp.ToUniversalTime() }
        $text = $Matches.rest
    }
    elseif ($text -match '^\[(?<local_time>[0-9]{2}:[0-9]{2}:[0-9]{2})\]\s*(?<rest>.+)$') {
        $localTime = [string]$Matches.local_time
        $text = [string]$Matches.rest
    }
    # Official CLIs prefix their connection and core-log callbacks this way.
    # Preserve the original line in the record, but parse its actual payload.
    if ($text -match '^\[(?:CONN|LOG)\]\s+(?<payload>.*)$') { $text = [string]$Matches.payload }
    return [pscustomobject]@{ text=$text; timestamp=$timestamp; local_time=$localTime }
}

function ConvertFrom-ProxyBridgeTextLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [datetime]$DefaultTimestampUtc = ([datetime]::MinValue)
    )
    $records = [System.Collections.Generic.List[object]]::new()
    $index = 0
    while ($index -lt @($Lines).Count) {
        $line = [string]$Lines[$index]
        $index++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $metadata = Get-ProxyBridgeLineMetadata -Line $line -DefaultTimestampUtc $DefaultTimestampUtc
        $text = [string]$metadata.text
        $observedAt = $(if ($metadata.timestamp -eq [datetime]::MinValue) { '' } else { $metadata.timestamp.ToString('o') })

        if ($text -match '^(?<process>.+?)(?:\s+\((?:PID:)?\s*(?<pid>[0-9]+)\))?(?:\s+from\s+(?<local>\[[^\]]+\]:[0-9]+|\S+:[0-9]+))?\s+->\s+(?<destination>\[[^\]]+\]:[0-9]+|\S+:[0-9]+)\s+via\s+(?<route>Direct(?:\s+\(UDP\))?|Blocked(?:\s+\(UDP\))?|Proxy(?:\s+.*)?)$') {
            $routeProcess = [string]$Matches['process']
            $routePidText = $(if ($Matches.ContainsKey('pid')) { [string]$Matches['pid'] } else { '' })
            $localText = $(if ($Matches.ContainsKey('local')) { [string]$Matches['local'] } else { '' })
            $destinationText = [string]$Matches['destination']
            $routeText = [string]$Matches['route']
            $local = ConvertFrom-ProxyBridgeLocalEndpoint -Endpoint $localText
            $destination = ConvertFrom-ProxyBridgeDestination -Destination $destinationText
            $action = $(if ($routeText -match '^Direct') { 'DIRECT' } elseif ($routeText -match '^Blocked') { 'BLOCK' } else { 'PROXY' })
            $routePid = $(if (-not [string]::IsNullOrWhiteSpace($routePidText)) { [int]$routePidText } else { 0 })
            $record = [pscustomobject][ordered]@{
                event='ROUTE_DECISION'; observed_at_utc=$observedAt; observed_local_time=[string]$metadata.local_time
                process=$routeProcess; pid=$routePid
                local_ip=[string]$local.ip; local_port=[int]$local.port
                destination_ip=[string]$destination.ip; destination_port=[int]$destination.port
                action=$action; route_detail=$routeText; raw_line=$line
            }
            if ($routeText -match '(?i)\b(?:ProxyConfigId|proxy_config_id)\s*=\s*(?<config_id>[0-9]+)') {
                $record | Add-Member -NotePropertyName proxy_config_id -NotePropertyValue ([int]$Matches.config_id)
            }
            $records.Add($record)
            continue
        }

        if ($text -match '^\[RELAY\]\s+accepted redirect:?\s*(?<rest>.*)$') {
            $rawLines = [System.Collections.Generic.List[string]]::new()
            $rawLines.Add($line)
            $relayText = [string]$Matches.rest
            while ($index -lt @($Lines).Count) {
                $candidate = [string]$Lines[$index]
                $candidateMetadata = Get-ProxyBridgeLineMetadata -Line $candidate -DefaultTimestampUtc $DefaultTimestampUtc
                if ([string]$candidateMetadata.text -notmatch '^(?:(?:process|pid|dest|destination|action|cfg)\s*=)') { break }
                $rawLines.Add($candidate)
                $relayText += ' ' + [string]$candidateMetadata.text
                $index++
            }
            $relayProcess = ''
            $relayPid = 0
            $relayDestination = ''
            $relayAction = ''
            $relayConfigId = $null
            if ($relayText -match '(?i)(?:^|\s)process=(?<value>\S+)') { $relayProcess = [string]$Matches.value }
            if ($relayText -match '(?i)(?:^|\s)pid=(?<value>[0-9]+)') { $relayPid = [int]$Matches.value }
            if ($relayText -match '(?i)(?:^|\s)(?:dest|destination)=(?<value>\[[^\]]+\]:[0-9]+|\S+:[0-9]+)') { $relayDestination = [string]$Matches.value }
            if ($relayText -match '(?i)(?:^|\s)action=(?<value>[012])') {
                $relayAction = switch ([int]$Matches.value) { 0 { 'PROXY' } 1 { 'DIRECT' } 2 { 'BLOCK' } }
            }
            if ($relayText -match '(?i)(?:^|\s)cfg=(?<value>[0-9]+)') { $relayConfigId = [int]$Matches.value }
            $destination = ConvertFrom-ProxyBridgeDestination -Destination $relayDestination
            $record = [pscustomobject][ordered]@{
                event='RELAY_ACCEPTED_REDIRECT'; observed_at_utc=$observedAt; observed_local_time=[string]$metadata.local_time
                process=$relayProcess; pid=$relayPid; local_ip=''; local_port=0
                destination_ip=[string]$destination.ip; destination_port=[int]$destination.port
                action=$relayAction; route_detail='relay redirect'; raw_line=($rawLines -join [Environment]::NewLine)
            }
            if ($null -ne $relayConfigId) { $record | Add-Member -NotePropertyName proxy_config_id -NotePropertyValue $relayConfigId }
            $records.Add($record)
            continue
        }
        $records.Add([pscustomobject][ordered]@{
            event='UNPARSED'; observed_at_utc=$observedAt; observed_local_time=[string]$metadata.local_time
            process=''; pid=0; local_ip=''; local_port=0; destination_ip=''; destination_port=0; action=''; route_detail=''; raw_line=$line
        })
    }
    return $records.ToArray()
}

function Import-ProxyBridgeTextEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [datetime]$DefaultTimestampUtc = ([datetime]::MinValue))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'PROXYBRIDGE_EVIDENCE_NOT_FOUND' }
    return @(ConvertFrom-ProxyBridgeTextLines -Lines @([System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path))) -DefaultTimestampUtc $DefaultTimestampUtc)
}

function Find-ProxyBridgeFlowEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records,
        [string]$Process = '',
        [int]$Pid = 0,
        [string]$DestinationIp = '',
        [int]$DestinationPort = 0,
        [ValidateSet('', 'DIRECT', 'BLOCK', 'PROXY')][string]$Action = '',
        [datetime]$StartTimeUtc = ([datetime]::MinValue),
        [datetime]$EndTimeUtc = ([datetime]::MaxValue)
    )
    $matches = foreach ($record in $Records) {
        if ([string]$record.event -notin @('ROUTE_DECISION', 'RELAY_ACCEPTED_REDIRECT')) { continue }
        if ($Process -and -not [string]::IsNullOrWhiteSpace([string]$record.process) -and -not [string]::Equals([string]$record.process, $Process, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($Pid -gt 0 -and [int]$record.pid -gt 0 -and [int]$record.pid -ne $Pid) { continue }
        if ($DestinationIp -and -not [string]::Equals([string]$record.destination_ip, $DestinationIp, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($DestinationPort -gt 0 -and [int]$record.destination_port -ne $DestinationPort) { continue }
        if ($Action -and [string]$record.action -ne $Action) { continue }
        if (-not [string]::IsNullOrWhiteSpace([string]$record.observed_at_utc)) {
            $observed = [datetime]::Parse([string]$record.observed_at_utc).ToUniversalTime()
            if ($observed -lt $StartTimeUtc.ToUniversalTime() -or $observed -gt $EndTimeUtc.ToUniversalTime()) { continue }
        }
        $record
    }
    return @($matches)
}

function ConvertFrom-ProxyBridgeTerminalCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$RawText,
        [Parameter(Mandatory)][string]$EvidenceDirectory,
        [System.Collections.IDictionary]$Environment = @{},
        [datetime]$DefaultTimestampUtc = ([datetime]::MinValue)
    )
    $failure = [pscustomobject]@{ status='DECODE_UNAVAILABLE'; reason=''; records=@(); source_event_stream_complete=$false; capture_scope='rendered-terminal-observations' }
    $root = Split-Path -Parent $PSScriptRoot
    $python = ''
    if ($Environment.ContainsKey('PB_TERMINAL_PYTHON_EXE')) { $python = [string]$Environment['PB_TERMINAL_PYTHON_EXE'] }
    else {
        foreach ($relative in @('bin/protocol-worker/runtime/python/python.exe','bin/dev-venv/Scripts/python.exe')) {
            $candidate = Join-Path $root $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $python=$candidate; break }
        }
    }
    if ([string]::IsNullOrWhiteSpace($python) -or -not (Test-Path -LiteralPath $python -PathType Leaf)) { $failure.reason='TERMINAL_PYTHON_MISSING'; return $failure }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'bin/terminal-decoder/packages/pyte/__init__.py'))) { $failure.reason='TERMINAL_PACKAGES_MISSING'; return $failure }
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    if ($encoding.GetByteCount($RawText) -gt 8MB) { $failure.reason='TERMINAL_INPUT_LIMIT'; return $failure }
    $null = New-Item -ItemType Directory -Path $EvidenceDirectory -Force
    # Private raw evidence; the audit exporter does not allow this file.
    $inputPath = Join-Path $EvidenceDirectory 'proxybridge-terminal-output.txt'
    [IO.File]::WriteAllText($inputPath, $RawText, $encoding)
    $plan = [pscustomobject]@{
        executable=$python; arguments=@('-I',(Join-Path $root 'src/pb_terminal_decode.py'),'--input',$inputPath)
        process_timeout_ms=30000; actual_path_timeout_ms=2000
    }
    try {
        $adapter = New-SystemProcessAdapter
        $result = & $adapter.Invoke $plan
        if ([bool]$result.timed_out -or [int]$result.exit_code -ne 0 -or -not [bool]$result.output_capture_complete -or -not [string]::IsNullOrWhiteSpace([string]$result.stderr)) {
            $failure.reason='TERMINAL_DECODER_EXECUTION_FAILED'; return $failure
        }
        $decoded = [string]$result.stdout | ConvertFrom-Json
        if ([int]$decoded.schema_version -ne 1 -or [string]$decoded.status -ne 'DECODED_OBSERVATIONS' -or [bool]$decoded.source_event_stream_complete -or [bool]$decoded.source_event_order_preserved -or -not [bool]$decoded.observations_deduplicated -or [int]$decoded.terminal_columns -ne 240 -or [int]$decoded.terminal_rows -ne 80 -or [string]$decoded.decoder_versions.pyte -ne '0.8.2' -or [string]$decoded.decoder_versions.wcwidth -ne '0.2.13' -or @($decoded.observed_lines).Count -gt 10000) {
            $failure.reason='TERMINAL_DECODER_RESULT_INVALID'; return $failure
        }
        if ((Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash -ine [string]$decoded.input_sha256) { $failure.reason='TERMINAL_INPUT_CHANGED'; return $failure }
        $records = @(ConvertFrom-ProxyBridgeTextLines -Lines @($decoded.observed_lines) -DefaultTimestampUtc $DefaultTimestampUtc | Where-Object { [string]$_.event -in @('ROUTE_DECISION','RELAY_ACCEPTED_REDIRECT') })
        foreach ($record in $records) { $record | Add-Member -NotePropertyName capture_scope -NotePropertyValue 'terminal-observation' }
        $decoded | Add-Member -NotePropertyName records -NotePropertyValue $records
        return $decoded
    } catch { $failure.reason='TERMINAL_DECODER_FAILED'; return $failure }
}

Export-ModuleMember -Function ConvertFrom-ProxyBridgeTextLines, Import-ProxyBridgeTextEvidence, Find-ProxyBridgeFlowEvidence, ConvertFrom-ProxyBridgeTerminalCapture
