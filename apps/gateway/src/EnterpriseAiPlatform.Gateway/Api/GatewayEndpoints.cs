using System.Diagnostics;
using System.Text.Json;
using EnterpriseAiPlatform.Gateway.Application.Invocation;
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
            GatewayRequestPipeline pipeline,
            ILoggerFactory loggerFactory) =>
        {
            var logger = loggerFactory.CreateLogger("GatewayRequestLifecycle");
            var traceId = Activity.Current?.TraceId.ToString() ?? "unavailable";
            var requestId = context.TraceIdentifier;

            byte[] body;
            string? modelAlias;
            try
            {
                using var buffer = new MemoryStream();
                await context.Request.Body.CopyToAsync(buffer, context.RequestAborted);
                body = buffer.ToArray();
                using var document = JsonDocument.Parse(body);
                var root = document.RootElement;
                modelAlias = root.ValueKind == JsonValueKind.Object &&
                    root.TryGetProperty("model", out var model) &&
                    model.ValueKind == JsonValueKind.String
                        ? model.GetString()
                        : null;
                var messagesValid = root.ValueKind == JsonValueKind.Object &&
                    root.TryGetProperty("messages", out var messages) &&
                    messages.ValueKind == JsonValueKind.Array &&
                    messages.GetArrayLength() > 0;
                if (string.IsNullOrWhiteSpace(modelAlias) || !messagesValid)
                {
                    throw new JsonException("Required request fields are invalid.");
                }
            }
            catch (JsonException)
            {
                logger.LogWarning(
                    "Gateway request rejected. reason_code={ReasonCode} request_id={RequestId} trace_id={TraceId}",
                    "REQUEST_SCHEMA_INVALID",
                    requestId,
                    traceId);
                context.Response.StatusCode = StatusCodes.Status400BadRequest;
                context.Response.Headers.CacheControl = "no-store";
                await context.Response.CompleteAsync();
                return;
            }

            var result = await pipeline.ExecuteAsync(
                new GatewayInvocationRequest(
                    requestId,
                    traceId,
                    modelAlias!,
                    body,
                    context.Request.Headers.Authorization.ToString()),
                context.RequestAborted);

            var statusCode = result.Outcome switch
            {
                GatewayInvocationOutcome.Succeeded => StatusCodes.Status200OK,
                GatewayInvocationOutcome.Unauthorized => StatusCodes.Status401Unauthorized,
                GatewayInvocationOutcome.Forbidden => StatusCodes.Status403Forbidden,
                GatewayInvocationOutcome.ProviderFailure => StatusCodes.Status502BadGateway,
                _ => StatusCodes.Status503ServiceUnavailable
            };

            logger.Log(
                result.Outcome == GatewayInvocationOutcome.Succeeded
                    ? LogLevel.Information
                    : LogLevel.Warning,
                "Gateway request completed. reason_code={ReasonCode} request_id={RequestId} trace_id={TraceId} tenant_id={TenantId} config_version={ConfigVersion} model={ModelAlias} provider={ProviderId} attempt_count={AttemptCount} usage_outcome={UsageOutcome} usage_reason_code={UsageReasonCode}",
                result.ReasonCode,
                requestId,
                traceId,
                result.TenantId,
                result.ConfigVersion,
                result.ModelAlias,
                result.ProviderId,
                result.AttemptCount,
                result.UsageOutcome,
                result.UsageReasonCode);

            context.Response.StatusCode = statusCode;
            context.Response.Headers.CacheControl = "no-store";
            if (result.Outcome == GatewayInvocationOutcome.Succeeded)
            {
                context.Response.ContentType = result.ResponseMediaType ?? "application/json";
                await context.Response.Body.WriteAsync(result.ResponseBody, context.RequestAborted);
            }
            else
            {
                await context.Response.CompleteAsync();
            }
        });

        return app;
    }
}
