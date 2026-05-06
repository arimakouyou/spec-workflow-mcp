---
name: leptos
description: |
  Best practices for the Leptos full-stack WASM framework (Rust). Covers target separation via the `ssr` / `hydrate` / `csr` feature flags, isolating server-only code with `#[cfg(feature = "ssr")]`, Axum integration with `leptos_axum`, the `#[component]` macro, `signal()` and derived computations (closures / Memo), state sharing with `provide_context`, `#[server]` functions, `Resource` + `Suspense`, the `ActionForm` progressively-enhanced form, `leptos_router` routing, a TDD strategy that extracts component logic into pure functions, and WASM verification via `cargo leptos build`. Reference when developing Leptos front-end / full-stack code. Takes precedence over `project-architecture.md`. Triggers on: 'Leptos', 'leptos_axum', '#[component]', 'cargo leptos build', 'ssr feature flag', 'Leptos フロントエンド', 'Leptos フルスタック開発'.
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# Leptos Best Practices

When using a Leptos full-stack configuration, this skill takes precedence over the `project-architecture` Rule.
All Diesel, Valkey, and Axum code must be wrapped in `#[cfg(feature = "ssr")]`.

## In Scope

- Creating and modifying Leptos components (`#[component]`)
- Designing reactive state with Signal / Memo
- Adding and modifying `#[server]` functions (DB connections, external API calls)
- Async data fetching with `Resource` + `Suspense` / `Transition`
- Forms using `ActionForm` / `ServerAction`
- Routing configuration with `leptos_router`
- Feature flag structure for a Leptos full-stack project

## Out of Scope

- Pure Axum API servers (no Leptos) -> `axum` Skill
- Diesel model definitions -> `diesel` Skill
- Valkey connection management -> `valkv-cache` Skill
- WASM-incompatible API use (`std::fs`, `std::net`, etc.) must be guarded with `#[cfg(feature = "ssr")]`

## Project Structure

- In a full-stack configuration, separate compilation targets using `ssr` / `hydrate` / `csr` feature flags
- Wrap server-only code (Diesel, Valkey, Axum) with `#[cfg(feature = "ssr")]`
- Use `cargo-leptos` as the build tool
- Enable the `ssr` feature in rust-analyzer settings

```toml
[lib]
crate-type = ["cdylib", "rlib"]

[features]
csr = ["leptos/csr"]
hydrate = ["leptos/hydrate"]
ssr = [
    "leptos/ssr",
    "dep:leptos_axum",
    "dep:axum",
    "dep:diesel",
    "dep:diesel-async",
    "dep:redis",
    "dep:tokio",
    "dep:tower",
    "dep:tower-http",
]
```

## Directory Structure (Full-Stack)

```
src/
├── lib.rs               # Crate root, branching by feature flag
├── app.rs               # Leptos App component (Router and Routes definitions)
├── main.rs              # Entry point (SSR/CSR branching by feature flag)
├── server/              # Everything under #[cfg(feature = "ssr")]
│   ├── mod.rs           # Axum server startup
│   ├── app_state.rs     # AppState definition (DbPool, Valkey, Config)
│   ├── db/
│   │   ├── mod.rs       # DB pool initialization
│   │   └── repository/  # Repository layer
│   ├── cache/
│   │   ├── mod.rs       # Valkey connection initialization
│   │   └── keys.rs
│   └── middleware/
│       └── auth.rs
├── pages/               # Page components (corresponding to routes)
├── components/          # Reusable UI components
├── models/              # Diesel models (cfg(feature = "ssr"))
├── dto/                 # Shared types (used by both server and client)
├── server_fns/          # #[server] functions
├── schema.rs            # Diesel auto-generated (cfg(feature = "ssr"))
└── error_template.rs    # Error display component
style/
├── main.css
migrations/
└── ...
```

## Axum Integration (SSR)

- Use `leptos_axum`'s `LeptosRoutes` trait to integrate Leptos routes into the Axum Router
- Receive server function endpoints at `/api/{*fn_name}`
- Inject the DB pool and other resources into Leptos context with `provide_context`

```rust
#[cfg(feature = "ssr")]
#[tokio::main]
async fn main() {
    let routes = generate_route_list(App);
    let state = AppState { /* db_pool, valkey, leptos_options, routes */ };

    let app = Router::new()
        .route("/api/{*fn_name}", get(server_fn_handler).post(server_fn_handler))
        .leptos_routes_with_handler(routes, get(leptos_routes_handler))
        .fallback(file_and_error_handler)
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let listener = TcpListener::bind(&addr).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
}
```

