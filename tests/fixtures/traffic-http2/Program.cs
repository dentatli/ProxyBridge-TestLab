using System.Net;
using System.Net.Http.Headers;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;

// Opt-in SDK component probe. Input contains signed messages, never the runtime secret.
using var input=JsonDocument.Parse(await Console.In.ReadToEndAsync());
var data=input.RootElement;
var host=IPAddress.Parse(data.GetProperty("host").GetString()!);
var port=data.GetProperty("port").GetInt32();
var messages=data.GetProperty("messages").EnumerateArray().Select(item=>Convert.FromBase64String(item.GetString()!)).ToArray();
if(host.AddressFamily!=AddressFamily.InterNetwork||port<1024||port>65535||messages.Length!=3||messages.Any(item=>item.Length<1||item.Length>8192))
    throw new InvalidOperationException("Invalid component fixture");
using var cancellation=new CancellationTokenSource(TimeSpan.FromSeconds(10));
using var handler=new SocketsHttpHandler {UseProxy=false,MaxConnectionsPerServer=1,EnableMultipleHttp2Connections=false};
var connections=0;
handler.ConnectCallback=async (_,token)=>
{
    var socket=new Socket(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp);
    try
    {
        await socket.ConnectAsync(new IPEndPoint(host,port),token);
        Interlocked.Increment(ref connections);
        return new NetworkStream(socket,true);
    }
    catch {socket.Dispose();throw;}
};
var pin=data.GetProperty("tls_certificate_sha256").GetString()!;
using var ca=X509Certificate2.CreateFromPem(data.GetProperty("tls_ca_pem").GetString()!);
using var chain=new X509Chain();
chain.ChainPolicy.TrustMode=X509ChainTrustMode.CustomRootTrust;
chain.ChainPolicy.CustomTrustStore.Add(ca);
chain.ChainPolicy.RevocationMode=X509RevocationMode.NoCheck;
var pinVerified=false;
handler.SslOptions.RemoteCertificateValidationCallback=(_,certificate,_,errors)=>
{
    if(certificate is not X509Certificate2 leaf||(errors&~SslPolicyErrors.RemoteCertificateChainErrors)!=SslPolicyErrors.None)return false;
    pinVerified=Convert.ToHexString(SHA256.HashData(leaf.RawData)).Equals(pin,StringComparison.OrdinalIgnoreCase)&&chain.Build(leaf);
    return pinVerified;
};
using var client=new HttpClient(handler);
var barrier=new BodyBarrier();
var replies=await Task.WhenAll(messages.Select(async message=>
{
    using var request=new HttpRequestMessage(HttpMethod.Post,$"https://traffic.testlab.invalid:{port}/testlab")
    {Content=new GatedContent(message,barrier),Version=HttpVersion.Version20,VersionPolicy=HttpVersionPolicy.RequestVersionExact};
    request.Content.Headers.ContentType=new MediaTypeHeaderValue("application/json");
    using var response=await client.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,cancellation.Token);
    if(response.Version!=HttpVersion.Version20||response.StatusCode!=HttpStatusCode.OK||response.Content.Headers.ContentType?.MediaType!="application/json")
        throw new InvalidOperationException("HTTP/2 response invalid");
    using var stream=await response.Content.ReadAsStreamAsync(cancellation.Token);
    using var output=new MemoryStream();
    var buffer=new byte[1024];
    while(true)
    {
        var count=await stream.ReadAsync(buffer,cancellation.Token);
        if(count==0)break;
        if(output.Length+count>8192)throw new InvalidOperationException("Response too large");
        output.Write(buffer,0,count);
    }
    return Convert.ToBase64String(output.ToArray());
}));
if(connections!=1||!pinVerified)throw new InvalidOperationException("Connection identity invalid");
Console.WriteLine(JsonSerializer.Serialize(new {responses=replies,tls_pin_verified=pinVerified,tcp_connections=connections}));

sealed class BodyBarrier
{
    private int waiting;
    private readonly TaskCompletionSource gate=new(TaskCreationOptions.RunContinuationsAsynchronously);
    public async Task Enter(CancellationToken token)
    {
        if(Interlocked.Increment(ref waiting)==3)gate.TrySetResult();
        await gate.Task.WaitAsync(token);
    }
}

sealed class GatedContent(byte[] body,BodyBarrier barrier):HttpContent
{
    protected override bool TryComputeLength(out long length){length=body.Length;return true;}
    protected override Task SerializeToStreamAsync(Stream stream,TransportContext? context)=>Write(stream,CancellationToken.None);
    protected override Task SerializeToStreamAsync(Stream stream,TransportContext? context,CancellationToken token)=>Write(stream,token);
    private async Task Write(Stream stream,CancellationToken token)
    {
        await barrier.Enter(token);
        await stream.WriteAsync(body,token);
    }
}
