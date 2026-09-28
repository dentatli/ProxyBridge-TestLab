using System.Net;
using ProxyBridge.TestLab.Ui.Hubs;
using ProxyBridge.TestLab.Ui.Models;
using ProxyBridge.TestLab.Ui.Services;

var builder = WebApplication.CreateBuilder(args);
var requestedRoot = builder.Configuration["RepositoryRoot"];
var paths = new AppPaths(AppPaths.Discover(requestedRoot));
var requestedStorageRoot = builder.Configuration["ConfigRoot"];
var storagePaths = new AppStoragePaths(string.IsNullOrWhiteSpace(requestedStorageRoot)
    ? AppStoragePaths.GetDefaultRoot()
    : requestedStorageRoot);
storagePaths.ScavengeStaleRuntimeDirectories();

builder.WebHost.UseUrls("http://127.0.0.1:5178");
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 64 * 1024);
builder.Services.AddSingleton(paths);
builder.Services.AddSingleton(storagePaths);
builder.Services.AddSingleton<CatalogService>();
builder.Services.AddSingleton<RunReportService>();
builder.Services.AddSingleton<DpapiSecretProtector>();
builder.Services.AddSingleton<ProtocolCertificateStore>();
builder.Services.AddSingleton<ServerProtocolPortCatalog>();
builder.Services.AddSingleton<LocalArtifactService>();
builder.Services.AddSingleton<SettingsStore>();
builder.Services.AddSingleton<RunnerEnvironmentService>();
builder.Services.AddSingleton<RequestTokenService>();
builder.Services.AddSingleton<ServerTrustStore>();
builder.Services.AddSingleton<ServerReceiptStore>();
builder.Services.AddSingleton<ServerArtifactBuilder>();
builder.Services.AddSingleton<IServerTransport, OpenSshServerTransport>();
builder.Services.AddSingleton<ServerProvisioningService>();
builder.Services.AddSingleton<ServerProtocolSmokeService>();
builder.Services.AddSignalR();
builder.Services.AddSingleton<RunConfirmationService>();
builder.Services.AddSingleton<IRunImmutablePreflightService, PowerShellImmutablePreflightService>();
builder.Services.AddSingleton<IRunReadinessService, RunReadinessService>();
builder.Services.AddSingleton<IRunExecutor, PowerShellRunExecutor>();
builder.Services.AddSingleton<RunJobStore>();
builder.Services.AddSingleton<IRunEventPublisher, SignalRRunEventPublisher>();
builder.Services.AddSingleton<RunCoordinator>();
builder.Services.AddHostedService(serviceProvider => serviceProvider.GetRequiredService<RunCoordinator>());

var app = builder.Build();

app.Use(async (context, next) =>
{
    var remoteAddress = context.Connection.RemoteIpAddress;
    if (remoteAddress is not null && !IPAddress.IsLoopback(remoteAddress))
    {
        context.Response.StatusCode = StatusCodes.Status403Forbidden;
        return;
    }

    var allowedHosts = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "127.0.0.1",
        "localhost",
        "[::1]",
        "::1"
    };
    if (!allowedHosts.Contains(context.Request.Host.Host))
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }

    if (context.Request.Path.StartsWithSegments("/api") &&
        !HttpMethods.IsGet(context.Request.Method) &&
        !HttpMethods.IsHead(context.Request.Method) &&
        !HttpMethods.IsOptions(context.Request.Method))
    {
        var expectedOrigin = $"{context.Request.Scheme}://{context.Request.Host}";
        var actualOrigin = context.Request.Headers.Origin.ToString();
        var tokenService = context.RequestServices.GetRequiredService<RequestTokenService>();
        if (!string.Equals(expectedOrigin, actualOrigin, StringComparison.OrdinalIgnoreCase) ||
            !tokenService.IsValid(context.Request.Headers["X-TestLab-CSRF"].ToString()))
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            return;
        }
    }

    context.Response.Headers.ContentSecurityPolicy =
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";
    context.Response.Headers.XContentTypeOptions = "nosniff";
    context.Response.Headers.XFrameOptions = "DENY";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    if (context.Request.Path.StartsWithSegments("/api"))
    {
        context.Response.Headers.CacheControl = "no-store";
    }

    await next();
});

app.UseDefaultFiles();
app.UseStaticFiles(new StaticFileOptions
{
    OnPrepareResponse = context => context.Context.Response.Headers.CacheControl = "no-cache"
});

var api = app.MapGroup("/api/v1");

