# External API Mock Patterns

Patterns for stubbing external HTTP API dependencies using WireMock.NET
and interface-based DI overrides via `WebApplicationFactory.WithWebHostBuilder`.

## Recommended Pattern: WireMock.NET HTTP-Level Stubbing

WireMock.NET creates an in-process HTTP server that intercepts real HTTP requests.
This tests the full HTTP client pipeline including serialization, headers, and error handling.

```csharp
// Production code: typed HttpClient
public class PaymentGatewayClient(HttpClient httpClient)
{
    public async Task<PaymentResult> ChargeAsync(ChargeRequest request)
    {
        var response = await httpClient.PostAsJsonAsync("/api/charge", request);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<PaymentResult>()
            ?? throw new InvalidOperationException("Null payment result");
    }
}

// Registration in Program.cs / Startup
services.AddHttpClient<PaymentGatewayClient>(client =>
{
    client.BaseAddress = new Uri(configuration["PaymentGateway:BaseUrl"]!);
    client.Timeout = TimeSpan.FromSeconds(10);
});
```

## WireMock.NET Test Setup

### Basic Stub (Success Response)

```csharp
_wireMock.Given(
    Request.Create()
        .WithPath("/api/charge")
        .UsingPost()
        .WithBody(new JsonMatcher(new { amount = 100 }))
).RespondWith(
    Response.Create()
        .WithStatusCode(200)
        .WithHeader("Content-Type", "application/json")
        .WithBodyAsJson(new
        {
            transactionId = "txn_123",
            status = "succeeded"
        })
);
```

### Error Response

```csharp
_wireMock.Given(
    Request.Create().WithPath("/api/charge").UsingPost()
).RespondWith(
    Response.Create()
        .WithStatusCode(500)
        .WithBodyAsJson(new { error = "Internal Server Error" })
);
```

### Timeout Simulation

```csharp
_wireMock.Given(
    Request.Create().WithPath("/api/charge").UsingPost()
).RespondWith(
    Response.Create()
        .WithDelay(TimeSpan.FromSeconds(30)) // Exceeds HttpClient timeout
);
```

### Request Verification (Spy)

```csharp
// After the test action
_wireMock.LogEntries.Should().ContainSingle(entry =>
    entry.RequestMessage.Path == "/api/charge" &&
    entry.RequestMessage.Method == "POST");

// Verify request body
var logEntry = _wireMock.LogEntries.First(e => e.RequestMessage.Path == "/api/charge");
var body = JsonSerializer.Deserialize<ChargeRequest>(logEntry.RequestMessage.Body!);
body!.Amount.Should().Be(100);
```

## Integration with WebApplicationFactory

Override the service configuration to point `HttpClient` base URLs to WireMock:

```csharp
public class PaymentIntegrationTests : IClassFixture<IntegrationTestFixture>, IAsyncLifetime
{
    private readonly IntegrationTestFixture _fixture;
    private WireMockServer _wireMock = default!;
    private HttpClient _client = default!;

    public PaymentIntegrationTests(IntegrationTestFixture fixture)
        => _fixture = fixture;

    public Task InitializeAsync()
    {
        _wireMock = WireMockServer.Start();

        _client = _fixture.Factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                // Override the payment gateway base URL
                services.Configure<PaymentGatewayOptions>(opts =>
                    opts.BaseUrl = _wireMock.Url!);

                // Alternative: override HttpClient directly
                services.AddHttpClient<PaymentGatewayClient>(client =>
                    client.BaseAddress = new Uri(_wireMock.Url!));
            });
        }).CreateClient();

        return Task.CompletedTask;
    }

    public Task DisposeAsync()
    {
        _wireMock.Dispose();
        return Task.CompletedTask;
    }
}
```

## Alternative Pattern: Interface-Based DI Override

When WireMock.NET is not suitable (e.g., non-HTTP dependencies), use interface-based DI:

```csharp
// Production code: interface
public interface IPaymentGateway
{
    Task<PaymentResult> ChargeAsync(decimal amount, CancellationToken ct = default);
}

// Production implementation
public class StripePaymentGateway(HttpClient httpClient) : IPaymentGateway
{
    public async Task<PaymentResult> ChargeAsync(decimal amount, CancellationToken ct)
    {
        // Real API call
    }
}

// Test stub
public class StubPaymentGateway : IPaymentGateway
{
    public PaymentResult? ResultToReturn { get; set; }
    public Exception? ExceptionToThrow { get; set; }
    public List<decimal> RecordedAmounts { get; } = [];

    public Task<PaymentResult> ChargeAsync(decimal amount, CancellationToken ct)
    {
        RecordedAmounts.Add(amount);

        if (ExceptionToThrow is not null)
            throw ExceptionToThrow;

        return Task.FromResult(ResultToReturn
            ?? new PaymentResult { TransactionId = "stub_txn", Status = "succeeded" });
    }
}

// Override in test
var stub = new StubPaymentGateway();
_client = _fixture.Factory.WithWebHostBuilder(builder =>
{
    builder.ConfigureServices(services =>
    {
        services.RemoveAll<IPaymentGateway>();
        services.AddSingleton<IPaymentGateway>(stub);
    });
}).CreateClient();
```

## Prohibited Practices

- Do not use `#if DEBUG` or conditional compilation to change production behavior for tests
- Do not mock `HttpMessageHandler` directly when WireMock.NET can be used — WireMock tests the full HTTP pipeline
- Do not use `Environment.SetEnvironmentVariable` in tests — it causes interference between parallel tests
- Do not create real network connections to external services in integration tests
- Do not hardcode WireMock ports — use `WireMockServer.Start()` which picks a random available port
