---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# プロジェクトアーキテクチャ (Axum + Diesel + Valkey)

このルールは REST API バックエンド構成の基本アーキテクチャを定義する。
Leptos フルスタック構成の場合は `leptos.md` のルールが優先される。

## ディレクトリ構成

```
src/
├── main.rs              # エントリポイント、サーバ起動
├── config.rs            # 環境変数・設定読み込み
├── app_state.rs         # AppState 定義
├── error.rs             # AppError 定義 (IntoResponse 実装)
├── db/
│   ├── mod.rs           # DB プール初期化
│   └── repository/      # リポジトリ層 (DBアクセスを抽象化)
│       ├── mod.rs
│       └── users.rs
├── cache/
│   ├── mod.rs           # Valkey 接続初期化
│   └── keys.rs          # キー生成ヘルパー
├── models/
│   ├── mod.rs
│   └── user.rs          # Diesel モデル (Queryable, Insertable 等)
├── handlers/
│   ├── mod.rs
│   └── users.rs         # Axum ハンドラ
├── routes/
│   ├── mod.rs           # ルーター構成
│   └── users.rs
├── middleware/
│   ├── mod.rs
│   └── auth.rs          # 認証ミドルウェア
├── schema.rs            # Diesel 自動生成
└── dto/
    ├── mod.rs
    └── user.rs           # リクエスト/レスポンス型 (Serialize, Deserialize)
migrations/
    └── ...
```

## レイヤー構成

```
Handler (Axum) → Repository (Diesel/Valkey) → Database/Cache
```

- **Handler**: HTTP リクエストの受付、バリデーション、レスポンス構築
- **Repository**: データアクセスロジック。DB クエリとキャッシュ操作をカプセル化
- **Model**: Diesel のテーブルマッピング
- **DTO**: API のリクエスト/レスポンス型 (Model とは分離する)

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

## エラー型の統一

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
impl From<deadpool::managed::PoolError</* ... */>> for AppError { /* ... */ }
impl IntoResponse for AppError { /* ... */ }
```

## 依存関係のガイドライン

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

## 設定管理

- 環境変数から読み込む (`dotenvy` + `std::env`)
- `DATABASE_URL`, `VALKEY_URL`, `HOST`, `PORT` 等を `AppConfig` にまとめる
- シークレット (DB パスワード等) はコードにハードコードしない
- 環境ごとの設定は環境変数で切り替える

## ログ・トレーシング

- `tracing` + `tracing-subscriber` を使う
- `tower_http::trace::TraceLayer` でリクエストログを出力する
- `RUST_LOG` 環境変数でログレベルを制御する
- 構造化ログを使う (`tracing::info!(user_id = %id, "User created")`)

## テスト戦略

- 単体テスト: リポジトリ層を直接テスト (テスト用 DB + トランザクションロールバック)
- 統合テスト: Axum アプリ全体を `tower::ServiceExt` でテスト
- テスト用の `AppState` を構築するヘルパー関数を用意する
- テスト用 DB は `test_transaction` でロールバックする
