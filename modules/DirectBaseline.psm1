Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'VpsEvidence.psm1') -Force

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { return (($algorithm.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $algorithm.Dispose() }
}

function New-DirectBaselinePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [int]$TimeoutMs = 5000
    )
    if ($TimeoutMs -lt 1) { throw 'DIRECT_BASELINE_TIMEOUT_INVALID' }
    foreach ($name in @('PB_VPS_IPV4','PB_ENDPOINT_A_PORT','PB_CLIENT_EXE')) {
        if (-not $Environment.ContainsKey($name) -or [string]::IsNullOrWhiteSpace([string]$Environment[$name])) { throw "DIRECT_BASELINE_ENVIRONMENT_MISSING_$name" }
    }
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse([string]$Environment['PB_VPS_IPV4'], [ref]$address) -or $address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { throw 'DIRECT_BASELINE_DESTINATION_IPV4_INVALID' }
    $port = 0
    if (-not [int]::TryParse([string]$Environment['PB_ENDPOINT_A_PORT'], [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'DIRECT_BASELINE_PORT_INVALID' }
    $baselineRunId = 'baseline-' + [guid]::NewGuid().ToString('N')
    $payload = [System.Text.Encoding]::UTF8.GetBytes("PB_NET|test_id=direct-baseline|run_id=$baselineRunId|sequence=1|phase=direct_baseline|protocol=TCP`n")
    return [pscustomobject][ordered]@{
        executor='powershell-dotnet-tcp-control'; watched_application=[System.IO.Path]::GetFileName([string]$Environment['PB_CLIENT_EXE'])
        remote_ip=[string]$Environment['PB_VPS_IPV4']; remote_port=$port; timeout_ms=$TimeoutMs
        test_id='direct-baseline';run_id=$baselineRunId;sequence=1;phase='direct_baseline';family='IPv4';protocol='TCP'
        payload_sha256=(Get-Sha256Hex $payload); payload_base64=[Convert]::ToBase64String($payload); payload_bytes=$payload.Length
    }
}

function New-SystemDirectBaselineAdapter {
    [CmdletBinding()]param()
    $adapter=[pscustomobject]@{is_mock=$false}
    $adapter | Add-Member -NotePropertyName InvokeFlow -NotePropertyValue {
        param($plan)
        $payload=[Convert]::FromBase64String([string]$plan.payload_base64)
        $client=[System.Net.Sockets.TcpClient]::new();$timedOut=$false;$received=[System.Collections.Generic.List[byte]]::new()
        try{
            $pending=$client.BeginConnect([string]$plan.remote_ip,[int]$plan.remote_port,$null,$null)
            if(-not $pending.AsyncWaitHandle.WaitOne([int]$plan.timeout_ms)){$timedOut=$true;return [pscustomobject]@{success=$false;timed_out=$true;bytes_sent=0;bytes_received=0;response_sha256='';error='connect timeout'}}
            $client.EndConnect($pending);$client.ReceiveTimeout=[int]$plan.timeout_ms;$client.SendTimeout=[int]$plan.timeout_ms
            $stream=$client.GetStream();$stream.Write($payload,0,$payload.Length);$stream.Flush();$buffer=New-Object byte[] $payload.Length
            while($received.Count -lt $payload.Length){$count=$stream.Read($buffer,0,[Math]::Min($buffer.Length,$payload.Length-$received.Count));if($count -le 0){break};for($i=0;$i -lt $count;$i++){$received.Add($buffer[$i])}}
            $response=$received.ToArray()
            return [pscustomobject]@{success=($response.Length -eq $payload.Length);timed_out=$false;bytes_sent=$payload.Length;bytes_received=$response.Length;response_sha256=$(if($response.Length -gt 0){Get-Sha256Hex $response}else{''});error=''}
        }
        catch{if($_.Exception -is [System.IO.IOException]){$timedOut=$true};return [pscustomobject]@{success=$false;timed_out=$timedOut;bytes_sent=0;bytes_received=$received.Count;response_sha256='';error=$_.Exception.GetType().Name}}
        finally{$client.Dispose()}
    }
    return $adapter
}

function New-MockDirectBaselineAdapter {
    [CmdletBinding()]
    param($FlowResult)
    if($null -eq $FlowResult){$FlowResult=[pscustomobject]@{success=$true;timed_out=$false;bytes_sent=64;bytes_received=64;response_sha256='';error=''}}
    $state=[pscustomobject]@{invoke_count=0;flow_result=$FlowResult}
    $adapter=[pscustomobject]@{is_mock=$true;state=$state}
    $adapter | Add-Member -NotePropertyName InvokeFlow -NotePropertyValue ({param($plan)$state.invoke_count++;if([string]::IsNullOrWhiteSpace([string]$state.flow_result.response_sha256)){$state.flow_result.response_sha256=[string]$plan.payload_sha256};return $state.flow_result}.GetNewClosure())
    return $adapter
}

function Invoke-DirectBaselineDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$Adapter,
        [Parameter(Mandatory)][scriptblock]$VpsCollector,
        [string]$ExpectedDirectEgressIpv4='',
        [switch]$AllowProductRuntime
    )
    if(-not [bool]$Adapter.is_mock -and -not $AllowProductRuntime){throw 'DIRECT_BASELINE_RUNTIME_NOT_ALLOWED'}
    if($null -eq $Adapter.PSObject.Properties['InvokeFlow']){throw 'DIRECT_BASELINE_ADAPTER_MISSING_INVOKEFLOW'}
    $flow=& $Adapter.InvokeFlow $Plan
    $clientEvidence=[pscustomobject][ordered]@{
        executor=[string]$Plan.executor;remote_ip=[string]$Plan.remote_ip;remote_port=[int]$Plan.remote_port
        payload_sha256=[string]$Plan.payload_sha256;response_sha256=[string]$flow.response_sha256
        bytes_sent=[int]$flow.bytes_sent;bytes_received=[int]$flow.bytes_received;timed_out=[bool]$flow.timed_out;success=[bool]$flow.success;error=[string]$flow.error
    }
    if(-not [bool]$flow.success -or [bool]$flow.timed_out -or [string]$flow.response_sha256 -ne [string]$Plan.payload_sha256){return [pscustomobject][ordered]@{passed=$false;status='FAIL_INFRASTRUCTURE';reason='DIRECT_BASELINE_CLIENT_FAILED';direct_egress_ip='';client_result=$clientEvidence;vps_collection=$null;vps_records=@()}}
    $canonical=[pscustomobject][ordered]@{record_kind='flow';sequence=[int]$Plan.sequence;phase=[string]$Plan.phase;protocol='TCP';payload_sha256=[string]$Plan.payload_sha256;expected_action='DIRECT';remote_ip=[string]$Plan.remote_ip;remote_port=[int]$Plan.remote_port}
    try{$collection=& $VpsCollector $canonical}catch{return [pscustomobject][ordered]@{passed=$false;status='FAIL_INFRASTRUCTURE';reason=('DIRECT_BASELINE_QUERY_FAILED: '+$_.Exception.Message);direct_egress_ip='';client_result=$clientEvidence;vps_collection=$null;vps_records=@()}}
    $complete=[bool]$collection.capture_complete
    if(@($collection.complete_shas).Count -gt 0){$complete=@($collection.complete_shas|ForEach-Object{([string]$_).ToLowerInvariant()}) -contains ([string]$Plan.payload_sha256).ToLowerInvariant()}
    if(@($collection.query_results|Where-Object{-not [bool]$_.success}).Count -gt 0){$complete=$false}
    if(-not $complete){return [pscustomobject][ordered]@{passed=$false;status='FAIL_INFRASTRUCTURE';reason='DIRECT_BASELINE_QUERY_INCOMPLETE';direct_egress_ip='';client_result=$clientEvidence;vps_collection=$collection;vps_records=@($collection.records)}}
    $check=Test-VpsPayloadEvidence -Records @($collection.records) -Sha256 ([string]$Plan.payload_sha256) -Protocol TCP -ExpectedReceived 1 -ExpectedEchoed 1 -ExpectedDestinationPort ([int]$Plan.remote_port)
    if(-not $check.passed){return [pscustomobject][ordered]@{passed=$false;status='FAIL_INFRASTRUCTURE';reason=('DIRECT_BASELINE_VPS_INVALID: '+(@($check.errors)-join ', '));direct_egress_ip='';client_result=$clientEvidence;vps_collection=$collection;vps_records=@($collection.records)}}
    $source=@($check.matches|Where-Object{[string]$_.event -eq 'MESSAGE_RECEIVED'}|Select-Object -ExpandProperty remote_ip -Unique)
    $sourceAddress=$null
    if($source.Count -ne 1 -or -not [System.Net.IPAddress]::TryParse([string]$source[0],[ref]$sourceAddress) -or $sourceAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork){return [pscustomobject][ordered]@{passed=$false;status='FAIL_INFRASTRUCTURE';reason='DIRECT_BASELINE_SOURCE_IPV4_INVALID';direct_egress_ip='';client_result=$clientEvidence;vps_collection=$collection;vps_records=@($collection.records)}}
    if(-not [string]::IsNullOrWhiteSpace($ExpectedDirectEgressIpv4) -and [string]$source[0] -ne $ExpectedDirectEgressIpv4){return [pscustomobject][ordered]@{passed=$false;status='FAIL_INFRASTRUCTURE';reason='DIRECT_BASELINE_EXPECTED_EGRESS_MISMATCH';direct_egress_ip=[string]$source[0];client_result=$clientEvidence;vps_collection=$collection;vps_records=@($collection.records)}}
    return [pscustomobject][ordered]@{passed=$true;status='PASS_BASELINE';reason='exact direct TCP echo and VPS source verified';direct_egress_ip=[string]$source[0];client_result=$clientEvidence;vps_collection=$collection;vps_records=@($collection.records)}
}

Export-ModuleMember -Function New-DirectBaselinePlan, Invoke-DirectBaselineDiscovery, New-SystemDirectBaselineAdapter, New-MockDirectBaselineAdapter
