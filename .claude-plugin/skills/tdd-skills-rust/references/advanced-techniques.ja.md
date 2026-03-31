# TDD 実践テクニックとアンチパターン

## 実践テクニック

### 仕様の不確実性への対処

問題: 仕様が曖昧で、どうテストを書けばいいか分からない。

対策: 具体例から始める。

```rust
// 悪い: 抽象的すぎる
#[test]
fn calculate_price() {
    // 何をテストする？
}

// 良い: 具体的なユースケース
#[test]
fn calculate_price_for_single_item_without_discount() {
    let calculator = PriceCalculator::new();
    let items = vec![Item { price: 1000 }];

    let total = calculator.calculate(&items);

    assert_eq!(total, 1000);
}
```

### レガシーコードへの TDD 適用

1. 既存の振る舞いを保護するテストを書く（特性テスト）
2. 小さくリファクタリング
3. 徐々にテストカバレッジを上げる

```rust
// Step 1: 既存の振る舞いを記録
#[test]
fn existing_behavior() {
    let result = legacy_function(&input_data);
    assert_eq!(result, expected_output);
}

// Step 2: trait で依存を抽象化してテスト可能にする
// Step 3: 新機能は TDD で
```

### テストが複雑になってきたら

対策:
1. テストヘルパー関数を作る
2. Builder パターンを使う
3. テストを分割する

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

## TDD のアンチパターン

### 1. テストを書かずに実装

```rust
// 悪い: いきなり実装
fn calculate_total(items: &[Item]) -> u64 {
    items.iter().map(|i| i.price).sum()
}

// 良い: まずテスト
#[test]
fn calculate_total_for_empty_list() {
    assert_eq!(calculate_total(&[]), 0);
}
```

### 2. 大きすぎるステップ

```rust
// 悪い: いきなり完璧を目指す
#[test]
fn complete_order_system() {
    // カート、決済、在庫管理、メール送信...全部
}

// 良い: 小さく分割
#[test]
fn create_empty_cart() {
    let cart = ShoppingCart::new();
    assert!(cart.is_empty());
}
```

### 3. テストのためのテスト

```rust
// 悪い: 自明すぎる（getter のテスト）
#[test]
fn getter() {
    let user = User { name: "Alice".into() };
    assert_eq!(user.name, "Alice");
}

// 良い: 振る舞いをテスト
#[test]
fn user_full_name() {
    let user = User { first_name: "Alice".into(), last_name: "Smith".into() };
    assert_eq!(user.full_name(), "Alice Smith");
}
```

### 4. プライベート関数のテスト

```rust
// 悪い: 内部関数を直接テスト
#[test]
fn internal_calculation() {
    assert_eq!(internal_helper(5), 10); // pub(crate) にして無理やりテスト
}

// 良い: 公開 API を通してテスト
#[test]
fn public_method_that_uses_internal() {
    let obj = MyStruct::new();
    assert_eq!(obj.calculate(5), expected_result);
}
```

Rust ではモジュール内テスト (`#[cfg(test)] mod tests`) からプライベート関数にアクセスできるが、
公開 API を通してテストする方が設計上望ましい。

### 5. テストの相互依存

```rust
// 悪い: テストが順序に依存（static mut 等）
// 良い: 各テストが独立
#[test]
fn create_cart() {
    let cart = ShoppingCart::new();
    assert!(cart.is_empty());
}

#[test]
fn add_item() {
    let mut cart = ShoppingCart::new(); // 毎回新規作成
    cart.add_item(Item { price: 100 });
    assert_eq!(cart.item_count(), 1);
}
```

## TODO リストの活用

実装中に思いついたアイデアを記録:

```markdown
## TODO
- [x] 空のカートの合計は0
- [x] 1つの商品を追加した場合の合計
- [ ] 複数の商品を追加した場合の合計
- [ ] 割引適用時の合計
- [ ] 負の価格の商品は追加できない（エラー）
- [ ] 在庫がない商品は追加できない
```

メリット:
- 今やるべきことに集中できる
- 進捗が可視化される
- 実装漏れを防げる

## まとめ

やるべきこと:
- 小さいステップで進める
- 具体例から始める
- TODO リストを活用
- テストヘルパーで整理

避けるべきこと:
- テストを飛ばす
- 大きすぎるステップ
- プライベート関数のテスト
- テストの相互依存
