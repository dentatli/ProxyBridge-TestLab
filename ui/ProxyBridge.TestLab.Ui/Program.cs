using System.Net;
using System.Text.Json;
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
builder.Services.AddSingleton<IRunCatalogProvider>(services => services.GetRequiredService<CatalogService>());
builder.Services.AddSingleton<RunReportService>();
builder.Services.AddSingleton<DpapiSecretProtector>();
builder.Services.AddSingleton<ProtocolCertificateStore>();
builder.Services.AddSingleton<ServerProtocolPortCatalog>();
builder.Services.AddSingleton<LocalArtifactService>();
builder.Services.AddSingleton<LocalReceiverService>();
builder.Services.AddHostedService(services => services.GetRequiredService<LocalReceiverService>());
builder.Services.AddSingleton<ILocalRuntimeStatusProvider>(services => services.GetRequiredService<LocalArtifactService>());
builder.Services.AddSingleton<SettingsStore>();
builder.Services.AddSingleton<IRunSettingsProvider>(services => services.GetRequiredService<SettingsStore>());
builder.Services.AddSingleton<RunnerEnvironmentService>();
builder.Services.AddSingleton<RequestTokenService>();
builder.Services.AddSingleton<BenchmarkLabService>();
builder.Services.AddSingleton<BenchmarkBuildCatalog>();
builder.Services.AddSingleton<BenchmarkLaunchPlanService>();
builder.Services.AddSingleton<RuntimeExecutionLease>();
builder.Services.AddSingleton<ServerTrustStore>();
builder.Services.AddSingleton<ServerReceiptStore>();
builder.Services.AddSingleton<ServerArtifactBuilder>();
builder.Services.AddSingleton<IServerTransport, OpenSshServerTransport>();
builder.Services.AddSingleton<ServerProvisioningService>();
builder.Services.AddSingleton<RuntimeCapabilityService>();
builder.Services.AddSingleton<IRuntimeCapabilityService>(services => services.GetRequiredService<RuntimeCapabilityService>());
builder.Services.AddSingleton<RunCapabilityFileService>();
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
builder.Services.AddSingleton<BenchmarkRunService>();
builder.Services.AddHostedService(serviceProvider => serviceProvider.GetRequiredService<BenchmarkRunService>());
builder.Services.Configure<HostOptions>(options => options.ShutdownTimeout = TimeSpan.FromMinutes(3));

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

api.MapGet("/lab/state", async (BenchmarkLabService lab, BenchmarkBuildCatalog builds, BenchmarkRunService runs, RequestTokenService tokens, CancellationToken cancellationToken) =>
    Results.Ok(new { csrf_token = tokens.Token, selection = await lab.GetSelectionAsync(cancellationToken), builds = await builds.PublicAsync(cancellationToken), reports = lab.GetReports(), local_runs = lab.GetLocalRttReports(), local_transfers = lab.GetLocalTransferReports(), local_connections = lab.GetLocalConnectionReports(), launch_history = lab.GetLaunchAttempts(), run_control = runs.State() }));

api.MapPost("/lab/build/select", async (BenchmarkBuildRequest request, BenchmarkBuildCatalog builds, BenchmarkLabService lab, BenchmarkRunService runs, CancellationToken token) =>
{
    try
    {
        if (runs.HasActiveRun) return Results.BadRequest(new { error = "REAL_RUN_ALREADY_ACTIVE" });
        return Results.Ok(await lab.SelectAsync(await builds.RequestAsync(request.BuildId, token), token));
    }
    catch (Exception error) when (error is InvalidOperationException or JsonException or IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or OperationCanceledException or ArgumentException or FormatException or KeyNotFoundException)
    { return Results.BadRequest(new { error = "BUILD_SELECTION_FAILED" }); }
});

api.MapPost("/lab/build/rename", async (BenchmarkBuildRenameRequest request, BenchmarkBuildCatalog builds, CancellationToken token) =>
{
    try { await builds.RenameAsync(request.BuildId, request.DisplayName, token); return Results.Ok(new { status = "BUILD_RENAMED" }); }
    catch (Exception error) when (error is InvalidOperationException or JsonException or IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or OperationCanceledException or ArgumentException)
    { return Results.BadRequest(new { error = "BUILD_RENAME_FAILED" }); }
});

api.MapGet("/lab/run", (BenchmarkRunService runs) => Results.Ok(runs.State()));
api.MapGet("/lab/history", (int offset, BenchmarkLabService lab) =>
    offset is >= 0 and <= 1000000 ? Results.Ok(lab.GetLaunchAttempts(offset)) : Results.BadRequest(new { error = "HISTORY_OFFSET_INVALID" }));
