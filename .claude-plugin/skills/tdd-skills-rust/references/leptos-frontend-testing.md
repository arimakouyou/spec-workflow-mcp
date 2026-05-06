# Leptos Frontend Testing Patterns

Unit testing strategies and patterns for frontend components (signals, `view!`, server functions) in a Leptos full-stack project.

## Test Strategy: Logic Extraction

The output of the `view!` macro (HTML structure, DOM event wiring, CSS classes) is not the target of unit tests. Instead, **extract** business logic from components into independent functions and test them with standard `#[test]`.

```
Component
├── view! macro (rendering)            -> E2E test (Playwright)
└── Business logic (extraction target) -> Unit test (cargo test)
    ├── Signal state transitions
    ├── Validation
    ├── Derived computation
    ├── Server function core logic
    └── Event handler logic
```

> **Note**: `cargo test` only compiles for the SSR target. After Green, verify WASM compilation with `cargo leptos build`.

---

## 1. Testing Signals and Reactive Logic

Signal creation, updates, and derived values can be tested directly with `#[test]`.

### Basics: Signal State Transitions

```rust
use leptos::prelude::*;

/// Counter increment logic
pub fn increment_count(current: i32, step: i32) -> i32 {
    current + step
}

/// Whether the counter value is even
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

### Derived Computation (Memo-equivalent Logic)

Extract Memo logic as a pure function and test it.

```rust
/// Price calculation logic (extracted from a Memo inside a component)
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

## 2. Component Logic Extraction Pattern

Extract testable logic from `#[component]` functions into independent functions.

### Before Extraction (Hard to Test)

```rust
#[component]
fn CreateUserForm() -> impl IntoView {
    let (name, set_name) = signal(String::new());
    let (error, set_error) = signal(None::<String>);

    // Logic embedded in a closure -> hard to test
    let on_submit = move |_| {
        let n = name.get();
        if n.is_empty() {
            set_error.set(Some("Name is required".into()));
        } else if n.len() > 50 {
            set_error.set(Some("Name must be 50 characters or fewer".into()));
        } else {
            set_error.set(None);
            // submit...
        }
    };

    view! { /* ... */ }
}
```

### After Extraction (Testable)

```rust
/// Validation logic extracted into an independent function
pub fn validate_username(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("Name is required".into());
    }
    if name.chars().count() > 50 {
        return Err("Name must be 50 characters or fewer".into());
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
        assert_eq!(result.unwrap_err(), "Name is required");
    }

    // Edge Cases
    #[test]
    fn validate_username_handles_multibyte() {
        assert!(validate_username("日本太郎").is_ok());
    }

    #[test]
    fn validate_username_accepts_50_multibyte_chars() {
        // 'あ' is 3 bytes but counts as 1 character via chars().count(). 50 chars <= 50 -> Ok
        let name: String = std::iter::repeat('あ').take(50).collect();
        assert!(validate_username(&name).is_ok());
    }
}
```

---

## 3. Server Function Tests

Extract the core logic of `#[server]` functions and mock dependencies via traits.

### Logic Extraction Pattern

