using EnterpriseAiPlatform.Gateway.Domain.Policy;

namespace EnterpriseAiPlatform.Gateway.Application.Policy;

public sealed class EvaluatePolicy(IPolicyRuntime runtime)
{
    private readonly IPolicyRuntime _runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));

    public async ValueTask<PolicyDecision> ExecuteAsync(
        PolicyEvaluationRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();

        if (!string.Equals(request.TenantId, request.Principal.TenantId, StringComparison.Ordinal) ||
            !string.Equals(request.TenantId, request.PolicyContext.TenantId, StringComparison.Ordinal))
        {
            return PolicyDecision.Indeterminate(request, "POLICY_TENANT_CONTEXT_MISMATCH");
        }

        if (request.ConfigVersion != request.PolicyContext.ConfigVersion)
        {
            return PolicyDecision.Indeterminate(request, "POLICY_CONTEXT_VERSION_MISMATCH");
        }

        var decision = await _runtime.EvaluateAsync(request, cancellationToken).ConfigureAwait(false);
        if (!MatchesRequest(decision, request))
        {
            return PolicyDecision.Indeterminate(request, "POLICY_RUNTIME_CONTEXT_MISMATCH");
        }

        return decision;
    }

    private static bool MatchesRequest(PolicyDecision decision, PolicyEvaluationRequest request) =>
        string.Equals(decision.RequestId, request.RequestId, StringComparison.Ordinal) &&
        string.Equals(decision.TraceId, request.TraceId, StringComparison.Ordinal) &&
        string.Equals(decision.TenantId, request.TenantId, StringComparison.Ordinal) &&
        decision.ConfigVersion == request.ConfigVersion &&
        string.Equals(decision.ModelAlias, request.Resource.ModelAlias, StringComparison.Ordinal) &&
        decision.PolicyVersion == request.PolicyContext.PolicyVersion;
}
