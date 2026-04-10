---
paths:
  - "**/*.cs"
---

# C# Coding Style Rules

Follow the official .NET coding conventions (https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions).
Target runtime: **.NET 10**. Use `dotnet format` with `.editorconfig` as the baseline and adhere to the rules below.

## CS1: Formatting Basics

- Indentation: 4 spaces (no tabs)
- File encoding: UTF-8 (with BOM for `.cs` files if required by tooling)
- Max line width: 120 characters
- Newline at end of file
- No trailing whitespace
- `.editorconfig` is the **single source of truth** for all formatting rules

```csharp
// .editorconfig (root)
root = true

[*.cs]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true
max_line_length = 120
```

## CS2: Analyzer Setup

Required analyzers:

| Analyzer | Rule Prefix | Purpose |
|---|---|---|
| .NET Analyzers (built-in) | `CAxxxx` | Code quality & design |
| Roslynator | `RCSxxxx` | Refactoring suggestions |
| StyleCop.Analyzers | `SAxxxx` | Style consistency |

Optional (recommended):

| Analyzer | Rule Prefix | Purpose |
|---|---|---|
| Meziantou.Analyzer | `MA0xxx` | Additional best practices |
| SonarAnalyzer.CSharp | `Sxxxx` | Security & reliability |

All severity levels are configured via `.editorconfig`. Enforce zero-warning builds in `Directory.Build.props`:

```xml
<!-- Directory.Build.props -->
<Project>
  <PropertyGroup>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <AnalysisLevel>latest-recommended</AnalysisLevel>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  </PropertyGroup>
</Project>
```

```csharp
// .editorconfig severity examples
[*.cs]
dotnet_diagnostic.CA1062.severity = warning
dotnet_diagnostic.SA1200.severity = none
dotnet_diagnostic.IDE0005.severity = warning
```

## CS3: Naming Conventions

| Item | Style | Example |
|---|---|---|
| Types (class, struct, record, enum) | `PascalCase` | `CustomerOrder` |
| Interfaces | `IPascalCase` | `IOrderService` |
| Methods | `PascalCase` | `CalculateTotal` |
| Properties | `PascalCase` | `FirstName` |
| Events | `PascalCase` | `OrderPlaced` |
| Namespaces | `PascalCase` | `MyApp.Services` |
| Public fields | `PascalCase` | `MaxRetryCount` |
| Parameters | `camelCase` | `orderId` |
| Local variables | `camelCase` | `itemCount` |
| Private/internal fields | `_camelCase` | `_logger` |
| Constants | `PascalCase` | `MaxBufferSize` |
| Local constants | `PascalCase` | `DefaultTimeout` |
| Type parameters | `TPascalCase` | `TEntity`, `TKey` |
| Enum members | `PascalCase` | `OrderStatus.Pending` |

> **Note:** The .NET runtime team convention uses `PascalCase` for constants (not `SCREAMING_SNAKE_CASE`). However, if the project or team convention mandates `SCREAMING_SNAKE_CASE` for compile-time constants, document it in `.editorconfig` and apply consistently.

```csharp
public interface IOrderRepository
{
    Task<Order?> FindByIdAsync(int orderId);
}

public class OrderService : IOrderRepository
{
    private readonly ILogger<OrderService> _logger;
    private const int MaxRetryCount = 3;

    public OrderService(ILogger<OrderService> logger)
    {
        _logger = logger;
    }

    public async Task<Order?> FindByIdAsync(int orderId)
    {
        var cacheKey = $"order_{orderId}";
        // ...
    }
}
```

## CS4: File Organization

