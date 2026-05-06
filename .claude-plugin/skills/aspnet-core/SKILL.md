---
name: aspnet-core
description: |
  ASP.NET Core (.NET 10) best practices. Covers endpoint definitions via Minimal APIs (`app.MapGet` / `MapGroup` / `RouteGroupBuilder`), DI (Scoped / Singleton / Transient + `IOptions<T>` / `IOptionsMonitor<T>`), middleware pipeline order (Exception Handler -> HSTS -> HTTPS Redirection -> CORS -> Authn -> Authz -> Routing -> Endpoints), `IMiddleware` / convention-based custom middleware, type-safe responses via `TypedResults` and `Results<T1,T2>`, ProblemDetails (RFC 9457), centralized error handling via `IExceptionHandler`, JwtBearer authentication + `AuthorizationBuilder` policy, `WebApplicationFactory<Program>` integration tests, and graceful shutdown (`IHostApplicationLifetime` / `BackgroundService`). Reference when adding ASP.NET Core endpoints, configuring DI, implementing middleware, implementing authentication/authorization, or writing integration tests. Triggers on: 'aspnet core', 'minimal api', 'add endpoint', 'configure DI', 'implement middleware', 'integration test', 'ASP.NET Core エンドポイント追加', 'DI 設定', 'middleware 実装', '認証・認可実装', '統合テスト'.
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# ASP.NET Core Best Practices (.NET 10)

## Scope

- Adding Minimal API endpoints and grouping with `MapGroup`
- DI configuration (Scoped / Singleton / Transient) and use of `IOptions<T>` / `IOptionsMonitor<T>`
- Building the middleware pipeline (`UseExceptionHandler`, `UseAuthentication` / `UseAuthorization`, etc.)
- Implementing custom middleware (`IMiddleware` / convention-based)
- Type-safe responses via `TypedResults` and `ProblemDetails`
- Centralized error handling via `IExceptionHandler`
- JwtBearer authentication + `AuthorizationBuilder` policy
- Integration tests using `WebApplicationFactory<Program>`
- Graceful shutdown via `IHostApplicationLifetime` / `BackgroundService`

## Out of Scope

- EF Core queries and DbContext -> `entity-framework-core` Skill
- Blazor components -> `blazor` Skill
- Project configuration -> `csproj` Skill
- C# code style -> `csharp-style` Rule

## Endpoint Configuration

- Use Minimal APIs with `app.MapGet()`, `app.MapPost()`, `app.MapPut()`, `app.MapDelete()` for concise endpoint definitions
- Group related routes with `MapGroup()` and `RouteGroupBuilder` to share prefixes, filters, and metadata
- Organize endpoints into static extension methods (e.g., `MapUserEndpoints()`) to keep `Program.cs` clean
- Use controller-based pattern (`[ApiController]`) only for large APIs with complex model binding, versioning, or when OpenAPI generation benefits from controller conventions
- Prefer Minimal APIs for microservices, lightweight APIs, and new projects on .NET 10

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Register endpoints via extension methods
app.MapUserEndpoints();
app.MapOrderEndpoints();

app.Run();
```

```csharp
// Endpoints/UserEndpoints.cs
public static class UserEndpoints
{
    public static void MapUserEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/users")
            .WithTags("Users")
            .RequireAuthorization();

        group.MapGet("/", GetAllUsers);
        group.MapGet("/{id:int}", GetUserById);
        group.MapPost("/", CreateUser);
        group.MapPut("/{id:int}", UpdateUser);
        group.MapDelete("/{id:int}", DeleteUser);
    }

    private static async Task<Results<Ok<List<UserDto>>, ProblemHttpResult>>
        GetAllUsers(IUserRepository repo) { /* ... */ }

    private static async Task<Results<Ok<UserDto>, NotFound, ProblemHttpResult>>
        GetUserById(int id, IUserRepository repo) { /* ... */ }

    private static async Task<Results<Created<UserDto>, ValidationProblem>>
        CreateUser(CreateUserRequest request, IUserRepository repo) { /* ... */ }
}
```

```csharp
// Sharing filters via RouteGroupBuilder
var api = app.MapGroup("/api")
    .AddEndpointFilter<ApiKeyFilter>();

var v1 = api.MapGroup("/v1");
var v2 = api.MapGroup("/v2");

