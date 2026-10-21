// Independent Winsock probe. No ProxyBridge code or kernel modifications.
// The controller owns WFP policy, ETW and fresh per-trial directories.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Threading;

public sealed class ProbeReady
{
    public string role;
    public int pid, count, listenPort, destinationPort;
}
public sealed class ProbeConnection
{
    public string role, error, contextRemoteAddress;
    public int pid, tid, localPort, peerPort, apiReturn, apiError;
    public int contextRemotePort, contextFamily, bufferCapacity, expectedContextBytes;
    public uint bytesReturned;
    public bool recordsQueried;
    public int recordsApiReturn, recordsApiError, recordsBufferCapacity;
    public uint recordsBytesReturned;
    public long queryBeginQpc, queryEndQpc, frequency, sentBytes, receivedBytes;
    public ulong socketValue;
    public bool contextValid, dataValid;
}
public sealed class ProbeSummary
{
    public string role, error;
    public int pid, expected, completed, failures;
    public bool cleanupCompleted;
}
public static class WfpContextProbe
{
    const uint QueryContext = 0x980000DD;
    const uint QueryRecords = 0x980000DC;
    const int ContextCapacity = 4096;
    const int ExpectedContextSize = 256; // pinned WFPSampler: two SOCKADDR_STORAGE
    static readonly int Pid = Process.GetCurrentProcess().Id;
    static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
    [DllImport("ws2_32.dll", SetLastError=true)]
    static extern int WSAIoctl(IntPtr socket, uint code, IntPtr input, uint inputSize,
        [Out] byte[] output, uint outputSize, out uint bytes, IntPtr overlapped, IntPtr completion);
    [DllImport("ws2_32.dll")] static extern int WSAGetLastError();
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();

