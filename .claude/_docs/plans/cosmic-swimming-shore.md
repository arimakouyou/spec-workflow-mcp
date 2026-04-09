# C#/.NET/ASP.NET 言語サポート追加プラン

## Context

現在このプラグインが提供するワークフローは、対象言語が実質 Rust のみ。Node.js のサポートは `quality-checks.md` と `setup-ci` に存在するが、TDD スキルやエージェントレベルでは不完全。

**目的**: 言語追加を容易にするルール構造を整備しつつ、第一弾として **C# (.NET 10) / ASP.NET Core / Blazor** をフルスタックサポートする。

**方針**:
- 既存 Rust ルール・エージェントは **一切変更しない**（並行ファイル作成）
- 共有ファイル（`quality-checks.md`、エージェント等）は **追記のみ**（既存パスは byte-identical）
- glob ベースの自動アクティベーション（`paths: ["**/*.cs", "**/*.csproj"]`）で言語ルールを自動選択
- スコープは **モダン .NET 10** に限定（.NET Framework は対象外）
- 実装は **Phase A → B → C → D の段階的**アプローチ

---

## ツール対応表（Rust → .NET）

ワークフロー上の役割と採用基準を明確化した対応表。全ルール・エージェント・スキルはこの対応に準拠する。

| Rust 側 | ワークフロー上の役割 | .NET 側 | 必須度 | 採用理由 |
|---|---|---|---|---|
| `cargo fmt` / `rustfmt` | コード整形 | `dotnet format` + `.editorconfig` | **必須** | .NET 標準。CI 同一コマンド |
| `cargo clippy` | lint / バグ予防 | .NET Analyzers (CAxxxx) + Roslynator + StyleCop.Analyzers | **必須** | clippy に最も近い組み合わせ。必要に応じて SonarAnalyzer.CSharp 追加 |
| `cargo test` | 単体/統合テスト | `dotnet test` + xUnit | **必須** | .NET 標準。xUnit に統一 |
| `cargo doc` | API コメント検証 | XML Documentation + CS1591、DocFX | **推奨** | CS1591 でコメント漏れ検知、DocFX で生成 |
| `cargo audit` | 依存脆弱性監査 | `dotnet list package --vulnerable --include-transitive` | **必須** | high/critical を fail にする運用 |
| `cargo +nightly udeps` | 未使用依存検出 | Snitch + Meziantou.Analyzer | **推奨** | 冗長参照・不要参照の検出 |
| `cargo leptos build` | SSR/WASM publish 検証 | `dotnet publish -c Release` | **条件付き必須** | Blazor Web App/WASM 成果物確認。PublishTrimmed + RunAOTCompilation 推奨 |
| `cargo clippy --target wasm32...` | WASM 互換性検証 | Trim/AOT 有効の `dotnet publish` | **条件付き推奨** | Browser/WASM 固有の破綻を早期検出 |
| `testcontainers` | DB/外部サービス付き統合テスト | Testcontainers for .NET | **必須** | 直接対応。設計思想同一 |
| `reqwest` | API 疎通/E2E | `HttpClient` + `WebApplicationFactory` | **必須** | ASP.NET Core in-process テストの定石 |
| （外部 API モック） | 外部依存スタブ | WireMock.NET | **推奨** | WebApplicationFactory とは役割が異なる |
| `diesel_cli` | マイグレーション/DB | `dotnet ef` | **必須** | EF Core 標準 |
| `sccache` | ビルド高速化 | MSBuild 増分ビルド + NuGet キャッシュ | **推奨** | .NET 標準機構で十分。CI ではキャッシュ明示設定要 |
| `cargo-mutants` | ミューテーションテスト | Stryker.NET | **推奨** | .NET デファクト。実行時間が長いので nightly 向き |
| `tests/architecture.rs` | アーキテクチャ制約テスト | NetArchTest.Rules / ArchUnitNET | **推奨** | 層依存や命名規約をテストで固定化 |
| `cargo deny` | ライセンス/依存監査 | dotnet-project-licenses + `dotnet nuget why` | **推奨** | OSS ライセンス確認・依存理由追跡 |
| `cargo bench` / `criterion` | ベンチマーク | BenchmarkDotNet | **推奨** | .NET デファクト。CI では別実行 |
| `cargo/config.toml` | プロジェクト共通設定 | `Directory.Build.props` + `.editorconfig` | **必須** | ビルド/解析/警告設定一元化 |
| `cargo watch` | 変更監視・自動再実行 | `dotnet watch` | **推奨** | ローカル開発用。CI 用ではない |

