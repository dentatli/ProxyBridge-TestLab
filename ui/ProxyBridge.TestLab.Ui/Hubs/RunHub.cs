using Microsoft.AspNetCore.SignalR;
using ProxyBridge.TestLab.Ui.Models;

namespace ProxyBridge.TestLab.Ui.Hubs;

public sealed class RunHub : Hub;

public interface IRunEventPublisher
{
    Task PublishAsync(RunJobView job, CancellationToken cancellationToken);
}

public sealed class SignalRRunEventPublisher(IHubContext<RunHub> hub) : IRunEventPublisher
{
    public Task PublishAsync(RunJobView job, CancellationToken cancellationToken) =>
        hub.Clients.All.SendAsync("RunUpdated", job, cancellationToken);
}
