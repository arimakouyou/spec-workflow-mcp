# Test Design

## Boundary Value Analysis

Values near boundaries are especially prone to bugs.

### Example: Age Categories

```rust
// 0-17: minor, 18-64: adult, 65+: senior

#[test]
fn age_17_is_minor() {
    assert!(is_minor(17));
}

#[test]
fn age_18_is_not_minor() {
    assert!(!is_minor(18));
}

#[test]
fn age_64_is_adult() {
    assert!(is_adult(64));
}

#[test]
fn age_65_is_senior() {
    assert!(is_senior(65));
}
```

## Equivalence Partitioning

Reduce test cases by grouping inputs that exhibit the same behavior.

### Example: Discount Calculation

```rust
// 0-999: no discount
// 1000-4999: 5% discount
// 5000+: 10% discount

use rstest::rstest;

// Pick a representative value from each class to test
#[rstest]
#[case(500, 0)]
#[case(3000, 150)]
#[case(10000, 1000)]
fn discount_representative_values(#[case] amount: u64, #[case] expected: u64) {
    assert_eq!(calculate_discount(amount), expected);
}

// Always test boundary values too
#[rstest]
#[case(999, 0)]
#[case(1000, 50)]
#[case(4999, 249)]
#[case(5000, 500)]
fn discount_boundary_values(#[case] amount: u64, #[case] expected: u64) {
    assert_eq!(calculate_discount(amount), expected);
}
```

## Test Naming Conventions

### Pattern 1: Structural English Naming (recommended)

```rust
#[test]
fn total_should_be_zero_when_cart_is_empty() { /* ... */ }

#[test]
fn total_should_increase_when_item_added() { /* ... */ }

#[test]
fn should_return_error_when_negative_price() { /* ... */ }
```

### Pattern 2: Japanese (when readability is prioritized)

```rust
#[test]
fn 空のカートの合計金額は0円() { /* ... */ }

#[test]
fn 商品追加でカートの合計金額が増える() { /* ... */ }

#[test]
fn 負の価格の商品追加で例外発生() { /* ... */ }
```

### Naming Tips
- The test name conveys what is being tested
- The cause of a failure can be inferred from the name
- Use a "subject_condition_expected-result" pattern

## Testing Error Cases

```rust
// Using #[should_panic]
#[test]
#[should_panic(expected = "division by zero")]
fn divide_by_zero_panics() {
    let calc = Calculator::new();
    calc.divide(10, 0);
}

// Returning Result (recommended)
#[test]
fn invalid_email_returns_validation_error() {
    let result = User::create("invalid-email");

    assert!(result.is_err());
    let err = result.unwrap_err();
    assert!(matches!(err, AppError::Validation(msg) if msg.contains("email")));
}
```

Returning Result is the more common pattern in Rust. Use `#[should_panic]` only when a panic is the intended behavior.

## Summary

- Always test boundary values
- Use equivalence partitioning to keep cases efficient
- Use clear naming
- Verify error cases via Result