---

## Phase A: ルール基盤（新規ファイル作成 + 既存ルール追記）

### A-1. 新規ルールファイル作成

| # | ファイル | 内容 | frontmatter `paths` |
|---|---------|------|---------------------|
| 1 | `rules/csharp-style.md` | C# コーディングスタイル (CS1-CS16)。命名 (PascalCase/camelCase)、.editorconfig 連携、Roslynator/StyleCop.Analyzers 設定、ファイル構成、XML doc (CS1591)、async/await パターン、record/pattern matching イディオム | `["**/*.cs"]` |
| 2 | `rules/csproj.md` | .csproj / Directory.Build.props 規約。SDK-style 形式、PropertyGroup 順序、PackageReference 規約、Central Package Management、Analyzer パッケージ設定（Roslynator, StyleCop, Meziantou）、`<TreatWarningsAsErrors>` | `["**/*.csproj", "**/Directory.Build.props", "**/Directory.Packages.props"]` |
| 3 | `rules/aspnet-core.md` | ASP.NET Core パターン。Minimal API / Controller、DI、ミドルウェア、`IResult`/`ProblemDetails`、ルーティング、認証・認可、`IOptions<T>`、`WebApplicationFactory` テスト | `["**/*.cs"]` + `globs: ["**/*.csproj"]` |
| 4 | `rules/entity-framework-core.md` | EF Core パターン。DbContext、`dotnet ef` マイグレーション、Fluent API、リポジトリパターン、クエリ最適化 (Include, Split Query, NoTracking)、トランザクション | `["**/*.cs", "**/Migrations/**"]` + `globs: ["**/*.csproj"]` |
| 5 | `rules/dotnet-build-cache.md` | .NET ビルドキャッシュ戦略。MSBuild 増分ビルド、NuGet キャッシュ (`~/.nuget/packages`)、CI キャッシュ設定、worktree 時の bin/obj 分離、`dotnet watch` 開発体験 | `["**/*.cs", "**/*.csproj"]` |
| 6 | `rules/blazor.md` | Blazor パターン（Leptos 相当）。Blazor Web App / WASM、`.razor` コンポーネント、code-behind (`*.razor.cs`)、`@bind` / カスケーディングパラメータ、`@page` ルーティング、`RenderMode`、Trim/AOT 互換性、`dotnet publish` による WASM ビルド検証 | `["**/*.razor", "**/*.razor.cs"]` + `globs: ["**/*.csproj"]` |

### A-2. 既存ルール追記

| # | ファイル | 変更内容 |
|---|---------|---------|
| 7 | `rules/quality-checks.md` | **QC12: .NET Quality Checks** 追加 + frontmatter `paths` 拡張 + QC7 検出に `dotnet` + `dotnet-blazor` 追加 + QC9 lockfile テーブル拡張 + QC11 SAST .NET セクション追加 + Step B/C/D .NET コマンド追加 |
| 8 | `rules/type-safety.md` | **TS-C1〜TS-C5** 追加（NRT `<Nullable>enable</Nullable>`、readonly record struct、exhaustive switch、Result パターン、immutability defaults） |
| 9 | `rules/api-validation.md` | **AV-C1〜AV-C5** 追加（Data Annotations + `[ApiController]`、FluentValidation、Model binding、`[JsonConverter]` enum、`required` keyword） |
| 10 | `rules/project-architecture.md` | ASP.NET Core + EF Core + Redis アーキテクチャセクション追加。NetArchTest.Rules / ArchUnitNET によるアーキテクチャテストのガイダンス含む |
| 11 | `rules/INDEX.md` | 新規ルール追加 + 早見表に C# 行追加 |

### QC12: .NET Quality Checks（詳細）

