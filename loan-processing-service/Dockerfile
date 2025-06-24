# Stage 1: Restore dependencies only when csproj changes
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS deps
WORKDIR /src
COPY LoanProcessingService.csproj ./
RUN dotnet restore --runtime linux-x64

# Stage 2: Build the application
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY --from=deps /src/obj ./obj
COPY . .
RUN dotnet publish -c Release -o /app/publish --runtime linux-x64 --self-contained true -p:PublishReadyToRun=true /p:PublishSingleFile=true /p:IncludeAllContentForSelfExtract=true

# Stage 3: Final runtime image
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["./LoanProcessingService"]
