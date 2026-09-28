using System.Text.Json;
using System.Text.RegularExpressions;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed record ServerPluginDefinition(
    string Id,
    string ImplementationStatus,
    int Milestone,
    IReadOnlyList<string> Artifacts,
    IReadOnlyList<string> Capabilities);

public sealed class ServerPluginCatalog
{
    private static readonly Regex SafeId = new("^[a-z0-9][a-z0-9._-]{0,63}$", RegexOptions.CultureInvariant);
    private static readonly Regex SafeRelativePath = new("^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$", RegexOptions.CultureInvariant);

    private ServerPluginCatalog(IReadOnlyList<ServerPluginDefinition> plugins) => Plugins = plugins;

    public IReadOnlyList<ServerPluginDefinition> Plugins { get; }
    public IReadOnlyList<ServerPluginDefinition> Implemented => Plugins.Where(plugin => plugin.ImplementationStatus == "IMPLEMENTED").ToArray();

    public static ServerPluginCatalog Load(byte[] json)
    {
        using var document = JsonDocument.Parse(json, new JsonDocumentOptions { AllowTrailingCommas = false, CommentHandling = JsonCommentHandling.Disallow });
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("schema_version", out var schema) || schema.GetInt32() != 1)
            throw new InvalidOperationException("SERVER_PLUGIN_CATALOG_SCHEMA_UNSUPPORTED");
        if (!root.TryGetProperty("plugins", out var pluginsElement) || pluginsElement.ValueKind != JsonValueKind.Array)
            throw new InvalidOperationException("SERVER_PLUGIN_CATALOG_INCOMPLETE");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var plugins = new List<ServerPluginDefinition>();
        foreach (var element in pluginsElement.EnumerateArray())
        {
            if (element.ValueKind != JsonValueKind.Object) throw new InvalidOperationException("SERVER_PLUGIN_ENTRY_INVALID");
            var id = RequiredString(element, "id");
            if (!SafeId.IsMatch(id) || !ids.Add(id)) throw new InvalidOperationException("SERVER_PLUGIN_ID_INVALID_OR_DUPLICATE");
            var status = RequiredString(element, "implementation_status");
            if (status is not ("IMPLEMENTED" or "PLANNED")) throw new InvalidOperationException("SERVER_PLUGIN_STATUS_INVALID");
            var milestone = element.GetProperty("milestone").GetInt32();
            if (milestone is < 0 or > 20) throw new InvalidOperationException("SERVER_PLUGIN_MILESTONE_INVALID");
            var artifacts = StringArray(element, "artifacts");
            var capabilities = StringArray(element, "capabilities");
            if (capabilities.Count == 0 || capabilities.Any(value => !SafeId.IsMatch(value))) throw new InvalidOperationException("SERVER_PLUGIN_CAPABILITY_INVALID");
            if (artifacts.Any(value => !SafeRelativePath.IsMatch(value)) || artifacts.Distinct(StringComparer.Ordinal).Count() != artifacts.Count)
                throw new InvalidOperationException("SERVER_PLUGIN_ARTIFACT_PATH_INVALID");
            if (status == "IMPLEMENTED" && artifacts.Count == 0) throw new InvalidOperationException("SERVER_PLUGIN_IMPLEMENTED_ARTIFACT_MISSING");
            if (status == "PLANNED" && artifacts.Count != 0) throw new InvalidOperationException("SERVER_PLUGIN_PLANNED_ARTIFACT_FORBIDDEN");
            plugins.Add(new ServerPluginDefinition(id, status, milestone, artifacts, capabilities));
        }
        if (!plugins.Any(plugin => plugin.Id == "endpoint-core" && plugin.ImplementationStatus == "IMPLEMENTED"))
            throw new InvalidOperationException("SERVER_PLUGIN_ENDPOINT_CORE_MISSING");
        return new ServerPluginCatalog(plugins);
    }

    public byte[] BuildInstalledManifest(IReadOnlyDictionary<string, string> runtimeHashes)
    {
        foreach (var plugin in Implemented)
            foreach (var artifact in plugin.Artifacts)
                if (!runtimeHashes.ContainsKey(artifact)) throw new InvalidOperationException("SERVER_PLUGIN_RUNTIME_ARTIFACT_MISSING");
        var value = new
        {
            schema_version = 1,
            agent_contract_version = 1,
            artifacts = runtimeHashes.OrderBy(item => item.Key, StringComparer.Ordinal).Select(item => new { path = item.Key, sha256 = item.Value }).ToArray(),
            plugins = Implemented.OrderBy(plugin => plugin.Id, StringComparer.Ordinal).Select(plugin => new
            {
                id = plugin.Id,
                implementation_status = plugin.ImplementationStatus,
                milestone = plugin.Milestone,
                artifacts = plugin.Artifacts,
                capabilities = plugin.Capabilities
            }).ToArray()
        };
        return JsonSerializer.SerializeToUtf8Bytes(value, new JsonSerializerOptions { WriteIndented = true });
    }

    private static string RequiredString(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var property) || property.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(property.GetString()))
            throw new InvalidOperationException("SERVER_PLUGIN_PROPERTY_MISSING");
        return property.GetString()!;
    }

    private static IReadOnlyList<string> StringArray(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var property) || property.ValueKind != JsonValueKind.Array)
            throw new InvalidOperationException("SERVER_PLUGIN_PROPERTY_MISSING");
        var values = new List<string>();
        foreach (var value in property.EnumerateArray())
        {
            if (value.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(value.GetString())) throw new InvalidOperationException("SERVER_PLUGIN_ARRAY_VALUE_INVALID");
            values.Add(value.GetString()!);
        }
        return values;
    }
}
