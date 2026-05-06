# TDD and Design

## TDD Is Also a Design Method

Practicing TDD naturally upholds the following design principles:

1. **YAGNI (You Aren't Gonna Need It)**: implement only what is required
2. **Single Responsibility Principle**: testable structs have clear responsibilities
3. **Dependency Inversion Principle**: using test doubles naturally leads to trait-based design
4. **Loose Coupling**: testable code has low coupling

## Testable Design

### Hard-to-Test Design

```rust
struct OrderService;

impl OrderService {
    fn process_order(&self, order_id: i64) -> Result<(), AppError> {
        // Direct DB access
        let mut conn = PgConnection::establish("postgres://...")?;
        let order = orders::table.find(order_id).first(&mut conn)?;

        // Direct external API call
        let client = reqwest::blocking::Client::new();
        client.post("https://payment.api/charge").json(&order).send()?;
        Ok(())
    }
}
```

Problems:
- Requires a DB (slow)
- Requires the external API (unstable)
- Tests depend on the environment

### Testable Design

```rust
// Abstract dependencies via traits
trait OrderRepository: Send + Sync {
    fn find_by_id(&self, id: i64) -> Result<Order, DbError>;
}

trait PaymentGateway: Send + Sync {
    fn charge(&self, amount: u64) -> Result<PaymentResult, PaymentError>;
}

// Dependency injection
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

Test:

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

## Design Benefits TDD Brings

### 1. Clearer Interfaces (traits)

Writing tests first leads to APIs that are easy to use.

```rust
// Starting from the test produces a simple, intuitive API
#[test]
fn cart_add_item() {
    let mut cart = ShoppingCart::new();
    cart.add(Item::new("Book", 1000));
    assert_eq!(cart.total(), 1000);
}
```

### 2. Separation of Responsibilities

Tests becoming complex is a sign that the struct is too complex.

```rust
// Too many responsibilities -> complex tests
struct OrderProcessor { /* inventory check + payment + email + shipping */ }

// Separate responsibilities -> simple tests
struct OrderProcessor {
    inventory: Box<dyn InventoryService>,
    payment: Box<dyn PaymentService>,
    notification: Box<dyn NotificationService>,
    shipping: Box<dyn ShippingService>,
}
```

### 3. Loose Coupling

Using traits naturally produces loose coupling.

```rust
// Tight coupling (hard to test)
impl UserService {
    fn create_user(&self, email: &str) -> Result<User, AppError> {
        let mut conn = PgConnection::establish("...")?; // direct creation
        // ...
    }
}

// Loose coupling (easy to test)
impl UserService {
    fn new(repository: Box<dyn UserRepository>) -> Self {
        Self { repository } // injected
    }
}
```

## Testability Principles

### 1. Inject External Dependencies

```rust
// Hard to test: get the time directly
fn generate_report(&self) -> Report {
    let now = chrono::Utc::now();
    // ...
}

// Easy to test: abstract via trait
trait Clock: Send + Sync {
    fn now(&self) -> DateTime<Utc>;
}

fn generate_report(&self, clock: &dyn Clock) -> Report {
    let now = clock.now();
    // ...
}
```

### 2. Separate Side Effects

```rust
// Side effects mixed in
fn process_and_save(data: &Data, conn: &mut PgConnection) -> Result<Report, AppError> {
    let result = expensive_calculation(data); // pure computation
    diesel::insert_into(reports::table).values(&result).execute(conn)?; // side effect
    Ok(result)
}

// Side effects separated
fn process(data: &Data) -> Report {
    expensive_calculation(data) // pure
}

fn save(report: &Report, conn: &mut PgConnection) -> Result<(), DbError> {
    diesel::insert_into(reports::table).values(report).execute(conn)?;
    Ok(())
}
```

### 3. Make It Deterministic

```rust
// Random (not reproducible)
fn generate_token() -> String {
    use rand::Rng;
    rand::thread_rng().gen::<[u8; 32]>().encode_hex()
}

// Deterministic (abstracted via trait)
trait TokenGenerator: Send + Sync {
    fn generate(&self) -> String;
}
```

## Summary

When you practice TDD:
- Abstraction via traits is used naturally
- Responsibilities are properly separated
- Code becomes loosely coupled
- Dependency injection is used naturally

TDD = design-driven development
