# ルールインデックス

全ルールファイルとその ID 体系の一覧。ルール参照時はこのインデックスから辿る。

## ID 体系付きルール（追跡可能）

| ファイル | ID プレフィックス | 件数 | 説明 |
|---------|-----------------|------|------|
| `rust-style.md` | RS1〜RS16 | 16 | Rust コードスタイル・フォーマット規約 |
| `quality-checks.md` | QC1〜QC12, QC3.5 | 13 | 品質チェックコマンド定義（タスクレベル: QC1〜QC6, QC3.5, QC8〜QC12 / 統合レベル: QC7）。QC12: .NET |
| `design-principles.md` | D1〜D7 | 7 | 設計原則（Taste Invariants） |
| `design-conformance.md` | DC1〜DC3 | 3 | 実装時の設計適合ルール |
| `security.md` | A1〜A10 | 10 | OWASP Top 10 + 認証/認可セキュリティ |
| `type-safety.md` | TS-R1〜R5, TS-C1〜C5, TS-T1〜T2 | 12 | 型安全性パターン（Rust + C# + TypeScript） |
| `enforcement-levels.md` | L1〜L5 | 5 | 段階的執行レベル定義 |
| `error-message-guidelines.md` | EM1〜EM4 | 4 | エラーメッセージ品質ガイドライン |
| `csharp-style.md` | CS1〜CS16 | 16 | C# コードスタイル・フォーマット規約（.NET 10） |
| `diagnostic-reasoning.md` | DR1〜DR6 | 6 | 診断推論プロトコル（リトライ前の構造化診断・セッション状態永続化・繰り返し防止・DIVERGENT 仮説転換） |
| `failure-taxonomy.md` | FC1〜FC6 | 6 | 横断的な失敗分類語彙（parallel-worker / review-worker / wave-harness 間の共通キー。DR6 DIVERGENT トリガー判定の入力） |
| `spec-dependency-graph.md` | SD1〜SD7 | 7 | 仕様書間の依存グラフ（ID 体系 + frontmatter スキーマ + refs 整合性 + DAG 制約 + 変更伝搬意味論）。`/spec-impact-analyze` と `/spec-verify` の入力 |

**合計: 105 ルール（ID 付き）**

## Skill に降格されたルール（Phase B-1 + B-2）

以下は従来 Rule として `.claude-plugin/rules/` に配置していたが、常時ロード不要な状況依存知識として Skill (`.claude-plugin/skills/{name}/SKILL.md`) に降格した:

### Phase B-1 — ○ 降格容易な 5 件

| 旧 Rule | 新 Skill | 説明 |
|---------|---------|------|
| `cargo-toml.md` | `cargo-toml` | Cargo.toml フォーマット規約 |
| `valkey.md` | `valkv-cache` | Valkey (Redis 互換) キャッシュパターン |
| `context7.md` | `context7` | Context7 MCP ドキュメント検索ガイド |
| `regression-test-policy.md` | `regression-test-policy` | リグレッションテストポリシー（RT1-RT3） |
| `resource-aware-parallelism.md` | `resource-aware-parallelism` | リソース検出・並列実行制御 |

### Phase B-2 — 技術別 9 件 + 特定タスク 3 件

| 旧 Rule | 新 Skill | 説明 |
|---------|---------|------|
| `axum.md` | `axum` | Axum Web フレームワークパターン (Rust) |
| `diesel.md` | `diesel` | Diesel ORM パターン (Rust) |
| `leptos.md` | `leptos` | Leptos フルスタック WASM パターン (Rust) |
| `rust-build-cache.md` | `rust-build-cache` | sccache ビルドキャッシュ戦略 |
| `csproj.md` | `csproj` | .csproj / Directory.Build.props 規約 (.NET 10) |
| `aspnet-core.md` | `aspnet-core` | ASP.NET Core パターン (.NET 10) |
| `entity-framework-core.md` | `entity-framework-core` | Entity Framework Core パターン (.NET 10) |
| `blazor.md` | `blazor` | Blazor フルスタック WASM パターン (.NET 10) |
| `dotnet-build-cache.md` | `dotnet-build-cache` | .NET ビルドキャッシュ戦略 |
| `api-validation.md` | `api-validation` | API バリデーション規約 (AV-R1-5, AV-C1-5 を Skill 本文内で保持) |
| `flaky-test-management.md` | `flaky-test-management` | Flaky Test 管理ポリシー (FT1-6 を Skill 本文内で保持) |
| `doc-freshness.md` | `doc-freshness` | ドキュメント鮮度管理 |

