# Test Implementation Patterns

A collection of typical patterns used in integration tests.

## File Layout Template

```
tests/
├── integration.rs           # Test binary entry point (references the modules below via mod)
├── integration/
│   ├── helpers/
│   │   ├── mod.rs          # Common helpers
│   │   ├── app.rs          # Test Axum app construction
│   │   ├── db.rs           # testcontainers DB setup
│   │   └── auth.rs         # Test authentication headers
│   ├── test_users.rs       # Test file per domain
│   └── test_posts.rs
```

## Pattern 1: List (GET /)

```rust
#[tokio::test]
async fn list_users_returns_all_users() {
    let ctx = TestContext::new().await;
    // Given: insert test data into the DB
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

## Pattern 2: Create (POST /)

```rust
#[tokio::test]
async fn create_user_returns_created() {
    let ctx = TestContext::new().await;

    // When
    let response = ctx.post("/api/users")
        .json(&json!({ "name": "Alice", "email": "alice@example.com" }))
        .await;

    // Then: verify the response
    assert_eq!(response.status(), StatusCode::CREATED);
    let body: UserResponse = response.json().await;
    assert_eq!(body.name, "Alice");

    // Then: verify the record was persisted to the DB
    let user = ctx.find_user_by_email("alice@example.com").await;
    assert!(user.is_some());
}
```

## Pattern 3: Detail (GET /:id)

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

## Pattern 4: Update (PUT /:id)

```rust
#[tokio::test]
async fn update_user_modifies_existing_record() {
    let ctx = TestContext::new().await;
    let user = ctx.seed_user(&NewUser { name: "Alice", email: "alice@example.com" }).await;

    let response = ctx.put(&format!("/api/users/{}", user.id))
        .json(&json!({ "name": "Alice Updated" }))
        .await;

    assert_eq!(response.status(), StatusCode::OK);

    // Verify the DB was also updated
    let updated = ctx.find_user_by_id(user.id).await.unwrap();
    assert_eq!(updated.name, "Alice Updated");
}
```

## Pattern 5: Delete (DELETE /:id)

```rust
#[tokio::test]
async fn delete_user_removes_record() {
    let ctx = TestContext::new().await;
    let user = ctx.seed_user(&NewUser { name: "Alice", email: "alice@example.com" }).await;

    let response = ctx.delete(&format!("/api/users/{}", user.id)).await;

    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    // Verify the record was removed from the DB
    let deleted = ctx.find_user_by_id(user.id).await;
    assert!(deleted.is_none());
}
```

## Pattern 6: parametrize (rstest)

```rust
use rstest::rstest;

const LONG_NAME: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; // 256 chars

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

## Pattern 7: Pagination

```rust
#[tokio::test]
async fn list_users_supports_pagination() {
    let ctx = TestContext::new().await;
    ctx.seed_users_count(25).await;

    // Page 1
    let response = ctx.get("/api/users?page=1&per_page=10").await;
    assert_eq!(response.status(), StatusCode::OK);
    let body: PaginatedResponse<UserResponse> = response.json().await;
    assert_eq!(body.items.len(), 10);
    assert_eq!(body.total, 25);

    // Page 3 (5 remaining items)
    let response = ctx.get("/api/users?page=3&per_page=10").await;
    let body: PaginatedResponse<UserResponse> = response.json().await;
    assert_eq!(body.items.len(), 5);
}
```

## Pattern 8: External API Failure Behavior

```rust
#[tokio::test]
async fn create_user_returns_error_when_external_api_fails() {
    let ctx = TestContext::with_failing_external_api().await;

    let response = ctx.post("/api/users")
        .json(&json!({ "name": "Alice", "email": "alice@example.com" }))
        .await;

    assert_eq!(response.status(), StatusCode::BAD_GATEWAY);

    // Verify the DB was rolled back
    let user = ctx.find_user_by_email("alice@example.com").await;
    assert!(user.is_none());
}
```

## Pattern 9: Authentication Errors

```rust
#[tokio::test]
async fn unauthenticated_request_returns_401() {
    let ctx = TestContext::new().await;

    let response = ctx.get_without_auth("/api/users").await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
```

## Common Errors and Remedies

| Error | Cause | Remedy |
|-------|-------|--------|
| `connection refused` | testcontainers container not started | Verify the Docker daemon is running |
| `table not found` | Migrations not applied | Verify TestContext runs migrations |
| Test data interferes across tests | Transaction not rolled back | Use an independent DB / transaction per test |
| `tokio runtime` error | Using `#[test]` | Switch to `#[tokio::test]` |
