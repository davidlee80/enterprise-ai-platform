using System.Diagnostics;
using EnterpriseAiPlatform.Gateway.Application.Runtime;

namespace EnterpriseAiPlatform.Gateway.Api;

internal static class GatewayEndpoints
{
    internal static WebApplication MapGatewayEndpoints(
        this WebApplication app,
        string serviceName,
        string version)
    {
        app.MapGet("/healthz", () => Results.Json(
            new HealthResponse("live", serviceName, version),
            statusCode: StatusCodes.Status200OK));

        app.MapGet("/readyz", async (
            GetRuntimeReadiness query,
            CancellationToken cancellationToken) =>
        {
            var readiness = await query.ExecuteAsync(cancellationToken);
            return Results.Json(
                new ReadinessResponse(
                    readiness.IsReady ? "ready" : "not_ready",
                    readiness.ReasonCode,
                    readiness.ConfigVersion,
                    readiness.SnapshotAgeSeconds),
                statusCode: readiness.IsReady
                    ? StatusCodes.Status200OK
                    : StatusCodes.Status503ServiceUnavailable);
        });

        app.MapPost("/v1/chat/completions", async (
            HttpContext context,
            GetRuntimeReadiness query,
            ILoggerFactory loggerFactory) =>
        {
            var readiness = await query.ExecuteAsync(context.RequestAborted);
            var logger = loggerFactory.CreateLogger("GatewayRequestLifecycle");
            var traceId = Activity.Current?.TraceId.ToString() ?? "unavailable";

            logger.LogWarning(
                "Gateway request rejected. reason_code={ReasonCode} request_id={RequestId} trace_id={TraceId} config_version={ConfigVersion}",
                readiness.ReasonCode,
                context.TraceIdentifier,
                traceId,
                readiness.ConfigVersion);

            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            context.Response.Headers.CacheControl = "no-store";
            await context.Response.CompleteAsync();
        });

        return app;
    }
}
