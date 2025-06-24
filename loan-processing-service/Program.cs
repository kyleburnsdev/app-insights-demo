using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.ApplicationInsights.Extensibility.Implementation;
using Microsoft.ApplicationInsights.Extensibility.PerfCounterCollector;
using Microsoft.ApplicationInsights.Extensibility.EventCounterCollector;
using System;
using System.Threading.Tasks;

// Create a logger for startup
var loggerFactory = LoggerFactory.Create(builder => {
    builder
        .AddConsole()
        .AddDebug();
});
var startupLogger = loggerFactory.CreateLogger("Startup");

try
{
    startupLogger.LogInformation("Starting Loan Processing Service...");
    
    var builder = WebApplication.CreateBuilder(args);

    // Add Application Insights
    builder.Services.AddApplicationInsightsTelemetry();

    // Add logging
    builder.Logging.AddConsole();
    builder.Logging.AddDebug();
    builder.Logging.AddApplicationInsights();

    // Add services to the container
    builder.Services.AddControllers();

    // Add health checks
    builder.Services.AddHealthChecks();

    startupLogger.LogInformation("Building application...");
    var app = builder.Build();

    // Get application logger
    var logger = app.Services.GetRequiredService<ILogger<Program>>();
    logger.LogInformation("Application built successfully");

    // Configure the HTTP request pipeline
    app.UseRouting();
    app.UseAuthorization();
    app.MapControllers();
    app.MapHealthChecks("/health");

    logger.LogInformation("Loan Processing Service is starting and will continue running...");
    
    // Use RunAsync instead of Run to keep the application running
    await app.RunAsync();
}
catch (Exception ex)
{
    startupLogger.LogError(ex, "Application startup failed with exception: {Message}", ex.Message);
    throw; // Rethrow to ensure non-zero exit code for container
}
