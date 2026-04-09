---
paths:
  - "**/*.rs"
  - "**/*.cs"
  - "**/Cargo.toml"
  - "**/*.csproj"
---

# Project Architecture

This rule defines the base architecture for REST API backend configurations.

- **Rust**: Axum + Diesel + Valkey（Leptos フルスタックの場合は `leptos.md` が優先）
- **C#/.NET**: ASP.NET Core + Entity Framework Core + Redis（Blazor フルスタックの場合は `blazor.md` が優先）

---

## Rust: Axum + Diesel + Valkey

This section defines the base architecture for a Rust REST API backend configuration.
When using a Leptos full-stack configuration, the rules in `leptos.md` take precedence.

## Directory Structure

```
src/
├── main.rs              # Entry point, server startup
├── config.rs            # Environment variable and configuration loading
├── app_state.rs         # AppState definition
├── error.rs             # AppError definition (IntoResponse implementation)
├── db/
│   ├── mod.rs           # DB pool initialization
│   └── repository/      # Repository layer (abstracts DB access)
│       ├── mod.rs
│       └── users.rs
├── cache/
│   ├── mod.rs           # Valkey connection initialization
│   └── keys.rs          # Key generation helpers
├── models/
│   ├── mod.rs
│   └── user.rs          # Diesel models (Queryable, Insertable, etc.)
├── handlers/
│   ├── mod.rs
│   └── users.rs         # Axum handlers
├── routes/
│   ├── mod.rs           # Router configuration
│   └── users.rs
├── middleware/
│   ├── mod.rs
│   └── auth.rs          # Authentication middleware
├── schema.rs            # Diesel auto-generated
└── dto/
    ├── mod.rs
    └── user.rs           # Request/response types (Serialize, Deserialize)
migrations/
    └── ...
```

## Layer Structure

```
Handler (Axum) → Repository (Diesel/Valkey) → Database/Cache
```

- **Handler**: Receives HTTP requests, performs validation, builds responses
- **Repository**: Data access logic. Encapsulates DB queries and cache operations
- **Model**: Diesel table mappings
- **DTO**: API request/response types (kept separate from Model)

## AppState

```rust
use diesel_async::pooled_connection::deadpool::Pool;
use diesel_async::AsyncPgConnection;
use redis::aio::ConnectionManager;

pub type DbPool = Pool<AsyncPgConnection>;

#[derive(Clone)]
pub struct AppState {
    pub db_pool: DbPool,
    pub valkey: ConnectionManager,
    pub config: Arc<AppConfig>,
}
```

## Unified Error Type

```rust
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};

pub enum AppError {
    NotFound,
    BadRequest(String),
    Unauthorized,
    Conflict(String),
    Internal(anyhow::Error),
}

impl From<diesel::result::Error> for AppError { /* ... */ }
impl From<redis::RedisError> for AppError { /* ... */ }
impl From<deadpool::managed::PoolError<deadpool_diesel::postgres::Manager>> for AppError { /* ... */ }
impl IntoResponse for AppError { /* ... */ }
```

## Dependency Guidelines

```toml
[dependencies]
axum = "0.8"
diesel = { version = "2.2", features = ["postgres"] }
diesel-async = { version = "0.5", features = ["postgres", "deadpool"] }
redis = { version = "0.27", features = ["tokio-comp", "connection-manager"] }
tokio = { version = "1", features = ["full"] }
tower = "0.5"
tower-http = { version = "0.6", features = ["trace", "cors", "timeout"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
anyhow = "1"
dotenvy = "0.15"
```

## Configuration Management

- Load from environment variables (`dotenvy` + `std::env`)
- Consolidate `DATABASE_URL`, `VALKEY_URL`, `HOST`, `PORT`, etc. into `AppConfig`
- Do not hardcode secrets (DB passwords, etc.) in code
- Switch configuration per environment using environment variables

## Logging and Tracing

- Use `tracing` + `tracing-subscriber`
- Output request logs with `tower_http::trace::TraceLayer`
- Control the log level with the `RUST_LOG` environment variable
- Use structured logging (`tracing::info!(user_id = %id, "User created")`)

## Testing Strategy

- Unit tests: Test the repository layer directly (test DB + transaction rollback)
- Integration tests: Test the full Axum app with `tower::ServiceExt`
- Provide a helper function to construct `AppState` for tests
- Use `test_transaction` to roll back the test DB

---

## C#/.NET: ASP.NET Core + Entity Framework Core + Redis

This section defines the base architecture for a C#/.NET REST API backend configuration.
When using a Blazor full-stack configuration, the rules in `blazor.md` take precedence.

### Directory Structure

