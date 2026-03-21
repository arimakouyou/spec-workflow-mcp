---
paths:
  - "**/*.rs"
globs:
  - "**/Cargo.toml"
---

# Axum Best Practices

## Router Configuration

- Create routers with `Router::new()` and register routes with `route()`
- Split related routes into separate `Router` modules and combine them with `merge()` or `nest()`
- Use `nest("/api/v1", api_routes())` to group routes under a common prefix
- Keep route definition files and handler implementation files separate

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

## State Management

- Define application state as a `#[derive(Clone)]` struct and pass it with `Router::with_state()`
- Consolidate shared resources such as DB pools and configuration values into `AppState`
- Use `Arc<RwLock<T>>` or `Arc<Mutex<T>>` when mutable shared state is required
- Retrieve state in handlers via the `State` extractor

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

## Extractors

- Extractor argument order matters. Place extractors that consume the request body (`Json`, `Form`, etc.) last
- Place `Path`, `Query`, and `State` first since they do not consume the body
- Implement `FromRequest` / `FromRequestParts` when creating custom extractors
- Perform validation at the extractor level

```rust
async fn update_user(
    State(state): State<AppState>,
    Path(user_id): Path<i64>,
    Json(payload): Json<UpdateUserRequest>,  // body-consuming extractor goes last
) -> Result<Json<User>, AppError> {
    // ...
}
```

## Error Handling

- Define an application-wide error type that implements `IntoResponse`
- Use `Result<T, AppError>` as the return type of handlers
- Implement `From` conversions from each error type (diesel, redis, etc.) to `AppError`
- Manage the mapping between HTTP status codes and error messages in a single place

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

- Use `tower::ServiceBuilder` to apply middleware in bulk (executed top to bottom)
- Implement authentication and authorization with `middleware::from_fn` or `middleware::from_fn_with_state`
- Use `TraceLayer` (tower-http) for request logging
- Configure timeouts with `HandleErrorLayer` + `tower::timeout`
- Apply middleware to all routes with `.layer()`, and only to authenticated routes with `.route_layer()`

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

## Responses

- Return successful responses as `Json<T>` (where `T: Serialize`)
- Use a tuple `(StatusCode, Json<T>)` when an explicit status code is needed
- Return `StatusCode::NO_CONTENT` for empty responses
- Use `axum::body::Body` for streaming responses

## Graceful Shutdown

- Configure `with_graceful_shutdown` on `axum::serve`
- Handle SIGTERM/SIGINT with `tokio::signal`

```rust
let listener = TcpListener::bind("0.0.0.0:3000").await?;
axum::serve(listener, app)
    .with_graceful_shutdown(shutdown_signal())
    .await?;

async fn shutdown_signal() {
    tokio::signal::ctrl_c().await.expect("failed to listen for ctrl_c");
}
```

## Testing

- Test handlers directly using `axum::body::Body` and `tower::ServiceExt`
- Construct a test `AppState` to inject test DBs or mocks
- Send actual HTTP requests in integration tests
