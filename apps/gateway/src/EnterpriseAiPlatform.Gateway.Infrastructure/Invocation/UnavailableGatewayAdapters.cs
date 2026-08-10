using EnterpriseAiPlatform.Gateway.Application.Invocation;

namespace EnterpriseAiPlatform.Gateway.Infrastructure.Invocation;

internal sealed class UnavailableGatewayAuthenticator : IGatewayAuthenticator
{
    public ValueTask<GatewayAuthenticationDecision> AuthenticateAsync(
        string? authorizationValue,
        string requestId,
        string traceId,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult(string.IsNullOrWhiteSpace(authorizationValue)
            ? new GatewayAuthenticationDecision(
                GatewayAuthenticationOutcome.Denied,
                "AUTHENTICATION_CREDENTIAL_MISSING",
                null,
                null,
                [])
            : new GatewayAuthenticationDecision(
                GatewayAuthenticationOutcome.Indeterminate,
                "AUTHENTICATION_RUNTIME_UNAVAILABLE",
                null,
                null,
                []));
    }
}

internal sealed class UnavailableGatewayRuntimeSnapshotSource : IGatewayRuntimeSnapshotSource
{
    public ValueTask<GatewayRuntimeSnapshot?> GetSnapshotAsync(
        string tenantId,
        string modelAlias,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult<GatewayRuntimeSnapshot?>(null);
    }
}

internal sealed class UnavailableGatewayProviderInvoker : IGatewayProviderInvoker
{
    public ValueTask<ProviderInvocationResult> InvokeAsync(
        ProviderInvocationContext context,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult(new ProviderInvocationResult(
            ProviderInvocationOutcome.Unavailable,
            "PROVIDER_ADAPTER_UNAVAILABLE",
            ReadOnlyMemory<byte>.Empty,
            null));
    }
}

internal sealed class UnavailableGatewayUsageSink : IGatewayUsageSink
{
    public UsageEnqueueResult TryEnqueue(GatewayUsageObservation observation) =>
        new("unavailable", "USAGE_ENQUEUE_UNAVAILABLE");
}
