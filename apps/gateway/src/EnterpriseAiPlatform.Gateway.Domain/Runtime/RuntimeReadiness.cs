namespace EnterpriseAiPlatform.Gateway.Domain.Runtime;

public sealed class RuntimeReadiness
{
    public RuntimeReadiness(
        bool isReady,
        string reasonCode,
        long? configVersion,
        double? snapshotAgeSeconds)
    {
        if (string.IsNullOrWhiteSpace(reasonCode))
        {
            throw new ArgumentException("A structured reason code is required.", nameof(reasonCode));
        }

        if (configVersion is < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(configVersion));
        }

        if (snapshotAgeSeconds is < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(snapshotAgeSeconds));
        }

        if (isReady && (configVersion is null || snapshotAgeSeconds is null))
        {
            throw new ArgumentException(
                "A ready runtime must identify its configuration version and snapshot age.",
                nameof(isReady));
        }

        IsReady = isReady;
        ReasonCode = reasonCode;
        ConfigVersion = configVersion;
        SnapshotAgeSeconds = snapshotAgeSeconds;
    }

    public bool IsReady { get; }

    public string ReasonCode { get; }

    public long? ConfigVersion { get; }

    public double? SnapshotAgeSeconds { get; }
}
