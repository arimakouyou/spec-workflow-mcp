---
paths:
  - "**/*.rs"
globs:
  - "**/Cargo.toml"
---

# Axum ベストプラクティス

## ルーター設定

- `Router::new()` でルーターを作成し、`route()` でルートを登録する
- 関連するルートを個別の `Router` モジュールに分割し、`merge()` または `nest()` で結合する
- `nest("/api/v1", api_routes())` を使用して共通プレフィックスの下にルートをグルーピングする
- ルート定義ファイルとハンドラー実装ファイルを分離する

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

## ステート管理

- アプリケーションステートを `#[derive(Clone)]` 構造体として定義し、`Router::with_state()` で渡す
- DB プールや設定値などの共有リソースを `AppState` に集約する
- 変更可能な共有ステートが必要な場合は `Arc<RwLock<T>>` または `Arc<Mutex<T>>` を使用する
- ハンドラーでは `State` エクストラクターでステートを取得する

```rust
#[derive(Clone)]
struct AppState {
    db_pool: Pool<AsyncPgConnection>,
    valkey_pool: redis::aio::MultiplexedConnection,
    config: Arc<AppConfig>,
}

async fn handler(State(state): State<AppState>) -> impl IntoResponse {
    // use state.db_pool, state.valkey_pool
}
```

## エクストラクター

- エクストラクターの引数順序は重要。リクエストボディを消費するエクストラクター（`Json`、`Form` など）は最後に配置する
- `Path`、`Query`、`State` はボディを消費しないため先に配置する
- カスタムエクストラクター作成時は `FromRequest` / `FromRequestParts` を実装する
- エクストラクターレベルでバリデーションを行う

```rust
async fn update_user(
    State(state): State<AppState>,
    Path(user_id): Path<i64>,
    Json(payload): Json<UpdateUserRequest>,  // ボディ消費エクストラクターは最後
) -> Result<Json<User>, AppError> {
    // ...
}
```

## エラーハンドリング

- `IntoResponse` を実装するアプリケーション共通のエラー型を定義する
- ハンドラーの戻り値型として `Result<T, AppError>` を使用する
- 各エラー型（diesel、redis など）から `AppError` への `From` 変換を実装する
- HTTP ステータスコードとエラーメッセージのマッピングを一箇所で管理する

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

## ミドルウェア

- `tower::ServiceBuilder` を使用してミドルウェアを一括適用する（上から下に実行）
- 認証・認可は `middleware::from_fn` または `middleware::from_fn_with_state` で実装する
- リクエストログには `TraceLayer`（tower-http）を使用する
- タイムアウトは `HandleErrorLayer` + `tower::timeout` で設定する
- すべてのルートに適用するには `.layer()`、認証が必要なルートのみに適用するには `.route_layer()` を使用する

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
            .layer(
                CorsLayer::new()
                    .allow_origin("https://example.com".parse::<HeaderValue>().unwrap())
                    .allow_methods([Method::GET, Method::POST])
                    .allow_headers([AUTHORIZATION, CONTENT_TYPE]),
            )
    )
    .with_state(state);
```

## レスポンス

- 成功レスポンスは `Json<T>`（`T: Serialize`）として返す
- 明示的なステータスコードが必要な場合はタプル `(StatusCode, Json<T>)` を使用する
- 空のレスポンスには `StatusCode::NO_CONTENT` を返す
- ストリーミングレスポンスには `axum::body::Body` を使用する

## グレースフルシャットダウン

- `axum::serve` に `with_graceful_shutdown` を設定する
- `tokio::signal` で SIGTERM/SIGINT を処理する

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

- `axum::body::Body` と `tower::ServiceExt` を使用してハンドラーを直接テストする
- テスト用の `AppState` を構築してテスト DB やモックを注入する
- インテグレーションテストでは実際の HTTP リクエストを送信する
