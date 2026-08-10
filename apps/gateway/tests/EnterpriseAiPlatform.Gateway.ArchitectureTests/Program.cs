using System.Net;
using System.Reflection;
using System.Text;
using EnterpriseAiPlatform.Gateway.Application.Invocation;
using EnterpriseAiPlatform.Gateway.Application.Policy;
using EnterpriseAiPlatform.Gateway.Application.Routing;
using EnterpriseAiPlatform.Gateway.Application.Runtime;
using EnterpriseAiPlatform.Gateway.Domain.Contracts;
using EnterpriseAiPlatform.Gateway.Domain.Policy;
using EnterpriseAiPlatform.Gateway.Domain.Routing;
using EnterpriseAiPlatform.Gateway.Domain.Runtime;
using EnterpriseAiPlatform.Gateway.Infrastructure;
using EnterpriseAiPlatform.Gateway.Infrastructure.Policy;
using Microsoft.Extensions.DependencyInjection;

TestDependencyInjection();
await TestRouterPluginAsync();
await TestOpaPolicyRuntimeAsync();
await TestGatewayRequestPipelineAsync();

Console.WriteLine(
    "status=pass reason_code=GATEWAY_DDD_DI_RUNTIME_OK container=Microsoft.Extensions.DependencyInjection layers=Domain,Application,Infrastructure,Api");
return 0;

static void TestDependencyInjection()
{
    var services = new ServiceCollection();
    services.AddSingleton<GetRuntimeReadiness>();
    services.AddGatewayInfrastructure();

    using (var provider = services.BuildServiceProvider(new ServiceProviderOptions
    {
        ValidateOnBuild = true,
        ValidateScopes = true
    }))
    {
        var registrations = provider.GetServices<IRuntimeReadinessSource>().ToArray();
        Assert(registrations.Length == 1, "DI_DEFAULT_REGISTRATION_COUNT_INVALID");
        Assert(provider.GetRequiredService<IPolicyRuntime>() is OpaPolicyRuntime, "DI_OPA_RUNTIME_NOT_REGISTERED");
        Assert(provider.GetRequiredService<EvaluatePolicy>() is not null, "DI_POLICY_USE_CASE_NOT_REGISTERED");
        Assert(provider.GetRequiredService<RouterPluginPipeline>() is not null, "DI_ROUTER_PIPELINE_NOT_REGISTERED");
        Assert(provider.GetRequiredService<GatewayRequestPipeline>() is not null, "DI_GATEWAY_REQUEST_PIPELINE_NOT_REGISTERED");

        var readiness = provider.GetRequiredService<GetRuntimeReadiness>()
            .ExecuteAsync(CancellationToken.None).AsTask().GetAwaiter().GetResult();
        Assert(!readiness.IsReady, "DI_DEFAULT_MUST_FAIL_CLOSED");
        Assert(readiness.ReasonCode == "RUNTIME_SNAPSHOT_UNAVAILABLE", "DI_DEFAULT_REASON_CODE_INVALID");
        Assert(readiness.ConfigVersion is null, "DI_DEFAULT_CONFIG_VERSION_INVALID");
    }

    var readyWithoutVersionRejected = false;
    try
    {
        _ = new RuntimeReadiness(
            isReady: true,
            reasonCode: "TEST_READY",
            configVersion: null,
            snapshotAgeSeconds: 0);
    }
    catch (ArgumentException)
    {
        readyWithoutVersionRejected = true;
    }
    Assert(readyWithoutVersionRejected, "DOMAIN_READY_CONFIG_VERSION_REQUIRED");

    var fake = new FakeRuntimeReadinessSource();
    var replacementServices = new ServiceCollection();
    replacementServices.AddSingleton<IRuntimeReadinessSource>(fake);
    replacementServices.AddGatewayInfrastructure();
    replacementServices.AddSingleton<GetRuntimeReadiness>();

    using var replacementProvider = replacementServices.BuildServiceProvider(new ServiceProviderOptions
    {
        ValidateOnBuild = true,
        ValidateScopes = true
    });
    var replacementRegistrations = replacementProvider.GetServices<IRuntimeReadinessSource>().ToArray();
    Assert(replacementRegistrations.Length == 1, "DI_REPLACEMENT_REGISTRATION_COUNT_INVALID");
    Assert(ReferenceEquals(replacementRegistrations[0], fake), "DI_REPLACEMENT_WAS_OVERRIDDEN");

    var replacementReadiness = replacementProvider.GetRequiredService<GetRuntimeReadiness>()
        .ExecuteAsync(CancellationToken.None).AsTask().GetAwaiter().GetResult();
    Assert(replacementReadiness.ReasonCode == "TEST_RUNTIME_UNAVAILABLE", "DI_FAKE_NOT_USED");
}

