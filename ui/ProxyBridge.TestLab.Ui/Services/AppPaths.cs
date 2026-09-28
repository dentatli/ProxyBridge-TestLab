namespace ProxyBridge.TestLab.Ui.Services;

public sealed class AppPaths
{
    public AppPaths(string repositoryRoot)
    {
        RepositoryRoot = Path.GetFullPath(repositoryRoot);
        ScenarioRoot = Path.Combine(RepositoryRoot, "scenarios");
        KnownDefectsPath = Path.Combine(RepositoryRoot, "config", "known-defects.json");
        CatalogExportScript = Path.Combine(RepositoryRoot, "scripts", "Export-UiCatalog.ps1");
        RunnerPath = Path.Combine(RepositoryRoot, "Run-WfpMatrix.ps1");
        CapabilitiesPath = Path.Combine(RepositoryRoot, "config", "capabilities.json");
        ClientContractPath = Path.Combine(RepositoryRoot, "config", "client-contract.json");
        RuntimeConfigPath = Path.Combine(RepositoryRoot, "config", "runtime.json");
        MockSuitePath = Path.Combine(RepositoryRoot, "config", "suites", "mock-full.json");
        RealSuitePath = Path.Combine(RepositoryRoot, "config", "suites", "real-diagnostic-ipv4.json");
        MockFixtureRoot = Path.Combine(RepositoryRoot, "tests", "fixtures", "mock");
        FixtureEnvironmentPath = Path.Combine(RepositoryRoot, "tests", "fixtures", ".env.test");
        EvidenceRoots =
        [
            Path.Combine(RepositoryRoot, "evidence"),
            Path.Combine(RepositoryRoot, "tests", "fixtures", "ui-runs")
        ];
    }

    public string RepositoryRoot { get; }
    public string ScenarioRoot { get; }
    public string KnownDefectsPath { get; }
    public string CatalogExportScript { get; }
    public string RunnerPath { get; }
    public string CapabilitiesPath { get; }
    public string ClientContractPath { get; }
    public string RuntimeConfigPath { get; }
    public string MockSuitePath { get; }
    public string RealSuitePath { get; }
    public string MockFixtureRoot { get; }
    public string FixtureEnvironmentPath { get; }
    public IReadOnlyList<string> EvidenceRoots { get; }

    public static string Discover(string? requestedRoot)
    {
        if (!string.IsNullOrWhiteSpace(requestedRoot))
        {
            return Validate(requestedRoot);
        }

        foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
        {
            var current = new DirectoryInfo(start);
            while (current is not null)
            {
                if (File.Exists(Path.Combine(current.FullName, "Run-WfpMatrix.ps1")) &&
                    Directory.Exists(Path.Combine(current.FullName, "scenarios")))
                {
                    return current.FullName;
                }

                current = current.Parent;
            }
        }

        throw new InvalidOperationException("TESTLAB_REPOSITORY_ROOT_NOT_FOUND");
    }

    private static string Validate(string candidate)
    {
        var full = Path.GetFullPath(candidate);
        if (!File.Exists(Path.Combine(full, "Run-WfpMatrix.ps1")) ||
            !Directory.Exists(Path.Combine(full, "scenarios")))
        {
            throw new InvalidOperationException("TESTLAB_REPOSITORY_ROOT_INVALID");
        }

        return full;
    }
}
