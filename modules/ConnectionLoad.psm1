Set-StrictMode -Version Latest

function Get-ConnectionLoadPreset {
    param([ValidateSet('SHORT','NORMAL','LONG')][string]$Duration='SHORT',[ValidateSet('LOW','HIGH')][string]$Load='LOW')
    $seconds=@{SHORT=8;NORMAL=32;LONG=120}[$Duration]
    return [ordered]@{method='tcp-connection-load-v1';duration=$Duration;load=$Load;levels=$(if ($Load -eq 'HIGH') {@(64,256,640)} else {@(8,32,64)});hold_seconds=$seconds;reference_connections=4;reference_seconds=8;rate_per_connection_bytes_per_s=65536;native_timeout_ms=600000;proxy_event_loop='ProactorEventLoop';minimum_available_bytes=$(if ($Load -eq 'HIGH') {2147483648L} else {536870912L})}
}

function Write-ConnectionJson($Value,[string]$Path) { ConvertTo-Json -InputObject $Value -Depth 15 | Set-Content -LiteralPath $Path -Encoding UTF8 }
function Get-ConnectionQpc { return [Diagnostics.Stopwatch]::GetTimestamp()*1000.0/[Diagnostics.Stopwatch]::Frequency }

function Read-ConnectionReceiverJson([string[]]$Lines) {
    $text=$Lines -join "`n"
    # Preserve Linux ISO timestamp spelling too: PS7 DateTime coercion would change +00:00 to Z.
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {return ConvertFrom-Json -InputObject $text -DateKind String}
    return ConvertFrom-Json -InputObject $text
}

function Get-ConnectionResourceObservation {
    param([string]$Directory,[long]$MinimumAvailableBytes)
    $observation=[ordered]@{schema_version=1;scope='connection-load-resource-gate';status='QUERY_FAILED';started_at_utc=[DateTime]::UtcNow.ToString('o');completed_at_utc='';free_physical_bytes=$null;disk_free_bytes=$null;minimum_available_bytes=$MinimumAvailableBytes;minimum_disk_free_bytes=268435456L;memory_bound_met=$false;disk_bound_met=$false;error=''}
    try {
        if ($MinimumAvailableBytes -notin @(536870912L,2147483648L)) {throw 'CONNECTION_RESOURCE_THRESHOLD_INVALID'}
        $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5
        $drive=Get-PSDrive -Name ([IO.Path]::GetPathRoot($Directory).Substring(0,1))
        if ($null -eq $os.FreePhysicalMemory -or $null -eq $drive.Free) {throw 'CONNECTION_RESOURCE_VALUES_MISSING'}
        $observation.free_physical_bytes=[long]$os.FreePhysicalMemory*1024
        $observation.disk_free_bytes=[long]$drive.Free
        $observation.memory_bound_met=$observation.free_physical_bytes -ge $MinimumAvailableBytes
        $observation.disk_bound_met=$observation.disk_free_bytes -ge $observation.minimum_disk_free_bytes
        $observation.status=$(if ($observation.memory_bound_met -and $observation.disk_bound_met) {'AVAILABLE'} else {'RESOURCE_BOUND'})
    } catch {$observation.error=$_.Exception.Message}
    $observation.completed_at_utc=[DateTime]::UtcNow.ToString('o')
    return $observation
}

