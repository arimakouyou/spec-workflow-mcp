# spec-workflow-mcp プラグイン フロー詳細

**最終更新**: 2026-04-20
**対象プラグイン**: `spec-workflow-mcp` v2.2.29
**収録元**: `.claude-plugin/` 配下の `plugin.json` / `agents/` / `skills/` / `rules/` / `hooks/hooks.json` / `.mcp.json`

本ドキュメントは、プラグインが公開する「フロー」「エージェント」「スキル」「ルール」「フック」「MCP サーバ」を俯瞰するためのリファレンスです。各項目の詳細実装は `.claude-plugin/` 配下の原本を参照してください。

---

## 目次

1. [プラグイン全体像](#1-プラグイン全体像)
2. [主要フロー（Spec-Driven Development）](#2-主要フロー-spec-driven-development)
3. [エージェント詳細（8 種）](#3-エージェント詳細8-種)
4. [スキル詳細（37 種）](#4-スキル詳細37-種)
5. [ルール一覧（36 ファイル）](#5-ルール一覧36-ファイル)
6. [フック定義](#6-フック定義)
7. [MCP サーバ](#7-mcp-サーバ)

---

## 1. プラグイン全体像

### 1.1 マニフェスト

`/.claude-plugin/plugin.json`:

| フィールド | 値 |
|---|---|
| name | `spec-workflow-mcp` |
| version | `2.2.29` |
| description | MCP server for structured spec-driven development with real-time web dashboard. |
| skills | `./skills/` |
| hooks | `./hooks/hooks.json` |
| rules | `./rules/` |
| license | GPL-3.0 |

`agents/` と `.mcp.json` はマニフェストに明記されないが、Claude Code の規約に従い自動検出される。

### 1.2 ディレクトリ構成

```text
.claude-plugin/
├── plugin.json          # マニフェスト
├── marketplace.json     # マーケットプレース配信情報
├── .mcp.json            # MCP サーバ定義（spec-workflow / playwright）
├── agents/              # 8 個のサブエージェント
├── skills/              # 37 個のスキル
├── rules/               # 36 個のルール（INDEX.md 含む）
└── hooks/               # 7 個の bash スクリプト + hooks.json
```

---

## 2. 主要フロー（Spec-Driven Development）

プラグインの中核は **Spec-Driven Development**。Phase 0 から Phase 5 まで段階的にドキュメントを固めて実装に入る流れ。

### 2.1 標準フロー（新規スペック）

```text
(任意) /steering-doc          … product / tech / structure をプロジェクト単位で整備
        │
        ▼
Phase 0:   /spec-request-spec      … ユースケース・技術スタック・task_type を定義
        │
        ▼
Phase 1:   /spec-requirements       … EARS 形式で REQ-N を定義（承認ゲート）
        │
        ▼
Phase 2:   /spec-design             … Wave1(骨格) → Wave2(詳細) 設計（承認ゲート）
        │
        ▼
Phase 3:   /spec-test-design        … UT / IT / E2E 仕様 + Traceability Matrix
        │
        ▼
Phase 4:   /spec-tasks              … タスク分解（N.M 形式, _Prompt/_TestFocus/_Evidence/_DependsOn）
        │
        ▼
Phase 5:   /spec-implement          … TDD (Red→Green→Refactor) を各タスクに適用
             ├─ /spec-impl-test-write   (RED)
             ├─ /spec-impl-code         (GREEN)
             ├─ /spec-impl-review       (REFACTOR)
             ├─ /spec-impl-test-run     (RED/GREEN 検証)
             ├─ /log-implementation     (実装ログ永続化)
             └─ Phase Review (オプション: phase-review-team)

並列パス: /spec-e2e-implement       … IT/E2E を独立して並列実装可能
```

### 2.2 中断・可視化フロー

- **`/spec-status`** — 現フェーズと次に必要なフェーズを判定
- **`/spec-verify`** — depends_on / spec_id の整合性を監査
- **`/spec-graph`** — Mermaid で依存グラフ可視化
- **`/spec-impact-analyze`** — 上流変更の下流波及を green/amber/gray で分類

### 2.3 PR・ブランチフロー（単発修正）

```text
GitHub Issue → /handle-issue
         ├─ Path A（大規模, 3+ 点）: Spec Workflow に接続
         ├─ Path B（小規模, 1-2 点）: TDD 実装 → /create-pr
         └─ Path C（判断要）: ユーザー確認

PR 対応: /pre-push-review → /create-pr → /handle-pr-comments → /update-review-patterns
```

### 2.4 リソース配分ポリシー

`rules/resource-aware-parallelism.md` に基づき、CPU / メモリから `MAX_HEAVY_AGENTS` と `MAX_LIGHT_AGENTS` を動的に決定してバッチ分割する。Phase Review の 5 専門家起動時に顕著に効く。

---

## 3. エージェント詳細（8 種）

`.claude-plugin/agents/` に配置された 8 個の subagent。多くは `spec-implement` オーケストレーションの各フェーズで呼び出される。

### 3.1 parallel-worker

| 項目 | 内容 |
|---|---|
| Model | sonnet |
| Tools | Read, Edit, Write, Bash, Grep, Glob, Skill, TaskGet/Update/List, SendMessage, advisor |
| Skills | tdd-skills |
| PermissionMode | bypassPermissions |

- **役割**: TDD フロー全体（Red→Green→Refactor）と品質チェックをエンドツーエンド実行。`spec-implement` Step 4 の主力。
- **主要ステップ**:
  1. Worktree 検証/作成 → 診断セッション（`diagnosis.md`）初期化
  2. RED: `test-design.md` の UT-N.M に合わせた失敗テストを記述
  3. GREEN: 実装（Leptos は「ロジック関数先 → view! 配線」の順）
  4. REFACTOR: テストが通る状態を維持したまま整理
  5. 品質チェック: rustfmt + clippy + cargo test（.NET は dotnet format + build + test）
  6. 依存脆弱性: cargo-audit / dotnet list package --vulnerable
  7. Mutation: cargo-mutants / Stryker.NET
  8. 完了レポート（status, worktree_path, branch, 品質結果, changed_files）
- **分担**: レビュー・コミットは `review-worker` に委譲する。

### 3.2 review-worker

| 項目 | 内容 |
|---|---|
| Model | opus |
| Tools | Read, Edit, Write, Bash, Grep, Glob, Skill, TaskGet/Update/List, SendMessage, advisor |
| PermissionMode | bypassPermissions |

- **役割**: 実装 Worker の成果をレビュー、最小限の手直しと git commit を担当。`spec-implement` Step 6。
- **レビュー観点（A-G + E2）**:
  - A スタイル・規約、B 設計・構造、C セキュリティ（OWASP）、D タスク仕様適合
  - E テストコード最終チェック（test-design.md 比較）、E2 TDD プロセス検証
  - F 設計整合（design.md）、G API ドキュメント（openapi.yaml）
- **ポリシー**: Anti-Bias Protocol / observation log 記録 / Severity 分類（Minor→auto-fix, Moderate→差戻し, Critical→escalate）/ 最大 3 サイクル。
- **成果物**: git commit（hash）+ 完了レポート（observations, auto_fixed, findings）。

### 3.3 integ-test-worker

| 項目 | 内容 |
|---|---|
| Model | sonnet |
| Tools | Read, Write, Edit, Bash, Grep, Glob, TaskGet/Update/List, SendMessage, advisor |

- **役割**: 統合テストの実装担当。ホワイトボード（Goal / Findings）から文脈を取得し、Handler→Repository→Model→DTO チェーンを押さえたテストを書く。
- **設計**: 5 カテゴリ（Happy Path / Error / Boundary / Edge / External Dependency）を必ずカバー。
- **品質自己チェック**: sccache を活用した「rustfmt + clippy + cargo test を単一 Bash」で実行。
- **制約**: 共通ヘルパー（`helpers/`）の編集は禁止。新規ヘルパーが要る場合は Command へリクエスト。

### 3.4 integ-test-auditor

| 項目 | 内容 |
|---|---|
| Model | opus |
| Tools | Read, Grep, Glob, TaskGet/Update, TaskList, SendMessage, advisor |

- **役割**: 統合テストの品質監査（読み取り専用）。`quality-gate.md` と `test-case-design.md` を読み込み、次の軸で PASS/FAIL を決定。
  - A: 5 カテゴリカバレッジ
  - B1: ステータスコード専用テスト = 0 / B2: POST/PUT/DELETE 後の DB 検証
  - C: Given-When-Then / 命名 / 独立性
  - D: TestContext / trait DI / 時間制御
  - E: `#[tokio::test]` / clippy / rustfmt
- **サイクル**: 最大 3 回、3 回目 FAIL は escalated。

### 3.5 unit-test-engineer

| 項目 | 内容 |
|---|---|
| Model | sonnet / Color | green |
| Tools | Read, Write, Edit, Bash, Grep, Glob, advisor |

- **役割**: Rust / C# 向け UT 専門（Design by Contract）。前提・事後・不変条件を抽出して 4 カテゴリ（Happy / Boundary / Exception / Edge）でテスト化。
- **ダブル**: Rust は mockall、C# は NSubstitute / Moq。
- **命名**: `{behavior}_when_{condition}`。
- **対象外**: `view!` / `.razor` 出力の DOM テスト（E2E へ回す）。

### 3.6 frontend-test-engineer

| 項目 | 内容 |
|---|---|
| Model | sonnet / Color | teal |
| Tools | Read, Write, Edit, Bash, Grep, Glob, advisor |

- **役割**: Leptos フロントエンド専用 UT。`view!` の外に抽出したロジック（signal / memo / validation / server function / handler）に絞ってテスト。
- **参照**: `skills/tdd-skills-rust/references/leptos-frontend-testing.md`。
- **対象外**: view! 出力 / DOM イベント / CSS / ルーティング / ハイドレーション。

### 3.7 code-simplifier

| 項目 | 内容 |
|---|---|
| Model | sonnet |
| Tools | Read, Edit, Write, Bash, Grep, Glob, advisor |

- **役割**: 機能を変えずにコードを洗練化。`.claude-plugin/rules/` 規約に準拠。
- **手順**: 計画 → advisor 相談 → 改善 → 機能保持再確認 → rustfmt+clippy / dotnet format で検証。
- **言語別ポイント**: Rust は不要 clone 削除・`?` 演算子・Box→Generics、C# は LINQ 化・null-coalescing・record 活用。

### 3.8 wave-harness-worker

| 項目 | 内容 |
|---|---|
| Model | sonnet |
| Tools | Read, Edit, Write, Bash, Grep, Glob, Skill, advisor |
| Skills | tdd-skills |

- **役割**: Wave Harness 環境専用。1 work_item の実装・検証・JSON スキーマ v3 準拠レスポンスを返す。
- **リトライ**: `diagnosis.md` の `## Rework Cycle` を読み、同一 failure_category 2 連続 FAIL で DR6 DIVERGENT を発動し根本的に異なる仮説を立てる。
- **制約**: ファイル編集のみ（git add/commit/checkout -b 禁止）。`test_targets` 未指定時は affected_files から推測。

---

## 4. スキル詳細（37 種）

`.claude-plugin/skills/<name>/SKILL.md` で定義。役割別にグルーピング。

### 4.1 Spec-Driven Development（Phase 0-5 + 周辺）— 17 スキル

#### spec-request-spec — Phase 0
新規スペックの起点。ユースケース / 技術スタック / `task_type` を決定して `request-spec.md` を生成。fix モードのサブエージェントでプレースホルダ除去後、ユーザー承認待ち。

#### spec-requirements — Phase 1
EARS 形式で REQ-N を定義。frontmatter（`spec_id / phase / version / depends_on`）必須。市場調査（web search）可。fix サブエージェント → ユーザー承認。

#### spec-design — Phase 2
Wave1（骨格）→ ユーザー承認 → Wave2（詳細）を追記する 2 段構え。`depends_on: [req-spec / requirements]`。

#### spec-test-design — Phase 3
UT/IT/E2E 仕様と **Requirements-Test Traceability Matrix** を作成。テスト技術（Playwright / testcontainers / reqwest 等）をここで決定。

#### spec-tasks — Phase 4
タスクをチェックリスト化（N.M 形式）、各タスクに `_Prompt / _TestFocus / _Evidence / _DependsOn` を付与。新規プロジェクトなら Phase 0 Setup に `git init` タスクを自動追加。

#### spec-implement — Phase 5
オーケストレーター。タスクごとに Discover → RED → GREEN → REFACTOR → UT Quality → Review+Commit → Log。Session lockfile（`.implement-session.json`）で排他制御。`_PhaseReview: true` のタスクでは `phase-review-team` を起動。

#### spec-impl-test-write（RED）
Steering / Task / design.md / test-design.md から 4 カテゴリ（Happy / Boundary / Error / Edge）の失敗テストを生成。コンパイル不可のまま返す。

#### spec-impl-code（GREEN）
テストを通す最小限の実装。Green Strategy（Fake It / Triangulation / Obvious Implementation）を明示選択。`structure.md` の File Placement Rule（P4-01）を尊重。

#### spec-impl-review（REFACTOR）
SRP / DRY / Error Handling / Type Safety を適用しつつテスト通過維持。Steering の **authoritative validator**（未承認依存・配置ルール違反の検出）。新機能追加は禁止。

#### spec-impl-test-run
`vitest / jest / pytest` などテストランナを自動検出。RED モードでは全失敗を、GREEN モードでは全成功を検証し、失敗時は `failure-taxonomy` で分類。

#### spec-verify
`requirements.md` ⇔ `design.md` ⇔ `test-design.md` ⇔ `tasks.md` の frontmatter / `spec_id` / ID 参照を検査し、dangling reference / 循環依存 / coverage gap を報告。

#### spec-review
check モード（指摘のみ）と fix モード（プレースホルダ・フォーマット・typo 自動修正）を持つ共通サブエージェント。`/spec-requirements` 等から自動呼び出し。

#### spec-impact-analyze
上流 spec の変更から下流ファイルを **green / amber / gray** に分類。PR 前の影響把握に使用。

#### spec-graph
Mermaid で file level / ID level の依存グラフを可視化。PR description 埋め込み可。

#### spec-status
5 フェーズの完了状態とタスク進捗を表形式で表示。「次に何をすべきか」を判定。

#### spec-e2e-implement
`spec-implement` と並列実行可能な IT/E2E 独立フロー。`docker-compose.test.yml` / Playwright / testcontainers をセットアップし CI 実行まで面倒を見る。

#### log-implementation
実装完了時に `.spec-workflow/specs/{spec}/Implementation Logs/task-{id}_summary.md` へ durable に記録。API / Component / Function / Class / Integration を artifact として整理。`spec-implement` が `[x]` を付ける**直前**に実行必須。

### 4.2 TDD スキル群 — 3 スキル

#### tdd-skills
Red-Green-Refactor / Given-When-Then / Test Doubles / F.I.R.S.T の共通原則。「TDD はテスト技法ではなくプログラミング技法」という前提を明示。

#### tdd-skills-rust
`#[cfg(test)]` / mockall（trait-based double）/ rstest（パラメタライズ）/ Rust 慣例の命名。

#### tdd-skills-dotnet
xUnit `[Fact]` / `[Theory]` / NSubstitute / Moq / Initial RED（`NotImplementedException`）/ C# 慣例の命名。

### 4.3 統合テスト・E2E — 2 スキル

#### integration-test（Rust）
Axum + Diesel + testcontainers。Alpha/Bravo workers 並列実装 → Pentagon reviewer の 4 段階品質ゲート。引数：`{domain}[,...] [--dry-run] [--base-branch] [--api]`。

#### integration-test-dotnet
ASP.NET Core + EF Core + Testcontainers + WireMock.NET。`WebApplicationFactory` と xUnit collection fixtures を基盤に 5 カテゴリカバレッジ。

### 4.4 PR・レビュー・品質管理 — 5 スキル

#### handle-pr-comments
PR レビューコメントを A-H カテゴリに分類して修正 → `/pre-push-review` → push。`spec-implement` 文脈では review-worker が担うのでユーザーが直接呼ぶ場面が違う点に注意。

#### pre-push-review
`.claude/_docs/know-how/pr-review-patterns.md` を基に A-H カテゴリで diff を観察。`codex` プラグイン導入時は `/codex:review` を併用。`--auto-fix` / `--save` オプションあり。

#### update-review-patterns
マージ済 PR のコメントから A-H チェックリストを自動更新。`--pr / --since / --auto / --dry-run`。週次運用 or マージ直後。

#### create-pr
テスト結果・UI スクリーンショット付きで `gh pr create`。`[--title] [--closes] [--spec] [--skip-tests] [--base]`。

#### check-approval
仕様書承認待ちを 15 秒間隔 60 分タイムアウトでポーリング。`approved` → `next:/<skill>` 自動実行、`needs-revision` / `rejected` → コメント提示。

### 4.5 GitHub Issue — 1 スキル

#### handle-issue
Issue を取得し、変更規模スコア（影響ファイル数 / 新規 API / DB スキーマ等）で Path A（Spec Workflow）/ Path B（TDD 直接）/ Path C（ユーザー判断）に分岐。

### 4.6 プロジェクト基盤・ドキュメント — 7 スキル

#### steering-doc
`product.md` → `tech.md` → `structure.md` の順に段階作成。`structure.md` は File Placement Rules（P4-01）を保有、`tech.md` は ADR サマリ、プロジェクト横断規約は `rules/` に寄せる。

#### adr
ADR を `.claude/_docs/adr/NNNN-slug.md` に version-controlled で記録。状態遷移 Proposed → Accepted → Deprecated / Superseded。`list` / `update` サブコマンドあり。

#### tech-debt
`TD-NNNN` で技術負債をレジストリ化。`add / list / update / audit`（コードベース走査で潜在負債検出）。

#### setup-ci
プロジェクト種別（Leptos / Rust / .NET / Node.js）に応じて 5 ワークフロー（`ci.yml` / `e2e.yml` / `scheduled-quality.yml` / `dependabot.yml` / `release.yml`）を生成。`--with-sast / --with-auto-merge / --with-flaky-detection` ほか多数のオプション。

#### generate-api-docs
Axum / Actix-web / Express / Fastify から OpenAPI 3.1 を自動生成。Doc コメント改善提案付き。

#### generate-arch-tests
`design.md` の Module Boundaries と Dependency Direction から architecture invariant test を生成し `tests/architecture.rs` に配置。Rust 対応。

#### cargo-mutants
`cargo mutants --no-shuffle -vV --in-diff` でミューテーション試験。`--base-branch` で diff-only 実行、`--timeout / --jobs` で runaway 防止。

### 4.7 Phase 完了レビュー — 1 スキル

#### phase-review-team
5 専門家（spec compliance / security×2 / performance / quality）を resource-aware に並列起動、leader が統合レポートを生成。`spec-implement` Step 3.5.2 で `_PhaseReview: true` のタスクから呼ばれる。

### 4.8 補助 — 1 スキル

#### knowhow-capture
チーム知識を `.claude/_docs/know-how/` に蓄積。Pattern A（explicit）/ B（2 回目以降検出）/ C（`--audit`）。`pre-push-review` のチェックリスト原本になる。

---

## 5. ルール一覧（36 ファイル）

`.claude-plugin/rules/INDEX.md` に従い分類。詳細 ID は各ファイル参照。

### 5.1 ID 体系付きルール（追跡可能チェック項目）

| ファイル | ID 範囲 | 概要 |
|---|---|---|
| rust-style.md | RS1-RS16 | Rust 公式スタイル（フォーマット・命名・構造） |
| quality-checks.md | QC1-QC12, QC3.5 | タスク/統合レベルの check コマンド定義 |
| design-principles.md | D1-D7 | SoC / 依存方向 / 最小公開 API / エラー一貫性 / 命名 / DRY / YAGNI |
| design-conformance.md | DC1-DC3 | design.md 整合（DB スキーマ・API・モデル変更禁止） |
| security.md | A1-A10 | OWASP Top 10 準拠 |
| type-safety.md | TS-R1-5, TS-C1-5, TS-T1-2 | Rust newtype / C# required / TS strict null |
| api-validation.md | AV-R1-5, AV-C1-5 | Serde `deny_unknown_fields` / ASP.NET Core モデル検証 |
| enforcement-levels.md | L1-L5 | ドキュメント → AI レビュー → CI → 構造テスト → コンパイラ |
| error-message-guidelines.md | EM1-EM4 | テスト・CI・lint のエラー形式 |
| flaky-test-management.md | FT1-FT6 | 定義 / 検出 / 追跡 / リトライ / 隔離 / 予防 |
| regression-test-policy.md | RT1-RT3 | バグ→テスト変換 / 受け入れ定着 / スイート管理 |
| csharp-style.md | CS1-CS16 | .NET 10 公式規約 |
| diagnostic-reasoning.md | DR1-DR6 | リトライ前診断 / 非繰り返し制約 / DR6 DIVERGENT |
| failure-taxonomy.md | FC1-FC6 | compile_error / test_failure / quality_check_failure / spec_mismatch |
| spec-dependency-graph.md | SD1-SD7 | ID 体系 / frontmatter / refs / DAG / 変更伝搬 |

### 5.2 言語・フレームワーク別リファレンスガイド

| ファイル | 内容 |
|---|---|
| axum.md | Router / State / Extractors / Error Handling |
| diesel.md | モデル / クエリ / Connection Pool / Tx / migration |
| leptos.md | フィーチャフラグ / SSR-CSR 分岐 / Axum 統合 |
| valkey.md | Valkey キャッシュパターン |
| cargo-toml.md | セクション順 / キー並序 / 依存ルール |
| rust-build-cache.md | sccache 環境変数前置 / worktree 共有 |
| csproj.md | SDK 形式 / PropertyGroup / PackageReference / 分析設定 |
| aspnet-core.md | Minimal APIs / DI / ミドルウェア / テスト |
| entity-framework-core.md | DbContext / エンティティ / Fluent API / migration |
| blazor.md | コンポーネント / 状態管理 / フォーム / テスト |
| dotnet-build-cache.md | MSBuild インクリメンタル / NuGet / worktree |
| context7.md | Context7 API ドキュメント検索運用 |

### 5.3 品質維持・ドキュメント同期

| ファイル | 内容 |
|---|---|
| doc-freshness.md | 90-180 日閾値の陳腐化検出 |
| doc-crossref.md | 仕様書・コード・ルール間の参照整合性 |

### 5.4 ワークフロー・プロセス

| ファイル | 内容 |
|---|---|
| spec-workflow-enforcement.md | tasks.md 読了後の直接実装を禁止、`/spec-implement` 強制 |
| feedback-loop.md | know-how → ルール昇格 → エージェント改善サイクル |
| project-architecture.md | Rust: Axum+Diesel+Valkey / C#: ASP.NET Core+EF Core+Redis |
| resource-aware-parallelism.md | CPU/メモリに基づく MAX_HEAVY/LIGHT_AGENTS 動的調整 |
| hybrid-inspection.md | 決定論的チェック + LLM review-worker の役割分担 |
| advisor-usage.md | 全エージェント共通の advisor 呼び出し規律 |

### 5.5 インデックス

| ファイル | 内容 |
|---|---|
| INDEX.md | 全ルールの ID プレフィックス・件数・早見表（実装時 / レビュー時の参照パターン） |

---

## 6. フック定義

`.claude-plugin/hooks/hooks.json` から起動される bash スクリプト群（7 個）。

### 6.1 PreToolUse

| matcher | フック | タイムアウト | 概要 |
|---|---|---|---|
| Bash | lockfile-guard.sh | 10s | ロックファイル存在時のコマンド保護 |
| Bash | format-check-guard.sh | 120s | フォーマット異常状態での Bash 実行抑止 |
| Bash | security-audit-guard.sh | 180s | `cargo audit` 等の事前ゲート |

### 6.2 PostToolUse

| matcher | フック | タイムアウト | 概要 |
|---|---|---|---|
| Read | tasks-read-guard.sh | 10s | `tasks.md` 読了検出（spec-workflow-enforcement 補助） |
| Edit\|Write | post-edit-check.sh | 15s | 編集後の即時チェック |
| Edit\|Write | post-edit-markdownlint.sh | 10s | Markdown lint |

### 6.3 hooks.json 未参照のスクリプト

| フック | 概要 |
|---|---|
| poll-approval.sh | 承認ポーリング補助。`/check-approval` から間接利用を想定 |

---

## 7. MCP サーバ

`.claude-plugin/.mcp.json` で登録される 2 サーバ。

```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "."]
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

- **spec-workflow**: 本プラグインの MCP サーバ本体。`requirements / design / test-design / tasks` などの仕様書管理、承認ゲート、Web ダッシュボードを提供。
- **playwright**: `spec-e2e-implement` / `integration-test` 系スキルが使う Playwright MCP。ブラウザ自動化を E2E 実装に提供。

---

## 付録: よくある参照パス

| 目的 | パス |
|---|---|
| 仕様書間依存グラフ | `rules/spec-dependency-graph.md` |
| 失敗分類 | `rules/failure-taxonomy.md` |
| 診断プロトコル | `rules/diagnostic-reasoning.md` |
| エンフォースメントの昇格ルート | `rules/enforcement-levels.md` |
| advisor 呼び出し規律 | `rules/advisor-usage.md` |
| ルール全体の索引 | `rules/INDEX.md` |

> **メンテナンス指針**: `plugin.json` / `agents/*.md` / `skills/*/SKILL.md` / `rules/*.md` / `hooks/hooks.json` のいずれかを更新したら、本ドキュメントも同期更新すること（CLAUDE.md「Documentation Synchronization」原則）。
