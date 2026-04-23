---
name: diesel
description: |
  Diesel / diesel-async ORM (Rust) のベストプラクティス。`Queryable`/`Selectable`/`Insertable`/`AsChangeset` による model 定義、`diesel.toml` の schema 自動生成、`.select(Model::as_select())` での type-safe クエリ、deadpool + `AsyncDieselConnectionManager` による connection pool、`.transaction()` と `scope_boxed()` によるトランザクション、up.sql/down.sql ペアでのマイグレーション、N+1 回避と batch insert をカバー。Diesel 利用 Rust コードの新規追加、既存クエリ修正、migration 作成、repository レイヤ実装、PostgreSQL スキーマ設計時に参照。
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# Diesel / diesel-async Best Practices

## 対象

- Diesel model の新規定義・更新（`Queryable`, `Selectable`, `Insertable`, `AsChangeset`）
- type-safe クエリの記述、repository レイヤの実装
- migration の作成（up.sql / down.sql）と運用
- diesel-async の connection pool 設計
- トランザクション境界の設計

## 対象外

- Axum handler の実装 → `axum` Skill
- Valkey/Redis キャッシュ連携 → `valkv-cache` Skill
- PostgreSQL 自体の運用（DB チューニング、バックアップ） → インフラ側

## Project Structure

- Configure the schema output path in `diesel.toml` (`file = "src/schema.rs"`)
- Do not manually edit `schema.rs` — it is an auto-generated file
- Place model definitions in a separate `models/` directory
- Create migrations with `diesel migration generate`

```
src/
├── db/
│   ├── mod.rs          # DB connection and pool initialization
│   └── repository/     # Repository layer
│       ├── mod.rs
│       └── users.rs
├── models/
│   ├── mod.rs
│   └── user.rs         # Queryable, Insertable, etc.
├── schema.rs           # Auto-generated (diesel print-schema)
└── ...
```

## Model Definitions

- Use `#[derive(Queryable, Selectable)]` for read models
- Use `#[derive(Insertable)]` for insert models
- Use `#[derive(AsChangeset)]` for update models
- Explicitly specify the table with `#[diesel(table_name = ...)]`
- Use `#[diesel(check_for_backend(Pg))]` to verify backend compatibility at compile time

```rust
#[derive(Debug, Queryable, Selectable)]
#[diesel(table_name = users)]
#[diesel(check_for_backend(Pg))]
pub struct User {
    pub id: i64,
    pub name: String,
    pub email: Option<String>,
    pub created_at: NaiveDateTime,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = users)]
pub struct NewUser<'a> {
    pub name: &'a str,
    pub email: Option<&'a str>,
}

#[derive(Debug, AsChangeset)]
#[diesel(table_name = users)]
pub struct UpdateUser<'a> {
    pub name: Option<&'a str>,
    pub email: Option<Option<&'a str>>,  // Option<Option<T>> controls NULL behavior
}
```

## Queries

- Use `.select(Model::as_select())` to select columns in a type-safe manner
- Chain filters with `.filter()`
- Implement pagination with `.limit()` + `.offset()`
- Use `get_result()` to retrieve values after INSERT/UPDATE (PostgreSQL RETURNING)
- Implement complex queries as repository layer methods

```rust
// Recommended: type-safe selection with as_select()
let users: Vec<User> = users::table
    .filter(users::name.like(format!("%{query}%")))
    .select(User::as_select())
    .order(users::created_at.desc())
    .limit(20)
    .offset(0)
    .load(conn)
    .await?;

// upsert (PostgreSQL)
diesel::insert_into(users::table)
    .values(&new_user)
    .on_conflict(users::email)
    .do_update()
    .set(&update_user)
    .get_result::<User>(conn)
    .await?;
```

## diesel-async Connection Pool

- deadpool is recommended (lightweight, simple configuration)
- Create a pool manager with `AsyncDieselConnectionManager`
- Store the pool in `AppState` and pass it via Axum's `State` extractor
- Handle connection acquisition failures with proper error handling

```rust
use diesel_async::pooled_connection::AsyncDieselConnectionManager;
use diesel_async::pooled_connection::deadpool::Pool;
use diesel_async::AsyncPgConnection;

pub type DbPool = Pool<AsyncPgConnection>;

pub fn create_pool(database_url: &str) -> DbPool {
    let config = AsyncDieselConnectionManager::<AsyncPgConnection>::new(database_url);
    Pool::builder(config)
        .build()
        .expect("Failed to create pool")
}
```

## Transactions

- Always use transactions when multiple DB operations must be executed atomically
- In diesel-async, pass a `scope_boxed()` closure to `connection.transaction()`
- Errors automatically trigger a rollback
- Use `test_transaction` in tests to guarantee rollback

```rust
conn.transaction::<_, diesel::result::Error, _>(|conn| {
    async move {
        let user = diesel::insert_into(users::table)
            .values(&new_user)
            .get_result::<User>(conn)
            .await?;

        diesel::insert_into(profiles::table)
            .values(&NewProfile { user_id: user.id })
            .execute(conn)
            .await?;

        Ok(user)
    }
    .scope_boxed()
})
.await?;
```

## Migrations

- Create migrations with `diesel migration generate create_users`
- Always create `up.sql` and `down.sql` as a pair
- `down.sql` must precisely reverse the operations in `up.sql`
- Migrations must be idempotent
- Run `diesel migration run` in the CI/CD pipeline for production environments
- Make table changes non-destructively (add column → migrate data → drop column)

```sql
-- up.sql
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);

-- down.sql
DROP TABLE users;
```

## Performance

- Avoid N+1 queries. Fetch related data using JOINs or batch queries
- Specify only the necessary columns with `.select()`
- Use `.limit()` + `.offset()` when fetching large amounts of data
- Perform bulk inserts in a single call with `.values(&vec_of_insertables)`
- Write queries that can make use of indexes

## 関連 Rule / Skill

- 普遍制約: `rust-style`, `design-principles`, `security` (A1-A10: SQL injection 等), `type-safety` (TS-R1-R5)
- 関連 Skill: `axum` (AppState に DbPool 格納), `cargo-toml`, `rust-build-cache`, `tdd-skills-rust`, `integration-test` (testcontainers での DB テスト), `spec-tasks`, `spec-test-design`