```bash
# 検出優先度: Leptos > Rust > .NET Blazor > .NET API > Node.js > Generic
# .NET Blazor 検出: *.csproj 内に <Project Sdk="Microsoft.NET.Sdk.BlazorWebAssembly"> or Blazor パッケージ参照
# .NET API 検出: *.sln or *.csproj が存在し Cargo.toml が存在しない

# QC12.1: Format check (dotnet format + .editorconfig)
dotnet format --verify-no-changes

# QC12.2: Build + Analyzer warnings as errors
# .NET Analyzers (CAxxxx) + Roslynator + StyleCop.Analyzers が有効
dotnet build --no-restore -warnaserror

# QC12.3: Test (xUnit)
dotnet test --no-build --verbosity quiet

# QC12.3.5: Doc Comment Coverage (Advisory) — CS1591
# <DocumentationFile> + <NoWarn> から CS1591 を除外して検証
dotnet build --no-restore -p:TreatWarningsAsErrors=true 2>&1 | grep -c "CS1591" || true

# QC12.4: Dependency Analysis
## Security audit (blocking on critical/high)
dotnet list package --vulnerable --include-transitive
## Unused/redundant dependency detection (advisory)
# Snitch: 冗長な直接参照の検出
dotnet tool run snitch 2>/dev/null || true
# Meziantou.Analyzer: 未使用 using 等の検出は QC12.2 に含まれる

# QC12.5: License audit (advisory)
dotnet-project-licenses --input . 2>/dev/null || true
```

### QC12.6: Blazor ビルド検証（Blazor プロジェクトのみ）

```bash
# Leptos の cargo leptos build 相当
# PublishTrimmed + RunAOTCompilation で WASM/Trim 互換性を検証
dotnet publish -c Release -p:PublishTrimmed=true 2>&1 | head -50

# Trim/AOT 警告の検出（反射依存コードの破綻検出）
dotnet publish -c Release -p:PublishTrimmed=true -p:RunAOTCompilation=true 2>&1 | grep -E "(IL2\d{3}|IL3\d{3})" || true
```

### Full check order (.NET):

1. `dotnet restore`
2. `dotnet format --verify-no-changes`
3. `dotnet build --no-restore -warnaserror` （Analyzers: CAxxxx + Roslynator + StyleCop）
4. `dotnet test --no-build --verbosity quiet`
5. `dotnet list package --vulnerable --include-transitive` （blocking: high/critical）
6. `dotnet tool run snitch` （advisory: 冗長参照検出）
7. `dotnet publish -c Release -p:PublishTrimmed=true` （Blazor プロジェクトのみ — 条件付き必須）

### QC7 プロジェクトタイプ検出（更新後）

```bash
# 1. Leptos
if grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null; then
  echo "leptos"
# 2. Rust API
elif grep -qE '(axum|actix-web|rocket)' Cargo.toml 2>/dev/null; then
  echo "rust-api"
# 3. .NET Blazor (Leptos 相当のフルスタック)
elif find . -maxdepth 2 -name '*.csproj' -exec grep -l 'BlazorWebAssembly\|Microsoft.AspNetCore.Components.WebAssembly' {} + 2>/dev/null | head -1 | grep -q .; then
  echo "dotnet-blazor"
# 4. .NET API
elif ls *.sln 2>/dev/null | head -1 | grep -q . || find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; then
  echo "dotnet"
# 5. Node.js
elif test -f package.json; then
  echo "nodejs"
else
  echo "generic"
fi
```

---

## Phase B: TDD スキル・テストインフラ

### B-1. 新規スキル作成

| # | ディレクトリ | 内容 |
|---|------------|------|
| 12 | `skills/tdd-skills-dotnet/SKILL.md` | .NET TDD スキル本体。xUnit (`[Fact]`, `[Theory]`)、テスト命名規約、Red-Green-Refactor の C# 実装パターン。Moq/NSubstitute、FluentAssertions |
| 13 | `skills/tdd-skills-dotnet/references/green-strategies.md` | C# での Fake It / Triangulation / Obvious Implementation。`throw new NotImplementedException()` → 実装 |
| 14 | `skills/tdd-skills-dotnet/references/test-doubles.md` | NSubstitute / Moq / manual fakes / WireMock.NET の使い分け |
| 15 | `skills/tdd-skills-dotnet/references/test-design.md` | `[Theory]` + `[InlineData]` / `[MemberData]` パラメタライズドテスト |
| 16 | `skills/tdd-skills-dotnet/references/test-patterns.md` | xUnit ライフサイクル (`IAsyncLifetime`)、Collection Fixtures、`ITestOutputHelper`、BenchmarkDotNet 連携 |
| 17 | `skills/tdd-skills-dotnet/references/tdd-and-design.md` | TDD がインターフェースベース DI 設計を導く仕組み。NetArchTest.Rules によるアーキテクチャ制約テスト |
| 18 | `skills/tdd-skills-dotnet/references/advanced-techniques.md` | Testcontainers.DotNet、`WebApplicationFactory<T>` オーバーライド、Stryker.NET |
| 19 | `skills/tdd-skills-dotnet/references/blazor-testing.md` | Blazor コンポーネントテスト（Leptos frontend testing 相当）。code-behind ロジック抽出、bUnit、signal/state テスト |
| 20 | `skills/integration-test-dotnet/SKILL.md` | .NET 統合テストスキル。ASP.NET Core + EF Core + Testcontainers.DotNet + Redis + WireMock.NET。WebApplicationFactory パターン |

