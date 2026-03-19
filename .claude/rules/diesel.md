---
paths:
  - "**/*.rs"
  - "**/migrations/**"
  - "**/diesel.toml"
globs:
  - "**/Cargo.toml"
---

# Diesel / diesel-async Best Practices

## プロジェクト構成

- `diesel.toml` でスキーマ出力先を設定する (`file = "src/schema.rs"`)
- `schema.rs` は自動生成ファイルなので手動編集しない
- モデル定義は `models/` ディレクトリに分離する
- マイグレーションは `diesel migration generate` で作成する

```
src/
├── db/
│   ├── mod.rs          # DB接続・プール初期化
│   └── repository/     # リポジトリ層
│       ├── mod.rs
│       └── users.rs
├── models/
│   ├── mod.rs
│   └── user.rs         # Queryable, Insertable 等
├── schema.rs           # 自動生成 (diesel print-schema)
└── ...
```

## モデル定義

- 読み取り用モデルには `#[derive(Queryable, Selectable)]` を使う
- 挿入用モデルには `#[derive(Insertable)]` を使う
- 更新用モデルには `#[derive(AsChangeset)]` を使う
- `#[diesel(table_name = ...)]` でテーブルを明示する
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
    pub email: Option<Option<&'a str>>,  // Option<Option<T>> で NULL 制御
}
```

## クエリ

- `.select(Model::as_select())` を使って型安全にカラムを選択する
- フィルタは `.filter()` でチェインする
- ページネーションは `.limit()` + `.offset()` で実装する
- `get_result()` で INSERT/UPDATE 後の値を取得する (PostgreSQL の RETURNING)
- 複雑なクエリはリポジトリ層のメソッドとして実装する

```rust
// 推奨: as_select() で型安全に
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

## diesel-async 接続プール

- deadpool を推奨 (軽量、設定がシンプル)
- `AsyncDieselConnectionManager` でプールマネージャを作成する
- プールは `AppState` に格納して Axum の `State` extractor で渡す
- 接続取得失敗は適切にエラーハンドリングする

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

- 複数のDB操作をアトミックに実行する場合は必ずトランザクションを使う
- diesel-async では `connection.transaction()` に `scope_boxed()` クロージャを渡す
- エラー発生時は自動ロールバック
- テスト時は `test_transaction` でロールバック保証する

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
- `down.sql` は `up.sql` の操作を正確に巻き戻す
- マイグレーションは冪等であること
- 本番環境では `diesel migration run` を CI/CD パイプラインで実行する
- テーブル変更は非破壊的に行う (カラム追加 → データ移行 → カラム削除)

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

- N+1 クエリを避ける。関連データは JOIN またはバッチ取得する
- 必要なカラムのみ `.select()` で指定する
- 大量データの取得には `.limit()` + `.offset()` を使う
- バルクインサートは `.values(&vec_of_insertables)` で一括実行する
- インデックスが効くクエリを書く
