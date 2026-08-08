using System.Net;

namespace EnterpriseAiPlatform.Gateway.Api;

internal static class HealthProbe
{
    internal static async Task<int> RunAsync(Uri healthUri)
    {
        if (!healthUri.IsLoopback ||
            !string.Equals(healthUri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine(
                "status=fail reason_code=HEALTH_PROBE_TARGET_INVALID detail=only loopback HTTP targets are allowed");
            return 2;
        }

        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(2)
        };

        try
        {
            using var response = await client.GetAsync(healthUri, HttpCompletionOption.ResponseHeadersRead);
            if (response.StatusCode == HttpStatusCode.OK)
            {
                return 0;
            }

            Console.Error.WriteLine(
                $"status=fail reason_code=HEALTH_PROBE_UNHEALTHY http_status={(int)response.StatusCode}");
            return 1;
        }
        catch (Exception exception) when (
            exception is HttpRequestException or TaskCanceledException)
        {
            Console.Error.WriteLine(
                $"status=fail reason_code=HEALTH_PROBE_UNREACHABLE error_type={exception.GetType().Name}");
            return 1;
        }
    }
}
