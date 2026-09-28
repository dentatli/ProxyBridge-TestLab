using System.Security.Cryptography;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class RequestTokenService
{
    private readonly byte[] _tokenBytes;

    public RequestTokenService()
    {
        _tokenBytes = RandomNumberGenerator.GetBytes(32);
        Token = Convert.ToBase64String(_tokenBytes);
    }

    public string Token { get; }

    public bool IsValid(string? candidate)
    {
        if (string.IsNullOrWhiteSpace(candidate)) return false;
        byte[] candidateBytes;
        try { candidateBytes = Convert.FromBase64String(candidate); }
        catch (FormatException) { return false; }
        try { return candidateBytes.Length == _tokenBytes.Length && CryptographicOperations.FixedTimeEquals(candidateBytes, _tokenBytes); }
        finally { CryptographicOperations.ZeroMemory(candidateBytes); }
    }
}
