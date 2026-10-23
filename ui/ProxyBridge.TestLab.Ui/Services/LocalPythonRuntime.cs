namespace ProxyBridge.TestLab.Ui.Services;

internal static class LocalPythonRuntime
{
    public static string Resolve(string root)
    {
        var bundled = Path.Combine(root, "bin", "runtime", "python", "python.exe");
        if (File.Exists(bundled)) return bundled;
        var development = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Python", "Python311", "python.exe");
        if (File.Exists(development)) return development;
        throw new InvalidOperationException("TRAFFIC_PYTHON_311_REQUIRED");
    }
}
