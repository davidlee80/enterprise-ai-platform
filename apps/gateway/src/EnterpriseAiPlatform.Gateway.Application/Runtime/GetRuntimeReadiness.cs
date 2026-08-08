using EnterpriseAiPlatform.Gateway.Domain.Runtime;

namespace EnterpriseAiPlatform.Gateway.Application.Runtime;

public sealed class GetRuntimeReadiness
{
    private readonly IRuntimeReadinessSource _source;

    public GetRuntimeReadiness(IRuntimeReadinessSource source)
    {
        _source = source ?? throw new ArgumentNullException(nameof(source));
    }

    public ValueTask<RuntimeReadiness> ExecuteAsync(CancellationToken cancellationToken) =>
        _source.GetReadinessAsync(cancellationToken);
}
