# syntax=docker/dockerfile:1.7

FROM mcr.microsoft.com/dotnet/sdk:10.0.302-noble@sha256:72dd743782f2ae7e5476fd64f6a460045e3998dc862218b80e6944cba79a01b0 AS restore
WORKDIR /src

COPY global.json Directory.Build.props Directory.Packages.props ./
COPY apps/gateway/src/EnterpriseAiPlatform.Gateway.Domain/EnterpriseAiPlatform.Gateway.Domain.csproj apps/gateway/src/EnterpriseAiPlatform.Gateway.Domain/
COPY apps/gateway/src/EnterpriseAiPlatform.Gateway.Domain/packages.lock.json apps/gateway/src/EnterpriseAiPlatform.Gateway.Domain/
COPY apps/gateway/src/EnterpriseAiPlatform.Gateway.Application/EnterpriseAiPlatform.Gateway.Application.csproj apps/gateway/src/EnterpriseAiPlatform.Gateway.Application/
COPY apps/gateway/src/EnterpriseAiPlatform.Gateway.Application/packages.lock.json apps/gateway/src/EnterpriseAiPlatform.Gateway.Application/
COPY apps/gateway/src/EnterpriseAiPlatform.Gateway.Infrastructure/EnterpriseAiPlatform.Gateway.Infrastructure.csproj apps/gateway/src/EnterpriseAiPlatform.Gateway.Infrastructure/
COPY apps/gateway/src/EnterpriseAiPlatform.Gateway.Infrastructure/packages.lock.json apps/gateway/src/EnterpriseAiPlatform.Gateway.Infrastructure/
COPY apps/gateway/src/EnterpriseAiPlatform.Gateway/EnterpriseAiPlatform.Gateway.csproj apps/gateway/src/EnterpriseAiPlatform.Gateway/
COPY apps/gateway/src/EnterpriseAiPlatform.Gateway/packages.lock.json apps/gateway/src/EnterpriseAiPlatform.Gateway/

RUN --mount=type=cache,id=gateway-nuget,target=/root/.nuget/packages,sharing=locked \
    dotnet restore apps/gateway/src/EnterpriseAiPlatform.Gateway/EnterpriseAiPlatform.Gateway.csproj \
      --locked-mode \
      --nologo

FROM restore AS publish
ARG SOURCE_URL
ARG SOURCE_REVISION
ARG SOURCE_VERSION
RUN test -n "$SOURCE_URL" \
    && test -n "$SOURCE_REVISION" \
    && test "$SOURCE_REVISION" != "uncommitted" \
    && test -n "$SOURCE_VERSION"
COPY apps/gateway/src/ apps/gateway/src/
RUN --mount=type=cache,id=gateway-nuget,target=/root/.nuget/packages,sharing=locked \
    dotnet publish apps/gateway/src/EnterpriseAiPlatform.Gateway/EnterpriseAiPlatform.Gateway.csproj \
      --configuration Release \
      --no-restore \
      --output /out \
      --property:UseAppHost=false \
      --property:Version="${SOURCE_VERSION}" \
      --nologo

FROM mcr.microsoft.com/dotnet/aspnet:10.0.10-noble-chiseled-extra@sha256:f9bd6be9b5ab75b8196bff0f0972580edaea7fa8ca04e6ef530950e33caee5b0 AS runtime
ARG SOURCE_URL
ARG SOURCE_REVISION
ARG SOURCE_VERSION
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      org.opencontainers.image.version="${SOURCE_VERSION}"

WORKDIR /app
COPY --from=publish --chown=1654:1654 /out/ ./

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0
EXPOSE 8080
USER 1654:1654

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["dotnet", "EnterpriseAiPlatform.Gateway.dll", "--health-check", "http://127.0.0.1:8080/healthz"]

ENTRYPOINT ["dotnet", "EnterpriseAiPlatform.Gateway.dll"]
