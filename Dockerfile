# The cmdemo1 AI Software Factory: one container, listening on 8080, health at /health.
#
# The Aisf.* packages are on a private feed. Pass a token with read:packages as a build secret;
# it is used for the restore only and is not kept in any image layer:
#   docker build --secret id=aisf_packages_token,env=AISF_PACKAGES_TOKEN -t cmdemo1-aisf .
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY NuGet.Config Factory.csproj ./
RUN --mount=type=secret,id=aisf_packages_token \
    NuGetPackageSourceCredentials_aisf="Username=aisf;Password=$(cat /run/secrets/aisf_packages_token)" \
    dotnet restore Factory.csproj
COPY . .
RUN dotnet publish Factory.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app/publish .
# Queues, saga data and the cache go under one directory the non-root user owns.
ENV ASPNETCORE_HTTP_PORTS=8080 \
    Factory__DataDirectory=/home/app/factory-data
EXPOSE 8080
USER $APP_UID
ENTRYPOINT ["dotnet", "Cmdemo1.Factory.dll"]
