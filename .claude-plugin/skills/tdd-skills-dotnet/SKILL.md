---
name: tdd-skills-dotnet
description: >
  .NET-specific version of tdd-skills. Provides TDD principles and C# implementation patterns based on t-wada's teachings.
  Covers Red-Green-Refactor cycle, test implementation using xUnit ([Fact], [Theory], NSubstitute, Moq),
  interface-based test double design, and boundary value test design.
  Use when implementing tests, designing tests, or practicing TDD in .NET 10 projects.
---

# TDD Skills (.NET)

> For foundational principles, see the language-agnostic `/tdd-skills`. This skill focuses on .NET-specific implementation patterns.

Provides TDD principles and practices based on the teachings of t-wada (Takuto Wada), aligned with .NET 10 / C# 13 language features.

## Pre-check: Know-how Reference

Read relevant know-how such as testing from the Know-how INDEX under the `feedback-loop` rule.
Incorporate checklists and counter-examples into your test design.

## The Essence of TDD

TDD is a "programming technique," not a "technique for writing tests."

> "TDD is the art of turning anxiety into boredom." - t-wada

## Red-Green-Refactor Cycle

```
Red:      Write a failing test
  |
Green:    Make it pass with minimal code
  |
Refactor: Refactor
  |
Red:      Next test...
```

### Initial RED Pattern in .NET

```csharp
// The canonical first RED: throw NotImplementedException
public class ShoppingCart
{
    public decimal Total()
    {
        throw new NotImplementedException();
    }
}
```

### Green Strategies (3 Types)

1. **Fake It**: Return a constant first (safest)
2. **Triangulation**: Generalize from multiple tests
3. **Obvious Implementation**: Implement directly when the solution is clear

Details: [references/green-strategies.md](references/green-strategies.md)

## Test Structure (Given-When-Then)

```csharp
using NSubstitute;
using Xunit;

public class UserQueryServiceTests
{
    [Fact]
    public void GetUserById_WhenUserExists_ReturnsEntity()
    {
        // Given
        var mockRepo = Substitute.For<IUserRepository>();
        mockRepo.FindById(123).Returns(new User { Id = 123, Name = "Alice" });
        var query = new UserQueryService(mockRepo);

        // When
        var result = query.GetUserById(123);

        // Then
        Assert.Equal(123, result.Id);
    }
}
```

## Test Naming Conventions

| Pattern | Example |
|---------|---------|
| `MethodName_StateUnderTest_ExpectedBehavior` | `GetTotal_WhenCartIsEmpty_ReturnsZero` |
| `Given_When_Then` | `GivenEmptyCart_WhenCalculateTotal_ThenReturnsZero` |
| `Should_ExpectedBehavior_When_Condition` | `Should_ReturnError_When_InvalidId` |

In xUnit, test methods are identified by `[Fact]` or `[Theory]` attributes.
Choose one naming convention and apply it consistently across the project.

## Test Types

| Type | Target | Test Doubles | Speed |
|------|--------|--------------|-------|
| Unit | Domain, UseCase | NSubstitute / Moq / manual fakes | Fast |
| Integration | API, Repository | `WebApplicationFactory<Program>` + Testcontainers | Slow |

## Test Doubles

| Type | Purpose | .NET Implementation |
|------|---------|---------------------|
| Stub | Return fixed values | NSubstitute `.Returns()` / Moq `.Setup().Returns()` |
| Mock | Verify calls | NSubstitute `.Received()` / Moq `.Verify()` |
| Fake | Lightweight implementation | `InMemoryUserRepository : IUserRepository` |

Details: [references/test-doubles.md](references/test-doubles.md)

## F.I.R.S.T Principles

- **F**ast: Fast
- **I**ndependent: Independent
- **R**epeatable: Repeatable
- **S**elf-Validating: Self-validating
- **T**imely: Write before production code

## Troubleshooting

| Problem | Solution |
|---------|----------|
| DI service not resolved in test | Override services via `WebApplicationFactory.WithWebHostBuilder` or register manually |
| `IServiceProvider` missing in unit test | Do not resolve from DI in unit tests; inject dependencies directly via constructor |
| Async test hangs | Use `async Task` return type with `[Fact]`; avoid `.Result` or `.Wait()` |
| Database state leaks between tests | Use `Respawn` or transaction rollback per test; use `IAsyncLifetime` for setup/teardown |
| `HttpClient` calls real endpoints | Use `WebApplicationFactory` for integration tests; use NSubstitute/WireMock for unit tests |
| Moq/NSubstitute cannot mock sealed class | Extract an interface or use the Adapter pattern to wrap the sealed class |
| FluentAssertions version conflict | Pin version in `Directory.Packages.props`; ensure single version across solution |

## Blazor Frontend Testing

Testing strategy for Blazor components (parameters, event callbacks, render fragments, cascading values):

- **Test logic, not rendering**: Extract business logic from `.razor` into code-behind `.razor.cs` or service classes, and test with `[Fact]`
- **bUnit for component tests**: Render components in a test context, assert markup, trigger events
- **Validation logic**: Extract validators into pure C# classes; test independently
- **`dotnet test` = server-side only**: After GREEN, run `dotnet publish -c Release -p:PublishTrimmed=true` for WASM verification

Details: [references/blazor-testing.md](references/blazor-testing.md)

## Detailed References

| Document | Contents |
|----------|----------|
| [green-strategies.md](references/green-strategies.md) | Green strategy details and practical examples |
| [test-design.md](references/test-design.md) | Boundary value analysis and equivalence partitioning |
| [test-patterns.md](references/test-patterns.md) | xUnit lifecycle, fixtures, and parameterized tests |
| [test-doubles.md](references/test-doubles.md) | Types of test doubles and when to use them |
| [tdd-and-design.md](references/tdd-and-design.md) | The effect of TDD on design |
| [advanced-techniques.md](references/advanced-techniques.md) | Testcontainers, mutation testing, and legacy code |
| [blazor-testing.md](references/blazor-testing.md) | Blazor component, state, and event handler testing patterns |
