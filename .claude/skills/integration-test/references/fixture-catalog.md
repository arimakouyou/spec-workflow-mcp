# 共通ヘルパー・Fixture カタログ

`tests/integration/helpers/` で定義するテスト用ヘルパーの一覧。

## TestContext（中核ヘルパー）

各テストで独立した DB コンテナと Axum アプリケーションを提供する。

```rust
pub struct TestContext {
    pub app: Router,
    pub db_pool: DbPool,
    pub valkey: ConnectionManager,
    _pg_container: ContainerAsync<Postgres>,
}

impl TestContext {
    /// 新しいテストコンテキストを作成（実 PostgreSQL コンテナ起動）
    pub async fn new() -> Self { /* ... */ }

    /// 外部 API がエラーを返す設定で作成
    pub async fn with_failing_external_api() -> Self { /* ... */ }

    /// GET リクエスト（認証ヘッダー付き）
    pub async fn get(&self, path: &str) -> TestResponse { /* ... */ }

    /// GET リクエスト（認証なし）
    pub async fn get_without_auth(&self, path: &str) -> TestResponse { /* ... */ }

    /// POST リクエスト（認証ヘッダー付き）
    pub async fn post(&self, path: &str) -> RequestBuilder { /* ... */ }

    /// PUT リクエスト（認証ヘッダー付き）
    pub async fn put(&self, path: &str) -> RequestBuilder { /* ... */ }

    /// DELETE リクエスト（認証ヘッダー付き）
    pub async fn delete(&self, path: &str) -> TestResponse { /* ... */ }
}
```

## DB 関連ヘルパー

### PostgreSQL コンテナ

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

### マイグレーション実行

```rust
use diesel_async::AsyncPgConnection;
use diesel_migrations::{embed_migrations, EmbeddedMigrations, MigrationHarness};

const MIGRATIONS: EmbeddedMigrations = embed_migrations!();

async fn run_migrations(database_url: &str) {
    // diesel の同期マイグレーションを blocking task で実行
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

### テストデータ投入 (Seed)

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

## 認証ヘッダー

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

## Axum アプリ構築

```rust
async fn build_test_app(db_pool: DbPool, valkey: ConnectionManager) -> Router {
    let state = AppState {
        db_pool,
        valkey,
        config: Arc::new(test_config()),
    };

    // 本番と同じルーター構成を使用
    crate::routes::routes()
        .with_state(state)
}
```

## Fixture 選択フロー

```
テストで何が必要？
  ├─ DB アクセスが必要
  │   └─ TestContext::new() を使用
  │       ├─ テストデータ投入 → seed_user(), seed_users()
  │       └─ DB 検証 → find_user_by_id(), find_user_by_email()
  │
  ├─ 外部 API のモック
  │   └─ TestContext::with_failing_external_api() or カスタム trait 実装
  │
  └─ HTTP リクエスト送信
      └─ ctx.get(), ctx.post(), ctx.put(), ctx.delete()
```
