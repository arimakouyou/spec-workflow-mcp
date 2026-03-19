# 外部 API モックパターン

trait ベースの DI で外部 API クライアントをテストダブルに差し替えるパターン。

## 推奨パターン: trait DI override

```rust
// 本番コード: trait 定義
#[async_trait]
pub trait PaymentGateway: Send + Sync {
    async fn charge(&self, amount: u64) -> Result<PaymentResult, PaymentError>;
}

// 本番実装
pub struct StripeGateway { /* ... */ }

#[async_trait]
impl PaymentGateway for StripeGateway {
    async fn charge(&self, amount: u64) -> Result<PaymentResult, PaymentError> {
        // 実際の API 呼び出し
    }
}
```

## テスト用テストダブル

### Stub（固定値を返す）

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

### Spy（呼び出し記録 + 固定値）

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

### 失敗する外部 API

```rust
pub struct FailingPaymentGateway;

#[async_trait]
impl PaymentGateway for FailingPaymentGateway {
    async fn charge(&self, _amount: u64) -> Result<PaymentResult, PaymentError> {
        Err(PaymentError::ServiceUnavailable)
    }
}
```

## TestContext への組み込み

```rust
impl TestContext {
    pub async fn with_failing_external_api() -> Self {
        let (container, url) = create_pg_container().await;
        run_migrations(&url).await;
        let db_pool = create_pool(&url);

        // 失敗する外部 API を注入
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

## 禁止事項

- `#[cfg(test)]` で本番コードの振る舞いを変えない
- mockall で具象型を直接 mock しない → 必ず trait を経由する
- テスト内で `std::env::set_var` で環境変数を書き換えない（テスト間で干渉する）
