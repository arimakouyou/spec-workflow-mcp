# Test Implementation Patterns

A collection of typical patterns used in .NET integration tests.

## Project Structure Template

```
tests/
└── MyApp.IntegrationTests/
    ├── MyApp.IntegrationTests.csproj
    ├── GlobalUsings.cs
    ├── Fixtures/
    │   ├── IntegrationTestFixture.cs     # WebApplicationFactory + Testcontainers
    │   ├── IntegrationTestCollection.cs  # xUnit collection definition
    │   └── DatabaseHelper.cs             # Seed data and DB verification helpers
    ├── Users/
    │   └── UserEndpointTests.cs          # Per-domain test class
    ├── Orders/
    │   └── OrderEndpointTests.cs
    └── ExternalApis/
        └── PaymentGatewayTests.cs        # WireMock.NET tests
```

## Pattern 1: List Retrieval (GET /)

```csharp
[Fact]
public async Task ListUsers_ReturnsAllUsers()
{
    // Given
    using var scope = _fixture.Factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Users.AddRange(
        new User { Name = "Alice", Email = "alice@example.com" },
        new User { Name = "Bob", Email = "bob@example.com" });
    await db.SaveChangesAsync();

    // When
    var response = await _client.GetAsync("/api/users");

    // Then
    response.StatusCode.Should().Be(HttpStatusCode.OK);
    var users = await response.Content.ReadFromJsonAsync<List<UserResponse>>();
    users.Should().HaveCount(2);
}
```

## Pattern 2: Create (POST /)

```csharp
[Fact]
public async Task CreateUser_ReturnsCreated_AndPersistsToDb()
{
    // Given
    var request = new { Name = "Alice", Email = "alice@example.com" };

    // When
    var response = await _client.PostAsJsonAsync("/api/users", request);

    // Then — response verification
    response.StatusCode.Should().Be(HttpStatusCode.Created);
    var body = await response.Content.ReadFromJsonAsync<UserResponse>();
    body!.Name.Should().Be("Alice");

    // Then — DB verification
    using var scope = _fixture.Factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var user = await db.Users.FirstOrDefaultAsync(u => u.Email == "alice@example.com");
    user.Should().NotBeNull();
}
```

## Pattern 3: Detail Retrieval (GET /:id)

```csharp
[Fact]
public async Task GetUser_ReturnsUser_WhenExists()
{
    // Given
    using var scope = _fixture.Factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var user = new User { Name = "Alice", Email = "alice@example.com" };
    db.Users.Add(user);
    await db.SaveChangesAsync();

    // When
    var response = await _client.GetAsync($"/api/users/{user.Id}");

    // Then
    response.StatusCode.Should().Be(HttpStatusCode.OK);
    var body = await response.Content.ReadFromJsonAsync<UserResponse>();
    body!.Id.Should().Be(user.Id);
}

[Fact]
public async Task GetUser_ReturnsNotFound_WhenMissing()
{
    // When
    var response = await _client.GetAsync("/api/users/99999");

    // Then
    response.StatusCode.Should().Be(HttpStatusCode.NotFound);
}
```

## Pattern 4: Update (PUT /:id)

```csharp
[Fact]
public async Task UpdateUser_ModifiesExistingRecord()
{
    // Given
    using var scope = _fixture.Factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var user = new User { Name = "Alice", Email = "alice@example.com" };
    db.Users.Add(user);
    await db.SaveChangesAsync();

    var request = new { Name = "Alice Updated" };

    // When
    var response = await _client.PutAsJsonAsync($"/api/users/{user.Id}", request);

    // Then
    response.StatusCode.Should().Be(HttpStatusCode.OK);

    // DB verification
    await db.Entry(user).ReloadAsync();
    user.Name.Should().Be("Alice Updated");
}
```

## Pattern 5: Delete (DELETE /:id)

