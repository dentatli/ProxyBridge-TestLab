using System.Collections.Concurrent;
using Microsoft.Extensions.Hosting;
using ProxyBridge.TestLab.Ui.Hubs;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Services;

public sealed class RunCoordinator(
    IRunReadinessService readiness,
    RunConfirmationService confirmations,
    IRunExecutor executor,
    RunJobStore store,
    IRunEventPublisher publisher) : BackgroundService
{
    private readonly object _gate = new();
    private readonly Dictionary<string, RunJobView> _jobs = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, CancellationTokenSource> _cancellations = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentQueue<string> _queue = new();
    private readonly SemaphoreSlim _queueSignal = new(0);
    private string? _activeRealRunId;

    public override async Task StartAsync(CancellationToken cancellationToken)
    {
        foreach (var loaded in await store.LoadAllAsync(cancellationToken))
        {
            var job = loaded;
            if (!RunJobStore.IsTerminal(job.State))
            {
                var now = DateTimeOffset.UtcNow;
                job = job with
                {
                    State = "FAILED_TO_START",
                    Terminal = true,
                    TerminalReason = "CONTROLLER_RESTART_INTERRUPTED",
                    CurrentScenarioId = null,
                    CurrentPhase = "INTERRUPTED",
                    UpdatedUtc = now,
                    Transitions = [.. job.Transitions, new("FAILED_TO_START", now, "The controller restarted. Runtime work was not resumed automatically.")]
                };
                await store.SaveAsync(job, cancellationToken);
            }
            _jobs[job.RunId] = job;
        }
        await base.StartAsync(cancellationToken);
    }

    public Task<RunPreparationView> PrepareAsync(RunCreateRequest request, CancellationToken cancellationToken) =>
        readiness.PrepareAsync(request, IsRealRunActive(), cancellationToken);

    public async Task<RunJobView> QueueAsync(RunCreateRequest request, CancellationToken cancellationToken)
    {
        var preparation = await readiness.PrepareAsync(request, IsRealRunActive(), cancellationToken);
        if (!preparation.CanStart) throw new RunRequestException("RUN_NOT_READY", preparation);
        if (preparation.Mode == "real" && !confirmations.Consume(request.ConfirmationNonce, preparation.Mode, preparation.ScenarioIds))
            throw new RunRequestException("REAL_RUN_CONFIRMATION_REQUIRED", preparation with { ConfirmationNonce = null, ConfirmationExpiresUtc = null });

        var now = DateTimeOffset.UtcNow;
        var runId = $"job-{now:yyyyMMddTHHmmssZ}-{Guid.NewGuid():N}"[..38];
        var job = new RunJobView(
            runId,
            preparation.Mode,
            "QUEUED",
            preparation.ScenarioIds,
            preparation.SelectedCount,
            0,
            null,
            "WAITING_FOR_CONTROLLER_LEASE",
            0,
            false,
            false,
            null,
            null,
            now,
            now,
            [
                new("DRAFT", now, "The browser submitted scenario IDs and public run options."),
                new("VALIDATING", now, "The controller revalidated catalog and readiness state."),
                new("QUEUED", now, "The run is waiting for the single controller worker.")
            ],
            []);
        lock (_gate)
        {
            _jobs.Add(runId, job);
            _cancellations.Add(runId, new CancellationTokenSource());
            _queue.Enqueue(runId);
        }
        await PersistAndPublishAsync(job, cancellationToken);
        _queueSignal.Release();
        return job;
    }

    public IReadOnlyList<RunJobView> List() { lock (_gate) return _jobs.Values.OrderByDescending(job => job.CreatedUtc).ToArray(); }

    public RunJobView? Get(string runId)
    {
        lock (_gate) return _jobs.TryGetValue(runId, out var job) ? job : null;
    }

    public async Task<RunJobView?> CancelAsync(string runId, CancellationToken cancellationToken)
    {
        RunJobView? updated;
        CancellationTokenSource? source;
        lock (_gate)
        {
            if (!_jobs.TryGetValue(runId, out var job)) return null;
            if (job.Terminal) return job;
            var now = DateTimeOffset.UtcNow;
            if (job.State == "QUEUED")
            {
                updated = job with
                {
                    State = "CANCELLED",
                    Terminal = true,
                    CancellationRequested = true,
                    CurrentPhase = "CANCELLED_BEFORE_START",
                    TerminalReason = "Cancelled before runner start.",
                    UpdatedUtc = now,
                    Transitions = [.. job.Transitions, new("CANCELLED", now, "The queued run was cancelled before runtime work began.")]
                };
            }
            else
            {
                updated = job with
                {
                    State = "CANCELLING",
                    CancellationRequested = true,
                    CurrentPhase = "COOPERATIVE_CLEANUP",
                    UpdatedUtc = now,
                    Transitions = [.. job.Transitions, new("CANCELLING", now, "Future scenarios are cancelled; the bounded current operation will finish normal cleanup.")]
                };
            }
            _jobs[runId] = updated;
            _cancellations.TryGetValue(runId, out source);
        }
        source?.Cancel();
        await PersistAndPublishAsync(updated, cancellationToken);
        return updated;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await _queueSignal.WaitAsync(stoppingToken); }
            catch (OperationCanceledException) { break; }
            if (!_queue.TryDequeue(out var runId)) continue;
            var job = Get(runId);
            if (job is null || job.Terminal) continue;
            await ExecuteJobAsync(job, stoppingToken);
        }
    }

    private async Task ExecuteJobAsync(RunJobView initial, CancellationToken stoppingToken)
    {
        var job = await TransitionAsync(initial, "PREFLIGHT", "VALIDATING_CURRENT_STATE", "Readiness is being revalidated immediately before runner start.");
        var preparation = await readiness.PrepareAsync(new RunCreateRequest(job.Mode, job.ScenarioIds), IsRealRunActive(), stoppingToken);
        if (!preparation.CanStart)
        {
            await FinishAsync(job, "FAILED_TO_START", "READINESS_CHANGED_BEFORE_START", null);
            return;
        }

        lock (_gate)
        {
            if (job.Mode == "real") _activeRealRunId = job.RunId;
        }
        try
        {
            job = await TransitionAsync(job, "RUNNING", "RUNNER_START", "The authoritative PowerShell runner owns assertions, cleanup, and result classification.");
            var attempt = 0;
            while (true)
            {
                CancellationToken token;
                lock (_gate) token = _cancellations[job.RunId].Token;
                var result = await executor.ExecuteAsync(
                    new RunExecutionContext(job.RunId, job.Mode, job.ScenarioIds, attempt),
                    update => ApplyProgressAsync(job.RunId, update),
                    token);
                job = Get(job.RunId)!;
                if (result.RecoverableStartFailure && attempt == 0 && !job.CancellationRequested)
                {
                    attempt++;
                    job = job with { RecoveryAttempts = attempt };
                    lock (_gate) _jobs[job.RunId] = job;
                    job = await TransitionAsync(job, "RECOVERING", "BOUNDED_RECOVERY", "The runner failed before evidence or runtime mutation. One bounded restart will be attempted.");
                    job = await TransitionAsync(job, "RUNNING", "RUNNER_RESTART", "Bounded recovery attempt 1 of 1 started.");
                    continue;
                }

                if (job.CancellationRequested || result.CancellationObserved)
                    await FinishAsync(job, "CANCELLED", result.Detail, result.EvidenceRunId);
                else if (result.SafetyStopped)
                    await FinishAsync(job, "SAFETY_STOPPED", "Shared-state contamination was reported. Remaining scenarios were not run.", result.EvidenceRunId);
                else if (result.EvidenceComplete)
                    await FinishAsync(job, "COMPLETED", result.Detail, result.EvidenceRunId);
                else
                    await FinishAsync(job, "FAILED_TO_START", result.Detail, result.EvidenceRunId);
                break;
            }
        }
        finally
        {
            lock (_gate)
            {
                if (_activeRealRunId == job.RunId) _activeRealRunId = null;
                if (_cancellations.Remove(job.RunId, out var source)) source.Dispose();
            }
        }
    }

    private async Task ApplyProgressAsync(string runId, RunExecutionProgress progress)
    {
        RunJobView updated;
        lock (_gate)
        {
            if (!_jobs.TryGetValue(runId, out var job) || job.Terminal) return;
            var merged = progress.Scenarios;
            var now = DateTimeOffset.UtcNow;
            updated = job with
            {
                State = progress.Phase == "CANCELLING" ? "CANCELLING" : job.State,
                CurrentScenarioId = progress.CurrentScenarioId,
                CurrentPhase = progress.Phase,
                CompletedCount = merged.Count,
                Scenarios = merged,
                UpdatedUtc = now
            };
            _jobs[runId] = updated;
        }
        await PersistAndPublishAsync(updated, CancellationToken.None);
    }

    private async Task<RunJobView> TransitionAsync(RunJobView job, string state, string phase, string detail)
    {
        var now = DateTimeOffset.UtcNow;
        var updated = job with
        {
            State = state,
            CurrentPhase = phase,
            UpdatedUtc = now,
            Transitions = [.. job.Transitions, new(state, now, detail)]
        };
        lock (_gate) _jobs[job.RunId] = updated;
        await PersistAndPublishAsync(updated, CancellationToken.None);
        return updated;
    }

    private async Task FinishAsync(RunJobView job, string state, string detail, string? evidenceRunId)
    {
        var now = DateTimeOffset.UtcNow;
        var updated = job with
        {
            State = state,
            Terminal = true,
            TerminalReason = detail,
            EvidenceRunId = evidenceRunId,
            CurrentScenarioId = null,
            CurrentPhase = state,
            UpdatedUtc = now,
            Transitions = [.. job.Transitions, new(state, now, detail)]
        };
        lock (_gate) _jobs[job.RunId] = updated;
        await PersistAndPublishAsync(updated, CancellationToken.None);
    }

    private bool IsRealRunActive() { lock (_gate) return _activeRealRunId is not null; }

    private async Task PersistAndPublishAsync(RunJobView job, CancellationToken cancellationToken)
    {
        await store.SaveAsync(job, cancellationToken);
        await publisher.PublishAsync(job, cancellationToken);
    }
}

public sealed class RunRequestException(string code, RunPreparationView preparation) : Exception(code)
{
    public string Code { get; } = code;
    public RunPreparationView Preparation { get; } = preparation;
}
