Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Initialize-RedirectEtwType {
    if ('PbRedirectEtw' -as [type]) {return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PbRedirectEtw {
    [StructLayout(LayoutKind.Sequential)] public struct Wnode {
        public uint BufferSize, ProviderId; public ulong HistoricalContext; public long TimeStamp;
        public Guid Guid; public uint ClientContext, Flags;
    }
    [StructLayout(LayoutKind.Sequential)] public struct Properties {
        public Wnode Wnode; public uint BufferSize, MinimumBuffers, MaximumBuffers, MaximumFileSize;
        public uint LogFileMode, FlushTimer, EnableFlags; public int AgeLimit;
        public uint NumberOfBuffers, FreeBuffers, EventsLost, BuffersWritten, LogBuffersLost, RealTimeBuffersLost;
        public IntPtr LoggerThreadId; public uint LogFileNameOffset, LoggerNameOffset;
    }
    public class Counters {
        public uint EventsLost, LogBuffersLost, RealTimeBuffersLost, BuffersWritten;
        public uint ControlStatus;
    }
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="ControlTraceW")]
    static extern uint ControlTrace(ulong handle, string name, IntPtr properties, uint control);
    public static int PropertiesSize() {return Marshal.SizeOf(typeof(Properties));}
    public static int LostOffset() {return (int)Marshal.OffsetOf(typeof(Properties), "EventsLost");}
    public static Counters Control(string name, bool stop) {
        if (!System.Text.RegularExpressions.Regex.IsMatch(name, "^PBRedirect-[a-f0-9]{32}$"))
            throw new ArgumentException("ETW_SESSION_NAME_NOT_OWNED");
        int size=PropertiesSize(), total=size+8192;
        IntPtr p=Marshal.AllocHGlobal(total);
        try {
            Marshal.Copy(new byte[total],0,p,total);
            var props=new Properties(); props.Wnode.BufferSize=(uint)total;
            props.LoggerNameOffset=(uint)size; props.LogFileNameOffset=(uint)(size+4096);
            Marshal.StructureToPtr(props,p,false);
            uint status=ControlTrace(0,name,p,stop ? 1u : 0u);
            if(status!=0) throw new System.ComponentModel.Win32Exception((int)status);
            props=(Properties)Marshal.PtrToStructure(p,typeof(Properties));
            return new Counters {EventsLost=props.EventsLost,LogBuffersLost=props.LogBuffersLost,
                RealTimeBuffersLost=props.RealTimeBuffersLost,BuffersWritten=props.BuffersWritten,ControlStatus=status};
        } finally {Marshal.FreeHGlobal(p);}
    }
}
'@
    if ([PbRedirectEtw]::PropertiesSize() -ne 120 -or [PbRedirectEtw]::LostOffset() -ne 88) {throw 'ETW_X64_LAYOUT_MISMATCH'}
}

function Write-RedirectEtwState($Context) {
    $Context | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Context.Directory 'capture-state.json') -Encoding UTF8
}

function New-RedirectEtwCapture([string]$Directory) {
    if (Test-Path -LiteralPath $Directory) {throw 'ETW_CAPTURE_DIRECTORY_EXISTS'}
    $null=New-Item -ItemType Directory -Path $Directory
    $context=[pscustomobject][ordered]@{Directory=[IO.Path]::GetFullPath($Directory);Session=('PBRedirect-'+[guid]::NewGuid().ToString('N'));
        Provider='{2f07e2ee-15db-40f1-90ef-9d7ba282188a}';Keywords='0x2080';Level=5;
        Started=$false;Stopped=$false;Exported=$false;StartUtc='';StopUtc='';Counters=$null;Error='';StopFallbackSucceeded=$false}
    Write-RedirectEtwState $context
    return $context
}

function Start-RedirectEtwCapture($Context) {
    Initialize-RedirectEtwType
    $etl=Join-Path $Context.Directory 'tcpip.etl'
    # Diagnostic/control-path keywords only; no stack walking, packet payload or system-wide kernel logger.
    $output=& logman.exe create trace $Context.Session -p $Context.Provider $Context.Keywords $Context.Level -o $etl -f bin -max 128 -bs 64 -nb 16 128 -ft 1 -ct perf -ets 2>&1
    $code=$LASTEXITCODE
    $output | Out-String | Set-Content -LiteralPath (Join-Path $Context.Directory 'start-output.txt') -Encoding UTF8
    if ($code -ne 0) {throw ('ETW_START_FAILED_'+$code)}
    $Context.Started=$true;$Context.StartUtc=[DateTime]::UtcNow.ToString('o');Write-RedirectEtwState $Context
    $null=[PbRedirectEtw]::Control($Context.Session,$false)
}

function Stop-RedirectEtwCapture($Context) {
    if (-not $Context.Started -or $Context.Stopped) {return}
    try {
        # STOP returns final loss counters, including flushing this session's buffers.
        $Context.Counters=[PbRedirectEtw]::Control($Context.Session,$true)
        $Context.Stopped=$true
    } catch {
        $Context.Error=$_.Exception.Message
        # Cleanup only the unique session started above; never stop another collector.
        $output=& logman.exe stop $Context.Session -ets 2>&1
        $Context.StopFallbackSucceeded=($LASTEXITCODE -eq 0)
        $output | Out-String | Set-Content -LiteralPath (Join-Path $Context.Directory 'stop-fallback.txt') -Encoding UTF8
        if ($Context.StopFallbackSucceeded) {$Context.Stopped=$true}
    } finally {
        $Context.StopUtc=[DateTime]::UtcNow.ToString('o');Write-RedirectEtwState $Context
    }
    if ($Context.Error) {throw ('ETW_STOP_OR_FINAL_STATISTICS_FAILED: '+$Context.Error)}
}

function Export-RedirectEtwCapture($Context) {
    if (-not $Context.Stopped -or $null -eq $Context.Counters) {throw 'ETW_NOT_STOPPED_WITH_FINAL_COUNTERS'}
    $output=& tracerpt.exe (Join-Path $Context.Directory 'tcpip.etl') -o (Join-Path $Context.Directory 'events.xml') -of XML -y 2>&1
    $code=$LASTEXITCODE
    $output | Out-String | Set-Content -LiteralPath (Join-Path $Context.Directory 'export-output.txt') -Encoding UTF8
    if ($code -ne 0) {throw ('ETW_EXPORT_FAILED_'+$code)}
    $Context.Exported=$true;Write-RedirectEtwState $Context
}

Export-ModuleMember -Function Initialize-RedirectEtwType,New-RedirectEtwCapture,Start-RedirectEtwCapture,Stop-RedirectEtwCapture,Export-RedirectEtwCapture
