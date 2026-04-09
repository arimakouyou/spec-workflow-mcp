---
paths:
  - "**/*.cs"
globs:
  - "**/*.csproj"
---

# ASP.NET Core Best Practices (.NET 10)

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

// エンドポイントを拡張メソッドで登録
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
// RouteGroupBuilder でフィルターを共有する例
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
// Program.cs — サービス登録
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

// 設定バインディング
builder.Services.Configure<JwtSettings>(
    builder.Configuration.GetSection("Jwt"));
builder.Services.Configure<SmtpSettings>(
    builder.Configuration.GetSection("Smtp"));
```

```csharp
// IOptions<T> の利用例
public class TokenService(IOptions<JwtSettings> jwtOptions)
{
    private readonly JwtSettings _settings = jwtOptions.Value;

    public string GenerateToken(User user) { /* _settings.SecretKey, _settings.Issuer ... */ }
}

// IOptionsMonitor<T> — ランタイムでの設定変更を監視
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
// Program.cs — ミドルウェアパイプラインの正しい順序
var app = builder.Build();

// 1. 例外処理（最初に配置）
app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// 2. HTTPS とセキュリティヘッダー
app.UseHsts();
app.UseHttpsRedirection();

// 3. CORS
app.UseCors("AllowFrontend");

// 4. 認証・認可
app.UseAuthentication();
app.UseAuthorization();

// 5. エンドポイント
app.MapUserEndpoints();
app.MapOrderEndpoints();

app.Run();
```

```csharp
// カスタムミドルウェア（IMiddleware インターフェース方式 — DI 対応）
public class RequestTimingMiddleware(ILogger<RequestTimingMiddleware> logger) : IMiddleware
{
    public async Task InvokeAsync(HttpContext context, RequestDelegate next)
    {
        var stopwatch = Stopwatch.StartNew();
        await next(context);
        stopwatch.Stop();

        logger.LogInformation(
            "リクエスト {Method} {Path} は {Elapsed}ms で完了",
            context.Request.Method,
            context.Request.Path,
            stopwatch.ElapsedMilliseconds);
    }
}

// 登録
builder.Services.AddTransient<RequestTimingMiddleware>();
app.UseMiddleware<RequestTimingMiddleware>();
```

```csharp
// カスタムミドルウェア（規約ベース方式）
public class CorrelationIdMiddleware(RequestDelegate next)
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
// TypedResults による型安全なレスポンス
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
// ProblemDetails サービスの登録（.NET 10）
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
// IExceptionHandler による集中エラーハンドリング（.NET 10 推奨パターン）
public class GlobalExceptionHandler(
    ILogger<GlobalExceptionHandler> logger,
    IProblemDetailsService problemDetailsService) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        logger.LogError(exception, "未処理の例外が発生: {Message}", exception.Message);

        var (statusCode, title) = exception switch
        {
            NotFoundException => (StatusCodes.Status404NotFound, "リソースが見つかりません"),
            ValidationException => (StatusCodes.Status400BadRequest, "バリデーションエラー"),
            UnauthorizedAccessException => (StatusCodes.Status403Forbidden, "アクセスが拒否されました"),
            _ => (StatusCodes.Status500InternalServerError, "内部サーバーエラー")
        };

        httpContext.Response.StatusCode = statusCode;

        return await problemDetailsService.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails =
            {
                Title = title,
                Status = statusCode,
                Detail = exception is not ServerException ? exception.Message : null
            }
        });
    }
}

// 登録
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddProblemDetails();

app.UseExceptionHandler();
```

```csharp
// カスタム例外型の定義
public abstract class AppException(string message, int statusCode) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}

public class NotFoundException(string resource, object id)
    : AppException($"{resource} (ID: {id}) は見つかりません", 404);

public class ConflictException(string message)
    : AppException(message, 409);
