# External API Mocking Patterns

A pattern for swapping out external API clients with test doubles using trait-based DI.

## Recommended Pattern: trait DI override

```rust
// Production code: trait definition
#[async_trait]
pub trait PaymentGateway: Send + Sync {
    async fn charge(&self, amount: u64) -> Result<PaymentResult, PaymentError>;
}

// Production implementation
pub struct StripeGateway { /* ... */ }

#[async_trait]
impl PaymentGateway for StripeGateway {
    async fn charge(&self, amount: u64) -> Result<PaymentResult, PaymentError> {
        // Actual API call
    }
}
```

## Test Doubles

### Stub (returns a fixed value)

```rust
pub struct StubPaymentGateway {
    pub result: Result<PaymentResult, PaymentError>,
}

#[async_trait]
impl PaymentGateway for StubPaymentGateway {
    async fn charge(&self, _amount: u64) -> Result<PaymentResult, PaymentError> {
        self.result.clone()
    }
}
```

### Spy (records calls + fixed value)

```rust
pub struct SpyPaymentGateway {
    pub calls: Arc<Mutex<Vec<u64>>>,
    pub result: Result<PaymentResult, PaymentError>,
}

#[async_trait]
impl PaymentGateway for SpyPaymentGateway {
    async fn charge(&self, amount: u64) -> Result<PaymentResult, PaymentError> {
        self.calls.lock().unwrap().push(amount);
        self.result.clone()
    }
}
```

### Failing External API

```rust
pub struct FailingPaymentGateway;

#[async_trait]
impl PaymentGateway for FailingPaymentGateway {
    async fn charge(&self, _amount: u64) -> Result<PaymentResult, PaymentError> {
        Err(PaymentError::ServiceUnavailable)
    }
}
```

## Wiring Into TestContext

```rust
impl TestContext {
    pub async fn with_failing_external_api() -> Self {
        let (container, url) = create_pg_container().await;
        run_migrations(&url).await;
        let db_pool = create_pool(&url);

        // Inject the failing external API
        let state = AppState {
            db_pool: db_pool.clone(),
            payment: Arc::new(FailingPaymentGateway) as Arc<dyn PaymentGateway>,
            // ...
        };

        let app = routes().with_state(state);
        Self { app, db_pool, _pg_container: container, /* ... */ }
    }
}
```

## Prohibited

- Do not change production behavior with `#[cfg(test)]`
- Do not mock concrete types directly with mockall — always go through a trait
- Do not rewrite environment variables with `std::env::set_var` inside tests (causes cross-test interference)
