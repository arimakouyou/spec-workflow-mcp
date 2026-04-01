# Leptos フロントエンドテストパターン

Leptos フルスタックプロジェクトにおけるフロントエンドコンポーネント（シグナル、view!、サーバー関数）のユニットテスト戦略とパターン。

## テスト戦略: ロジック抽出

`view!` マクロの出力（HTML 構造、DOM イベント配線、CSS クラス）はユニットテストの対象としない。代わりに、コンポーネントからビジネスロジックを独立関数に**抽出**し、標準の `#[test]` でテストする。

```
コンポーネント
├── view! マクロ（レンダリング）   → E2E テスト（Playwright）
└── ビジネスロジック（抽出対象）   → ユニットテスト（cargo test）
    ├── シグナル状態遷移
    ├── バリデーション
    ├── 派生計算
    ├── サーバー関数コアロジック
    └── イベントハンドラロジック
```

> **Note**: `cargo test` は SSR ターゲットでのみコンパイルする。GREEN 後に `cargo leptos build` で WASM コンパイルを検証すること。

---

## 1. シグナル・リアクティブロジックのテスト

シグナルの作成・更新・派生値は `#[test]` で直接テスト可能。

### 基本: シグナルの状態遷移

```rust
use leptos::prelude::*;

/// カウンターのインクリメントロジック
pub fn increment_count(current: i32, step: i32) -> i32 {
    current + step
}

/// カウンターが偶数かどうか
pub fn is_even(value: i32) -> bool {
    value % 2 == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn increment_count_adds_step_to_current() {
        // Given
        let current = 5;
        let step = 3;

        // When
        let result = increment_count(current, step);

        // Then
        assert_eq!(result, 8);
    }

    #[test]
    fn is_even_returns_true_when_even() {
        assert!(is_even(0));
        assert!(is_even(4));
        assert!(is_even(-2));
    }

    #[test]
    fn is_even_returns_false_when_odd() {
        assert!(!is_even(1));
        assert!(!is_even(-3));
    }
}
```

### 派生計算（Memo 相当ロジック）

Memo のロジックは純粋関数として抽出しテストする。

```rust
/// 価格計算ロジック（コンポーネント内の Memo から抽出）
pub fn calculate_total(items: &[CartItem]) -> u64 {
    items.iter().map(|item| item.price * item.quantity as u64).sum()
}

pub fn format_price(yen: u64) -> String {
    format!("¥{}", yen.to_formatted_string(&Locale::ja))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn calculate_total_returns_zero_for_empty_cart() {
        assert_eq!(calculate_total(&[]), 0);
    }

    #[test]
    fn calculate_total_sums_price_times_quantity() {
        let items = vec![
            CartItem { price: 100, quantity: 2 },
            CartItem { price: 500, quantity: 1 },
        ];
        assert_eq!(calculate_total(&items), 700);
    }

    #[test]
    fn calculate_total_with_single_item() {
        let items = vec![CartItem { price: 1000, quantity: 3 }];
        assert_eq!(calculate_total(&items), 3000);
    }
}
```

---

## 2. コンポーネントロジック抽出パターン

`#[component]` 関数から、テスト可能なロジックを独立関数に抽出する。

### 抽出前（テスト困難）

```rust
#[component]
fn CreateUserForm() -> impl IntoView {
    let (name, set_name) = signal(String::new());
    let (error, set_error) = signal(None::<String>);

    // ロジックがクロージャ内に埋め込まれている → テスト困難
    let on_submit = move |_| {
        let n = name.get();
        if n.is_empty() {
            set_error.set(Some("名前は必須です".into()));
        } else if n.len() > 50 {
            set_error.set(Some("名前は50文字以内です".into()));
        } else {
            set_error.set(None);
            // submit...
        }
    };

    view! { /* ... */ }
}
```

### 抽出後（テスト可能）

