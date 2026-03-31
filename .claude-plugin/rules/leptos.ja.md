---
paths:
  - "**/*.rs"
globs:
  - "**/Cargo.toml"
---

# Leptos ベストプラクティス

Leptos フルスタック構成を使用する場合、このルールは `project-architecture.md` より優先される。
すべての Diesel、Valkey、Axum コードは `#[cfg(feature = "ssr")]` でラップしなければならない。

## プロジェクト構成

- フルスタック構成では、`ssr` / `hydrate` / `csr` フィーチャーフラグでコンパイルターゲットを分離する
- サーバー専用コード（Diesel、Valkey、Axum）は `#[cfg(feature = "ssr")]` でラップする
- ビルドツールとして `cargo-leptos` を使用する
- rust-analyzer の設定で `ssr` フィーチャーを有効にする

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

## ディレクトリ構成（フルスタック）

```
src/
├── lib.rs               # クレートルート、フィーチャーフラグによる分岐
├── app.rs               # Leptos App コンポーネント（Router と Routes の定義）
├── main.rs              # エントリポイント（SSR/CSR のフィーチャーフラグによる分岐）
├── server/              # すべて #[cfg(feature = "ssr")] 配下
│   ├── mod.rs           # Axum サーバー起動
│   ├── app_state.rs     # AppState 定義（DbPool、Valkey、Config）
│   ├── db/
│   │   ├── mod.rs       # DB プール初期化
│   │   └── repository/  # リポジトリレイヤー
│   ├── cache/
│   │   ├── mod.rs       # Valkey 接続初期化
│   │   └── keys.rs
│   └── middleware/
│       └── auth.rs
├── pages/               # ページコンポーネント（ルートに対応）
├── components/          # 再利用可能な UI コンポーネント
├── models/              # Diesel モデル（cfg(feature = "ssr")）
├── dto/                 # 共有型（サーバーとクライアント両方で使用）
├── server_fns/          # #[server] 関数
├── schema.rs            # Diesel 自動生成（cfg(feature = "ssr")）
└── error_template.rs    # エラー表示コンポーネント
style/
├── main.css
migrations/
└── ...
```

## Axum 統合（SSR）

- `leptos_axum` の `LeptosRoutes` トレイトを使用して Leptos ルートを Axum Router に統合する
- サーバー関数エンドポイントは `/api/{*fn_name}` で受け取る
- `provide_context` で DB プールなどのリソースを Leptos コンテキストに注入する

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

## フィーチャーフラグによる分離

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

## コンポーネント

- `#[component]` マクロでコンポーネントを定義する。コンポーネント名は `UpperCamelCase` にする
- Props は関数引数として定義し、`#[prop]` 属性でオプション値やデフォルト値を制御する
- コンポーネントは小さく、単一責務に保つ
- 再利用可能なコンポーネントは `components/` ディレクトリに配置する

```rust
#[component]
fn UserCard(
    /// ユーザー名
    name: String,
    /// メールアドレス（オプション）
    #[prop(optional)]
    email: Option<String>,
    /// アバターサイズ
    #[prop(default = 48)]
    avatar_size: u32,
    /// クリックハンドラ
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

## シグナルとリアクティブシステム

- `signal()` で読み取り/書き込みのシグナルペアを作成する
- 派生状態はクロージャ（`move || ...`）で表現する。不必要なシグナルを作成しない
- 高コストな派生計算には `Memo` を使用する（依存関係が変化していない場合の再計算を回避）
- `provide_context` / `use_context` でグローバル状態を共有する
- 読み取りと書き込みを単一の値にまとめたい場合は `RwSignal` を使用する

```rust
let (count, set_count) = signal(0);

// 派生状態: シグナルではなくクロージャを使用
let is_even = move || count.get() % 2 == 0;
let double_count = move || count.get() * 2;

