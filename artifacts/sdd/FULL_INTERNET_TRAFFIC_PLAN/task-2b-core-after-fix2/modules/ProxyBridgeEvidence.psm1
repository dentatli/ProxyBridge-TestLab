Set-StrictMode -Version Latest

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

        if ($text -match '^(?<process>.+?)(?:\s+\((?:PID:)?\s*(?<pid>[0-9]+)\))?(?:\s+from\s+(?<local>\[[^\]]+\]:[0-9]+|\S+:[0-9]+))?\s+->\s+(?<destination>\[[^\]]+\]:[0-9]+|\S+:[0-9]+)\s+via\s+(?<route>Direct|Blocked|Proxy(?:\s+.*)?)$') {
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

Export-ModuleMember -Function ConvertFrom-ProxyBridgeTextLines, Import-ProxyBridgeTextEvidence, Find-ProxyBridgeFlowEvidence
