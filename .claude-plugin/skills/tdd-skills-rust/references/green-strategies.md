# Three Green Strategies

Three strategies for making a test pass as quickly as possible, and when to use each.

## 1. Fake It

The safest approach. Return a constant first to make the test pass.

```rust
#[test]
fn empty_cart_total_should_be_zero() {
    let cart = ShoppingCart::new();
    assert_eq!(cart.total(), 0);
}

// Fake It
impl ShoppingCart {
    fn total(&self) -> u64 {
        0 // Start with a constant fake
    }
}
```

### When to use
- When the implementation approach is not yet clear
- When the logic required is complex
- When you are not yet comfortable with TDD

### Benefits
- Safest, least likely to fail
- Lets you advance reliably in small steps
- Gives you time to organize your thinking

## 2. Triangulation

Derive a generalization from multiple test cases.

```rust
// Test 1: empty cart
#[test]
fn empty_cart_total_should_be_zero() {
    let cart = ShoppingCart::new();
    assert_eq!(cart.total(), 0);
    // Implementation: return 0
}

// Test 2: one item added (generalize from the fake here)
#[test]
fn one_item_cart_total() {
    let mut cart = ShoppingCart::new();
    cart.add_item(Item { price: 100 });
    assert_eq!(cart.total(), 100);
}

// Generalized implementation
impl ShoppingCart {
    fn total(&self) -> u64 {
        self.items.iter().map(|item| item.price).sum()
    }
}
```

### When to use
- When it is unclear how to generalize
- When you want to find a common pattern across multiple test cases

### Process
1. Fake It with the first test (return a constant)
2. Add a second test
3. Generalize so both tests pass
4. Add a third, fourth test as needed

## 3. Obvious Implementation

The fastest approach, but takes practice. Implement the correct solution directly.

```rust
#[test]
fn total_calculates_sum_of_item_prices() {
    let mut cart = ShoppingCart::new();
    cart.add_item(Item { price: 100 });
    cart.add_item(Item { price: 200 });
    assert_eq!(cart.total(), 300);
}

// Obvious Implementation (skip Fake It and implement directly)
impl ShoppingCart {
    fn total(&self) -> u64 {
        self.items.iter().map(|item| item.price).sum()
    }
}
```

### When to use
- When the implementation is obvious
- When the logic is simple
- When you are comfortable with TDD

### Important caveat
If you assumed it was obvious but the test does not pass, fall back to Fake It without hesitation.

## Strategy Selection Flowchart

```
Is the implementation obvious?
  |- Yes -> Try Obvious Implementation
  |          |- Success -> Done
  |          \- Fail    -> Fall back to Fake It
  |
  \- No  -> Start with Fake It
             |- Single test    -> Stay on Fake It
             \- Multiple tests -> Generalize via Triangulation
```

## Worked Example: Fibonacci

### Step 1: Fake It

```rust
#[test]
fn fib_0() {
    assert_eq!(fib(0), 0);
}

fn fib(_n: u64) -> u64 {
    0 // Fake It
}
```

### Step 2: Triangulation

```rust
#[test]
fn fib_1() {
    assert_eq!(fib(1), 1);
}

fn fib(n: u64) -> u64 {
    if n == 0 { return 0; }
    1 // Still faked
}
```

### Step 3: Triangulate further

```rust
#[test]
fn fib_2() {
    assert_eq!(fib(2), 1);
}

fn fib(n: u64) -> u64 {
    if n <= 1 { return n; }
    fib(n - 1) + fib(n - 2) // Generalize here
}
```

## Summary

| Strategy | Speed | Safety | Recommended for |
|----------|-------|--------|-----------------|
| Fake It | Slow | High | Beginner to advanced |
| Triangulation | Medium | High | Intermediate to advanced |
| Obvious Implementation | Fast | Low | Advanced |

Principle: when in doubt, Fake It. Once comfortable, use Obvious Implementation. When complex, use Triangulation.