- **One primary type per file**; file name must match the type name (e.g., `OrderService.cs`)
- Nested helper types or private types used only by the primary type may remain in the same file
- Use **file-scoped namespaces** (C# 10+)
- Order within a file:
  1. `using` directives
  2. Namespace declaration
  3. Type declaration

Member order within a type:

1. Constants and static readonly fields
2. Fields
3. Constructors
4. Properties
5. Methods (public first, then protected, then private)
6. Nested types

```csharp
using Microsoft.Extensions.Logging;

namespace MyApp.Services;

public sealed class OrderService
{
    private const int MaxRetries = 3;

    private readonly ILogger<OrderService> _logger;
    private readonly IOrderRepository _repository;

    public OrderService(ILogger<OrderService> logger, IOrderRepository repository)
    {
        _logger = logger;
        _repository = repository;
    }

    public string ServiceName => "OrderService";

    public async Task<Order> GetOrderAsync(int id)
    {
        // ...
    }

    private void ValidateOrder(Order order)
    {
        // ...
    }
}
```

## CS5: Using Directives

- Place common `global using` directives in a dedicated `GlobalUsings.cs` file
- Enable implicit usings: `<ImplicitUsings>enable</ImplicitUsings>` in the project file
- Sort order: `System.*` namespaces first, then alphabetical
- Remove unused usings — enforce via `IDE0005`

```csharp
// GlobalUsings.cs
global using System.Collections.Immutable;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Logging;
```

```xml
<!-- .csproj -->
<PropertyGroup>
    <ImplicitUsings>enable</ImplicitUsings>
</PropertyGroup>
```

```csharp
// .editorconfig
dotnet_diagnostic.IDE0005.severity = warning
dotnet_sort_system_directives_first = true
dotnet_separate_import_directive_groups = false
```

## CS6: Type Definitions

- Prefer `record` for immutable data transfer objects and value semantics
- Prefer `record struct` for small, stack-allocated value types
- Use `sealed` on classes when inheritance is not intended
- Use **primary constructors** (C# 12+) where appropriate to reduce boilerplate

```csharp
// Immutable data — use record
public record OrderSummary(int Id, string CustomerName, decimal Total);

// Small value type — use record struct
public readonly record struct Coordinate(double Latitude, double Longitude);

// Sealed class — no inheritance intended
public sealed class EmailSender
{
    public Task SendAsync(string to, string subject, string body) => throw new NotImplementedException();
}

// Primary constructor (C# 12+)
public sealed class OrderValidator(ILogger<OrderValidator> logger, IOrderRepository repository)
{
    public bool Validate(Order order)
    {
        logger.LogInformation("Validating order {OrderId}", order.Id);
        return order.Items.Count > 0;
    }
}
```

## CS7: Properties and Fields

- Prefer **auto-properties** over manual backing fields
- Use `init` for properties that should be immutable after construction
- Use `required` (C# 11+) for mandatory properties in object initializers
- Use **expression-bodied members** for single-expression getters

```csharp
public class Customer
{
    // Required + init — must be set at creation, immutable after
    public required string Name { get; init; }

    // Auto-property with init
    public string? Email { get; init; }

    // Expression-bodied read-only property
    public string DisplayName => $"{Name} <{Email}>";

    // Computed property with backing logic
    public bool IsValid => !string.IsNullOrWhiteSpace(Name);
}

// Usage
var customer = new Customer { Name = "Alice", Email = "alice@example.com" };
```

## CS8: Null Safety

- `<Nullable>enable</Nullable>` is **mandatory** in all projects
- **Never** use the `!` (null-forgiving) operator in production code
- Use null-conditional (`?.`), null-coalescing (`??`), and null-coalescing assignment (`??=`) patterns
- Annotate all nullable reference types explicitly

```csharp
// Good: proper null handling
public string GetDisplayName(User? user)
{
    var name = user?.Profile?.DisplayName ?? "Anonymous";
    return name;
}

// Good: null-coalescing assignment
public IList<string> GetTags(Article article)
{
    article.Tags ??= new List<string>();
    return article.Tags;
}

// Bad: null-forgiving operator — never in production
// var name = user!.Name;

// Good: guard clause
public void Process(Order order)
{
    ArgumentNullException.ThrowIfNull(order);
    // ...
}
```

```xml
<!-- .csproj -->
<PropertyGroup>
    <Nullable>enable</Nullable>
</PropertyGroup>
```

## CS9: Pattern Matching

- Prefer **switch expressions** over `if-else` chains for type/value dispatch
- Use `is`, `and`, `or`, `not` pattern combinators
- Ensure switches are **exhaustive** — use discard `_` as the final arm

```csharp
// Switch expression with type patterns
public decimal CalculateDiscount(Customer customer) => customer switch
{
    PremiumCustomer { Years: > 5 } => 0.20m,
    PremiumCustomer => 0.10m,
    RegularCustomer { OrderCount: > 100 } => 0.05m,
    _ => 0m,
};

// Pattern combinators
public bool IsValidHttpStatus(int code) => code is >= 200 and < 300;

public string Classify(int value) => value switch
{
    < 0 => "Negative",
    0 => "Zero",
    > 0 and <= 100 => "Small",
    _ => "Large",
};

// 'not' pattern for null checks
if (result is not null)
{
    Process(result);
}
```

## CS10: LINQ and Expressions

- Prefer **method (fluent) syntax** over query syntax
- Use **expression-bodied methods** for single-expression implementations
- Avoid excessive chaining — break into intermediate variables when chains exceed 3–4 operations or become hard to read

```csharp
// Good: method syntax
var activeUsers = users
    .Where(u => u.IsActive)
    .OrderBy(u => u.LastLogin)
    .Select(u => new UserSummary(u.Id, u.Name))
    .ToList();

// Good: break long chains into intermediate variables
var recentOrders = orders.Where(o => o.Date > cutoff);
var grouped = recentOrders.GroupBy(o => o.CustomerId);
var summaries = grouped
    .Select(g => new OrderSummary(g.Key, g.Sum(o => o.Total)))
    .ToList();

// Expression-bodied method for simple logic
public bool IsEligible(User user) => user.IsActive && user.Age >= 18;

// Avoid: query syntax (unless significantly more readable for joins)
// var q = from u in users where u.IsActive select u.Name;
```

## CS11: Async/Await

- Suffix async methods with `Async` (e.g., `GetOrderAsync`)
- Return `Task`, `Task<T>`, or `ValueTask<T>` — never `async void` (except event handlers)
- Always prefer `await` over `.Result` or `.Wait()` to avoid deadlocks
- Use `ConfigureAwait(false)` in **library code** (not in application/UI code)
- Use `CancellationToken` in all async APIs

```csharp
// Good: async method with CancellationToken
public async Task<Order?> GetOrderAsync(int id, CancellationToken cancellationToken = default)
{
    var order = await _repository.FindByIdAsync(id, cancellationToken);
    return order;
}

// Good: ValueTask for hot paths that often complete synchronously
public ValueTask<CachedItem?> GetCachedAsync(string key)
{
    if (_cache.TryGetValue(key, out var item))
    {
        return ValueTask.FromResult<CachedItem?>(item);
    }

    return LoadFromStoreAsync(key);
}

// Good: ConfigureAwait(false) in library code
public async Task<string> ReadContentAsync(string path, CancellationToken cancellationToken)
{
    var bytes = await File.ReadAllBytesAsync(path, cancellationToken).ConfigureAwait(false);
    return Encoding.UTF8.GetString(bytes);
}

// Bad: blocking on async code
// var order = GetOrderAsync(id).Result;  // deadlock risk
// GetOrderAsync(id).Wait();              // deadlock risk
```

## CS12: Error Handling

- Prefer **Result/discriminated union patterns** (e.g., `OneOf<T, Error>`) for expected failures
- Reserve exceptions for truly **exceptional, unexpected** conditions
- Always include **meaningful messages** in exceptions
- Use **structured logging** with semantic parameters

```csharp
// Result pattern using a simple discriminated union
public readonly record struct Result<T>
{
    public T? Value { get; }
    public string? Error { get; }
    public bool IsSuccess => Error is null;

    private Result(T value) { Value = value; Error = null; }
    private Result(string error) { Value = default; Error = error; }

    public static Result<T> Success(T value) => new(value);
    public static Result<T> Failure(string error) => new(error);
}

// Usage
public Result<Order> CreateOrder(OrderRequest request)
{
    if (request.Items.Count == 0)
    {
        return Result<Order>.Failure("Order must contain at least one item.");
    }

    var order = new Order(request);
    return Result<Order>.Success(order);
}

// Exceptions for truly exceptional cases
public void ProcessPayment(Payment payment)
{
    ArgumentNullException.ThrowIfNull(payment);

    if (payment.Amount <= 0)
    {
        throw new ArgumentOutOfRangeException(
            nameof(payment.Amount),
            payment.Amount,
            "Payment amount must be positive.");
    }
}

// Structured logging
_logger.LogError(
    "Failed to process order {OrderId} for customer {CustomerId}: {Error}",
    order.Id,
    order.CustomerId,
    ex.Message);
```

## CS13: XML Documentation

- Use `///` doc comments for **all public APIs**
- Enable `CS1591` warning via `<DocumentationFile>` to enforce completeness
- Include `<summary>`, `<param>`, `<returns>`, and `<exception>` tags
- Use [DocFX](https://dotnet.github.io/docfx/) for documentation generation

```csharp
/// <summary>
/// Retrieves an order by its unique identifier.
/// </summary>
/// <param name="orderId">The unique identifier of the order.</param>
/// <param name="cancellationToken">A token to cancel the asynchronous operation.</param>
/// <returns>
/// The order if found; otherwise, <see langword="null"/>.
/// </returns>
/// <exception cref="ArgumentOutOfRangeException">
/// Thrown when <paramref name="orderId"/> is less than or equal to zero.
/// </exception>
public async Task<Order?> GetOrderAsync(int orderId, CancellationToken cancellationToken = default)
{
    ArgumentOutOfRangeException.ThrowIfNegativeOrZero(orderId);
    return await _repository.FindByIdAsync(orderId, cancellationToken);
}
```

```xml
<!-- .csproj — enable documentation file to enforce CS1591 -->
<PropertyGroup>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
    <NoWarn>$(NoWarn);CS1591</NoWarn> <!-- Remove this line to enforce on all public APIs -->
</PropertyGroup>
```

## CS14: Attributes

- Place **one attribute per line** when multiple attributes are present
- Group related attributes together
- Use the short form for well-known attributes (e.g., `[Serializable]` not `[SerializableAttribute]`)

```csharp
// One attribute per line
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class OrdersController : ControllerBase
{
    [HttpGet("{id}")]
    [ProducesResponseType(typeof(Order), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetAsync(int id)
    {
        // ...
    }
}

// Data annotations — group related attributes
public class CreateOrderRequest
{
    [Required]
    [StringLength(200, MinimumLength = 1)]
    [JsonPropertyName("customerName")]
    public required string CustomerName { get; init; }

    [Required]
    [Range(0.01, double.MaxValue)]
    [JsonPropertyName("total")]
    public required decimal Total { get; init; }
}
```

## CS15: String Handling

- Use **string interpolation** `$""` over string concatenation or `string.Format`
- Use **raw string literals** `"""..."""` (C# 11+) for multiline strings and embedded quotes
- Use `StringComparison.Ordinal` or `StringComparison.OrdinalIgnoreCase` for non-culture-sensitive comparisons
- Use `string.Create` or `StringBuilder` for performance-critical string building

```csharp
// Good: string interpolation
var message = $"Order {orderId} placed by {customerName} at {DateTime.UtcNow:O}";

// Good: raw string literal for multiline / embedded quotes
var json = """
    {
        "name": "Alice",
        "role": "Admin"
    }
    """;

// Good: ordinal comparison for non-culture scenarios
if (status.Equals("active", StringComparison.OrdinalIgnoreCase))
{
    Process();
}

// Good: Span-based comparison to avoid allocation
ReadOnlySpan<char> span = input.AsSpan().Trim();
if (span.Equals("OK", StringComparison.Ordinal))
{
    // ...
}

// Bad: culture-sensitive comparison for identifiers
// if (status == "active")  // uses CurrentCulture — unpredictable in some locales
```

## CS16: General Advice

- Leverage `dotnet format` + `.editorconfig` actively — run in CI to enforce style
- Use `dotnet watch` for rapid development feedback loops
- Prefer **immutability**: use `readonly`, `init`, `record`, `ImmutableArray<T>` where possible
- Use `Span<T>` / `Memory<T>` / `ReadOnlySpan<T>` for performance-critical paths to minimize allocations
- Prefer `IAsyncEnumerable<T>` for streaming data over materializing large collections
- Use **source generators** over runtime reflection where possible

```csharp
// Immutable collection
private static readonly ImmutableArray<string> AllowedRoles =
    ImmutableArray.Create("Admin", "Editor", "Viewer");

// Span for zero-allocation parsing
public static int CountWords(ReadOnlySpan<char> text)
{
    var count = 0;
    foreach (var range in text.Split(' '))
    {
        if (!text[range].IsEmpty)
        {
            count++;
        }
    }
    return count;
}

// IAsyncEnumerable for streaming
public async IAsyncEnumerable<Order> GetOrdersAsync(
    [EnumeratorCancellation] CancellationToken cancellationToken = default)
{
    await foreach (var order in _repository.StreamAllAsync(cancellationToken))
    {
        yield return order;
    }
}

// Source generator — prefer over reflection
// Use [JsonSerializable] for System.Text.Json source generation
[JsonSerializable(typeof(Order))]
[JsonSerializable(typeof(List<Order>))]
internal partial class AppJsonContext : JsonSerializerContext;
```

```ini
# Run formatting in CI
dotnet format --verify-no-changes --verbosity diagnostic
```
