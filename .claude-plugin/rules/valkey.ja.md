---
paths:
  - "**/*.rs"
globs:
  - "**/Cargo.toml"
---

# Valkey (redis-rs) Best Practices

Valkey は Redis 互換のインメモリデータストア。Rust クライアントには `redis-rs` を使用する。

## 依存関係

```toml
[dependencies]
redis = { version = "0.27", features = ["tokio-comp", "connection-manager"] }
```

- `tokio-comp` feature で非同期サポートを有効化する
- クラスター使用時は `cluster-async` feature を追加する

## 接続管理

- 非同期接続には `MultiplexedConnection` を使う (クローン可能、スレッドセーフ)
- 接続プールは通常不要。`MultiplexedConnection` が内部で多重化する
- 自動再接続には `ConnectionManager` (`connection-manager` feature) を使う
- ブロッキングコマンド (`BLPOP`, `BRPOP` 等) は専用の接続で実行する

```rust
use redis::Client;

let client = Client::open("redis://127.0.0.1:6379/")?;
let conn = client.get_multiplexed_async_connection().await?;

// conn は Clone 可能なので AppState に格納して共有できる
#[derive(Clone)]
struct AppState {
    db_pool: DbPool,
    valkey: redis::aio::MultiplexedConnection,
}
```

## ConnectionManager による自動再接続

```rust
use redis::aio::ConnectionManager;

let client = Client::open("redis://127.0.0.1:6379/")?;
let conn = ConnectionManager::new(client).await?;
// conn は Clone 可能、接続断時に自動再接続する
```

## コマンド実行

- `AsyncCommands` トレイトを import して高レベル API を使う
- 型パラメータで戻り値の型を指定する
- 存在しないキーの取得には `Option<T>` を使う

```rust
use redis::AsyncCommands;

// SET / GET
let _: () = conn.set("key", "value").await?;
let val: String = conn.get("key").await?;

// Option で存在チェック
let maybe: Option<String> = conn.get("maybe_missing").await?;

// 有効期限付き SET
let _: () = conn.set_ex("session:abc", session_data, 3600).await?;

// ハッシュ操作
let _: () = conn.hset("user:1", "name", "Alice").await?;
let name: String = conn.hget("user:1", "name").await?;

// DEL
let _: () = conn.del("key").await?;
```

## パイプライン

- 複数コマンドを一度に送信してネットワークラウンドトリップを削減する
- バッチ処理やキャッシュのウォームアップに使う

```rust
let (k1, k2): (i32, i32) = redis::pipe()
    .set("key_1", 42).ignore()
    .set("key_2", 43).ignore()
    .get("key_1")
    .get("key_2")
    .query_async(&mut conn)
    .await?;
```

## キー設計

- プレフィックスとコロン区切りで名前空間を作る: `{entity}:{id}:{attribute}`
- 例: `user:123:profile`, `session:abc123`, `cache:posts:page:1`
- キー名は短く、しかし読みやすく
- TTL (有効期限) を必ず設定する。期限なしキーはメモリリークの原因になる

## キャッシュパターン

- Cache-Aside パターンを基本とする
- キャッシュミス時にDBから取得してキャッシュに書き込む
- 更新時はキャッシュを削除する (更新ではなく削除が安全)

```rust
async fn get_user_cached(
    conn: &mut impl AsyncCommands,
    db: &mut AsyncPgConnection,
    user_id: i64,
) -> Result<User, AppError> {
    let cache_key = format!("user:{user_id}");

    // キャッシュ確認
    if let Some(cached) = conn.get::<_, Option<String>>(&cache_key).await? {
        return Ok(serde_json::from_str(&cached)?);
    }

    // DB から取得
    let user = users::table
        .find(user_id)
        .select(User::as_select())
        .first(db)
        .await?;

    // キャッシュに保存 (TTL 付き)
    let serialized = serde_json::to_string(&user)?;
    let _: () = conn.set_ex(&cache_key, &serialized, 300).await?;

    Ok(user)
}

async fn update_user(/* ... */) -> Result<User, AppError> {
    // DB 更新
    let user = diesel::update(users::table.find(user_id))
        .set(&changes)
        .get_result::<User>(db)
        .await?;

    // キャッシュ削除 (更新ではなく削除)
    let _: () = conn.del(format!("user:{user_id}")).await?;

    Ok(user)
}
```

## セッション管理

- セッションデータは Valkey のハッシュ型で格納する
- セッション ID はランダム生成し、推測不可能にする
- TTL を必ず設定する (例: 24時間)

## エラーハンドリング

- `redis::RedisError` を `AppError` に変換する `From` 実装を用意する
- 接続エラー時はリトライロジックを入れる (`ConnectionManager` 使用時は自動)
- Valkey ダウン時にもアプリケーションが degraded mode で動作できるようにする

## やってはいけないこと

- `KEYS *` を本番で使わない → `SCAN` を使う
- 大きな値 (> 1MB) を単一キーに保存しない
- Lua スクリプトで長時間ブロックしない
- TTL なしでキャッシュを保存しない
- `FLUSHALL` / `FLUSHDB` を本番で使わない
