#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateSet('SMOKE','STANDARD')][string]$Profile='SMOKE',
    [string]$EvidenceDirectory='',
    [string]$EnvPath='',
    [string]$PythonPath='',
    [switch]$Resume,
    [switch]$DiagnosticPull,
    [switch]$ProxyNoDelay
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($DiagnosticPull -and ($Resume -or $Profile -ne 'STANDARD')) { throw 'TCP_DIAGNOSTIC_REQUIRES_NEW_STANDARD_RUN' }
$root=Split-Path -Parent $PSScriptRoot
foreach ($name in @('Env','ProductBuild','RuntimeEnvironment','InterceptionState','ProxyBridgeCli','ProcessAdapter','ProxyBridgeEvidence')) { Import-Module (Join-Path $root ('modules/'+$name+'.psm1')) }
if (-not $EnvPath) { $EnvPath=Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env' }
if (-not $PythonPath) { $PythonPath=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' }
$client=Join-Path $root 'bin/tcp-rtt/pb_tcp_rtt_client.exe'
$receiver=Join-Path $root 'src/pb_net_endpoint.py'
$buildReceipt=Join-Path $root 'bin/tcp-rtt/build-receipt.json'
$wheel=Join-Path $root 'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl'
$proxyHelper=Join-Path $root $(if ($ProxyNoDelay) {'src/pb_tcp_nodelay_diagnostic.py'} else {'src/pb_controlled_tcp_proxy.py'})
if (-not (Test-Path -LiteralPath $proxyHelper -PathType Leaf)) { throw 'TCP_PROXY_HELPER_MISSING' }
$packages=Join-Path $root 'bin/tools/psutil-7.2.2/packages'
$samplerWheel=Join-Path $root 'bin/tools/psutil-7.2.2/psutil-7.2.2-cp37-abi3-win_amd64.whl'
foreach ($path in @($EnvPath,$PythonPath,$client,$receiver,$buildReceipt,$wheel,(Join-Path $packages 'psutil/__init__.py'))) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "TCP_DEPENDENCY_MISSING_$path" } }
$engineSha='35D31540D8F6B564839B135BF0C925A224D768519B33C0FAFA9290A3437E8D6A'
foreach ($path in @($client)) { if ((Get-FileHash $path).Hash -ne $engineSha) { throw 'TCP_ENGINE_HASH_MISMATCH' } }
$clientBuild=Get-Content -LiteralPath $buildReceipt -Raw | ConvertFrom-Json
if ($clientBuild.engine_sha256 -ne $engineSha -or $clientBuild.source_sha256 -ne (Get-FileHash (Join-Path $root 'src/pb_net_client.c')).Hash) { throw 'TCP_RTT_SOURCE_BUILD_CHANGED_REBUILD_REQUIRED' }
if ((Get-FileHash $wheel).Hash -ne '5190D3AE00A29325EC9048306FCD8BD08F8E89DDD75C535CC01D1D646F105344' -or (Get-FileHash $samplerWheel).Hash -ne 'EB7E81434C8D223EC4A219B5FC1C47D0417B12BE7EA866E24FB5AD6E84B3D988') { throw 'TCP_LIBRARY_WHEEL_HASH_MISMATCH' }
$environment=Import-DotEnv -Path $EnvPath
$identity=Get-ProductBuildIdentity -Environment $environment -Contract driver
if (-not $identity.files_verified) { throw 'TCP_PRODUCT_FILES_NOT_VERIFIED' }
if ($Resume -and -not $EvidenceDirectory) { throw 'TCP_RESUME_REQUIRES_EVIDENCE_DIRECTORY' }
if (-not $EvidenceDirectory) { $EvidenceDirectory=Join-Path $root ('artifacts/local-route/'+$(if ($DiagnosticPull) {'tcp-loaded-rtt-diagnostic-pull-'} elseif ($ProxyNoDelay) {'tcp-loaded-rtt-nodelay-'} else {'tcp-loaded-rtt-'})+$Profile.ToLowerInvariant()+'-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)) }
if ($Resume) {
    if (-not (Test-Path -LiteralPath $EvidenceDirectory -PathType Container)) { throw 'TCP_RESUME_DIRECTORY_MISSING' }
} else {
    if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'TCP_RTT_REQUIRES_NEW_DIRECTORY' }
    $null=New-Item -ItemType Directory -Path $EvidenceDirectory
}
$EvidenceDirectory=(Resolve-Path -LiteralPath $EvidenceDirectory).Path
$pairs=$(if ($Profile -eq 'SMOKE') {1} else {3})
$echoCount=$(if ($Profile -eq 'SMOKE') {128} else {3000})
$warmup=$(if ($Profile -eq 'SMOKE') {16} else {100})
$loadClient=Join-Path $root 'bin/tools/ctstraffic-2.0.3.9/ctsTraffic.exe'
$loadReceiver=Join-Path $root 'bin/tools/ctstraffic-2.0.3.9/ctsTrafficReceiver.exe'
$loadSha='0548089E59C872306CE2C98E7163E2A717119756010CF64D3CB3DA2854F632CF'
foreach ($path in @($loadClient,$loadReceiver)) { if ((Get-FileHash -LiteralPath $path).Hash -ne $loadSha) { throw 'TCP_LOAD_ENGINE_HASH_MISMATCH' } }
$transferBytes=$(if ($Profile -eq 'SMOKE') {134217728L} else {8589934592L})
$rateLimit=$(if ($Profile -eq 'SMOKE') {8388608L} else {67108864L})
$messageBytes=512
$pauseMs=20
$manifest=[ordered]@{schema_version=1;status='RUNNING';profile=$Profile;scenario_id='tcp_loaded_echo_rtt_v1';started_at_utc=[DateTime]::UtcNow.ToString('o');pair_count=$pairs;echo_count=$echoCount;warmup_count=$warmup;message_bytes=$messageBytes;pause_ms=$pauseMs;transfer_bytes=$transferBytes;rate_limit_bytes_per_s=$rateLimit;runs=@();error='';version_switch_ready=$false}
if ($DiagnosticPull) { $manifest['diagnostic_only']=$true }
if ($ProxyNoDelay) { $manifest['proxy_accepted_tcp_nodelay']=$true }
if ($ProxyNoDelay -and -not $DiagnosticPull) { $manifest['tcp_fixture_revision']='accepted_nodelay_v1' }
$helperStopTimeoutMs=15000
function Write-Json($value,[string]$path) { $value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8 }
function Save-Manifest { Write-Json $manifest (Join-Path $EvidenceDirectory 'comparison-manifest.json') }
function Qpc-Ms { return [Diagnostics.Stopwatch]::GetTimestamp()*1000.0/[Diagnostics.Stopwatch]::Frequency }
function Start-Worker([string]$name,[string]$exe,[string[]]$arguments,$workers) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$exe; $info.Arguments=Join-ProcessArguments $arguments; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($info)
    $worker=[pscustomobject]@{name=$name;process=$process;stdout=$process.StandardOutput.ReadToEndAsync();stderr=$process.StandardError.ReadToEndAsync()}
    $workers.Add($worker)
    return $worker
}
function Wait-Event($worker,[string]$path,[int]$expectedCount=1) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt 5000) {
        if ($worker.process.HasExited) { throw "TCP_HELPER_EARLY_EXIT_$($worker.name)" }
        if (Test-Path $path) { if (@(Get-Content $path | Where-Object {$_} | ConvertFrom-Json | Where-Object event -eq 'LISTENING').Count -eq $expectedCount) { return } }
        Start-Sleep -Milliseconds 50
    }
    throw "TCP_HELPER_NOT_READY_$($worker.name)"
}
function Read-LoadProgress([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
    try { $text=$reader.ReadToEnd() } finally { $reader.Dispose() }
    $lastNewline=$text.LastIndexOf("`n")
    if ($lastNewline -lt 0) { return $null }
    $lines=@($text.Substring(0,$lastNewline+1) -split '\r?\n' | Where-Object {$_})
    if ($lines.Count -lt 2) { return $null }
    $row=@($lines[0],$lines[-1]) | ConvertFrom-Csv
    if ($null -eq $row -or @($row.PSObject.Properties).Count -lt 7) { return $null }
    $culture=[Globalization.CultureInfo]::InvariantCulture
    return [pscustomobject]@{time_slice=[double]::Parse($row.TimeSlice,$culture);send_bps=[double]::Parse($row.SendBps,$culture);recv_bps=[double]::Parse($row.RecvBps,$culture);in_flight=[int]$row.'In-Flight';completed=[int]$row.Completed;net_errors=[int]$row.NetError;data_errors=[int]$row.DataError;observed_qpc_ms=(Qpc-Ms)}
}
function Assert-Off {
    $state=Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
    $loaded=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
    $processes=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe'))
    if (-not $state.current_driver_preparation_allowed -or -not $state.wfp_detachment_observed -or $state.wfp.service_state -ne 'Stopped' -or -not $loaded.query_complete -or -not $loaded.known_interception_driver_names_absent -or $processes.Count) { throw 'TCP_REQUIRES_CONFIRMED_PRODUCT_OFF' }
    return [pscustomobject]@{state=$state;loaded=$loaded}
}
function Invoke-TcpRun([string]$direction,[string]$mode,[string]$directory) {
    $null=New-Item -ItemType Directory -Path $directory
    $workers=[Collections.Generic.List[object]]::new()
    $receipt=[ordered]@{status='RUNNING';mode=$mode;traffic_generated=$false;workers_stopped=$false;driver_stop_observed=$false;receiver_identity_verified=$false;version_switch_ready=$false;error=''}
    $receipt['helper_stop_timeout_ms']=$helperStopTimeoutMs
    $receipt['load_receiver_identity_verified']=$false
    $startedProduct=$false
    $native=$null
    $adapter=New-SystemProcessAdapter
    try {
        $before=Assert-Off
        Write-Json $before.state (Join-Path $directory 'interception-before.json')
        Write-Json $before.loaded (Join-Path $directory 'loaded-drivers-before.json')
        Write-Json $identity (Join-Path $directory 'product-build.json')
        foreach ($port in @(54122,54123,54125,54126)) { if (@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count) { throw 'TCP_PORT_IN_USE' } }
        $runId=[guid]::NewGuid().ToString()
        $receiverLog=Join-Path $directory 'receiver.jsonl'
        $clientLog=Join-Path $directory 'client.jsonl'
        $common=@('--mode','single','--family','4','--protocol','tcp','--local-ip','127.0.0.1','--local-port','0','--remote-ip','127.0.0.1','--tcp-remote-port','54122','--tcp-rtt','1','--stream-count',"$($echoCount+$warmup)",'--benchmark-message-size',"$messageBytes",'--stream-interval-ms',"$pauseMs",'--test-id','local_tcp_echo_rtt','--run-id',$runId,'--jsonl-log',$clientLog,'--expected-action',$(if ($mode -eq 'OFF') {'DIRECT'} else {'PROXY'}),'--tcp-peer-policy','record-only','--expect','echo','--timeout-ms','3000')
        $server=Start-Worker 'receiver' $PythonPath @('-u',$receiver,'--jsonl-log',$receiverLog,'--endpoint-a-port','54122','--endpoint-b-port','54125','--control-stdin','--log-flush-mode','BUFFERED','--tcp-nodelay') $workers
        Wait-Event $server $receiverLog 8
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while ($timer.ElapsedMilliseconds -lt 5000) {
            if ($server.process.HasExited) { throw 'TCP_RECEIVER_EARLY_EXIT' }
            if (@(Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort 54122 -State Listen -OwningProcess $server.process.Id -ErrorAction SilentlyContinue).Count -eq 1) { $receipt.receiver_identity_verified=$true; break }
            Start-Sleep -Milliseconds 50
        }
        if (-not $receipt.receiver_identity_verified) { throw 'TCP_RECEIVER_NOT_READY' }
        $loadCommon=@('-protocol:tcp',('-pattern:'+$direction),('-transfer:'+$transferBytes),('-ratelimit:'+$rateLimit),'-verify:data','-port:54126','-buffer:65536','-consoleverbosity:1','-statusupdate:250')
        $bulkServer=Start-Worker 'load-receiver' $loadReceiver (@('-listen:127.0.0.1','-serverexitlimit:1',('-connectionfilename:'+(Join-Path $directory 'load-receiver.csv')),('-statusfilename:'+(Join-Path $directory 'load-receiver-status.csv')))+$loadCommon) $workers
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while ($timer.ElapsedMilliseconds -lt 5000) {
            if ($bulkServer.process.HasExited) { throw 'TCP_LOAD_RECEIVER_EARLY_EXIT' }
            if (@(Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort 54126 -State Listen -OwningProcess $bulkServer.process.Id -ErrorAction SilentlyContinue).Count -eq 1) { $receipt.load_receiver_identity_verified=$true;break }
            Start-Sleep -Milliseconds 50
        }
        if (-not $receipt.load_receiver_identity_verified) { throw 'TCP_LOAD_RECEIVER_NOT_READY' }
        $proxyLog=Join-Path $directory 'proxy.jsonl'
        $proxy=Start-Worker 'proxy' $PythonPath @('-u',$proxyHelper,'--wheel',$wheel,'--jsonl-log',$proxyLog,'--port','54123','--receiver-port','54122','--additional-receiver-port','54126','--max-duration-seconds','300') $workers
        Wait-Event $proxy $proxyLog
        $samplerLog=Join-Path $directory 'pc-samples.jsonl'
        $samplerConfig=Join-Path $directory 'sampler-config.json'
        Write-Json @([ordered]@{role='receiver';pid=$server.process.Id;path=$PythonPath},[ordered]@{role='proxy';pid=$proxy.process.Id;path=$PythonPath},[ordered]@{role='load_receiver';pid=$bulkServer.process.Id;path=$loadReceiver}) $samplerConfig
        $sampler=Start-Worker 'sampler' $PythonPath @('-u',(Join-Path $root 'src/pb_pc_sampler.py'),'--packages',$packages,'--config',$samplerConfig,'--jsonl-log',$samplerLog,'--max-duration-seconds','300') $workers
        Wait-Event $sampler $samplerLog
        Write-Json ([ordered]@{scenario_id='tcp_loaded_echo_rtt_v1';run_id=$runId;echo_count=$echoCount;warmup_count=$warmup;message_bytes=$messageBytes;pause_ms=$pauseMs;connections=1;client_tcp_nodelay=$true;receiver_tcp_nodelay=$true;receiver_log_mode='BUFFERED';receiver_port=54122;proxy_port=54123;proxy_event_loop='_WindowsSelectorEventLoop';engine_sha256=$engineSha;source_sha256=(Get-FileHash (Join-Path $root 'src/pb_net_client.c')).Hash;receiver_helper_sha256=(Get-FileHash $receiver).Hash;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;proxy_helper_sha256=(Get-FileHash $proxyHelper).Hash;sampler_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash;python_sha256=(Get-FileHash $PythonPath).Hash;receiver_pid=$server.process.Id;proxy_pid=$proxy.process.Id;sampler_pid=$sampler.process.Id;load=[ordered]@{direction=$direction;transfer_bytes=$transferBytes;rate_limit_bytes_per_s=$rateLimit;receiver_port=54126;receiver_pid=$bulkServer.process.Id;engine_sha256=$loadSha;verify='data';buffer_bytes=65536;status_interval_ms=250;progress_poll_ms=100;progress_max_gap_ms=1000;minimum_rate_fraction=0.05}}) (Join-Path $directory 'benchmark-config.json')
        if ($ProxyNoDelay) {
            $diagnosticConfig=Get-Content -LiteralPath (Join-Path $directory 'benchmark-config.json') -Raw | ConvertFrom-Json
            $diagnosticConfig | Add-Member -NotePropertyName proxy_accepted_tcp_nodelay -NotePropertyValue $true
            $diagnosticConfig | Add-Member -NotePropertyName proxy_base_helper_sha256 -NotePropertyValue (Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash
            if (-not $DiagnosticPull) { $diagnosticConfig | Add-Member -NotePropertyName tcp_fixture_revision -NotePropertyValue 'accepted_nodelay_v1' }
            Write-Json $diagnosticConfig (Join-Path $directory 'benchmark-config.json')
        }
        $workload={
            param($cli)
            if ($mode -eq 'PROXY') {
                $active=Get-LoadedInterceptionDriverObservation -AllowProductRuntime
                Write-Json $active (Join-Path $directory 'loaded-drivers-active.json')
                if (-not $active.query_complete -or -not $active.selected_driver_loaded -or $active.known_interception_drivers.Count -ne 1) { throw 'TCP_SELECTED_ACTIVE_DRIVER_NOT_CONFIRMED' }
                Write-Json @(Get-NetTCPConnection -State Listen -OwningProcess $cli.pid | Select-Object LocalAddress,LocalPort,OwningProcess) (Join-Path $directory 'product-tcp-listeners.json')
                $sampler.process.StandardInput.WriteLine(([ordered]@{role='proxybridge_cli';pid=$cli.pid;path=$cli.actual_path} | ConvertTo-Json -Compress));$sampler.process.StandardInput.Flush()
            }
            Start-Sleep -Milliseconds 1000
            $bulk=$null;$native=$null;$progress=$null
            $statusPath=Join-Path $directory 'load-client-status.csv'
            $bulkArgs=@('-target:127.0.0.1','-connections:1','-iterations:1','-shutdown:graceful',('-connectionfilename:'+(Join-Path $directory 'load-client.csv')),('-statusfilename:'+$statusPath))+$loadCommon
            $loadStart=Qpc-Ms
            try {
                $bulk=& $adapter.StartProcess ([pscustomobject]@{executable=$loadClient;arguments=$bulkArgs;timeout_ms=240000})
                $probe=& $adapter.ProbeActualPath $bulk 2000 25
                if ($probe.status -ne 'PATH_OBTAINED' -or $bulk.actual_path -ine $loadClient) { throw 'TCP_LOAD_CLIENT_IDENTITY_NOT_CONFIRMED' }
                $sampler.process.StandardInput.WriteLine(([ordered]@{role='load_generator';pid=$bulk.pid;path=$bulk.actual_path} | ConvertTo-Json -Compress));$sampler.process.StandardInput.Flush()
                $progress=[IO.StreamWriter]::new((Join-Path $directory 'load-progress.jsonl'),$false,[Text.UTF8Encoding]::new($false),262144)
                $lastSlice=-1.0;$ready=$null;$wait=[Diagnostics.Stopwatch]::StartNew()
                while ($wait.ElapsedMilliseconds -lt 10000) {
                    if (-not $bulk.session.IsRunning) { throw 'TCP_LOAD_ENDED_BEFORE_RTT' }
                    $row=Read-LoadProgress $statusPath
                    if ($row -and $row.time_slice -gt $lastSlice) {
                        $lastSlice=$row.time_slice;$row | Add-Member -NotePropertyName pid -NotePropertyValue $bulk.pid
                        $progress.WriteLine(($row | ConvertTo-Json -Compress))
                        $bps=$(if ($direction -eq 'push') {$row.send_bps} else {$row.recv_bps})
                        if ($bps -ge $rateLimit*0.05 -and $row.in_flight -eq 1 -and $row.net_errors -eq 0 -and $row.data_errors -eq 0) { $ready=$row;break }
                    }
                    Start-Sleep -Milliseconds 100
                }
                if (-not $ready) { throw 'TCP_LOAD_PROGRESS_NOT_CONFIRMED' }
                $start=Qpc-Ms
                $native=& $adapter.StartProcess ([pscustomobject]@{executable=$client;arguments=$common;timeout_ms=180000})
                $probe=& $adapter.ProbeActualPath $native 2000 25
                if ($probe.status -ne 'PATH_OBTAINED' -or $native.actual_path -ine $client) { throw 'TCP_CLIENT_IDENTITY_NOT_CONFIRMED' }
                $sampler.process.StandardInput.WriteLine(([ordered]@{role='generator';pid=$native.pid;path=$native.actual_path} | ConvertTo-Json -Compress));$sampler.process.StandardInput.Flush()
                $receipt.traffic_generated=$true
                $wait.Restart()
                while ($native.session.IsRunning -and $wait.ElapsedMilliseconds -lt 180000) {
                    $row=Read-LoadProgress $statusPath
                    if ($row -and $row.time_slice -gt $lastSlice) {
                        $lastSlice=$row.time_slice;$row | Add-Member -NotePropertyName pid -NotePropertyValue $bulk.pid
                        $progress.WriteLine(($row | ConvertTo-Json -Compress))
                    }
                    if (-not $bulk.session.IsRunning) { throw 'TCP_LOAD_ENDED_DURING_RTT' }
                    Start-Sleep -Milliseconds 100
                }
                if ($native.session.IsRunning) { $native.timed_out=$true;throw 'TCP_CLIENT_TIMEOUT' }
                $end=Qpc-Ms
                $loadStillRunning=$bulk.session.IsRunning
                Write-Json ([ordered]@{start_qpc_ms=$start;end_qpc_ms=$end;client_pid=$native.pid}) (Join-Path $directory 'measurement-window.json')
                if (-not $loadStillRunning) { throw 'TCP_LOAD_ENDED_AT_RTT_EXIT' }
                $result=& $adapter.GetProcessResult $native
                if ($result.exit_code -ne 0 -or $result.timed_out -or -not $result.output_capture_complete) { throw 'TCP_CLIENT_FAILED' }
                $remaining=[Math]::Max(1,240000-[int]((Qpc-Ms)-$loadStart))
                if (-not $bulk.session.WaitForExit($remaining)) { $bulk.timed_out=$true;throw 'TCP_LOAD_CLIENT_TIMEOUT' }
                $loadEnd=Qpc-Ms
                $bulkResult=& $adapter.GetProcessResult $bulk
                Write-Json ([ordered]@{start_qpc_ms=$loadStart;ready_qpc_ms=$ready.observed_qpc_ms;end_qpc_ms=$loadEnd;client_pid=$bulk.pid;load_running_at_rtt_exit=$loadStillRunning}) (Join-Path $directory 'load-window.json')
                if ($bulkResult.exit_code -ne 0 -or $bulkResult.timed_out -or -not $bulkResult.output_capture_complete) { throw 'TCP_LOAD_CLIENT_FAILED' }
                if (-not $bulkServer.process.WaitForExit(15000)) { throw 'TCP_LOAD_RECEIVER_DID_NOT_FINISH' }
                return $result
            } finally {
                if ($progress) { $progress.Dispose() }
                foreach ($item in @(@{process=$native;name='client'},@{process=$bulk;name='load-client'})) {
                    if ($null -ne $item.process) {
                        $forced=$false
                        try {
                            if ($item.process.session.IsRunning) {
                                $null=& $adapter.StopProcess $item.process 1000
                                if ($item.process.session.IsRunning) { & $adapter.KillProcess $item.process; $forced=$true }
                            }
                            $completion=& $adapter.GetProcessResult $item.process
                            $completion | Add-Member -NotePropertyName forced_stop -NotePropertyValue $forced
                            Write-Json $completion (Join-Path $directory ($item.name+'-process.json'))
                        } finally { & $adapter.DisposeProcess $item.process }
                    }
                }
            }
        }.GetNewClosure()
        if ($mode -eq 'PROXY') {
            $runtimeConfig=Get-Content (Join-Path $root 'config/runtime.json') -Raw | ConvertFrom-Json
            $runtimePlan=New-RuntimeEnvironmentPlan -Environment $environment -RuntimeConfig $runtimeConfig -ProductOnly
            if ($runtimePlan.service_bootstrap -ne 'driver-service') { throw 'TCP_REQUIRES_HEADLESS_KIT' }
            $startedProduct=$true
            $preparation=Invoke-RuntimeEnvironmentPreparation -Plan $runtimePlan -Adapter (New-SystemRuntimeEnvironmentAdapter) -AllowProductRuntime
            Write-Json $preparation (Join-Path $directory 'preparation-result.json')
            if (-not $preparation.prepared) { throw 'TCP_PRODUCT_PREPARATION_FAILED' }
            $profilePath=Join-Path $directory 'route.pbprofile'
            Write-Json ([ordered]@{Version='1.0';LocalhostViaProxy=$true;IsTrafficLoggingEnabled=$true;ProxyConfigs=@([ordered]@{Id=1;Name='Controlled TCP SOCKS5';Type='SOCKS5';Host='127.0.0.1';Port='54123';Username='';Password='';SendDomainToProxy=$false});ProxyRules=@([ordered]@{Name='TCP request and response latency';ProcessName='pb_tcp_rtt_client.exe';TargetHosts='127.0.0.1';TargetPorts='54122';TargetDomains='';Protocol='TCP';Action='PROXY';ProxyConfigId=1;IsEnabled=$true},[ordered]@{Name='Concurrent TCP transfer';ProcessName='ctsTraffic.exe';TargetHosts='127.0.0.1';TargetPorts='54126';TargetDomains='';Protocol='TCP';Action='PROXY';ProxyConfigId=1;IsEnabled=$true})}) $profilePath
            $cliPlan=New-ProxyBridgeCliPlan -ExecutablePath $environment['PB_PROXYBRIDGE_CLI_EXE'] -ProfilePath $profilePath -ProductProfileContract driver -CliVariant $environment['PB_PROXYBRIDGE_CLI_VARIANT'] -ReadyStableMs 1000 -ReadinessTimeoutMs 10000 -StopTimeoutMs 5000
            $sink={param($value) Write-Json $value (Join-Path $directory 'cli-lifecycle.json')}.GetNewClosure()
            $lifecycle=Invoke-ProxyBridgeCliLifecycle -Plan $cliPlan -ProcessAdapter $adapter -AllowProductRuntime -Workload $workload -EvidenceSink $sink
            if (-not $lifecycle.ready -or -not $lifecycle.graceful_stop -or $lifecycle.forced_stop -or -not $lifecycle.post_stop_verified -or $lifecycle.process_result.exit_code -ne 0) { throw 'TCP_CLI_LIFECYCLE_FAILED' }
            $records=@(ConvertFrom-ProxyBridgeTextLines -Lines @($lifecycle.process_result.stdout -split '\r?\n') -DefaultTimestampUtc ([DateTime]::Parse($lifecycle.started_at_utc)))
            Write-Json $records (Join-Path $directory 'route-observations.json')
        } else { $null=& $workload $null }
        $receipt.status='COMPLETED'
    } catch { $receipt.status='FAILED';$receipt.error=$_.Exception.Message }
    finally {
        $clean=$true
        foreach ($worker in $workers) {
            $forced=$false
            try {
                if (-not $worker.process.HasExited -and $worker.name -ne 'load-receiver') { $worker.process.StandardInput.WriteLine('STOP');$worker.process.StandardInput.Flush() }
                if (-not $worker.process.WaitForExit($helperStopTimeoutMs)) {
                    $receipt.error+='; TCP_HELPER_STOP_TIMEOUT_'+$worker.name+'_'+$helperStopTimeoutMs+'ms'
                    $worker.process.Kill();$worker.process.WaitForExit();$forced=$true
                }
                $out=$worker.stdout.GetAwaiter().GetResult();$err=$worker.stderr.GetAwaiter().GetResult()
                Write-Json ([ordered]@{pid=$worker.process.Id;exit_code=$worker.process.ExitCode;forced_stop=$forced;stdout=$out;stderr=$err;output_capture_complete=$true}) (Join-Path $directory ($worker.name+'-process.json'))
                if ($forced -or $worker.process.ExitCode -ne 0) {
                    $clean=$false
                    $receipt.error+='; TCP_HELPER_EXIT_NOT_CLEAN_'+$worker.name+'_exit'+$worker.process.ExitCode+'_forced'+$forced
                }
            } catch { $clean=$false;$receipt.error+='; helper cleanup: '+$_.Exception.Message }
            finally { if (-not $worker.process.HasExited) { $worker.process.Kill();$worker.process.WaitForExit() };$worker.process.Dispose() }
        }
        $receipt.workers_stopped=$clean
        try {
            if ($startedProduct) {
                $stopState=Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
                if ($stopState.wfp.status -ne 'SERVICE_FILE_VERIFIED') { throw 'TCP_DRIVER_IDENTITY_CHANGED' }
                $scm=[ServiceProcess.ServiceController]::new('ProxyBridgeDrv')
                try { if ($scm.Status -eq [ServiceProcess.ServiceControllerStatus]::Running) { $scm.Stop() };$scm.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(10)) } finally { $scm.Dispose() }
            }
            $after=Assert-Off
            Write-Json $after.state (Join-Path $directory 'interception-after.json')
            Write-Json $after.loaded (Join-Path $directory 'loaded-drivers-after.json')
            $receipt.driver_stop_observed=$true
        } catch { $receipt.error+='; driver cleanup: '+$_.Exception.Message }
        if (-not $receipt.workers_stopped -or -not $receipt.driver_stop_observed) { $receipt.status='FAILED' }
        Write-Json $receipt (Join-Path $directory 'run-receipt.json')
    }
    if ($receipt.status -ne 'COMPLETED') {
        if (-not $receipt.error) { $receipt.error='TCP_RUN_NOT_COMPLETED_WITHOUT_DETAIL';Write-Json $receipt (Join-Path $directory 'run-receipt.json') }
        throw $receipt.error
    }
    & $PythonPath (Join-Path $root 'src/pb_tcp_loaded_rtt_report.py') --run-directory $directory
    if ($LASTEXITCODE -ne 0) { throw 'TCP_EVIDENCE_NOT_CONFIRMED' }
}
if ($Resume) {
    $reply=& $PythonPath (Join-Path $root 'src/pb_tcp_loaded_rtt_report.py') --validate-resume $EvidenceDirectory | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'TCP_RESUME_EVIDENCE_NOT_CONFIRMED' }
    $resumePlan=$reply | ConvertFrom-Json
    $old=Get-Content -LiteralPath (Join-Path $EvidenceDirectory 'comparison-manifest.json') -Raw | ConvertFrom-Json
    $oldNoDelay=$old.PSObject.Properties['proxy_accepted_tcp_nodelay'] -and $old.proxy_accepted_tcp_nodelay
    if ([bool]$oldNoDelay -ne [bool]$ProxyNoDelay) { throw 'TCP_RESUME_NODELAY_CHANGED' }
    if ($ProxyNoDelay -and (-not $old.PSObject.Properties['tcp_fixture_revision'] -or $old.tcp_fixture_revision -ne 'accepted_nodelay_v1')) { throw 'TCP_RESUME_FIXTURE_CHANGED' }
    foreach ($key in @('profile','scenario_id','pair_count','echo_count','warmup_count','message_bytes','pause_ms','transfer_bytes','rate_limit_bytes_per_s')) {
        if ($old.$key -ne $manifest[$key]) { throw ('TCP_RESUME_PROFILE_CHANGED_'+$key) }
    }
    $reference=Get-Content -LiteralPath (Join-Path (Join-Path $EvidenceDirectory $resumePlan.retained[0].directory) 'tcp-loaded-rtt-report.json') -Raw | ConvertFrom-Json
    if ($reference.bundle_sha256 -ne $identity.bundle_sha256) { throw 'TCP_RESUME_PRODUCT_CHANGED' }
    $referenceNoDelay=$reference.config.PSObject.Properties['proxy_accepted_tcp_nodelay'] -and $reference.config.proxy_accepted_tcp_nodelay
    if ([bool]$referenceNoDelay -ne [bool]$ProxyNoDelay) { throw 'TCP_RESUME_CONFIG_NODELAY_CHANGED' }
    $expected=[ordered]@{scenario_id='tcp_loaded_echo_rtt_v1';echo_count=$echoCount;warmup_count=$warmup;message_bytes=$messageBytes;pause_ms=$pauseMs;connections=1;client_tcp_nodelay=$true;receiver_tcp_nodelay=$true;receiver_log_mode='BUFFERED';receiver_port=54122;proxy_port=54123;proxy_event_loop='_WindowsSelectorEventLoop';engine_sha256=$engineSha;source_sha256=(Get-FileHash (Join-Path $root 'src/pb_net_client.c')).Hash;receiver_helper_sha256=(Get-FileHash $receiver).Hash;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;proxy_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash;sampler_helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_pc_sampler.py')).Hash;python_sha256=(Get-FileHash $PythonPath).Hash}
    $expectedLoad=[ordered]@{transfer_bytes=$transferBytes;rate_limit_bytes_per_s=$rateLimit;receiver_port=54126;engine_sha256=$loadSha;verify='data';buffer_bytes=65536;status_interval_ms=250;progress_poll_ms=100;progress_max_gap_ms=1000;minimum_rate_fraction=0.05}
    $expected['proxy_helper_sha256']=(Get-FileHash $proxyHelper).Hash
    if ($ProxyNoDelay) {
        $expected['proxy_accepted_tcp_nodelay']=$true
        $expected['proxy_base_helper_sha256']=(Get-FileHash (Join-Path $root 'src/pb_controlled_tcp_proxy.py')).Hash
        $expected['tcp_fixture_revision']='accepted_nodelay_v1'
    }
    foreach ($key in $expected.Keys) { if ($reference.config.$key -ne $expected[$key]) { throw ('TCP_RESUME_CONDITIONS_CHANGED_'+$key) } }
    foreach ($key in $expectedLoad.Keys) { if ($reference.config.load.$key -ne $expectedLoad[$key]) { throw ('TCP_RESUME_LOAD_CHANGED_'+$key) } }
    $current=Assert-Off
    if ($current.loaded.other_driver_names_sha256 -ne $reference.other_driver_names_sha256) { throw 'TCP_RESUME_DRIVER_INVENTORY_CHANGED' }
    $backup='comparison-manifest-before-resume-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.json'
    Copy-Item -LiteralPath (Join-Path $EvidenceDirectory 'comparison-manifest.json') -Destination (Join-Path $EvidenceDirectory $backup)
    $manifest.started_at_utc=$old.started_at_utc
    $manifest.runs=@($resumePlan.retained)
    $history=@();if ($old.PSObject.Properties['failed_attempts']) { $history=@($old.failed_attempts) }
    $manifest['failed_attempts']=$history+@($resumePlan.failed)
    $manifest['resumed_at_utc']=[DateTime]::UtcNow.ToString('o')
    $manifest['retained_completed_runs']=$manifest.runs.Count
    Write-Host ('Возобновление / Resume: '+$manifest.runs.Count+' completed runs retained; '+$resumePlan.remaining+' runs remaining. Excluded attempts remain in history.')
}
Write-Host ('TCP RTT under concurrent '+$transferBytes+' byte transfer @ '+$rateLimit+' bytes/s: '+$Profile+'; push + pull; '+$pairs+' pairs/direction; '+$echoCount+' echoes + '+$warmup+' warmup; SOCKS5 vs direct.')
Write-Host 'Одновременная передача и RTT на разных контролируемых портах / Concurrent verified transfer and RTT on separate controlled ports. Rate-capped load; not maximum throughput, ICMP or game-stability evidence.'
if ($ProxyNoDelay) { Write-Host 'SOCKS5-стенд: accepted TCP_NODELAY=1 с проверкой сокетов; новая конфигурация, не смешивать с прежними сериями / Accepted TCP_NODELAY=1 verified; do not mix with legacy fixture results.' }
Write-Host $(if ($DiagnosticPull) {'Отдельная диагностика download, один PROXY run / Isolated diagnostic download; not comparison. Approximately 3–5 minutes.'} elseif ($Profile -eq 'SMOKE') {'Ориентировочно 2–5 минут / Approximately 2–5 minutes; readiness only.'} elseif ($Resume) {'Остаток ориентировочно 12–16 минут / Remaining approximately 12–16 minutes for five runs.'} else {'Ориентировочно 25–35 минут / Approximately 25–35 minutes; 12 x 8 GiB loopback payload, no payload files.'})
Write-Host ('Результаты / Results: '+$EvidenceDirectory)
Save-Manifest
try {
    foreach ($direction in @('push','pull')) {
        for ($pair=1;$pair -le $pairs;$pair++) {
            $order=$(if ($pair % 2) { @('OFF','PROXY') } else { @('PROXY','OFF') })
            foreach ($mode in $order) {
                if ($DiagnosticPull -and ($direction -ne 'pull' -or $pair -ne 1 -or $mode -ne 'PROXY')) { continue }
                $name='{0}-pair-{1:d2}-{2}' -f $direction,$pair,$mode.ToLowerInvariant()
                $existing=@($manifest.runs | Where-Object {$_.direction -eq $direction -and $_.pair -eq $pair -and $_.mode -eq $mode})
                if ($existing.Count) { continue }
                if (Test-Path -LiteralPath (Join-Path $EvidenceDirectory $name)) { $name+='-retry-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6) }
                $entry=[ordered]@{direction=$direction;pair=$pair;mode=$mode;directory=$name;status='RUNNING'}
                $manifest.runs+=$entry;Save-Manifest
                Write-Host ('['+$manifest.runs.Count+'/'+$(if ($DiagnosticPull) {1} else {$pairs*4})+'] '+$name)
                Invoke-TcpRun $direction $mode (Join-Path $EvidenceDirectory $name)
                $entry.status='COMPLETED';Save-Manifest
            }
        }
    }
    $manifest.status='COMPLETED'
} catch { $manifest.status='FAILED';$manifest.error=$(if ($_.Exception.Message) { $_.Exception.Message } else { 'TCP_LOADED_RTT_SERIES_FAILED_WITHOUT_DETAIL' }) }
finally { $manifest['completed_at_utc']=[DateTime]::UtcNow.ToString('o');Save-Manifest }
if ($manifest.status -ne 'COMPLETED') { throw $manifest.error }
if ($DiagnosticPull) { Write-Host 'Диагностический run завершён / Diagnostic run completed; no paired comparison';return }
& $PythonPath (Join-Path $root 'src/pb_tcp_loaded_rtt_report.py') --evidence-directory $EvidenceDirectory
if ($LASTEXITCODE -ne 0) { throw 'TCP_LOADED_RTT_COMPARISON_NOT_CONFIRMED' }
Write-Host ('Отчёт / Report: '+(Join-Path $EvidenceDirectory 'summary.md'))
