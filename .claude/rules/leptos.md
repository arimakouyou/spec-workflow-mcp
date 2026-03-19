---
paths:
  - "**/*.rs"
globs:
  - "**/Cargo.toml"
---

# Leptos Best Practices

Leptos フルスタック構成を使用する場合、このルールが `project-architecture.md` より優先される。
Diesel, Valkey, Axum のコードはすべて `#[cfg(feature = "ssr")]` で囲む。

## プロジェクト構成

- フルスタック構成では `ssr` / `hydrate` / `csr` の feature flag でコンパイル対象を分離する
- サーバー専用コード (Diesel, Valkey, Axum) は `#[cfg(feature = "ssr")]` で囲む
- `cargo-leptos` をビルドツールとして使用する
- rust-analyzer の設定で `ssr` feature を有効化する

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

## ディレクトリ構成 (フルスタック)

```
src/
├── lib.rs               # クレートルート、feature flag で分岐
├── app.rs               # Leptos App コンポーネント (Router, Routes 定義)
├── main.rs              # エントリポイント (feature flag で SSR/CSR 分岐)
├── server/              # #[cfg(feature = "ssr")] 以下すべて
│   ├── mod.rs           # Axum サーバ起動
│   ├── app_state.rs     # AppState 定義 (DbPool, Valkey, Config)
│   ├── db/
│   │   ├── mod.rs       # DB プール初期化
│   │   └── repository/  # リポジトリ層
│   ├── cache/
│   │   ├── mod.rs       # Valkey 接続初期化
│   │   └── keys.rs
│   └── middleware/
│       └── auth.rs
├── pages/               # ページコンポーネント (ルートに対応)
├── components/          # 再利用可能な UI コンポーネント
├── models/              # Diesel モデル (cfg(feature = "ssr"))
├── dto/                 # 共有型 (server/client 両方で使用)
├── server_fns/          # #[server] 関数
├── schema.rs            # Diesel 自動生成 (cfg(feature = "ssr"))
└── error_template.rs    # エラー表示コンポーネント
style/
├── main.css
migrations/
└── ...
```

## Axum 連携 (SSR)

- `leptos_axum` の `LeptosRoutes` trait で Leptos ルートを Axum Router に統合する
- server function のエンドポイントは `/api/{*fn_name}` で受ける
- `provide_context` で DB プール等を Leptos のコンテキストに注入する

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

## feature flag による分離

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

- `#[component]` マクロで定義する。コンポーネント名は `UpperCamelCase`
- props は関数引数として定義し、`#[prop]` アトリビュートでオプション・デフォルト値を制御する
- コンポーネントは小さく、単一責任に保つ
- 再利用可能なコンポーネントは `components/` ディレクトリにまとめる

```rust
#[component]
fn UserCard(
    /// ユーザー名
    name: String,
    /// メールアドレス (省略可)
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

- `signal()` で読み取り/書き込みシグナルのペアを作成する
- 派生状態はクロージャ (`move || ...`) で表現する。不要な `signal` を増やさない
- 高コストな派生計算には `Memo` を使う (依存値が変わらなければ再計算しない)
- グローバル状態は `provide_context` / `use_context` で共有する
- `RwSignal` は読み書きを1つにまとめたい場合に使う

```rust
let (count, set_count) = signal(0);

// 派生状態: signal ではなくクロージャで
let is_even = move || count.get() % 2 == 0;
let double_count = move || count.get() * 2;

// 高コストな計算は Memo で
let expensive = Memo::new(move |_| heavy_computation(count.get()));
```

## 条件分岐とリスト描画

- 条件分岐は `move || if ... { ... } else { ... }` で。異なる型は `.into_any()` で統一する
- リスト描画はキー付きの `For` コンポーネントを使う
- 静的リストのみ `Vec<impl IntoView>` を直接使う

```rust
// 条件分岐
{move || if is_loading.get() {
    view! { <p>"Loading..."</p> }.into_any()
} else {
    view! { <UserList users=users.get()/> }.into_any()
}}

// リスト描画
<For
    each=move || items.get()
    key=|item| item.id
    let(item)
>
    <ItemRow item=item/>
</For>
```

## Server Functions

- `#[server]` マクロでサーバー専用関数を定義する
- 戻り値は `Result<T, ServerFnError>` とする
- DB アクセス、認証、外部 API 呼び出しなどはすべて server function で行う
- server function 内で `use_context` を使い DB プールなどを取得する
- カスタムエラー型を定義して `FromServerFnError` を実装する

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
- `Resource::new` の第1引数 (source) でリアクティブな依存を宣言する
- `Transition` は既存コンテンツを表示しながらバックグラウンドでリロードする

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

- `ServerAction` + `ActionForm` でプログレッシブエンハンスメント対応のフォームを作る
- JS が無効でもフォームは動作する
- `action.value()` で最新の結果を取得、`action.pending()` でローディング状態を取得する

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
- `<Routes>` + `<Route>` でルート定義する
- パスパラメータは `path!("/users/:id")` で定義し、`use_params` で取得する
- SSR モードは `ssr=SsrMode::OutOfOrder` (デフォルト)、`PartiallyBlocked`、`Async` から選択する

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

- `ErrorBoundary` コンポーネントで子コンポーネントのエラーをキャッチする
- server function のエラーは `Result` で伝播し、UI 側で `match` する
- ユーザー向けエラーメッセージとログ用の詳細エラーを分離する

## スタイリング

- `class:name=signal` でクラスの動的な切り替えを行う
- `style:property=signal` でインラインスタイルを動的に設定する
- CSS ファイルは `Cargo.toml` の `[package.metadata.leptos]` で `style-file` を指定する

## パフォーマンス

- シグナルの粒度を細かくする。大きな構造体を丸ごとシグナルにしない
- `Memo` で不要な再計算を防ぐ
- `For` コンポーネントで key を正しく設定してリスト再描画を最小化する
- `Suspense` で非同期データの読み込みを分離し、描画ブロックを減らす
