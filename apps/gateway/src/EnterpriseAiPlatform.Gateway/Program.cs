using System.Diagnostics;
using System.Net;
using System.Reflection;
using System.Text.Json.Serialization;

const string serviceName = "enterprise-ai-platform-gateway";
const string unavailableReason = "RUNTIME_SNAPSHOT_UNAVAILABLE";

if (args.Length == 2 &&
    string.Equals(args[0], "--health-check", StringComparison.Ordinal) &&
    Uri.TryCreate(args[1], UriKind.Absolute, out var healthUri))
{
    return await HealthProbe.RunAsync(healthUri);
}

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(options => options.AddServerHeader = false);
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole(options =>
{
    options.IncludeScopes = true;
    options.TimestampFormat = "yyyy-MM-ddTHH:mm:ss.fffZ";
    options.UseUtcTimestamp = true;
});

var app = builder.Build();
var version = typeof(Program).Assembly
    .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
    .InformationalVersion.Split('+', 2)[0] ?? "unknown";

app.MapGet("/healthz", () => Results.Json(
    new HealthResponse("live", serviceName, version),
    statusCode: StatusCodes.Status200OK));

app.MapGet("/readyz", () => Results.Json(
    new ReadinessResponse(
        "not_ready",
        unavailableReason,
        ConfigVersion: null,
        SnapshotAgeSeconds: null),
    statusCode: StatusCodes.Status503ServiceUnavailable));

app.MapPost("/v1/chat/completions", async (HttpContext context) =>
{
    var logger = context.RequestServices
        .GetRequiredService<ILoggerFactory>()
        .CreateLogger("GatewayRequestLifecycle");
    var traceId = Activity.Current?.TraceId.ToString() ?? "unavailable";

    logger.LogWarning(
        "Gateway request rejected. reason_code={ReasonCode} request_id={RequestId} trace_id={TraceId} config_version={ConfigVersion}",
        unavailableReason,
        context.TraceIdentifier,
        traceId,
        null);

    context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
    context.Response.Headers.CacheControl = "no-store";
    await context.Response.CompleteAsync();
});

app.Logger.LogInformation(
    "Gateway runtime starting. service={Service} version={Version} readiness_reason_code={ReasonCode}",
    serviceName,
    version,
    unavailableReason);

await app.RunAsync();
return 0;

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

internal sealed record HealthResponse(
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("service")] string Service,
    [property: JsonPropertyName("version")] string Version);

internal sealed record ReadinessResponse(
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("reason_code")] string ReasonCode,
    [property: JsonPropertyName("config_version")] long? ConfigVersion,
    [property: JsonPropertyName("snapshot_age_seconds")] long? SnapshotAgeSeconds);

public partial class Program
{
}