```

## Authentication & Authorization

- Use `builder.Services.AddAuthentication().AddJwtBearer()` for JWT-based API auth
- Define named policies with `AddAuthorizationBuilder()` for role-based and claim-based rules
- Implement `IAuthorizationHandler` for complex, data-dependent authorization logic
- Apply authorization at the endpoint level with `RequireAuthorization()` or `[Authorize]`

```csharp
// Program.cs — 認証・認可の設定
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
// カスタム認可ハンドラー
public class UserEditRequirement : IAuthorizationRequirement;

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

        // 自分自身の編集か、管理者のみ許可
        if (currentUserId == userId || context.User.IsInRole("Admin"))
        {
            context.Succeed(requirement);
        }
    }
}
```

```csharp
// エンドポイントへの認可ポリシー適用
app.MapDelete("/api/users/{id:int}", DeleteUser)
    .RequireAuthorization("AdminOnly");

app.MapPut("/api/users/{id:int}", UpdateUser)
    .RequireAuthorization("CanEditUser");

// 認可不要の公開エンドポイント
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
// テストプロジェクトからアクセス可能にするマーカー（Program.cs の末尾）
public partial class Program;
```

```csharp
// 統合テスト用のカスタムファクトリ
public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // 本番の DbContext をテスト用 InMemory DB に差し替え
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<AppDbContext>));
            if (descriptor is not null)
                services.Remove(descriptor);

            services.AddDbContext<AppDbContext>(options =>
                options.UseInMemoryDatabase("TestDb"));

            // 外部サービスをモックに差し替え
            services.AddScoped<IEmailSender, FakeEmailSender>();
        });

        builder.UseEnvironment("Testing");
    }
}
```

```csharp
// 統合テストの例
public class UserEndpointsTests(CustomWebApplicationFactory factory)
    : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client = factory.CreateClient();

    [Fact]
    public async Task GetUser_存在するユーザー_200OKを返す()
    {
        // Arrange — テストデータの準備
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.Users.Add(new User { Id = 1, Name = "テストユーザー" });
        await db.SaveChangesAsync();

        // Act
        var response = await _client.GetAsync("/api/users/1");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var user = await response.Content.ReadFromJsonAsync<UserDto>();
        user!.Name.Should().Be("テストユーザー");
    }

    [Fact]
    public async Task GetUser_存在しないユーザー_404NotFoundを返す()
    {
        var response = await _client.GetAsync("/api/users/99999");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        var problem = await response.Content.ReadFromJsonAsync<ProblemDetails>();
        problem!.Status.Should().Be(404);
    }
}
```

```csharp
// WireMock.NET による外部APIモック
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
// CancellationToken をハンドラーに伝搬
app.MapGet("/api/long-operation", async (
    ILongRunningService service,
    CancellationToken cancellationToken) =>
{
    var result = await service.ProcessAsync(cancellationToken);
    return TypedResults.Ok(result);
});
```

```csharp
// IHostApplicationLifetime によるライフサイクルフック
public class ApplicationLifetimeService(
    IHostApplicationLifetime lifetime,
    ILogger<ApplicationLifetimeService> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        lifetime.ApplicationStarted.Register(() =>
            logger.LogInformation("アプリケーションが起動しました"));

        lifetime.ApplicationStopping.Register(() =>
            logger.LogInformation("アプリケーションの停止処理を開始します..."));

        lifetime.ApplicationStopped.Register(() =>
            logger.LogInformation("アプリケーションが停止しました"));

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}

// 登録
builder.Services.AddHostedService<ApplicationLifetimeService>();
```

```csharp
// BackgroundService による安全な停止処理
public class QueueProcessorService(
    IMessageQueue queue,
    ILogger<QueueProcessorService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("キュープロセッサーを開始します");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var message = await queue.DequeueAsync(stoppingToken);
                await ProcessMessageAsync(message, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                logger.LogInformation("キュープロセッサーの停止が要求されました");
                break;
            }
        }

        logger.LogInformation("キュープロセッサーが正常に停止しました");
    }
}
```

```csharp
// シャットダウンタイムアウトの設定
builder.Services.Configure<HostOptions>(options =>
{
    options.ShutdownTimeout = TimeSpan.FromSeconds(60);
});
```
