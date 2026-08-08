namespace EnterpriseAiPlatform.Gateway.Infrastructure.Policy;

public sealed record OpaPolicyRuntimeOptions
{
    public static readonly Uri DefaultBaseAddress = new("http://127.0.0.1:8181/", UriKind.Absolute);
    public const string DefaultDecisionPath = "v1/data/enterprise_ai/gateway/decision";

    public OpaPolicyRuntimeOptions(Uri baseAddress, string decisionPath = DefaultDecisionPath)
    {
        ArgumentNullException.ThrowIfNull(baseAddress);
        ArgumentException.ThrowIfNullOrWhiteSpace(decisionPath);
        if (!baseAddress.IsAbsoluteUri || !baseAddress.IsLoopback ||
            !string.Equals(baseAddress.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) ||
            !string.IsNullOrEmpty(baseAddress.UserInfo) ||
            !string.IsNullOrEmpty(baseAddress.Query) ||
            !string.IsNullOrEmpty(baseAddress.Fragment))
        {
            throw new ArgumentException(
                "OPA must use an unauthenticated loopback HTTP sidecar address.",
                nameof(baseAddress));
        }

        if (decisionPath.StartsWith("/", StringComparison.Ordinal) ||
            decisionPath.Contains('?') ||
            decisionPath.Contains('#') ||
            decisionPath.Contains("..", StringComparison.Ordinal))
        {
            throw new ArgumentException("OPA decision path must be a relative Data API path.", nameof(decisionPath));
        }

        BaseAddress = baseAddress;
        DecisionPath = decisionPath;
    }

    public Uri BaseAddress { get; }
    public string DecisionPath { get; }
}