api.MapGet("/system/status", async (
    CatalogService catalogService,
    RunReportService reportService,
    SettingsStore settingsStore,
    ServerProvisioningService serverProvisioning,
    RequestTokenService tokenService,
    CancellationToken cancellationToken) =>
{
    var catalog = await catalogService.GetAllAsync(cancellationToken);
    var runs = await reportService.ListAsync(cancellationToken);
    var settings = await settingsStore.GetViewAsync(cancellationToken);
    var serverStatus = await serverProvisioning.GetStatusAsync(cancellationToken);
    return Results.Ok(new
    {
        application = "ProxyBridge TestLab",
        milestone = 8,
        mode = "RELEASE_CANDIDATE",
        real_runtime_available = true,
        csrf_token = tokenService.Token,
        configuration = new
        {
            valid_for_save = settings.Validation.ValidForSave,
            complete = settings.Validation.Ready,
            readiness_issue_count = settings.Validation.ReadinessIssues.Count,
            updated_utc = settings.UpdatedUtc
        },
        server = serverStatus,
        catalog = new
        {
            declared = catalog.Count,
            executable = catalog.Count(item => item.ImplementationStatus == "EXECUTABLE"),
            declarative = catalog.Count(item => item.ImplementationStatus == "DECLARATIVE_ONLY"),
            system_checks = catalog.Count(item => item.ImplementationStatus == "SYSTEM_CHECK"),
            capability_gated = catalog.Count(item => item.ImplementationStatus == "CAPABILITY_GATED"),
            unsupported = catalog.Count(item => item.ImplementationStatus == "UNSUPPORTED_PRODUCT_SCOPE")
        },
        available_reports = runs.Count
    });
});

api.MapGet("/settings/schema", () => Results.Ok(SettingsSchema.Document));

api.MapGet("/settings", async (SettingsStore store, CancellationToken cancellationToken) =>
    Results.Ok(await store.GetViewAsync(cancellationToken)));

api.MapPost("/settings/validate", async (
    ProxyBridge.TestLab.Ui.Models.SettingsUpdateRequest request,
    SettingsStore store,
    CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await store.ValidateAsync(request, cancellationToken)); }
    catch (InvalidOperationException exception) when (exception.Message == "UNKNOWN_PROTECTED_FIELD")
    {
        return Results.BadRequest(new { error = "UNKNOWN_PROTECTED_FIELD" });
    }
});

api.MapPut("/settings", async (
    ProxyBridge.TestLab.Ui.Models.SettingsUpdateRequest request,
    SettingsStore store,
    CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await store.SaveAsync(request, cancellationToken)); }
    catch (SettingsValidationException exception)
    {
        return Results.BadRequest(new { error = exception.Message, validation = exception.Validation });
    }
    catch (InvalidOperationException exception) when (exception.Message == "UNKNOWN_PROTECTED_FIELD")
    {
        return Results.BadRequest(new { error = "UNKNOWN_PROTECTED_FIELD" });
    }
});

api.MapGet("/server/status", async (ServerProvisioningService service, CancellationToken cancellationToken) =>
    Results.Ok(await service.GetStatusAsync(cancellationToken)));

api.MapPost("/server/validate", async (
    ProxyBridge.TestLab.Ui.Models.ServerValidationRequest request,
    ServerProvisioningService service,
    CancellationToken cancellationToken) =>
    Results.Ok(await service.ValidateAsync(request, cancellationToken)));

api.MapPost("/server/plan", async (ServerProvisioningService service, CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await service.CreatePlanAsync(cancellationToken)); }
    catch (ServerOperationException exception) { return Results.BadRequest(new { error = exception.Message, detail = exception.Detail }); }
});

api.MapPost("/server/apply", async (
    ProxyBridge.TestLab.Ui.Models.ServerApplyRequest request,
    ServerProvisioningService service,
    CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await service.ApplyAsync(request, repair: false, cancellationToken)); }
    catch (ServerOperationException exception) { return Results.BadRequest(new { error = exception.Message }); }
});

api.MapPost("/server/repair", async (
    ProxyBridge.TestLab.Ui.Models.ServerApplyRequest request,
    ServerProvisioningService service,
    CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await service.ApplyAsync(request, repair: true, cancellationToken)); }
    catch (ServerOperationException exception) { return Results.BadRequest(new { error = exception.Message }); }
});

api.MapGet("/server/metrics", async (ServerProvisioningService service, CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await service.GetMetricsAsync(cancellationToken)); }
    catch (ServerOperationException exception) { return Results.BadRequest(new { error = exception.Message }); }
});

api.MapPost("/server/protocol-smoke", async (ServerProtocolSmokeService service, CancellationToken cancellationToken) =>
    Results.Ok(await service.RunAsync(cancellationToken)));

