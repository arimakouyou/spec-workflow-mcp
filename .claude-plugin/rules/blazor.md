---
paths:
  - "**/*.razor"
  - "**/*.razor.cs"
globs:
  - "**/*.csproj"
---

# Blazor Best Practices

Blazor Web App または Blazor WebAssembly を使用する場合、このルールは `aspnet-core.md` を補完する。

## プロジェクト構成 (Blazor Web App)

```
src/
├── Components/
│   ├── Layout/
│   │   ├── MainLayout.razor
│   │   └── NavMenu.razor
│   ├── Pages/
│   │   ├── Home.razor
│   │   └── Counter.razor
│   └── _Imports.razor
├── Models/
├── Services/
├── Data/                    # EF Core (サーバーサイド)
├── Program.cs
├── App.razor
└── wwwroot/
```

## レンダーモード

- `InteractiveServer` — SignalR ベースのサーバーサイドレンダリング
- `InteractiveWebAssembly` — ブラウザ内 WASM
- `InteractiveAuto` — 初回はサーバー、その後 WASM に切替
- コンポーネントごとに `@rendermode` で指定、または `App.razor` でグローバルに設定

## コンポーネントパターン

- 1 ファイル 1 コンポーネント、ファイル名 = コンポーネント名
- コードビハインドパターン: `MyComponent.razor` + `MyComponent.razor.cs`
- Props には `[Parameter]`、コンテキストには `[CascadingParameter]` を使用
- 子から親への通信には `EventCallback<T>` を使用

```csharp
// MyComponent.razor.cs (コードビハインド)
public partial class MyComponent : ComponentBase
{
    [Parameter]
    public string Title { get; set; } = string.Empty;

    [Parameter]
    public EventCallback<string> OnTitleChanged { get; set; }

    [CascadingParameter]
    public ThemeInfo? Theme { get; set; }
}
```

## 状態管理

- `@bind` で双方向バインディング
- カスケーディングバリューで DI ライクな状態伝搬
- 複雑な状態には State コンテナ（Scoped サービスとして登録）を使用
- static フィールドに状態を保存しない

## サーバー関数 (Leptos の `#[server]` に相当)

- 標準の ASP.NET Core API エンドポイントを使用
- Blazor WASM からは DI で注入された `HttpClient` で呼び出す
- Blazor Server: サービスを直接注入して使用

## フォームとバリデーション

- `<EditForm>` と `Model` バインディング
- バリデーションには `DataAnnotationsValidator`
- 複雑なルールには `FluentValidation`
- `<ValidationSummary>` と `<ValidationMessage>` でエラー表示

```razor
<EditForm Model="@user" OnValidSubmit="@HandleSubmit">
    <DataAnnotationsValidator />
    <ValidationSummary />

    <InputText @bind-Value="user.Name" />
    <ValidationMessage For="@(() => user.Name)" />

    <button type="submit">送信</button>
</EditForm>
```

## ルーティング

- `@page "/path"` ディレクティブでルート定義
- ルートパラメータ: `@page "/user/{Id:int}"`
- プログラマティックナビゲーションには `NavigationManager`
- アクティブリンクスタイリングには `<NavLink>`

## WASM ビルド検証 (`cargo leptos build` に相当)

```bash
dotnet publish -c Release -p:PublishTrimmed=true
```

- `-p:PublishTrimmed=true` は **必須** — これなしではトリミング互換性の問題が検出されない
- プロジェクトの .csproj に `<PublishTrimmed>true</PublishTrimmed>` を設定済みの場合でも、明示的に指定することで CI とローカルの挙動を一致させる

追加の最適化設定（.csproj に記述）:

```xml
<PropertyGroup>
    <PublishTrimmed>true</PublishTrimmed>
    <RunAOTCompilation>true</RunAOTCompilation>
</PropertyGroup>
```

- Trim/AOT 警告 (IL2xxx, IL3xxx) を確認すること — リフレクション依存のコードが実行時に破損することを示す
- GREEN phase でテストが通過した後、必ず `dotnet publish -c Release -p:PublishTrimmed=true` を実行して WASM コンパイルを検証する

## テスト

- **ロジックテスト**: ロジックをコードビハインド `.razor.cs` ファイルに抽出し、xUnit でテスト
- **コンポーネントテスト**: bUnit でレンダリングとインタラクションをテスト
- 生の HTML 出力をテストしない — コンポーネントの振る舞いと状態をテストする
- シグナル/状態変化、イベントハンドラコールバック、バリデーションロジックをテストする

### bUnit テスト例

```csharp
[Fact]
public void Counter_IncrementButton_UpdatesCount()
{
    using var ctx = new TestContext();
    var cut = ctx.RenderComponent<Counter>();

    cut.Find("button").Click();

    cut.Find("p").MarkupMatches("<p>Current count: 1</p>");
}
```

### ユニットテスト対象

| フロントエンド関心事 | テストアプローチ |
|---|---|
| コンポーネント状態遷移 | ロジックをコードビハインドに抽出、xUnit でアサート |
| バリデーションロジック | バリデーション関数を抽出、直接テスト |
| サービスロジック | DI サービスを単体テスト、モック依存 |
| EventCallback ハンドラ | bUnit でイベント発火、状態変化をアサート |

### ユニットテスト対象外（E2E に委譲）

- Razor テンプレートの HTML 出力
- CSS クラスの動的適用
- ルーティング遷移
- SignalR 接続の振る舞い

## パフォーマンス

- リスト描画の最適化には `@key` を使用
- `<BlazorWebAssemblyLazyLoad>` でアセンブリを遅延ロード
- 長いリストには `<Virtualize>` で仮想化
- `ShouldRender()` でコンポーネントの不要な再レンダリングを最小化

```razor
<Virtualize Items="@items" Context="item">
    <ItemRow Item="@item" />
</Virtualize>
```