function Invoke-ConnectionCohort {
    param($Context,$Phase,$Cli)
    $directory=Join-Path $Context.directory $Phase.id
    $null=New-Item -ItemType Directory -Path $directory
    $adapter=$Context.adapter;$server=$null;$client=$null
    $record=[ordered]@{id=$Phase.id;phase=$Phase.phase;requested_connections=$Phase.connections;hold_seconds=$Phase.seconds;status='RUNNING';error='';server_controlled_stop=$false;server_forced_stop=$false;client_forced_stop=$false;snapshot_complete=$false}
    $volume=[long]$Phase.seconds*65536
    $common=@('-protocol:tcp','-pattern:push',('-transfer:'+$volume),'-ratelimit:65536','-verify:data','-port:54122','-buffer:65536','-consoleverbosity:1','-statusupdate:250')
    $startingWorker='';$startingPlan=$null
    $external=$Context.PSObject.Properties['external_receiver'] -and $Context.external_receiver
    $target=$(if ($external) {[string]$Context.external_receiver.host} else {'127.0.0.1'})
    $remoteRun='';$remoteAttempted=$false
    try {
        $resources=Get-ConnectionResourceObservation -Directory $directory -MinimumAvailableBytes $Context.preset.minimum_available_bytes
        Write-ConnectionJson $resources (Join-Path $directory 'resource-observation.json')
        if ($resources.status -eq 'QUERY_FAILED') {throw 'CONNECTION_RESOURCE_OBSERVATION_FAILED'}
        if ($resources.status -ne 'AVAILABLE') {throw 'CONNECTION_LOAD_RESOURCE_BOUND'}
        if ($external) {
            $remoteRun='pair-'+[guid]::NewGuid().ToString('N')
            $record['receiver_run_id']=$remoteRun;$remoteAttempted=$true
            $remoteStart=Read-ConnectionReceiverJson (& (Join-Path $Context.root 'scripts/Invoke-LinuxCtsReceiver.ps1') -Phase Start -ConnectionFile $Context.external_receiver.connection_file -RunId $remoteRun -TransferBytes $volume -MaxConnections $Phase.connections -MaxTotalConnections $Phase.connections -MaxDurationSeconds 720)
            Write-ConnectionJson $remoteStart (Join-Path $directory 'linux-start.json')
            if ($remoteStart.result.status -ne 'RECEIVER_LISTENING') {throw 'CONNECTION_LINUX_RECEIVER_NOT_READY'}
        } else {
        $serverPlan=[pscustomobject]@{executable=$Context.receiver;arguments=(@('-listen:127.0.0.1',('-serverexitlimit:'+$Phase.connections),('-connectionfilename:'+(Join-Path $directory 'receiver.csv')))+$common);console_host_path=(Join-Path $Context.root 'bin/pb_console_host.exe');stop_timeout_ms=5000}
        $startingWorker='receiver';$startingPlan=$serverPlan
        $server=& $adapter.StartProcess $serverPlan
        $startingWorker='';$startingPlan=$null
        $probe=& $adapter.ProbeActualPath $server 2000 25
        if ($probe.status -ne 'PATH_OBTAINED' -or $server.actual_path -ine $Context.receiver) { throw 'CONNECTION_RECEIVER_PATH_NOT_CONFIRMED' }
        $ready=[Diagnostics.Stopwatch]::StartNew()
        do {
            $listeners=@(Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' -LocalPort 54122 -OwningProcess $server.pid -ErrorAction SilentlyContinue)
            if ($listeners.Count -eq 1) { break }
            if (-not $server.session.IsRunning) { throw 'CONNECTION_RECEIVER_EARLY_EXIT' }
            Start-Sleep -Milliseconds 50
        } while ($ready.ElapsedMilliseconds -lt 5000)
        if ($listeners.Count -ne 1) { throw 'CONNECTION_RECEIVER_NOT_READY' }
        $Context.sampler.process.StandardInput.WriteLine(([ordered]@{role='receiver';pid=$server.pid;path=$server.actual_path} | ConvertTo-Json -Compress));$Context.sampler.process.StandardInput.Flush()
        $record.receiver_pid=$server.pid
        }
        $connectionOptions=@('-throttleconnections:32')
        if ($Context.PSObject.Properties['diagnostic_case'] -and $Context.diagnostic_case) {
            if (-not $Context.diagnostic_only -or $Context.mode -ne 'PROXY' -or $Context.diagnostic_case.pending_limit -notin @(1,32) -or $Context.diagnostic_case.connect_method -cnotin @('ConnectEx','connect')) {throw 'CONNECTION_MATRIX_CONTEXT_INVALID'}
            $connectionOptions=@(('-throttleconnections:'+$Context.diagnostic_case.pending_limit),('-conn:'+$Context.diagnostic_case.connect_method))
        }
        $clientPlan=[pscustomobject]@{executable=$Context.client;arguments=(@(('-target:'+$target),('-connections:'+$Phase.connections),'-iterations:1')+$connectionOptions+@('-shutdown:rude',('-connectionfilename:'+(Join-Path $directory 'client.csv')))+$common);timeout_ms=600000}
        $start=Get-ConnectionQpc
        $startingWorker='client';$startingPlan=$clientPlan
        $client=& $adapter.StartProcess $clientPlan
        $startingWorker='';$startingPlan=$null
        $probe=& $adapter.ProbeActualPath $client 2000 25
        if ($probe.status -ne 'PATH_OBTAINED' -or $client.actual_path -ine $Context.client) { throw 'CONNECTION_GENERATOR_PATH_NOT_CONFIRMED' }
        $record.client_pid=$client.pid
        $observed=Get-CimInstance Win32_Process -Filter ('ProcessId='+$client.pid) -OperationTimeoutSec 5
        Write-ConnectionJson ([ordered]@{pid=$client.pid;expected_executable=$Context.client;expected_arguments=@($clientPlan.arguments);observed_executable=$observed.ExecutablePath;observed_command_line=$observed.CommandLine;capture_qpc_ms=(Get-ConnectionQpc)}) (Join-Path $directory 'client-launch.json')
        $Context.sampler.process.StandardInput.WriteLine(([ordered]@{role='generator';pid=$client.pid;path=$client.actual_path} | ConvertTo-Json -Compress));$Context.sampler.process.StandardInput.Flush()
        $owner=$(if ($Cli) {$Cli.pid} else {$client.pid});$port=$(if ($Cli) {54123} else {54122})
        $snapshotStart=Get-ConnectionQpc
        $timer=[Diagnostics.Stopwatch]::StartNew();$sockets=@()
        do {
            $sockets=@(Get-NetTCPConnection -State Established -RemoteAddress '127.0.0.1' -RemotePort $port -OwningProcess $owner -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,OwningProcess)
            if ($sockets.Count -eq $Phase.connections -or -not $client.session.IsRunning) { break }
            Start-Sleep -Milliseconds 50
        } while ($timer.ElapsedMilliseconds -lt 15000)
        $snapshotEnd=Get-ConnectionQpc
        Write-ConnectionJson ([ordered]@{owner_pid=$owner;target_port=$port;start_qpc_ms=$snapshotStart;end_qpc_ms=$snapshotEnd;sockets=@($sockets);requested_connections=$Phase.connections}) (Join-Path $directory 'owned-socket-snapshot.json')
        $record.snapshot_complete=$sockets.Count -eq $Phase.connections
        if (-not $client.session.WaitForExit(600000)) { $client.timed_out=$true;throw 'CONNECTION_GENERATOR_TIMEOUT' }
        $record.end_qpc_ms=Get-ConnectionQpc;$record.start_qpc_ms=$start
        $record.status='OBSERVED'
    } catch {
        $record.status='INCONCLUSIVE';$record.error=$_.Exception.Message
        if ($startingWorker) {
            $failure=[ordered]@{status='PROCESS_START_FAILED';worker=$startingWorker;error=$record.error;executable=$startingPlan.executable;arguments=@($startingPlan.arguments);metadata=[ordered]@{}}
            $cause=$_.Exception
            while ($cause) {
                foreach ($key in $cause.Data.Keys) {if ([string]$key -like 'PB_START_*') {$failure.metadata[[string]$key]=$cause.Data[$key]}}
                $cause=$cause.InnerException
            }
            Write-ConnectionJson $failure (Join-Path $directory ($startingWorker+'-start-failure.json'))
            $record['process_start_failure']=$failure
        }
    }
    finally {
        if ($client) {
            if ($client.session.IsRunning) { & $adapter.KillProcess $client;$record.client_forced_stop=$true }
            Write-ConnectionJson (& $adapter.GetProcessResult $client) (Join-Path $directory 'client-process.json')
            & $adapter.DisposeProcess $client
        }
        if ($remoteAttempted) {
            try {
                $remoteStop=Read-ConnectionReceiverJson (& (Join-Path $Context.root 'scripts/Invoke-LinuxCtsReceiver.ps1') -Phase Stop -ConnectionFile $Context.external_receiver.connection_file -RunId $remoteRun)
                Write-ConnectionJson $remoteStop (Join-Path $directory 'linux-stop.json')
                if ($remoteStop.result.status -ne 'RECEIVER_SERVICE_STOPPED') {throw 'CONNECTION_LINUX_STOP_UNCONFIRMED'}
            } catch {$record.status='INCONCLUSIVE';$record.error+='; LINUX_STOP: '+$_.Exception.Message}
            try {$null=& (Join-Path $Context.root 'scripts/Invoke-LinuxCtsReceiver.ps1') -Phase Collect -ConnectionFile $Context.external_receiver.connection_file -RunId $remoteRun -EvidenceDirectory (Join-Path $directory 'linux-receiver')}
            catch {$record.status='INCONCLUSIVE';$record.error+='; LINUX_COLLECT: '+$_.Exception.Message}
        }
        if ($server) {
            if (-not $server.session.WaitForExit(1000)) {
                $record.server_controlled_stop=& $adapter.StopProcess $server 5000
                if ($server.session.IsRunning) { & $adapter.KillProcess $server;$record.server_forced_stop=$true }
            }
            Write-ConnectionJson (& $adapter.GetProcessResult $server) (Join-Path $directory 'receiver-process.json')
            & $adapter.DisposeProcess $server
        }
        Write-ConnectionJson $record (Join-Path $directory 'phase-receipt.json')
    }
    return $record
}

function Invoke-ConnectionCohorts {
    param($Context,$Cli)
    if ($Cli) {
        $Context.sampler.process.StandardInput.WriteLine(([ordered]@{role='proxybridge_cli';pid=$Cli.pid;path=$Cli.actual_path} | ConvertTo-Json -Compress));$Context.sampler.process.StandardInput.Flush()
    }
    $phases=@([pscustomobject]@{id='baseline';phase='baseline';connections=4;seconds=8})
    foreach ($count in $Context.preset.levels) { $phases+=[pscustomobject]@{id=('load-'+$count);phase='load';connections=$count;seconds=$Context.preset.hold_seconds} }
    $phases+=[pscustomobject]@{id='recovery';phase='recovery';connections=4;seconds=8}
    foreach ($phase in $phases) {
        if ($Context.cancellation_path -and (Test-Path -LiteralPath $Context.cancellation_path)) { $Context.receipt.status='CANCELLED';break }
        Write-Host ($Context.mode+' / '+$phase.id+': '+$phase.connections+' connections / соединений')
        $record=Invoke-ConnectionCohort -Context $Context -Phase $phase -Cli $Cli
        $Context.receipt.phases+=@($record)
        Write-ConnectionJson $Context.receipt (Join-Path $Context.directory 'run-receipt.json')
        # Keep the same product and fixture for recovery after an observed native
        # failure. Resource bounds or forced cleanup abort further load safely.
        if ($record.error) {throw ('CONNECTION_COHORT_INCOMPLETE: '+$record.error)}
        if ($record.client_forced_stop -or $record.server_forced_stop) { throw 'CONNECTION_COHORT_COULD_NOT_COMPLETE_CLEANLY' }
    }
}

Export-ModuleMember -Function Get-ConnectionLoadPreset,Get-ConnectionResourceObservation,Invoke-ConnectionCohorts,Write-ConnectionJson