api.MapGet("/catalog", async (HttpRequest request, CatalogService catalogService, CancellationToken cancellationToken) =>
{
    IEnumerable<ProxyBridge.TestLab.Ui.Models.CatalogScenario> items = await catalogService.GetAllAsync(cancellationToken);
    var query = request.Query["q"].ToString();
    var protocol = request.Query["protocol"].ToString();
    var family = request.Query["family"].ToString();
    var action = request.Query["action"].ToString();
    var status = request.Query["status"].ToString();
    var group = request.Query["group"].ToString();

    if (!string.IsNullOrWhiteSpace(query))
    {
        items = items.Where(item =>
            item.ScenarioId.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            item.Title.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            item.Tags.Any(tag => tag.Contains(query, StringComparison.OrdinalIgnoreCase)));
    }
    if (!string.IsNullOrWhiteSpace(protocol)) items = items.Where(item => item.Protocol.Equals(protocol, StringComparison.OrdinalIgnoreCase));
    if (!string.IsNullOrWhiteSpace(family) && int.TryParse(family, out var familyNumber)) items = items.Where(item => item.Family == familyNumber);
    if (!string.IsNullOrWhiteSpace(action)) items = items.Where(item => item.Action.Equals(action, StringComparison.OrdinalIgnoreCase));
    if (!string.IsNullOrWhiteSpace(status)) items = items.Where(item => item.ImplementationStatus.Equals(status, StringComparison.OrdinalIgnoreCase));
    if (!string.IsNullOrWhiteSpace(group)) items = items.Where(item => item.CoverageGroup.Equals(group, StringComparison.OrdinalIgnoreCase));

    var result = items.ToArray();
    return Results.Ok(new { total = result.Length, items = result });
});

api.MapGet("/catalog/{scenarioId}", async (string scenarioId, CatalogService catalogService, CancellationToken cancellationToken) =>
{
    var item = (await catalogService.GetAllAsync(cancellationToken)).FirstOrDefault(candidate =>
        candidate.ScenarioId.Equals(scenarioId, StringComparison.OrdinalIgnoreCase));
    return item is null ? Results.NotFound() : Results.Ok(item);
});

api.MapPost("/runs/dry-run", async (
    RunCreateRequest request,
    RunCoordinator coordinator,
    CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await coordinator.PrepareAsync(request, cancellationToken)); }
    catch (InvalidOperationException exception) { return Results.BadRequest(new { error = exception.Message }); }
});

api.MapPost("/runs", async (
    RunCreateRequest request,
    RunCoordinator coordinator,
    CancellationToken cancellationToken) =>
{
    try { return Results.Accepted(value: await coordinator.QueueAsync(request, cancellationToken)); }
    catch (RunRequestException exception)
    {
        return Results.BadRequest(new { error = exception.Code, preparation = exception.Preparation });
    }
});

api.MapGet("/runs", async (RunCoordinator coordinator, RunReportService service, CancellationToken cancellationToken) =>
    Results.Ok(new { jobs = coordinator.List(), reports = await service.ListAsync(cancellationToken) }));

api.MapGet("/runs/{runId}", async (string runId, RunCoordinator coordinator, RunReportService service, CancellationToken cancellationToken) =>
{
    var job = coordinator.Get(runId);
    if (job is not null)
    {
        var report = string.IsNullOrWhiteSpace(job.EvidenceRunId) ? null : await service.GetAsync(job.EvidenceRunId, cancellationToken);
        return Results.Ok(new { job, run = report?.Run, results = report?.Results ?? [] });
    }
    var historical = await service.GetAsync(runId, cancellationToken);
    return historical is null ? Results.NotFound() : Results.Ok(new { job = (RunJobView?)null, run = historical.Value.Run, results = historical.Value.Results });
});

api.MapPost("/runs/{runId}/cancel", async (string runId, RunCoordinator coordinator, CancellationToken cancellationToken) =>
{
    var job = await coordinator.CancelAsync(runId, cancellationToken);
    return job is null ? Results.NotFound() : Results.Ok(job);
});

api.MapGet("/runs/{runId}/export", async (string runId, RunCoordinator coordinator, RunReportService service, CancellationToken cancellationToken) =>
{
    var job = coordinator.Get(runId);
    var reportRunId = job?.EvidenceRunId ?? runId;
    if (string.IsNullOrWhiteSpace(reportRunId)) return Results.NotFound();
    var export = await service.CreateAuditExportAsync(reportRunId, cancellationToken);
    return export is null
        ? Results.NotFound()
        : Results.File(export.Content, "application/zip", export.FileName, enableRangeProcessing: false);
});

api.MapGet("/runs/{runId}/scenarios/{scenarioId}", async (
    string runId,
    string scenarioId,
    RunCoordinator coordinator,
    RunReportService service,
    CancellationToken cancellationToken) =>
{
    var job = coordinator.Get(runId);
    var reportRunId = job?.EvidenceRunId ?? runId;
    if (string.IsNullOrWhiteSpace(reportRunId)) return Results.NotFound();
    var detail = await service.GetScenarioAsync(reportRunId, scenarioId, cancellationToken);
    return detail is null ? Results.NotFound() : Results.Ok(detail);
});

app.MapHub<RunHub>("/hubs/runs");

app.MapGet("/favicon.ico", () => Results.NoContent());

app.MapFallback(async context =>
{
    if (context.Request.Path.StartsWithSegments("/api"))
    {
        context.Response.StatusCode = StatusCodes.Status404NotFound;
        return;
    }

    context.Response.ContentType = "text/html; charset=utf-8";
    await context.Response.SendFileAsync(Path.Combine(app.Environment.WebRootPath, "index.html"));
});

app.Run();
