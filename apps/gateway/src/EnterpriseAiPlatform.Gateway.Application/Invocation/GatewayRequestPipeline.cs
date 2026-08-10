using EnterpriseAiPlatform.Gateway.Application.Policy;
using EnterpriseAiPlatform.Gateway.Application.Routing;
using EnterpriseAiPlatform.Gateway.Domain.Policy;
using EnterpriseAiPlatform.Gateway.Domain.Routing;

namespace EnterpriseAiPlatform.Gateway.Application.Invocation;

public enum GatewayAuthenticationOutcome
{
    Authenticated,
    Denied,
    Indeterminate
}

public sealed record GatewayAuthenticationDecision(
    GatewayAuthenticationOutcome Outcome,
    string ReasonCode,
    string? SubjectId,
    string? TenantId,
    IReadOnlyList<string> Scopes);

public interface IGatewayAuthenticator
{
    ValueTask<GatewayAuthenticationDecision> AuthenticateAsync(
        string? authorizationValue,
        string requestId,
        string traceId,
        CancellationToken cancellationToken);
}

public sealed record GatewayInvocationRequest
{
    public GatewayInvocationRequest(
        string requestId,
        string traceId,
        string modelAlias,
        ReadOnlyMemory<byte> requestBody,
        string? authorizationValue)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(requestId);
        ArgumentException.ThrowIfNullOrWhiteSpace(traceId);
        ArgumentException.ThrowIfNullOrWhiteSpace(modelAlias);
        if (requestBody.IsEmpty)
        {
            throw new ArgumentException("Request body is required.", nameof(requestBody));
        }

        RequestId = requestId;
        TraceId = traceId;
        ModelAlias = modelAlias;
        RequestBody = requestBody;
        AuthorizationValue = authorizationValue;
    }

    public string RequestId { get; }
    public string TraceId { get; }
    public string ModelAlias { get; }
    public ReadOnlyMemory<byte> RequestBody { get; }
    public string? AuthorizationValue { get; }
}

public sealed record GatewayRuntimeSnapshot
{
    public GatewayRuntimeSnapshot(
        string tenantId,
        long configVersion,
        PublishedPolicyContext policyContext,
        RouterRegistry routerRegistry,
        IEnumerable<RouterCandidate> candidates,
        string routeStrategy,
        string requestedRegion,
        decimal estimatedCost,
        int maximumProviderAttempts)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(tenantId);
        ArgumentOutOfRangeException.ThrowIfLessThan(configVersion, 1);
        ArgumentException.ThrowIfNullOrWhiteSpace(routeStrategy);
        ArgumentException.ThrowIfNullOrWhiteSpace(requestedRegion);
        ArgumentOutOfRangeException.ThrowIfNegative(estimatedCost);
        ArgumentOutOfRangeException.ThrowIfLessThan(maximumProviderAttempts, 1);

        PolicyContext = policyContext ?? throw new ArgumentNullException(nameof(policyContext));
        RouterRegistry = routerRegistry ?? throw new ArgumentNullException(nameof(routerRegistry));
        var candidateCopy = (candidates ?? throw new ArgumentNullException(nameof(candidates))).ToArray();
        if (candidateCopy.Length == 0)
        {
            throw new ArgumentException("At least one Provider candidate is required.", nameof(candidates));
        }
        if (!string.Equals(tenantId, policyContext.TenantId, StringComparison.Ordinal) ||
            !string.Equals(tenantId, routerRegistry.TenantId, StringComparison.Ordinal) ||
            configVersion != policyContext.ConfigVersion ||
            configVersion != routerRegistry.ConfigVersion)
        {
            throw new ArgumentException("Snapshot tenant and config version must be consistent.");
        }

        TenantId = tenantId;
        ConfigVersion = configVersion;
        Candidates = Array.AsReadOnly(candidateCopy);
        RouteStrategy = routeStrategy;
        RequestedRegion = requestedRegion;
        EstimatedCost = estimatedCost;
        MaximumProviderAttempts = maximumProviderAttempts;
    }

    public string TenantId { get; }
    public long ConfigVersion { get; }
    public PublishedPolicyContext PolicyContext { get; }
    public RouterRegistry RouterRegistry { get; }
    public IReadOnlyList<RouterCandidate> Candidates { get; }
    public string RouteStrategy { get; }
    public string RequestedRegion { get; }
    public decimal EstimatedCost { get; }
    public int MaximumProviderAttempts { get; }
}

public interface IGatewayRuntimeSnapshotSource
{
    ValueTask<GatewayRuntimeSnapshot?> GetSnapshotAsync(
        string tenantId,
        string modelAlias,
        CancellationToken cancellationToken);
}

public enum ProviderInvocationOutcome
{
    Succeeded,
    Failed,
    Unavailable
}

