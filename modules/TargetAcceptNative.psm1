Set-StrictMode -Version Latest

function Initialize-TargetTcpTable {
    if ('PBTargetTcpTable' -as [type]) {return}
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Net;
public static class PBTargetTcpTable {
    [DllImport("iphlpapi.dll")] static extern uint GetExtendedTcpTable(IntPtr p, ref int n, bool order, int af, int cls, uint reserved);
    public class Row { public uint State, Pid; public int LocalPort, RemotePort; public string LocalAddress, RemoteAddress; }
    public static Row[] Read() {
        int size=0; uint code=GetExtendedTcpTable(IntPtr.Zero,ref size,false,2,5,0);
        if(code!=122) throw new System.ComponentModel.Win32Exception((int)code);
        for(int attempt=0;attempt<4;attempt++) {
            IntPtr p=Marshal.AllocHGlobal(size);
            try {
                code=GetExtendedTcpTable(p,ref size,false,2,5,0);
                if(code==122) continue;
                if(code!=0) throw new System.ComponentModel.Win32Exception((int)code);
                int count=Marshal.ReadInt32(p);
                if(count<0 || count>(size-4)/24) throw new InvalidOperationException("TCP_TABLE_LAYOUT_INVALID");
                var rows=new List<Row>();
                for(int i=0;i<count;i++) {
                    int o=4+i*24;
                    rows.Add(new Row {State=(uint)Marshal.ReadInt32(p,o),
                        LocalAddress=new IPAddress((uint)Marshal.ReadInt32(p,o+4)).ToString(),
                        LocalPort=(Marshal.ReadByte(p,o+8)<<8)|Marshal.ReadByte(p,o+9),
                        RemoteAddress=new IPAddress((uint)Marshal.ReadInt32(p,o+12)).ToString(),
                        RemotePort=(Marshal.ReadByte(p,o+16)<<8)|Marshal.ReadByte(p,o+17),
                        Pid=(uint)Marshal.ReadInt32(p,o+20)});
                }
                return rows.ToArray();
            } finally {Marshal.FreeHGlobal(p);}
        }
        throw new InvalidOperationException("TCP_TABLE_UNSTABLE");
    }
}
'@
}

