---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Project Architecture (Axum + Diesel + Valkey)

This rule defines the base architecture for a REST API backend configuration.
When using a Leptos full-stack configuration, the rules in `leptos.md` take precedence.

## Directory Structure

```
src/
├── main.rs              # Entry point, server startup
├── config.rs            # Environment variable and configuration loading
├── app_state.rs         # AppState definition
├── error.rs             # AppError definition (IntoResponse implementation)
├── db/
│   ├── mod.rs           # DB pool initialization
│   └── repository/      # Repository layer (abstracts DB access)
│       ├── mod.rs
│       └── users.rs
├── cache/
│   ├── mod.rs           # Valkey connection initialization
│   └── keys.rs          # Key generation helpers
├── models/
│   ├── mod.rs
│   └── user.rs          # Diesel models (Queryable, Insertable, etc.)
├── handlers/
│   ├── mod.rs
│   └── users.rs         # Axum handlers
├── routes/
│   ├── mod.rs           # Router configuration
│   └── users.rs
├── middleware/
│   ├── mod.rs
│   └── auth.rs          # Authentication middleware
├── schema.rs            # Diesel auto-generated
└── dto/
    ├── mod.rs
    └── user.rs           # Request/response types (Serialize, Deserialize)
migrations/
    └── ...
```

## Layer Structure

```
Handler (Axum) → Repository (Diesel/Valkey) → Database/Cache
```

- **Handler**: Receives HTTP requests, performs validation, builds responses
- **Repository**: Data access logic. Encapsulates DB queries and cache operations
- **Model**: Diesel table mappings
- **DTO**: API request/response types (kept separate from Model)

## AppState

```rust
use diesel_async::pooled_connection::deadpool::Pool;
use diesel_async::AsyncPgConnection;
use redis::aio::ConnectionManager;

pub type DbPool = Pool<AsyncPgConnection>;

#[derive(Clone)]
pub struct AppState {
    pub db_pool: DbPool,
    pub valkey: ConnectionManager,
    pub config: Arc<AppConfig>,
}
```

## Unified Error Type

```rust
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};

pub enum AppError {
    NotFound,
    BadRequest(String),
    Unauthorized,
    Conflict(String),
    Internal(anyhow::Error),
}

impl From<diesel::result::Error> for AppError { /* ... */ }
impl From<redis::RedisError> for AppError { /* ... */ }
impl From<deadpool::managed::PoolError<deadpool_diesel::postgres::Manager>> for AppError { /* ... */ }
impl IntoResponse for AppError { /* ... */ }
```

## Dependency Guidelines

```toml
[dependencies]
axum = "0.8"
diesel = { version = "2.2", features = ["postgres"] }
diesel-async = { version = "0.5", features = ["postgres", "deadpool"] }
redis = { version = "0.27", features = ["tokio-comp", "connection-manager"] }
tokio = { version = "1", features = ["full"] }
tower = "0.5"
tower-http = { version = "0.6", features = ["trace", "cors", "timeout"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
anyhow = "1"
dotenvy = "0.15"
```

## Configuration Management

- Load from environment variables (`dotenvy` + `std::env`)
- Consolidate `DATABASE_URL`, `VALKEY_URL`, `HOST`, `PORT`, etc. into `AppConfig`
- Do not hardcode secrets (DB passwords, etc.) in code
- Switch configuration per environment using environment variables

## Logging and Tracing

- Use `tracing` + `tracing-subscriber`
- Output request logs with `tower_http::trace::TraceLayer`
- Control the log level with the `RUST_LOG` environment variable
- Use structured logging (`tracing::info!(user_id = %id, "User created")`)

## Testing Strategy

- Unit tests: Test the repository layer directly (test DB + transaction rollback)
- Integration tests: Test the full Axum app with `tower::ServiceExt`
- Provide a helper function to construct `AppState` for tests
- Use `test_transaction` to roll back the test DB
