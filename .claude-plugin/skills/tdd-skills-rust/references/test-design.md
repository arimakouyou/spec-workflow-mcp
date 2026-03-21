# テスト設計

## 境界値分析（Boundary Value Analysis）

境界付近の値は特にバグが発生しやすい。

### 例: 年齢区分

```rust
// 0-17: 未成年, 18-64: 成人, 65以上: 高齢者

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

## 同値分割（Equivalence Partitioning）

同じ振る舞いをするグループに分割してテストケースを削減。

### 例: 割引計算

```rust
// 0-999: 割引なし
// 1000-4999: 5%割引
// 5000以上: 10%割引

use rstest::rstest;

// 各クラスから代表値を選んでテスト
#[rstest]
#[case(500, 0)]
#[case(3000, 150)]
#[case(10000, 1000)]
fn discount_representative_values(#[case] amount: u64, #[case] expected: u64) {
    assert_eq!(calculate_discount(amount), expected);
}

// 境界値も必ずテスト
#[rstest]
#[case(999, 0)]
#[case(1000, 50)]
#[case(4999, 249)]
#[case(5000, 500)]
fn discount_boundary_values(#[case] amount: u64, #[case] expected: u64) {
    assert_eq!(calculate_discount(amount), expected);
}
```

## テスト命名規則

### パターン1: 英語構造的命名（推奨）

```rust
#[test]
fn total_should_be_zero_when_cart_is_empty() { /* ... */ }

#[test]
fn total_should_increase_when_item_added() { /* ... */ }

#[test]
fn should_return_error_when_negative_price() { /* ... */ }
```

### パターン2: 日本語（可読性重視の場合）

```rust
#[test]
fn 空のカートの合計金額は0円() { /* ... */ }

#[test]
fn 商品追加でカートの合計金額が増える() { /* ... */ }

#[test]
fn 負の価格の商品追加で例外発生() { /* ... */ }
```

### 命名のポイント
- テスト名から何をテストしているか分かる
- 失敗時に原因が推測できる
- 「対象_条件_期待結果」パターン

## エラーケースのテスト

```rust
// #[should_panic] を使う方法
#[test]
#[should_panic(expected = "division by zero")]
fn divide_by_zero_panics() {
    let calc = Calculator::new();
    calc.divide(10, 0);
}

// Result を返す方法（推奨）
#[test]
fn invalid_email_returns_validation_error() {
    let result = User::create("invalid-email");

    assert!(result.is_err());
    let err = result.unwrap_err();
    assert!(matches!(err, AppError::Validation(msg) if msg.contains("email")));
}
```

Result を返すパターンの方が Rust では一般的。`#[should_panic]` は panic が意図された場合のみ使用する。

## まとめ

- 境界値は必ずテスト
- 同値分割で効率化
- 明確な命名
- エラーケースは Result ベースで検証