static async Task TestGatewayRequestPipelineAsync()
{
    var version = ContractVersion.FromNumber(1);
    var identity = new FakeRouterPlugin("identity", version, static (context, _) =>
        ValueTask.FromResult(new RouterPluginResult(
            "identity",
            ContractVersion.FromNumber(1),
            RouterPluginOutcome.Applied,
            "IDENTITY_APPLIED",
            context.Candidates.Select(candidate => candidate.ProviderId))));
    var snapshot = new GatewayRuntimeSnapshot(
        "tenant-verified",
        42,
        new PublishedPolicyContext(
            "tenant-verified",
            42,
            version,
            ["p_tenant", "p_model"],
            "active",
            ["smart-chat"],
            ["cn-north"],
            new PolicyBudget(90m, 100m),
            [PolicyObligation.DisableBodyLogging()]),
        new RouterRegistry(
            "tenant-verified",
            42,
            [new RouterPluginRegistration("identity", version, true)],
            [new RouterPipelineRegistration("test-composed", ["identity"])]),
        [
            new RouterCandidate("provider-a", "cn-north", 10, 100, true),
            new RouterCandidate("provider-b", "cn-north", 20, 50, true)
        ],
        "test-composed",
        "cn-north",
        10m,
        2);
    var request = new GatewayInvocationRequest(
        "request-gateway-test",
        "trace-gateway-test",
        "smart-chat",
        Encoding.UTF8.GetBytes("{\"model\":\"smart-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"test-only\"}]}"),
        "Bearer credential-test-only");
    var provider = new FakeGatewayProviderInvoker();
    var pipeline = new GatewayRequestPipeline(
        new FakeGatewayAuthenticator(GatewayAuthenticationOutcome.Authenticated),
        new FakeGatewaySnapshotSource(snapshot),
        new EvaluatePolicy(new FakePolicyRuntime(PolicyOutcome.Allow)),
        new RouterPluginPipeline([identity]),
        provider,
        new ThrowingGatewayUsageSink());

    var success = await pipeline.ExecuteAsync(request, CancellationToken.None);
    Assert(success.Outcome == GatewayInvocationOutcome.Succeeded, "GATEWAY_PIPELINE_SUCCESS_FAILED");
    Assert(success.ProviderId == "provider-b" && success.AttemptCount == 2, "GATEWAY_PIPELINE_FALLBACK_FAILED");
    Assert(success.ConfigVersion == 42 && success.TenantId == "tenant-verified", "GATEWAY_PIPELINE_CONTEXT_LOST");
    Assert(success.UsageReasonCode == "USAGE_ENQUEUE_UNAVAILABLE", "GATEWAY_PIPELINE_USAGE_FAILURE_BLOCKED_RESPONSE");
    Assert(Encoding.UTF8.GetString(success.ResponseBody.Span).Contains("chat.completion", StringComparison.Ordinal), "GATEWAY_PIPELINE_RESPONSE_LOST");

    var denied = await new GatewayRequestPipeline(
        new FakeGatewayAuthenticator(GatewayAuthenticationOutcome.Denied),
        new FakeGatewaySnapshotSource(snapshot),
        new EvaluatePolicy(new FakePolicyRuntime(PolicyOutcome.Allow)),
        new RouterPluginPipeline([identity]),
        provider,
        new RecordingGatewayUsageSink())
        .ExecuteAsync(request, CancellationToken.None);
    Assert(denied.Outcome == GatewayInvocationOutcome.Unauthorized, "GATEWAY_PIPELINE_AUTH_DENIAL_FAILED");
    Assert(denied.ReasonCode == "AUTHENTICATION_DENIED", "GATEWAY_PIPELINE_AUTH_REASON_INVALID");

    var policyDeniedUsage = new RecordingGatewayUsageSink();
    var policyDenied = await new GatewayRequestPipeline(
        new FakeGatewayAuthenticator(GatewayAuthenticationOutcome.Authenticated),
        new FakeGatewaySnapshotSource(snapshot),
        new EvaluatePolicy(new FakePolicyRuntime(PolicyOutcome.Deny)),
        new RouterPluginPipeline([identity]),
        provider,
        policyDeniedUsage)
        .ExecuteAsync(request, CancellationToken.None);
    Assert(policyDenied.Outcome == GatewayInvocationOutcome.Forbidden, "GATEWAY_PIPELINE_POLICY_DENIAL_FAILED");
    Assert(policyDeniedUsage.Observations.Count == 1, "GATEWAY_PIPELINE_DENIAL_USAGE_MISSING");

    Console.WriteLine("status=pass reason_code=GATEWAY_REQUEST_PIPELINE_OK auth=verified policy=allow router=selected fallback=verified usage=non-blocking");
}