v1.MapGet("/items", GetItemsV1);
v2.MapGet("/items", GetItemsV2);
```

## Dependency Injection

- Register all services in `Program.cs` using `builder.Services`
- Use **Scoped** for per-request services (DbContext, repositories, unit-of-work)
- Use **Singleton** for shared, thread-safe services (configuration, caches, `HttpClient` factories)
- Use **Transient** for lightweight, stateless services
- Prefer constructor injection. Avoid the service locator pattern (`IServiceProvider.GetService<T>()`)
- Use `IOptions<T>` for static configuration, `IOptionsSnapshot<T>` for per-request reload, and `IOptionsMonitor<T>` for runtime change notifications

```csharp
// Program.cs - service registration
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Default")));

builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<IOrderService, OrderService>();

builder.Services.AddSingleton<ICacheService, RedisCacheService>();
builder.Services.AddSingleton<IEmailSender, SmtpEmailSender>();

builder.Services.AddHttpClient<IGitHubClient, GitHubClient>(client =>
{
    client.BaseAddress = new Uri("https://api.github.com");
    client.DefaultRequestHeaders.UserAgent.ParseAdd("MyApp/1.0");
});

// Configuration binding
builder.Services.Configure<JwtSettings>(
    builder.Configuration.GetSection("Jwt"));
builder.Services.Configure<SmtpSettings>(
    builder.Configuration.GetSection("Smtp"));
```

```csharp
// Example using IOptions<T>
public class TokenService(IOptions<JwtSettings> jwtOptions)
{
    private readonly JwtSettings _settings = jwtOptions.Value;

    public string GenerateToken(User user) { /* _settings.SecretKey, _settings.Issuer ... */ }
}

// IOptionsMonitor<T> - watch for runtime configuration changes
public class FeatureFlagService(IOptionsMonitor<FeatureFlags> monitor)
{
    public bool IsEnabled(string flag) => monitor.CurrentValue.EnabledFlags.Contains(flag);
}
```

## Middleware Pipeline

- **Order matters**: Exception handling → HSTS → HTTPS Redirection → CORS → Authentication → Authorization → Routing → Endpoints
- Use `app.UseExceptionHandler()` for global error handling (must be first)
- Implement custom middleware with the `IMiddleware` interface (DI-friendly) or convention-based pattern
- Use `app.UseStatusCodePages()` alongside `ProblemDetails` for consistent error responses

```csharp
// Program.cs - correct middleware pipeline order
var app = builder.Build();

// 1. Exception handling (place first)
app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// 2. HTTPS and security headers
app.UseHsts();
app.UseHttpsRedirection();

// 3. CORS
app.UseCors("AllowFrontend");

// 4. Authentication and authorization
app.UseAuthentication();
app.UseAuthorization();

// 5. Endpoints
app.MapUserEndpoints();
app.MapOrderEndpoints();

app.Run();
```

```csharp
// Custom middleware (IMiddleware interface style - DI-friendly)
public class RequestTimingMiddleware(ILogger<RequestTimingMiddleware> logger) : IMiddleware
{
    public async Task InvokeAsync(HttpContext context, RequestDelegate next)
    {
        var stopwatch = Stopwatch.StartNew();
        await next(context);
        stopwatch.Stop();

        logger.LogInformation(
            "Request {Method} {Path} completed in {Elapsed}ms",
            context.Request.Method,
            context.Request.Path,
            stopwatch.ElapsedMilliseconds);
    }
}

// Registration
builder.Services.AddTransient<RequestTimingMiddleware>();
app.UseMiddleware<RequestTimingMiddleware>();
```

```csharp
// Custom middleware (convention-based style)
public class CorrelationIdMiddleware(RequestDelegate next, ILogger<CorrelationIdMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = context.Request.Headers["X-Correlation-Id"].FirstOrDefault()
            ?? Guid.NewGuid().ToString();
        context.Response.Headers["X-Correlation-Id"] = correlationId;

        using (logger.BeginScope(new Dictionary<string, object>
            { ["CorrelationId"] = correlationId }))
        {
            await next(context);
        }
    }
}
```

## Request/Response Patterns

- Use `TypedResults` for compile-time type-safe responses in Minimal APIs
- Use `Results<T1, T2, ...>` union return types so OpenAPI schema generation is accurate
- Return `ProblemDetails` (RFC 9457) for all error responses
- Use `[FromBody]`, `[FromQuery]`, `[FromRoute]`, `[FromHeader]` for explicit model binding
- Apply `[ApiController]` on controllers for automatic model validation (returns `ValidationProblem` on invalid input)

```csharp
// Type-safe responses via TypedResults
app.MapGet("/api/users/{id:int}", async Task<Results<Ok<UserDto>, NotFound, ProblemHttpResult>>
    (int id, IUserRepository repo) =>
{
    var user = await repo.FindByIdAsync(id);
    if (user is null)
        return TypedResults.NotFound();

    return TypedResults.Ok(user.ToDto());
});

