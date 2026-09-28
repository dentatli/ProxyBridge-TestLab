[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/ProtocolWorker.psm1') -Force

$dotnet = 'C:\Program Files\dotnet\dotnet.exe'
$probe = Join-Path $root 'ui\ProxyBridge.TestLab.Ui.ServerProbe\bin\Release\net10.0-windows\ProxyBridge.TestLab.Ui.ServerProbe.dll'
$bundleRoot = Join-Path $root 'bin\protocol-worker'
$entrypoint = Join-Path $bundleRoot 'worker\pb_protocol_worker.py'
$manifest = Join-Path $bundleRoot 'worker\plugins\manifest.json'
$runtimeContract = Join-Path $root 'config\protocol-worker-runtime.json'
$evidenceContract = Join-Path $root 'config\protocol-evidence-contract.json'
$python = Get-Item -LiteralPath (Join-Path $bundleRoot 'runtime\python\python.exe') -ErrorAction SilentlyContinue
Assert-True ($null -ne $python) 'Bundled Python is required for the loopback protocol slice'
Assert-True (Test-Path -LiteralPath $probe -PathType Leaf) 'server probe must be built before the protocol slice'
$contracts = Import-ProtocolWorkerRuntimeContract -RuntimeContractPath $runtimeContract -PluginManifestPath $manifest
$temp = New-TestDirectory
$server = $null
$results = [System.Collections.Generic.List[object]]::new()

function Start-TestProcess([string]$Executable, [string[]]$Arguments) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Executable
    $quoted = foreach ($argument in $Arguments) { '"' + $argument.Replace('"','\"') + '"' }
    $psi.Arguments = $quoted -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    Assert-True $process.Start() 'protocol test process must start'
    return $process
}

function Invoke-ProtocolPlan($Plan, [string]$Name, [string]$ServerEvidencePath, [bool]$ExpectServerEvidence = $true) {
    $planPath = Join-Path $temp ($Name + '.plan.json')
    $outputPath = Join-Path $temp ($Name + '.client.jsonl')
    Write-ProtocolWorkerPlan -Plan $Plan -Path $planPath -RuntimeContracts $contracts
    $worker = Start-TestProcess $python.FullName @('-I','-B',$entrypoint,'--plan',$planPath,'--output-jsonl',$outputPath,'--manifest',$manifest)
    try {
        Assert-True $worker.WaitForExit(10000) "$Name worker bounded completion"
        $stdout = $worker.StandardOutput.ReadToEnd().Trim()
        $stderr = $worker.StandardError.ReadToEnd().Trim()
        Assert-Equal 0 $worker.ExitCode "$Name worker exit code (stderr='$stderr'; stdout='$stdout')"
        Assert-Equal 'PROTOCOL_WORKER_OK records=1' $stdout "$Name stable worker status"
        Assert-Equal '' $stderr "$Name worker stderr"
    }
    finally { $worker.Dispose() }
    Assert-NoUtf8Bom $outputPath "$Name client evidence UTF-8 without BOM"
    $client = @(Read-ProtocolWorkerEvidence -Path $outputPath -Plan $Plan -RuntimeContracts $contracts -EvidenceContractPath $evidenceContract)
    Assert-Equal 1 $client.Count "$Name client evidence count"
    $serverRecord = $null
    if ($ExpectServerEvidence) {
        for ($attempt = 0; $attempt -lt 100 -and $null -eq $serverRecord; $attempt++) {
            try { $serverRecord = Read-ProtocolServerEvidence -Path $ServerEvidencePath -Plan $Plan -RuntimeContracts $contracts -EvidenceContractPath $evidenceContract }
            catch {
                if ($_.Exception.Message -notmatch 'PROTOCOL_SERVER_EVIDENCE_(MISSING|IDENTITY_MISSING)') { throw }
                Start-Sleep -Milliseconds 25
            }
        }
        Assert-True ($null -ne $serverRecord) "$Name exact server evidence"
        Assert-Equal ([string]$client[0].payload_sha256) ([string]$serverRecord.payload_sha256) "$Name independent payload correlation"
    }
    else {
        Assert-Throws { Read-ProtocolServerEvidence -Path $ServerEvidencePath -Plan $Plan -RuntimeContracts $contracts -EvidenceContractPath $evidenceContract } 'PROTOCOL_SERVER_EVIDENCE_IDENTITY_MISSING' "$Name must have zero exact server matches"
    }
    return [pscustomobject]@{ Name=$Name; Plan=$Plan; Client=$client[0]; Server=$serverRecord; OutputPath=$outputPath }
}

