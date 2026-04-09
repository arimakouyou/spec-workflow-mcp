---
paths:
  - "**/*.cs"
  - "**/*.csproj"
---

# .NET ビルドキャッシュ

.NET プロジェクトで `dotnet` コマンドを実行する全エージェント向けのビルドキャッシュ設定ルール。
Rust の sccache とは異なり、.NET はビルトインのキャッシュメカニズムに依存する。

## MSBuild インクリメンタルビルド

MSBuild は入出力のタイムスタンプを自動的に追跡する。ローカル開発では特別な設定は不要。

- `dotnet build` は変更されたファイルのみを再コンパイルする
- インクリメンタルビルドはデフォルトで有効であり、設定不要
- `bin/` や `obj/` ディレクトリを worktree 間で共有してはならない（worktree 固有の絶対パスが含まれるため）

## NuGet パッケージキャッシュ

NuGet パッケージキャッシュは `~/.nuget/packages` で自動的に共有される。

- worktree 間での並行アクセスに安全
- CI: `actions/cache` で `~/.nuget/packages` をキャッシュする
- CI 出力をクリーンにするための環境変数:
  - `DOTNET_CLI_TELEMETRY_OPTOUT=1`
  - `DOTNET_NOLOGO=true`

## Worktree 環境でのキャッシュ戦略

| メカニズム | 推奨 | 理由 |
|-----------|------|------|
| NuGet キャッシュ (`~/.nuget/packages`) | 推奨 | worktree 間で共有、並行アクセス安全 |
| `bin/` / `obj/` 共有 | **禁止** | 絶対パスを含むため、worktree 間で共有するとビルド破損の原因になる |
| MSBuild インクリメンタルビルド | デフォルト | 自動、設定不要 |

## dotnet restore 最適化

`dotnet restore` を先に実行し、後続コマンドでは `--no-restore` フラグを使用することで不要なリストアを省略できる。

```bash
# 推奨チェーン: restore → build → test
dotnet restore
dotnet build --no-restore
dotnet test --no-build
```

## dotnet watch（ローカル開発）

`dotnet watch run` でホットリロード付きの開発サーバーを起動できる。

- ローカル開発専用 — CI では使用しない
- Blazor、Razor Pages、MVC で Hot Reload をサポート

## トラブルシューティング

### ビルドが古い状態に見える場合

```bash
dotnet clean
dotnet build
```

### NuGet リストアが失敗する場合

ローカルキャッシュをクリアして再試行:

```bash
dotnet nuget locals all --clear
dotnet restore
```
