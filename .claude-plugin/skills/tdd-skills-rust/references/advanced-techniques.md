# TDD Practical Techniques and Antipatterns

## Practical Techniques

### Coping with Specification Uncertainty

Problem: the specification is vague and you cannot tell how to write a test.

Approach: start from a concrete example.

```rust
// Bad: too abstract
#[test]
fn calculate_price() {
    // What is being tested?
}

// Good: a concrete use case
#[test]
fn calculate_price_for_single_item_without_discount() {
    let calculator = PriceCalculator::new();
    let items = vec![Item { price: 1000 }];

    let total = calculator.calculate(&items);

    assert_eq!(total, 1000);
}
```

### Applying TDD to Legacy Code

1. Write tests that protect existing behavior (characterization tests)
2. Refactor in small steps
3. Gradually raise test coverage

```rust
// Step 1: capture existing behavior
#[test]
fn existing_behavior() {
    let result = legacy_function(&input_data);
    assert_eq!(result, expected_output);
}

// Step 2: abstract dependencies via trait so it becomes testable
// Step 3: do new functionality with TDD
```

### When Tests Get Complex

Approach:
1. Create test helper functions
2. Use the Builder pattern
3. Split tests

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn create_premium_user() -> User {
        User { id: 1, name: "Alice".into(), is_premium: true }
    }

    fn create_cart_with_items(user: &User) -> ShoppingCart {
        let mut cart = ShoppingCart::new(user.id);
        cart.add_item(ItemBuilder::new().name("Book").price(1000).build());
        cart.add_item(ItemBuilder::new().name("Pen").price(500).build());
        cart
    }

    #[test]
    fn premium_user_gets_discount() {
        let user = create_premium_user();
        let cart = create_cart_with_items(&user);

        let total = cart.calculate_total(&user);

        assert_eq!(total, 1350); // 10% discount
    }
}
```

## TDD Antipatterns

### 1. Implementing Without Writing Tests

```rust
// Bad: jumping to implementation
fn calculate_total(items: &[Item]) -> u64 {
    items.iter().map(|i| i.price).sum()
}

// Good: test first
#[test]
fn calculate_total_for_empty_list() {
    assert_eq!(calculate_total(&[]), 0);
}
```

### 2. Steps That Are Too Big

```rust
// Bad: aiming for perfection in one step
#[test]
fn complete_order_system() {
    // Cart, payment, inventory management, email sending... all of it
}

// Good: split into small steps
#[test]
fn create_empty_cart() {
    let cart = ShoppingCart::new();
    assert!(cart.is_empty());
}
```

### 3. Tests for the Sake of Tests

```rust
// Bad: too trivial (testing a getter)
#[test]
fn getter() {
    let user = User { name: "Alice".into() };
    assert_eq!(user.name, "Alice");
}

// Good: testing behavior
#[test]
fn user_full_name() {
    let user = User { first_name: "Alice".into(), last_name: "Smith".into() };
    assert_eq!(user.full_name(), "Alice Smith");
}
```

### 4. Testing Private Functions

```rust
// Bad: testing internal functions directly
#[test]
fn internal_calculation() {
    assert_eq!(internal_helper(5), 10); // forced test by promoting to pub(crate)
}

// Good: test through the public API
#[test]
fn public_method_that_uses_internal() {
    let obj = MyStruct::new();
    assert_eq!(obj.calculate(5), expected_result);
}
```

In Rust, in-module tests (`#[cfg(test)] mod tests`) can access private functions, but
testing through the public API is preferable from a design standpoint.

### 5. Inter-test Dependencies

```rust
// Bad: tests depend on order (e.g. via static mut)
// Good: each test is independent
#[test]
fn create_cart() {
    let cart = ShoppingCart::new();
    assert!(cart.is_empty());
}

#[test]
fn add_item() {
    let mut cart = ShoppingCart::new(); // freshly created each time
    cart.add_item(Item { price: 100 });
    assert_eq!(cart.item_count(), 1);
}
```

## Using a TODO List

Record ideas you have during implementation:

```markdown
## TODO
- [x] Total of an empty cart is 0
- [x] Total when one item is added
- [ ] Total when multiple items are added
- [ ] Total when discount is applied
- [ ] Items with negative price cannot be added (error)
- [ ] Out-of-stock items cannot be added
```

Benefits:
- Lets you focus on what to do now
- Visualizes progress
- Prevents missed implementations

## Summary

What you should do:
- Advance in small steps
- Start from concrete examples
- Use a TODO list
- Organize with test helpers

What you should avoid:
- Skipping tests
- Steps that are too big
- Testing private functions
- Inter-test dependencies