## Separation by Feature Flag

```rust
// src/lib.rs
pub mod app;
pub mod dto;
pub mod pages;
pub mod components;
pub mod server_fns;

#[cfg(feature = "ssr")]
pub mod server;

#[cfg(feature = "ssr")]
pub mod models;

#[cfg(feature = "ssr")]
pub mod schema;
```

## Components

- Define components with the `#[component]` macro. Component names must be `UpperCamelCase`
- Define props as function arguments and control optional values and defaults with the `#[prop]` attribute
- Keep components small and single-responsibility
- Place reusable components in the `components/` directory

```rust
#[component]
fn UserCard(
    /// User name
    name: String,
    /// Email address (optional)
    #[prop(optional)]
    email: Option<String>,
    /// Avatar size
    #[prop(default = 48)]
    avatar_size: u32,
    /// Click handler
    #[prop(into)]
    on_click: Callback<()>,
) -> impl IntoView {
    view! {
        <div class="user-card" on:click=move |_| on_click.run(())>
            <span>{name}</span>
            {email.map(|e| view! { <span class="email">{e}</span> })}
        </div>
    }
}
```

## Signals and the Reactive System

- Create read/write signal pairs with `signal()`
- Express derived state as closures (`move || ...`). Avoid creating unnecessary signals
- Use `Memo` for expensive derived computations (avoids recomputation when dependencies have not changed)
- Share global state with `provide_context` / `use_context`
- Use `RwSignal` when you want to combine reading and writing into a single value

```rust
let (count, set_count) = signal(0);

// Derived state: use a closure, not a signal
let is_even = move || count.get() % 2 == 0;
let double_count = move || count.get() * 2;

// Use Memo for expensive computations
let expensive = Memo::new(move |_| heavy_computation(count.get()));
```

## Conditional Rendering and List Rendering

- Use `move || if ... { ... } else { ... }` for conditional rendering. Unify different types with `.into_any()`
- Use the keyed `For` component for list rendering
- Only use `Vec<impl IntoView>` directly for static lists

```rust
// Conditional rendering
{move || if is_loading.get() {
    view! { <p>"Loading..."</p> }.into_any()
} else {
    view! { <UserList users=users.get()/> }.into_any()
}}

// List rendering
<For
    each=move || items.get()
    key=|item| item.id
    let(item)
>
    <ItemRow item=item/>
</For>
```

## Server Functions

- Define server-only functions with the `#[server]` macro
- Use `Result<T, ServerFnError>` as the return type
- Perform all DB access, authentication, and external API calls inside server functions
- Use `use_context` inside server functions to obtain the DB pool and other resources
- Define a custom error type and implement `FromServerFnError`

```rust
#[server]
pub async fn get_user(id: i64) -> Result<UserDto, ServerFnError> {
    use crate::db::repository::users;
    let pool = use_context::<DbPool>()
        .ok_or_else(|| ServerFnError::new("No DB pool"))?;
    let mut conn = pool.get().await
        .map_err(|e| ServerFnError::new(e.to_string()))?;
    let user = users::find_by_id(&mut conn, id).await
        .map_err(|e| ServerFnError::new(e.to_string()))?;
    Ok(user.into())
}
```

## Resources and Async Data

- Fetch server data with `Resource` and display loading states with `Suspense`
- Declare reactive dependencies in the first argument (source) of `Resource::new`
- Use `Transition` to reload data in the background while displaying existing content

```rust
let user_resource = Resource::new(
    move || user_id.get(),
    |id| get_user(id),
);

view! {
    <Suspense fallback=|| view! { <p>"Loading..."</p> }>
        {move || Suspend::new(async move {
            user_resource.await.map(|user| {
                view! { <UserProfile user=user/> }
            })
        })}
    </Suspense>
}
```

## Forms and Actions

- Use `ServerAction` + `ActionForm` to create progressively enhanced forms
- Forms must work even when JavaScript is disabled
- Use `action.value()` to get the latest result and `action.pending()` to get the loading state

```rust
let create_user = ServerAction::<CreateUser>::new();

view! {
    <ActionForm action=create_user>
        <input type="text" name="name" required/>
        <input type="email" name="email"/>
        <button type="submit" disabled=move || create_user.pending().get()>
            "Create"
        </button>
    </ActionForm>
}
```

