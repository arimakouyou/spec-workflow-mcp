# ルールインデックス

全ルールファイルとその ID 体系の一覧。ルール参照時はこのインデックスから辿る。

## ID 体系付きルール（追跡可能）

| ファイル | ID プレフィックス | 件数 | 説明 |
|---------|-----------------|------|------|
| `rust-style.md` | RS1〜RS16 | 16 | Rust コードスタイル・フォーマット規約 |
| `quality-checks.md` | QC1〜QC12, QC3.5 | 14 | 品質チェックコマンド定義（タスクレベル: QC1〜QC6, QC3.5, QC8〜QC12 / 統合レベル: QC7）。QC12: .NET |
| `design-principles.md` | D1〜D7 | 7 | 設計原則（Taste Invariants） |
| `design-conformance.md` | DC1〜DC3 | 3 | 実装時の設計適合ルール |
| `security.md` | A1〜A10 | 10 | OWASP Top 10 + 認証/認可セキュリティ |
| `type-safety.md` | TS-R1〜R5, TS-C1〜C5, TS-T1〜T2 | 12 | 型安全性パターン（Rust + C# + TypeScript） |
| `api-validation.md` | AV-R1〜AV-R5, AV-C1〜AV-C5 | 10 | API リクエストバリデーション（Rust + C#） |
| `enforcement-levels.md` | L1〜L5 | 5 | 段階的執行レベル定義 |
| `error-message-guidelines.md` | EM1〜EM4 | 4 | エラーメッセージ品質ガイドライン |
| `flaky-test-management.md` | FT1〜FT6 | 6 | Flaky Test 管理ポリシー |
| `regression-test-policy.md` | RT1〜RT3 | 3 | リグレッションテストポリシー（バグ→テスト変換・受入基準定着） |

| `csharp-style.md` | CS1〜CS16 | 16 | C# コードスタイル・フォーマット規約（.NET 10） |

**合計: 99 ルール（ID 付き）**

## リファレンスガイド（ID なし・パターン集）

| ファイル | 説明 |
|---------|------|
| `axum.md` | Axum Web フレームワークパターン |
| `diesel.md` | Diesel ORM パターン |
| `leptos.md` | Leptos フルスタック WASM パターン |
| `valkey.md` | Valkey キャッシュパターン |
| `cargo-toml.md` | Cargo.toml フォーマット規約 |
| `context7.md` | Context7 API ドキュメント検索ガイド |
| `rust-build-cache.md` | sccache ビルドキャッシュ戦略 |
| `csproj.md` | .csproj / Directory.Build.props 規約（.NET 10） |
| `aspnet-core.md` | ASP.NET Core パターン（.NET 10） |
| `entity-framework-core.md` | Entity Framework Core パターン（.NET 10） |
| `blazor.md` | Blazor フルスタック WASM パターン（.NET 10） |
| `dotnet-build-cache.md` | .NET ビルドキャッシュ戦略 |

## 品質維持・ガベージコレクション

| ファイル | 説明 |
|---------|------|
| `doc-freshness.md` | ドキュメント鮮度管理（閾値監視・陳腐化検出） |
| `doc-crossref.md` | ドキュメント間クロスリファレンス検証 |

## テスト品質・CI 運用ルール

| ファイル | 説明 |
|---------|------|
| `error-message-guidelines.md` | エラーメッセージ品質ガイドライン（EM1-EM4） |
| `flaky-test-management.md` | Flaky Test 管理ポリシー（FT1-FT6: 定義・検出・追跡・リトライ・隔離・予防） |
| `regression-test-policy.md` | リグレッションテストポリシー（RT1-RT3: バグ→テスト変換・受入基準定着・スイート管理） |

## ワークフロー・プロセスルール

| ファイル | 説明 |
|---------|------|
| `spec-workflow-enforcement.md` | spec-workflow 必須手順（tasks.md 読後の実装禁止等） |
| `feedback-loop.md` | フィードバックループメカニズム |
| `project-architecture.md` | プロジェクト構造・レイヤー定義 |
| `resource-aware-parallelism.md` | リソース検出・並列実行制御 |
| `hybrid-inspection.md` | ハイブリッド検査モデル（決定論 + LLM） |

## ルール参照の早見表

### 実装中に参照するルール

#### Rust

| 作業 | 参照ルール |
|------|----------|
| Rust コード記述 | RS1-RS16, D1-D7, TS-R1-R5 |
| API ハンドラ実装 | AV-R1-R5, A1-A10, DC2 |
| DB スキーマ/マイグレーション | DC1, DC3 |
| テスト記述 | QC3, D6, D7 |
| セキュリティ確認 | A1-A10, AV-R1 |
| コミット前チェック | QC1-QC6, QC8-QC11 |

#### C# (.NET 10)

| 作業 | 参照ルール |
|------|----------|
| C# コード記述 | CS1-CS16, D1-D7, TS-C1-C5 |
| API ハンドラ実装 | AV-C1-C5, A1-A10, DC2 |
| DB スキーマ/マイグレーション | DC1, DC3 |
| テスト記述 | QC12, D6, D7 |
| セキュリティ確認 | A1-A10, AV-C1 |
| コミット前チェック | QC12, QC8-QC11 |

### レビュー時に参照するルール

#### Rust

| review-worker カテゴリ | 参照ルール |
|-----------------------|----------|
| A: Style | RS1-RS16 |
| B: Design | D1-D7, TS-R1-R5, L1-L5 |
| C: Security | A1-A10, AV-R1-R5 |
| D: Spec | （仕様書ベース） |
| E: Tests | QC3 |
| F: Design Conformance | DC1-DC3 |
| G: API Documentation | （openapi.yaml ベース） |

#### C# (.NET 10)

| review-worker カテゴリ | 参照ルール |
|-----------------------|----------|
| A: Style | CS1-CS16 |
| B: Design | D1-D7, TS-C1-C5, L1-L5 |
| C: Security | A1-A10, AV-C1-C5 |
| D: Spec | （仕様書ベース） |
| E: Tests | QC12 |
| F: Design Conformance | DC1-DC3 |
| G: API Documentation | （openapi.yaml ベース） |
