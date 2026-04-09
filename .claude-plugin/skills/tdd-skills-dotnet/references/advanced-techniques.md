# Advanced TDD Techniques and Anti-patterns

## Advanced Techniques

### Dealing with Specification Uncertainty

Problem: The specification is ambiguous, and you don't know how to write the test.

Solution: Start from concrete examples.

```csharp
// Bad: Too abstract
[Fact]
public void CalculatePrice()
{
    // What are we testing?
}

// Good: Concrete use case
[Fact]
public void CalculatePrice_SingleItemWithoutDiscount_ReturnsItemPrice()
{
    var calculator = new PriceCalculator();
    var items = new[] { new Item { Price = 1000m } };

    var total = calculator.Calculate(items);

    Assert.Equal(1000m, total);
}
```

### Testcontainers.DotNet (PostgreSQL, SQL Server, Redis)

Use Testcontainers to spin up real database containers for integration tests.

```csharp
using Testcontainers.PostgreSql;

public class UserRepositoryIntegrationTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16")
        .Build();

    private AppDbContext _context = null!;

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_postgres.GetConnectionString())
            .Options;
        _context = new AppDbContext(options);
        await _context.Database.MigrateAsync();
    }

    [Fact]
    public async Task Save_PersistsUserToDatabase()
    {
        // Given
        var repo = new UserRepository(_context);
        var newUser = new NewUser { Name = "Alice", Email = "alice@example.com" };

        // When
        var saved = await repo.SaveAsync(newUser);

        // Then
        var found = await _context.Users.FindAsync(saved.Id);
        Assert.NotNull(found);
        Assert.Equal("Alice", found.Name);
    }

    public async Task DisposeAsync()
    {
        await _context.DisposeAsync();
        await _postgres.DisposeAsync();
    }
}
```

#### SQL Server Container

```csharp
using Testcontainers.MsSql;

private readonly MsSqlContainer _sqlServer = new MsSqlBuilder()
    .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
    .Build();
```

#### Redis Container

```csharp
using Testcontainers.Redis;

private readonly RedisContainer _redis = new RedisBuilder()
    .WithImage("redis:7")
    .Build();
```

### `WebApplicationFactory<Program>` with Service Overrides

Test ASP.NET Core APIs end-to-end with dependency overrides.

```csharp
using Microsoft.AspNetCore.Mvc.Testing;

public class UsersApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public UsersApiTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                // Replace real services with fakes
                services.RemoveAll<IUserRepository>();
                services.AddSingleton<IUserRepository, InMemoryUserRepository>();

                // Replace DbContext with in-memory
                services.RemoveAll<AppDbContext>();
                services.AddDbContext<AppDbContext>(options =>
                    options.UseInMemoryDatabase("TestDb"));
            });
        }).CreateClient();
    }

    [Fact]
    public async Task GetUser_ReturnsOk()
    {
        var response = await _client.GetAsync("/api/users/1");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task CreateUser_ReturnsCreated()
    {
        var request = new { Name = "Alice", Email = "alice@example.com" };

        var response = await _client.PostAsJsonAsync("/api/users", request);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var user = await response.Content.ReadFromJsonAsync<UserDto>();
        Assert.Equal("Alice", user!.Name);
    }
}
```

#### Combining WebApplicationFactory with Testcontainers

```csharp
public class IntegrationTestFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16")
        .Build();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(options =>
                options.UseNpgsql(_postgres.GetConnectionString()));
        });
    }

    public async Task InitializeAsync() => await _postgres.StartAsync();
    public new async Task DisposeAsync() => await _postgres.DisposeAsync();
}

public class FullIntegrationTests(IntegrationTestFactory factory)
    : IClassFixture<IntegrationTestFactory>
{
    private readonly HttpClient _client = factory.CreateClient();

    [Fact]
    public async Task CreateAndGetUser_RoundTrip()
    {
        var createResponse = await _client.PostAsJsonAsync("/api/users",
            new { Name = "Alice", Email = "alice@example.com" });
        var created = await createResponse.Content.ReadFromJsonAsync<UserDto>();

        var getResponse = await _client.GetFromJsonAsync<UserDto>($"/api/users/{created!.Id}");

        Assert.Equal("Alice", getResponse!.Name);
    }
}
```

### Stryker.NET Mutation Testing

Mutation testing verifies that your tests actually catch bugs by introducing small changes (mutations) to the production code.

```bash
# Install globally
dotnet tool install -g dotnet-stryker

# Run from the test project directory
cd tests/MyApp.Tests
dotnet stryker

# Run nightly (recommended — mutation testing is slow)
dotnet stryker --reporters "['html', 'json']" --threshold-high 80 --threshold-low 60
```

Configuration in `stryker-config.json`:

```json
{
  "stryker-config": {
    "project": "MyApp.csproj",
    "reporters": ["html", "progress"],
    "threshold-high": 80,
    "threshold-low": 60,
    "mutate": [
      "!**/Migrations/**",
      "!**/Program.cs"
    ]
  }
}
```

> Recommendation: Run Stryker.NET in nightly CI pipelines, not on every commit. It is too slow for the inner development loop.

