using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record ProtocolCertificateBundle(
    byte[] CaCertificatePem,
    byte[] ServerCertificateChainPem,
    byte[] ServerPrivateKeyPem,
    string CaCertificateSha256,
    string ServerCertificateSha256);

public sealed class ProtocolCertificateStore(AppStoragePaths paths, DpapiSecretProtector protector)
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private readonly object _gate = new();

    public ProtocolCertificateBundle GetOrCreate()
    {
        lock (_gate)
        {
            paths.EnsureSecureDirectories();
            X509Certificate2 serverCertificate;
            X509Certificate2 caCertificate;
            if (File.Exists(paths.ProtocolCertificatePath) && File.Exists(paths.ProtocolCaPath))
            {
                var protectedPfx = Convert.FromBase64String(File.ReadAllText(paths.ProtocolCertificatePath, Encoding.UTF8).Trim());
                try
                {
                    var envelope = protector.Unprotect(protectedPfx);
                    try { serverCertificate = LoadServerCertificate(envelope); }
                    finally { CryptographicOperations.ZeroMemory(envelope); }
                }
                finally { CryptographicOperations.ZeroMemory(protectedPfx); }
                caCertificate = X509CertificateLoader.LoadCertificate(File.ReadAllBytes(paths.ProtocolCaPath));
                Validate(serverCertificate, caCertificate);
            }
            else
            {
                (serverCertificate, caCertificate) = Create();
                Persist(serverCertificate, caCertificate);
            }

            using (serverCertificate)
            using (caCertificate)
            using (var privateKey = serverCertificate.GetRSAPrivateKey() ?? throw new InvalidOperationException("PROTOCOL_SERVER_PRIVATE_KEY_MISSING"))
            {
                var caBlock = PemEncoding.WriteString("CERTIFICATE", caCertificate.RawData);
                var serverBlock = PemEncoding.WriteString("CERTIFICATE", serverCertificate.RawData);
                var caPem = Utf8NoBom.GetBytes(caBlock + "\n");
                var serverPem = Utf8NoBom.GetBytes(serverBlock + "\n" + caBlock + "\n");
                EnsurePublicCaPem(caPem);
                var privateKeyBytes = privateKey.ExportPkcs8PrivateKey();
                try
                {
                    var keyPem = Utf8NoBom.GetBytes(PemEncoding.WriteString("PRIVATE KEY", privateKeyBytes) + "\n");
                    return new ProtocolCertificateBundle(caPem, serverPem, keyPem,
                        Convert.ToHexString(SHA256.HashData(caCertificate.RawData)).ToLowerInvariant(),
                        Convert.ToHexString(SHA256.HashData(serverCertificate.RawData)).ToLowerInvariant());
                }
                finally { CryptographicOperations.ZeroMemory(privateKeyBytes); }
            }
        }
    }

    private void Persist(X509Certificate2 serverCertificate, X509Certificate2 caCertificate)
    {
        using var privateKey = serverCertificate.GetRSAPrivateKey() ?? throw new InvalidOperationException("PROTOCOL_SERVER_PRIVATE_KEY_MISSING");
        var privateKeyBytes = privateKey.ExportPkcs8PrivateKey();
        byte[] envelope;
        try
        {
            using var stream = new MemoryStream();
            using (var writer = new Utf8JsonWriter(stream))
            {
                writer.WriteStartObject();
                writer.WriteNumber("schema_version", 1);
                writer.WriteBase64String("certificate_der", serverCertificate.RawData);
                writer.WriteBase64String("private_key_pkcs8", privateKeyBytes);
                writer.WriteEndObject();
            }
            envelope = stream.ToArray();
            if (stream.TryGetBuffer(out var buffer)) CryptographicOperations.ZeroMemory(buffer.AsSpan(0, checked((int)stream.Length)));
        }
        finally { CryptographicOperations.ZeroMemory(privateKeyBytes); }
        try
        {
            var protectedEnvelope = protector.Protect(envelope);
            try { WriteAtomic(paths.ProtocolCertificatePath, Convert.ToBase64String(protectedEnvelope) + Environment.NewLine); }
            finally { CryptographicOperations.ZeroMemory(protectedEnvelope); }
        }
        finally { CryptographicOperations.ZeroMemory(envelope); }
        WriteAtomicBytes(paths.ProtocolCaPath, caCertificate.RawData);
    }

    private void EnsurePublicCaPem(byte[] caPem)
    {
        if (File.Exists(paths.ProtocolCaPemPath) && File.ReadAllBytes(paths.ProtocolCaPemPath).AsSpan().SequenceEqual(caPem)) return;
        WriteAtomicBytes(paths.ProtocolCaPemPath, caPem);
    }

    private static X509Certificate2 LoadServerCertificate(byte[] envelope)
    {
        byte[]? certificateBytes = null;
        byte[]? privateKeyBytes = null;
        try
        {
            using var document = JsonDocument.Parse(envelope);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("schema_version", out var schema) || schema.GetInt32() != 1)
                throw new InvalidOperationException("PROTOCOL_CERTIFICATE_STORE_SCHEMA_UNSUPPORTED");
            certificateBytes = root.GetProperty("certificate_der").GetBytesFromBase64();
            privateKeyBytes = root.GetProperty("private_key_pkcs8").GetBytesFromBase64();
            using var publicCertificate = X509CertificateLoader.LoadCertificate(certificateBytes);
            using var key = RSA.Create();
            key.ImportPkcs8PrivateKey(privateKeyBytes, out var bytesRead);
            if (bytesRead != privateKeyBytes.Length) throw new InvalidOperationException("PROTOCOL_CERTIFICATE_STORE_INVALID");
            return publicCertificate.CopyWithPrivateKey(key);
        }
        catch (Exception exception) when (exception is JsonException or FormatException or CryptographicException or InvalidOperationException)
        {
            throw new InvalidOperationException("PROTOCOL_CERTIFICATE_STORE_INVALID", exception);
        }
        finally
        {
            if (certificateBytes is not null) CryptographicOperations.ZeroMemory(certificateBytes);
            if (privateKeyBytes is not null) CryptographicOperations.ZeroMemory(privateKeyBytes);
        }
    }

    private static (X509Certificate2 Server, X509Certificate2 Ca) Create()
    {
        var now = DateTimeOffset.UtcNow;
        using var caKey = RSA.Create(3072);
        var caRequest = new CertificateRequest("CN=ProxyBridge TestLab Local Protocol CA", caKey, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        caRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        caRequest.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign, true));
        caRequest.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(caRequest.PublicKey, false));
        using var temporaryCa = caRequest.CreateSelfSigned(now.AddMinutes(-5), now.AddYears(5));

        using var serverKey = RSA.Create(2048);
        var serverRequest = new CertificateRequest("CN=proxybridge-testlab.test", serverKey, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        serverRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        serverRequest.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment, true));
        serverRequest.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection { new("1.3.6.1.5.5.7.3.1") }, true));
        var san = new SubjectAlternativeNameBuilder();
        san.AddDnsName("proxybridge-testlab.test");
        san.AddIpAddress(IPAddress.Loopback);
        san.AddIpAddress(IPAddress.IPv6Loopback);
        serverRequest.CertificateExtensions.Add(san.Build());
        serverRequest.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(serverRequest.PublicKey, false));
        var serial = RandomNumberGenerator.GetBytes(16);
        try
        {
            using var publicServer = serverRequest.Create(temporaryCa, now.AddMinutes(-5), now.AddYears(2), serial);
            var publicCa = X509CertificateLoader.LoadCertificate(temporaryCa.RawData);
            return (publicServer.CopyWithPrivateKey(serverKey), publicCa);
        }
        finally { CryptographicOperations.ZeroMemory(serial); }
    }

    private static void Validate(X509Certificate2 server, X509Certificate2 ca)
    {
        if (!server.HasPrivateKey || server.NotAfter.ToUniversalTime() <= DateTime.UtcNow.AddDays(30) || ca.NotAfter.ToUniversalTime() <= DateTime.UtcNow.AddDays(30))
            throw new InvalidOperationException("PROTOCOL_CERTIFICATE_MATERIAL_INVALID");
        using var chain = new X509Chain();
        chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
        chain.ChainPolicy.CustomTrustStore.Add(ca);
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
        if (!chain.Build(server)) throw new InvalidOperationException("PROTOCOL_CERTIFICATE_CHAIN_INVALID");
    }

    private static void WriteAtomic(string path, string value)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, value, Utf8NoBom); File.Move(temporary, path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private static void WriteAtomicBytes(string path, byte[] value)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllBytes(temporary, value); File.Move(temporary, path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
