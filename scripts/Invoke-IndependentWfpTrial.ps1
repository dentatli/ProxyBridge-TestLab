[CmdletBinding()]
param(
    [ValidateSet('Healthy','Target','Capacity','Drain','SilentRetry')][string]$Mode='Healthy',
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9-]+$')][string]$TrialId,
    [string]$KitDirectory='C:\PB-Independent-Wfp-20261021-r2',
    [ValidateRange(42201,65535)][int]$ControlPort=42201,
    [switch]$RecordsFirst,
    [ValidateRange(1024,65336)][int]$FillerBasePort=42001,
    [ValidateRange(200,65535)][int]$BacklogHint=512,
    [switch]$BlockDiscard,
    [ValidateRange(100,5000)][int]$DropHoldMilliseconds=100
)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'PB-SUT'){throw 'TARGET_IDENTITY_DIFFERS'}
$kit=$KitDirectory
$directory=Join-Path $kit $TrialId
if(Test-Path -LiteralPath $directory){throw 'TRIAL_ALREADY_EXISTS_NO_REPEAT'}
$null=New-Item -ItemType Directory $directory
$probe=Join-Path $kit 'WfpContextProbe.exe'
$cli=Join-Path $kit 'WFPSampler.exe'
$children=New-Object System.Collections.Generic.List[System.Diagnostics.Process]
$trace='PBWfp-'+$TrialId
$traceStarted=$false;$policyAdded=$false;$blockAdded=$false;$discardAdded=$false;$cleanupErrors=@()
$result=[ordered]@{status='INCOMPLETE';mode=$Mode;directory=$directory;control_port=$ControlPort;records_first=[bool]$RecordsFirst;filler_base_port=$FillerBasePort}
$bulk=$Mode -in @('Target','Capacity','Drain')
function Wait-File([string]$name,[int]$milliseconds=10000){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true){
        if(Test-Path -LiteralPath (Join-Path $directory $name)){
            try{
                $value=Get-Content -LiteralPath (Join-Path $directory $name) -Raw | ConvertFrom-Json
                if($value){return $value}
            }catch{if($_.Exception -isnot [System.ArgumentException]){throw}}
        }
        if($watch.ElapsedMilliseconds -gt $milliseconds){throw "FILE_TIMEOUT:$name"}
        Start-Sleep -Milliseconds 25
    }
}
function Start-Probe([string]$role,[int]$count){
    $arguments=@($role,'--directory',$directory,'--count',"$count")
    if($role -eq 'control'){$arguments+=@('--base-port',"$ControlPort")}
    if($role -eq 'fillers'){$arguments+=@('--base-port',"$FillerBasePort")}
    if($role -eq 'server' -and $RecordsFirst){$arguments+=@('--records-first','1')}
    if($role -eq 'server' -and $Mode -eq 'Capacity'){$arguments+=@('--backlog-hint',"$BacklogHint")}
    if($role -eq 'server' -and $Mode -eq 'Drain'){$arguments+=@('--accept-first','1')}
    $process=Start-Process -FilePath $probe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$directory\$role.stdout.txt" -RedirectStandardError "$directory\$role.stderr.txt"
    $children.Add($process)
    return $process
}
try{
    if($BlockDiscard -and $Mode -ne 'SilentRetry'){throw 'DISCARD_BLOCK_REQUIRES_SINGLE_FLOW_DROP_MODE'}
    if($bulk -and $ControlPort -ge $FillerBasePort -and $ControlPort -lt $FillerBasePort+200){throw 'SOURCE_PORT_RANGES_OVERLAP'}
    if((Get-Service ProxyBridgeDrv).Status -ne 'Stopped'){throw 'PRODUCT_DRIVER_MUST_BE_STOPPED'}
    foreach($service in 'WFPSampler','WFPSamplerCallouts'){
        if((Get-Service $service).Status -ne 'Running'){throw 'SAMPLE_SERVICE_NOT_RUNNING'}
    }
    $count=1;if($bulk){$count=201}
    $server=Start-Probe 'server' $count
    $ready=Wait-File 'server-ready.json'
    if($ready.pid -ne $server.Id){throw 'SERVER_PID_DIFFERS'}
    if($Mode -eq 'Capacity' -and $ready.backlogHint -ne $BacklogHint){throw 'BACKLOG_HINT_DIFFERS'}
    if($Mode -eq 'Drain' -and -not $ready.acceptFirst){throw 'ACCEPT_FIRST_NOT_ENABLED'}
    $result['server_ready']=$ready
    $policy=@('-s','PROXY','-l','FWPM_LAYER_ALE_CONNECT_REDIRECT_V4','-ipp','TCP','-ipra','127.0.0.1','-iprp','54122','-aaid',$probe,'-pra','127.0.0.1','-prp','34010','-plspid',"$($server.Id)",'-in','-v')
    $policy | ConvertTo-Json | Set-Content "$directory\policy-arguments.json" -Encoding UTF8
    & $cli @policy *> "$directory\policy-add.txt"
    if($LASTEXITCODE -ne 0){throw 'POLICY_ADD_FAILED'}
    $policyAdded=$true
    if($Mode -eq 'SilentRetry'){
        if($BlockDiscard){
            # Attempt the documented TRANSPORT_DISCARD suppression for this
            # tuple only. Whether reset generation stopped must be checked in ETW.
            $discardPolicy=@('-s','BASIC_ACTION_BLOCK','-l','FWPM_LAYER_INBOUND_TRANSPORT_V4_DISCARD','-ipp','TCP','-ipla','127.0.0.1','-iplp','34010','-ipra','127.0.0.1','-iprp',"$ControlPort",'-v')
            $discardPolicy|ConvertTo-Json|Set-Content "$directory\discard-policy-arguments.json" -Encoding UTF8
            & $cli @discardPolicy *> "$directory\discard-add.txt"
            if($LASTEXITCODE -ne 0){throw 'DISCARD_BLOCK_ADD_FAILED'}
            $discardAdded=$true
            $result['discard_block_enabled']=$true
        }
        # Exact incoming tuple only. Remove after SynSent is observed; ETW
        # records how many retransmissions occurred before removal completed.
        $blockPolicy=@('-s','BASIC_ACTION_BLOCK','-l','FWPM_LAYER_INBOUND_TRANSPORT_V4','-ipp','TCP','-ipla','127.0.0.1','-iplp','34010','-ipra','127.0.0.1','-iprp',"$ControlPort",'-v')
        $blockPolicy | ConvertTo-Json | Set-Content "$directory\block-policy-arguments.json" -Encoding UTF8
        & $cli @blockPolicy *> "$directory\block-add.txt"
        if($LASTEXITCODE -ne 0){throw 'SILENT_BLOCK_ADD_FAILED'}
        $blockAdded=$true
    }
    & logman.exe start $trace -ets -o "$directory\tcpip.etl" -p Microsoft-Windows-TCPIP 0xffffffffffffffff 5 -bs 128 -nb 32 128 *> "$directory\trace-start.txt"
    if($LASTEXITCODE -ne 0){throw 'TRACE_START_FAILED'}
    $traceStarted=$true
    if($Mode -eq 'Drain'){$null=New-Item -ItemType File "$directory\server-release.flag"}
    if(-not $bulk){
        $null=New-Item -ItemType File "$directory\server-release.flag"
    }else{
        $fillers=Start-Probe 'fillers' 200
        $fillerReady=Wait-File 'fillers-ready.json' 20000
        if($fillerReady.pid -ne $fillers.Id){throw 'FILLER_PID_DIFFERS'}
        $owned=@(Get-NetTCPConnection -OwningProcess $fillers.Id -ErrorAction Stop)
        ConvertTo-Json -InputObject @($owned | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess) | Set-Content "$directory\fillers-tcp.json" -Encoding UTF8
        # Winsock hides the redirected tuple; the native TCP table can expose it.
        $connections=@($owned | Where-Object {$_.State -eq 'Established' -and $_.RemotePort -in @(54122,34010) -and $_.LocalPort -ge $FillerBasePort -and $_.LocalPort -lt $FillerBasePort+200})
        $result['filler_native_count']=$connections.Count
        if($connections.Count -ne 200){throw 'FILLER_COUNT_DIFFERS'}
    }
    $control=Start-Probe 'control' 1
    $null=Wait-File 'control-started.json'
    if($Mode -in @('Target','SilentRetry')){
        $watch=[Diagnostics.Stopwatch]::StartNew();$syn=$null
        while($watch.ElapsedMilliseconds -lt 3000){
            $syn=Get-NetTCPConnection -OwningProcess $control.Id -LocalPort $ControlPort -State SynSent -ErrorAction SilentlyContinue
            if($syn){break};Start-Sleep -Milliseconds 20
        }
        if(-not $syn){throw 'CONTROL_SYN_SENT_NOT_OBSERVED'}
        $syn | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess | ConvertTo-Json | Set-Content "$directory\control-syn.json" -Encoding UTF8
        if($Mode -eq 'SilentRetry'){
            $result['drop_hold_milliseconds']=$DropHoldMilliseconds
            Start-Sleep -Milliseconds $DropHoldMilliseconds
        }else{Start-Sleep -Milliseconds 100}
        if($Mode -eq 'SilentRetry'){
            & $cli @blockPolicy -r *> "$directory\block-remove.txt"
            if($LASTEXITCODE -ne 0){throw 'SILENT_BLOCK_REMOVE_FAILED'}
            $blockAdded=$false
            $result['block_removed_after_syn_sent']=$true
        }else{
            $null=New-Item -ItemType File "$directory\server-release.flag"
        }
    }
    if($Mode -in @('Capacity','Drain')){
        $connected=Wait-File 'control-ready.json' 15000
        if($connected.pid -ne $control.Id){throw 'CONTROL_PID_DIFFERS'}
        $result['control_connected_before_processing']=$true
        if($Mode -eq 'Capacity'){$null=New-Item -ItemType File "$directory\server-release.flag"}
    }
    $null=New-Item -ItemType File "$directory\clients-release.flag"
    foreach($process in $children){if(-not $process.WaitForExit(90000)){throw 'CHILD_TIMEOUT'}}
    $rows=@(Get-Content "$directory\server-connections.jsonl" | ForEach-Object {$_ | ConvertFrom-Json})
    $result['queries']=$rows.Count
    $result['query_failures']=@($rows | Where-Object {$_.apiReturn -ne 0} | Select-Object peerPort,apiReturn,apiError,bytesReturned)
    $result['server_summary']=Get-Content "$directory\server-summary.json" -Raw | ConvertFrom-Json
    $result['control_summary']=Get-Content "$directory\control-summary.json" -Raw | ConvertFrom-Json
    if($bulk){
        $result['fillers_summary']=Get-Content "$directory\fillers-summary.json" -Raw | ConvertFrom-Json
        if($result.fillers_summary.completed -ne 200 -or $result.fillers_summary.failures -ne 0){throw 'FILLER_DATA_INCOMPLETE'}
    }
    $result['child_exits']=@($children | ForEach-Object { [ordered]@{pid=$_.Id;exit=$_.ExitCode} })
    if($rows.Count -ne $count){throw 'QUERY_COUNT_DIFFERS'}
    if(@($rows | Group-Object peerPort | Where-Object Count -ne 1).Count){throw 'DUPLICATE_QUERY_PORT'}
    if($Mode -eq 'Drain' -and $result.server_summary.acceptedBeforeProcessing -ne 201){throw 'ACCEPT_DRAIN_INCOMPLETE'}
    if($Mode -eq 'Healthy'){
        if(@($rows | Where-Object {-not $_.contextValid -or -not $_.dataValid}).Count){throw 'HEALTHY_CONTEXT_OR_DATA_FAILED'}
        $result.status='HEALTHY_SUCCESS'
    }elseif($Mode -eq 'SilentRetry'){
        if($rows[0].peerPort -ne $ControlPort){throw 'CONTROL_QUERY_PORT_DIFFERS'}
        $result['selected_query']=$rows[0]
        if($rows[0].contextValid -and $rows[0].dataValid){$result.status='SILENT_RETRY_QUERY_SUCCESS_ETW_PENDING'}
        elseif($rows[0].apiError -eq 10022 -and $rows[0].bytesReturned -eq 0){$result.status='SILENT_RETRY_CONTEXT_FAILURE_ETW_PENDING'}
        else{throw 'OTHER_CONTROL_FAILURE'}
    }else{
        $selected=@($rows | Where-Object peerPort -eq $ControlPort)
        if($selected.Count -ne 1){throw 'CONTROL_QUERY_COUNT_DIFFERS'}
        $result['selected_query']=$selected[0]
        $fill=@($rows | Where-Object peerPort -ne $ControlPort)
        if(@($fill | Where-Object {-not $_.contextValid -or -not $_.dataValid}).Count){throw 'FILLER_CONTEXT_OR_DATA_FAILED'}
        if($selected[0].apiError -eq 10022 -and $selected[0].bytesReturned -eq 0){$result.status='INDEPENDENT_10022_OBSERVED_ETW_PENDING'}
        elseif($selected[0].contextValid -and $selected[0].dataValid){$result.status='TARGET_QUERY_SUCCESS_ETW_PENDING'}
        else{throw 'OTHER_CONTROL_FAILURE'}
    }
}catch{$result['error']=$_.Exception.Message}
finally{
    if($traceStarted){& logman.exe stop $trace -ets *> "$directory\trace-stop.txt";if($LASTEXITCODE -ne 0){$cleanupErrors+='TRACE_STOP_FAILED'}}
    if($blockAdded){& $cli @blockPolicy -r *> "$directory\block-remove-cleanup.txt";if($LASTEXITCODE -ne 0){$cleanupErrors+='SILENT_BLOCK_REMOVE_FAILED'}}
    if($discardAdded){& $cli @discardPolicy -r *> "$directory\discard-remove-cleanup.txt";if($LASTEXITCODE -ne 0){$cleanupErrors+='DISCARD_BLOCK_REMOVE_FAILED'}}
    if($policyAdded){& $cli @policy -r *> "$directory\policy-remove.txt";if($LASTEXITCODE -ne 0){$cleanupErrors+='POLICY_REMOVE_FAILED'}}
    foreach($process in $children){try{if(-not $process.HasExited){$process.Kill();$process.WaitForExit()}}catch{$cleanupErrors+=$_.Exception.Message}}
    $result['cleanup_errors']=$cleanupErrors
    if($cleanupErrors.Count){$result.status='CLEANUP_INCOMPLETE'}
    $result | ConvertTo-Json -Depth 8 | Set-Content "$directory\result.json" -Encoding UTF8
}
$result | ConvertTo-Json -Depth 8
