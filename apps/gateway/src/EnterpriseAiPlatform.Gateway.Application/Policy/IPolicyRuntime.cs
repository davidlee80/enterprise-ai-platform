using EnterpriseAiPlatform.Gateway.Domain.Policy;

namespace EnterpriseAiPlatform.Gateway.Application.Policy;

public interface IPolicyRuntime
{
    ValueTask<PolicyDecision> EvaluateAsync(
        PolicyEvaluationRequest request,
        CancellationToken cancellationToken);
}
