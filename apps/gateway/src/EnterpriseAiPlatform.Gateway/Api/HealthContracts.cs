using System.Text.Json.Serialization;

namespace EnterpriseAiPlatform.Gateway.Api;

internal sealed record HealthResponse(
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("service")] string Service,
    [property: JsonPropertyName("version")] string Version);

internal sealed record ReadinessResponse(
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("reason_code")] string ReasonCode,
    [property: JsonPropertyName("config_version")] long? ConfigVersion,
    [property: JsonPropertyName("snapshot_age_seconds")] double? SnapshotAgeSeconds);