```rust
/// バリデーションロジックを独立関数に抽出
pub fn validate_username(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("名前は必須です".into());
    }
    if name.chars().count() > 50 {
        return Err("名前は50文字以内です".into());
    }
    Ok(())
}

#[component]
fn CreateUserForm() -> impl IntoView {
    let (name, set_name) = signal(String::new());
    let (error, set_error) = signal(None::<String>);

    let on_submit = move |_| {
        match validate_username(&name.get()) {
            Ok(()) => { set_error.set(None); /* submit */ }
            Err(msg) => set_error.set(Some(msg)),
        }
    };

    view! { /* ... */ }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Happy Path
    #[test]
    fn validate_username_accepts_valid_name() {
        assert!(validate_username("alice").is_ok());
    }

    #[test]
    fn validate_username_accepts_single_char() {
        assert!(validate_username("a").is_ok());
    }

    #[test]
    fn validate_username_accepts_max_length() {
        let name = "a".repeat(50);
        assert!(validate_username(&name).is_ok());
    }

    // Boundary Values
    #[test]
    fn validate_username_rejects_51_chars() {
        let name = "a".repeat(51);
        assert!(validate_username(&name).is_err());
    }

    // Error Handling
    #[test]
    fn validate_username_rejects_empty() {
        let result = validate_username("");
        assert_eq!(result.unwrap_err(), "名前は必須です");
    }

    // Edge Cases
    #[test]
    fn validate_username_handles_multibyte() {
        assert!(validate_username("日本太郎").is_ok());
    }

    #[test]
    fn validate_username_accepts_50_multibyte_chars() {
        // 'あ' は3バイトだが chars().count() では1文字。50文字 ≦ 50 → Ok
        let name: String = std::iter::repeat('あ').take(50).collect();
        assert!(validate_username(&name).is_ok());
    }
}
```

---

## 3. サーバー関数テスト

`#[server]` 関数のコアロジックを抽出し、依存は trait 経由でモック。

### ロジック抽出パターン

```rust
/// サーバー関数のコアロジック（trait 経由で依存注入）
pub async fn get_user_logic<R: UserRepository>(
    repo: &R,
    id: i64,
) -> Result<UserDto, AppError> {
    let user = repo.find_by_id(id).await?;
    Ok(user.into())
}

/// サーバー関数本体（Leptos コンテキストから依存を取得）
#[server]
pub async fn get_user(id: i64) -> Result<UserDto, ServerFnError> {
    let pool = use_context::<DbPool>()
        .ok_or_else(|| ServerFnError::new("No DB pool"))?;
    let repo = DieselUserRepository::new(pool);
    get_user_logic(&repo, id).await
        .map_err(|e| ServerFnError::new(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockall::predicate::*;

    // mockall でリポジトリのモック生成
    mock! {
        UserRepo {}
        #[async_trait]
        impl UserRepository for UserRepo {
            async fn find_by_id(&self, id: i64) -> Result<User, AppError>;
        }
    }

    #[tokio::test]
    async fn get_user_logic_returns_dto_when_found() {
        // Given
        let mut mock = MockUserRepo::new();
        mock.expect_find_by_id()
            .with(eq(1))
            .returning(|_| Ok(User { id: 1, name: "Alice".into() }));

        // When
        let result = get_user_logic(&mock, 1).await;

        // Then
        let dto = result.unwrap();
        assert_eq!(dto.name, "Alice");
    }

    #[tokio::test]
    async fn get_user_logic_returns_error_when_not_found() {
        // Given
        let mut mock = MockUserRepo::new();
        mock.expect_find_by_id()
            .returning(|_| Err(AppError::NotFound));

        // When
        let result = get_user_logic(&mock, 999).await;

        // Then
        assert!(matches!(result, Err(AppError::NotFound)));
    }
}
```

---

## 4. Callback・イベントハンドラテスト

`on:click` や `on:submit` クロージャの本体を名前付き関数に抽出する。

```rust
/// フォーム送信ハンドラのロジック（抽出済み）
pub fn handle_form_submit(
    name: &str,
    email: &str,
) -> Result<CreateUserRequest, Vec<String>> {
    let mut errors = Vec::new();

    if name.is_empty() {
        errors.push("名前は必須です".into());
    }
    if !email.contains('@') {
        errors.push("メールアドレスの形式が不正です".into());
    }

    if errors.is_empty() {
        Ok(CreateUserRequest {
            name: name.to_string(),
            email: email.to_string(),
        })
    } else {
        Err(errors)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handle_form_submit_succeeds_with_valid_input() {
        let result = handle_form_submit("Alice", "alice@example.com");
        assert!(result.is_ok());
        let req = result.unwrap();
        assert_eq!(req.name, "Alice");
    }

    #[test]
    fn handle_form_submit_fails_with_empty_name() {
        let result = handle_form_submit("", "alice@example.com");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains(&"名前は必須です".to_string()));
    }

    #[test]
    fn handle_form_submit_fails_with_invalid_email() {
        let result = handle_form_submit("Alice", "invalid");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains(&"メールアドレスの形式が不正です".to_string()));
    }

    #[test]
    fn handle_form_submit_reports_all_errors() {
        let result = handle_form_submit("", "invalid");
        let errors = result.unwrap_err();
        assert_eq!(errors.len(), 2);
    }
}
```

