# テスト実装パターン

インテグレーションテストで使う典型的なパターン集。

## ファイル構成テンプレート

```
tests/
├── integration.rs           # テストバイナリエントリポイント（mod で下記を参照）
├── integration/
│   ├── helpers/
│   │   ├── mod.rs          # 共通ヘルパー
│   │   ├── app.rs          # テスト用 Axum app 構築
│   │   ├── db.rs           # testcontainers DB セットアップ
│   │   └── auth.rs         # テスト用認証ヘッダー
│   ├── test_users.rs       # ドメインごとのテストファイル
│   └── test_posts.rs
```

## パターン1: リスト取得 (GET /)

```rust
#[tokio::test]
async fn list_users_returns_all_users() {
    let ctx = TestContext::new().await;
    // Given: DB にテストデータを投入
    ctx.seed_users(&[
        NewUser { name: "Alice", email: "alice@example.com" },
        NewUser { name: "Bob", email: "bob@example.com" },
    ]).await;

    // When: GET /api/users
    let response = ctx.get("/api/users").await;

    // Then
    assert_eq!(response.status(), StatusCode::OK);
    let body: Vec<UserResponse> = response.json().await;
    assert_eq!(body.len(), 2);
}
```

## パターン2: 作成 (POST /)

```rust
#[tokio::test]
async fn create_user_returns_created() {
    let ctx = TestContext::new().await;

    // When
    let response = ctx.post("/api/users")
        .json(&json!({ "name": "Alice", "email": "alice@example.com" }))
        .await;

    // Then: レスポンス検証
    assert_eq!(response.status(), StatusCode::CREATED);
    let body: UserResponse = response.json().await;
    assert_eq!(body.name, "Alice");

    // Then: DB にも保存されたことを検証
    let user = ctx.find_user_by_email("alice@example.com").await;
    assert!(user.is_some());
}
```

## パターン3: 詳細取得 (GET /:id)

```rust
#[tokio::test]
async fn get_user_returns_user_when_exists() {
    let ctx = TestContext::new().await;
    let user = ctx.seed_user(&NewUser { name: "Alice", email: "alice@example.com" }).await;

    let response = ctx.get(&format!("/api/users/{}", user.id)).await;

    assert_eq!(response.status(), StatusCode::OK);
    let body: UserResponse = response.json().await;
    assert_eq!(body.id, user.id);
}

#[tokio::test]
async fn get_user_returns_not_found_when_missing() {
    let ctx = TestContext::new().await;

    let response = ctx.get("/api/users/99999").await;

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}
```

## パターン4: 更新 (PUT /:id)

```rust
#[tokio::test]
async fn update_user_modifies_existing_record() {
    let ctx = TestContext::new().await;
    let user = ctx.seed_user(&NewUser { name: "Alice", email: "alice@example.com" }).await;

    let response = ctx.put(&format!("/api/users/{}", user.id))
        .json(&json!({ "name": "Alice Updated" }))
        .await;

    assert_eq!(response.status(), StatusCode::OK);

    // DB も更新されたことを検証
    let updated = ctx.find_user_by_id(user.id).await.unwrap();
    assert_eq!(updated.name, "Alice Updated");
}
```

## パターン5: 削除 (DELETE /:id)

```rust
#[tokio::test]
async fn delete_user_removes_record() {
    let ctx = TestContext::new().await;
    let user = ctx.seed_user(&NewUser { name: "Alice", email: "alice@example.com" }).await;

    let response = ctx.delete(&format!("/api/users/{}", user.id)).await;

    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    // DB から削除されたことを検証
    let deleted = ctx.find_user_by_id(user.id).await;
    assert!(deleted.is_none());
}
```

## パターン6: parametrize (rstest)

```rust
use rstest::rstest;

const LONG_NAME: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; // 256文字

#[rstest]
#[case("", StatusCode::BAD_REQUEST)]
#[case(LONG_NAME, StatusCode::BAD_REQUEST)]
#[case("valid_name", StatusCode::CREATED)]
#[tokio::test]
async fn create_user_validates_name(
    #[case] name: &str,
    #[case] expected_status: StatusCode,
) {
    let ctx = TestContext::new().await;

    let response = ctx.post("/api/users")
        .json(&json!({ "name": name, "email": "test@example.com" }))
        .await;

    assert_eq!(response.status(), expected_status);
}
```

## パターン7: ページネーション

```rust
#[tokio::test]
async fn list_users_supports_pagination() {
    let ctx = TestContext::new().await;
    ctx.seed_users_count(25).await;

    // 1ページ目
    let response = ctx.get("/api/users?page=1&per_page=10").await;
    assert_eq!(response.status(), StatusCode::OK);
    let body: PaginatedResponse<UserResponse> = response.json().await;
    assert_eq!(body.items.len(), 10);
    assert_eq!(body.total, 25);

    // 3ページ目（残り5件）
    let response = ctx.get("/api/users?page=3&per_page=10").await;
    let body: PaginatedResponse<UserResponse> = response.json().await;
    assert_eq!(body.items.len(), 5);
}
```

## パターン8: 外部 API エラー時の挙動

```rust
#[tokio::test]
async fn create_user_returns_error_when_external_api_fails() {
    let ctx = TestContext::with_failing_external_api().await;

    let response = ctx.post("/api/users")
        .json(&json!({ "name": "Alice", "email": "alice@example.com" }))
        .await;

    assert_eq!(response.status(), StatusCode::BAD_GATEWAY);

    // DB にはロールバックされていることを検証
    let user = ctx.find_user_by_email("alice@example.com").await;
    assert!(user.is_none());
}
```

## パターン9: 認証エラー

```rust
#[tokio::test]
async fn unauthenticated_request_returns_401() {
    let ctx = TestContext::new().await;

    let response = ctx.get_without_auth("/api/users").await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
```

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `connection refused` | testcontainers コンテナ未起動 | Docker デーモンが起動しているか確認 |
| `table not found` | マイグレーション未実行 | TestContext でマイグレーション実行を確認 |
| テスト間でデータが干渉 | トランザクション未ロールバック | 各テストで独立した DB / トランザクションを使用 |
| `tokio runtime` エラー | `#[test]` を使っている | `#[tokio::test]` に変更 |
