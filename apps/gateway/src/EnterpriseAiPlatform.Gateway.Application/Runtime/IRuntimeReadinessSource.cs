using EnterpriseAiPlatform.Gateway.Domain.Runtime;

namespace EnterpriseAiPlatform.Gateway.Application.Runtime;

public interface IRuntimeReadinessSource
{
    ValueTask<RuntimeReadiness> GetReadinessAsync(CancellationToken cancellationToken);
}