```
src/
├── Program.cs               # Entry point, DI configuration, middleware pipeline
├── appsettings.json         # Configuration (non-secret defaults)
├── appsettings.Development.json
├── GlobalUsings.cs          # Global using directives
├── Data/
│   ├── AppDbContext.cs      # EF Core DbContext
│   ├── Configurations/      # IEntityTypeConfiguration<T>
│   │   └── UserConfiguration.cs
│   └── Migrations/
├── Models/
│   ├── User.cs              # EF Core entities
│   └── Order.cs
├── Repositories/
│   ├── IUserRepository.cs   # Repository interface
│   └── UserRepository.cs    # EF Core implementation
├── Services/
│   ├── IUserService.cs      # Business logic interface
│   └── UserService.cs
├── Endpoints/               # Minimal API endpoint groups (or Controllers/)
│   ├── UserEndpoints.cs
│   └── OrderEndpoints.cs
├── Middleware/
│   ├── ExceptionHandlingMiddleware.cs
│   └── RequestLoggingMiddleware.cs
├── DTOs/
│   ├── CreateUserRequest.cs
│   └── UserResponse.cs
└── Exceptions/
    └── AppException.cs      # Unified exception type
```

### Layer Structure

```
Endpoint/Controller (ASP.NET Core) → Service → Repository (EF Core) → Database/Cache
```

- **Endpoint/Controller**: Receives HTTP requests, model binding/validation, builds responses
- **Service**: Business logic. Orchestrates repository calls and cache operations
- **Repository**: Data access logic. Encapsulates EF Core queries and Redis operations
- **Model**: EF Core entity mappings
- **DTO**: API request/response types (kept separate from Model)

### Dependency Injection Configuration

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// Data layer
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// Cache
builder.Services.AddStackExchangeRedisCache(options =>
    options.Configuration = builder.Configuration.GetConnectionString("Redis"));

// Repositories (Scoped — per-request)
builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<IOrderRepository, OrderRepository>();

// Services (Scoped)
builder.Services.AddScoped<IUserService, UserService>();

// Configuration (Singleton)
builder.Services.Configure<AppConfig>(builder.Configuration.GetSection("App"));

var app = builder.Build();

// Middleware pipeline (order matters)
app.UseMiddleware<ExceptionHandlingMiddleware>();
app.UseAuthentication();
app.UseAuthorization();

// Endpoints
app.MapUserEndpoints();
app.MapOrderEndpoints();

app.Run();
```

### Unified Error Handling

```csharp
public class AppException : Exception
{
    public string Code { get; }
    public int StatusCode { get; }

    public AppException(string code, string message, int statusCode = 500)
        : base(message) => (Code, StatusCode) = (code, statusCode);

    public static AppException NotFound(string message) => new("NotFound", message, 404);
    public static AppException BadRequest(string message) => new("BadRequest", message, 400);
    public static AppException Conflict(string message) => new("Conflict", message, 409);
}

public class ExceptionHandlingMiddleware(RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (AppException ex)
        {
            context.Response.StatusCode = ex.StatusCode;
            await context.Response.WriteAsJsonAsync(new ProblemDetails
            {
                Status = ex.StatusCode,
                Title = ex.Code,
                Detail = ex.Message,
            });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unhandled exception");
            context.Response.StatusCode = 500;
            await context.Response.WriteAsJsonAsync(new ProblemDetails
            {
                Status = 500,
                Title = "InternalServerError",
                Detail = "An unexpected error occurred",
            });
        }
    }
}
```

### Dependency Guidelines

```xml
<!-- Directory.Build.props -->
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
  <Nullable>enable</Nullable>
  <ImplicitUsings>enable</ImplicitUsings>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>

<!-- Common packages (example) -->
<ItemGroup>
  <!-- ORM -->
  <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" />
  <!-- Cache -->
  <PackageReference Include="Microsoft.Extensions.Caching.StackExchangeRedis" />
  <!-- Validation -->
  <PackageReference Include="FluentValidation.AspNetCore" />
  <!-- Logging -->
  <PackageReference Include="Serilog.AspNetCore" />
  <!-- Analyzers -->
  <PackageReference Include="Roslynator.Analyzers" PrivateAssets="all" />
  <PackageReference Include="StyleCop.Analyzers" PrivateAssets="all" />
  <PackageReference Include="Meziantou.Analyzer" PrivateAssets="all" />
</ItemGroup>
```

### Configuration Management

- Use `appsettings.json` + `appsettings.{Environment}.json` for non-secret configuration
- Use User Secrets (`dotnet user-secrets`) for local development secrets
- Use environment variables for production secrets
- Bind to strongly-typed options with `IOptions<T>` / `IOptionsMonitor<T>`
- Do not hardcode secrets (connection strings, API keys) in code

### Logging

- Use `Serilog` + structured logging
- Request logging with `app.UseSerilogRequestLogging()`
- Control log level with `appsettings.json` `Logging:LogLevel` section
- Use structured logging (`logger.LogInformation("User {UserId} created", userId)`)

### Testing Strategy

- Unit tests: Test the service layer with mocked repositories (xUnit + NSubstitute/Moq)
- Integration tests: `WebApplicationFactory<Program>` + Testcontainers for .NET (real DB)
- Architecture tests: NetArchTest.Rules / ArchUnitNET for layer dependency enforcement
- WireMock.NET for external API mocking
