---
name: valkv-cache
description: |
  Patterns for using Valkey (a Redis-compatible in-memory data store) from Rust via the redis-rs client. Covers multiplexing with MultiplexedConnection, automatic reconnection with ConnectionManager, type-safe command execution via AsyncCommands, pipelines, key namespace design, the Cache-Aside pattern, session management, error handling, and production anti-patterns to avoid (KEYS *, large values, no TTL, FLUSHALL). Use when implementing a Valkey/Redis cache or session store, deciding connection strategy, or choosing a cache update strategy. Triggers on: 'valkey cache', 'redis cache', 'redis-rs', 'cache-aside pattern', 'Valkeyキャッシュ', 'Redisキャッシュ', 'セッションストア'.
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# Valkey (Redis-compatible) + redis-rs Skill

## Targets

- Rust code that uses Valkey or Redis as a cache / session store / pub-sub
- Connection management with the `redis-rs` client (MultiplexedConnection / ConnectionManager)
- Design and implementation of cache strategies (Cache-Aside)
- Design of key expiration (TTL) strategies
- Conversion between Valkey/Redis errors and `AppError`

## Out of Scope

- Operation / monitoring of the Redis server itself -> refer to infrastructure docs
- NATS JetStream -> different use case (request/reply or durable queues)
- Detailed pub-sub design -> this skill focuses on caching; create a separate Skill if needed

## Key Aspects

### 1. Dependencies

```toml
[dependencies]
redis = { version = "0.27", features = ["tokio-comp", "connection-manager"] }
```

- `tokio-comp`: async support
- `connection-manager`: automatic reconnection
- For cluster usage, add `cluster-async`

### 2. Connection Management

- For async connections, use `MultiplexedConnection` (clonable, thread-safe, no connection pool needed)
- If automatic reconnection is required, use `ConnectionManager` (`connection-manager` feature)
- For blocking commands (`BLPOP` / `BRPOP`, etc.), use a separate dedicated connection

```rust
use redis::Client;

let client = Client::open("redis://127.0.0.1:6379/")?;
let conn = client.get_multiplexed_async_connection().await?;

#[derive(Clone)]
struct AppState {
    db_pool: DbPool,
    valkey: redis::aio::MultiplexedConnection,
}
```

### 3. Automatic Reconnection with ConnectionManager

```rust
use redis::aio::ConnectionManager;

let client = Client::open("redis://127.0.0.1:6379/")?;
let conn = ConnectionManager::new(client).await?;
```

### 4. Command Execution

- Import the `AsyncCommands` trait to use the high-level API
- Specify return type via type parameter
- Receive missing keys with `Option<T>`

```rust
use redis::AsyncCommands;

let _: () = conn.set("key", "value").await?;
let val: String = conn.get("key").await?;
let maybe: Option<String> = conn.get("maybe_missing").await?;
let _: () = conn.set_ex("session:abc", session_data, 3600).await?;
let _: () = conn.hset("user:1", "name", "Alice").await?;
let name: String = conn.hget("user:1", "name").await?;
let _: () = conn.del("key").await?;
```

### 5. Pipelines

For reducing network round-trips. Use for batch processing and cache warm-up.

```rust
let (k1, k2): (i32, i32) = redis::pipe()
    .set("key_1", 42).ignore()
    .set("key_2", 43).ignore()
    .get("key_1")
    .get("key_2")
    .query_async(&mut conn)
    .await?;
```

### 6. Key Design

- Namespace with prefix + colon-separated form: `{entity}:{id}:{attribute}`
- Examples: `user:123:profile`, `session:abc123`, `cache:posts:page:1`
- Keep key names short while preserving readability
- Always set a TTL (keys with no expiry cause memory leaks)

### 7. Cache-Aside Pattern

- On cache miss, fetch from DB -> write to cache
- On update, **delete** the cache (deletion is safer than update)

```rust
async fn get_user_cached(
    conn: &mut impl AsyncCommands,
    db: &mut AsyncPgConnection,
    user_id: i64,
) -> Result<User, AppError> {
    let cache_key = format!("user:{user_id}");

    if let Some(cached) = conn.get::<_, Option<String>>(&cache_key).await? {
        return Ok(serde_json::from_str(&cached)?);
    }

    let user = users::table
        .find(user_id)
        .select(User::as_select())
        .first(db)
        .await?;

    let serialized = serde_json::to_string(&user)?;
    let _: () = conn.set_ex(&cache_key, &serialized, 300).await?;

    Ok(user)
}

async fn update_user(/* ... */) -> Result<User, AppError> {
    let user = diesel::update(users::table.find(user_id))
        .set(&changes)
        .get_result::<User>(db)
        .await?;

    let _: () = conn.del(format!("user:{user_id}")).await?;

    Ok(user)
}
```

### 8. Session Management

- Store session data as a hash type
- Generate session IDs randomly (unguessable)
- Always set a TTL (e.g., 24 hours)

### 9. Error Handling

- Implement `From` conversion from `redis::RedisError` to `AppError`
- Retry on connection errors (automatic when using `ConnectionManager`)
- Design for degraded-mode operation when Valkey is unavailable

## Common Pitfalls

1. **Using `KEYS *` in production**: scans all keys and blocks. Use `SCAN`
2. **Storing large values under a single key**: avoid > 1 MB. Split or use a different store
3. **Long-blocking Lua scripts**: EVAL runs single-threaded
4. **Cache without TTL**: leads to unbounded memory growth
5. **Using `FLUSHALL` / `FLUSHDB` in production**: irreversible

## Project-Specific Conventions

- Cache key naming: consider a version prefix (e.g., `v1:user:123`) so old keys do not match after a schema change
- TTL default guidelines: session 24 h, API response cache 5 m, static-data cache 1 h (each project should set its own operational baseline)

## Related Rules / Skills

- Universal constraints: `design-principles` (D4: error handling), `security` (A5: authentication / sessions)
- Related Skills: `axum` (store MultiplexedConnection in AppState), `diesel` (DB + cache two-tier composition), `integration-test` (boot Valkey via testcontainers)

## References

- redis-rs docs: <https://docs.rs/redis/>
- Valkey: <https://valkey.io/>
- Redis Commands Reference: <https://redis.io/commands>