static async Task TestRouterPluginAsync()
{
    var routeMethod = typeof(IRouterPlugin).GetMethod(nameof(IRouterPlugin.RouteAsync));
    Assert(routeMethod is not null, "ROUTER_PLUGIN_METHOD_MISSING");
    Assert(routeMethod!.ReturnType == typeof(ValueTask<RouterPluginResult>), "ROUTER_PLUGIN_RETURN_TYPE_INVALID");
    var parameters = routeMethod.GetParameters();
    Assert(
        parameters.Length == 2 &&
        parameters[0].ParameterType == typeof(RouterPluginContext) &&
        parameters[1].ParameterType == typeof(CancellationToken),
        "ROUTER_PLUGIN_PARAMETERS_INVALID");

    var version = ContractVersion.FromNumber(1);
    var identity = new FakeRouterPlugin("identity", version, static (context, _) =>
        ValueTask.FromResult(new RouterPluginResult(
            "identity",
            ContractVersion.FromNumber(1),
            RouterPluginOutcome.Applied,
            "IDENTITY_APPLIED",
            context.Candidates.Select(candidate => candidate.ProviderId))));
    var reverse = new FakeRouterPlugin("reverse", version, static (context, _) =>
        ValueTask.FromResult(new RouterPluginResult(
            "reverse",
            ContractVersion.FromNumber(1),
            RouterPluginOutcome.Applied,
            "REVERSE_APPLIED",
            context.Candidates.Reverse().Select(candidate => candidate.ProviderId))));
    var invalid = new FakeRouterPlugin("invalid", version, static (_, _) =>
        ValueTask.FromResult(new RouterPluginResult(
            "invalid",
            ContractVersion.FromNumber(1),
            RouterPluginOutcome.Applied,
            "INVALID_RESULT",
            ["provider-outside-request"])));
    var pipeline = new RouterPluginPipeline([identity, reverse, invalid]);
    var request = NewRouterRequest();

    var baseRegistry = new RouterRegistry(
        "tenant-verified",
        42,
        [new RouterPluginRegistration("identity", version, true)],
        [new RouterPipelineRegistration("test-composed", ["identity"])]);
    var baseDecision = await pipeline.RouteAsync(request, baseRegistry, CancellationToken.None);
    Assert(baseDecision.Outcome == RouteOutcome.Selected, "ROUTER_BASE_OUTCOME_INVALID");
    Assert(baseDecision.SelectedProviderId == "provider-a", "ROUTER_BASE_SELECTION_INVALID");

    var composedRegistry = new RouterRegistry(
        "tenant-verified",
        42,
        [
            new RouterPluginRegistration("identity", version, true),
            new RouterPluginRegistration("reverse", version, true)
        ],
        [new RouterPipelineRegistration("test-composed", ["identity", "reverse"])]);
    var composedDecision = await pipeline.RouteAsync(request, composedRegistry, CancellationToken.None);
    Assert(composedDecision.Outcome == RouteOutcome.Selected, "ROUTER_COMPOSED_OUTCOME_INVALID");
    Assert(composedDecision.SelectedProviderId == "provider-b", "ROUTER_DYNAMIC_PLUGIN_REGISTRATION_FAILED");
    Assert(composedDecision.PluginTrace.Count == 2, "ROUTER_PLUGIN_TRACE_MISSING");

    var invalidRegistry = new RouterRegistry(
        "tenant-verified",
        42,
        [new RouterPluginRegistration("invalid", version, true)],
        [new RouterPipelineRegistration("test-composed", ["invalid"])]);
    var invalidDecision = await pipeline.RouteAsync(request, invalidRegistry, CancellationToken.None);
    Assert(invalidDecision.Outcome == RouteOutcome.Indeterminate, "ROUTER_INVALID_RESULT_NOT_INDETERMINATE");
    Assert(invalidDecision.ReasonCode == "ROUTER_PLUGIN_RESULT_INVALID", "ROUTER_INVALID_RESULT_REASON_INVALID");

    using var cancellation = new CancellationTokenSource();
    cancellation.Cancel();
    await AssertCanceledAsync(
        async () => await pipeline.RouteAsync(request, baseRegistry, cancellation.Token),
        "ROUTER_CANCELLATION_NOT_PROPAGATED");

    Console.WriteLine("status=pass reason_code=ROUTER_PLUGIN_RUNTIME_OK signature=RouteAsync(context,cancellationToken)");
}

