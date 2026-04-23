---
name: dotnet-build-cache
description: |
  .NET プロジェクトで dotnet コマンドを実行する全エージェント向けのビルドキャッシュ設定。MSBuild インクリメンタルビルド (デフォルト有効・設定不要)、NuGet パッケージキャッシュ (`~/.nuget/packages` で自動共有・並行アクセス安全)、`bin/` / `obj/` 共有禁止 (worktree 間で絶対パス差分)、`dotnet restore → build --no-restore → test --no-build` 最適化チェーン、`dotnet watch` によるホットリロード、CI での `actions/cache` 対象、`dotnet clean` / `dotnet nuget locals all --clear` でのトラブルシュートをカバー。dotnet build / test / publish を走らせる直前、.NET 系 parallel-worker / integ-test-worker 起動前に参照。
allowed-tools: [Read, Bash, Grep]
---

# .NET ビルドキャッシュ

.NET プロジェクトで `dotnet` コマンドを実行する全エージェント向けのビルドキャッシュ設定ガイド。
Rust の sccache とは異なり、.NET はビルトインのキャッシュメカニズムに依存する。

## 対象

- dotnet build / test / publish を走らせる直前
- CI 環境での NuGet キャッシュ設定 (`actions/cache` の対象決定)
- worktree 内での並列 dotnet コマンド実行前の前処理
- .NET 系 `parallel-worker` / `integ-test-worker` / `wave-harness-worker` 起動前

## 対象外

- Rust のビルドキャッシュ → `rust-build-cache` Skill
- CI workflow の `actions/cache` セットアップ詳細 → `setup-ci` Skill
- エージェント並列数制御 → `resource-aware-parallelism` Skill

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

## 関連 Rule / Skill

- 普遍制約: `quality-checks` (QC12)
- 関連 Skill: `csproj`, `aspnet-core`, `entity-framework-core`, `blazor`, `setup-ci`, `resource-aware-parallelism`
- 関連 Agent: `parallel-worker`, `integ-test-worker`, `wave-harness-worker`, `review-worker`