function Write-TargetJson($Value,[string]$Path) {
    ConvertTo-Json -InputObject $Value -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Start-TargetNative($Context,[string]$Role,[string[]]$Arguments) {
    $plan=[pscustomobject]@{executable=$Context.client;arguments=$Arguments;timeout_ms=60000}
    # Register ownership immediately, before identity checks can throw.
    try {$child=& $Context.adapter.StartProcess $plan}
    catch {
        $failure=[ordered]@{role=$Role;error=$_.Exception.Message;metadata=[ordered]@{}}
        $cause=$_.Exception
        while ($cause) {
            foreach ($key in $cause.Data.Keys) {if ([string]$key -like 'PB_START_*') {$failure.metadata[[string]$key]=$cause.Data[$key]}}
            $cause=$cause.InnerException
        }
        Write-TargetJson $failure (Join-Path $Context.directory ($Role+'-start-failure.json'))
        throw
    }
    $Context.children.Add([pscustomobject]@{role=$Role;child=$child})
    $probe=& $Context.adapter.ProbeActualPath $child 2000 25
    if ($probe.status -ne 'PATH_OBTAINED' -or $child.actual_path -ine $Context.client) {throw 'TARGET_NATIVE_PATH_UNCONFIRMED'}
    $observed=Get-CimInstance Win32_Process -Filter ('ProcessId='+$child.pid) -OperationTimeoutSec 5
    Write-TargetJson ([ordered]@{pid=$child.pid;role=$Role;expected_executable=$Context.client;
        arguments=$Arguments;observed_executable=$observed.ExecutablePath;observed_command_line=$observed.CommandLine;
        qpc=[Diagnostics.Stopwatch]::GetTimestamp()}) (Join-Path $Context.directory ($Role+'-launch.json'))
    return $child
}

function Invoke-TargetNativeCohort {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Gate)
    Initialize-TargetTcpTable
    $probeOnly=$Context.PSObject.Properties['probe_only'] -and $Context.probe_only
    $manualHost=$Context.PSObject.Properties['manual_host_window'] -and $Context.manual_host_window
    $flowObserver=$Context.PSObject.Properties['flow_observer'] -and $Context.flow_observer
    if ($manualHost -and $probeOnly) {throw 'TARGET_MANUAL_HOST_REQUIRES_TARGET_201'}
    $fillerCount=if ($probeOnly) {3} else {200}
    $fillerPortEnd=42000+$fillerCount
    $Context | Add-Member -NotePropertyName children -NotePropertyValue ([Collections.Generic.List[object]]::new())
    $Context | Add-Member -NotePropertyName clock -NotePropertyValue ([Diagnostics.Stopwatch]::StartNew())
    $record=[ordered]@{method='target-native-cohort-v1';status='RUNNING';fillers=$fillerCount;control_port=42201;
        error='';cleanup_errors=@();native_processes_stopped=$false;observations=@();hold_ms=100}
    $Context | Add-Member -NotePropertyName record -NotePropertyValue $record
    $common=@('-protocol:tcp','-pattern:push','-transfer:524288','-ratelimit:65536','-verify:data',
        '-port:54122','-buffer:65536','-consoleverbosity:1','-statusupdate:250','-target:127.0.0.1',
        '-iterations:1','-throttleconnections:32','-conn:ConnectEx','-shutdown:rude')
    $startCommand=Get-Command Start-TargetNative
    $startFillers={& $startCommand $Context 'fillers' ($common+@(('-connections:'+$fillerCount),('-LocalPort:[42001,'+$fillerPortEnd+']'),('-connectionfilename:'+(Join-Path $Context.directory 'fillers.csv'))))}.GetNewClosure()
    $startControl={
        if ($manualHost -and $Context.clock.ElapsedMilliseconds -ge 15000) {throw 'TARGET_HOST_WINDOW_EXPIRED_NO_CONTROL'}
        & $startCommand $Context 'control' ($common+@('-connections:1','-LocalPort:42201',('-connectionfilename:'+(Join-Path $Context.directory 'control.csv'))))
    }.GetNewClosure()
    $waitFillers={param($child)
        do {
            $rows=@([PBTargetTcpTable]::Read() | Where-Object {$_.Pid -eq $child.pid -and $_.State -eq 5 -and
                $_.LocalAddress -eq '127.0.0.1' -and $_.LocalPort -ge 42001 -and $_.LocalPort -le $fillerPortEnd -and
                $_.RemoteAddress -eq '127.0.0.1' -and $_.RemotePort -in @(34010,54122)})
            if ($rows.Count -eq $fillerCount -and @($rows.LocalPort | Sort-Object -Unique).Count -eq $fillerCount) {
                $Context.record.observations+=@([ordered]@{stage='fillers-established';qpc=[Diagnostics.Stopwatch]::GetTimestamp();pid=$child.pid;sockets=$rows});return
            }
            if (-not $child.session.IsRunning) {throw 'TARGET_FILLERS_EARLY_EXIT'}
            if ($Context.clock.ElapsedMilliseconds -ge 15000) {throw 'TARGET_FILLERS_NOT_ESTABLISHED'}
            Start-Sleep -Milliseconds 5
        } while ($true)
    }.GetNewClosure()
    $waitSyn={param($child)
        $timer=[Diagnostics.Stopwatch]::StartNew()
        do {
            $rows=@([PBTargetTcpTable]::Read() | Where-Object {$_.Pid -eq $child.pid -and $_.LocalPort -eq 42201 -and
                $_.LocalAddress -eq '127.0.0.1' -and $_.RemoteAddress -eq '127.0.0.1' -and $_.RemotePort -in @(34010,54122)})
            if (@($rows | Where-Object State -eq 5).Count) {
                if (-not $probeOnly) {throw 'TARGET_CONTROL_ALREADY_ESTABLISHED'}
                $Context.record.observations+=@([ordered]@{stage='control-established';qpc=[Diagnostics.Stopwatch]::GetTimestamp();pid=$child.pid;sockets=$rows});return
            }
            if (@($rows | Where-Object State -eq 3).Count -eq 1) {
                if ($probeOnly) {
                    if ($timer.ElapsedMilliseconds -ge 1000 -or $Context.clock.ElapsedMilliseconds -ge 20000) {throw 'TARGET_CONTROL_ESTABLISH_TIMEOUT'}
                    Start-Sleep -Milliseconds 1;continue
                }
                $Context.record.observations+=@([ordered]@{stage='control-synsent';qpc=[Diagnostics.Stopwatch]::GetTimestamp();pid=$child.pid;sockets=$rows});return
            }
            if (-not $child.session.IsRunning -or $timer.ElapsedMilliseconds -ge 1000 -or $Context.clock.ElapsedMilliseconds -ge 20000) {throw 'TARGET_CONTROL_SYN_NOT_OBSERVED'}
            Start-Sleep -Milliseconds 1
        } while ($true)
    }.GetNewClosure()
    $hold={Start-Sleep -Milliseconds 100
        $Context.record.observations+=@([ordered]@{stage='release-request';qpc=[Diagnostics.Stopwatch]::GetTimestamp()})
    }.GetNewClosure()
    $collect={param($fillers,$control)
        foreach ($child in @($fillers,$control)) {
            $remaining=[int][Math]::Max(1,60000-$Context.clock.ElapsedMilliseconds)
            if (-not $child.session.WaitForExit($remaining)) {throw 'TARGET_NATIVE_TIMEOUT'}
        }
        $Context.record.status='COLLECTED'
    }.GetNewClosure()
    $beforeControl=$null
    if ($manualHost) {
        Import-Module (Join-Path $PSScriptRoot 'TargetHostWindow.psm1')
        $windowCommand=Get-Command Wait-TargetHostWindow
        $beforeControl={param($fillers)
            # Discard buffered keys: confirmation must follow this ready message.
            while ([Console]::KeyAvailable) {$null=[Console]::ReadKey($true)}
            $hostCommands=if ($flowObserver) {'reset t1=0, be2, be3, be4'} else {'be2'}
            $hostRecovery=if ($flowObserver) {'bd2, bd3, bd4'} else {'bd2'}
            Write-Host ('TARGET_PREFILL_READY: 200 connections; host Break, '+$hostCommands+', separate g; then press C here. Remaining window ms: '+(15000-$Context.clock.ElapsedMilliseconds))
            Write-Host ('Break/be can pause the entire VM including Codex/RDP. After completion/error: host '+$hostRecovery+', separate g. No repeat Run.')
            $elapsed={$Context.clock.ElapsedMilliseconds}.GetNewClosure()
            $confirmed={
                if (-not [Console]::KeyAvailable) {return $false}
                return [Console]::ReadKey($true).KeyChar -in @('c','C')
            }
            $validateReady={
                if (-not $fillers.session.IsRunning) {throw 'TARGET_FILLERS_EARLY_EXIT'}
                $rows=@([PBTargetTcpTable]::Read() | Where-Object {$_.Pid -eq $fillers.pid -and $_.State -eq 5 -and
                    $_.LocalAddress -eq '127.0.0.1' -and $_.LocalPort -ge 42001 -and $_.LocalPort -le 42200 -and
                    $_.RemoteAddress -eq '127.0.0.1' -and $_.RemotePort -in @(34010,54122)})
                if ($rows.Count -ne 200 -or @($rows.LocalPort | Sort-Object -Unique).Count -ne 200) {throw 'TARGET_PREFILL_CHANGED_NO_CONTROL'}
            }.GetNewClosure()
            $window=& $windowCommand -Elapsed $elapsed -Confirmed $confirmed -ValidateReady $validateReady
            $Context.record['host_window']=$window
            $Context.record.observations+=@([ordered]@{stage='host-confirmed';qpc=[Diagnostics.Stopwatch]::GetTimestamp();elapsed_ms=$Context.clock.ElapsedMilliseconds})
        }.GetNewClosure()
    }
    $writeCommand=Get-Command Write-TargetJson
    $cleanup={param($fillers,$control)
        foreach ($entry in $Context.children) {
            try {
                if ($entry.child.session.IsRunning) {& $Context.adapter.KillProcess $entry.child;throw 'TARGET_NATIVE_FORCED_STOP'}
            } catch {$Context.record.cleanup_errors+=@($_.Exception.Message)}
            finally {
                try {& $writeCommand (& $Context.adapter.GetProcessResult $entry.child) (Join-Path $Context.directory ($entry.role+'-process.json'))}
                catch {$Context.record.cleanup_errors+=@($_.Exception.Message)}
                finally {
                    try {& $Context.adapter.DisposeProcess $entry.child}
                    catch {$Context.record.cleanup_errors+=@($_.Exception.Message)}
                }
            }
        }
        $Context.record.native_processes_stopped=$Context.record.cleanup_errors.Count -eq 0
    }.GetNewClosure()
    try {
        $sequenceArgs=@{Gate=$Gate;StartFillers=$startFillers;WaitFillers=$waitFillers;StartControl=$startControl;
            WaitControlSyn=$waitSyn;Hold=$hold;Collect=$collect;Cleanup=$cleanup}
        if ($beforeControl) {$sequenceArgs.BeforeControl=$beforeControl}
        Invoke-TargetAcceptSequence @sequenceArgs
    } catch {$record.status='INCOMPLETE';$record.error=$_.Exception.Message}
    finally {
        if ($record.cleanup_errors.Count) {$record.status='INCOMPLETE'}
        $record['elapsed_ms']=$Context.clock.ElapsedMilliseconds
        Write-TargetJson $record (Join-Path $Context.directory 'cohort.json')
    }
    if ($record.status -ne 'COLLECTED') {throw ('TARGET_COHORT_INCOMPLETE: '+$record.error)}
}

Export-ModuleMember -Function Initialize-TargetTcpTable,Invoke-TargetNativeCohort,Write-TargetJson