static async Task TestOpaPolicyRuntimeAsync()
{
    var request = NewPolicyRequest();
    var allowJson = """
        {
          "result": {
            "schema_version": 1,
            "request_id": "request-policy-test",
            "trace_id": "trace-policy-test",
            "tenant_id": "tenant-verified",
            "config_version": 42,
            "model_alias": "smart-chat",
            "outcome": "allow",
            "allow": true,
            "reason_code": "POLICY_ALLOWED",
            "deny_reason": null,
            "obligations": [
              { "kind": "force_region", "region": "cn-north" },
              { "kind": "disable_body_logging", "enabled": true }
            ],
            "matched_policy_ids": ["p_tenant", "p_model"],
            "policy_version": 7
          }
        }
        """;
    var handler = new StubHttpMessageHandler((message, _) =>
    {
        Assert(message.Method == HttpMethod.Post, "OPA_HTTP_METHOD_INVALID");
        Assert(message.RequestUri?.AbsoluteUri == "http://127.0.0.1:8181/v1/data/enterprise_ai/gateway/decision", "OPA_DATA_API_PATH_INVALID");
        var body = message.Content!.ReadAsStringAsync().GetAwaiter().GetResult();
        Assert(body.Contains("\"input\"", StringComparison.Ordinal), "OPA_INPUT_ENVELOPE_MISSING");
        Assert(body.Contains("\"tenant_id\":\"tenant-verified\"", StringComparison.Ordinal), "OPA_TENANT_CONTEXT_MISSING");
        Assert(!body.Contains("endpoint", StringComparison.OrdinalIgnoreCase), "OPA_ENDPOINT_DISCLOSURE");
        Assert(!body.Contains("provider_key", StringComparison.OrdinalIgnoreCase), "OPA_CREDENTIAL_DISCLOSURE");
        return Task.FromResult(JsonResponse(HttpStatusCode.OK, allowJson));
    });
    var runtime = NewOpaRuntime(handler);
    var decision = await new EvaluatePolicy(runtime).ExecuteAsync(request, CancellationToken.None);
    Assert(decision.Outcome == PolicyOutcome.Allow && decision.Allow == true, "OPA_ALLOW_DECISION_INVALID");
    Assert(decision.Obligations.Count == 2, "OPA_OBLIGATIONS_LOST");
    Assert(handler.CallCount == 1, "OPA_CALL_COUNT_INVALID");

    var undefined = await new EvaluatePolicy(NewOpaRuntime(new StubHttpMessageHandler((_, _) =>
        Task.FromResult(JsonResponse(HttpStatusCode.OK, "{}")))))
        .ExecuteAsync(request, CancellationToken.None);
    Assert(undefined.Outcome == PolicyOutcome.Indeterminate, "OPA_UNDEFINED_NOT_INDETERMINATE");
    Assert(undefined.ReasonCode == "POLICY_RUNTIME_DOCUMENT_UNDEFINED", "OPA_UNDEFINED_REASON_INVALID");

    var unavailable = await new EvaluatePolicy(NewOpaRuntime(new StubHttpMessageHandler((_, _) =>
        Task.FromResult(JsonResponse(HttpStatusCode.ServiceUnavailable, "{}")))))
        .ExecuteAsync(request, CancellationToken.None);
    Assert(unavailable.Outcome == PolicyOutcome.Indeterminate, "OPA_HTTP_FAILURE_NOT_INDETERMINATE");
    Assert(unavailable.ReasonCode == "POLICY_RUNTIME_HTTP_ERROR", "OPA_HTTP_FAILURE_REASON_INVALID");

    var malformed = await new EvaluatePolicy(NewOpaRuntime(new StubHttpMessageHandler((_, _) =>
        Task.FromResult(JsonResponse(HttpStatusCode.OK, "{\"result\":{\"allow\":true}}")))))
        .ExecuteAsync(request, CancellationToken.None);
    Assert(malformed.ReasonCode == "POLICY_RUNTIME_RESULT_INVALID", "OPA_MALFORMED_RESULT_ACCEPTED");

    var transportFailure = await new EvaluatePolicy(NewOpaRuntime(new StubHttpMessageHandler((_, _) =>
        throw new HttpRequestException("test transport failure"))))
        .ExecuteAsync(request, CancellationToken.None);
    Assert(transportFailure.ReasonCode == "POLICY_RUNTIME_UNAVAILABLE", "OPA_TRANSPORT_FAILURE_REASON_INVALID");

    using var runtimeTimeout = new CancellationTokenSource();
    runtimeTimeout.Cancel();
    var timedOut = await new EvaluatePolicy(NewOpaRuntime(new StubHttpMessageHandler((_, _) =>
        Task.FromCanceled<HttpResponseMessage>(runtimeTimeout.Token))))
        .ExecuteAsync(request, CancellationToken.None);
    Assert(timedOut.ReasonCode == "POLICY_RUNTIME_TIMEOUT", "OPA_TIMEOUT_REASON_INVALID");

    var contextMismatchHandler = new StubHttpMessageHandler((_, _) =>
        throw new InvalidOperationException("Mismatched tenant context must not reach OPA."));
    var contextMismatchRequest = NewPolicyRequest(principalTenantId: "tenant-other");
    var contextMismatch = await new EvaluatePolicy(NewOpaRuntime(contextMismatchHandler))
        .ExecuteAsync(contextMismatchRequest, CancellationToken.None);
    Assert(contextMismatch.ReasonCode == "POLICY_TENANT_CONTEXT_MISMATCH", "POLICY_TENANT_GUARD_INVALID");
    Assert(contextMismatchHandler.CallCount == 0, "POLICY_TENANT_MISMATCH_REACHED_OPA");

    var externalEndpointRejected = false;
    try
    {
        _ = new OpaPolicyRuntimeOptions(new Uri("http://opa.internal:8181/", UriKind.Absolute));
    }
    catch (ArgumentException)
    {
        externalEndpointRejected = true;
    }
    Assert(externalEndpointRejected, "OPA_NON_LOOPBACK_ENDPOINT_ACCEPTED");

    using var cancellation = new CancellationTokenSource();
    cancellation.Cancel();
    await AssertCanceledAsync(
        async () => await new EvaluatePolicy(runtime).ExecuteAsync(request, cancellation.Token),
        "OPA_CANCELLATION_NOT_PROPAGATED");

    Console.WriteLine("status=pass reason_code=POLICY_OPA_RUNTIME_OK runtime=OPA data_api=v1 cancellation=propagated");
}