### Testing Legacy Code with the Adapter Pattern

When legacy code has hard dependencies that cannot be easily injected:

```csharp
// Legacy code: tightly coupled to static/sealed class
public class LegacyOrderProcessor
{
    public void Process(Order order)
    {
        // Directly calls a static legacy payment system
        LegacyPaymentSystem.Charge(order.Amount);
        LegacyEmailSender.Send(order.CustomerEmail, "Order confirmed");
    }
}

// Step 1: Create adapter interfaces
public interface IPaymentAdapter
{
    void Charge(decimal amount);
}

public interface IEmailAdapter
{
    void Send(string to, string message);
}

// Step 2: Implement adapters wrapping legacy code
public class LegacyPaymentAdapter : IPaymentAdapter
{
    public void Charge(decimal amount) => LegacyPaymentSystem.Charge(amount);
}

public class LegacyEmailAdapter : IEmailAdapter
{
    public void Send(string to, string message) => LegacyEmailSender.Send(to, message);
}

// Step 3: Refactored class uses adapters
public class OrderProcessor(IPaymentAdapter payment, IEmailAdapter email)
{
    public void Process(Order order)
    {
        payment.Charge(order.Amount);
        email.Send(order.CustomerEmail, "Order confirmed");
    }
}

// Step 4: Now testable
[Fact]
public void Process_ChargesCorrectAmount()
{
    var payment = Substitute.For<IPaymentAdapter>();
    var email = Substitute.For<IEmailAdapter>();
    var processor = new OrderProcessor(payment, email);

    processor.Process(new Order { Amount = 5000m, CustomerEmail = "test@example.com" });

    payment.Received(1).Charge(5000m);
}
```

### Characterization Tests for Legacy Code

Before refactoring, capture existing behavior.

```csharp
// Step 1: Record existing behavior
[Fact]
public void ExistingBehavior_IsPreserved()
{
    var input = CreateKnownInput();
    var result = LegacyFunction(input);

    // Assert current (possibly surprising) behavior
    Assert.Equal("unexpected-but-actual-output", result);
}

// Step 2: Add more characterization tests to build a safety net
// Step 3: Refactor with confidence, knowing tests catch regressions
// Step 4: Write new features with TDD
```

## TDD Anti-patterns

### 1. Implementing Without Tests First

```csharp
// Bad: Implement first
public decimal CalculateTotal(IEnumerable<Item> items) =>
    items.Sum(i => i.Price);

// Good: Write the test first
[Fact]
public void CalculateTotal_EmptyList_ReturnsZero()
{
    Assert.Equal(0m, Calculator.CalculateTotal([]));
}
```

### 2. Steps That Are Too Large

```csharp
// Bad: Try to build everything at once
[Fact]
public void CompleteOrderSystem()
{
    // Cart, payment, inventory, email... all at once
}

// Good: Small, incremental steps
[Fact]
public void CreateEmptyCart_ShouldBeEmpty()
{
    var cart = new ShoppingCart();
    Assert.True(cart.IsEmpty);
}
```

### 3. Tests for the Sake of Tests

```csharp
// Bad: Testing something trivial (property getter)
[Fact]
public void Getter()
{
    var user = new User { Name = "Alice" };
    Assert.Equal("Alice", user.Name);
}

// Good: Test behavior
[Fact]
public void User_FullName_CombinesFirstAndLast()
{
    var user = new User { FirstName = "Alice", LastName = "Smith" };
    Assert.Equal("Alice Smith", user.FullName);
}
```

### 4. Testing Private Methods

```csharp
// Bad: Testing internal helpers (using [InternalsVisibleTo] to force access)
[Fact]
public void InternalCalculation()
{
    Assert.Equal(10, InternalHelper(5));
}

// Good: Test through the public API
[Fact]
public void PublicMethod_ThatUsesInternal_ReturnsExpected()
{
    var obj = new MyService();
    Assert.Equal(expectedResult, obj.Calculate(5));
}
```

### 5. Tests That Depend on Each Other

```csharp
// Bad: Tests depend on execution order or shared mutable state
// Good: Each test is independent
[Fact]
public void CreateCart_IsEmpty()
{
    var cart = new ShoppingCart();
    Assert.True(cart.IsEmpty);
}

[Fact]
public void AddItem_IncreasesCount()
{
    var cart = new ShoppingCart(); // Fresh instance every time
    cart.AddItem(new Item { Price = 100m });
    Assert.Equal(1, cart.ItemCount);
}
```

## TODO List Technique

Record ideas that come up during implementation:

```markdown
## TODO
- [x] Empty cart total is 0
- [x] Total for one item
- [ ] Total for multiple items
- [ ] Total with discount applied
- [ ] Negative price items should be rejected (error)
- [ ] Out-of-stock items cannot be added
```

Benefits:
- Stay focused on the current task
- Progress is visible
- Prevents missed implementations

## Summary

Do:
- Progress in small steps
- Start from concrete examples
- Use the TODO list
- Organize with test helpers and builders
- Use Testcontainers for real integration tests
- Run mutation testing in nightly CI

Avoid:
- Skipping tests
- Steps that are too large
- Testing private methods
- Tests that depend on each other
