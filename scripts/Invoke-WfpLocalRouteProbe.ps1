#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvPath,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [ValidateRange(1024,65533)][int]$BasePort = 53121,
    [ValidateSet('SOCKS5','HTTP')][string]$ProxyType = 'SOCKS5',
    [ValidateSet('DIRECT','PROXY')][string[]]$Actions = @('DIRECT','PROXY'),
    [ValidateSet('TCP','UDP')][string]$Protocol = 'TCP',
    [ValidateSet('RULES','UNRULED','OFF')][string]$TrafficMode = 'RULES',
    [string]$UdpProxyPythonPath = '',
    [switch]$UdpBenchmark,
    [switch]$MatchedComparisonWorkload,
    [ValidateRange(16,40000)][int]$BenchmarkPacketCount = 64,
    [ValidateRange(0,200)][int]$BenchmarkIntervalMs = 100,
    [ValidateRange(0,1200)][int]$BenchmarkMessageSize = 0,
    [ValidateRange(8,1000)][int]$BenchmarkWarmupPackets = 8,
    [ValidateRange(1,4)][int]$BenchmarkStreams = 1,
    [ValidateSet('SHARED','DISTINCT')][string]$BenchmarkDestinationMode = 'SHARED',
    [ValidateSet('FLUSH_EACH','BUFFERED')][string]$EvidenceLogMode = 'FLUSH_EACH',
    [switch]$AllowProductRuntime
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $AllowProductRuntime) { throw 'PRODUCT_RUNTIME_NOT_ALLOWED' }
if ($EvidenceLogMode -eq 'BUFFERED' -and -not $UdpBenchmark) { throw 'BUFFERED_EVIDENCE_REQUIRES_UDP_BENCHMARK' }
if ($MatchedComparisonWorkload -and -not $UdpBenchmark) { throw 'MATCHED_WORKLOAD_REQUIRES_UDP_BENCHMARK' }
if ($BenchmarkMessageSize -gt 0 -and ($BenchmarkMessageSize -lt 256 -or -not $UdpBenchmark)) { throw 'IDENTIFIED_MESSAGE_SIZE_REQUIRES_BENCHMARK_AND_256_TO_1200_BYTES' }
if ($BenchmarkStreams -gt 1 -and -not $UdpBenchmark) { throw 'MULTIPLE_STREAMS_REQUIRE_UDP_BENCHMARK' }
if ($BenchmarkDestinationMode -eq 'DISTINCT' -and (-not $UdpBenchmark -or $BenchmarkStreams -ne 2)) { throw 'DISTINCT_DESTINATIONS_REQUIRE_TWO_UDP_STREAMS' }
$benchmarkDestinationPorts = @($BasePort+1)
if ($BenchmarkDestinationMode -eq 'DISTINCT') { $benchmarkDestinationPorts += $BasePort }
if ($BenchmarkPacketCount % $BenchmarkStreams -ne 0) { throw 'BENCHMARK_PACKET_COUNT_MUST_DIVIDE_BY_STREAMS' }
$packetsPerStream = [int]($BenchmarkPacketCount / $BenchmarkStreams)
if ($packetsPerStream -gt 20000) { throw 'BENCHMARK_MAXIMUM_20000_PACKETS_PER_STREAM' }
if ($UdpBenchmark -and $packetsPerStream -le $BenchmarkWarmupPackets) { throw 'BENCHMARK_REQUIRES_PACKETS_AFTER_WARMUP' }
if ($TrafficMode -in @('UNRULED','OFF')) { $Actions = @('DIRECT') }
if ($TrafficMode -eq 'OFF' -and ($Protocol -ne 'UDP' -or -not $UdpBenchmark)) { throw 'PRODUCT_OFF_REQUIRES_UDP_BENCHMARK' }
if ($Protocol -eq 'UDP' -and ($ProxyType -ne 'SOCKS5' -or ($TrafficMode -eq 'RULES' -and $Actions -contains 'DIRECT'))) { throw 'UDP_PROBE_SUPPORTS_SOCKS5_PROXY_OR_UNRULED_ONLY' }
if ($UdpBenchmark -and ($Protocol -ne 'UDP' -or $ProxyType -ne 'SOCKS5' -or $Actions.Count -ne 1 -or ($TrafficMode -eq 'RULES' -and $Actions[0] -ne 'PROXY'))) { throw 'BENCHMARK_REQUIRES_UDP_SOCKS5_PROXY_OR_UNRULED' }
$root = Split-Path -Parent $PSScriptRoot
foreach ($module in @('Env','ProductBuild','RuntimeEnvironment','InterceptionState','ProxyBridgeCli','ProcessAdapter','ProxyBridgeEvidence')) { Import-Module (Join-Path $root ('modules/' + $module + '.psm1')) }
if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'PROBE_REQUIRES_NEW_EVIDENCE_DIRECTORY' }
$null = New-Item -ItemType Directory -Path $EvidenceDirectory
$EvidenceDirectory = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
$environment = Import-DotEnv -Path $EnvPath
$python = Join-Path $root 'bin/dev-venv/Scripts/python.exe'
$receiverPython = ''
$client = Join-Path $root 'bin/pb_net_client.exe'
$wheel = Join-Path $root 'bin/tools/pproxy-2.7.9/pproxy-2.7.9-py3-none-any.whl'
$proxyPython = $python
$proxyHost = Join-Path $root 'src/pb_controlled_proxy.py'
$proxyLibrary = 'pproxy'
$proxyVersion = '2.7.9'
$wheelSha256 = 'a073d02616a47c43e1d20a547918c307dbda598c6d53869b165025f3cfe58e80'
if ($Protocol -eq 'UDP') {
    $proxyPython = $UdpProxyPythonPath
    $proxyHost = Join-Path $root 'src/pb_controlled_udp_proxy.py'
    $proxyLibrary = 'asyncio-socks-server'
    $proxyVersion = '1.3.3'
    $wheel = Join-Path $root 'bin/tools/asyncio-socks-server-1.3.3/asyncio_socks_server-1.3.3-py3-none-any.whl'
    $wheelSha256 = '5190d3ae00a29325ec9048306fcd8bd08f8e89ddd75c535cc01d1d646f105344'
}
$receiverLog = Join-Path $EvidenceDirectory 'receiver.jsonl'
$proxyLog = Join-Path $EvidenceDirectory 'proxy.jsonl'
$runId = 'local-' + [guid]::NewGuid().ToString('N')
$benchmarkTestId = $(if ($TrafficMode -in @('UNRULED','OFF')) { 'local-udp-unruled' } else { 'local-udp-proxy' })
if ($MatchedComparisonWorkload) { $benchmarkTestId = 'local-udp-path-comparison' }
$workers = [Collections.Generic.List[object]]::new()
$receipt = [ordered]@{schema_version=1;status='NOT_COMPLETED';started_at_utc=[DateTime]::UtcNow.ToString('o');run_id=$runId;scope="IPv4 $Protocol $($Actions -join '/') via $ProxyType, loopback traffic only";traffic_generated=$false;route_verified=$false;benchmark_performed=$false;driver_stop_observed=$false;workers_stopped=$false;interception_cleanup_verified=$false;version_switch_ready=$false;cases=[Collections.Generic.List[object]]::new();reason=''}
$serviceStartAttempted = $false
# A zero pacing interval still needs time for network round trips and evidence writes.
# For the new larger parallel series, budget the longest stream; retain existing profiles' reserve.
$timeoutPacketCount = $(if ($BenchmarkPacketCount -gt 20000) { $packetsPerStream } else { $BenchmarkPacketCount })
$benchmarkTimeoutMs = $(if ($timeoutPacketCount -le 64) { 20000 } else { $timeoutPacketCount * [Math]::Max(20,$BenchmarkIntervalMs) * 2 + 30000 })
$workerBudgetSeconds = [int][Math]::Ceiling($benchmarkTimeoutMs / 1000.0) + 30
$udpProxyBudgetSeconds = $(if ($UdpBenchmark) { $workerBudgetSeconds } else { 60 })
$receipt['traffic_mode'] = $(if ($TrafficMode -eq 'OFF') { 'product-off-direct' } elseif ($TrafficMode -eq 'UNRULED') { 'product-running-unruled' } else { 'product-rules' })
$receipt['unruled_profile_verified'] = $false
$receipt['product_off_verified'] = $false
$receipt['receiver_process_identity_verified'] = $false
if ($TrafficMode -eq 'UNRULED') { $receipt.scope = "IPv4 $Protocol directly to loopback receiver with ProxyBridge running; client outside rules" }
if ($TrafficMode -eq 'OFF') { $receipt.scope = 'IPv4 UDP directly to loopback receiver; selected ProxyBridge stopped and not started' }
function Save-ProbeJson($Value, [string]$Name) { $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory $Name) -Encoding UTF8 }

