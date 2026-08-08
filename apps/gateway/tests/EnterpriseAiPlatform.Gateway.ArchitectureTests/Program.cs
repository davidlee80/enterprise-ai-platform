using EnterpriseAiPlatform.Gateway.Application.Runtime;
using EnterpriseAiPlatform.Gateway.Domain.Runtime;
using EnterpriseAiPlatform.Gateway.Infrastructure;
using Microsoft.Extensions.DependencyInjection;

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

    var readiness = await provider.GetRequiredService<GetRuntimeReadiness>()
        .ExecuteAsync(CancellationToken.None);
    Assert(!readiness.IsReady, "DI_DEFAULT_MUST_FAIL_CLOSED");
    Assert(
        readiness.ReasonCode == "RUNTIME_SNAPSHOT_UNAVAILABLE",
        "DI_DEFAULT_REASON_CODE_INVALID");
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

using (var replacementProvider = replacementServices.BuildServiceProvider(new ServiceProviderOptions
{
    ValidateOnBuild = true,
    ValidateScopes = true
}))
{
    var registrations = replacementProvider.GetServices<IRuntimeReadinessSource>().ToArray();
    Assert(registrations.Length == 1, "DI_REPLACEMENT_REGISTRATION_COUNT_INVALID");
    Assert(ReferenceEquals(registrations[0], fake), "DI_REPLACEMENT_WAS_OVERRIDDEN");

    var readiness = await replacementProvider.GetRequiredService<GetRuntimeReadiness>()
        .ExecuteAsync(CancellationToken.None);
    Assert(readiness.ReasonCode == "TEST_RUNTIME_UNAVAILABLE", "DI_FAKE_NOT_USED");
}

Console.WriteLine(
    "status=pass reason_code=GATEWAY_DDD_DI_RUNTIME_OK container=Microsoft.Extensions.DependencyInjection layers=Domain,Application,Infrastructure,Api");
return 0;

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
