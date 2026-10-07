namespace ProxyBridge.TestLab.Ui.Services;

/// <summary>Shared with Invoke-PlannedBenchmark.ps1; coordinates real runners in this checkout.</summary>
public sealed class RuntimeExecutionLease(AppPaths paths)
{
    public FileStream Acquire()
    {
        var root = Path.Combine(paths.RepositoryRoot, "artifacts", "benchmark-launch");
        for (var current = root; current is not null; current = Path.GetDirectoryName(current))
            if (Directory.Exists(current) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("RUNTIME_LEASE_REPARSE_POINT");
        Directory.CreateDirectory(root);
        var file = Path.Combine(root, "execution.lock");
        if (File.Exists(file) && (File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidOperationException("RUNTIME_LEASE_REPARSE_POINT");
        return new FileStream(file, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }
}
