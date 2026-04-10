# TDD and Design

## TDD Is Also a Design Methodology

Practicing TDD naturally leads to adherence to these design principles:

1. **YAGNI (You Aren't Gonna Need It)**: Minimal implementation
2. **Single Responsibility Principle**: Testable classes have clear responsibilities
3. **Dependency Inversion Principle**: Using test doubles naturally leads to interface-based design
4. **Loose Coupling**: Testable code has low coupling

## Testable vs. Untestable Design

### Untestable Design

```csharp
public class OrderService
{
    public void ProcessOrder(int orderId)
    {
        // Direct DB access
        using var context = new AppDbContext("Server=localhost;Database=orders;...");
        var order = context.Orders.Find(orderId)
            ?? throw new NotFoundException();

        // Direct external API call
        var client = new HttpClient();
        client.PostAsJsonAsync("https://payment.api/charge", order).Wait();
    }
}
```

Problems:
- Requires a database (slow)
- Requires an external API (unstable)
- Tests depend on the environment

### Testable Design

```csharp
// Abstract dependencies with interfaces
public interface IOrderRepository
{
    Task<Order?> FindByIdAsync(int id);
}

public interface IPaymentGateway
{
    Task<PaymentResult> ChargeAsync(decimal amount);
}

// Dependency injection
public class OrderService(
    IOrderRepository orderRepo,
    IPaymentGateway payment)
{
    public async Task ProcessOrderAsync(int orderId)
    {
        var order = await orderRepo.FindByIdAsync(orderId)
            ?? throw new NotFoundException();
        await payment.ChargeAsync(order.Amount);
    }
}
```

Test:

```csharp
[Fact]
public async Task ProcessOrder_ChargesPayment()
{
    // Given
    var repo = Substitute.For<IOrderRepository>();
    repo.FindByIdAsync(1).Returns(new Order { Id = 1, Amount = 5000m });

    var payment = Substitute.For<IPaymentGateway>();
    payment.ChargeAsync(5000m).Returns(PaymentResult.Success);

    var service = new OrderService(repo, payment);

    // When
    await service.ProcessOrderAsync(1);

    // Then
    await payment.Received(1).ChargeAsync(5000m);
}
```

## Design Benefits from TDD

### 1. Interface Clarification

Writing tests first produces simple, intuitive APIs.

```csharp
// Starting from the test leads to a clean API
[Fact]
public void Cart_AddItem_IncreasesTotal()
{
    var cart = new ShoppingCart();
    cart.Add(new Item("Book", 1000m));
    Assert.Equal(1000m, cart.Total());
}
```

### 2. Separation of Responsibilities

Complex tests = a sign that the class is too complex.

```csharp
// Too many responsibilities -> complex tests
public class OrderProcessor
{
    // Inventory check + payment + email + shipping
}

// Separated responsibilities -> simple tests
public class OrderProcessor(
    IInventoryService inventory,
    IPaymentService payment,
    INotificationService notification,
    IShippingService shipping)
{
    // Each dependency is independently testable
}
```

### 3. Loose Coupling

Using interfaces naturally leads to loose coupling.

```csharp
// Tightly coupled (hard to test)
public class UserService
{
    public User CreateUser(string email)
    {
        using var context = new AppDbContext(); // Direct creation
        // ...
    }
}

// Loosely coupled (easy to test)
public class UserService(IUserRepository repository)
{
    public User CreateUser(string email)
    {
        // Uses injected dependency
    }
}
```

## TDD and ASP.NET Core Service Decomposition

TDD naturally drives the decomposition of ASP.NET Core applications into testable layers.

```csharp
// Controller: thin, delegates to service
[ApiController]
[Route("api/[controller]")]
public class UsersController(IUserService userService) : ControllerBase
{
    [HttpGet("{id}")]
    public async Task<ActionResult<UserDto>> GetUser(int id)
    {
        var user = await userService.GetByIdAsync(id);
        return user is null ? NotFound() : Ok(user);
    }
}

// Service: orchestrates business logic
public class UserService(IUserRepository repo, IEmailService email) : IUserService
{
    public async Task<UserDto?> GetByIdAsync(int id)
    {
        var user = await repo.FindByIdAsync(id);
        return user?.ToDto();
    }
}

// Repository: data access only
public class UserRepository(AppDbContext context) : IUserRepository
{
    public async Task<User?> FindByIdAsync(int id)
    {
        return await context.Users.FindAsync(id);
    }
}
```

Each layer is independently testable:

```csharp
// Test the controller in isolation
[Fact]
public async Task GetUser_WhenNotFound_ReturnsNotFound()
{
    var service = Substitute.For<IUserService>();
    service.GetByIdAsync(999).Returns((UserDto?)null);
    var controller = new UsersController(service);

    var result = await controller.GetUser(999);

    Assert.IsType<NotFoundResult>(result.Result);
}

// Test the service in isolation
[Fact]
public async Task GetById_WhenExists_ReturnsDto()
{
    var repo = Substitute.For<IUserRepository>();
    repo.FindByIdAsync(1).Returns(new User { Id = 1, Name = "Alice" });
    var service = new UserService(repo, Substitute.For<IEmailService>());

    var dto = await service.GetByIdAsync(1);

    Assert.NotNull(dto);
    Assert.Equal("Alice", dto.Name);
}
```

## Testability Principles

### 1. Inject External Dependencies

```csharp
// Hard to test: obtains time directly
public Report GenerateReport()
{
    var now = DateTime.UtcNow;
    // ...
}

// Easy to test: abstracted via interface
public interface IClock
{
    DateTimeOffset UtcNow { get; }
}

public Report GenerateReport(IClock clock)
{
    var now = clock.UtcNow;
    // ...
}

// In test
var clock = Substitute.For<IClock>();
clock.UtcNow.Returns(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
```

### 2. Separate Side Effects

```csharp
// Side effects mixed in
public async Task<Report> ProcessAndSaveAsync(Data data, AppDbContext context)
{
    var result = ExpensiveCalculation(data); // Pure computation
    context.Reports.Add(result);
    await context.SaveChangesAsync();        // Side effect
    return result;
}

// Side effects separated
public Report Process(Data data)
{
    return ExpensiveCalculation(data); // Pure
}

public async Task SaveAsync(Report report, AppDbContext context)
{
    context.Reports.Add(report);
    await context.SaveChangesAsync();  // Side effect isolated
}
```

### 3. Make It Deterministic

```csharp
// Random (not reproducible)
public string GenerateToken()
{
    return Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
}

// Deterministic (abstracted via interface)
public interface ITokenGenerator
{
    string Generate();
}

// In test
var generator = Substitute.For<ITokenGenerator>();
generator.Generate().Returns("fixed-token-for-test");
```

## NetArchTest.Rules for Architecture Constraints

Use NetArchTest to enforce architectural rules as tests.

```csharp
using NetArchTest.Rules;

[Fact]
public void Domain_ShouldNotReference_Infrastructure()
{
    var result = Types.InAssembly(typeof(Order).Assembly)
        .ShouldNot()
        .HaveDependencyOn("MyApp.Infrastructure")
        .GetResult();

    Assert.True(result.IsSuccessful,
        $"Domain references Infrastructure: {string.Join(", ", result.FailingTypeNames ?? [])}");
}

[Fact]
public void Controllers_ShouldInheritFromControllerBase()
{
    var result = Types.InAssembly(typeof(UsersController).Assembly)
        .That()
        .HaveNameEndingWith("Controller")
        .Should()
        .Inherit(typeof(ControllerBase))
        .GetResult();

    Assert.True(result.IsSuccessful);
}

[Fact]
public void Services_ShouldNotAccessDbContextDirectly()
{
    var result = Types.InAssembly(typeof(UserService).Assembly)
        .That()
        .HaveNameEndingWith("Service")
        .ShouldNot()
        .HaveDependencyOn("Microsoft.EntityFrameworkCore")
        .GetResult();

    Assert.True(result.IsSuccessful);
}
```

## Summary

Practicing TDD leads to:
- Interface-based abstraction used naturally
- Responsibilities properly separated
- Loosely coupled code
- Dependency injection used naturally
- Clean ASP.NET Core layered architecture

TDD = Design-Driven Development