function New-ProbeIndex([object[]]$Rows, [string]$Property) {
    $index = @{}
    foreach ($item in $Rows) {
        $field = $item.PSObject.Properties[$Property]
        if ($null -eq $field) { continue }
        $key = [string]$field.Value
        if (-not $index.ContainsKey($key)) { $index[$key] = [Collections.Generic.List[object]]::new() }
        $index[$key].Add($item)
    }
    return $index
}
function Start-ProbeWorker([string]$Name, [string[]]$Arguments, [string]$LogPath, [int]$ListenerCount, [string]$ExecutablePath = $python) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $ExecutablePath
    $info.Arguments = Join-ProcessArguments -Arguments $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    $worker = [pscustomobject]@{name=$Name;process=$process;stdout_task=$process.StandardOutput.ReadToEndAsync();stderr_task=$process.StandardError.ReadToEndAsync()}
    $workers.Add($worker)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt 5000) {
        if ($process.HasExited) { throw "PROBE_WORKER_EARLY_EXIT_$Name" }
        if (Test-Path -LiteralPath $LogPath) {
            $events = @(Get-Content -LiteralPath $LogPath | Where-Object { $_ } | ConvertFrom-Json)
            $listeners = @($events | Where-Object event -eq 'LISTENING')
            if ($listeners.Count -eq $ListenerCount) {
                if ($Name -eq 'receiver') {
                    if (@($listeners | Where-Object { $_.process_id -ne $process.Id }).Count) { throw 'RECEIVER_WORKER_PID_MISMATCH' }
                    $receipt.receiver_process_identity_verified = $true
                }
                return
            }
        }
        Start-Sleep -Milliseconds 50
    }
    throw "PROBE_WORKER_NOT_READY_$Name"
}
try {
    foreach ($file in @($python,$proxyPython,$proxyHost,$client,$wheel)) { if ([string]::IsNullOrWhiteSpace($file) -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "PROBE_DEPENDENCY_MISSING_$file" } }
    # Windows venv python.exe redirects to a child; observe the actual receiver interpreter.
    $receiverBase = @(& $python -c 'import sys; print(sys._base_executable)')
    if ($LASTEXITCODE -ne 0 -or $receiverBase.Count -ne 1) { throw 'RECEIVER_INTERPRETER_RESOLUTION_FAILED' }
    $receiverPython = ([string]$receiverBase[0]).Trim()
    if (-not (Test-Path -LiteralPath $receiverPython -PathType Leaf)) { throw 'RECEIVER_INTERPRETER_MISSING' }
    if ((Get-FileHash -LiteralPath $wheel).Hash.ToLowerInvariant() -ne $wheelSha256) { throw 'PROXY_WHEEL_DIGEST_MISMATCH' }
    $identity = Get-ProductBuildIdentity -Environment $environment -Contract driver
    Save-ProbeJson $identity 'product-build.json'
    if (-not $identity.files_verified) { throw 'PROBE_FILES_NOT_VERIFIED' }
    $before = Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
    Save-ProbeJson $before 'interception-before.json'
    if (-not $before.current_driver_preparation_allowed -or $before.wfp.service_state -ne 'Stopped') { throw 'PROBE_REQUIRES_VERIFIED_STOPPED_DRIVER' }
    $active = @(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object { $_.Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe','pb_net_client.exe') })
    if ($active.Count) { throw 'PROBE_PROCESS_CONFLICT' }
    if ($TrafficMode -in @('OFF','UNRULED') -or $UdpBenchmark) {
        $loadedBefore = Get-LoadedInterceptionDriverObservation -AllowProductRuntime
        Save-ProbeJson $loadedBefore 'loaded-drivers-before.json'
        if (-not $loadedBefore.query_complete -or -not $loadedBefore.known_interception_driver_names_absent) { throw 'BASELINE_KNOWN_INTERCEPTION_DRIVER_LOADED' }
        if ($TrafficMode -eq 'OFF') { $receipt.product_off_verified = $before.wfp_detachment_observed }
        if ($TrafficMode -eq 'OFF' -and -not $receipt.product_off_verified) { throw 'SELECTED_PRODUCT_OFF_NOT_CONFIRMED' }
    }
    Save-ProbeJson ([ordered]@{client_sha256=(Get-FileHash $client).Hash;python_version=(& $python --version);proxy_python_version=(& $proxyPython --version);proxy_python_path=$proxyPython;proxy_library=$proxyLibrary;proxy_version=$proxyVersion;proxy_wheel_sha256=(Get-FileHash $wheel).Hash;proxy_helper_sha256=(Get-FileHash $proxyHost).Hash;proxy_license='MIT';proxy_max_duration_seconds=$(if ($Protocol -eq 'UDP') { $udpProxyBudgetSeconds } else { 60 });local_receiver='src/pb_net_endpoint.py';explicit_client_proxy=$false;source_event_stream_complete=$false}) 'dependencies.json'
    Start-ProbeWorker 'receiver' @('-u',(Join-Path $root 'src/pb_net_endpoint.py'),'--jsonl-log',$receiverLog,'--endpoint-a-port',"$BasePort",'--endpoint-b-port',"$($BasePort+1)",'--control-stdin','--log-flush-mode',$EvidenceLogMode) $receiverLog 8 $receiverPython
    Save-ProbeJson ([ordered]@{pid=$workers[0].process.Id;path=$receiverPython;python_version=(& $receiverPython --version);python_sha256=(Get-FileHash $receiverPython).Hash;helper_sha256=(Get-FileHash (Join-Path $root 'src/pb_net_endpoint.py')).Hash;listener_pid_verified=$receipt.receiver_process_identity_verified}) 'receiver-identity.json'
    $proxyArguments = @('-u',$proxyHost,'--wheel',$wheel,'--jsonl-log',$proxyLog,'--port',"$($BasePort+2)",'--receiver-port',"$BasePort",'--receiver-port',"$($BasePort+1)")
    if ($Protocol -eq 'TCP') { $proxyArguments += @('--proxy-type',$ProxyType.ToLowerInvariant()) }
    if ($Protocol -eq 'UDP') { $proxyArguments += @('--max-duration-seconds',"$udpProxyBudgetSeconds",'--log-flush-mode',$EvidenceLogMode) }
    Start-ProbeWorker 'proxy' $proxyArguments $proxyLog 1 $proxyPython
    $samplerWorker = $null
    if ($UdpBenchmark) {
        $samplerDirectory = Join-Path $root 'bin/tools/psutil-7.2.2'
        $samplerWheel = Join-Path $samplerDirectory 'psutil-7.2.2-cp37-abi3-win_amd64.whl'
        if ((Get-FileHash $samplerWheel).Hash.ToLowerInvariant() -ne 'eb7e81434c8d223ec4a219b5fc1c47d0417b12be7ea866e24fb5ad6e84b3d988') { throw 'PSUTIL_DIGEST_MISMATCH' }
        Save-ProbeJson @([ordered]@{role='receiver';pid=$workers[0].process.Id;path=$receiverPython},[ordered]@{role='proxy';pid=$workers[1].process.Id;path=$proxyPython}) 'sampler-config.json'
        Save-ProbeJson ([ordered]@{test_id=$benchmarkTestId;traffic_mode=$receipt.traffic_mode;packet_count=$BenchmarkPacketCount;packets_per_stream=$packetsPerStream;interval_ms=$BenchmarkIntervalMs;warmup_packets=($BenchmarkWarmupPackets*$BenchmarkStreams);warmup_packets_per_stream=$BenchmarkWarmupPackets;message_size_bytes=$BenchmarkMessageSize;workload_timeout_ms=$benchmarkTimeoutMs;payload='run/sequence/phase identified echo';parallelism=$BenchmarkStreams;helper_log_flush_mode=$EvidenceLogMode;helper_log_buffer_bytes=262144;native_log_flush_mode='FLUSH_EACH';destination_mode=$BenchmarkDestinationMode;destination_ports=$benchmarkDestinationPorts;capacity_benchmark=$false;sampler='psutil 7.2.2';sampler_license='BSD-3-Clause';sampler_wheel_sha256=(Get-FileHash $samplerWheel).Hash}) 'benchmark-config.json'
        Start-ProbeWorker 'sampler' @('-u',(Join-Path $root 'src/pb_pc_sampler.py'),'--packages',(Join-Path $samplerDirectory 'packages'),'--config',(Join-Path $EvidenceDirectory 'sampler-config.json'),'--jsonl-log',(Join-Path $EvidenceDirectory 'pc-samples.jsonl'),'--max-duration-seconds',"$workerBudgetSeconds") (Join-Path $EvidenceDirectory 'pc-samples.jsonl') 1 $proxyPython
        $samplerWorker = $workers[2]
    }
    $runtimeConfig = Get-Content (Join-Path $root 'config/runtime.json') -Raw | ConvertFrom-Json
    $plan = New-RuntimeEnvironmentPlan -Environment $environment -RuntimeConfig $runtimeConfig -ProductOnly
    if ($plan.service_bootstrap -ne 'driver-service') { throw 'PROBE_REQUIRES_HEADLESS_KIT' }
    if ($TrafficMode -ne 'OFF') {
        $serviceStartAttempted = $true
        $preparation = Invoke-RuntimeEnvironmentPreparation -Plan $plan -Adapter (New-SystemRuntimeEnvironmentAdapter) -AllowProductRuntime
        Save-ProbeJson $preparation 'preparation-result.json'
        if (-not $preparation.prepared) { throw 'PROBE_PREPARATION_FAILED' }
    }
    $profile = [ordered]@{Version='1.0';LocalhostViaProxy=$true;IsTrafficLoggingEnabled=$true;ProxyConfigs=@([ordered]@{Id=1;Name="Controlled local $ProxyType";Type=$ProxyType;Host='127.0.0.1';Port="$($BasePort+2)";Username='';Password='';SendDomainToProxy=$false});ProxyRules=@()}
    if ($TrafficMode -in @('UNRULED','OFF')) {
        # A nonmatching enabled rule keeps the product active without ruling the generator.
        $profile.ProxyRules += [ordered]@{Name='Other application only';ProcessName='pb_testlab_other_app.exe';TargetHosts='127.0.0.1';TargetPorts="$($BasePort+1)";TargetDomains='';Protocol=$Protocol;Action='PROXY';ProxyConfigId=1;IsEnabled=$true}
    } else { foreach ($action in $Actions) {
        $rulePorts = @($(if ($action -eq 'DIRECT') { $BasePort } else { $BasePort+1 }))
        if ($BenchmarkDestinationMode -eq 'DISTINCT') { $rulePorts = $benchmarkDestinationPorts }
        foreach ($port in $rulePorts) {
            $ruleName = $(if ($BenchmarkDestinationMode -eq 'DISTINCT') { "Local $Protocol $action to $port" } else { "Local $Protocol $action" })
            $profile.ProxyRules += [ordered]@{Name=$ruleName;ProcessName='pb_net_client.exe';TargetHosts='127.0.0.1';TargetPorts="$port";TargetDomains='';Protocol=$Protocol;Action=$action;ProxyConfigId=1;IsEnabled=$true}
        }
    } }
    $profilePath = Join-Path $EvidenceDirectory 'route.pbprofile'
    Save-ProbeJson $profile 'route.pbprofile'
    $cliPlan = New-ProxyBridgeCliPlan -ExecutablePath $environment['PB_PROXYBRIDGE_CLI_EXE'] -ProfilePath $profilePath -ProductProfileContract driver -CliVariant $environment['PB_PROXYBRIDGE_CLI_VARIANT'] -ReadyStableMs 1000 -ReadinessTimeoutMs 10000 -StopTimeoutMs 5000
    $processAdapter = New-SystemProcessAdapter
    $workload = {
        param($ownedCli)
        $results = @()
        $relayPort = 0
        if ($TrafficMode -eq 'UNRULED' -or ($UdpBenchmark -and $TrafficMode -ne 'OFF')) {
            $loadedActive = Get-LoadedInterceptionDriverObservation -AllowProductRuntime
            $loadedActive | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'loaded-drivers-active.json') -Encoding UTF8
            if (-not $loadedActive.selected_driver_loaded -or $loadedActive.known_interception_drivers.Count -ne 1) { throw 'ACTIVE_SELECTED_DRIVER_NOT_CONFIRMED' }
        }
        if ($TrafficMode -eq 'UNRULED') {
            $live = $ownedCli.session.Stdout
            $watchMatch = [regex]::Match($live, 'driver: pushed (\d+) watched image\(s\)')
            $receipt.unruled_profile_verified = $profile.ProxyRules.Count -eq 1 -and $profile.ProxyRules[0].ProcessName -eq 'pb_testlab_other_app.exe' -and $live -match "Added rule ID: \d+ for process 'pb_testlab_other_app\.exe'" -and $live -match '1 added, 0 failed' -and $live -match 'driver: ProxyBridgeDrv active -' -and $watchMatch.Success -and [int]$watchMatch.Groups[1].Value -eq 1
            if (-not $receipt.unruled_profile_verified) { throw 'UNRULED_PROFILE_NOT_CONFIRMED' }
            [ordered]@{mode='product-running-unruled';client_process='pb_net_client.exe';configured_process='pb_testlab_other_app.exe';client_absent_from_rules=$true;watched_images=[int]$watchMatch.Groups[1].Value;cli_pid=$ownedCli.pid;cli_path=$ownedCli.actual_path;verified_at_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'unruled-profile-evidence.json') -Encoding UTF8
        }
        if ($UdpBenchmark) {
            if ($TrafficMode -eq 'RULES') {
            $relayMatch = [regex]::Match($ownedCli.session.Stdout, 'UDP relay listening on port (\d+)')
            if (-not $relayMatch.Success) { throw 'OWNED_UDP_RELAY_NOT_REPORTED' }
            $relayPort = [int]$relayMatch.Groups[1].Value
            $relaySockets = @(Get-NetUDPEndpoint -OwningProcess $ownedCli.pid -ErrorAction Stop | Where-Object { $_.LocalPort -eq $relayPort -and $_.LocalAddress -in @('0.0.0.0','127.0.0.1') })
            if ($relaySockets.Count -ne 1) { throw 'OWNED_UDP_RELAY_NOT_VERIFIED' }
            [ordered]@{pid=$ownedCli.pid;path=$ownedCli.actual_path;relay_ip='127.0.0.1';relay_port=$relayPort;socket_bind=$relaySockets[0].LocalAddress;verified_at_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'relay-ownership.json') -Encoding UTF8
            }
            if ($TrafficMode -ne 'OFF') {
                $samplerWorker.process.StandardInput.WriteLine(([ordered]@{role='proxybridge_cli';pid=$ownedCli.pid;path=$ownedCli.actual_path} | ConvertTo-Json -Compress))
                $samplerWorker.process.StandardInput.Flush()
            }
            Start-Sleep -Milliseconds 1000
        }
        foreach ($action in $Actions) {
            $port = $(if ($action -eq 'DIRECT' -and $TrafficMode -eq 'RULES') { $BasePort } else { $BasePort+1 })
            $testId = $(if ($TrafficMode -in @('UNRULED','OFF')) { 'local-' + $Protocol.ToLowerInvariant() + '-unruled' } else { 'local-' + $Protocol.ToLowerInvariant() + '-' + $action.ToLowerInvariant() })
            if ($UdpBenchmark) { $testId = $benchmarkTestId }
            $clientLog = Join-Path $EvidenceDirectory ($testId + '.jsonl')
            $clientPlan = [pscustomobject]@{executable=$client;arguments=@('--mode','single','--family','4','--protocol',$Protocol.ToLowerInvariant(),'--local-ip','127.0.0.1','--local-port','0','--remote-ip','127.0.0.1','--tcp-remote-port',"$port",'--udp-remote-port',"$port",'--test-id',$testId,'--run-id',$runId,'--jsonl-log',$clientLog,'--expected-action',$action,'--tcp-peer-policy','record-only','--expect','echo','--timeout-ms','3000');timeout_ms=5000}
            $receipt.traffic_generated = $true
            if ($UdpBenchmark) {
                $clientPlan.arguments += @('--stream-count',"$packetsPerStream",'--benchmark-streams',"$BenchmarkStreams",'--benchmark-warmup-count',"$BenchmarkWarmupPackets",'--stream-interval-ms',"$BenchmarkIntervalMs",'--second-remote-port',"$port")
                if ($BenchmarkDestinationMode -eq 'DISTINCT') { $clientPlan.arguments += @('--benchmark-alternate-port',"$BasePort") }
                if ($BenchmarkMessageSize -gt 0) { $clientPlan.arguments += @('--benchmark-message-size',"$BenchmarkMessageSize") }
                if ($TrafficMode -in @('UNRULED','OFF')) { $clientPlan.arguments += @('--benchmark-source-policy','exact') }
                else { $clientPlan.arguments += @('--benchmark-relay-ip','127.0.0.1','--benchmark-relay-port',"$relayPort") }
                $clientPlan.timeout_ms = $benchmarkTimeoutMs
                $native = $null
                try {
                    $native = & $processAdapter.StartProcess $clientPlan
                    $probe = & $processAdapter.ProbeActualPath $native 2000 25
                    if ($probe.status -ne 'PATH_OBTAINED' -or $native.actual_path -ine $client) { throw 'BENCHMARK_CLIENT_PATH_NOT_VERIFIED' }
                    $native.actual_path_probe_status = $probe.status
                    $native.actual_path_probe_attempts = $probe.attempts
                    $native.actual_path_probe_elapsed_ms = $probe.elapsed_ms
                    $samplerWorker.process.StandardInput.WriteLine(([ordered]@{role='generator';pid=$native.pid;path=$native.actual_path} | ConvertTo-Json -Compress))
                    $samplerWorker.process.StandardInput.Flush()
                    if (-not $native.session.WaitForExit($clientPlan.timeout_ms)) { $native.timed_out=$true; & $processAdapter.KillProcess $native }
                    $result = & $processAdapter.GetProcessResult $native
                } finally {
                    if ($null -ne $native) {
                        try { if (& $processAdapter.IsRunning $native) { & $processAdapter.KillProcess $native } }
                        finally { & $processAdapter.DisposeProcess $native }
                    }
                }
                Start-Sleep -Milliseconds 1000
            } else { $result = Invoke-ProcessPlan -Plan $clientPlan -ProcessAdapter $processAdapter -AllowProductRuntime }
            $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory ($testId + '-process.json')) -Encoding UTF8
            $results += [pscustomobject]@{action=$action;test_id=$testId;destination_port=$port;pid=$result.pid;exit_code=$result.exit_code;timed_out=$result.timed_out}
        }
        # Allow the existing product callback/receiver writer to deliver their final observations.
        Start-Sleep -Milliseconds 500
        return $results
    }.GetNewClosure()
    $sink = {param($value) $value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'cli-lifecycle.json') -Encoding UTF8}.GetNewClosure()
    if ($TrafficMode -eq 'OFF') {
        # No CLI lifecycle is fabricated or saved for a product-off run.
        $lifecycle = [pscustomobject]@{workload_result=(& $workload $null);process_result=[pscustomobject]@{stdout='';output_capture_complete=$false};started_at_utc=$receipt.started_at_utc}
    } else { $lifecycle = Invoke-ProxyBridgeCliLifecycle -Plan $cliPlan -ProcessAdapter $processAdapter -AllowProductRuntime -Workload $workload -EvidenceSink $sink }
    if ($UdpBenchmark) {
        # Close both helper logs before reading packet evidence, including buffered tails.
        $trafficWorkers = @($workers | Where-Object { $_.name -in @('receiver','proxy') })
        foreach ($worker in $trafficWorkers) {
            if ($worker.process.HasExited) { throw "TRAFFIC_HELPER_EARLY_EXIT_$($worker.name)" }
            $worker.process.StandardInput.WriteLine('STOP')
            $worker.process.StandardInput.Flush()
        }
        foreach ($worker in $trafficWorkers) {
            if (-not $worker.process.WaitForExit(5000) -or $worker.process.ExitCode -ne 0) { throw "TRAFFIC_HELPER_STOP_FAILED_$($worker.name)" }
        }
    }
    $stdout = $lifecycle.process_result.stdout
    $records = @(ConvertFrom-ProxyBridgeTextLines -Lines @($stdout -split '\r?\n') -DefaultTimestampUtc ([DateTime]::Parse($lifecycle.started_at_utc)))
    Save-ProbeJson $records 'route-observations.json'
    $receiver = @(Get-Content $receiverLog | ConvertFrom-Json)
    $proxy = @(Get-Content $proxyLog | ConvertFrom-Json)
    $receiverIndex = New-ProbeIndex $receiver 'sequence'
    $proxyHashIndex = New-ProbeIndex $proxy 'payload_sha256'
    $associateIndex = New-ProbeIndex @($proxy | Where-Object event -eq 'UDP_ASSOCIATE_READY') 'connection_id'
    $configMatch = [regex]::Match($stdout, ('\[1\]\s+' + $ProxyType + '\s+127\.0\.0\.1:' + ($BasePort+2) + '\s+\(id=(\d+)\)'))
    foreach ($case in @($lifecycle.workload_result)) {
        $clientRows = @(Get-Content (Join-Path $EvidenceDirectory ($case.test_id + '.jsonl')) | ConvertFrom-Json)
        if (-not $UdpBenchmark -and $clientRows.Count -ne 1) { $clientRows = @($null) }
        foreach ($row in $clientRows) {
            $destinationPort = $case.destination_port
            $destinationDeclared = $true
            if ($UdpBenchmark -and $null -ne $row) {
                $streamIndex = [int]$row.benchmark_stream_index
                $destinationDeclared = $streamIndex -ge 1 -and $streamIndex -le $BenchmarkStreams
                if ($destinationDeclared) {
                    $destinationPort = [int]$benchmarkDestinationPorts[$(if ($BenchmarkDestinationMode -eq 'DISTINCT') { $streamIndex-1 } else { 0 })]
                    $destinationDeclared = $row.requested_remote_ip -eq '127.0.0.1' -and $row.requested_remote_port -eq $destinationPort
                }
            }
            $payloadVerified = $false
            $socketVerified = $false
            $routeVerified = $false
            $unexpectedProxyPath = $false
            $clientCheckPassed = $false
            $responseSourceMismatch = $false
            $clientResult = $(if ($null -ne $row) { $row.actual_result } else { 'NO_RECORD' })
            if ($null -ne $row -and $row.run_id -eq $runId -and $row.process_id -eq $case.pid -and $row.protocol -eq $Protocol -and $row.requested_remote_ip -eq '127.0.0.1' -and $row.requested_remote_port -eq $destinationPort) {
                $sequenceRows = @()
                if ($receiverIndex.ContainsKey([string]$row.sequence)) { $sequenceRows = $receiverIndex[[string]$row.sequence].ToArray() }
                $proxyRows = @()
                if ($proxyHashIndex.ContainsKey($row.payload_sha256)) { $proxyRows = $proxyHashIndex[$row.payload_sha256].ToArray() }
                $received = @($sequenceRows | Where-Object { $_.event -eq $(if ($Protocol -eq 'TCP') {'MESSAGE_RECEIVED'} else {'RECEIVED'}) -and $_.protocol -eq $Protocol -and $_.test_id -eq $case.test_id -and $_.run_id -eq $runId -and $_.sequence -eq $row.sequence -and $_.local_port -eq $destinationPort -and $_.sha256 -eq $row.payload_sha256 -and $_.bytes -eq $row.bytes_sent })
                $echoed = @($sequenceRows | Where-Object { $_.event -eq 'ECHOED' -and $_.test_id -eq $case.test_id -and $_.run_id -eq $runId -and $_.sha256 -eq $row.response_sha256 -and $_.bytes -eq $row.bytes_received })
                $payloadVerified = $destinationDeclared -and $row.bytes_sent -gt 0 -and $row.bytes_sent -eq $row.bytes_received -and $row.payload_sha256 -eq $row.response_sha256 -and $received.Count -eq 1 -and $echoed.Count -eq 1
                $clientCheckPassed = $case.exit_code -eq 0 -and -not $case.timed_out -and $row.actual_result -eq 'pass'
                $responseSourceMismatch = $Protocol -eq 'UDP' -and $row.actual_result -eq 'fail:udp_response_source' -and $row.bytes_received -gt 0 -and ($row.actual_remote_ip -ne $row.requested_remote_ip -or $row.actual_remote_port -ne $row.requested_remote_port)
                if ($received.Count -eq 1) {
                    if ($case.action -eq 'DIRECT') {
                        $socketVerified = $received[0].remote_ip -eq $row.actual_local_ip -and $received[0].remote_port -eq $row.actual_local_port -and $row.actual_remote_port -eq $destinationPort
                        $routeVerified = @($records | Where-Object { $_.event -eq 'ROUTE_DECISION' -and $_.pid -eq $case.pid -and $_.destination_ip -eq '127.0.0.1' -and $_.destination_port -eq $destinationPort -and $_.action -eq 'DIRECT' }).Count -gt 0
                        if ($TrafficMode -eq 'OFF') { $routeVerified = $receipt.product_off_verified }
                        if ($Protocol -eq 'TCP') {
                            $unexpectedProxyPath = @($proxy | Where-Object { $_.event -eq 'OUTBOUND_CONNECTED' -and $_.destination_port -eq $destinationPort -and $_.outbound_peer_ip -eq '127.0.0.1' -and $_.outbound_peer_port -eq $destinationPort -and $_.outbound_local_ip -eq $received[0].remote_ip -and $_.outbound_local_port -eq $received[0].remote_port }).Count -gt 0
                        } else {
                            $unexpectedProxyPath = @($proxyRows | Where-Object { $_.event -eq 'UDP_OUTBOUND_DATAGRAM' -and $_.destination_ip -eq '127.0.0.1' -and $_.destination_port -eq $destinationPort -and $_.payload_sha256 -eq $row.payload_sha256 -and $_.bytes -eq $row.bytes_sent }).Count -gt 0
                        }
                        if ($TrafficMode -eq 'UNRULED') {
                            $routeVerified = $routeVerified -and $receipt.unruled_profile_verified -and @($records | Where-Object { $_.event -eq 'RELAY_ACCEPTED_REDIRECT' -and $_.pid -eq $case.pid }).Count -eq 0
                        }
                    } elseif ($Protocol -eq 'TCP') {
                        $outbound = @($proxy | Where-Object { $_.event -eq 'OUTBOUND_CONNECTED' -and $_.destination_port -eq $destinationPort -and $_.outbound_peer_ip -eq '127.0.0.1' -and $_.outbound_peer_port -eq $destinationPort -and $_.outbound_local_ip -eq $received[0].remote_ip -and $_.outbound_local_port -eq $received[0].remote_port })
                        $socketVerified = $outbound.Count -eq 1
                        if ($socketVerified) { $socketVerified = @($proxy | Where-Object { $_.event -eq 'INBOUND_ACCEPTED' -and $_.connection_id -eq $outbound[0].connection_id }).Count -eq 1 }
                        if ($configMatch.Success) {
                            $routeVerified = @($records | Where-Object { $_.event -eq 'RELAY_ACCEPTED_REDIRECT' -and $_.pid -eq $case.pid -and $_.destination_ip -eq '127.0.0.1' -and $_.destination_port -eq $destinationPort -and $_.action -eq 'PROXY' -and $_.proxy_config_id -eq [int]$configMatch.Groups[1].Value }).Count -eq 1
                        }
                    } else {
                        $outbound = @($proxyRows | Where-Object { $_.event -eq 'UDP_OUTBOUND_DATAGRAM' -and $_.destination_ip -eq '127.0.0.1' -and $_.destination_port -eq $destinationPort -and $_.outbound_local_port -eq $received[0].remote_port -and $_.payload_sha256 -eq $row.payload_sha256 -and $_.bytes -eq $row.bytes_sent -and $received[0].remote_ip -eq '127.0.0.1' })
                        if ($outbound.Count -eq 1) {
                            $associate = @()
                            if ($associateIndex.ContainsKey([string]$outbound[0].connection_id)) { $associate = $associateIndex[[string]$outbound[0].connection_id].ToArray() }
                            $returned = @($proxyRows | Where-Object { $_.event -eq 'UDP_RETURN_DATAGRAM' -and $_.connection_id -eq $outbound[0].connection_id -and $_.remote_ip -eq '127.0.0.1' -and $_.remote_port -eq $destinationPort -and $_.payload_sha256 -eq $row.response_sha256 -and $_.bytes -eq $row.bytes_received })
                            $socketVerified = $associate.Count -eq 1 -and $returned.Count -eq 1
                        }
                        $routeVerified = @($records | Where-Object { $_.event -eq 'ROUTE_DECISION' -and $_.pid -eq $case.pid -and $_.destination_ip -eq '127.0.0.1' -and $_.destination_port -eq $destinationPort -and $_.action -eq 'PROXY' -and $_.route_detail -match 'socks5://' }).Count -gt 0 -and $stdout -match ('UDP ASSOCIATE established with SOCKS5 proxy 127\.0\.0\.1:' + ($BasePort+2) + '\s')
                    }
                }
            }
            $passed = $payloadVerified -and $clientCheckPassed -and $socketVerified -and $routeVerified -and -not $unexpectedProxyPath -and ($TrafficMode -eq 'OFF' -or $lifecycle.process_result.output_capture_complete)
            $receipt.cases.Add([ordered]@{sequence=$(if ($null -ne $row) {$row.sequence} else {0});name_ru=$(if ($TrafficMode -eq 'OFF') {'Напрямую, ProxyBridge выключен'} elseif ($TrafficMode -eq 'UNRULED') {'ProxyBridge включён, приложение вне правил'} elseif ($case.action -eq 'DIRECT') {"Прямое $Protocol-соединение"} else {"$Protocol через локальный $ProxyType"});name_en=$(if ($TrafficMode -eq 'OFF') {'Direct, ProxyBridge stopped'} elseif ($TrafficMode -eq 'UNRULED') {'ProxyBridge running, application outside rules'} elseif ($case.action -eq 'DIRECT') {"Direct $Protocol connection"} else {"$Protocol through local $ProxyType"});action=$case.action;client_pid=$case.pid;payload_verified=$payloadVerified;client_check_passed=$clientCheckPassed;client_result=$clientResult;socket_path_verified=$socketVerified;product_route_observed=($TrafficMode -ne 'OFF' -and $routeVerified);mode_state_verified=$routeVerified;unexpected_proxy_path=$unexpectedProxyPath;response_source_mismatch=$responseSourceMismatch;status=$(if ($passed) {'ROUTE_OBSERVED'} elseif ($payloadVerified -and $socketVerified -and $routeVerified -and $responseSourceMismatch -and $lifecycle.process_result.output_capture_complete) {'SOURCE_ENDPOINT_MISMATCH'} elseif ($payloadVerified -and $routeVerified -and $unexpectedProxyPath) {'ROUTE_MISMATCH'} else {'INCONCLUSIVE'})})
        }
    }
    $expectedCases = $(if ($UdpBenchmark) { $BenchmarkPacketCount } else { $Actions.Count })
    $receipt.route_verified = $receipt.cases.Count -eq $expectedCases -and @($receipt.cases | Where-Object status -ne 'ROUTE_OBSERVED').Count -eq 0
    $receipt.status = $(if ($receipt.route_verified) {'ROUTES_OBSERVED'} elseif (@($receipt.cases | Where-Object status -eq 'SOURCE_ENDPOINT_MISMATCH').Count) {'SOURCE_ENDPOINT_MISMATCH'} elseif (@($receipt.cases | Where-Object status -eq 'ROUTE_MISMATCH').Count) {'ROUTE_MISMATCH'} else {'INCONCLUSIVE'})
    if ($receipt.status -eq 'SOURCE_ENDPOINT_MISMATCH') { $receipt.reason='UDP payload integrity and traversal through the controlled proxy were observed, but the client received a response from a different endpoint than requested.' }
    if ($receipt.status -eq 'ROUTE_MISMATCH') { $receipt.reason='DIRECT was reported by the product, but the receiver socket and payload matched an outbound connection of the controlled SOCKS5 proxy.' }
} catch {
    $receipt.status='FAILED'
    $receipt.reason=$_.Exception.Message
} finally {
    $workersClean = $true
    foreach ($worker in $workers) {
        try {
            $forced = $false
            if (-not $worker.process.HasExited) { $worker.process.StandardInput.WriteLine('STOP'); $worker.process.StandardInput.Flush() }
            if (-not $worker.process.WaitForExit(5000)) { $forced=$true; $worker.process.Kill(); $null=$worker.process.WaitForExit(5000) }
            $captureComplete = $worker.stdout_task.Wait(5000) -and $worker.stderr_task.Wait(5000)
            if (-not $captureComplete) { throw 'PROBE_WORKER_CAPTURE_INCOMPLETE' }
            $workerResult = [ordered]@{pid=$worker.process.Id;exit_code=$worker.process.ExitCode;forced_stop=$forced;output_capture_complete=$captureComplete;stdout=$worker.stdout_task.GetAwaiter().GetResult();stderr=$worker.stderr_task.GetAwaiter().GetResult()}
            if ($worker.name -eq 'proxy' -and $Protocol -eq 'UDP') {
                $stops = @(Get-Content -LiteralPath $proxyLog | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.event -eq 'STOPPED' })
                $workerResult['shutdown_reason'] = $(if ($stops.Count -eq 1) { $stops[0].shutdown_reason } else { 'STOP_EVIDENCE_MISSING' })
                if ($workerResult.shutdown_reason -ne 'STDIN_STOP') {
                    $workersClean=$false
                    $receipt.reason += '; proxy shutdown: ' + $workerResult.shutdown_reason
                }
            }
            Save-ProbeJson $workerResult ($worker.name + '-process.json')
            if ($forced -or $workerResult.exit_code -ne 0 -or -not $captureComplete) { $workersClean=$false }
        } catch { $workersClean=$false; $receipt.reason += '; worker cleanup: ' + $_.Exception.Message }
        finally {
            try {
                if (-not $worker.process.HasExited) { $worker.process.Kill(); $null=$worker.process.WaitForExit(5000) }
            } catch { $workersClean=$false; $receipt.reason += '; final worker stop: ' + $_.Exception.Message }
            $worker.process.Dispose()
        }
    }
    $receipt.workers_stopped = $workersClean
    if ($serviceStartAttempted) {
        try {
            $remaining = @(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object { $_.Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe') })
            if ($remaining.Count) { throw 'PROBE_PRODUCT_PROCESS_REMAINS' }
            $afterCli = Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
            if ($afterCli.wfp.status -ne 'SERVICE_FILE_VERIFIED') { throw 'PROBE_DRIVER_IDENTITY_CHANGED' }
            $controller = [ServiceProcess.ServiceController]::new('ProxyBridgeDrv')
            try {
                if ($controller.Status -eq [ServiceProcess.ServiceControllerStatus]::Running) { $controller.Stop() }
                $controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(10))
            } finally { $controller.Dispose() }
            $after = Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
            Save-ProbeJson $after 'interception-after.json'
            $receipt.driver_stop_observed = $after.wfp.service_state -eq 'Stopped' -and $after.wfp_objects.query_complete -and $after.wfp_objects.no_known_objects_observed
            if (-not $receipt.driver_stop_observed) { throw 'PROBE_DRIVER_STOP_NOT_OBSERVED' }
        } catch { $receipt.status='FAILED'; $receipt.reason += '; driver cleanup: ' + $_.Exception.Message }
    }
    if ($TrafficMode -in @('OFF','UNRULED') -or $UdpBenchmark) {
        try {
            $loadedAfter = Get-LoadedInterceptionDriverObservation -AllowProductRuntime
            Save-ProbeJson $loadedAfter 'loaded-drivers-after.json'
            if (-not $loadedAfter.known_interception_driver_names_absent) { throw 'SELECTED_PRODUCT_DRIVER_REMAINS_LOADED' }
            if ($TrafficMode -eq 'OFF') {
                $after = Get-InterceptionStateSnapshot -Environment $environment -AllowProductRuntime
                Save-ProbeJson $after 'interception-after.json'
                $remaining = @(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Where-Object { $_.Name -in @('ProxyBridge.exe','ProxyBridge_CLI.exe') })
                $receipt.product_off_verified = $receipt.product_off_verified -and $after.current_driver_preparation_allowed -and $after.wfp_detachment_observed -and $remaining.Count -eq 0
                $receipt.driver_stop_observed = $receipt.product_off_verified
                if (-not $receipt.product_off_verified) { throw 'SELECTED_PRODUCT_OFF_STATE_CHANGED' }
            }
        } catch { $receipt.status='FAILED'; $receipt.reason += '; product-state verification: ' + $_.Exception.Message }
    }
    if (-not $workersClean) { $receipt.status='FAILED'; $receipt.reason += '; workers did not stop cleanly' }
    $receipt.completed_at_utc=[DateTime]::UtcNow.ToString('o')
    Save-ProbeJson $receipt 'route-probe-receipt.json'
}
if ($receipt.status -eq 'FAILED') { throw $receipt.reason }
if ($UdpBenchmark) {
    & $proxyPython (Join-Path $root 'src/pb_udp_benchmark_report.py') --evidence-directory $EvidenceDirectory
    if ($LASTEXITCODE -ne 0) { throw 'BENCHMARK_REPORT_FAILED' }
    $benchmarkReport = Get-Content (Join-Path $EvidenceDirectory 'udp-benchmark-report.json') -Raw | ConvertFrom-Json
    $receipt.benchmark_performed = $benchmarkReport.performance_status -in @('MEASURED','MEASURED_WITH_SOURCE_DEFECT')
    Save-ProbeJson $receipt 'route-probe-receipt.json'
}
Write-Output $receipt.status
