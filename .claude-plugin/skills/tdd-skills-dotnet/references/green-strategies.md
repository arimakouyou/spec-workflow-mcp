# Three Green Strategies

Three strategies for making a test pass as quickly as possible, and when to use each.

## 1. Fake It

The safest approach. Return a constant first to make the test pass.

```csharp
[Fact]
public void EmptyCart_Total_ShouldBeZero()
{
    var cart = new ShoppingCart();
    Assert.Equal(0m, cart.Total());
}

// Fake It implementation
public class ShoppingCart
{
    public decimal Total()
    {
        return 0m; // Return a constant first
    }
}
```

### When to Use
- When the implementation approach is not yet clear
- When complex processing is required
- When you are new to TDD

### Benefits
- Safest and least likely to fail
- Progress in small, reliable steps
- Gives time to organize your thinking

## 2. Triangulation

Derive a generalized implementation from multiple test cases.

```csharp
// Test 1: Empty cart
[Fact]
public void EmptyCart_Total_ShouldBeZero()
{
    var cart = new ShoppingCart();
    Assert.Equal(0m, cart.Total());
    // Implementation: return 0m;
}

// Test 2: One item added (generalize from fake)
[Fact]
public void OneItem_Total_ShouldEqualItemPrice()
{
    var cart = new ShoppingCart();
    cart.AddItem(new Item { Price = 100m });
    Assert.Equal(100m, cart.Total());
}

// Generalized implementation
public class ShoppingCart
{
    private readonly List<Item> _items = [];

    public void AddItem(Item item) => _items.Add(item);

    public decimal Total() => _items.Sum(item => item.Price);
}
```

### When to Use
- When it is unclear how to generalize
- When you want to find common patterns from multiple test cases

### Process
1. Fake It for the first test (return a constant)
2. Add a second test
3. Generalize to pass both tests
4. Add a third, fourth test as needed...

### Using `[Theory]` for Triangulation

```csharp
[Theory]
[InlineData(0, 0)]
[InlineData(100, 100)]
[InlineData(250, 250)]
public void SingleItem_Total_ShouldEqualPrice(decimal price, decimal expected)
{
    var cart = new ShoppingCart();
    if (price > 0)
        cart.AddItem(new Item { Price = price });
    Assert.Equal(expected, cart.Total());
}
```

## 3. Obvious Implementation

The fastest approach, but requires experience. Implement the correct solution directly.

```csharp
[Fact]
public void Total_CalculatesSumOfItemPrices()
{
    var cart = new ShoppingCart();
    cart.AddItem(new Item { Price = 100m });
    cart.AddItem(new Item { Price = 200m });
    Assert.Equal(300m, cart.Total());
}

// Obvious Implementation (skip Fake It)
public class ShoppingCart
{
    private readonly List<Item> _items = [];

    public void AddItem(Item item) => _items.Add(item);

    public decimal Total() => _items.Sum(item => item.Price);
}
```

### When to Use
- When the implementation is obvious
- When the processing is simple
- When you are experienced with TDD

### Important Note
If you think the implementation is obvious but the test fails, do not hesitate to fall back to Fake It.

## Strategy Selection Flowchart

```
Is the implementation obvious?
  +-- Yes -> Try Obvious Implementation
  |           +-- Success -> Done
  |           +-- Failure -> Fall back to Fake It
  |
  +-- No  -> Start with Fake It
              +-- Only 1 test   -> Stay with Fake It
              +-- Multiple tests -> Triangulate to generalize
```

## Practical Example: Fibonacci Sequence

### Step 1: Fake It

```csharp
[Fact]
public void Fib_0_Returns0()
{
    Assert.Equal(0, Fibonacci.Calculate(0));
}

public static class Fibonacci
{
    public static int Calculate(int n)
    {
        return 0; // Fake It
    }
}
```

### Step 2: Triangulation

```csharp
[Fact]
public void Fib_1_Returns1()
{
    Assert.Equal(1, Fibonacci.Calculate(1));
}

public static class Fibonacci
{
    public static int Calculate(int n)
    {
        if (n == 0) return 0;
        return 1; // Still faking
    }
}
```

### Step 3: Further Triangulation

```csharp
[Fact]
public void Fib_2_Returns1()
{
    Assert.Equal(1, Fibonacci.Calculate(2));
}

public static class Fibonacci
{
    public static int Calculate(int n)
    {
        if (n <= 1) return n;
        return Calculate(n - 1) + Calculate(n - 2); // Generalized
    }
}
```

### Parameterized Verification

```csharp
[Theory]
[InlineData(0, 0)]
[InlineData(1, 1)]
[InlineData(2, 1)]
[InlineData(3, 2)]
[InlineData(10, 55)]
public void Fib_ReturnsCorrectValue(int input, int expected)
{
    Assert.Equal(expected, Fibonacci.Calculate(input));
}
```

## Summary

| Strategy | Speed | Safety | Recommended Level |
|----------|-------|--------|-------------------|
| Fake It | Slow | High | Beginner to Advanced |
| Triangulation | Medium | High | Intermediate to Advanced |
| Obvious Implementation | Fast | Low | Advanced |

Principle: When in doubt, Fake It. When experienced, use Obvious Implementation. When complex, use Triangulation.