### B-2. 既存エージェント追記

| # | ファイル | 変更内容 |
|---|---------|---------|
| 21 | `agents/parallel-worker.md` | **言語適応型品質チェック**追加。`.NET Task Detection` + `Blazor Task Detection` ブロック。Retry Policy .NET 行追加。Completion Report に `dotnet_format`, `dotnet_build`, `dotnet_test`, `stryker` キー追加。Stryker.NET mutation testing セクション追加（`cargo-mutants` 相当、nightly 推奨） |
| 22 | `agents/review-worker.md` | .NET 品質チェックコマンド追加。カテゴリ A: `csharp-style.md` 参照。カテゴリ F: EF Core スキーマ適合 |
| 23 | `agents/code-simplifier.md` | C# 改善ポイント追加（LINQ、async/await、null-conditional、pattern matching、record 活用） |
| 24 | `agents/unit-test-engineer.md` | C#/xUnit テスト構造追加。NSubstitute/Moq パターン。Blazor code-behind テスト |

---

## Phase C: オーケストレーション・CI

### C-1. スキル修正

| # | ファイル | 変更内容 |
|---|---------|---------|
| 25 | `skills/spec-implement/SKILL.md` | **Step 0.5: 言語検出** 追加。Step 4 parallel-worker プロンプトに言語条件分岐。Step 5 UT 品質検証 .NET 分岐。Step 5.5 code-simplifier .NET テストコマンド。Phase Review (3.5.1) .NET コマンド。Step 9 Final E2E Gate .NET 対応（`dotnet run` スモークテスト含む） |
| 26 | `skills/setup-ci/SKILL.md` | `dotnet` + `dotnet-blazor` 検出追加。.NET 設定収集（.NET version from `<TargetFramework>` / `global.json`）。テンプレート選択に `ci-dotnet.yml` 追加 |

### C-2. CI テンプレート作成

| # | ファイル | 内容 |
|---|---------|------|
| 27 | `skills/setup-ci/references/ci-dotnet.yml` | GitHub Actions CI for .NET 10。`actions/setup-dotnet@v4`、restore → format → build (analyzers) → test → audit → Blazor publish (条件付き)。PR コメント統合。Stryker.NET nightly schedule |

---

## Phase D: 仕上げ

| # | ファイル | 変更内容 |
|---|---------|---------|
| 28 | `rules/security.md` | C# 固有ノート追加（EF Core パラメタライズドクエリ A1、ASP.NET Core 認証ミドルウェア A2、認可ポリシー A3、Blazor セキュリティ考慮事項） |
| 29 | `rules/INDEX.md` | 最終確認・C# 早見表完成 |

---

## ファイル一覧サマリ

### 新規作成（17 ファイル）

```
.claude-plugin/
├── rules/
│   ├── csharp-style.md               # CS1-CS16
│   ├── csproj.md                     # .csproj / Directory.Build.props 規約
│   ├── aspnet-core.md                # ASP.NET Core パターン
│   ├── entity-framework-core.md      # EF Core パターン
│   ├── dotnet-build-cache.md         # ビルドキャッシュ戦略
│   └── blazor.md                     # Blazor パターン（Leptos 相当）
├── skills/
│   ├── tdd-skills-dotnet/
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── green-strategies.md
│   │       ├── test-doubles.md
│   │       ├── test-design.md
│   │       ├── test-patterns.md
│   │       ├── tdd-and-design.md
│   │       ├── advanced-techniques.md
│   │       └── blazor-testing.md     # Blazor テスト（Leptos frontend testing 相当）
│   ├── integration-test-dotnet/
│   │   └── SKILL.md
│   └── setup-ci/references/
│       └── ci-dotnet.yml
```

### 既存修正（12 ファイル）

