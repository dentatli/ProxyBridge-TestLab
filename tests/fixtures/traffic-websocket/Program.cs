using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;

// Opt-in SDK interoperability. Input is public PKI and one already authenticated message.
using var input = JsonDocument.Parse(await Console.In.ReadToEndAsync());
var data=input.RootElement;
var host=IPAddress.Parse(data.GetProperty("host").GetString()!);
var port=data.GetProperty("port").GetInt32();
var secure=data.GetProperty("secure").GetBoolean();
var message=Convert.FromBase64String(data.GetProperty("message").GetString()!);
if(host.AddressFamily!=AddressFamily.InterNetwork||port<1024||port>65535||message.Length<3||message.Length>8192)
    throw new InvalidOperationException("Invalid component fixture");
using var cancellation=new CancellationTokenSource(TimeSpan.FromSeconds(10));
using var handler=new SocketsHttpHandler { UseProxy=false };
handler.ConnectCallback=async (_,token)=>
{
    var socket=new Socket(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp);
    try {await socket.ConnectAsync(new IPEndPoint(host,port),token);return new NetworkStream(socket,true);}
    catch {socket.Dispose();throw;}
};
var pinVerified=false;
if(secure)
{
    var pin=data.GetProperty("tls_certificate_sha256").GetString()!;
    var ca=X509Certificate2.CreateFromPem(data.GetProperty("tls_ca_pem").GetString()!);
    using(ca)
    using(var chain=new X509Chain())
    {
        // This trust is scoped to the one SDK handler; OS trust is untouched.
        chain.ChainPolicy.TrustMode=X509ChainTrustMode.CustomRootTrust;
        chain.ChainPolicy.CustomTrustStore.Add(ca);
        chain.ChainPolicy.RevocationMode=X509RevocationMode.NoCheck;
        handler.SslOptions.RemoteCertificateValidationCallback=(_,certificate,_,errors)=>
        {
            if(certificate is not X509Certificate2 leaf || (errors&~SslPolicyErrors.RemoteCertificateChainErrors)!=SslPolicyErrors.None)
                return false;
            pinVerified=Convert.ToHexString(SHA256.HashData(leaf.RawData)).Equals(pin,StringComparison.OrdinalIgnoreCase)&&chain.Build(leaf);
            return pinVerified;
        };
        await Exchange();
    }
}
else await Exchange();

async Task Exchange()
{
    using var invoker=new HttpMessageInvoker(handler,false);
    using var client=new ClientWebSocket();
    await client.ConnectAsync(new Uri($"{(secure?"wss":"ws")}://traffic.testlab.invalid:{port}/testlab"),invoker,cancellation.Token);
    var first=message.Length/3;var second=2*message.Length/3;
    await client.SendAsync(message.AsMemory(0,first),WebSocketMessageType.Binary,false,cancellation.Token);
    await client.SendAsync(message.AsMemory(first,second-first),WebSocketMessageType.Binary,false,cancellation.Token);
    await client.SendAsync(message.AsMemory(second),WebSocketMessageType.Binary,true,cancellation.Token);
    using var received=new MemoryStream();
    var buffer=new byte[512];
    while(true)
    {
        var result=await client.ReceiveAsync(buffer.AsMemory(),cancellation.Token);
        if(result.MessageType!=WebSocketMessageType.Binary||received.Length+result.Count>8192)
            throw new InvalidOperationException("Unexpected SDK reply");
        received.Write(buffer,0,result.Count);
        if(result.EndOfMessage)break;
    }
    await client.CloseAsync(WebSocketCloseStatus.NormalClosure,"",cancellation.Token);
    if(client.CloseStatus!=WebSocketCloseStatus.NormalClosure||secure&&!pinVerified)
        throw new InvalidOperationException("SDK identity or close unverified");
    Console.WriteLine(JsonSerializer.Serialize(new {response=Convert.ToBase64String(received.ToArray()),
        close_verified=true,tls_pin_verified=pinVerified}));
}