app.MapPost("/api/users", async Task<Results<Created<UserDto>, ValidationProblem>>
    (CreateUserRequest request, IValidator<CreateUserRequest> validator, IUserRepository repo) =>
{
    var result = await validator.ValidateAsync(request);
    if (!result.IsValid)
        return TypedResults.ValidationProblem(result.ToDictionary());

    var user = await repo.CreateAsync(request);
    return TypedResults.Created($"/api/users/{user.Id}", user.ToDto());
});
```

```csharp
// Registering ProblemDetails services (.NET 10)
builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = context =>
    {
        context.ProblemDetails.Extensions["traceId"] =
            Activity.Current?.Id ?? context.HttpContext.TraceIdentifier;
    };
});
```

## Error Handling

- Register `ProblemDetails` services and use `app.UseExceptionHandler()` for global error handling
- Implement a unified error type or use `IExceptionHandler` (introduced in .NET 8+) for centralized exception-to-response mapping
- Return `ProblemDetails` for machine-readable error responses on all non-success paths
- Never leak internal exception details to clients in production

```csharp
// Centralized error handling via IExceptionHandler (.NET 10 recommended pattern)
public class GlobalExceptionHandler(
    ILogger<GlobalExceptionHandler> logger,
    IProblemDetailsService problemDetailsService) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        logger.LogError(exception, "Unhandled exception occurred: {Message}", exception.Message);

        var (statusCode, title) = exception switch
        {
            NotFoundException => (StatusCodes.Status404NotFound, "Resource not found"),
            ValidationException => (StatusCodes.Status400BadRequest, "Validation error"),
            UnauthorizedAccessException => (StatusCodes.Status403Forbidden, "Access denied"),
            _ => (StatusCodes.Status500InternalServerError, "Internal server error")
        };

        httpContext.Response.StatusCode = statusCode;

        return await problemDetailsService.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails =
            {
                Title = title,
                Status = statusCode,
                // Hide exception details in production environments (prevent information leakage)
                Detail = httpContext.RequestServices.GetRequiredService<IHostEnvironment>().IsDevelopment()
                    ? exception.Message : null
            }
        });
    }
}

// Registration
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddProblemDetails();

app.UseExceptionHandler();
```

```csharp
// Custom exception type definitions
public abstract class AppException(string message, int statusCode) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}

public class NotFoundException(string resource, object id)
    : AppException($"{resource} (ID: {id}) was not found", 404);

public class ConflictException(string message)
    : AppException(message, 409);
```

## Authentication & Authorization

- Use `builder.Services.AddAuthentication().AddJwtBearer()` for JWT-based API auth
- Define named policies with `AddAuthorizationBuilder()` for role-based and claim-based rules
- Implement `IAuthorizationHandler` for complex, data-dependent authorization logic
- Apply authorization at the endpoint level with `RequireAuthorization()` or `[Authorize]`

```csharp
// Program.cs - authentication and authorization configuration
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Key"]!))
        };
    });

builder.Services.AddAuthorizationBuilder()
    .AddPolicy("AdminOnly", policy => policy.RequireRole("Admin"))
    .AddPolicy("CanEditUser", policy =>
        policy.Requirements.Add(new UserEditRequirement()));

builder.Services.AddScoped<IAuthorizationHandler, UserEditAuthorizationHandler>();
```

```csharp
// Custom authorization handler
public class UserEditRequirement : IAuthorizationRequirement { }

public class UserEditAuthorizationHandler(IUserRepository repo)
    : AuthorizationHandler<UserEditRequirement, int>
{
    protected override async Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        UserEditRequirement requirement,
        int userId)
    {
        var currentUserId = int.Parse(
            context.User.FindFirstValue(ClaimTypes.NameIdentifier)!);

        // Allow only the user themselves or administrators
        if (currentUserId == userId || context.User.IsInRole("Admin"))
        {
            context.Succeed(requirement);
        }
    }
}
```

```csharp
// Applying authorization policies to endpoints
app.MapDelete("/api/users/{id:int}", DeleteUser)
    .RequireAuthorization("AdminOnly");

app.MapPut("/api/users/{id:int}", UpdateUser)
    .RequireAuthorization("CanEditUser");

// Public endpoint requiring no authorization
app.MapGet("/api/health", () => TypedResults.Ok("Healthy"))
    .AllowAnonymous();
