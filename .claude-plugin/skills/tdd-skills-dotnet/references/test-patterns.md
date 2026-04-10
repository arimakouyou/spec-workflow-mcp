# Test Patterns

## xUnit Test Lifecycle

### Constructor / Dispose (Per-Test Setup/Teardown)

xUnit creates a new instance of the test class for each test method. Use the constructor for setup and `IDisposable` for teardown.

```csharp
public class ShoppingCartTests : IDisposable
{
    private readonly ShoppingCart _cart;
    private readonly IUserRepository _repo;

    public ShoppingCartTests()
    {
        // Runs before each test
        _repo = Substitute.For<IUserRepository>();
        _cart = new ShoppingCart();
    }

    [Fact]
    public void EmptyCart_Total_ReturnsZero()
    {
        Assert.Equal(0m, _cart.Total());
    }

    [Fact]
    public void AddItem_IncreasesItemCount()
    {
        _cart.AddItem(new Item { Price = 100m });
        Assert.Equal(1, _cart.ItemCount);
    }

    public void Dispose()
    {
        // Runs after each test (cleanup resources)
    }
}
```

### `IAsyncLifetime` (Async Setup/Teardown)

For tests requiring async initialization (e.g., database setup).

```csharp
public class DatabaseTests : IAsyncLifetime
{
    private readonly TestDatabase _db;

    public DatabaseTests()
    {
        _db = new TestDatabase();
    }

    public async Task InitializeAsync()
    {
        // Async setup: runs before each test
        await _db.MigrateAsync();
        await _db.SeedAsync();
    }

    [Fact]
    public async Task FindUser_ReturnsSeededUser()
    {
        var user = await _db.Users.FindAsync(1);
        Assert.NotNull(user);
    }

    public async Task DisposeAsync()
    {
        // Async teardown: runs after each test
        await _db.ResetAsync();
    }
}
```

## Collection Fixtures (`ICollectionFixture<T>`)

Share expensive resources (DB containers, HTTP servers) across multiple test classes.

```csharp
// 1. Define the fixture
public class DatabaseFixture : IAsyncLifetime
{
    public string ConnectionString { get; private set; } = "";

    public async Task InitializeAsync()
    {
        // Start Testcontainers PostgreSQL (once for the collection)
        var container = new PostgreSqlBuilder()
            .WithImage("postgres:16")
            .Build();
        await container.StartAsync();
        ConnectionString = container.GetConnectionString();
    }

    public Task DisposeAsync() => Task.CompletedTask;
}

// 2. Define a collection
[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture> { }

// 3. Use in test classes
[Collection("Database")]
public class UserRepositoryTests(DatabaseFixture db)
{
    [Fact]
    public async Task Save_PersistsUser()
    {
        await using var context = new AppDbContext(db.ConnectionString);
        var repo = new UserRepository(context);

        var user = await repo.SaveAsync(new NewUser { Name = "Alice" });

        Assert.True(user.Id > 0);
    }
}

[Collection("Database")]
public class OrderRepositoryTests(DatabaseFixture db)
{
    [Fact]
    public async Task Save_PersistsOrder()
    {
        await using var context = new AppDbContext(db.ConnectionString);
        var repo = new OrderRepository(context);

        var order = await repo.SaveAsync(new NewOrder { Amount = 5000m });

        Assert.True(order.Id > 0);
    }
}
```

## `ITestOutputHelper` for Test Output

xUnit captures test output via `ITestOutputHelper` instead of `Console.WriteLine`.

```csharp
public class DiagnosticTests(ITestOutputHelper output)
{
    [Fact]
    public void ProcessOrder_LogsSteps()
    {
        output.WriteLine("Starting order processing test...");

        var service = new OrderService();
        var result = service.Process(new Order { Amount = 1000m });

        output.WriteLine($"Result: {result.Status}");
        Assert.Equal(OrderStatus.Completed, result.Status);
    }
}
```

## Test Data Builder Pattern

Build complex objects flexibly for tests.

```csharp
public class ItemBuilder
{
    private string _name = "Default Item";
    private decimal _price = 1000m;
    private int _stock = 10;

    public ItemBuilder WithName(string name) { _name = name; return this; }
    public ItemBuilder WithPrice(decimal price) { _price = price; return this; }
    public ItemBuilder WithStock(int stock) { _stock = stock; return this; }

    public Item Build() => new()
    {
        Name = _name,
        Price = _price,
        Stock = _stock,
    };
}

[Fact]
public void ExpensiveItem_IsMarkedAsLuxury()
{
    var item = new ItemBuilder()
        .WithName("Luxury Watch")
        .WithPrice(1_000_000m)
        .Build();

    Assert.True(item.IsLuxury());
}
```

## FluentAssertions Patterns

FluentAssertions provides more readable assertion syntax.