// 高コストな計算には Memo を使用
let expensive = Memo::new(move |_| heavy_computation(count.get()));
```

## 条件付きレンダリングとリストレンダリング

- 条件付きレンダリングには `move || if ... { ... } else { ... }` を使用する。異なる型は `.into_any()` で統一する
- リストレンダリングにはキー付きの `For` コンポーネントを使用する
- 静的なリストにのみ `Vec<impl IntoView>` を直接使用する

```rust
// 条件付きレンダリング
{move || if is_loading.get() {
    view! { <p>"Loading..."</p> }.into_any()
} else {
    view! { <UserList users=users.get()/> }.into_any()
}}

// リストレンダリング
<For
    each=move || items.get()
    key=|item| item.id
    let(item)
>
    <ItemRow item=item/>
</For>
```

## サーバー関数

- `#[server]` マクロでサーバー専用関数を定義する
- 戻り値の型として `Result<T, ServerFnError>` を使用する
- すべての DB アクセス、認証、外部 API 呼び出しはサーバー関数内で行う
- サーバー関数内では `use_context` で DB プールなどのリソースを取得する
- カスタムエラー型を定義し、`FromServerFnError` を実装する

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

## リソースと非同期データ

- `Resource` でサーバーデータを取得し、`Suspense` でローディング状態を表示する
- `Resource::new` の第1引数（ソース）でリアクティブな依存関係を宣言する
- `Transition` を使用して既存コンテンツを表示しながらバックグラウンドでデータを再読み込みする

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

## フォームとアクション

- `ServerAction` + `ActionForm` を使用してプログレッシブエンハンスメント対応のフォームを作成する
- JavaScript が無効でもフォームが動作するようにする
- `action.value()` で最新の結果を、`action.pending()` でローディング状態を取得する

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

## ルーティング

- `leptos_router` でクライアントサイドルーティングを設定する
- `<Routes>` + `<Route>` でルートを定義する
- `path!("/users/:id")` でパスパラメータを定義し、`use_params` で取得する
- SSR モードは `ssr=SsrMode::OutOfOrder`（デフォルト）、`PartiallyBlocked`、`Async` から選択する

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

## エラーハンドリング

- `ErrorBoundary` コンポーネントを使用して子コンポーネントのエラーをキャッチする
- サーバー関数のエラーは `Result` で伝播し、UI 側で `match` で処理する
- ユーザー向けエラーメッセージと内部の詳細エラーログを分離する

## スタイリング

- `class:name=signal` でクラスを動的に切り替える
- `style:property=signal` でインラインスタイルを動的に設定する
- `Cargo.toml` の `[package.metadata.leptos]` で `style-file` を指定して CSS ファイルを読み込む

## ビルド検証

Leptos フルスタックプロジェクトでは、`cargo build` と `cargo test` は**ホストターゲット**（SSR）のみをコンパイルする。WASM フロントエンドコードはこれらのコマンドではコンパイル・検証されない。必ず以下を実行すること:

```bash
cargo leptos build
```

このコマンドは SSR と WASM の両方のターゲットをビルドする。一般的な WASM 専用のコンパイルエラーには以下がある:
- `wasm32-unknown-unknown` で利用できない `std::fs`、`std::net` などの API の使用
- `#[cfg(feature = "ssr")]` の外での `tokio::spawn` やその他のランタイム固有コードの呼び出し
- サーバー専用依存関係への `#[cfg(feature = "ssr")]` ガードの欠落

### Leptos での TDD

- `cargo test` は SSR ターゲットのテストのみを実行する。サーバー関数やリポジトリロジックにはこれで十分
- コンポーネントのレンダリングテストは `#[cfg(test)]` ブロック内で `leptos::mount_to` を使用する
- TDD の Green フェーズ後、Refactor に進む前に必ず `cargo leptos build` を実行して WASM コンパイルを検証する
- Green 後の WASM コンパイル失敗は、`#[cfg(feature = "ssr")]` ガードが不足していることを示すシグナル

## パフォーマンス

- シグナルの粒度を細かく保つ。大きな構造体を単一のシグナルでラップしない
- `Memo` を使用して不要な再計算を防ぐ
- `For` コンポーネントにキーを正しく設定してリストの再レンダリングを最小化する
- `Suspense` を使用して非同期データ読み込みを分離し、レンダリングのブロッキングを軽減する