```

## Testing

- Use `WebApplicationFactory<Program>` for integration tests that spin up a real test server
- Override services (e.g., swap DB for in-memory, mock external APIs) with `WithWebHostBuilder`
- Use the built-in `HttpClient` from the factory for sending test requests
- Use WireMock.NET to stub external HTTP dependencies
- Make `Program` accessible to tests by adding `InternalsVisibleTo` or a partial class marker

```csharp
// Marker to make Program accessible from the test project (end of Program.cs)
public partial class Program;
```

```csharp
// Custom factory for integration tests
public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Swap the production DbContext for a Testcontainers DB used in tests
            // Note: do not use InMemory DB for integration tests (its behavior diverges from real DBs)
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<AppDbContext>));
            if (descriptor is not null)
                services.Remove(descriptor);

            services.AddDbContext<AppDbContext>(options =>
                options.UseNpgsql(TestDatabaseContainer.ConnectionString));

            // Swap external services for mocks
            services.AddScoped<IEmailSender, FakeEmailSender>();
        });

        builder.UseEnvironment("Testing");
    }
}
```

```csharp
// Integration test example
public class UserEndpointsTests(CustomWebApplicationFactory factory)
    : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client = factory.CreateClient();

    [Fact]
    public async Task GetUser_ExistingUser_Returns200OK()
    {
        // Arrange - prepare test data
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.Users.Add(new User { Id = 1, Name = "Test User" });
        await db.SaveChangesAsync();

        // Act
        var response = await _client.GetAsync("/api/users/1");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var user = await response.Content.ReadFromJsonAsync<UserDto>();
        user!.Name.Should().Be("Test User");
    }

    [Fact]
    public async Task GetUser_NonExistentUser_Returns404NotFound()
    {
        var response = await _client.GetAsync("/api/users/99999");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var problem = await response.Content.ReadFromJsonAsync<ProblemDetails>();
        problem!.Status.Should().Be(404);
    }
}
```

```csharp
// External API mocking via WireMock.NET
public class ExternalApiTests : IClassFixture<CustomWebApplicationFactory>, IAsyncLifetime
{
    private readonly WireMockServer _mockServer = WireMockServer.Start();

    public async Task InitializeAsync()
    {
        _mockServer.Given(
            Request.Create().WithPath("/api/external/validate").UsingPost())
            .RespondWith(
                Response.Create()
                    .WithStatusCode(200)
                    .WithHeader("Content-Type", "application/json")
                    .WithBody("""{"valid": true}"""));
    }

    public async Task DisposeAsync() => _mockServer.Stop();
}
```

## Graceful Shutdown

- Use `IHostApplicationLifetime` to hook into application start, stopping, and stopped events
- Propagate `CancellationToken` through handler parameters — the token is cancelled on shutdown
- Use `IHostedService` / `BackgroundService` for long-running tasks that need graceful termination
- Configure shutdown timeout with `HostOptions.ShutdownTimeout` if the default 30 seconds is insufficient

```csharp
// Propagate CancellationToken into handlers
app.MapGet("/api/long-operation", async (
    ILongRunningService service,
    CancellationToken cancellationToken) =>
{
    var result = await service.ProcessAsync(cancellationToken);
    return TypedResults.Ok(result);
});
```

```csharp
// Lifecycle hooks via IHostApplicationLifetime
public class ApplicationLifetimeService(
    IHostApplicationLifetime lifetime,
    ILogger<ApplicationLifetimeService> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        lifetime.ApplicationStarted.Register(() =>
            logger.LogInformation("Application started"));

        lifetime.ApplicationStopping.Register(() =>
            logger.LogInformation("Beginning application shutdown..."));

        lifetime.ApplicationStopped.Register(() =>
            logger.LogInformation("Application stopped"));

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}

// Registration
builder.Services.AddHostedService<ApplicationLifetimeService>();
```

```csharp
// Safe shutdown handling via BackgroundService
public class QueueProcessorService(
    IMessageQueue queue,
    ILogger<QueueProcessorService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Starting queue processor");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var message = await queue.DequeueAsync(stoppingToken);
                await ProcessMessageAsync(message, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                logger.LogInformation("Queue processor shutdown requested");
                break;
            }
        }

        logger.LogInformation("Queue processor stopped cleanly");
    }
}
```

```csharp
// Configuring the shutdown timeout
builder.Services.Configure<HostOptions>(options =>
{
    options.ShutdownTimeout = TimeSpan.FromSeconds(60);
});
```

## Related Rules / Skills

- Universal constraints: `csharp-style`, `design-principles` (D1-D7), `security` (A1-A10), `type-safety` (TS-C1-C5), `api-validation` Skill (AV-C1-C5)
- Related Skills: `csproj`, `entity-framework-core`, `blazor`, `dotnet-build-cache`, `tdd-skills-dotnet`, `integration-test-dotnet`
