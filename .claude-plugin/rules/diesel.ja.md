---
paths:
  - "**/*.rs"
  - "**/migrations/**"
  - "**/diesel.toml"
globs:
  - "**/Cargo.toml"
---

# Diesel / diesel-async ベストプラクティス

## プロジェクト構成

- `diesel.toml` でスキーマ出力パスを設定する（`file = "src/schema.rs"`）
- `schema.rs` は自動生成ファイルのため手動で編集しない
- モデル定義は個別の `models/` ディレクトリに配置する
- マイグレーションは `diesel migration generate` で作成する

```
src/
├── db/
│   ├── mod.rs          # DB接続とプール初期化
│   └── repository/     # リポジトリレイヤー
│       ├── mod.rs
│       └── users.rs
├── models/
│   ├── mod.rs
│   └── user.rs         # Queryable, Insertable など
├── schema.rs           # 自動生成（diesel print-schema）
└── ...
```

## モデル定義

- 読み取りモデルには `#[derive(Queryable, Selectable)]` を使用する
- 挿入モデルには `#[derive(Insertable)]` を使用する
- 更新モデルには `#[derive(AsChangeset)]` を使用する
- `#[diesel(table_name = ...)]` でテーブルを明示的に指定する
- `#[diesel(check_for_backend(Pg))]` でコンパイル時にバックエンド互換性を検証する

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
    pub email: Option<Option<&'a str>>,  // Option<Option<T>> で NULL の挙動を制御
}
```

## クエリ

- `.select(Model::as_select())` を使用して型安全にカラムを選択する
- `.filter()` でフィルターを連結する
- `.limit()` + `.offset()` でページネーションを実装する
- INSERT/UPDATE 後の値取得には `get_result()` を使用する（PostgreSQL の RETURNING）
- 複雑なクエリはリポジトリレイヤーのメソッドとして実装する

```rust
// 推奨: as_select() による型安全な選択
let users: Vec<User> = users::table
    .filter(users::name.like(format!("%{query}%")))
    .select(User::as_select())
    .order(users::created_at.desc())
    .limit(20)
    .offset(0)
    .load(conn)
    .await?;

// upsert（PostgreSQL）
diesel::insert_into(users::table)
    .values(&new_user)
    .on_conflict(users::email)
    .do_update()
    .set(&update_user)
    .get_result::<User>(conn)
    .await?;
```

## diesel-async コネクションプール

- deadpool を推奨（軽量でシンプルな設定）
- `AsyncDieselConnectionManager` でプールマネージャを作成する
- プールを `AppState` に格納し、Axum の `State` エクストラクタで渡す
- コネクション取得失敗を適切なエラーハンドリングで処理する

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

## トランザクション

- 複数の DB 操作をアトミックに実行する場合は必ずトランザクションを使用する
- diesel-async では `connection.transaction()` に `scope_boxed()` クロージャを渡す
- エラー発生時は自動的にロールバックされる
- テストでは `test_transaction` を使用してロールバックを保証する

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

## マイグレーション

- `diesel migration generate create_users` でマイグレーションを作成する
- `up.sql` と `down.sql` は必ずペアで作成する
- `down.sql` は `up.sql` の操作を正確に元に戻さなければならない
- マイグレーションは冪等でなければならない
- 本番環境では CI/CD パイプラインで `diesel migration run` を実行する
- テーブル変更は非破壊的に行う（カラム追加 → データ移行 → カラム削除）

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

## パフォーマンス

- N+1 クエリを避ける。JOIN やバッチクエリで関連データを取得する
- `.select()` で必要なカラムのみを指定する
- 大量データの取得時は `.limit()` + `.offset()` を使用する
- バルクインサートは `.values(&vec_of_insertables)` で一度に実行する
- インデックスを活用できるクエリを記述する