```
.claude-plugin/
├── rules/
│   ├── quality-checks.md             # QC12 追加 + QC7/QC9/QC11 .NET 対応
│   ├── type-safety.md                # TS-C1〜C5 追加
│   ├── api-validation.md             # AV-C1〜C5 追加
│   ├── project-architecture.md       # ASP.NET Core + NetArchTest セクション追加
│   ├── security.md                   # C#/Blazor ノート追加
│   └── INDEX.md                      # 新規エントリ + C# 早見表
├── agents/
│   ├── parallel-worker.md            # .NET 品質チェック + Stryker.NET
│   ├── review-worker.md              # .NET レビュー対応
│   ├── code-simplifier.md            # C# 改善ポイント
│   └── unit-test-engineer.md         # C#/xUnit + Blazor テスト
└── skills/
    ├── spec-implement/SKILL.md       # 言語検出 + ルーティング
    └── setup-ci/SKILL.md             # .NET 検出 + テンプレート
```

---

## 実行順序と依存関係

```
Phase A (ルール基盤) ──────────────────────────────┐
  A-1: 新規ルール 6 ファイル（並列作成可）          │
  A-2: 既存ルール追記 5 ファイル（並列編集可）      │
  → Phase A 完了時に確認                            │
                                                    ↓
Phase B (TDD・テストインフラ) ─────────────────────┐
  B-1: tdd-skills-dotnet (9 ファイル)               │ ← A の QC12 参照
  B-1: integration-test-dotnet (1 ファイル)         │ ← A の aspnet-core.md, ef-core.md, blazor.md 参照
  B-2: エージェント追記 4 ファイル                   │ ← A の quality-checks.md QC12 参照
  → Phase B 完了時に確認                            │
                                                    ↓
Phase C (オーケストレーション) ────────────────────┐
  C-1: spec-implement 修正                          │ ← B のエージェント・スキル必要
  C-1: setup-ci 修正                                │ ← A の QC12 参照
  C-2: ci-dotnet.yml 作成                           │
  → Phase C 完了時に確認                            │
                                                    ↓
Phase D (仕上げ) ──────────────────────────────────
  security.md 追記
  INDEX.md 最終確認
  → E2E 検証
```

---

## 検証方法

### Phase A 検証
- glob パターン確認: `.cs` / `.razor` ファイルが存在するテストプロジェクトで新規ルールが自動アクティベーションされることを確認
- INDEX.md の ID 体系に重複がないことを確認
- quality-checks.md の既存 Rust/Node.js セクションが無変更であることを diff 確認

### Phase B 検証
- `tdd-skills-dotnet/SKILL.md` が skill として認識されることを確認
- `parallel-worker.md` が `.csproj` 存在下で `dotnet` コマンドを選択することを手動確認
- Stryker.NET セクションが `cargo-mutants` と同等の結果ハンドリングを持つことを確認

### Phase C 検証
- C# プロジェクト（`*.csproj` あり、`Cargo.toml` なし）で `spec-implement` を実行し、言語検出が `dotnet` になることを確認
- Blazor プロジェクトで `dotnet-blazor` が検出されることを確認
- `setup-ci` で `ci-dotnet.yml` テンプレートが選択されることを確認

### E2E 検証
- 簡易 ASP.NET Core Web API プロジェクトを作成し、spec-workflow 全フェーズ (requirements → design → test-design → tasks → implement → review) を通して動作確認
- Blazor Web App プロジェクトで同様に動作確認（Trim/AOT 検証含む）

---

## リスクと対策

| リスク | 影響度 | 対策 |
|--------|--------|------|
| 共有ファイル変更で既存 Rust ワークフローが壊れる | 高 | 追記のみ。変更後に Rust プロジェクトで品質チェックを実行し既存パスが動作することを確認 |
| エージェントプロンプト肥大化 | 中 | コマンドをインラインせず `quality-checks.md` を参照させる。「プロジェクトタイプに応じた QC コマンドを使用」と記述 |
| .NET エコシステムのバリエーション | 中 | スコープを .NET 10 に明示的に限定。ルール冒頭に明記 |
| 検出の偽陽性（Cargo.toml + .csproj 共存） | 低 | 優先度チェーンで Rust が先。polyglot は tech.md で明示指定 |
| Analyzer パッケージの競合・ノイズ | 中 | Directory.Build.props で Analyzer 設定を一元化。推奨パッケージセットを csproj.md で定義 |
| Stryker.NET の実行時間 | 低 | nightly schedule 推奨。CI では PR チェックに含めない |