api.MapGet("/lab/history/{id}", (string id, BenchmarkLabService lab) =>
{
    if (!System.Text.RegularExpressions.Regex.IsMatch(id, "^(lab-tcp_(rtt|rtt_three_modes|transfer|connections)-smoke-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}|tcp-rtt-three-modes-smoke-[0-9]{8}-[0-9]{6}-[a-f0-9]{6})$"))
        return Results.BadRequest(new { error = "HISTORY_ID_INVALID" });
    return Results.Ok(id.StartsWith("lab-tcp_connections-", StringComparison.Ordinal) ? lab.GetLocalConnectionReports(id) : id.StartsWith("lab-tcp_transfer-", StringComparison.Ordinal) ? lab.GetLocalTransferReports(id) : lab.GetLocalRttReports(id));
});
api.MapPost("/lab/run/start", async (BenchmarkStartRequest request, BenchmarkRunService runs, CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await runs.LaunchAsync(request.PlanId, cancellationToken)); }
    catch (InvalidOperationException error)
    {
        var allowed = new[] { "INVALID_PLAN", "ADMINISTRATOR_REQUIRED", "REAL_RUN_ALREADY_ACTIVE", "AUTOMATIC_SCENARIO_PENDING", "SELECTION_REQUIRED", "SELECTION_CHANGED_PREPARE_AGAIN", "PLAN_ALREADY_USED_PREPARE_AGAIN" };
        return Results.BadRequest(new { error = allowed.Contains(error.Message) ? error.Message : "GUI_RUN_NOT_STARTED" });
    }
    catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or System.ComponentModel.Win32Exception or OperationCanceledException or KeyNotFoundException or ArgumentException)
    { return Results.BadRequest(new { error = "GUI_RUN_NOT_STARTED" }); }
});
api.MapPost("/lab/run/stop", async (BenchmarkStartRequest request, BenchmarkRunService runs, CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await runs.RequestStopAsync(cancellationToken, request.PlanId)); }
    catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException or OperationCanceledException)
    { return Results.BadRequest(new { error = "GUI_STOP_NOT_QUEUED" }); }
});

api.MapPost("/lab/inspect", async (ProductSelectionRequest request, BenchmarkLabService lab, CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await lab.InspectAsync(request, cancellationToken)); }
    catch (Exception error) when (error is InvalidOperationException or JsonException or IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or OperationCanceledException)
    { return Results.BadRequest(new { error = "PRODUCT_FILES_INSPECTION_FAILED" }); }
});

api.MapPost("/lab/select", async (ProductSelectionRequest request, BenchmarkLabService lab, CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await lab.SelectAsync(request, cancellationToken)); }
    catch (Exception error) when (error is InvalidOperationException or JsonException or IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or OperationCanceledException)
    { return Results.BadRequest(new { error = "PRODUCT_SELECTION_NOT_SAVED" }); }
});

api.MapPost("/lab/prepare", async (BenchmarkPlanRequest request, BenchmarkLaunchPlanService service, CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await service.PrepareAsync(request, cancellationToken)); }
    catch (Exception error) when (error is InvalidOperationException or JsonException or IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or OperationCanceledException)
    { return Results.BadRequest(new { error = "BENCHMARK_PLAN_NOT_PREPARED" }); }
});

api.MapPost("/lab/suite/prepare", async (BenchmarkSuiteRequest request, BenchmarkLaunchPlanService service, BenchmarkRunService runs, CancellationToken token) =>
{
    try
    {
        if (runs.HasActiveRun) return Results.BadRequest(new { error = "REAL_RUN_ALREADY_ACTIVE" });
        return Results.Ok(await service.PrepareSuiteAsync(request, token));
    }
    catch (Exception error) when (error is InvalidOperationException or JsonException or IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or OperationCanceledException)
    { return Results.BadRequest(new { error = "BENCHMARK_PLAN_NOT_PREPARED" }); }
});
api.MapPost("/lab/suite/start", async (BenchmarkStartRequest request, BenchmarkRunService runs, CancellationToken token) =>
{
    try { return Results.Ok(await runs.LaunchSuiteAsync(request.PlanId, token)); }
    catch (InvalidOperationException error)
    {
        var allowed = new[] { "INVALID_PLAN", "ADMINISTRATOR_REQUIRED", "REAL_RUN_ALREADY_ACTIVE", "PLAN_ALREADY_USED_PREPARE_AGAIN" };
        return Results.BadRequest(new { error = allowed.Contains(error.Message) ? error.Message : "SUITE_LAUNCH_NOT_CONFIRMED" });
    }
    catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or OperationCanceledException or KeyNotFoundException or ArgumentException)
    { return Results.BadRequest(new { error = "SUITE_LAUNCH_NOT_CONFIRMED" }); }
});
api.MapPost("/lab/suite/stop", async (BenchmarkStartRequest request, BenchmarkRunService runs, CancellationToken token) =>
{
    try { return Results.Ok(await runs.RequestSuiteStopAsync(request.PlanId, token)); }
    catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException or OperationCanceledException)
    { return Results.BadRequest(new { error = "GUI_STOP_NOT_QUEUED" }); }
});

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

api.MapGet("/local-receiver/status", (LocalReceiverService service) => Results.Ok(new
{
    receiver = service.GetStatus(),
    lastEvidence = service.GetLastEvidence()
}));

api.MapPost("/local-receiver/start", async (LocalReceiverService service, CancellationToken cancellationToken) =>
{
    try { return Results.Ok(await service.StartReceiverAsync(cancellationToken)); }
    catch (InvalidOperationException exception) { return Results.BadRequest(new { error = exception.Message }); }
});

api.MapPost("/local-receiver/stop", async (LocalReceiverService service, CancellationToken cancellationToken) =>
    Results.Ok(new { evidence = await service.StopReceiverAsync(cancellationToken) }));

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
    BenchmarkRunService labRuns,
    CancellationToken cancellationToken) =>
{
    if (request.Mode == "real" && labRuns.HasActiveRun) return Results.BadRequest(new { error = "REAL_RUN_ALREADY_ACTIVE" });
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
