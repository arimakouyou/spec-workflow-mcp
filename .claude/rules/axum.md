---
paths:
  - "**/*.rs"
globs:
  - "**/Cargo.toml"
---

# Axum Best Practices

## Router 構成

- `Router::new()` でルーターを作成し、`route()` でルートを登録する
- 関連するルートは `Router` 単位でモジュール分割し、`merge()` や `nest()` で結合する
- `nest("/api/v1", api_routes())` でプレフィックスをまとめる
- ルート定義ファイルと handler 実装ファイルは分離する

```rust
// routes/mod.rs
pub fn routes() -> Router<AppState> {
    Router::new()
        .merge(users::routes())
        .merge(posts::routes())
}

// routes/users.rs
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/users", get(list_users).post(create_user))
        .route("/users/{id}", get(get_user).put(update_user).delete(delete_user))
}
```

## State 管理

- アプリケーション状態は `#[derive(Clone)]` な構造体で定義し、`Router::with_state()` で渡す
- DB プールや設定値など共有リソースは `AppState` にまとめる
- 可変共有状態が必要な場合は `Arc<RwLock<T>>` や `Arc<Mutex<T>>` を使う
- `State` extractor でハンドラから取得する

```rust
#[derive(Clone)]
struct AppState {
    db_pool: Pool<AsyncPgConnection>,
    valkey_pool: redis::aio::MultiplexedConnection,
    config: Arc<AppConfig>,
}

async fn handler(State(state): State<AppState>) -> impl IntoResponse {
    // state.db_pool, state.valkey_pool を使用
}
```

## Extractor

- Extractor は引数の順序に意味がある。リクエストボディを消費する extractor (`Json`, `Form` 等) は最後に置く
- `Path`, `Query`, `State` はボディを消費しないため先に配置する
- カスタム extractor を作る場合は `FromRequest` / `FromRequestParts` を実装する
- バリデーションは extractor レベルで行う

```rust
async fn update_user(
    State(state): State<AppState>,
    Path(user_id): Path<i64>,
    Json(payload): Json<UpdateUserRequest>,  // ボディ消費は最後
) -> Result<Json<User>, AppError> {
    // ...
}
```

## エラーハンドリング

- `IntoResponse` を実装したアプリケーション共通エラー型を定義する
- ハンドラの戻り値は `Result<T, AppError>` とする
- `From` トレイトで各エラー型 (diesel, redis, etc.) から `AppError` への変換を実装する
- HTTP ステータスコードとエラーメッセージの対応を一箇所で管理する

```rust
enum AppError {
    NotFound,
    BadRequest(String),
    Internal(anyhow::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            AppError::NotFound => (StatusCode::NOT_FOUND, "Not found".to_string()),
            AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            AppError::Internal(err) => {
                tracing::error!(%err, "Internal error");
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".to_string())
            }
        };
        (status, Json(json!({ "error": message }))).into_response()
    }
}
```

## Middleware

- `tower::ServiceBuilder` で middleware をまとめて適用する (上から順に実行される)
- 認証・認可は `middleware::from_fn` または `middleware::from_fn_with_state` で実装する
- `TraceLayer` (tower-http) をリクエストログに使う
- タイムアウトは `HandleErrorLayer` + `tower::timeout` で設定する
- 全ルートに適用するものは `.layer()`、認証が必要なルートのみは `.route_layer()` で適用する

```rust
let app = Router::new()
    .route("/protected", get(protected_handler))
    .route_layer(middleware::from_fn_with_state(state.clone(), auth))
    .route("/public", get(public_handler))
    .layer(
        ServiceBuilder::new()
            .layer(TraceLayer::new_for_http())
            .layer(HandleErrorLayer::new(handle_timeout))
            .timeout(Duration::from_secs(30))
            .layer(CorsLayer::permissive())
    )
    .with_state(state);
```

## レスポンス

- 成功レスポンスは `Json<T>` で返す (`T: Serialize`)
- ステータスコードを明示したい場合は `(StatusCode, Json<T>)` のタプルで返す
- 空レスポンスは `StatusCode::NO_CONTENT` を返す
- ストリーミングレスポンスには `axum::body::Body` を使う

## Graceful Shutdown

- `axum::serve` に `with_graceful_shutdown` を設定する
- `tokio::signal` で SIGTERM/SIGINT をハンドルする

```rust
let listener = TcpListener::bind("0.0.0.0:3000").await?;
axum::serve(listener, app)
    .with_graceful_shutdown(shutdown_signal())
    .await?;

async fn shutdown_signal() {
    tokio::signal::ctrl_c().await.expect("failed to listen for ctrl_c");
}
```

## テスト

- `axum::body::Body` と `tower::ServiceExt` を使ってハンドラを直接テストする
- テスト用の `AppState` を作成してテスト用 DB / モックを注入する
- 統合テストでは実際の HTTP リクエストを送信する
