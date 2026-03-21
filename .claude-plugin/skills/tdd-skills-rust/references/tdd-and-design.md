# TDD と設計

## TDD は設計手法でもある

TDD を実践すると、自然に以下の設計原則が守られる:

1. **YAGNI（You Aren't Gonna Need It）**: 必要最小限の実装
2. **単一責任の原則**: テストしやすい構造体は責任が明確
3. **依存性逆転の原則**: テストダブルを使うと自然に trait 設計
4. **疎結合**: テストしやすいコードは結合度が低い

## テストしやすい設計

### テストしにくい設計

```rust
struct OrderService;

impl OrderService {
    fn process_order(&self, order_id: i64) -> Result<(), AppError> {
        // DB に直接アクセス
        let mut conn = PgConnection::establish("postgres://...")?;
        let order = orders::table.find(order_id).first(&mut conn)?;

        // 外部 API を直接呼び出し
        let client = reqwest::blocking::Client::new();
        client.post("https://payment.api/charge").json(&order).send()?;
        Ok(())
    }
}
```

問題点:
- DB が必要（遅い）
- 外部 API が必要（不安定）
- テストが環境に依存

### テストしやすい設計

```rust
// trait で依存を抽象化
trait OrderRepository: Send + Sync {
    fn find_by_id(&self, id: i64) -> Result<Order, DbError>;
}

trait PaymentGateway: Send + Sync {
    fn charge(&self, amount: u64) -> Result<PaymentResult, PaymentError>;
}

// 依存性注入
struct OrderService {
    order_repo: Box<dyn OrderRepository>,
    payment: Box<dyn PaymentGateway>,
}

impl OrderService {
    fn new(
        order_repo: Box<dyn OrderRepository>,
        payment: Box<dyn PaymentGateway>,
    ) -> Self {
        Self { order_repo, payment }
    }

    fn process_order(&self, order_id: i64) -> Result<(), AppError> {
        let order = self.order_repo.find_by_id(order_id)?;
        self.payment.charge(order.amount)?;
        Ok(())
    }
}
```

テスト:

```rust
#[test]
fn process_order_charges_payment() {
    let mut mock_repo = MockOrderRepository::new();
    mock_repo.expect_find_by_id()
        .returning(|_| Ok(Order { id: 1, amount: 5000 }));

    let mut mock_payment = MockPaymentGateway::new();
    mock_payment.expect_charge()
        .with(mockall::predicate::eq(5000))
        .returning(|_| Ok(PaymentResult::Success));

    let service = OrderService::new(
        Box::new(mock_repo),
        Box::new(mock_payment),
    );

    assert!(service.process_order(1).is_ok());
}
```

## TDD がもたらす設計上の利点

### 1. インターフェース（trait）の明確化

テストを先に書くことで、使いやすい API が設計される。

```rust
// テストから始めるので、シンプルで直感的な API になる
#[test]
fn cart_add_item() {
    let mut cart = ShoppingCart::new();
    cart.add(Item::new("Book", 1000));
    assert_eq!(cart.total(), 1000);
}
```

### 2. 責任の分離

テストが複雑になる = 構造体が複雑すぎるサイン。

```rust
// 責任が多すぎる → テストが複雑
struct OrderProcessor { /* 在庫確認 + 決済 + メール + 配送 */ }

// 責任を分離 → テストが簡単
struct OrderProcessor {
    inventory: Box<dyn InventoryService>,
    payment: Box<dyn PaymentService>,
    notification: Box<dyn NotificationService>,
    shipping: Box<dyn ShippingService>,
}
```

### 3. 疎結合

trait を使うことで、自然に疎結合になる。

```rust
// 密結合（テストしにくい）
impl UserService {
    fn create_user(&self, email: &str) -> Result<User, AppError> {
        let mut conn = PgConnection::establish("...")?; // 直接生成
        // ...
    }
}

// 疎結合（テストしやすい）
impl UserService {
    fn new(repository: Box<dyn UserRepository>) -> Self {
        Self { repository } // 注入
    }
}
```

## テスタビリティの原則

### 1. 外部依存を注入する

```rust
// テストしにくい: 時刻を直接取得
fn generate_report(&self) -> Report {
    let now = chrono::Utc::now();
    // ...
}

// テストしやすい: trait で抽象化
trait Clock: Send + Sync {
    fn now(&self) -> DateTime<Utc>;
}

fn generate_report(&self, clock: &dyn Clock) -> Report {
    let now = clock.now();
    // ...
}
```

### 2. 副作用を分離する

```rust
// 副作用が混在
fn process_and_save(data: &Data, conn: &mut PgConnection) -> Result<Report, AppError> {
    let result = expensive_calculation(data); // 純粋な計算
    diesel::insert_into(reports::table).values(&result).execute(conn)?; // 副作用
    Ok(result)
}

// 副作用を分離
fn process(data: &Data) -> Report {
    expensive_calculation(data) // 純粋
}

fn save(report: &Report, conn: &mut PgConnection) -> Result<(), DbError> {
    diesel::insert_into(reports::table).values(report).execute(conn)?;
    Ok(())
}
```

### 3. 決定論的にする

```rust
// ランダム（再現不可）
fn generate_token() -> String {
    use rand::Rng;
    rand::thread_rng().gen::<[u8; 32]>().encode_hex()
}

// 決定論的（trait で抽象化）
trait TokenGenerator: Send + Sync {
    fn generate(&self) -> String;
}
```

## まとめ

TDD を実践すると:
- trait による抽象化が自然に使われる
- 責任が適切に分離される
- 疎結合なコードになる
- 依存性注入が自然に使われる

TDD = 設計駆動開発