```csharp
using FluentAssertions;

[Fact]
public void Cart_Total_ShouldBeCorrect()
{
    var cart = new ShoppingCart();
    cart.AddItem(new Item { Price = 100m });
    cart.AddItem(new Item { Price = 200m });

    cart.Total().Should().Be(300m);
}

[Fact]
public void GetUsers_ShouldReturnExpectedUsers()
{
    var users = service.GetAllUsers();

    users.Should().HaveCount(3);
    users.Should().Contain(u => u.Name == "Alice");
    users.Should().BeInAscendingOrder(u => u.Name);
    users.Should().AllSatisfy(u => u.Id.Should().BePositive());
}

[Fact]
public void CreateUser_WithInvalidEmail_ShouldThrow()
{
    var act = () => User.Create("invalid-email");

    act.Should().Throw<ValidationException>()
       .WithMessage("*email*");
}

[Fact]
public async Task GetUserAsync_WithInvalidId_ShouldThrow()
{
    var act = () => service.GetUserAsync(-1);

    await act.Should().ThrowAsync<NotFoundException>();
}

// Object graph comparison
[Fact]
public void MapToDto_ShouldMapAllProperties()
{
    var user = new User { Id = 1, Name = "Alice", Email = "alice@example.com" };

    var dto = user.ToDto();

    dto.Should().BeEquivalentTo(new UserDto
    {
        Id = 1,
        Name = "Alice",
        Email = "alice@example.com",
    });
}
```

## Parameterized Tests with `[Theory]`

### `[InlineData]` for Simple Cases

```csharp
[Theory]
[InlineData(0, 0)]
[InlineData(500, 0)]
[InlineData(999, 0)]
[InlineData(1000, 50)]
[InlineData(3000, 150)]
[InlineData(5000, 500)]
[InlineData(10000, 1000)]
public void CalculateDiscount_ReturnsExpected(decimal amount, decimal expected)
{
    Assert.Equal(expected, DiscountCalculator.Calculate(amount));
}
```

### `[MemberData]` for Complex Cases

```csharp
public static IEnumerable<object[]> CartScenarios =>
[
    [new[] { 100m, 200m }, 300m],
    [new[] { 1000m }, 1000m],
    [Array.Empty<decimal>(), 0m],
];

[Theory]
[MemberData(nameof(CartScenarios))]
public void Cart_Total_MatchesExpected(decimal[] prices, decimal expected)
{
    var cart = new ShoppingCart();
    foreach (var price in prices)
        cart.AddItem(new Item { Price = price });

    Assert.Equal(expected, cart.Total());
}
```

## One Test, One Concept

Principle: Each test should verify a single concept.

```csharp
// Bad: Multiple concepts in one test
[Fact]
public void ShoppingCart()
{
    var cart = new ShoppingCart();
    Assert.True(cart.IsEmpty);              // Empty check
    cart.AddItem(new Item { Price = 100m });
    Assert.Equal(1, cart.ItemCount);        // Count check
    Assert.Equal(100m, cart.Total());       // Total check
}

// Good: One concept per test
[Fact]
public void NewCart_ShouldBeEmpty()
{
    var cart = new ShoppingCart();
    Assert.True(cart.IsEmpty);
}

[Fact]
public void AddItem_IncreasesItemCount()
{
    var cart = new ShoppingCart();
    cart.AddItem(new Item { Price = 100m });
    Assert.Equal(1, cart.ItemCount);
}

[Fact]
public void AddItem_IncreasesTotal()
{
    var cart = new ShoppingCart();
    cart.AddItem(new Item { Price = 100m });
    Assert.Equal(100m, cart.Total());
}
```

Exception: Multiple assertions verifying a single concept are acceptable.

```csharp
[Fact]
public void AddItem_UpdatesCartState()
{
    var cart = new ShoppingCart();
    var item = new Item { Name = "Book", Price = 100m };

    cart.AddItem(item);

    // All verify the single concept of "item added"
    Assert.Equal(1, cart.ItemCount);
    Assert.Equal(100m, cart.Total());
    Assert.Contains("Book", cart.ItemNames);
}
```

## BenchmarkDotNet Integration (Performance-Sensitive Code)

For performance-critical paths, add benchmarks alongside unit tests.

```csharp
using BenchmarkDotNet.Attributes;

[MemoryDiagnoser]
public class DiscountCalculatorBenchmarks
{
    [Benchmark]
    public decimal Calculate_SmallAmount() => DiscountCalculator.Calculate(500m);

    [Benchmark]
    public decimal Calculate_LargeAmount() => DiscountCalculator.Calculate(100_000m);
}
```

Run with: `dotnet run -c Release -- --filter *DiscountCalculator*`

> Note: Benchmarks live in a separate project (e.g., `MyApp.Benchmarks`), not in the test project.

## Summary

- Use constructor/`Dispose` for per-test setup/teardown
- Use `IAsyncLifetime` for async initialization
- Use Collection Fixtures to share expensive resources
- Use `ITestOutputHelper` for diagnostic output
- Builder pattern for flexible test data
- FluentAssertions for readable assertions
- `[Theory]` with `[InlineData]`/`[MemberData]` for parameterized tests
- One test, one concept
