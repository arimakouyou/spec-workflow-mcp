# Green の3つの戦略

テストを最速で通すための3つの戦略と使い分け。

## 1. 仮実装（Fake It）

最も安全な方法。まず定数を返してテストを通す。

```rust
#[test]
fn empty_cart_total_should_be_zero() {
    let cart = ShoppingCart::new();
    assert_eq!(cart.total(), 0);
}

// 仮実装
impl ShoppingCart {
    fn total(&self) -> u64 {
        0 // まずは定数で仮実装
    }
}
```

### 使うべき場面
- 実装方法がまだ明確でない時
- 複雑な処理が必要な時
- TDD に慣れていない時

### メリット
- 最も安全で失敗しにくい
- 小さいステップで確実に進められる
- 思考を整理する時間ができる

## 2. 三角測量（Triangulation）

複数のテストケースから一般化を導く。

```rust
// Test 1: 空のカート
#[test]
fn empty_cart_total_should_be_zero() {
    let cart = ShoppingCart::new();
    assert_eq!(cart.total(), 0);
    // 実装: return 0
}

// Test 2: 商品1つ追加（ここで仮実装から一般化）
#[test]
fn one_item_cart_total() {
    let mut cart = ShoppingCart::new();
    cart.add_item(Item { price: 100 });
    assert_eq!(cart.total(), 100);
}

// 一般化した実装
impl ShoppingCart {
    fn total(&self) -> u64 {
        self.items.iter().map(|item| item.price).sum()
    }
}
```

### 使うべき場面
- どう一般化すべきか不明確な時
- 複数のテストケースから共通パターンを見つけたい時

### プロセス
1. 最初のテストで仮実装（定数を返す）
2. 2つ目のテストを追加
3. 両方のテストが通るように一般化
4. 必要に応じて3つ目、4つ目...

## 3. 明白な実装（Obvious Implementation）

最も高速だが、慣れが必要。いきなり正解を実装。

```rust
#[test]
fn total_calculates_sum_of_item_prices() {
    let mut cart = ShoppingCart::new();
    cart.add_item(Item { price: 100 });
    cart.add_item(Item { price: 200 });
    assert_eq!(cart.total(), 300);
}

// 明白な実装（仮実装を経ずに直接実装）
impl ShoppingCart {
    fn total(&self) -> u64 {
        self.items.iter().map(|item| item.price).sum()
    }
}
```

### 使うべき場面
- 実装方法が明白な時
- シンプルな処理の時
- TDD に慣れている時

### 重要な注意
明白だと思って実装したがテストが通らない場合は、躊躇なく仮実装に戻る。

## 戦略の使い分けフローチャート

```
実装は明白か？
  ├─ Yes → 明白な実装を試す
  │         ├─ 成功 → 完了
  │         └─ 失敗 → 仮実装に戻る
  │
  └─ No → 仮実装から開始
            ├─ テストが1つ → 仮実装のまま
            └─ テストが複数 → 三角測量で一般化
```

## 実践例: フィボナッチ数列

### ステップ1: 仮実装

```rust
#[test]
fn fib_0() {
    assert_eq!(fib(0), 0);
}

fn fib(_n: u64) -> u64 {
    0 // 仮実装
}
```

### ステップ2: 三角測量

```rust
#[test]
fn fib_1() {
    assert_eq!(fib(1), 1);
}

fn fib(n: u64) -> u64 {
    if n == 0 { return 0; }
    1 // まだ仮実装
}
```

### ステップ3: さらに三角測量

```rust
#[test]
fn fib_2() {
    assert_eq!(fib(2), 1);
}

fn fib(n: u64) -> u64 {
    if n <= 1 { return n; }
    fib(n - 1) + fib(n - 2) // ここで一般化
}
```

## まとめ

| 戦略 | 速度 | 安全性 | 推奨レベル |
|------|------|--------|-----------|
| 仮実装 | 遅い | 高い | 初心者〜上級者 |
| 三角測量 | 中間 | 高い | 中級者〜上級者 |
| 明白な実装 | 速い | 低い | 上級者 |

原則: 迷ったら仮実装。慣れたら明白な実装。複雑なら三角測量。