> **注**: `feedback-loop.md` は `always_apply: true` を持つため降格候補から外し、Rule として維持している。

## ワークフロー・プロセスルール

| ファイル | 説明 |
|---------|------|
| `spec-workflow-enforcement.md` | spec-workflow 必須手順（tasks.md 読後の実装禁止等） |
| `feedback-loop.md` | フィードバックループメカニズム（`always_apply: true`） |
| `project-architecture.md` | プロジェクト構造・レイヤー定義 |
| `hybrid-inspection.md` | ハイブリッド検査モデル（決定論 + LLM） |
| `advisor-usage.md` | advisor ツール利用ガイドライン（全エージェント共通） |
| `doc-crossref.md` | ドキュメント間クロスリファレンス検証 |

## ルール参照の早見表

### 実装中に参照するルール

#### Rust

| 作業 | 参照ルール / Skill |
|------|----------|
| Rust コード記述 | RS1-RS16, D1-D7, TS-R1-R5 |
| API ハンドラ実装 | AV-R1-R5 (`api-validation` Skill), A1-A10, DC2 |
| DB スキーマ/マイグレーション | DC1, DC3 |
| テスト記述 | QC3, D6, D7 |
| セキュリティ確認 | A1-A10, AV-R1 (`api-validation` Skill) |
| テスト失敗修正 | DR1-DR6, FC1-FC6, `flaky-test-management` Skill |
| コミット前チェック | QC1-QC6, QC8-QC11 |

#### C# (.NET 10)

| 作業 | 参照ルール / Skill |
|------|----------|
| C# コード記述 | CS1-CS16, D1-D7, TS-C1-C5 |
| API ハンドラ実装 | AV-C1-C5 (`api-validation` Skill), A1-A10, DC2 |
| DB スキーマ/マイグレーション | DC1, DC3 |
| テスト記述 | QC12, D6, D7 |
| セキュリティ確認 | A1-A10, AV-C1 (`api-validation` Skill) |
| テスト失敗修正 | DR1-DR6, FC1-FC6, `flaky-test-management` Skill |
| コミット前チェック | QC12, QC8-QC11 |

### レビュー時に参照するルール

#### Rust

| review-worker カテゴリ | 参照ルール / Skill |
|-----------------------|----------|
| A: Style | RS1-RS16 |
| B: Design | D1-D7, TS-R1-R5, L1-L5 |
| C: Security | A1-A10, AV-R1-R5 (`api-validation` Skill) |
| D: Spec | （仕様書ベース） |
| E: Tests | QC3, `flaky-test-management` Skill |
| F: Design Conformance | DC1-DC3 |
| G: API Documentation | （openapi.yaml ベース） |

#### C# (.NET 10)

| review-worker カテゴリ | 参照ルール / Skill |
|-----------------------|----------|
| A: Style | CS1-CS16 |
| B: Design | D1-D7, TS-C1-C5, L1-L5 |
| C: Security | A1-A10, AV-C1-C5 (`api-validation` Skill) |
| D: Spec | （仕様書ベース） |
| E: Tests | QC12, `flaky-test-management` Skill |
| F: Design Conformance | DC1-DC3 |
| G: API Documentation | （openapi.yaml ベース） |
