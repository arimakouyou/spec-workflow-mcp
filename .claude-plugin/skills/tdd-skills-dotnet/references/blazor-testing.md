# Blazor Frontend Testing Patterns

Unit testing strategy for Blazor full-stack projects covering components, state management, event handlers, and validation logic.

## Testing Strategy: Logic Extraction

Do not unit-test the Razor markup output (HTML structure, DOM event wiring, CSS classes) directly. Instead, **extract** business logic from components into code-behind files (`.razor.cs`) or standalone service classes, and test with standard `[Fact]` / `[Theory]`. Use **bUnit** for component-level testing when you need to verify rendering and interaction behavior.

```
Component
+-- Razor markup (rendering)          -> E2E tests (Playwright)
+-- Business logic (extraction target) -> Unit tests (dotnet test)
|   +-- State transitions
|   +-- Validation
|   +-- Derived calculations
|   +-- Service call orchestration
|   +-- Event handler logic
+-- Component behavior                -> bUnit tests (dotnet test)
    +-- Parameter rendering
    +-- Event callback invocation
    +-- Cascading values
    +-- Conditional rendering
```

> **Note**: `dotnet test` covers server-side logic. After GREEN, run `dotnet publish -p:PublishTrimmed=true` for Blazor WASM to verify the trimmed app compiles correctly.

---

## 1. Code-Behind Logic Extraction

### Before: Logic Embedded in Razor (Hard to Test)

```razor
@* Counter.razor *@
@page "/counter"

<p>Count: @_count</p>
<button @onclick="Increment">Click me</button>

@code {
    private int _count;

    private void Increment()
    {
        _count++;
        if (_count > 100)
            _count = 100; // Max cap buried in UI code
    }
}
```

### After: Logic in Code-Behind (Testable)

```csharp
// Counter.razor.cs
public partial class Counter
{
    private int _count;

    public static int CalculateNextCount(int current, int step, int max = 100)
    {
        var next = current + step;
        return Math.Min(next, max);
    }

    private void Increment()
    {
        _count = CalculateNextCount(_count, 1);
    }
}

// Counter.razor (minimal)
@page "/counter"
<p>Count: @_count</p>
<button @onclick="Increment">Click me</button>
```

```csharp
// CounterTests.cs
public class CounterLogicTests
{
    [Fact]
    public void CalculateNextCount_IncrementsbyStep()
    {
        Assert.Equal(8, Counter.CalculateNextCount(5, 3));
    }

    [Fact]
    public void CalculateNextCount_CapsAtMax()
    {
        Assert.Equal(100, Counter.CalculateNextCount(99, 5));
    }

    [Theory]
    [InlineData(0, 1, 100, 1)]
    [InlineData(99, 1, 100, 100)]
    [InlineData(100, 1, 100, 100)]
    [InlineData(50, 10, 55, 55)]
    public void CalculateNextCount_BoundaryValues(int current, int step, int max, int expected)
    {
        Assert.Equal(expected, Counter.CalculateNextCount(current, step, max));
    }
}
```

---

## 2. bUnit Component Testing

Use bUnit to render Blazor components in a test context and assert behavior.

### Basic Component Rendering

```csharp
using Bunit;
using Xunit;

public class CounterComponentTests : TestContext
{
    [Fact]
    public void Counter_InitialRender_ShowsZero()
    {
        // Given / When
        var cut = RenderComponent<Counter>();

        // Then
        cut.Find("p").MarkupMatches("<p>Count: 0</p>");
    }

    [Fact]
    public void Counter_ClickButton_IncrementsCount()
    {
        // Given
        var cut = RenderComponent<Counter>();

        // When
        cut.Find("button").Click();

        // Then
        cut.Find("p").MarkupMatches("<p>Count: 1</p>");
    }
}
```

### Testing with Parameters

```csharp
// UserCard.razor
<div class="user-card">
    <h3>@Name</h3>
    <p>@Email</p>
</div>

@code {
    [Parameter] public string Name { get; set; } = "";
    [Parameter] public string Email { get; set; } = "";
}
```

```csharp
[Fact]
public void UserCard_RendersNameAndEmail()
{
    var cut = RenderComponent<UserCard>(parameters => parameters
        .Add(p => p.Name, "Alice")
        .Add(p => p.Email, "alice@example.com"));

    cut.Find("h3").TextContent.Should().Be("Alice");
    cut.Find("p").TextContent.Should().Be("alice@example.com");
}
```

### Testing Event Callbacks

```csharp
// DeleteButton.razor
<button @onclick="() => OnDelete.InvokeAsync(ItemId)">Delete</button>

@code {
    [Parameter] public int ItemId { get; set; }
    [Parameter] public EventCallback<int> OnDelete { get; set; }
}
```

```csharp
[Fact]
public void DeleteButton_Click_InvokesCallbackWithId()
{
    int? deletedId = null;
    var cut = RenderComponent<DeleteButton>(parameters => parameters
        .Add(p => p.ItemId, 42)
        .Add(p => p.OnDelete, (int id) => deletedId = id));

    cut.Find("button").Click();

    Assert.Equal(42, deletedId);
}
```

