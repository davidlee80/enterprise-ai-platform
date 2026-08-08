namespace EnterpriseAiPlatform.Gateway.Domain.Contracts;

public readonly record struct ContractVersion
{
    private ContractVersion(long? number, string? text)
    {
        Number = number;
        Text = text;
    }

    public long? Number { get; }

    public string? Text { get; }

    public bool IsNumber => Number.HasValue;

    public bool IsInitialized => Number.HasValue || Text is not null;

    public static ContractVersion FromNumber(long value)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(value, 1);
        return new ContractVersion(value, null);
    }

    public static ContractVersion FromText(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        return new ContractVersion(null, value);
    }

    public override string ToString() => IsNumber
        ? Number!.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)
        : Text ?? throw new InvalidOperationException("Contract version is not initialized.");

    public void EnsureInitialized(string parameterName)
    {
        if (!IsInitialized)
        {
            throw new ArgumentException("Contract version is not initialized.", parameterName);
        }
    }
}