```rust
/// Server function core logic (dependencies injected via trait)
pub async fn get_user_logic<R: UserRepository>(
    repo: &R,
    id: i64,
) -> Result<UserDto, AppError> {
    let user = repo.find_by_id(id).await?;
    Ok(user.into())
}

/// Server function entry point (resolves dependencies from the Leptos context)
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

    // Generate a repository mock with mockall
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

## 4. Callback / Event Handler Tests

Extract the body of `on:click` and `on:submit` closures into named functions.

```rust
/// Form submission handler logic (extracted)
pub fn handle_form_submit(
    name: &str,
    email: &str,
) -> Result<CreateUserRequest, Vec<String>> {
    let mut errors = Vec::new();

    if name.is_empty() {
        errors.push("Name is required".into());
    }
    if !email.contains('@') {
        errors.push("Email address format is invalid".into());
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
        assert!(result.unwrap_err().contains(&"Name is required".to_string()));
    }

    #[test]
    fn handle_form_submit_fails_with_invalid_email() {
        let result = handle_form_submit("Alice", "invalid");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains(&"Email address format is invalid".to_string()));
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

## 5. Testing Props and Initial State

Test logic that derives initial state from Props.

```rust
/// Pagination initial-state calculation
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

## 6. UT vs CT vs E2E Coverage (Revised in H, dapper-hardening)

> The POC `wasm-bindgen-test-leptos-poc.md` confirmed that the **CT (Component Test) layer is practical** (3 tests PASS in 5 seconds). `view!` / event wiring / Suspense / Resource are now **verified at the CT layer** (the previous spec's "everything is E2E's responsibility" was revised in H-3).

### UT (pure logic, millisecond scale, zero external dependencies)

- Extracted pure functions (state-update logic, derived computation, validation, server fn core)
- Run with `cargo test`
- Details: sections 1-5 of this document

### CT (Component Test, wasm-bindgen-test, seconds)

With `wasm-bindgen-test` + `cargo test --target wasm32-unknown-unknown`, mount the real component, manipulate signals, and observe the DOM:

```rust
#[wasm_bindgen_test]
async fn click_increment_updates_dom() {
    let wrapper = fresh_wrapper();
    let _dispose = mount_to(
        wrapper.clone().unchecked_into(),
        || view! { <SimpleCounter initial_value=0 /> },
    );

    let inc_button = wrapper
        .query_selector("[data-testid='btn-inc']")
        .unwrap().unwrap()
        .unchecked_into::<web_sys::HtmlElement>();
    inc_button.click();
    tick().await; // wait for the reactive update with gloo-timers

    let value_span = wrapper
        .query_selector("[data-testid='counter-value']")
        .unwrap().unwrap();
    assert_eq!(value_span.text_content().unwrap(), "1");
}
```

**What CT can cover**:

| Target | Verifiable via CT |
|--------|-------------------|
| `view!` DOM output (initial render) | Yes - query_selector + text_content |
| DOM event wiring (`on:click`, etc.) | Yes - trigger via HtmlElement::click(), observe update with tick().await |
| Signal-driven DOM updates | Yes - verify the DOM after tick().await |
| `Suspense` / `Resource` (via mock) | Yes - via the mock declared in design.md K-3 (mockito, etc.) |
| DOM reflection of derived computation | Yes - verify that values via Memo / derive appear in the DOM |

**Minimum setup** (established in the POC):

```toml
# Cargo.toml
[target.'cfg(target_arch = "wasm32")'.dev-dependencies]
wasm-bindgen-test = "0.3"
gloo-timers = { version = "0.3", features = ["futures"] }
```

```toml
# .cargo/config.toml
[target.wasm32-unknown-unknown]
runner = "wasm-bindgen-test-runner"
```

Run: `cargo test --target wasm32-unknown-unknown`

CI: Firefox + geckodriver (snap or apt), or Chromium + chromedriver

### E2E (Playwright, user journey only)

- User journeys that chain multiple features (composite cases that cannot be reduced to CT / ST)
- Hydration behavior (SSR -> CSR transition)
- Routing transitions (navigation verification of `<A href="...">`)

### Changes from the Previous Spec (dapper-hardening H-3)

The following items, formerly listed in `frontend-test-engineer.md` L104-112 "Out of unit-test scope" as **entirely E2E's responsibility**, have been moved to CT's responsibility:

| Target | Old | New |
|--------|-----|-----|
| `view!` DOM output | E2E | CT verifies via query_selector / inner_html |
| DOM event wiring (`on:click`) | E2E | CT triggers via HtmlElement::click() |
| `Suspense` / `Resource` display switching | E2E | CT observes via mock + tick().await |
| CSS class application (`class:active=signal`) | E2E | CT can verify via classList (when needed) |

**What remains in E2E**:
- Hydration behavior (SSR -> CSR)
- Routing transitions (across multiple pages)
- Chaining of multiple features (user journey)

---

## 7. Test File Layout

```
src/
├── pages/
│   └── users_page.rs        # component + extracted logic + #[cfg(test)] mod tests
├── components/
│   └── user_card.rs          # component + #[cfg(test)] mod tests
├── server_fns/
│   └── users.rs              # #[server] function + core logic + #[cfg(test)] mod tests
└── helpers/                  # shared validation / computation logic
    ├── validation.rs         # + #[cfg(test)] mod tests
    └── formatting.rs         # + #[cfg(test)] mod tests
```

Principle: write tests inside `#[cfg(test)] mod tests` in the same file as the implementation. The same applies when shared logic is extracted into `helpers/`.

### Feature Flag Considerations

- Tests run via `cargo test` with the SSR feature enabled
- Write server-function tests inside `#[cfg(test)]` (not `#[cfg(feature = "ssr")]`)
- When tests use server-only dependencies, `#[cfg(all(test, feature = "ssr"))]` is also acceptable

---

## Pattern Summary

| Test Target | Extraction Pattern | Assertion Example |
|-------------|--------------------|-------------------|
| Signal state transitions | Make state-update functions pure | `assert_eq!(increment_count(5, 3), 8)` |
| Derived computation | Make Memo logic pure | `assert_eq!(calculate_total(&items), 700)` |
| Validation | Extract a validate function | `assert!(validate_username("").is_err())` |
| Server functions | Make core logic an async function with traits injected | `assert_eq!(get_user_logic(&mock, 1).await?.name, "Alice")` |
| Handler logic | Extract on:click/on:submit bodies into functions | `assert!(handle_form_submit("", "bad").is_err())` |
| Props initial state | Extract initialization logic into a function | `assert_eq!(calculate_pagination(21, 10).total_pages, 3)` |
| Display formatting | Extract a format function | `assert_eq!(format_price(1000), "¥1,000")` |

## Four-Category Coverage (Frontend Application)

| Category | Frontend Application Examples |
|----------|-------------------------------|
| Happy Path | Logic works correctly with valid Props |
| Boundary Values | Empty string, max length, 0 items, 1 item, page boundary |
| Error Handling | Validation errors, state transitions on API failure |
| Edge Cases | Multibyte characters, repeated calls, division by zero |
