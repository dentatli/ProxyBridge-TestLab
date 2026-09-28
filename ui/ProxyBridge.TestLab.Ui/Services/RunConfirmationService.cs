using System.Security.Cryptography;
using System.Text;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class RunConfirmationService
{
    private readonly object _gate = new();
    private readonly Dictionary<string, PendingConfirmation> _pending = new(StringComparer.Ordinal);

    public (string Nonce, DateTimeOffset ExpiresUtc) Issue(string mode, IReadOnlyList<string> scenarioIds)
    {
        var now = DateTimeOffset.UtcNow;
        var nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(24)).ToLowerInvariant();
        var expires = now.AddMinutes(2);
        var digest = ComputeDigest(mode, scenarioIds);
        lock (_gate)
        {
            RemoveExpiredUnsafe(now);
            _pending[nonce] = new PendingConfirmation(digest, expires);
        }
        return (nonce, expires);
    }

    public bool Consume(string? nonce, string mode, IReadOnlyList<string> scenarioIds)
    {
        if (string.IsNullOrWhiteSpace(nonce)) return false;
        lock (_gate)
        {
            var now = DateTimeOffset.UtcNow;
            RemoveExpiredUnsafe(now);
            if (!_pending.Remove(nonce, out var pending) || pending.ExpiresUtc <= now) return false;
            return CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(pending.Digest),
                Encoding.UTF8.GetBytes(ComputeDigest(mode, scenarioIds)));
        }
    }

    private static string ComputeDigest(string mode, IReadOnlyList<string> scenarioIds)
    {
        var canonical = mode.Trim().ToLowerInvariant() + "\n" + string.Join("\n", scenarioIds.Order(StringComparer.OrdinalIgnoreCase));
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonical))).ToLowerInvariant();
    }

    private void RemoveExpiredUnsafe(DateTimeOffset now)
    {
        foreach (var key in _pending.Where(item => item.Value.ExpiresUtc <= now).Select(item => item.Key).ToArray())
            _pending.Remove(key);
    }

    private sealed record PendingConfirmation(string Digest, DateTimeOffset ExpiresUtc);
}