## Routing

- Configure client-side routing with `leptos_router`
- Define routes with `<Routes>` + `<Route>`
- Define path parameters with `path!("/users/:id")` and retrieve them with `use_params`
- Choose an SSR mode from `ssr=SsrMode::OutOfOrder` (default), `PartiallyBlocked`, or `Async`

```rust
view! {
    <Router>
        <nav>
            <A href="/">"Home"</A>
            <A href="/users">"Users"</A>
        </nav>
        <main>
            <Routes fallback=|| view! { <p>"Not Found"</p> }>
                <Route path=path!("/") view=HomePage/>
                <Route path=path!("/users") view=UsersPage/>
                <Route path=path!("/users/:id") view=UserDetailPage/>
            </Routes>
        </main>
    </Router>
}
```

## Error Handling

- Use the `ErrorBoundary` component to catch errors from child components
- Propagate server function errors via `Result` and handle them on the UI side with `match`
- Separate user-facing error messages from detailed internal error logs

## Styling

- Toggle classes dynamically with `class:name=signal`
- Set inline styles dynamically with `style:property=signal`
- Specify CSS files via `style-file` in `[package.metadata.leptos]` in `Cargo.toml`

## Build Verification

In a Leptos full-stack project, `cargo build` and `cargo test` only compile for the **host target** (SSR). WASM frontend code is not compiled or verified by these commands. You **must** run:

```bash
cargo leptos build
```

This command builds both SSR and WASM targets. Common WASM-only compilation errors include:

- Using `std::fs`, `std::net`, or other APIs unavailable in `wasm32-unknown-unknown`
- Calling `tokio::spawn` or other runtime-specific code outside `#[cfg(feature = "ssr")]`
- Missing `#[cfg(feature = "ssr")]` guards on server-only dependencies

### TDD with Leptos

#### Test Strategy

`cargo test` only compiles for the SSR target. Leptos front-end code (components, signals, reactive logic) is testable with standard `#[test]` by **extracting** logic out of the `view!` macro.

#### Unit-Testable Concerns

| Front-end concern | Test approach |
|---|---|
| Signal state transitions | Extract state-update logic into a pure function and assert signal values |
| Derived computation / Memo | Extract the computation into a pure function and assert input/output |
| Validation logic | Extract a validate function from the component and test it directly |
| Server-function logic | Extract the core computation of `#[server]` into an async function and trait-mock its dependencies |
| Callback / handler logic | Extract the body of `on:click` / `on:submit` into a named function and test it |
| Component initial state | Test the logic that derives initial signal values from Props |

#### Out of Scope for Unit Tests (Defer to E2E)

- HTML output of the `view!` macro
- DOM event wiring (whether `on:click` actually fires)
- Dynamic CSS class application (`class:active=signal`)
- Route transitions
- Loading display of `Suspense` / `Resource`

#### Example: Extracted Component-Logic Test

```rust
/// Extract validation logic out of the component
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
    let validation = move || validate_username(&name.get());
    // ... view! { ... }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_username_rejects_empty() {
        assert!(validate_username("").is_err());
    }

    #[test]
    fn validate_username_accepts_valid() {
        assert!(validate_username("alice").is_ok());
    }

    #[test]
    fn validate_username_rejects_over_50_chars() {
        assert!(validate_username(&"a".repeat(51)).is_err());
    }
}
```

#### Post-GREEN Build Verification

After tests pass in the GREEN phase, always run `cargo leptos build` to verify WASM compilation. A WASM compile failure indicates a missing `#[cfg(feature = "ssr")]` guard.

For detailed test patterns, see TDD Skills (Rust) reference: [leptos-frontend-testing.md](../tdd-skills-rust/references/leptos-frontend-testing.md).

## Performance

- Keep signal granularity fine. Avoid wrapping large structs in a single signal
- Use `Memo` to prevent unnecessary recomputation
- Set keys correctly on the `For` component to minimize list re-rendering
- Use `Suspense` to isolate async data loading and reduce rendering blocks

## Related Rules / Skills

- Universal constraints: `rust-style`, `design-principles`, `security` (A1-A10), `type-safety` (TS-R1-R5)
- Related Skills: `axum` (Router structure for SSR), `diesel` (DB access for SSR), `valkv-cache`, `cargo-toml`, `rust-build-cache`, `tdd-skills-rust`, `spec-impl-code`, `spec-impl-test-write`
