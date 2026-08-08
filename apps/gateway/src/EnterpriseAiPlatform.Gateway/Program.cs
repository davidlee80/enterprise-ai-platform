using System.Reflection;
using EnterpriseAiPlatform.Gateway.Api;
using EnterpriseAiPlatform.Gateway.Application.Runtime;
using EnterpriseAiPlatform.Gateway.Infrastructure;

const string serviceName = "enterprise-ai-platform-gateway";

if (args.Length == 2 &&
    string.Equals(args[0], "--health-check", StringComparison.Ordinal) &&
    Uri.TryCreate(args[1], UriKind.Absolute, out var healthUri))
{
    return await HealthProbe.RunAsync(healthUri);
}

var builder = WebApplication.CreateBuilder(args);
builder.Host.UseDefaultServiceProvider(options =>
{
    options.ValidateOnBuild = true;
    options.ValidateScopes = true;
});
builder.WebHost.ConfigureKestrel(options => options.AddServerHeader = false);
builder.Services.AddSingleton<GetRuntimeReadiness>();
builder.Services.AddGatewayInfrastructure();
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
var startupReadiness = await app.Services
    .GetRequiredService<GetRuntimeReadiness>()
    .ExecuteAsync(CancellationToken.None);

app.MapGatewayEndpoints(serviceName, version);

app.Logger.LogInformation(
    "Gateway runtime starting. service={Service} version={Version} readiness={Readiness} readiness_reason_code={ReasonCode} config_version={ConfigVersion}",
    serviceName,
    version,
    startupReadiness.IsReady ? "ready" : "not_ready",
    startupReadiness.ReasonCode,
    startupReadiness.ConfigVersion);

await app.RunAsync();
return 0;

public partial class Program
{
}
