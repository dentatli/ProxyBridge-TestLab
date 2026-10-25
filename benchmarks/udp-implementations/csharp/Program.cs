using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;

const int Body=512, SignedBytes=32+Body, Packet=SignedBytes+32;
const uint Magic=0x31424c50;
long nonce=1,accepted=0,invalid=0,sendErrors=0;
int stopped=0;
byte[] key=Enumerable.Range(0,32).Select(v=>(byte)v).ToArray(); // Public benchmark key.
using var socket=new Socket(AddressFamily.InterNetwork,SocketType.Dgram,ProtocolType.Udp);
socket.ReceiveBufferSize=4*1024*1024;socket.SendBufferSize=4*1024*1024;socket.ReceiveTimeout=200;
socket.Bind(new IPEndPoint(IPAddress.Loopback,0));
var thread=new Thread(()=>{
    var buffer=new byte[65536];var peer=new SocketAddress(AddressFamily.InterNetwork);
    Span<byte> expected=stackalloc byte[32];
    using var hmac=new HMACSHA256(key);
    while(Volatile.Read(ref stopped)==0){
        int n;
        try{n=socket.ReceiveFrom(buffer.AsSpan(),SocketFlags.None,peer);}
        catch(SocketException e)when(e.SocketErrorCode==SocketError.TimedOut){continue;}
        catch(SocketException){if(Volatile.Read(ref stopped)!=0)break;Interlocked.Increment(ref sendErrors);continue;}
        catch(ObjectDisposedException){break;}
        var data=buffer.AsSpan(0,n);
        if(n!=Packet||BinaryPrimitives.ReadUInt32LittleEndian(data)!=Magic||data[4]!=1||data[5]!=0||data[6]!=1||data[7]!=0||
           BinaryPrimitives.ReadUInt64LittleEndian(data[24..])!=unchecked((ulong)Interlocked.Read(ref nonce))){Interlocked.Increment(ref invalid);continue;}
        uint flow=BinaryPrimitives.ReadUInt32LittleEndian(data[8..]),sequence=BinaryPrimitives.ReadUInt32LittleEndian(data[12..]);
        if(flow>=1024){Interlocked.Increment(ref invalid);continue;}
        hmac.TryComputeHash(data[..SignedBytes],expected,out _);
        int diff=CryptographicOperations.FixedTimeEquals(expected,data[SignedBytes..])?0:1;
        for(uint i=0;i<Body;i++)diff|=data[32+(int)i]^unchecked((byte)(flow+sequence+i));
        if(diff!=0){Interlocked.Increment(ref invalid);continue;}
        data[6]=2;hmac.TryComputeHash(data[..SignedBytes],data[SignedBytes..],out _);
        try{if(socket.SendTo(data,SocketFlags.None,peer)!=Packet)Interlocked.Increment(ref sendErrors);else Interlocked.Increment(ref accepted);}
        catch(SocketException){Interlocked.Increment(ref sendErrors);}
    }
}){IsBackground=true,Name="UDP benchmark worker"};
thread.Start();
Console.WriteLine($"{{\"ready\":true,\"port\":{((IPEndPoint)socket.LocalEndPoint!).Port},\"receive_buffer\":{socket.ReceiveBufferSize}}}");
while(Console.ReadLine() is string command){
    if(command.StartsWith("RESET ",StringComparison.Ordinal)){
        Interlocked.Exchange(ref nonce,unchecked((long)Convert.ToUInt64(command[6..],16)));
        Interlocked.Exchange(ref accepted,0);Interlocked.Exchange(ref invalid,0);Interlocked.Exchange(ref sendErrors,0);
        Console.WriteLine("{\"reset\":true}");
    }else if(command=="STATS"){
        Console.WriteLine($"{{\"accepted\":{Interlocked.Read(ref accepted)},\"invalid\":{Interlocked.Read(ref invalid)},\"send_errors\":{Interlocked.Read(ref sendErrors)}}}");
    }else if(command=="STOP")break;
}
Volatile.Write(ref stopped,1);socket.Close();
if(!thread.Join(3000))return 5;
return 0;