public sealed record ProviderInvocationContext(
    string RequestId,
    string TraceId,
    string TenantId,
    long ConfigVersion,
    string ModelAlias,
    string ProviderId,
    int AttemptNumber,
    IReadOnlyList<PolicyObligation> Obligations,
    ReadOnlyMemory<byte> RequestBody);

public sealed record ProviderInvocationResult(
    ProviderInvocationOutcome Outcome,
    string ReasonCode,
    ReadOnlyMemory<byte> ResponseBody,
    string? ResponseMediaType);

public interface IGatewayProviderInvoker
{
    ValueTask<ProviderInvocationResult> InvokeAsync(
        ProviderInvocationContext context,
        CancellationToken cancellationToken);
}

public sealed record GatewayUsageObservation(
    string RequestId,
    string TraceId,
    string TenantId,
    long ConfigVersion,
    string ModelAlias,
    string? ProviderId,
    int AttemptCount,
    string RequestOutcome,
    string ReasonCode);

public sealed record UsageEnqueueResult(string Outcome, string ReasonCode);

public interface IGatewayUsageSink
{
    UsageEnqueueResult TryEnqueue(GatewayUsageObservation observation);
}

public enum GatewayInvocationOutcome
{
    Succeeded,
    Unauthorized,
    Forbidden,
    Unavailable,
    ProviderFailure
}

public sealed record GatewayInvocationResult(
    GatewayInvocationOutcome Outcome,
    string ReasonCode,
    string? TenantId,
    long? ConfigVersion,
    string ModelAlias,
    string? ProviderId,
    int AttemptCount,
    string UsageOutcome,
    string UsageReasonCode,
    ReadOnlyMemory<byte> ResponseBody,
    string? ResponseMediaType);

