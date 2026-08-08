using EnterpriseAiPlatform.Gateway.Application.Runtime;
using EnterpriseAiPlatform.Gateway.Domain.Runtime;

namespace EnterpriseAiPlatform.Gateway.Infrastructure.Runtime;

internal sealed class UnavailableRuntimeReadinessSource : IRuntimeReadinessSource
{
    private static readonly RuntimeReadiness Unavailable = new(
        isReady: false,
        reasonCode: "RUNTIME_SNAPSHOT_UNAVAILABLE",
        configVersion: null,
        snapshotAgeSeconds: null);

    public ValueTask<RuntimeReadiness> GetReadinessAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult(Unavailable);
    }
}
