# テストパターン

## テストフィクスチャ

テストで共通して使うデータやオブジェクトの準備。

### ヘルパー関数

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

### rstest によるフィクスチャ

`rstest` クレートで pytest 風のフィクスチャを使える。

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

## テストデータビルダー

複雑なオブジェクトを柔軟に構築。

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

## パラメータ化テスト

### rstest によるパラメータ化

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

### マクロによるパラメータ化（rstest 不使用時）

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

## 1テスト1アサート（の意図）

原則: 1つのテストで検証する概念は1つ。

```rust
// 悪い: 複数の概念
#[test]
fn shopping_cart() {
    let mut cart = ShoppingCart::new();
    assert!(cart.is_empty());         // 空の検証
    cart.add_item(Item { price: 100 });
    assert_eq!(cart.item_count(), 1); // 個数の検証
    assert_eq!(cart.total(), 100);    // 合計の検証
}

// 良い: 概念ごとに分割
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

例外: 関連する複数のアサートが1つの概念を検証する場合は OK。

```rust
#[test]
fn add_item_updates_cart_state() {
    let mut cart = ShoppingCart::new();
    let item = Item { name: "Book".into(), price: 100 };

    cart.add_item(item);

    // これらは全て「商品追加」という1つの概念を検証
    assert_eq!(cart.item_count(), 1);
    assert_eq!(cart.total(), 100);
    assert!(cart.contains("Book"));
}
```

## まとめ

- ヘルパー関数 or `rstest` フィクスチャで共通データを準備
- Builder パターンで柔軟なテストデータ
- `rstest` のパラメータ化で重複削減
- 1テスト1概念を意識
