# Shared Helpers & Fixture Catalog

Catalog of test helpers defined in the `Fixtures/` directory of the integration test project.

## IntegrationTestFixture (Core Fixture)

Provides a real PostgreSQL and Redis container plus a configured `WebApplicationFactory`
for each test collection.

```csharp
public class IntegrationTestFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    private readonly RedisContainer _redis = new RedisBuilder()
        .WithImage("redis:7-alpine")
        .Build();

    public WebApplicationFactory<Program> Factory { get; private set; } = default!;

    public async Task InitializeAsync()
    {
        await Task.WhenAll(_postgres.StartAsync(), _redis.StartAsync());

        Factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.ConfigureServices(services =>
                {
                    // Replace DbContext
                    services.RemoveAll<DbContextOptions<AppDbContext>>();
                    services.AddDbContext<AppDbContext>(options =>
                        options.UseNpgsql(_postgres.GetConnectionString()));

                    // Replace Redis
                    services.RemoveAll<IConnectionMultiplexer>();
                    services.AddSingleton<IConnectionMultiplexer>(
                        ConnectionMultiplexer.Connect(_redis.GetConnectionString()));
                });
            });

        // Apply migrations
        using var scope = Factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync();
    }

    public async Task DisposeAsync()
    {
        await _postgres.DisposeAsync();
        await _redis.DisposeAsync();
    }
}
```

## Collection Definition

xUnit collection fixture to share the `IntegrationTestFixture` across test classes:

```csharp
[CollectionDefinition("Integration")]
public class IntegrationTestCollection : ICollectionFixture<IntegrationTestFixture>
{
    // This class has no code; it just anchors the collection definition.
}
```

## DatabaseHelper

Utility methods for seeding test data and verifying DB state:

```csharp
public static class DatabaseHelper
{
    /// Create a scoped DbContext from the factory
    public static AppDbContext CreateDbContext(WebApplicationFactory<Program> factory)
    {
        var scope = factory.Services.CreateScope();
        return scope.ServiceProvider.GetRequiredService<AppDbContext>();
    }

    /// Seed a single entity and return it (with generated ID)
    public static async Task<T> SeedAsync<T>(
        WebApplicationFactory<Program> factory, T entity) where T : class
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.Set<T>().Add(entity);
        await db.SaveChangesAsync();
        return entity;
    }

    /// Seed multiple entities
    public static async Task SeedManyAsync<T>(
        WebApplicationFactory<Program> factory, params T[] entities) where T : class
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.Set<T>().AddRange(entities);
        await db.SaveChangesAsync();
    }

    /// Reset database state between tests (using Respawn)
    public static async Task ResetAsync(WebApplicationFactory<Program> factory)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var connection = db.Database.GetDbConnection();
        await connection.OpenAsync();

        var respawner = await Respawner.CreateAsync(connection, new RespawnerOptions
        {
            DbAdapter = DbAdapter.Postgres,
            SchemasToInclude = ["public"],
        });
        await respawner.ResetAsync(connection);
    }
}
```

## Authenticated HttpClient Helper

```csharp
public static class HttpClientExtensions
{
    /// Create an HttpClient with a test authentication token
    public static HttpClient CreateAuthenticatedClient(
        this WebApplicationFactory<Program> factory, string role = "User")
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", GenerateTestToken(role));
        return client;
    }

    private static string GenerateTestToken(string role)
    {
        // Generate a test JWT or use a test auth scheme
        // Implementation depends on the project's auth setup
        return $"test-token-{role}";
    }
}
```

## GlobalUsings.cs

Common using statements for the test project:

```csharp
global using System.Net;
global using System.Net.Http.Json;
global using FluentAssertions;
global using Microsoft.AspNetCore.Mvc.Testing;
global using Microsoft.EntityFrameworkCore;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.DependencyInjection.Extensions;
global using Testcontainers.PostgreSql;
global using Testcontainers.Redis;
global using WireMock.Server;
global using WireMock.RequestBuilders;
global using WireMock.ResponseBuilders;
global using Xunit;
```

## NuGet Package References

Required packages for the integration test project (`*.IntegrationTests.csproj`):

```xml
<ItemGroup>
  <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.*" />
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*" />
  <PackageReference Include="xunit" Version="2.*" />
  <PackageReference Include="xunit.runner.visualstudio" Version="2.*" />
  <PackageReference Include="FluentAssertions" Version="8.*" />
  <PackageReference Include="Testcontainers.PostgreSql" Version="4.*" />
  <PackageReference Include="Testcontainers.Redis" Version="4.*" />
  <PackageReference Include="WireMock.Net" Version="1.*" />
  <PackageReference Include="Respawn" Version="6.*" />
</ItemGroup>
```

## Fixture Selection Flow

```
What does the test need?
  +-- DB access required
  |   +-- Use IntegrationTestFixture (via IClassFixture / ICollectionFixture)
  |       +-- Seed data -> DatabaseHelper.SeedAsync / SeedManyAsync
  |       +-- Verify DB -> CreateDbContext + LINQ queries
  |       +-- Reset between tests -> DatabaseHelper.ResetAsync (Respawn)
  |
  +-- External HTTP API mocking
  |   +-- WireMockServer.Start() in test class IAsyncLifetime
  |   +-- Override service URL via ConfigureServices
  |
  +-- Authenticated HTTP requests
  |   +-- factory.CreateAuthenticatedClient()
  |
  +-- Unauthenticated HTTP requests
      +-- factory.CreateClient() (no auth headers)
```