### Testing with Injected Services

```csharp
[Fact]
public void UserList_RendersUsersFromService()
{
    // Given
    var userService = Substitute.For<IUserService>();
    userService.GetAllAsync().Returns([
        new UserDto { Name = "Alice" },
        new UserDto { Name = "Bob" },
    ]);
    Services.AddSingleton(userService);

    // When
    var cut = RenderComponent<UserList>();

    // Then
    var items = cut.FindAll("li");
    Assert.Equal(2, items.Count);
}
```

### Testing Cascading Values

```csharp
[Fact]
public void ThemeAwareComponent_UsesThemeFromCascadingValue()
{
    var cut = RenderComponent<ThemeAwareComponent>(parameters => parameters
        .AddCascadingValue("Theme", "dark"));

    cut.Find("div").ClassList.Should().Contain("dark-theme");
}
```

---

## 3. Validation Logic Testing

Extract validators into pure C# classes; test independently.

```csharp
// Validator class (pure C#, no Blazor dependency)
public class CreateUserValidator
{
    public ValidationResult Validate(CreateUserRequest request)
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(request.Name))
            errors.Add("Name is required.");

        if (request.Name?.Length > 50)
            errors.Add("Name must be 50 characters or fewer.");

        if (string.IsNullOrWhiteSpace(request.Email))
            errors.Add("Email is required.");
        else if (!request.Email.Contains('@'))
            errors.Add("Email format is invalid.");

        return new ValidationResult(errors);
    }
}
```

```csharp
public class CreateUserValidatorTests
{
    private readonly CreateUserValidator _validator = new();

    [Fact]
    public void Validate_ValidRequest_ReturnsNoErrors()
    {
        var request = new CreateUserRequest { Name = "Alice", Email = "alice@example.com" };
        var result = _validator.Validate(request);
        Assert.True(result.IsValid);
    }

    [Fact]
    public void Validate_EmptyName_ReturnsError()
    {
        var request = new CreateUserRequest { Name = "", Email = "alice@example.com" };
        var result = _validator.Validate(request);
        Assert.Contains(result.Errors, e => e.Contains("Name is required"));
    }

    [Fact]
    public void Validate_NameExceeds50Chars_ReturnsError()
    {
        var request = new CreateUserRequest
        {
            Name = new string('a', 51),
            Email = "alice@example.com",
        };
        var result = _validator.Validate(request);
        Assert.Contains(result.Errors, e => e.Contains("50 characters"));
    }

    [Fact]
    public void Validate_InvalidEmail_ReturnsError()
    {
        var request = new CreateUserRequest { Name = "Alice", Email = "invalid" };
        var result = _validator.Validate(request);
        Assert.Contains(result.Errors, e => e.Contains("Email format"));
    }

    [Fact]
    public void Validate_MultipleErrors_ReturnsAllErrors()
    {
        var request = new CreateUserRequest { Name = "", Email = "invalid" };
        var result = _validator.Validate(request);
        Assert.Equal(2, result.Errors.Count);
    }

    [Theory]
    [InlineData("a")]
    [InlineData("Valid Name")]
    public void Validate_ValidNames_Pass(string name)
    {
        var request = new CreateUserRequest { Name = name, Email = "test@example.com" };
        Assert.True(_validator.Validate(request).IsValid);
    }
}
```

---

## 4. State Management Testing

Test state container classes independently of UI.

```csharp
// CartState.cs (standalone state container)
public class CartState
{
    private readonly List<CartItem> _items = [];

    public IReadOnlyList<CartItem> Items => _items.AsReadOnly();
    public decimal Total => _items.Sum(i => i.Price * i.Quantity);
    public bool IsEmpty => _items.Count == 0;

    public void AddItem(CartItem item)
    {
        var existing = _items.FirstOrDefault(i => i.ProductId == item.ProductId);
        if (existing is not null)
            existing.Quantity += item.Quantity;
        else
            _items.Add(item);
    }

    public void RemoveItem(int productId)
    {
        _items.RemoveAll(i => i.ProductId == productId);
    }
}
```

```csharp
public class CartStateTests
{
    [Fact]
    public void NewCart_IsEmpty()
    {
        var state = new CartState();
        Assert.True(state.IsEmpty);
        Assert.Equal(0m, state.Total);
    }

    [Fact]
    public void AddItem_IncreasesTotal()
    {
        var state = new CartState();
        state.AddItem(new CartItem { ProductId = 1, Price = 100m, Quantity = 2 });
        Assert.Equal(200m, state.Total);
    }

    [Fact]
    public void AddItem_SameProduct_IncrementsQuantity()
    {
        var state = new CartState();
        state.AddItem(new CartItem { ProductId = 1, Price = 100m, Quantity = 1 });
        state.AddItem(new CartItem { ProductId = 1, Price = 100m, Quantity = 3 });

        Assert.Single(state.Items);
        Assert.Equal(4, state.Items[0].Quantity);
    }

    [Fact]
    public void RemoveItem_RemovesFromCart()
    {
        var state = new CartState();
        state.AddItem(new CartItem { ProductId = 1, Price = 100m, Quantity = 1 });

        state.RemoveItem(1);

        Assert.True(state.IsEmpty);
    }
}
```

