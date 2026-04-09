# Test Doubles

Techniques for isolating external dependencies to make tests fast and stable.

## Test Double Implementation in .NET

In .NET, interfaces (`IXxx`) are used to implement test doubles.
Primary approaches: NSubstitute, Moq, and manual fakes.

## The 5 Types of Test Doubles

### 1. Dummy

Fills a parameter slot but is never actually used.

```csharp
public class DummyLogger : ILogger<UserService>
{
    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
    public bool IsEnabled(LogLevel logLevel) => false;
    public void Log<TState>(LogLevel logLevel, EventId eventId, TState state,
        Exception? exception, Func<TState, Exception?, string> formatter) { }
}
```

With NSubstitute, a dummy is simply an unused substitute:

```csharp
var dummyLogger = Substitute.For<ILogger<UserService>>();
```

### 2. Stub

Returns predetermined values.

#### NSubstitute

```csharp
[Fact]
public void GetUserName_WhenUserExists_ReturnsName()
{
    // Given
    var repo = Substitute.For<IUserRepository>();
    repo.FindById(1).Returns(new User { Id = 1, Name = "Test User" });
    var service = new UserService(repo);

    // When
    var name = service.GetUserName(1);

    // Then
    Assert.Equal("Test User", name);
}
```

#### Moq

```csharp
[Fact]
public void GetUserName_WhenUserExists_ReturnsName()
{
    // Given
    var mockRepo = new Mock<IUserRepository>();
    mockRepo.Setup(r => r.FindById(1))
            .Returns(new User { Id = 1, Name = "Test User" });
    var service = new UserService(mockRepo.Object);

    // When
    var name = service.GetUserName(1);

    // Then
    Assert.Equal("Test User", name);
}
```

Use cases:
- Fix DB query results
- Control external API responses

### 3. Spy

Records calls for later verification.

```csharp
public class SpyEmailService : IEmailService
{
    public List<(string To, string Subject, string Body)> SentEmails { get; } = [];

    public Task SendAsync(string to, string subject, string body)
    {
        SentEmails.Add((to, subject, body));
        return Task.CompletedTask;
    }
}

[Fact]
public async Task Register_SendsWelcomeEmail()
{
    // Given
    var spy = new SpyEmailService();
    var service = new RegistrationService(spy);

    // When
    await service.RegisterAsync("user@example.com");

    // Then
    Assert.Single(spy.SentEmails);
    Assert.Equal("user@example.com", spy.SentEmails[0].To);
}
```

### 4. Mock

Verifies expected calls. Use NSubstitute or Moq.

#### NSubstitute

```csharp
[Fact]
public void DeleteUser_CallsRepository()
{
    // Given
    var repo = Substitute.For<IUserRepository>();
    var service = new UserService(repo);

    // When
    service.DeleteUser(123);

    // Then
    repo.Received(1).Delete(123);
}
```

#### Moq

```csharp
[Fact]
public void DeleteUser_CallsRepository()
{
    // Given
    var mockRepo = new Mock<IUserRepository>();
    var service = new UserService(mockRepo.Object);

    // When
    service.DeleteUser(123);

    // Then
    mockRepo.Verify(r => r.Delete(123), Times.Once);
}
```

Mock vs Spy:
- Mock: Set expectations beforehand and verify (behavior verification)
- Spy: Record actual calls and check afterwards (state verification)

### 5. Fake

A lightweight working implementation (e.g., in-memory DB).

```csharp
public class InMemoryUserRepository : IUserRepository
{
    private readonly Dictionary<int, User> _users = new();
    private int _nextId = 1;

    public User? FindById(int id) =>
        _users.GetValueOrDefault(id);

    public User Save(NewUser newUser)
    {
        var user = new User { Id = _nextId, Name = newUser.Name };
        _users[_nextId] = user;
        _nextId++;
        return user;
    }

    public void Delete(int id) =>
        _users.Remove(id);
}

[Fact]
public void Save_ThenFindById_ReturnsUser()
{
    // Given
    var repo = new InMemoryUserRepository();

    // When
    var saved = repo.Save(new NewUser { Name = "Alice" });
    var found = repo.FindById(saved.Id);

    // Then
    Assert.NotNull(found);
    Assert.Equal("Alice", found.Name);
}
```

Use cases:
- Complex business logic tests
- Tests combining multiple operations
- When behavior close to the real implementation is needed

## WireMock.NET for External HTTP APIs

When the system under test calls external HTTP APIs, use WireMock.NET to simulate responses.

```csharp
using WireMock.Server;
using WireMock.RequestBuilders;
using WireMock.ResponseBuilders;

public class PaymentGatewayTests : IDisposable
{
    private readonly WireMockServer _server;
    private readonly PaymentClient _client;

    public PaymentGatewayTests()
    {
        _server = WireMockServer.Start();
        _client = new PaymentClient(new HttpClient
        {
            BaseAddress = new Uri(_server.Url!)
        });
    }

    [Fact]
    public async Task Charge_WhenSuccessful_ReturnsTransactionId()
    {
        // Given
        _server.Given(
            Request.Create().WithPath("/api/charge").UsingPost()
        ).RespondWith(
            Response.Create()
                .WithStatusCode(200)
                .WithBodyAsJson(new { TransactionId = "txn_123" })
        );

        // When
        var result = await _client.ChargeAsync(5000m);

        // Then
        Assert.Equal("txn_123", result.TransactionId);
    }

    [Fact]
    public async Task Charge_WhenServerError_ThrowsPaymentException()
    {
        // Given
        _server.Given(
            Request.Create().WithPath("/api/charge").UsingPost()
        ).RespondWith(
            Response.Create().WithStatusCode(500)
        );

        // When / Then
        await Assert.ThrowsAsync<PaymentException>(
            () => _client.ChargeAsync(5000m));
    }

    public void Dispose() => _server.Stop();
}
```

## Test Double Selection Guide

```
What do you want to test?
  +-- Return value only        -> Stub
  +-- Whether it was called    -> Mock (NSubstitute / Moq)
  +-- Call history              -> Spy
  +-- Complex state transitions -> Fake
  +-- Nothing (fill parameter) -> Dummy
```

| Situation | Recommended | Reason |
|-----------|-------------|--------|
| DB access | Fake (InMemory) / Stub | Fast, state management |
| External API calls | Stub / WireMock.NET | Fixed responses, isolation |
| Side effects (email, etc.) | Spy / Mock | Verify send history |
| Time / random | Stub (via interface) | Fixed values for reproducibility |

## NSubstitute vs Moq: When to Use Each

| Aspect | NSubstitute | Moq |
|--------|-------------|-----|
| Syntax | Clean, fluent, less ceremony | Explicit `Setup`/`Verify` |
| Learning curve | Lower | Slightly higher |
| Arg matching | `Arg.Is<T>(predicate)` | `It.Is<T>(predicate)` |
| Strict mode | Not built-in | `MockBehavior.Strict` available |
| Community | Growing | Established, large ecosystem |
| Recommendation | Default choice for new projects | Use if team already familiar |

## Anti-pattern: Excessive Mocking

```csharp
// Bad: Mocking everything
[Fact]
public void CalculatePrice()
{
    var mockItem = Substitute.For<IItem>();
    mockItem.Price.Returns(100m);
    // Mocks everywhere - unclear what is being tested
}

// Good: Combine real objects with targeted mocks
[Fact]
public void CalculatePrice()
{
    var item = new Item { Name = "Book", Price = 100m };
    var cart = new ShoppingCart();
    cart.AddItem(item);
    Assert.Equal(100m, cart.Total());
}
```

Principle: Use the simplest test double. When in doubt, start with a Stub.