public sealed class GatewayRequestPipeline(
    IGatewayAuthenticator authenticator,
    IGatewayRuntimeSnapshotSource snapshotSource,
    EvaluatePolicy policy,
    RouterPluginPipeline router,
    IGatewayProviderInvoker provider,
    IGatewayUsageSink usageSink)
{
    private readonly IGatewayAuthenticator _authenticator = authenticator ?? throw new ArgumentNullException(nameof(authenticator));
    private readonly IGatewayRuntimeSnapshotSource _snapshotSource = snapshotSource ?? throw new ArgumentNullException(nameof(snapshotSource));
    private readonly EvaluatePolicy _policy = policy ?? throw new ArgumentNullException(nameof(policy));
    private readonly RouterPluginPipeline _router = router ?? throw new ArgumentNullException(nameof(router));
    private readonly IGatewayProviderInvoker _provider = provider ?? throw new ArgumentNullException(nameof(provider));
    private readonly IGatewayUsageSink _usageSink = usageSink ?? throw new ArgumentNullException(nameof(usageSink));

    public async ValueTask<GatewayInvocationResult> ExecuteAsync(
        GatewayInvocationRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();

        var authentication = await _authenticator.AuthenticateAsync(
            request.AuthorizationValue,
            request.RequestId,
            request.TraceId,
            cancellationToken).ConfigureAwait(false);
        if (authentication.Outcome != GatewayAuthenticationOutcome.Authenticated)
        {
            return EmptyResult(
                authentication.Outcome == GatewayAuthenticationOutcome.Denied
                    ? GatewayInvocationOutcome.Unauthorized
                    : GatewayInvocationOutcome.Unavailable,
                authentication.ReasonCode,
                request.ModelAlias);
        }
        if (string.IsNullOrWhiteSpace(authentication.SubjectId) ||
            string.IsNullOrWhiteSpace(authentication.TenantId))
        {
            return EmptyResult(GatewayInvocationOutcome.Unavailable, "AUTHENTICATION_CONTEXT_INVALID", request.ModelAlias);
        }

        var snapshot = await _snapshotSource.GetSnapshotAsync(
            authentication.TenantId,
            request.ModelAlias,
            cancellationToken).ConfigureAwait(false);
        if (snapshot is null)
        {
            return EmptyResult(
                GatewayInvocationOutcome.Unavailable,
                "RUNTIME_SNAPSHOT_UNAVAILABLE",
                request.ModelAlias,
                authentication.TenantId);
        }
        if (!string.Equals(snapshot.TenantId, authentication.TenantId, StringComparison.Ordinal))
        {
            return EmptyResult(GatewayInvocationOutcome.Unavailable, "RUNTIME_SNAPSHOT_TENANT_MISMATCH", request.ModelAlias, authentication.TenantId);
        }

        var policyRequest = new PolicyEvaluationRequest(
            request.RequestId,
            request.TraceId,
            snapshot.TenantId,
            snapshot.ConfigVersion,
            new PolicyPrincipal(authentication.SubjectId, snapshot.TenantId, authentication.Scopes),
            new PolicyResource(request.ModelAlias, snapshot.RequestedRegion, snapshot.EstimatedCost),
            snapshot.PolicyContext);
        var policyDecision = await _policy.ExecuteAsync(policyRequest, cancellationToken).ConfigureAwait(false);
        if (policyDecision.Outcome != PolicyOutcome.Allow)
        {
            var outcome = policyDecision.Outcome == PolicyOutcome.Deny
                ? GatewayInvocationOutcome.Forbidden
                : GatewayInvocationOutcome.Unavailable;
            return CompleteWithUsage(
                outcome,
                policyDecision.ReasonCode,
                request,
                snapshot,
                null,
                0,
                ReadOnlyMemory<byte>.Empty,
                null);
        }

        var routeRequest = new RouterRequest(
            request.RequestId,
            request.TraceId,
            snapshot.TenantId,
            snapshot.ConfigVersion,
            request.ModelAlias,
            snapshot.RouteStrategy,
            policyDecision.Outcome,
            policyDecision.PolicyVersion,
            policyDecision.Obligations,
            snapshot.Candidates);
        var routeDecision = await _router.RouteAsync(routeRequest, snapshot.RouterRegistry, cancellationToken).ConfigureAwait(false);
        if (routeDecision.Outcome != RouteOutcome.Selected)
        {
            var outcome = routeDecision.Outcome == RouteOutcome.NoRoute
                ? GatewayInvocationOutcome.Forbidden
                : GatewayInvocationOutcome.Unavailable;
            return CompleteWithUsage(outcome, routeDecision.ReasonCode, request, snapshot, null, 0, ReadOnlyMemory<byte>.Empty, null);
        }

        var attemptCount = 0;
        var lastReasonCode = "PROVIDER_ATTEMPTS_EXHAUSTED";
        string? lastProviderId = null;
        foreach (var providerId in routeDecision.OrderedCandidateIds.Take(snapshot.MaximumProviderAttempts))
        {
            cancellationToken.ThrowIfCancellationRequested();
            attemptCount++;
            lastProviderId = providerId;
            ProviderInvocationResult providerResult;
            try
            {
                providerResult = await _provider.InvokeAsync(
                    new ProviderInvocationContext(
                        request.RequestId,
                        request.TraceId,
                        snapshot.TenantId,
                        snapshot.ConfigVersion,
                        request.ModelAlias,
                        providerId,
                        attemptCount,
                        routeDecision.ForwardedObligations,
                        request.RequestBody),
                    cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception)
            {
                providerResult = new ProviderInvocationResult(
                    ProviderInvocationOutcome.Unavailable,
                    "PROVIDER_ADAPTER_UNAVAILABLE",
                    ReadOnlyMemory<byte>.Empty,
                    null);
            }

            lastReasonCode = providerResult.ReasonCode;
            if (providerResult.Outcome == ProviderInvocationOutcome.Succeeded)
            {
                return CompleteWithUsage(
                    GatewayInvocationOutcome.Succeeded,
                    providerResult.ReasonCode,
                    request,
                    snapshot,
                    providerId,
                    attemptCount,
                    providerResult.ResponseBody,
                    providerResult.ResponseMediaType);
            }
        }

        return CompleteWithUsage(
            GatewayInvocationOutcome.ProviderFailure,
            lastReasonCode,
            request,
            snapshot,
            lastProviderId,
            attemptCount,
            ReadOnlyMemory<byte>.Empty,
            null);
    }

    private GatewayInvocationResult CompleteWithUsage(
        GatewayInvocationOutcome outcome,
        string reasonCode,
        GatewayInvocationRequest request,
        GatewayRuntimeSnapshot snapshot,
        string? providerId,
        int attemptCount,
        ReadOnlyMemory<byte> responseBody,
        string? responseMediaType)
    {
        UsageEnqueueResult usage;
        try
        {
            usage = _usageSink.TryEnqueue(new GatewayUsageObservation(
                request.RequestId,
                request.TraceId,
                snapshot.TenantId,
                snapshot.ConfigVersion,
                request.ModelAlias,
                providerId,
                attemptCount,
                outcome == GatewayInvocationOutcome.Succeeded ? "succeeded" : "failed",
                reasonCode));
        }
        catch (Exception)
        {
            usage = new UsageEnqueueResult("unavailable", "USAGE_ENQUEUE_UNAVAILABLE");
        }

        return new GatewayInvocationResult(
            outcome,
            reasonCode,
            snapshot.TenantId,
            snapshot.ConfigVersion,
            request.ModelAlias,
            providerId,
            attemptCount,
            usage.Outcome,
            usage.ReasonCode,
            responseBody,
            responseMediaType);
    }

    private static GatewayInvocationResult EmptyResult(
        GatewayInvocationOutcome outcome,
        string reasonCode,
        string modelAlias,
        string? tenantId = null) =>
        new(
            outcome,
            reasonCode,
            tenantId,
            null,
            modelAlias,
            null,
            0,
            "not_attempted",
            "USAGE_CONTEXT_UNAVAILABLE",
            ReadOnlyMemory<byte>.Empty,
            null);
}