---

## 5. Event Handler Logic Testing

Extract event handler logic into named methods or standalone functions.

```csharp
// FormHandler.cs (extracted from component)
public static class FormHandler
{
    public static Result<CreateUserRequest, List<string>> HandleSubmit(
        string name, string email)
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(name))
            errors.Add("Name is required.");
        if (!email.Contains('@'))
            errors.Add("Email format is invalid.");

        return errors.Count == 0
            ? Result<CreateUserRequest, List<string>>.Ok(
                new CreateUserRequest { Name = name, Email = email })
            : Result<CreateUserRequest, List<string>>.Error(errors);
    }
}
```

```csharp
public class FormHandlerTests
{
    [Fact]
    public void HandleSubmit_ValidInput_ReturnsOk()
    {
        var result = FormHandler.HandleSubmit("Alice", "alice@example.com");
        Assert.True(result.IsOk);
        Assert.Equal("Alice", result.Value.Name);
    }

    [Fact]
    public void HandleSubmit_EmptyName_ReturnsError()
    {
        var result = FormHandler.HandleSubmit("", "alice@example.com");
        Assert.True(result.IsError);
        Assert.Contains("Name is required.", result.Errors);
    }

    [Fact]
    public void HandleSubmit_InvalidEmail_ReturnsError()
    {
        var result = FormHandler.HandleSubmit("Alice", "invalid");
        Assert.True(result.IsError);
        Assert.Contains("Email format is invalid.", result.Errors);
    }

    [Fact]
    public void HandleSubmit_AllInvalid_ReportsAllErrors()
    {
        var result = FormHandler.HandleSubmit("", "invalid");
        Assert.Equal(2, result.Errors.Count);
    }
}
```

---

## 6. What NOT to Unit Test

The following should be verified with E2E tests (Playwright):

| Target | Reason |
|--------|--------|
| Razor markup HTML output | Rendering differs between Server/WASM modes |
| DOM event wiring (`@onclick` fires) | Requires browser environment |
| CSS class application (`class="@(IsActive ? "active" : "")"`) | DOM-dependent |
| Navigation (`NavigationManager.NavigateTo`) | Requires full hosting context |
| `<AuthorizeView>` behavior | Requires authentication middleware |
| JavaScript interop (`IJSRuntime`) | Requires browser JS engine |

---

## 7. Test File Organization

```
src/
+-- MyApp.Web/
|   +-- Pages/
|   |   +-- Users.razor           # Component markup
|   |   +-- Users.razor.cs        # Code-behind with extracted logic
|   +-- Components/
|   |   +-- UserCard.razor
|   |   +-- UserCard.razor.cs
|   +-- State/
|   |   +-- CartState.cs          # Standalone state containers
|   +-- Validators/
|       +-- CreateUserValidator.cs # Pure validation logic
+-- MyApp.Tests/
    +-- Unit/
    |   +-- Pages/
    |   |   +-- UsersLogicTests.cs      # Code-behind logic tests
    |   +-- State/
    |   |   +-- CartStateTests.cs       # State container tests
    |   +-- Validators/
    |       +-- CreateUserValidatorTests.cs
    +-- Component/
    |   +-- UserCardTests.cs            # bUnit component tests
    |   +-- CounterTests.cs
    +-- Integration/
        +-- UsersApiTests.cs            # WebApplicationFactory tests
```

Principle: Logic lives in `.razor.cs` code-behind or standalone classes. Tests mirror the source structure.

---

## Pattern Summary

| Test Target | Extraction Pattern | Assertion Example |
|------------|-------------------|-------------------|
| State transitions | Pure function in code-behind | `Assert.Equal(8, Counter.CalculateNextCount(5, 3))` |
| Derived calculations | Static/instance method | `Assert.Equal(700m, CartState.CalculateTotal(items))` |
| Validation | Validator class | `Assert.False(validator.Validate(invalid).IsValid)` |
| Event handler logic | Static method or service | `Assert.True(FormHandler.HandleSubmit("Alice", "a@b.com").IsOk)` |
| Component rendering | bUnit `RenderComponent` | `cut.Find("h3").TextContent.Should().Be("Alice")` |
| Component interaction | bUnit `Find().Click()` | `cut.Find("button").Click(); Assert.Equal(1, count)` |
| Cascading values | bUnit `AddCascadingValue` | `cut.Find("div").ClassList.Should().Contain("dark")` |

## 4-Category Coverage (Frontend Application)

| Category | Frontend Application Example |
|----------|------------------------------|
| Happy Path | Valid parameters render correctly, valid form submits |
| Boundary Values | Empty string, max length, 0 items, 1 item, page boundary |
| Error Handling | Validation errors, API failure state display |
| Edge Cases | Multibyte characters, rapid clicks, zero-division in calculations |
