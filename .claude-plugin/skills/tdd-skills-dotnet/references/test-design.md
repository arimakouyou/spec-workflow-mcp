# Test Design

## Boundary Value Analysis

Values near boundaries are especially prone to bugs.

### Example: Age Classification

```csharp
// 0-17: Minor, 18-64: Adult, 65+: Senior

[Fact]
public void Age17_IsMinor()
{
    Assert.True(AgeClassifier.IsMinor(17));
}

[Fact]
public void Age18_IsNotMinor()
{
    Assert.False(AgeClassifier.IsMinor(18));
}

[Fact]
public void Age64_IsAdult()
{
    Assert.True(AgeClassifier.IsAdult(64));
}

[Fact]
public void Age65_IsSenior()
{
    Assert.True(AgeClassifier.IsSenior(65));
}
```

### Using `[Theory]` + `[InlineData]` for Boundary Values

```csharp
[Theory]
[InlineData(17, true)]
[InlineData(18, false)]
public void IsMinor_BoundaryValues(int age, bool expected)
{
    Assert.Equal(expected, AgeClassifier.IsMinor(age));
}

[Theory]
[InlineData(64, true)]
[InlineData(65, false)]
public void IsAdult_BoundaryValues(int age, bool expected)
{
    Assert.Equal(expected, AgeClassifier.IsAdult(age));
}
```

## Equivalence Partitioning

Reduce test cases by grouping inputs that produce the same behavior.

### Example: Discount Calculation

```csharp
// 0-999: No discount
// 1000-4999: 5% discount
// 5000+: 10% discount

// Representative values from each partition
[Theory]
[InlineData(500, 0)]
[InlineData(3000, 150)]
[InlineData(10000, 1000)]
public void Discount_RepresentativeValues(decimal amount, decimal expected)
{
    Assert.Equal(expected, DiscountCalculator.Calculate(amount));
}

// Boundary values (always test these)
[Theory]
[InlineData(999, 0)]
[InlineData(1000, 50)]
[InlineData(4999, 249.95)]
[InlineData(5000, 500)]
public void Discount_BoundaryValues(decimal amount, decimal expected)
{
    Assert.Equal(expected, DiscountCalculator.Calculate(amount));
}
```

## `[MemberData]` for Complex Test Data

When test data is too complex for `[InlineData]`, use `[MemberData]`.

```csharp
public class OrderDiscountTests
{
    public static IEnumerable<object[]> ComplexOrderData =>
    [
        [new Order { Items = [new("Book", 1000m)], IsPremium = false }, 0m],
        [new Order { Items = [new("Book", 1000m)], IsPremium = true }, 100m],
        [new Order
        {
            Items = [new("Book", 1000m), new("Pen", 500m)],
            IsPremium = true
        }, 150m],
    ];

    [Theory]
    [MemberData(nameof(ComplexOrderData))]
    public void CalculateDiscount_WithComplexOrders(Order order, decimal expectedDiscount)
    {
        var result = DiscountCalculator.Calculate(order);
        Assert.Equal(expectedDiscount, result);
    }
}
```

### `[ClassData]` for Reusable Test Data

```csharp
public class DiscountTestData : IEnumerable<object[]>
{
    public IEnumerator<object[]> GetEnumerator()
    {
        yield return [0m, 0m];
        yield return [999m, 0m];
        yield return [1000m, 50m];
        yield return [5000m, 500m];
    }

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}

[Theory]
[ClassData(typeof(DiscountTestData))]
public void Discount_WithClassData(decimal amount, decimal expected)
{
    Assert.Equal(expected, DiscountCalculator.Calculate(amount));
}
```

## Test Naming Conventions

### Pattern 1: `MethodName_StateUnderTest_ExpectedBehavior` (Recommended)

```csharp
[Fact]
public void Total_WhenCartIsEmpty_ReturnsZero() { /* ... */ }

[Fact]
public void Total_WhenItemAdded_IncreasesByItemPrice() { /* ... */ }

[Fact]
public void AddItem_WithNegativePrice_ThrowsArgumentException() { /* ... */ }
```

### Pattern 2: `Given_When_Then`

```csharp
[Fact]
public void GivenEmptyCart_WhenCalculateTotal_ThenReturnsZero() { /* ... */ }

[Fact]
public void GivenPremiumUser_WhenCheckout_ThenAppliesDiscount() { /* ... */ }
```

### Naming Guidelines
- The test name should clearly describe what is being tested
- When the test fails, the name should help identify the cause
- Follow the "Subject_Condition_ExpectedResult" pattern

## Error Case Testing

```csharp
// Assert.Throws for synchronous exceptions
[Fact]
public void Divide_ByZero_ThrowsDivideByZeroException()
{
    var calc = new Calculator();
    Assert.Throws<DivideByZeroException>(() => calc.Divide(10, 0));
}

// Assert.ThrowsAsync for async exceptions
[Fact]
public async Task GetUser_WithInvalidId_ThrowsNotFoundException()
{
    var service = new UserService(Substitute.For<IUserRepository>());
    await Assert.ThrowsAsync<NotFoundException>(
        () => service.GetUserAsync(-1));
}

// Checking exception message
[Fact]
public void CreateUser_WithInvalidEmail_ThrowsWithMessage()
{
    var ex = Assert.Throws<ValidationException>(
        () => User.Create("invalid-email"));
    Assert.Contains("email", ex.Message, StringComparison.OrdinalIgnoreCase);
}

// Result pattern (recommended for domain validation)
[Fact]
public void Validate_InvalidEmail_ReturnsValidationError()
{
    var result = UserValidator.Validate(new CreateUserRequest { Email = "invalid" });

    Assert.False(result.IsValid);
    Assert.Contains(result.Errors, e => e.PropertyName == "Email");
}
```

## Edge Case Patterns

```csharp
[Theory]
[InlineData(null)]
[InlineData("")]
[InlineData("   ")]
public void ParseName_WithNullOrWhitespace_ReturnsError(string? input)
{
    var result = NameParser.Parse(input);
    Assert.False(result.IsSuccess);
}

[Fact]
public void ProcessList_WithEmptyCollection_ReturnsEmptyResult()
{
    var result = Processor.Process([]);
    Assert.Empty(result);
}

[Fact]
public void Calculate_WithMaxDecimal_DoesNotOverflow()
{
    Assert.Throws<OverflowException>(
        () => Calculator.Add(decimal.MaxValue, 1m));
}
```

## Summary

- Always test boundary values
- Use equivalence partitioning for efficiency
- Use `[Theory]` + `[InlineData]` for simple parameterized data
- Use `[MemberData]` or `[ClassData]` for complex test data
- Clear naming conventions
- Test error cases with `Assert.Throws` or result-based validation