try {
    $fixtureRoot = Join-Path $temp 'server-fixture'
    $fixtureOutput = @(& $dotnet $probe --export-protocol-fixture $root $fixtureRoot)
    Assert-Equal 0 $LASTEXITCODE 'protocol fixture exporter exit code'
    Assert-True ($fixtureOutput -contains 'PROTOCOL_FIXTURE_READY') 'protocol fixture exporter status'
    $configPath = Join-Path $fixtureRoot 'protocol-server-config.json'
    $serverEvidence = Join-Path $fixtureRoot 'protocols.jsonl'
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.bind_ipv4 = '127.0.0.1'
    $config.bind_ipv6 = ''
    $config.jsonl_log = 'protocols.jsonl'
    $config | Add-Member -NotePropertyName allow_ephemeral_ports -NotePropertyValue $true
    $serviceNames = @(
        'dns','http','tls','https','http2','quic_http3','websocket','grpc','webtransport',
        'ftp','ftp_data','smtp','smtps','imap','imaps','pop3','pop3s','mqtt','mqtts',
        'amqp','amqps','ntp','irc','ircs','multipeer','stun_turn','rtp_media','receive_only','failure_control'
    )
    foreach ($section in $serviceNames) { $config.$section.port = 0 }
    Write-TestUtf8NoBom $configPath (($config | ConvertTo-Json -Depth 10) + [Environment]::NewLine)

    $server = Start-TestProcess $python.FullName @('-I','-B',(Join-Path $fixtureRoot 'pb_protocol_server.py'),'--serve','--config',$configPath)
    $readyTask = $server.StandardOutput.ReadLineAsync()
    Assert-True $readyTask.Wait(10000) 'protocol server bounded readiness'
    $ready = [string]$readyTask.Result
    if (-not $ready.StartsWith('PROTOCOL_SERVER_READY ')) {
        $serverFailure = $(if ($server.HasExited) { $server.StandardError.ReadToEnd().Trim() } else { 'server remained active with an invalid readiness line' })
        throw "ASSERTION FAILED: protocol server readiness status; stdout='$ready'; status='$serverFailure'"
    }
    $readyPorts = @{}
    foreach ($token in @($ready.Substring('PROTOCOL_SERVER_READY '.Length).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))) {
        if ($token -notmatch '^([a-z0-9_]+)=(\d+)$') { throw "ASSERTION FAILED: invalid readiness token '$token'" }
        if ($readyPorts.ContainsKey($Matches[1])) { throw "ASSERTION FAILED: duplicate readiness service '$($Matches[1])'" }
        $readyPorts[$Matches[1]] = [int]$Matches[2]
    }
    Assert-Equal $serviceNames.Count $readyPorts.Count 'protocol server readiness service count'
    foreach ($section in $serviceNames) {
        Assert-True $readyPorts.ContainsKey($section) "protocol server readiness includes $section"
        Assert-True ($readyPorts[$section] -gt 0) "protocol server allocates $section"
        $config.$section.port = [int]$readyPorts[$section]
    }
    $allocatedPorts = @($serviceNames | ForEach-Object { [int]$readyPorts[$_] })
    Assert-Equal $serviceNames.Count @($allocatedPorts | Sort-Object -Unique).Count 'protocol server must allocate distinct loopback ports'
    Assert-True (-not $server.HasExited) 'protocol server remains alive after readiness'

    $common = @{ RunId='protocol-slice'; AttemptId='attempt-1'; OperationTimeoutMs=5000; RuntimeContracts=$contracts }
    $dnsUdp = New-ProtocolWorkerPlan @common -ScenarioId 'dns-udp-a' -FlowId 'flow-dns-udp' -PluginId 'protocol-dns' -ProtocolFamily 'dns-classic' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.dns.port;dns_transport='UDP';query_name='a.probe.test.';query_type='A'}) -Expected ([pscustomobject]@{response_code=0;answers=@('192.0.2.123')})
    $results.Add((Invoke-ProtocolPlan $dnsUdp 'dns-udp-a' $serverEvidence))
    $dnsTcp = New-ProtocolWorkerPlan @common -ScenarioId 'dns-tcp-aaaa' -FlowId 'flow-dns-tcp' -PluginId 'protocol-dns' -ProtocolFamily 'dns-classic' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.dns.port;dns_transport='TCP';query_name='aaaa.probe.test.';query_type='AAAA'}) -Expected ([pscustomobject]@{response_code=0;answers=@('2001:db8::123')})
    $results.Add((Invoke-ProtocolPlan $dnsTcp 'dns-tcp-aaaa' $serverEvidence))
    $dnsServfail = New-ProtocolWorkerPlan @common -ScenarioId 'dns-servfail' -FlowId 'flow-dns-servfail' -PluginId 'protocol-dns' -ProtocolFamily 'dns-classic' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.dns.port;dns_transport='UDP';query_name='servfail.probe.test.';query_type='A'}) -Expected ([pscustomobject]@{response_code=2;answers=@()})
    $results.Add((Invoke-ProtocolPlan $dnsServfail 'dns-servfail' $serverEvidence))
    $tls = New-ProtocolWorkerPlan @common -ScenarioId 'tls-session' -FlowId 'flow-tls' -PluginId 'protocol-tls' -ProtocolFamily 'tls' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.tls.port;server_name='proxybridge-testlab.test';ca_path=(Join-Path $fixtureRoot 'tls\ca.pem')}) -Expected ([pscustomobject]@{result='PASS'})
    $results.Add((Invoke-ProtocolPlan $tls 'tls-session' $serverEvidence))
    $http = New-ProtocolWorkerPlan @common -ScenarioId 'http1-clear' -FlowId 'flow-http' -PluginId 'protocol-http' -ProtocolFamily 'http1' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.http.port;authority='proxybridge-testlab.test';path='/probe';use_tls=$false}) -Expected ([pscustomobject]@{status_code=200})
    $results.Add((Invoke-ProtocolPlan $http 'http1-clear' $serverEvidence))
    $https = New-ProtocolWorkerPlan @common -ScenarioId 'http1-tls' -FlowId 'flow-https' -PluginId 'protocol-http' -ProtocolFamily 'http1' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.https.port;authority='proxybridge-testlab.test';path='/probe';use_tls=$true;server_name='proxybridge-testlab.test';ca_path=(Join-Path $fixtureRoot 'tls\ca.pem')}) -Expected ([pscustomobject]@{status_code=200})
    $results.Add((Invoke-ProtocolPlan $https 'http1-tls' $serverEvidence))
    $http2 = New-ProtocolWorkerPlan @common -ScenarioId 'http2-tls' -FlowId 'flow-http2' -PluginId 'protocol-http2' -ProtocolFamily 'http2' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.http2.port;authority='proxybridge-testlab.test';path='/probe';server_name='proxybridge-testlab.test';ca_path=(Join-Path $fixtureRoot 'tls\ca.pem')}) -Expected ([pscustomobject]@{status_code=200})
    $results.Add((Invoke-ProtocolPlan $http2 'http2-tls' $serverEvidence))
    $grpc = New-ProtocolWorkerPlan @common -ScenarioId 'grpc-unary' -FlowId 'flow-grpc' -PluginId 'protocol-grpc' -ProtocolFamily 'grpc' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.grpc.port;authority='proxybridge-testlab.test';server_name='proxybridge-testlab.test';ca_path=(Join-Path $fixtureRoot 'tls\ca.pem');service='testlab.Echo';method='Unary'}) -Expected ([pscustomobject]@{application_status='0'})
    $results.Add((Invoke-ProtocolPlan $grpc 'grpc-unary' $serverEvidence))
    $websocket = New-ProtocolWorkerPlan @common -ScenarioId 'websocket-secure' -FlowId 'flow-websocket' -PluginId 'protocol-websocket' -ProtocolFamily 'websocket' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.websocket.port;authority='proxybridge-testlab.test';path='/socket';subprotocol='pb-test.v1';use_tls=$true;server_name='proxybridge-testlab.test';ca_path=(Join-Path $fixtureRoot 'tls\ca.pem')}) -Expected ([pscustomobject]@{close_code=1000})
    $results.Add((Invoke-ProtocolPlan $websocket 'websocket-secure' $serverEvidence))
    $http3 = New-ProtocolWorkerPlan @common -ScenarioId 'http3-quic' -FlowId 'flow-http3' -PluginId 'protocol-quic' -ProtocolFamily 'quic-http3' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.quic_http3.port;authority='proxybridge-testlab.test';path='/probe';server_name='proxybridge-testlab.test';ca_path=(Join-Path $fixtureRoot 'tls\ca.pem')}) -Expected ([pscustomobject]@{status_code=200})
    $results.Add((Invoke-ProtocolPlan $http3 'http3-quic' $serverEvidence))
    $webtransport = New-ProtocolWorkerPlan @common -ScenarioId 'webtransport-datagram' -FlowId 'flow-webtransport' -PluginId 'protocol-webtransport' -ProtocolFamily 'webtransport' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.webtransport.port;authority='proxybridge-testlab.test';server_name='proxybridge-testlab.test';ca_path=(Join-Path $fixtureRoot 'tls\ca.pem')}) -Expected ([pscustomobject]@{status_code=200})
    $results.Add((Invoke-ProtocolPlan $webtransport 'webtransport-datagram' $serverEvidence))

    $caPath = Join-Path $fixtureRoot 'tls\ca.pem'
    $ftp = New-ProtocolWorkerPlan @common -ScenarioId 'ftp-upload' -FlowId 'flow-ftp' -PluginId 'protocol-ftp' -ProtocolFamily 'ftp-ftps' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.ftp.port;use_tls=$false}) -Expected ([pscustomobject]@{control_status='221'})
    $results.Add((Invoke-ProtocolPlan $ftp 'ftp-upload' $serverEvidence))
    $ftps = New-ProtocolWorkerPlan @common -ScenarioId 'ftps-upload' -FlowId 'flow-ftps' -PluginId 'protocol-ftp' -ProtocolFamily 'ftp-ftps' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.ftp.port;use_tls=$true;server_name='proxybridge-testlab.test';ca_path=$caPath}) -Expected ([pscustomobject]@{control_status='221'})
    $results.Add((Invoke-ProtocolPlan $ftps 'ftps-upload' $serverEvidence))

    foreach ($mailCase in @(
        [pscustomobject]@{Name='smtp';Protocol='SMTP';Family='smtp';Port=[int]$config.smtp.port;Secure=$false;Status='250'},
        [pscustomobject]@{Name='smtps';Protocol='SMTPS';Family='smtp';Port=[int]$config.smtps.port;Secure=$true;Status='250'},
        [pscustomobject]@{Name='imap';Protocol='IMAP';Family='imap-pop3';Port=[int]$config.imap.port;Secure=$false;Status='OK'},
        [pscustomobject]@{Name='imaps';Protocol='IMAPS';Family='imap-pop3';Port=[int]$config.imaps.port;Secure=$true;Status='OK'},
        [pscustomobject]@{Name='pop3';Protocol='POP3';Family='imap-pop3';Port=[int]$config.pop3.port;Secure=$false;Status='OK'},
        [pscustomobject]@{Name='pop3s';Protocol='POP3S';Family='imap-pop3';Port=[int]$config.pop3s.port;Secure=$true;Status='OK'}
    )) {
        $parameters = [ordered]@{remote_host='127.0.0.1';remote_port=$mailCase.Port;mail_protocol=$mailCase.Protocol}
        if ($mailCase.Secure) { $parameters.server_name='proxybridge-testlab.test'; $parameters.ca_path=$caPath }
        $plan = New-ProtocolWorkerPlan @common -ScenarioId ("mail-{0}" -f $mailCase.Name) -FlowId ("flow-mail-{0}" -f $mailCase.Name) -PluginId 'protocol-mail' -ProtocolFamily $mailCase.Family -Transport TCP -Parameters ([pscustomobject]$parameters) -Expected ([pscustomobject]@{protocol_status=$mailCase.Status})
        $results.Add((Invoke-ProtocolPlan $plan ("mail-{0}" -f $mailCase.Name) $serverEvidence))
    }

    foreach ($messageCase in @(
        [pscustomobject]@{Name='mqtt';Protocol='MQTT';Family='mqtt';Port=[int]$config.mqtt.port;Secure=$false},
        [pscustomobject]@{Name='mqtts';Protocol='MQTTS';Family='mqtt';Port=[int]$config.mqtts.port;Secure=$true},
        [pscustomobject]@{Name='amqp';Protocol='AMQP';Family='amqp';Port=[int]$config.amqp.port;Secure=$false},
        [pscustomobject]@{Name='amqps';Protocol='AMQPS';Family='amqp';Port=[int]$config.amqps.port;Secure=$true}
    )) {
        $parameters = [ordered]@{remote_host='127.0.0.1';remote_port=$messageCase.Port;messaging_protocol=$messageCase.Protocol}
        if ($messageCase.Secure) { $parameters.server_name='proxybridge-testlab.test'; $parameters.ca_path=$caPath }
        $plan = New-ProtocolWorkerPlan @common -ScenarioId ("messaging-{0}" -f $messageCase.Name) -FlowId ("flow-messaging-{0}" -f $messageCase.Name) -PluginId 'protocol-messaging' -ProtocolFamily $messageCase.Family -Transport TCP -Parameters ([pscustomobject]$parameters) -Expected ([pscustomobject]@{acknowledged=$true})
        $results.Add((Invoke-ProtocolPlan $plan ("messaging-{0}" -f $messageCase.Name) $serverEvidence))
    }

    $ntp = New-ProtocolWorkerPlan @common -ScenarioId 'ntp-v4' -FlowId 'flow-ntp' -PluginId 'protocol-ntp' -ProtocolFamily 'ntp' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.ntp.port}) -Expected ([pscustomobject]@{stratum=2})
    $results.Add((Invoke-ProtocolPlan $ntp 'ntp-v4' $serverEvidence))
    foreach ($ircCase in @(
        [pscustomobject]@{Name='irc';Port=[int]$config.irc.port;Secure=$false},
        [pscustomobject]@{Name='ircs';Port=[int]$config.ircs.port;Secure=$true}
    )) {
        $parameters = [ordered]@{remote_host='127.0.0.1';remote_port=$ircCase.Port;use_tls=$ircCase.Secure}
        if ($ircCase.Secure) { $parameters.server_name='proxybridge-testlab.test'; $parameters.ca_path=$caPath }
        $plan = New-ProtocolWorkerPlan @common -ScenarioId ("irc-{0}" -f $ircCase.Name) -FlowId ("flow-irc-{0}" -f $ircCase.Name) -PluginId 'protocol-irc' -ProtocolFamily 'irc' -Transport TCP -Parameters ([pscustomobject]$parameters) -Expected ([pscustomobject]@{acknowledged=$true})
        $results.Add((Invoke-ProtocolPlan $plan ("irc-{0}" -f $ircCase.Name) $serverEvidence))
    }
    $multipeer = New-ProtocolWorkerPlan @common -ScenarioId 'controlled-multipeer' -FlowId 'flow-multipeer' -PluginId 'protocol-multipeer' -ProtocolFamily 'controlled-p2p' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.multipeer.port}) -Expected ([pscustomobject]@{peer_count=2})
    $results.Add((Invoke-ProtocolPlan $multipeer 'controlled-multipeer' $serverEvidence))

    $stun = New-ProtocolWorkerPlan @common -ScenarioId 'stun-binding' -FlowId 'flow-stun' -PluginId 'protocol-realtime' -ProtocolFamily 'stun-turn' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.stun_turn.port;ice_protocol='STUN'}) -Expected ([pscustomobject]@{method='BINDING';integrity_verified=$true})
    $results.Add((Invoke-ProtocolPlan $stun 'stun-binding' $serverEvidence))
    $turn = New-ProtocolWorkerPlan @common -ScenarioId 'turn-allocate' -FlowId 'flow-turn' -PluginId 'protocol-realtime' -ProtocolFamily 'stun-turn' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.stun_turn.port;ice_protocol='TURN'}) -Expected ([pscustomobject]@{method='ALLOCATE';integrity_verified=$true})
    $results.Add((Invoke-ProtocolPlan $turn 'turn-allocate' $serverEvidence))
    $media = New-ProtocolWorkerPlan @common -ScenarioId 'srtp-media' -FlowId 'flow-srtp' -PluginId 'protocol-media' -ProtocolFamily 'rtp-media' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.rtp_media.port;packet_count=12}) -Expected ([pscustomobject]@{rtcp_status='RECEIVER_REPORT';sequence_gap_count=0})
    $results.Add((Invoke-ProtocolPlan $media 'srtp-media' $serverEvidence))
    $receiveOnly = New-ProtocolWorkerPlan @common -ScenarioId 'udp-receive-only' -FlowId 'flow-receive-only' -PluginId 'protocol-receive-only' -ProtocolFamily 'udp-receive-only' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.receive_only.port}) -Expected ([pscustomobject]@{server_initiated=$true})
    $results.Add((Invoke-ProtocolPlan $receiveOnly 'udp-receive-only' $serverEvidence))
    $processFailure = New-ProtocolWorkerPlan @common -ScenarioId 'process-termination' -FlowId 'flow-process-termination' -PluginId 'protocol-failure' -ProtocolFamily 'process-failure' -Transport TCP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.failure_control.port}) -Expected ([pscustomobject]@{expected_failure_signature='CLIENT_PROCESS_TERMINATED'})
    $results.Add((Invoke-ProtocolPlan $processFailure 'process-termination' $serverEvidence))

    $shortCommon = $common.Clone()
    $shortCommon.OperationTimeoutMs = 100
    $noResponse = New-ProtocolWorkerPlan @shortCommon -ScenarioId 'dns-no-response' -FlowId 'flow-dns-no-response' -PluginId 'protocol-dns' -ProtocolFamily 'dns-classic' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=1;dns_transport='UDP';query_name='blocked.probe.test.';query_type='A'}) -Expected ([pscustomobject]@{outcome='no-response'})
    $noResponseResult = Invoke-ProtocolPlan $noResponse 'dns-no-response' $serverEvidence $false
    Assert-Equal 'PASS' ([string]$noResponseResult.Client.result) 'bounded client no-response semantics must pass'
    Assert-True ([bool]$noResponseResult.Client.no_response_observed) 'no-response evidence marker must be explicit'

    $unexpectedResponse = New-ProtocolWorkerPlan @common -ScenarioId 'dns-unexpected-response' -FlowId 'flow-dns-unexpected-response' -PluginId 'protocol-dns' -ProtocolFamily 'dns-classic' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.dns.port;dns_transport='UDP';query_name='a.probe.test.';query_type='A'}) -Expected ([pscustomobject]@{outcome='no-response'})
    $unexpectedResponseResult = Invoke-ProtocolPlan $unexpectedResponse 'dns-unexpected-response' $serverEvidence
    Assert-Equal 'FAIL' ([string]$unexpectedResponseResult.Client.result) 'a response must fail a no-response expectation'

    foreach ($result in $results) { Assert-Equal 'PASS' ([string]$result.Client.result) "$($result.Name) protocol assertion" }
    $tlsResult = @($results | Where-Object Name -eq 'tls-session')[0]
    Assert-Equal ([string]$tlsResult.Client.peer_certificate_sha256) ([string]$tlsResult.Server.peer_certificate_sha256) 'TLS certificate identity must agree across channels'

    $negative = New-ProtocolWorkerPlan @common -ScenarioId 'dns-negative-answer' -FlowId 'flow-dns-negative' -PluginId 'protocol-dns' -ProtocolFamily 'dns-classic' -Transport UDP -Parameters ([pscustomobject]@{remote_host='127.0.0.1';remote_port=[int]$config.dns.port;dns_transport='UDP';query_name='negative.probe.test.';query_type='A'}) -Expected ([pscustomobject]@{response_code=0;answers=@('192.0.2.124')})
    $negativeResult = Invoke-ProtocolPlan $negative 'dns-negative-answer' $serverEvidence
    Assert-Equal 'FAIL' ([string]$negativeResult.Client.result) 'wrong expected DNS answer must fail closed'
    Assert-Equal 'PASS' ([string]$negativeResult.Server.result) 'negative DNS fixture still requires valid independent server evidence'

    $tamperedClient = Join-Path $temp 'tampered-client.jsonl'
    $tamperedClientRecord = $negativeResult.Client | Select-Object * -ExcludeProperty answer_digest
    Write-TestUtf8NoBom $tamperedClient (($tamperedClientRecord | ConvertTo-Json -Compress) + [Environment]::NewLine)
    Assert-Throws { Read-ProtocolWorkerEvidence -Path $tamperedClient -Plan $negative -RuntimeContracts $contracts -EvidenceContractPath $evidenceContract } 'PROTOCOL_WORKER_EVIDENCE_FIELD_MISSING' 'missing protocol field must not produce a verdict'

    $tamperedServer = Join-Path $temp 'tampered-server.jsonl'
    $tamperedLines = foreach ($line in [System.IO.File]::ReadAllLines($serverEvidence, [System.Text.Encoding]::UTF8)) {
        $record = $line | ConvertFrom-Json
        if ([string]$record.flow_id -eq [string]$negative.flow_id) { $record.flow_id = 'unrelated-flow' }
        $record | ConvertTo-Json -Compress
    }
    Write-TestUtf8NoBom $tamperedServer (($tamperedLines -join [Environment]::NewLine) + [Environment]::NewLine)
    Assert-Throws { Read-ProtocolServerEvidence -Path $tamperedServer -Plan $negative -RuntimeContracts $contracts -EvidenceContractPath $evidenceContract } 'PROTOCOL_SERVER_EVIDENCE_IDENTITY_MISSING' 'unrelated server evidence must not satisfy the current flow'
    Assert-NoUtf8Bom $serverEvidence 'protocol server evidence UTF-8 without BOM'
}
finally {
    if ($null -ne $server) {
        try { if (-not $server.HasExited) { $server.Kill(); $server.WaitForExit(5000) | Out-Null } } catch { }
        $server.Dispose()
    }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

'PASS: Milestones 12-16 protocol loopback vertical slice'
