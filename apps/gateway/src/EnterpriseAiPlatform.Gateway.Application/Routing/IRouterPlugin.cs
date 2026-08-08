using EnterpriseAiPlatform.Gateway.Domain.Contracts;
using EnterpriseAiPlatform.Gateway.Domain.Routing;

namespace EnterpriseAiPlatform.Gateway.Application.Routing;

public interface IRouterPlugin
{
    string PluginId { get; }

    ContractVersion PluginVersion { get; }

    ValueTask<RouterPluginResult> RouteAsync(
        RouterPluginContext context,
        CancellationToken cancellationToken);
}
