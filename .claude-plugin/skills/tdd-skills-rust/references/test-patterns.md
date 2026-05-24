# Test Patterns

## Test Fixtures

Preparing data and objects shared across tests.

### Helper Functions

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn create_cart() -> ShoppingCart {
        ShoppingCart::new()
    }

    fn sample_item() -> Item {
        Item { name: "Book".into(), price: 1000 }
    }

    #[test]
    fn empty_cart_total() {
        let cart = create_cart();
        assert_eq!(cart.total(), 0);
    }

    #[test]
    fn add_item() {
        let mut cart = create_cart();
        cart.add_item(sample_item());
        assert_eq!(cart.item_count(), 1);
    }
}
```

### Fixtures with rstest

The `rstest` crate provides pytest-style fixtures.

```rust
use rstest::*;

#[fixture]
fn cart() -> ShoppingCart {
    ShoppingCart::new()
}

#[fixture]
fn sample_item() -> Item {
    Item { name: "Book".into(), price: 1000 }
}

#[rstest]
fn empty_cart_total(cart: ShoppingCart) {
    assert_eq!(cart.total(), 0);
}

#[rstest]
fn add_item(mut cart: ShoppingCart, sample_item: Item) {
    cart.add_item(sample_item);
    assert_eq!(cart.item_count(), 1);
}
```

## Test Data Builders

Flexibly construct complex objects.

```rust
struct ItemBuilder {
    name: String,
    price: u64,
    stock: u32,
}

impl ItemBuilder {
    fn new() -> Self {
        Self {
            name: "Default Item".into(),
            price: 1000,
            stock: 10,
        }
    }

    fn name(mut self, name: &str) -> Self {
        self.name = name.into();
        self
    }

    fn price(mut self, price: u64) -> Self {
        self.price = price;
        self
    }

    fn stock(mut self, stock: u32) -> Self {
        self.stock = stock;
        self
    }

    fn build(self) -> Item {
        Item {
            name: self.name,
            price: self.price,
            stock: self.stock,
        }
    }
}

#[test]
fn expensive_item() {
    let item = ItemBuilder::new()
        .name("Luxury Watch")
        .price(1_000_000)
        .build();

    assert!(item.is_expensive());
}
```

## Parameterized Tests

### Parameterization with rstest

```rust
use rstest::rstest;

#[rstest]
#[case(0, 0)]
#[case(500, 0)]
#[case(999, 0)]
#[case(1000, 50)]
#[case(3000, 150)]
#[case(5000, 500)]
#[case(10000, 1000)]
fn calculate_discount(#[case] amount: u64, #[case] expected: u64) {
    assert_eq!(super::calculate_discount(amount), expected);
}
```

### Parameterization via Macro (when not using rstest)

```rust
macro_rules! discount_tests {
    ($($name:ident: ($amount:expr, $expected:expr),)*) => {
        $(
            #[test]
            fn $name() {
                assert_eq!(calculate_discount($amount), $expected);
            }
        )*
    };
}

discount_tests! {
    no_discount_0: (0, 0),
    no_discount_500: (500, 0),
    boundary_999: (999, 0),
    discount_5pct_1000: (1000, 50),
    discount_10pct_5000: (5000, 500),
}
```

## One Assertion per Test (in spirit)

Principle: each test verifies one concept.

```rust
// Bad: multiple concepts
#[test]
fn shopping_cart() {
    let mut cart = ShoppingCart::new();
    assert!(cart.is_empty());         // verifies empty
    cart.add_item(Item { price: 100 });
    assert_eq!(cart.item_count(), 1); // verifies count
    assert_eq!(cart.total(), 100);    // verifies total
}

// Good: split per concept
#[test]
fn new_cart_should_be_empty() {
    let cart = ShoppingCart::new();
    assert!(cart.is_empty());
}

#[test]
fn add_item_increases_item_count() {
    let mut cart = ShoppingCart::new();
    cart.add_item(Item { price: 100 });
    assert_eq!(cart.item_count(), 1);
}

#[test]
fn add_item_increases_total() {
    let mut cart = ShoppingCart::new();
    cart.add_item(Item { price: 100 });
    assert_eq!(cart.total(), 100);
}
```

Exception: it is OK when several related assertions verify a single concept.

```rust
#[test]
fn add_item_updates_cart_state() {
    let mut cart = ShoppingCart::new();
    let item = Item { name: "Book".into(), price: 100 };

    cart.add_item(item);

    // All of these verify the single concept "item added"
    assert_eq!(cart.item_count(), 1);
    assert_eq!(cart.total(), 100);
    assert!(cart.contains("Book"));
}
```

## Summary

- Prepare shared data via helper functions or `rstest` fixtures
- Use the Builder pattern for flexible test data
- Reduce duplication via `rstest` parameterization
- Aim for one concept per test