---

## 5. Props と初期状態のテスト

Props から導出される初期状態ロジックをテストする。

```rust
/// ページネーションの初期状態計算
pub fn calculate_pagination(total_items: usize, items_per_page: usize) -> Pagination {
    let total_pages = if items_per_page == 0 {
        0
    } else {
        (total_items + items_per_page - 1) / items_per_page
    };

    Pagination {
        current_page: 1,
        total_pages,
        has_next: total_pages > 1,
        has_prev: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pagination_with_zero_items() {
        let p = calculate_pagination(0, 10);
        assert_eq!(p.total_pages, 0);
        assert!(!p.has_next);
    }

    #[test]
    fn pagination_with_exact_page_boundary() {
        let p = calculate_pagination(20, 10);
        assert_eq!(p.total_pages, 2);
        assert!(p.has_next);
    }

    #[test]
    fn pagination_with_partial_last_page() {
        let p = calculate_pagination(21, 10);
        assert_eq!(p.total_pages, 3);
    }

    #[test]
    fn pagination_with_items_per_page_zero() {
        let p = calculate_pagination(10, 0);
        assert_eq!(p.total_pages, 0);
    }

    #[test]
    fn pagination_with_single_item() {
        let p = calculate_pagination(1, 10);
        assert_eq!(p.total_pages, 1);
        assert!(!p.has_next);
    }
}
```

---

## 6. ユニットテストで扱わないもの

以下は E2E テスト（Playwright）で検証する。

| 対象 | 理由 |
|------|------|
| `view!` マクロの HTML 出力 | SSR/CSR でレンダリング挙動が異なる、DOM 依存 |
| DOM イベント配線（`on:click` が発火するか） | ブラウザ環境が必要 |
| CSS クラスの適用（`class:active=signal`） | DOM 依存 |
| ルーティング遷移（`<A href="...">`） | Router コンテキストが必要 |
| `Suspense` / `Resource` のローディング表示 | 非同期レンダリングフロー |
| ハイドレーション動作 | SSR → CSR 遷移はブラウザ環境必須 |

---

## 7. テストファイル配置

```
src/
├── pages/
│   └── users_page.rs        # コンポーネント + 抽出ロジック + #[cfg(test)] mod tests
├── components/
│   └── user_card.rs          # コンポーネント + #[cfg(test)] mod tests
├── server_fns/
│   └── users.rs              # #[server] 関数 + コアロジック + #[cfg(test)] mod tests
└── helpers/                  # 共有バリデーション・計算ロジック
    ├── validation.rs         # + #[cfg(test)] mod tests
    └── formatting.rs         # + #[cfg(test)] mod tests
```

原則: テストは実装と同ファイルの `#[cfg(test)] mod tests` 内に記述する。共有ロジックを `helpers/` に抽出した場合も同様。

### feature flag の考慮

- テストは `cargo test` で SSR feature 付きで実行される
- サーバー関数のテストは `#[cfg(test)]` 内に書く（`#[cfg(feature = "ssr")]` ではない）
- テスト内でサーバー専用の依存を使う場合は `#[cfg(all(test, feature = "ssr"))]` も可

---

## パターンサマリー

| テスト対象 | 抽出パターン | アサーション例 |
|-----------|-------------|---------------|
| シグナル状態遷移 | 状態更新関数を純粋関数に | `assert_eq!(increment_count(5, 3), 8)` |
| 派生計算 | Memo ロジックを純粋関数に | `assert_eq!(calculate_total(&items), 700)` |
| バリデーション | validate 関数を抽出 | `assert!(validate_username("").is_err())` |
| サーバー関数 | コアロジックを async 関数に、依存を trait 注入 | `assert_eq!(get_user_logic(&mock, 1).await?.name, "Alice")` |
| ハンドラロジック | on:click/on:submit の本体を関数に | `assert!(handle_form_submit("", "bad").is_err())` |
| Props 初期状態 | 初期化ロジックを関数に | `assert_eq!(calculate_pagination(21, 10).total_pages, 3)` |
| 表示フォーマット | format 関数を抽出 | `assert_eq!(format_price(1000), "¥1,000")` |

## 4カテゴリカバレッジ（フロントエンド適用）

| カテゴリ | フロントエンドでの適用例 |
|---------|----------------------|
| Happy Path | 有効な Props でロジックが正しく動作する |
| Boundary Values | 空文字列、最大長、0件、1件、ページ境界 |
| Error Handling | バリデーションエラー、API 失敗時の状態遷移 |
| Edge Cases | マルチバイト文字、連続呼び出し、ゼロ除算 |
