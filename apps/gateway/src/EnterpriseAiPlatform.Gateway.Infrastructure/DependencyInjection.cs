using EnterpriseAiPlatform.Gateway.Application.Runtime;
using EnterpriseAiPlatform.Gateway.Infrastructure.Runtime;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace EnterpriseAiPlatform.Gateway.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddGatewayInfrastructure(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IRuntimeReadinessSource, UnavailableRuntimeReadinessSource>();
        return services;
    }
}