```csharp
[Fact]
public async Task DeleteUser_RemovesRecord()
{
    // Given
    using var scope = _fixture.Factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var user = new User { Name = "Alice", Email = "alice@example.com" };
    db.Users.Add(user);
    await db.SaveChangesAsync();
    var userId = user.Id;

    // When
    var response = await _client.DeleteAsync($"/api/users/{userId}");

    // Then
    response.StatusCode.Should().Be(HttpStatusCode.NoContent);

    // DB verification
    var deleted = await db.Users.FindAsync(userId);
    deleted.Should().BeNull();
}
```

## Pattern 6: Theory with InlineData (Parameterized Tests)

```csharp
[Theory]
[InlineData("", HttpStatusCode.BadRequest)]
[InlineData("a", HttpStatusCode.BadRequest)]           // Too short
[InlineData("ValidName", HttpStatusCode.Created)]
public async Task CreateUser_ValidatesName(string name, HttpStatusCode expectedStatus)
{
    // Given
    var request = new { Name = name, Email = "test@example.com" };

    // When
    var response = await _client.PostAsJsonAsync("/api/users", request);

    // Then
    response.StatusCode.Should().Be(expectedStatus);
}
```

## Pattern 7: Pagination

```csharp
[Fact]
public async Task ListUsers_SupportsPagination()
{
    // Given — seed 25 users
    using var scope = _fixture.Factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Users.AddRange(
        Enumerable.Range(1, 25).Select(i =>
            new User { Name = $"User{i}", Email = $"user{i}@example.com" }));
    await db.SaveChangesAsync();

    // When — page 1
    var response = await _client.GetAsync("/api/users?page=1&pageSize=10");
    response.StatusCode.Should().Be(HttpStatusCode.OK);
    var page1 = await response.Content.ReadFromJsonAsync<PaginatedResponse<UserResponse>>();
    page1!.Items.Should().HaveCount(10);
    page1.TotalCount.Should().Be(25);

    // When — page 3 (remaining 5)
    response = await _client.GetAsync("/api/users?page=3&pageSize=10");
    var page3 = await response.Content.ReadFromJsonAsync<PaginatedResponse<UserResponse>>();
    page3!.Items.Should().HaveCount(5);
}
```

## Pattern 8: External API Error Handling (WireMock.NET)

```csharp
[Fact]
public async Task CreateOrder_ReturnsBadGateway_WhenPaymentGatewayFails()
{
    // Given — stub returns 500
    _wireMock.Given(
        Request.Create().WithPath("/api/charge").UsingPost()
    ).RespondWith(
        Response.Create().WithStatusCode(500)
    );

    var request = new { ProductId = 1, Amount = 100 };

    // When
    var response = await _client.PostAsJsonAsync("/api/orders", request);

    // Then
    response.StatusCode.Should().Be(HttpStatusCode.BadGateway);

    // DB should be rolled back
    using var scope = _fixture.Factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var orders = await db.Orders.ToListAsync();
    orders.Should().BeEmpty();
}
```

## Pattern 9: Authentication Error

```csharp
[Fact]
public async Task UnauthenticatedRequest_Returns401()
{
    // Given — create a client without authentication
    var client = _fixture.Factory.CreateClient();
    client.DefaultRequestHeaders.Clear(); // Remove any default auth

    // When
    var response = await client.GetAsync("/api/users");

    // Then
    response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
}
```

## Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `Connection refused` | Testcontainers container not started | Verify Docker daemon is running |
| `No such table` / `relation does not exist` | Migration not applied | Ensure `db.Database.MigrateAsync()` runs in fixture `InitializeAsync` |
| Data interference between tests | Shared DB state without cleanup | Use per-test transaction scope or `Respawn` library for DB reset |
| `Cannot resolve scoped service` | Getting scoped service from root | Use `Factory.Services.CreateScope()` |
| `System.ObjectDisposedException` | Factory/container disposed prematurely | Ensure `IAsyncLifetime.DisposeAsync` ordering is correct |