    static string Json(object value)
    {
        using (var memory = new MemoryStream())
        {
            new DataContractJsonSerializer(value.GetType()).WriteObject(memory, value);
            return Utf8.GetString(memory.ToArray());
        }
    }
    static void NewJson(string path, object value)
    {
        using (var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write))
        using (var writer = new StreamWriter(file, Utf8)) writer.WriteLine(Json(value));
    }
    static void WaitFlag(string directory, string flag, Stopwatch deadline)
    {
        while (!File.Exists(Path.Combine(directory, flag)))
        {
            if (deadline.ElapsedMilliseconds > 90000) throw new TimeoutException("GATE_TIMEOUT:" + flag);
            Thread.Sleep(20);
        }
    }
    static Socket NewSocket()
    {
        return new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp)
        { ReceiveTimeout=10000, SendTimeout=10000, NoDelay=true };
    }
    static byte Pattern(int sourcePort, int offset) { return (byte)((sourcePort + offset) % 251); }
    static void SendPayload(Socket socket, int sourcePort, int length, ProbeConnection result)
    {
        var buffer = new byte[16384]; int done = 0;
        while (done < length)
        {
            int chunk = Math.Min(buffer.Length, length - done);
            for (int i=0; i<chunk; ++i) buffer[i]=Pattern(sourcePort, done+i);
            int sent=socket.Send(buffer, 0, chunk, SocketFlags.None);
            if (sent <= 0) throw new IOException("SEND_ZERO");
            done+=sent; result.sentBytes+=sent;
        }
    }
    static void ReceivePayload(Socket socket, int sourcePort, int length, ProbeConnection result)
    {
        var buffer = new byte[16384]; int done = 0;
        while (done < length)
        {
            int count=socket.Receive(buffer, 0, Math.Min(buffer.Length,length-done), SocketFlags.None);
            if (count == 0) throw new IOException("PEER_CLOSED");
            for (int i=0; i<count; ++i)
                if (buffer[i] != Pattern(sourcePort,done+i)) throw new IOException("PAYLOAD_DIFFERS");
            done+=count; result.receivedBytes+=count;
        }
    }
    static ProbeConnection Query(Socket socket, int destinationPort, bool recordsFirst)
    {
        var bytes = new byte[ContextCapacity]; uint returned = 0;
        var result = new ProbeConnection { role="server", pid=Pid,
            tid=(int)GetCurrentThreadId(), socketValue=unchecked((ulong)socket.Handle.ToInt64()),
            bufferCapacity=ContextCapacity, expectedContextBytes=ExpectedContextSize,
            frequency=Stopwatch.Frequency };
        if (recordsFirst)
        {
            var records = new byte[65536]; uint recordsReturned;
            result.recordsQueried=true; result.recordsBufferCapacity=records.Length;
            result.recordsApiReturn=WSAIoctl(socket.Handle, QueryRecords, IntPtr.Zero, 0,
                records, (uint)records.Length, out recordsReturned, IntPtr.Zero, IntPtr.Zero);
            result.recordsApiError=result.recordsApiReturn == -1 ? WSAGetLastError() : 0;
            result.recordsBytesReturned=recordsReturned;
        }
        result.queryBeginQpc=Stopwatch.GetTimestamp();
        result.apiReturn=WSAIoctl(socket.Handle, QueryContext, IntPtr.Zero, 0,
            bytes, ContextCapacity, out returned, IntPtr.Zero, IntPtr.Zero);
        result.apiError=result.apiReturn == -1 ? WSAGetLastError() : 0;
        result.queryEndQpc=Stopwatch.GetTimestamp(); result.bytesReturned=returned;
        result.localPort=((IPEndPoint)socket.LocalEndPoint).Port;
        result.peerPort=((IPEndPoint)socket.RemoteEndPoint).Port;
        if (result.apiReturn == 0 && returned >= 8)
        {
            result.contextFamily=BitConverter.ToUInt16(bytes,0);
            result.contextRemotePort=(bytes[2]<<8)|bytes[3];
            result.contextRemoteAddress=new IPAddress(new byte[] {bytes[4],bytes[5],bytes[6],bytes[7]}).ToString();
            result.contextValid=returned == ExpectedContextSize && result.contextFamily == 2 &&
                result.contextRemotePort == destinationPort && result.contextRemoteAddress == "127.0.0.1";
        }
        return result;
    }
    static int Server(string directory, int count, int listenPort, int destinationPort, int backlog, int payload, bool recordsFirst)
    {
        var summary = new ProbeSummary {role="server",pid=Pid,expected=count};
        var deadline=Stopwatch.StartNew(); Socket listener=null;
        NewJson(Path.Combine(directory,"server.claim.json"),summary);
        try
        {
            listener=NewSocket(); listener.Bind(new IPEndPoint(IPAddress.Loopback,listenPort));
            listener.Listen(backlog);
            NewJson(Path.Combine(directory,"server-ready.json"),new ProbeReady {
                role="server",pid=Pid,count=count,listenPort=listenPort,destinationPort=destinationPort});
            WaitFlag(directory,"server-release.flag",deadline);
            using (var log = new StreamWriter(new FileStream(Path.Combine(directory,"server-connections.jsonl"),FileMode.CreateNew),Utf8))
            {
                log.AutoFlush=true;
                while (summary.completed < count)
                {
                    if (deadline.ElapsedMilliseconds > 90000) throw new TimeoutException("ACCEPT_TOTAL_TIMEOUT");
                    if (!listener.Poll(100000,SelectMode.SelectRead)) continue;
                    using (Socket socket=listener.Accept())
                    {
                        socket.ReceiveTimeout=10000; socket.SendTimeout=10000;
                        // One original query per socket; no fallback or retry.
                        ProbeConnection row=Query(socket,destinationPort,recordsFirst);
                        try
                        {
                            if (row.apiReturn != 0 || !row.contextValid) throw new IOException("ORIGINAL_CONTEXT_QUERY_FAILED");
                            if (recordsFirst && (row.recordsApiReturn != 0 || row.recordsBytesReturned == 0)) throw new IOException("ORIGINAL_RECORDS_QUERY_FAILED");
                            ReceivePayload(socket,row.peerPort,payload,row);
                            SendPayload(socket,row.peerPort,payload,row); row.dataValid=true;
                        }
                        catch (Exception error) {row.error=error.Message; summary.failures++;}
                        log.WriteLine(Json(row)); summary.completed++;
                    }
                }
            }
        }
        catch (Exception error) {summary.error=error.Message; summary.failures++;}
        finally
        {
            if (listener != null) listener.Close(); summary.cleanupCompleted=true;
            NewJson(Path.Combine(directory,"server-summary.json"),summary);
        }
        return summary.failures == 0 ? 0 : 2;
    }
    static int Clients(string directory, string role, int count, int basePort, int destinationPort, int payload)
    {
        var sockets=new List<Socket>(); var summary=new ProbeSummary {role=role,pid=Pid,expected=count};
        var deadline=Stopwatch.StartNew();
        NewJson(Path.Combine(directory,role+".claim.json"),summary);
        try
        {
            NewJson(Path.Combine(directory,role+"-started.json"),new ProbeReady {
                role=role,pid=Pid,count=count,destinationPort=destinationPort});
            for (int i=0; i<count; ++i)
            {
                if (deadline.ElapsedMilliseconds > 90000) throw new TimeoutException("CONNECT_TOTAL_TIMEOUT");
                Socket socket=NewSocket(); sockets.Add(socket);
                socket.Bind(new IPEndPoint(IPAddress.Loopback,basePort+i));
                IAsyncResult pending=socket.BeginConnect(IPAddress.Loopback,destinationPort,null,null);
                try
                {
                    if (!pending.AsyncWaitHandle.WaitOne(15000)) throw new TimeoutException("CONNECT_TIMEOUT");
                    socket.EndConnect(pending);
                }
                finally {pending.AsyncWaitHandle.Close();}
            }
            NewJson(Path.Combine(directory,role+"-ready.json"),new ProbeReady {role=role,pid=Pid,count=count,destinationPort=destinationPort});
            WaitFlag(directory,"clients-release.flag",deadline);
            using (var log=new StreamWriter(new FileStream(Path.Combine(directory,role+"-connections.jsonl"),FileMode.CreateNew),Utf8))
            {
                log.AutoFlush=true;
                foreach (Socket socket in sockets)
                {
                    if (deadline.ElapsedMilliseconds > 90000) throw new TimeoutException("CLIENT_TOTAL_TIMEOUT");
                    var row=new ProbeConnection {role=role,pid=Pid,localPort=((IPEndPoint)socket.LocalEndPoint).Port,
                        peerPort=((IPEndPoint)socket.RemoteEndPoint).Port,frequency=Stopwatch.Frequency};
                    try
                    {
                        SendPayload(socket,row.localPort,payload,row);
                        ReceivePayload(socket,row.localPort,payload,row); row.dataValid=true;
                    }
                    catch (Exception error) {row.error=error.Message; summary.failures++;}
                    log.WriteLine(Json(row)); summary.completed++;
                }
            }
        }
        catch (Exception error) {summary.error=error.Message; summary.failures++;}
        finally
        {
            foreach (Socket socket in sockets) socket.Close(); summary.cleanupCompleted=true;
            NewJson(Path.Combine(directory,role+"-summary.json"),summary);
        }
        return summary.failures == 0 ? 0 : 2;
    }
    static int Number(Dictionary<string,string> args, string key, int fallback, int min, int max)
    {
        int value=args.ContainsKey(key) ? int.Parse(args[key]) : fallback;
        if (value<min || value>max) throw new ArgumentOutOfRangeException(key); return value;
    }
    public static int Main(string[] args)
    {
        if (args.Length == 0 || (args.Length == 1 && args[0] == "--help"))
        {
            Console.WriteLine("WfpContextProbe server|fillers|control --directory FRESH_TRIAL_DIR [--count N] [--base-port N] [--listen-port N] [--destination-port N] [--backlog N] [--payload-bytes N] [--records-first 0|1]");
            Console.WriteLine("No driver, filter or ETW setup. server-release.flag / clients-release.flag are controlled externally. --help creates no sockets.");
            return 0;
        }
        try
        {
            string role=args[0]; if (role!="server" && role!="fillers" && role!="control") throw new ArgumentException("ROLE_INVALID");
            var values=new Dictionary<string,string>();
            for (int i=1; i<args.Length; i+=2)
            {
                if (i+1>=args.Length) throw new ArgumentException("OPTION_VALUE_MISSING");
                if (args[i]!="--directory" && args[i]!="--count" && args[i]!="--base-port" && args[i]!="--listen-port" && args[i]!="--destination-port" && args[i]!="--backlog" && args[i]!="--payload-bytes" && args[i]!="--records-first") throw new ArgumentException("UNKNOWN_OPTION");
                values.Add(args[i],args[i+1]);
            }
            string directory=Path.GetFullPath(values["--directory"]);
            if (!Directory.Exists(directory)) throw new DirectoryNotFoundException(directory);
            int count=Number(values,"--count",role=="server"?201:role=="fillers"?200:1,1,role=="server"?201:200);
            if (role=="control" && count!=1) throw new ArgumentException("CONTROL_COUNT_MUST_BE_ONE");
            int destination=Number(values,"--destination-port",54122,1024,65535);
            int payload=Number(values,"--payload-bytes",524288,1,524288);
            if (role=="server") return Server(directory,count,Number(values,"--listen-port",34010,1024,65535),destination,Number(values,"--backlog",int.MaxValue,1,int.MaxValue),payload,Number(values,"--records-first",0,0,1)==1);
            int first=Number(values,"--base-port",role=="control"?42201:42001,1024,65535);
            if (first+count-1>65535) throw new ArgumentException("PORT_RANGE_INVALID");
            return Clients(directory,role,count,first,destination,payload);
        }
        catch (Exception error) {Console.Error.WriteLine(error.Message); return 3;}
    }
}
