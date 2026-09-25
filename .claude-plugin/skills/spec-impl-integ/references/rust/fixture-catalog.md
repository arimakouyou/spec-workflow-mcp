# Common Helpers and Fixture Catalog

A catalog of test helpers defined in `tests/integration/helpers/`.

## TestContext (Core Helper)

Provides an independent DB container and Axum application for each test.

```rust
pub struct TestContext {
    pub app: Router,
    pub db_pool: DbPool,
    pub valkey: ConnectionManager,
    _pg_container: ContainerAsync<Postgres>,
}

impl TestContext {
    /// Create a new test context (starts a real PostgreSQL container)
    pub async fn new() -> Self { /* ... */ }

    /// Create with the external API configured to return errors
    pub async fn with_failing_external_api() -> Self { /* ... */ }

    /// GET request (with authentication header)
    pub async fn get(&self, path: &str) -> TestResponse { /* ... */ }

    /// GET request (without authentication)
    pub async fn get_without_auth(&self, path: &str) -> TestResponse { /* ... */ }

    /// POST request (with authentication header)
    pub async fn post(&self, path: &str) -> RequestBuilder { /* ... */ }

    /// PUT request (with authentication header)
    pub async fn put(&self, path: &str) -> RequestBuilder { /* ... */ }

    /// DELETE request (with authentication header)
    pub async fn delete(&self, path: &str) -> TestResponse { /* ... */ }
}
```

## DB Helpers

### PostgreSQL Container

```rust
use testcontainers::runners::AsyncRunner;
use testcontainers_modules::postgres::Postgres;

async fn create_pg_container() -> (ContainerAsync<Postgres>, String) {
    let container = Postgres::default().start().await.unwrap();
    let port = container.get_host_port_ipv4(5432).await.unwrap();
    let url = format!("postgres://postgres:postgres@localhost:{port}/postgres");
    (container, url)
}
```

### Migration Execution

```rust
use diesel_async::AsyncPgConnection;
use diesel_migrations::{embed_migrations, EmbeddedMigrations, MigrationHarness};

const MIGRATIONS: EmbeddedMigrations = embed_migrations!();

async fn run_migrations(database_url: &str) {
    // Run diesel synchronous migrations inside a blocking task
    let url = database_url.to_string();
    tokio::task::spawn_blocking(move || {
        use diesel::prelude::*;
        let mut conn = PgConnection::establish(&url).unwrap();
        conn.run_pending_migrations(MIGRATIONS).unwrap();
    })
    .await
    .unwrap();
}
```

### Seeding Test Data

```rust
impl TestContext {
    pub async fn seed_user(&self, new_user: &NewUser) -> User {
        let mut conn = self.db_pool.get().await.unwrap();
        diesel::insert_into(users::table)
            .values(new_user)
            .get_result(&mut conn)
            .await
            .unwrap()
    }

    pub async fn seed_users(&self, users: &[NewUser]) -> Vec<User> {
        let mut conn = self.db_pool.get().await.unwrap();
        diesel::insert_into(users::table)
            .values(users)
            .get_results(&mut conn)
            .await
            .unwrap()
    }

    pub async fn find_user_by_id(&self, id: i64) -> Option<User> {
        let mut conn = self.db_pool.get().await.unwrap();
        users::table.find(id)
            .select(User::as_select())
            .first(&mut conn)
            .await
            .optional()
            .unwrap()
    }
}
```

## Authentication Header

```rust
fn test_auth_header() -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(
        "Authorization",
        HeaderValue::from_static("Bearer test-token-xxx"),
    );
    headers
}
```

## Axum App Construction

```rust
async fn build_test_app(db_pool: DbPool, valkey: ConnectionManager) -> Router {
    let state = AppState {
        db_pool,
        valkey,
        config: Arc::new(test_config()),
    };

    // Use the same router configuration as production
    crate::routes::routes()
        .with_state(state)
}
```

## Fixture Selection Flow

```
What does the test need?
  ├─ DB access required
  │   └─ Use TestContext::new()
  │       ├─ Seed data → seed_user(), seed_users()
  │       └─ DB verification → find_user_by_id(), find_user_by_email()
  │
  ├─ External API mocking
  │   └─ TestContext::with_failing_external_api() or a custom trait implementation
  │
  └─ HTTP request dispatch
      └─ ctx.get(), ctx.post(), ctx.put(), ctx.delete()
```
