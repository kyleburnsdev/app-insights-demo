using Microsoft.ApplicationInsights;
using Microsoft.ApplicationInsights.DataContracts;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Logging;
using System.Data;
using Azure.Identity;
using Azure.Storage.Blobs;
using Polly;
using Polly.CircuitBreaker;
using Polly.Retry;

namespace LoanProcessingService.Controllers
{
    [ApiController]
    [Route("api/[controller]")]    public class LoansController : ControllerBase
    {
        private readonly IConfiguration _config;
        private readonly TelemetryClient _telemetryClient;
        private readonly ILogger<LoansController> _logger;
        
        public LoansController(IConfiguration config, TelemetryClient telemetryClient, ILogger<LoansController> logger)
        {
            _config = config;
            _telemetryClient = telemetryClient;
            _logger = logger;
        }

        // Define Polly policies
        private static readonly AsyncCircuitBreakerPolicy circuitBreakerPolicy = Policy
            .Handle<Exception>()
            .CircuitBreakerAsync(3, TimeSpan.FromSeconds(30));
        private static readonly AsyncRetryPolicy retryPolicy = Policy
            .Handle<Exception>()
            .WaitAndRetryAsync(3, retryAttempt => TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)));

        // Intentional N+1 query flaw: Fetches all loans, then fetches customer for each loan separately        [HttpGet]
        public async Task<IActionResult> GetLoans()
        {
            var loans = new List<object>();
            string? connStr = _config.GetConnectionString("DefaultConnection");
            
            if (string.IsNullOrEmpty(connStr))
            {
                _logger.LogError("Database connection string is null or empty");
                return StatusCode(500, new { error = "Database configuration error" });
            }
            
            string userId = HttpContext.User?.Identity?.Name ?? HttpContext.Request.Headers["X-User-Id"].FirstOrDefault() ?? "anonymous";
            string correlationId = HttpContext.Request.Headers["Request-Id"].FirstOrDefault() ?? HttpContext.TraceIdentifier;
            
            _logger.LogInformation("Processing loan lookup request for user {UserId} with correlation ID {CorrelationId}", userId, correlationId);
            _telemetryClient.TrackEvent("LoanLookupRequested", new Dictionary<string, string> { { "userId", userId }, { "correlationId", correlationId } });
            
            try
            {
                _logger.LogDebug("Attempting to retrieve loans from database");
                
                await circuitBreakerPolicy.ExecuteAsync(async () =>
                {
                    await retryPolicy.ExecuteAsync(async () =>
                    {
                        _logger.LogDebug("Opening database connection");
                        using (var conn = new SqlConnection(connStr))
                        {
                            await conn.OpenAsync();
                            _logger.LogDebug("Database connection opened successfully");
                            
                            var cmd = new SqlCommand("SELECT LoanId, CustomerId, Amount, Status FROM Loans", conn);
                            using (var reader = await cmd.ExecuteReaderAsync())
                            {
                                _logger.LogDebug("Executing SQL query to retrieve loans");
                                int loanCount = 0;
                                
                                while (await reader.ReadAsync())
                                {
                                    var loanId = reader.GetInt32(0);
                                    var customerId = reader.GetInt32(1);
                                    var amount = reader.GetDecimal(2);
                                    var status = reader.GetString(3);
                                    
                                    _logger.LogDebug("Retrieved loan {LoanId} for customer {CustomerId}", loanId, customerId);

                                    // N+1 query: fetch customer for each loan
                                    var customer = await GetCustomerById(conn, customerId);
                                    loans.Add(new { loanId, customer, amount, status });
                                    loanCount++;
                                }
                                
                                _logger.LogInformation("Retrieved {LoanCount} loans from database", loanCount);
                            }
                        }
                    });
                });
                
                _logger.LogInformation("Loan lookup completed successfully for user {UserId}", userId);
                _telemetryClient.TrackEvent("LoanLookupSuccess", new Dictionary<string, string> { { "userId", userId }, { "correlationId", correlationId } });
                _telemetryClient.GetMetric("LoanLookupSuccess").TrackValue(1);
                return Ok(loans);
            }
            catch (SqlException sqlEx)
            {
                _logger.LogError(sqlEx, "SQL exception occurred during loan lookup: {ErrorMessage}", sqlEx.Message);
                _telemetryClient.TrackEvent("LoanLookupSqlError", new Dictionary<string, string> { { "userId", userId }, { "correlationId", correlationId }, { "error", sqlEx.Message }, { "sqlErrorNumber", sqlEx.Number.ToString() } });
                _telemetryClient.GetMetric("LoanLookupError").TrackValue(1);
                _telemetryClient.TrackException(sqlEx);
                return StatusCode(500, new { error = "Database error occurred", details = sqlEx.Message });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Exception occurred during loan lookup: {ErrorMessage}", ex.Message);
                _telemetryClient.TrackEvent("LoanLookupError", new Dictionary<string, string> { { "userId", userId }, { "correlationId", correlationId }, { "error", ex.Message } });
                _telemetryClient.GetMetric("LoanLookupError").TrackValue(1);
                _telemetryClient.TrackException(ex);
                return StatusCode(500, new { error = "An unexpected error occurred", details = ex.Message });
            }
        }        private async Task<object?> GetCustomerById(SqlConnection conn, int customerId)
        {
            _logger.LogDebug("Getting customer information for customer ID {CustomerId}", customerId);
            
            var cmd = new SqlCommand("SELECT FirstName, LastName, Email FROM Customers WHERE CustomerId = @id", conn);
            cmd.Parameters.AddWithValue("@id", customerId);
            
            try
            {
                using (var reader = await cmd.ExecuteReaderAsync())
                {
                    if (await reader.ReadAsync())
                    {
                        var firstName = reader.GetString(0);
                        var lastName = reader.GetString(1);
                        var email = reader.GetString(2);
                        
                        _logger.LogDebug("Found customer {FirstName} {LastName} with email {Email}", firstName, lastName, email);
                        
                        return new
                        {
                            firstName,
                            lastName,
                            email
                        };
                    }
                }
                
                _logger.LogWarning("Customer with ID {CustomerId} not found", customerId);
                return new { firstName = "Unknown", lastName = "Customer", email = "" };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving customer {CustomerId}: {ErrorMessage}", customerId, ex.Message);
                return new { firstName = "Error", lastName = "Retrieving", email = "" };
            }
        }

        public void ConfigureServices(IServiceCollection services)
        {
            // ...existing code...
            services.AddHealthChecks()
                .AddCheck("sql", () =>
                {
                    try
                    {
                        var sqlServer = Environment.GetEnvironmentVariable("SQL_SERVER_NAME");
                        var dbName = Environment.GetEnvironmentVariable("SQL_DATABASE_NAME");
                        var connStr = $"Server=tcp:{sqlServer}.database.windows.net,1433;Database={dbName};Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;";
                        using var conn = new SqlConnection(connStr)
                        {
                            AccessToken = (new DefaultAzureCredential()).GetToken(
                                new Azure.Core.TokenRequestContext(new[] { "https://database.windows.net//.default" })
                            ).Token
                        };
                        conn.Open();
                        return HealthCheckResult.Healthy();
                    }
                    catch
                    {
                        return HealthCheckResult.Unhealthy();
                    }
                }, tags: new[] { "ready" })
                .AddCheck("blob", () =>
                {
                    try
                    {
                        var storageAccount = Environment.GetEnvironmentVariable("STORAGE_ACCOUNT_NAME");
                        var blobUri = $"https://{storageAccount}.blob.core.windows.net/";
                        var client = new BlobServiceClient(new Uri(blobUri), new DefaultAzureCredential());
                        client.GetProperties();
                        return HealthCheckResult.Healthy();
                    }
                    catch
                    {
                        return HealthCheckResult.Unhealthy();
                    }
                }, tags: new[] { "ready" });
        }

        public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
        {
            // ...existing code...
            app.UseHealthChecks("/health/live", new HealthCheckOptions
            {
                Predicate = _ => false,
                ResponseWriter = async (context, report) =>
                {
                    await context.Response.WriteAsync("Healthy");
                }
            });
            app.UseHealthChecks("/health/ready", new HealthCheckOptions
            {
                Predicate = check => check.Tags.Contains("ready")
            });
            // ...existing code...
        }
    }
}