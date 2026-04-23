---
name: valkv-cache
description: |
  Valkey (Redis 互換のインメモリデータストア) を Rust の redis-rs クライアントで利用するパターン集。MultiplexedConnection による多重化、ConnectionManager による自動再接続、AsyncCommands による型安全なコマンド実行、パイプライン、キー名前空間設計、Cache-Aside パターン、セッション管理、エラーハンドリング、避けるべき本番アンチパターン (KEYS *, 大きな値, TTL なし, FLUSHALL) をカバー。Valkey/Redis のキャッシュ・セッションストア実装、接続戦略、キャッシュ更新戦略の判断時に参照。
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# Valkey (Redis-compatible) + redis-rs Skill

## 対象

- Valkey あるいは Redis をキャッシュ / セッションストア / pub-sub として使う Rust コードの実装
- `redis-rs` クライアントによる接続管理（MultiplexedConnection / ConnectionManager）
- キャッシュ戦略（Cache-Aside）の設計・実装
- Key Expiration (TTL) 戦略の設計
- Valkey/Redis エラーと `AppError` との変換

## 対象外

- Redis サーバ自体の運用 / 監視 → インフラ側ドキュメント参照
- NATS JetStream → 用途が異なる（Request/Reply や永続キュー向け）
- pub-sub の詳細設計 → 本スキルはキャッシュ中心。必要なら別 Skill 新設

## 主要観点

### 1. 依存関係

```toml
[dependencies]
redis = { version = "0.27", features = ["tokio-comp", "connection-manager"] }
```

- `tokio-comp`: 非同期サポート
- `connection-manager`: 自動再接続
- クラスター利用時は `cluster-async` を追加

### 2. 接続管理

- 非同期接続は `MultiplexedConnection` を使う（Clone 可能、スレッドセーフ、接続プール不要）
- 自動再接続が必要なら `ConnectionManager`（`connection-manager` feature）
- ブロッキングコマンド（`BLPOP` / `BRPOP` など）は別の専用接続で

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

### 3. ConnectionManager による自動再接続

```rust
use redis::aio::ConnectionManager;

let client = Client::open("redis://127.0.0.1:6379/")?;
let conn = ConnectionManager::new(client).await?;
```

### 4. コマンド実行

- `AsyncCommands` トレイトを import して高レベル API を使う
- 型パラメータで戻り値型を指定
- 存在しないキーは `Option<T>` で受ける

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

### 5. パイプライン

ネットワークラウンドトリップ削減用。バッチ処理・キャッシュウォームアップで使う。

```rust
let (k1, k2): (i32, i32) = redis::pipe()
    .set("key_1", 42).ignore()
    .set("key_2", 43).ignore()
    .get("key_1")
    .get("key_2")
    .query_async(&mut conn)
    .await?;
```

### 6. キー設計

- プレフィックス + コロン区切りで名前空間: `{entity}:{id}:{attribute}`
- 例: `user:123:profile`, `session:abc123`, `cache:posts:page:1`
- キー名は短く、ただし可読性を確保
- TTL を必ず設定（期限なしキーはメモリリークの原因）

### 7. Cache-Aside パターン

- キャッシュミス時に DB 取得 → キャッシュ書き込み
- 更新時はキャッシュを**削除**（更新ではなく削除が安全）

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

### 8. セッション管理

- セッションデータはハッシュ型で格納
- セッション ID はランダム生成（推測不可能）
- TTL を必ず設定（例: 24 時間）

### 9. エラーハンドリング

- `redis::RedisError` から `AppError` への `From` 実装
- 接続エラー時はリトライ（`ConnectionManager` 使用時は自動）
- Valkey 不在時にも degraded mode で動作できる設計にする

## よくある落とし穴

1. **`KEYS *` を本番で使う**: 全キー走査はブロッキング。`SCAN` を使う
2. **大きな値を単一キーに保存**: > 1MB は避ける。分割または別ストアへ
3. **Lua スクリプトで長時間ブロック**: EVAL は単一スレッドで実行される
4. **TTL なしキャッシュ**: メモリ無制限増加につながる
5. **`FLUSHALL` / `FLUSHDB` を本番で使用**: 取り返しがつかない

## プロジェクト固有の規約

- キャッシュキーの命名: スキーマ変更時に古いキーをヒットさせないため、バージョン prefix（例: `v1:user:123`）を検討
- TTL 既定値の目安: セッション 24h、API レスポンスキャッシュ 5m、静的データキャッシュ 1h（プロジェクト側で運用標準を決める）

## 関連 Rule / Skill

- 普遍制約: `design-principles` (D4: エラーハンドリング), `security` (A5: 認証・セッション)
- 関連 Skill: `axum` (AppState に MultiplexedConnection を格納)、`diesel` (DB + キャッシュの二層構成)、`integration-test` (testcontainers で Valkey 起動)

## 参考リンク

- redis-rs docs: <https://docs.rs/redis/>
- Valkey: <https://valkey.io/>
- Redis Commands Reference: <https://redis.io/commands>
