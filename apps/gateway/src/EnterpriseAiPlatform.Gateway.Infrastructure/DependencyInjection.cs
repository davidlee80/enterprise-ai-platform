using EnterpriseAiPlatform.Gateway.Application.Policy;
using EnterpriseAiPlatform.Gateway.Application.Routing;
using EnterpriseAiPlatform.Gateway.Application.Runtime;
using EnterpriseAiPlatform.Gateway.Infrastructure.Policy;
using EnterpriseAiPlatform.Gateway.Infrastructure.Runtime;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace EnterpriseAiPlatform.Gateway.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddGatewayInfrastructure(
        this IServiceCollection services,
        OpaPolicyRuntimeOptions? policyRuntimeOptions = null)
    {
        ArgumentNullException.ThrowIfNull(services);

        var opaOptions = policyRuntimeOptions ?? new OpaPolicyRuntimeOptions(OpaPolicyRuntimeOptions.DefaultBaseAddress);
        services.TryAddSingleton(opaOptions);
        services.AddHttpClient<OpaPolicyRuntime>((serviceProvider, client) =>
        {
            var options = serviceProvider.GetRequiredService<OpaPolicyRuntimeOptions>();
            client.BaseAddress = options.BaseAddress;
        });
        services.TryAddTransient<IPolicyRuntime>(serviceProvider =>
            serviceProvider.GetRequiredService<OpaPolicyRuntime>());
        services.TryAddTransient<EvaluatePolicy>();
        services.TryAddTransient<RouterPluginPipeline>();
        services.TryAddSingleton<IRuntimeReadinessSource, UnavailableRuntimeReadinessSource>();
        return services;
    }
}
