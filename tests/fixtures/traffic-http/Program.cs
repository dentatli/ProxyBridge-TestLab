using System.IO.Compression;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;

// Explicit SDK component fixture: no runtime secret, OS proxy or trust-store modification.
using var input=JsonDocument.Parse(await Console.In.ReadToEndAsync());
var data=input.RootElement;
var host=IPAddress.Parse(data.GetProperty("host").GetString()!);
var port=data.GetProperty("port").GetInt32();
var secure=data.GetProperty("secure").GetBoolean();
var chunked=data.GetProperty("chunked").GetBoolean();
var compressed=data.GetProperty("compressed").GetBoolean();
var message=Convert.FromBase64String(data.GetProperty("message").GetString()!);
if(host.AddressFamily!=AddressFamily.InterNetwork||port<1024||port>65535||message.Length<1||message.Length>8192)
    throw new InvalidOperationException("Invalid component fixture");
using var cancellation=new CancellationTokenSource(TimeSpan.FromSeconds(10));
using var handler=new SocketsHttpHandler {UseProxy=false};
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
    using var ca=X509Certificate2.CreateFromPem(data.GetProperty("tls_ca_pem").GetString()!);
    using var chain=new X509Chain();
    chain.ChainPolicy.TrustMode=X509ChainTrustMode.CustomRootTrust;
    chain.ChainPolicy.CustomTrustStore.Add(ca);
    chain.ChainPolicy.RevocationMode=X509RevocationMode.NoCheck;
    handler.SslOptions.RemoteCertificateValidationCallback=(_,certificate,_,errors)=>
    {
        if(certificate is not X509Certificate2 leaf||(errors&~SslPolicyErrors.RemoteCertificateChainErrors)!=SslPolicyErrors.None)
            return false;
        pinVerified=Convert.ToHexString(SHA256.HashData(leaf.RawData)).Equals(pin,StringComparison.OrdinalIgnoreCase)&&chain.Build(leaf);
        return pinVerified;
    };
    await Exchange();
}
else await Exchange();

async Task Exchange()
{
    using var client=new HttpClient(handler,false);
    byte[] body=message;
    if(compressed)
    {
        using var encoded=new MemoryStream();
        using(var gzip=new GZipStream(encoded,CompressionLevel.SmallestSize,true))gzip.Write(message);
        body=encoded.ToArray();
    }
    using var request=new HttpRequestMessage(HttpMethod.Post,$"{(secure?"https":"http")}://traffic.testlab.invalid:{port}/testlab")
    {Content=new ByteArrayContent(body),Version=HttpVersion.Version11,VersionPolicy=HttpVersionPolicy.RequestVersionExact};
    request.Content.Headers.ContentType=new MediaTypeHeaderValue("application/json");
    request.Headers.AcceptEncoding.Add(new StringWithQualityHeaderValue("gzip"));
    if(compressed)request.Content.Headers.ContentEncoding.Add("gzip");
    if(chunked)request.Headers.TransferEncodingChunked=true;
    using var response=await client.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,cancellation.Token);
    if(response.StatusCode!=HttpStatusCode.OK||(response.Headers.TransferEncodingChunked==true)!=chunked||
       response.Content.Headers.ContentEncoding.Contains("gzip")!=compressed||secure&&!pinVerified)
        throw new InvalidOperationException("SDK response framing or identity mismatch");
    using var stream=await response.Content.ReadAsStreamAsync(cancellation.Token);
    using var decoded=compressed?new GZipStream(stream,CompressionMode.Decompress,true):null;
    var source=(Stream?)decoded??stream;
    using var received=new MemoryStream();var buffer=new byte[512];
    while(true)
    {
        var count=await source.ReadAsync(buffer,cancellation.Token);
        if(count==0)break;
        if(received.Length+count>8192)throw new InvalidOperationException("SDK decoded body limit");
        received.Write(buffer,0,count);
    }
    Console.WriteLine(JsonSerializer.Serialize(new {response=Convert.ToBase64String(received.ToArray()),
        chunked,gzip=compressed,tls_pin_verified=pinVerified}));
}