static OpaPolicyRuntime NewOpaRuntime(HttpMessageHandler handler)
{
    var options = new OpaPolicyRuntimeOptions(OpaPolicyRuntimeOptions.DefaultBaseAddress);
    return new OpaPolicyRuntime(new HttpClient(handler) { BaseAddress = options.BaseAddress }, options);
}

static HttpResponseMessage JsonResponse(HttpStatusCode statusCode, string json) =>
    new(statusCode) { Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json") };

static PolicyEvaluationRequest NewPolicyRequest(string principalTenantId = "tenant-verified") =>
    new(
        "request-policy-test",
        "trace-policy-test",
        "tenant-verified",
        42,
        new PolicyPrincipal("subject-policy-test", principalTenantId, ["chat:invoke"]),
        new PolicyResource("smart-chat", "cn-north", 10m),
        new PublishedPolicyContext(
            "tenant-verified",
            42,
            ContractVersion.FromNumber(7),
            ["p_tenant", "p_model"],
            "active",
            ["smart-chat"],
            ["cn-north"],
            new PolicyBudget(90m, 100m),
            [PolicyObligation.ForceRegion("cn-north"), PolicyObligation.DisableBodyLogging()]));

static RouterRequest NewRouterRequest() =>
    new(
        "request-router-test",
        "trace-router-test",
        "tenant-verified",
        42,
        "smart-chat",
        "test-composed",
        PolicyOutcome.Allow,
        ContractVersion.FromNumber(7),
        [PolicyObligation.DisableBodyLogging()],
        [
            new RouterCandidate("provider-a", "cn-north", 10, 100, true),
            new RouterCandidate("provider-b", "cn-south", 20, 50, true)
        ]);

static async Task AssertCanceledAsync(Func<Task> action, string reasonCode)
{
    try
    {
        await action();
    }
    catch (OperationCanceledException)
    {
        return;
    }

    Assert(false, reasonCode);
}

static void Assert(bool condition, string reasonCode)
{
    if (!condition)
    {
        Console.Error.WriteLine($"status=fail reason_code={reasonCode}");
        Environment.Exit(1);
    }
}

internal sealed class FakeRuntimeReadinessSource : IRuntimeReadinessSource
{
    public ValueTask<RuntimeReadiness> GetReadinessAsync(CancellationToken cancellationToken) =>
        ValueTask.FromResult(new RuntimeReadiness(
            isReady: false,
            reasonCode: "TEST_RUNTIME_UNAVAILABLE",
            configVersion: 42,
            snapshotAgeSeconds: 1.5));
}

internal sealed class FakeRouterPlugin(
    string pluginId,
    ContractVersion pluginVersion,
    Func<RouterPluginContext, CancellationToken, ValueTask<RouterPluginResult>> route) : IRouterPlugin
{
    private readonly Func<RouterPluginContext, CancellationToken, ValueTask<RouterPluginResult>> _route = route;

    public string PluginId { get; } = pluginId;
    public ContractVersion PluginVersion { get; } = pluginVersion;

    public ValueTask<RouterPluginResult> RouteAsync(
        RouterPluginContext context,
        CancellationToken cancellationToken) =>
        _route(context, cancellationToken);
}

internal sealed class StubHttpMessageHandler(
    Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
{
    private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> _send = send;

    public int CallCount { get; private set; }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        CallCount++;
        return _send(request, cancellationToken);
    }
}

internal sealed class FakeGatewayAuthenticator(GatewayAuthenticationOutcome outcome) : IGatewayAuthenticator
{
    public ValueTask<GatewayAuthenticationDecision> AuthenticateAsync(
        string? authorizationValue,
        string requestId,
        string traceId,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult(outcome == GatewayAuthenticationOutcome.Authenticated
            ? new GatewayAuthenticationDecision(
                outcome,
                "AUTHENTICATION_SUCCEEDED",
                "subject-test-only",
                "tenant-verified",
                ["chat:invoke"])
            : new GatewayAuthenticationDecision(
                outcome,
                outcome == GatewayAuthenticationOutcome.Denied
                    ? "AUTHENTICATION_DENIED"
                    : "AUTHENTICATION_RUNTIME_UNAVAILABLE",
                null,
                null,
                []));
    }
}

internal sealed class FakeGatewaySnapshotSource(GatewayRuntimeSnapshot snapshot) : IGatewayRuntimeSnapshotSource
{
    public ValueTask<GatewayRuntimeSnapshot?> GetSnapshotAsync(
        string tenantId,
        string modelAlias,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult<GatewayRuntimeSnapshot?>(snapshot);
    }
}

internal sealed class FakePolicyRuntime(PolicyOutcome outcome) : IPolicyRuntime
{
    public ValueTask<PolicyDecision> EvaluateAsync(
        PolicyEvaluationRequest request,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult(new PolicyDecision(
            request.RequestId,
            request.TraceId,
            request.TenantId,
            request.ConfigVersion,
            request.Resource.ModelAlias,
            outcome,
            outcome switch
            {
                PolicyOutcome.Allow => "POLICY_ALLOWED",
                PolicyOutcome.Deny => "POLICY_DENIED",
                _ => "POLICY_RUNTIME_UNAVAILABLE"
            },
            outcome == PolicyOutcome.Deny ? "POLICY_MODEL_DENIED" : null,
            outcome == PolicyOutcome.Allow ? request.PolicyContext.Obligations : [],
            outcome == PolicyOutcome.Indeterminate ? [] : request.PolicyContext.PolicyIds,
            request.PolicyContext.PolicyVersion));
    }
}

internal sealed class FakeGatewayProviderInvoker : IGatewayProviderInvoker
{
    public ValueTask<ProviderInvocationResult> InvokeAsync(
        ProviderInvocationContext context,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (context.ProviderId == "provider-a")
        {
            return ValueTask.FromResult(new ProviderInvocationResult(
                ProviderInvocationOutcome.Unavailable,
                "PROVIDER_TIMEOUT",
                ReadOnlyMemory<byte>.Empty,
                null));
        }

        return ValueTask.FromResult(new ProviderInvocationResult(
            ProviderInvocationOutcome.Succeeded,
            "PROVIDER_SUCCEEDED",
            Encoding.UTF8.GetBytes("{\"id\":\"chatcmpl-test\",\"object\":\"chat.completion\",\"created\":1,\"model\":\"smart-chat\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}"),
            "application/json"));
    }
}

internal sealed class ThrowingGatewayUsageSink : IGatewayUsageSink
{
    public UsageEnqueueResult TryEnqueue(GatewayUsageObservation observation) =>
        throw new InvalidOperationException("test-only enqueue failure");
}

internal sealed class RecordingGatewayUsageSink : IGatewayUsageSink
{
    public List<GatewayUsageObservation> Observations { get; } = [];

    public UsageEnqueueResult TryEnqueue(GatewayUsageObservation observation)
    {
        Observations.Add(observation);
        return new UsageEnqueueResult("enqueued", "USAGE_ENQUEUED");
    }
}
