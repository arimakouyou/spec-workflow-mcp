---
name: spec-implement
description: "Phase 5 of spec-driven development: implement tasks from an approved tasks.md document using TDD (Red-Green-Refactor). ONLY use this skill when ALL FOUR spec documents exist: requirements.md, design.md, test-design.md, AND tasks.md. Use this skill when the user explicitly requests to start implementation, code a specific task ID, or continue implementation of an existing spec. Triggers on: 'implement task', 'start coding', 'work on task 3', 'implement spec X', 'continue implementation', '/spec-implement'. DO NOT trigger on general 'implement X' requests unless spec documents exist."
---

# Spec Implementation (Phase 5) — TDD Orchestrator

Execute tasks systematically from the approved tasks.md using a **TDD-driven workflow**. Each task follows the cycle: Start → Discover → Read Guidance → **TDD Implementation (parallel-worker)** → **UT Quality Verification** → **Code Review + Commit (review-worker)** → Log → Complete.

## ⛔ Orchestrator Prohibited Actions (ABSOLUTE RULES)

You executing this skill are the **orchestrator**, not the **implementer**. Strictly follow these rules:

| Prohibited | Reason |
|-----------|--------|
| **Do not write code yourself** | Implementation must always be delegated to `parallel-worker` |
| **Do not write tests yourself** | The initial TDD tests (RED phase) are `parallel-worker`'s responsibility. Adding supplemental tests is the test engineer's (`frontend-test-engineer` or `unit-test-engineer`) responsibility |
| **Do not run git commit yourself** | Commits must always be delegated to `review-worker` |
| **Do not skip agent calls** | Each step's agent call cannot be skipped |

**For any reason whatsoever (e.g., "it's a simple task", "I can do it myself"), do not skip agent calls.**

The orchestrator's sole responsibilities:
1. Read tasks.md and identify the next task
2. Call agents with the correct prompts
3. Receive agent completion reports and hand off to the next agent
4. Call `/log-implementation` skill
5. Update task status in tasks.md

## Prerequisites Check (MANDATORY — DO NOT SKIP)

Before doing anything else, verify all prerequisite files exist:

1. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists
2. Check `.spec-workflow/specs/{spec-name}/design.md` exists
3. Check `.spec-workflow/specs/{spec-name}/test-design.md` exists
4. Check `.spec-workflow/specs/{spec-name}/tasks.md` exists

If ANY file is missing — **STOP immediately. Do NOT start implementing.**

| Missing File | Required Skill |
|-------------|---------------|
| requirements.md | `/spec-requirements` |
| design.md | `/spec-design` |
| test-design.md | `/spec-test-design` |
| tasks.md | `/spec-tasks` |

Tell the user: "Cannot start implementation because {filename} does not exist. Please run {skill-name} first." Then exit this skill.

---

Tasks must be approved and cleaned up (Phases 1-4 complete). If not, use `/spec-tasks` first.

## Step 0: Tool Verification (MANDATORY — DO NOT SKIP)

Prerequisites 通過後、実装開始前に全必須ツールの存在を検証する。Task Cycle 開始前に **1回だけ** 実行。

### 0.1 ツール要件の読み取り

以下2ファイルからツール要件テーブルを解析:
1. `.spec-workflow/specs/{spec-name}/design.md` → `## Required Build Tools` セクション
2. `.spec-workflow/specs/{spec-name}/test-design.md` → `#### Required Test Tools` セクション

いずれかのセクションが存在しない場合は警告ログ（`[tool-verify] WARNING: Required Tools section missing in {filename} — skipping tool verification for that file`）を出力し、存在するセクションのみ検証する。両方とも存在しない場合は `[tool-verify] WARNING: No Required Tools sections found in design.md or test-design.md — skipping tool verification` を出力して Task Cycle へ進む（後方互換性）。

**重要:** 後続の quality-checks では `docker-compose` コマンド（または `docker compose` サブコマンド）が必須扱いとなる場合がある。Docker Compose を利用するプロジェクトでは、いずれかの Required Tools テーブルに **必ず `docker-compose`（もしくは `docker compose`）を必須ツールとして含めること**。含めないと Step 0 を通過しても Phase Review / スモークテストで FAIL（環境不備）になる可能性がある。

### 0.2 ツール存在確認

各ツールエントリについて Check Command を実行する。**Check Command はセキュリティ上の制約に従うこと:**

**安全性チェック（実行前に必ず検証 — 対象はドキュメントに記載された Check Command 文字列自体）:**
- Check Command は `<tool> --version` や `<tool> -v` 等の読み取り専用バージョン確認パターンのみ許可
- ドキュメント記載の Check Command 文字列にパイプ (`|`)、リダイレクト (`>`, `<`)、セミコロン (`;`)、`&&`、`$()` 等のシェル演算子が含まれる場合は**自動実行しない** — ユーザーに内容を提示して承認を得てから実行
- 安全なパターンの場合のみ自動実行（`2>&1` はオーケストレータが付与するラッパーであり、Check Command 自体には含まれない）:

```bash
# 各ツールの Check Command を順次実行（安全パターンのみ自動実行）
# 注: 2>&1 は stderr のバージョン出力を取得するためオーケストレータが付与
{check_command} 2>&1
echo "EXIT_CODE: $?"
```

- exit 0 → バージョン解析。Min Version が指定されている場合はバージョン比較:
  - バージョン要件を満たす → `[tool-verify] {tool}: OK ({detected_version})`
  - バージョンが古い → VERSION_MISMATCH リストへ追加
- exit ≠ 0 → Required 列に応じて分類:
  - `Yes` → MISSING_REQUIRED リストへ
  - `Recommended` → 警告ログ `[tool-verify] WARNING: {tool} not found (recommended, not required)` を出力、続行

### 0.3 インストール案内とユーザー承認

**Install Command のユーザー承認なしの自動実行は行わない。** spec ドキュメント由来のコマンドには `curl|sh` や権限昇格等のリスクがあるため、必ずユーザーの明示的な承認を得てから実行する。

MISSING_REQUIRED リストおよび VERSION_MISMATCH リストが空でない場合、以下の手順を実行:

1. 不足ツール一覧をユーザーに提示:
   ```
   以下のツールが不足／バージョン不足です:

   | Tool | Purpose | Install Command | Status |
   |------|---------|-----------------|--------|
   | {tool} | {purpose} | `{install_command}` | Missing / Version mismatch |

   上記 Install Command を確認し、実行してよろしいですか？ (yes/no)
   ```

2. ユーザーが承認した場合のみ Install Command を実行し、再度 Check Command で検証:
   - 成功 → リストから除外、ログ `[tool-verify] {tool}: installed successfully ({version})` を記録
   - 失敗 → リストに残留

3. ユーザーが拒否した場合 → リストに残留し、0.4 ゲート判定へ進む

### 0.4 ゲート判定

```
if MISSING_REQUIRED is not empty OR VERSION_MISMATCH is not empty:
  Report to user:
    "## ⛔ Tool Verification Failed

    以下の必須ツールが不足または要件を満たしていないため、実装を開始できません:

    | Tool | Purpose | Install Command | Status |
    |------|---------|-----------------|--------|
    | {tool} | {purpose} | {install_command} | Missing / Version too old ({detected} < {required}) |

    上記ツールをインストール／アップグレードした後、再度 `/spec-implement` を実行してください。"

  STOP — Task Cycle に進まない。

else:
  log "[tool-verify] All required tools verified. Proceeding to implementation."
  Proceed to Task Cycle.
```

---

## Inputs

- **spec name** (kebab-case, e.g., `user-authentication`)
- **task ID** (optional — if not provided, pick the next pending `[ ]` task)

## Task Cycle

Repeat for each wave:

### 1. Start the Wave

Parse `.spec-workflow/specs/{spec-name}/tasks.md` and compute execution waves based on `_DependsOn:` dependencies:

1. Parse tasks.md to identify Phase structure and `_DependsOn:` metadata
2. Compute execution waves using topological sort — tasks with no unresolved dependencies form a wave. During this computation, explicitly detect dependency cycles (cases where the `_DependsOn:` graph is not a DAG).
   - If any cycle is detected, **STOP execution immediately**. Do not start any wave.
   - Inform the user that `.spec-workflow/specs/{spec-name}/tasks.md` contains cyclic `_DependsOn:` references. Clearly request that they open `tasks.md`, fix the `_DependsOn:` graph so that it becomes acyclic (DAG), and then rerun `/spec-implement`.
   - Do not attempt to auto-resolve, ignore, or partially execute around cyclic dependencies; always escalate to the user for manual correction.
3. The **next pending wave** is the first wave (in Phase order) containing at least one `[ ]` task

**Single-task wave**: If the wave contains only one task, process it as before (sequential flow).

**Multi-task wave**: If the wave contains multiple tasks, process them in parallel:
- Mark ALL tasks in the wave from `[ ]` to `[-]` in tasks.md
- Prepare worktrees for all tasks (step 3.7)
- Launch parallel-workers in resource-aware batches (step 4)

**リソース適応型並列制御**: Multi-task wave を処理する前に、`resource-aware-parallelism.md` のリソース検出スニペットを実行し `MAX_HEAVY_AGENTS` を取得する。wave 内のタスク数が `MAX_HEAVY_AGENTS` を超える場合は、wave を `MAX_HEAVY_AGENTS` 個ずつの**サブバッチ**に分割し、各サブバッチを逐次処理する。`MAX_HEAVY_AGENTS=1` の場合は全タスクを逐次実行する。

サブバッチ分割例:
- wave 6タスク, MAX_HEAVY_AGENTS=3 → サブバッチ [3, 3]
- wave 4タスク, MAX_HEAVY_AGENTS=2 → サブバッチ [2, 2]
- wave 3タスク, MAX_HEAVY_AGENTS=1 → サブバッチ [1, 1, 1]（逐次実行）

> Note: multi-task wave では、複数タスクが同時に `[-]`（進行中）になることは **意図された正常な動作** です。これは `implement-task` プロンプト等の「Only one task should be in-progress at a time」ガイダンスの明示的な例外です。

**Wave 計算時の PhaseReview 除外**: `_PhaseReview: true` のタスクは wave 計算から常に除外する。PhaseReview はフェーズ内の全通常タスク完了後に単独で処理する。

**No `_DependsOn:` metadata**: If no tasks in the Phase have `_DependsOn:`, all non-PhaseReview tasks form Wave 0 and are processed as a single multi-task wave in **parallel**. Mark them from `[ ]` to `[-]` together, following the same multi-task wave rules described above.

**Multi-task wave の per-task 処理**: wave 内の各タスクは、steps 3-8（worktree 作成 → parallel-worker → UT検証 → review-worker → log → merge/cleanup → mark `[x]`）を**タスクごとに独立して**実行する。各タスクは専用の worktree/branch で作業し、完了時に個別にマージする。wave 内の全タスクが完了（または失敗）した後に次の wave に進む。

### 2. Discover Existing Work

Before writing any code, search implementation logs to understand what's already been built. This prevents duplicate endpoints, reimplemented components, and broken integrations.

Implementation logs live in: `.spec-workflow/specs/{spec-name}/Implementation Logs/`

**Search with grep** (fast, recommended):
```bash
grep -r "GET\|POST\|PUT\|DELETE" ".spec-workflow/specs/{spec-name}/Implementation Logs/"
grep -r "component\|Component" ".spec-workflow/specs/{spec-name}/Implementation Logs/"
grep -r "function\|class" ".spec-workflow/specs/{spec-name}/Implementation Logs/"
grep -r "integration\|dataFlow" ".spec-workflow/specs/{spec-name}/Implementation Logs/"
```

**Or read markdown files directly** to examine specific log entries.

Search at least 2-3 different terms to discover comprehensively. If you find existing code that does what your task needs, reuse it instead of recreating.

### 3. Read Task Guidance

Look at the task's `_Prompt` field for structured guidance:
- **Role**: The developer persona to adopt
- **Task**: What to build, with context references
- **Restrictions**: Constraints and things to avoid
- **_Leverage**: Existing files to reuse
- **_Requirements**: Which requirements this implements
- **_Evidence**: EV-{category}-{NNN} IDs that scope the existing-code context (`.claude-plugin/rules/evidence-coverage.md`). For each listed ID, resolve to `.spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md` and pass the resolved paths to the TDD subagent. Do **not** list evidence files that are not referenced by this task's `_Evidence` line — those belong to other tasks
- **Success**: How to know you're done

### 3.5 Phase Review Tasks

If the task has `_PhaseReview: true_`, **skip the TDD cycle (steps 4-5)** and instead:

#### 3.5.1 Run Tests

Run the test command appropriate for the detected project type (see quality-checks.md):

```bash
# Rust / Leptos
cargo test --quiet

# .NET
dotnet restore
dotnet build --no-restore -warnaserror
dotnet test --no-build --verbosity quiet
```

- **All pass** → proceed to 3.5.2
- **Failures** → analyze the failing test errors and identify the root cause task:
  - **Root cause is a task within the current Phase** → revert the root cause task from `[x]` to `[-]`, and revert the PhaseReview task from `[-]` to `[ ]`. Re-run the root cause task from step 4.
  - **Root cause is a task from a prior Phase** → escalate to the user (prior Phase fix is needed, impact scope must be assessed)

#### 3.5.1.5 Integration Verification (統合検証)

ユニットテスト通過後、Phase の成果物が統合レベルで動作することを検証する。
コマンド定義は `quality-checks.md` の「Integration Verification」セクションを参照。

**Step A: プロジェクトタイプ検出**

| 検出条件 | タイプ |
|----------|--------|
| `Cargo.toml` に `[package.metadata.leptos]` | Leptos フルスタック |
| `Cargo.toml` に `axum` / `actix-web` / `rocket` 依存 | Rust API |
| `*.csproj` に `BlazorWebAssembly` / `Microsoft.AspNetCore.Components.WebAssembly` | .NET Blazor フルスタック |
| `*.sln` or `*.csproj` 存在（Cargo.toml なし） | .NET API |
| `package.json` 存在 | Node.js |
| いずれにも該当しない | Generic（ビルドのみ検証） |

**Step B: ビルド検証（必須）**

成果物のビルドが成功することを確認する。コマンドはプロジェクトタイプに応じて `quality-checks.md` を参照。

**Step C: 統合テスト実行**

統合テストファイルが存在する場合に実行。存在しない場合の判定（**このルールに厳密に従うこと**）:
- design.md の Excluded Test Environments で当該環境が明示的に除外 → SKIP (設計時除外)
- test-design.md に統合テスト仕様が存在する（仕様あり） → FAIL (実装漏れ)
  - 「仕様あり」の判定: test-design.md に `## Integration Test Specifications` 見出しが存在し、かつそのセクション内に `### IT-` で始まる見出しが 1 件以上ある場合
- 上記条件を満たす仕様が存在しない（仕様なし） → SKIP (設計上不要)

**Step D: スモークテスト（API プロジェクトのみ）**

サーバを一時起動し、ヘルスチェックエンドポイントへの疎通を確認する。外部依存（DB等）で起動不可の場合は FAIL (環境不備)（SKIP は許可しない）。

**結果判定:**

| 結果 | アクション |
|------|----------|
| PASS | 3.5.2 Expert Team Review に進む |
| FAIL (ビルド) | ビルドエラーを分析、根本原因タスクを特定。Phase 内タスク → `[x]` を `[-]` に戻して差し戻し、PhaseReview を `[ ]` に戻す。根本原因タスクの step 4 から再実行 |
| FAIL (統合テスト) | 失敗テストを分析、根本原因タスク特定。Phase 内タスク → 差し戻し、前 Phase → ユーザーエスカレート |
| FAIL (スモーク) | 起動ログを分析し根本原因特定、差し戻し |
| FAIL (環境不備) | 必須ツール・ランタイム未インストール。不足ツールをユーザーに報告し、design.md / test-design.md の Required Tools テーブルの Install Command を提示。実装を停止（STOP） |
| FAIL (実装漏れ) | test-design.md にテスト仕様が定義されているのにテストファイルが存在しない。テスト実装の漏れとしてユーザーに報告 |
| SKIP (設計上不要) | テスト仕様自体が設計書に存在しない場合のみ（例: 統合テスト未定義、ヘルスチェック未定義）。ログに SKIP 理由を記録し、3.5.2 に進む。Expert Team Review で補完 |
| SKIP (設計時除外) | design.md の「Excluded Test Environments」で明示的に除外されたテスト。除外理由をログに記録し、3.5.2 に進む |

**注意**: 環境がない、サーバー起動が必要、Chrome が必要 等の理由で「SKIP」を選択してはならない。test-design.md / design.md の Required Tools に Required=Yes で記載されたツールやランタイムが不足している場合は、常に上記の「FAIL (環境不備)」として扱い、実装を停止（STOP）すること（quality-checks.md の Step C/D に SKIP と記載がある場合も同様）。

統合検証の結果（各ステップの PASS/FAIL/SKIP）は、3.5.2 の Expert Team Review に入力として渡すこと。

> **アーキテクチャ不変条件テスト**: Rust: `tests/architecture.rs`（`/generate-arch-tests` で生成）が存在する場合、step 3.5.1 の `cargo test` で自動実行される。.NET: NetArchTest.Rules / ArchUnitNET によるアーキテクチャテストが存在する場合、`dotnet test` で自動実行される。依存方向違反が検出された場合はテスト失敗として扱い、根本原因タスクの特定と差し戻しを行う。テストが存在しない場合、かつ design.md に `## Module Boundaries` セクションが存在する場合は、アーキテクチャテストの追加をユーザーに提案する。

#### 3.5.1.6 CVE Audit (依存脆弱性監査)

Expert Team Review の前に、依存ライブラリの脆弱性を機械的に検査する。

**Step A: 監査ツール実行**

| プロジェクトタイプ | 検出条件 | 監査コマンド |
|----------------|----------|------------|
| Rust | `Cargo.lock` 存在 | `cargo audit` |
| .NET | `*.csproj` 存在 | `dotnet list package --vulnerable --include-transitive` |
| Node.js (npm) | `package-lock.json` 存在 | `npm audit` |
| Node.js (Yarn) | `yarn.lock` 存在 | `yarn audit`（Yarn v1）または `yarn npm audit`（Yarn v2+） |
| 複合 | 複数のロックファイル/プロジェクトファイル存在 | 該当する監査コマンドをそれぞれ実行 |

ロックファイルが存在しない場合は SKIP（新規プロジェクトで依存未解決）。

`cargo audit` 未インストールの場合:
```bash
cargo audit --version 2>&1 || echo "NOT_INSTALLED"
```
未インストールなら `cargo install cargo-audit` をユーザーに提案（Step 0.3 のユーザー承認ルールに従う）。インストールを拒否された場合は SKIP とし、Expert Team Review のセキュリティ担当に委ねる。

**Step B: 結果分類**

| 重大度 | アクション |
|-------|----------|
| Critical / High | CVE_FOUND リストに追加 |
| Medium/Moderate / Low | 警告ログに記録 |

※ `cargo audit` の `medium` および `npm audit` の `moderate` は同一の重大度として扱う。

**Step C: 結果の引き渡し**

CVE 監査結果を Expert Team Review の入力に追加する:

```
CVE Audit Results:
- cargo audit: {PASS / N件の脆弱性検出 / SKIP}
- npm audit: {PASS / N件の脆弱性検出 / SKIP / N/A}
- Critical/High CVEs: {CVE_FOUND リスト or なし}
  - 各エントリ形式: CVE-ID | パッケージ名 | 現バージョン | 修正済みバージョン | 推奨対応
```

Expert Team Review のセキュリティ担当がこの結果を踏まえてレビューし、Verdict（PASS / NEEDS_REWORK / BLOCK）を判定する。CVE の深刻度と対応方針の最終判断はセキュリティ担当に委ねる。

CVE 監査結果は統合検証結果と共に 3.5.2 の Expert Team Review に入力として渡すこと。

#### 3.5.2 Expert Team Review (multi-perspective review)

Phase 完了時は、コミット前に専門家チームによる多角的コードレビューを実施する。詳細は `/phase-review-team` スキルを参照。

**リソース制限**: 並列起動前に `resource-aware-parallelism.md` のリソース検出を実行し、`MAX_LIGHT_AGENTS` に基づいて専門家をバッチ分割起動する。詳細は `/phase-review-team` スキル内の手順を参照。

**チーム編成（最大5名を並列起動）:**

| Role | Perspective |
|------|-------------|
| 実装担当 | 仕様書にある機能を網羅しているか、仕様を逸脱していないか |
| セキュリティ担当1 | 認証、認可、データ漏洩 |
| セキュリティ担当2 | OWASP TOP 10、最新の CVE |
| パフォーマンス担当 | ボトルネック、計算量、リソース効率 |
| 品質・保守性担当 | テストカバレッジ、読みやすさ、命名規則、DRY 原則 |

**手順:**

1. `MAX_LIGHT_AGENTS` に基づき、5名の専門家を Agent tool でバッチ分割起動（リソースが十分な場合は全員同時並列。プロンプト詳細は `/phase-review-team` スキルを参照）
2. 各担当は独立して調査し、具体的な問題箇所と改善案を報告
3. リーダー（オーケストレーター）は各報告を統合し、優先度付き最終レポートを作成
4. レポートを `.spec-workflow/specs/{spec-name}/reviews/phase-{phase-number}-review.md` に保存

**Verdict に基づく分岐:**

| Verdict | Condition | Action |
|---------|-----------|--------|
| **PASS** | P0 = 0, P1 = 0 | 3.5.3 に進む（review-worker にコミットを委譲） |
| **NEEDS_REWORK** | P0 = 0, P1 > 0 | P1 の発見事項を parallel-worker に差し戻し。修正後、変更箇所のみ再レビュー（最大2回） |
| **BLOCK** | P0 > 0 | ユーザーにエスカレート |

#### 3.5.3 Code Review + Commit (delegate to review-worker)

Expert Team Review で PASS 後、PhaseReview 専用の Worktree を作成し、review-worker にコミットを委譲する:

```bash
# PhaseReview 専用 Worktree を作成
WORKTREE_PATH=".worktrees/{spec-name}/phase-review-{phase-number}"
BRANCH="review/{spec-name}/phase-{phase-number}"

if git worktree list | grep -q "$WORKTREE_PATH"; then
  echo "Reusing existing worktree: $WORKTREE_PATH"
else
  git worktree add "$WORKTREE_PATH" -b "$BRANCH"
  echo "Created new worktree: $WORKTREE_PATH (branch: $BRANCH)"
fi
```

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:review-worker",
  description: "Phase review: final commit",
  prompt: `⚠️ INDEPENDENT REVIEW REQUIRED ⚠️
    Expert team review has already been completed, but you MUST perform your own independent review.
    Previous review results are reference only — your job is to find problems, not confirm prior approval.

    As a phase review, please perform a final review and commit all files changed in the current Phase.

    Project path: {project-path}
    Spec name: {spec-name}
    Phase: {phase-number}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}
    Changed files: {all files changed in this phase}

    **Important**: Always run \`cd {WORKTREE_PATH}\` before reviewing and committing.

    Integration Verification Results (from step 3.5.1.5):
    - Build: {integration-verification.build}
    - Integration Tests: {integration-verification.integration-tests}
    - Smoke Test: {integration-verification.smoke-test}

    Expert team review report: .spec-workflow/specs/{spec-name}/reviews/phase-{phase-number}-review.md (reference only).
    Focus on final quality checks (rustfmt, clippy, tests) and commit.
    Review across all aspects (A–G) and report review_action as commit / rework / escalate.
    Include integration-verification results in your completion report.
    G: API Documentation — docs/openapi.yaml が存在し、API関連ファイルに変更がある場合、
    openapi.yaml が更新されているか確認。未更新の場合は /generate-api-docs の実行を推奨として報告。
    The commit message should summarize the Phase's deliverables.`
})
```

- **review_action: commit** → proceed to 3.5.4
- **review_action: rework** → follow the normal rework flow (identify the root cause task and send it back to that task's parallel-worker)
- **review_action: escalate** → follow the normal escalate flow

> **CI フィードバック**: CI ワークフローが `/setup-ci` で構成されている場合、テスト結果サマリーが PR コメントに自動投稿される（sticky comment 方式で更新）。Phase Review 後に `/create-pr` で PR を作成した際、CI 実行結果を PR コメントから確認可能。`--no-pr-comments` で無効化されている場合はコメント投稿なし。

#### 3.5.4 Complete

review-worker has committed. Merge the PhaseReview worktree and clean up:

```bash
# Merge PhaseReview worktree branch
git merge --no-ff "$BRANCH" -m "merge: integrate phase-{phase-number} review"

# Remove the worktree
git worktree remove "$WORKTREE_PATH"
git branch -d "$BRANCH"
```

Proceed to step 7 (Log).

### 3.6 TDD Skip Tasks

If the task has `_TDDSkip: true_` (tasks that cannot be tested such as project initialization, Dockerfile, migrations, etc.), **skip the TDD cycle (step 4) and UT quality verification (step 5)** and instead:

1. Instruct parallel-worker to implement directly without TDD (add `_TDDSkip: true, so skip the TDD cycle and perform direct implementation + quality checks only` to the prompt)
2. After parallel-worker completes, skip step 5 (UT) and step 5.5 (code-simplifier) and proceed to step 6 (review-worker)
3. review-worker reviews across all aspects as usual (but skip category E: final test verification)

### 3.7 Prepare Worktrees

Prepare a git worktree for each task in the wave. This allows parallel-worker and review-worker to work safely in independent working directories without affecting the orchestrator's main branch.

**For multi-task waves**: Create worktrees for ALL tasks in the wave before launching any parallel-workers.

```bash
WORKTREE_PATH=".worktrees/{spec-name}/{task-id}"
BRANCH="impl/{spec-name}/{task-id}"

# Check for existing worktree (reuse during rework cycle)
if git worktree list | grep -q "$WORKTREE_PATH"; then
  echo "Reusing existing worktree: $WORKTREE_PATH (branch: $BRANCH)"
else
  git worktree add "$WORKTREE_PATH" -b "$BRANCH"
  echo "Created new worktree: $WORKTREE_PATH (branch: $BRANCH)"
fi
```

Retain `WORKTREE_PATH` and `BRANCH` as variables and pass them to the agent prompts in steps 4 and 6.

### 4. TDD Implementation (parallel-worker) [AGENT CALL REQUIRED]

> ⛔ **Do not write code yourself. Always call the `parallel-worker` agent.**

Delegate the entire TDD cycle (Red → Green → Refactor + quality checks) to the `parallel-worker` agent. parallel-worker only implements; **it does not git commit** (that is review-worker's responsibility).

**Wave parallel execution**: For multi-task waves, apply resource-aware parallelism control（`resource-aware-parallelism.md` 参照）。並列起動前にリソース検出スニペットを実行し `MAX_HEAVY_AGENTS` を取得する。wave 内のタスク数が `MAX_HEAVY_AGENTS` を超える場合はサブバッチに分割し、各サブバッチ内のエージェントのみ同時起動する。各サブバッチの完了を待ってから次のサブバッチを起動し、全サブバッチ完了後に step 5 へ進む。wave 内タスク数が `MAX_HEAVY_AGENTS` 以下の場合は全エージェントを同時起動する。

リソース検出結果をログに記録する:
```
[resource-check] CPU: {CPU_CORES} cores, Free memory: {FREE_MEM_MB}MB, MAX_HEAVY_AGENTS: {MAX_HEAVY_AGENTS}
[wave-split] Wave has {N} tasks, processing in {M} sub-batch(es) of {sizes}
```

Each agent works in its own isolated worktree.

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:parallel-worker",
  description: "TDD: Red-Green-Refactor implementation",
  prompt: `Implement the following task using TDD (Red→Green→Refactor).

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}
    Task prompt:
    {paste the full _Prompt content here}

    Test focus areas: {_TestFocus content from task, if available}
    Leverage files: {_Leverage file paths from task}
    Evidence files: {for each EV-{category}-{NNN} in the task's _Evidence line, pass .spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md. Pass an empty list if no _Evidence line (e.g. Phase 0 setup or legacy spec).}
    Design doc path: {project-path}/.spec-workflow/specs/{spec-name}/design.md
    Test design doc path: {project-path}/.spec-workflow/specs/{spec-name}/test-design.md

    **Important**: Always start by running \`cd {WORKTREE_PATH}\` before beginning implementation. Changes directly in the main repository are prohibited.

    Base branch: {BASE_BRANCH}

    Steps:
    1. RED: Write failing tests (see /spec-impl-test-write skill)
    2. Confirm all tests fail by running them
    3. GREEN: Write the minimum code to make the tests pass (see /spec-impl-code skill)
    4. Confirm all tests pass by running them (retry up to 3 times on failure)
    5. REFACTOR: Clean up the code (see /spec-impl-review skill)
    6. Confirm all tests still pass after refactoring
    7. Run the quality checks defined in quality-checks.md for the detected project type:
       - Rust: rustfmt, clippy, cargo test, dependency analysis tools
       - .NET: dotnet format, dotnet build -warnaserror, dotnet test, dotnet list package --vulnerable
    8. Run mutation testing on the diff (Rust: cargo-mutants, .NET: Stryker.NET — if installed)

    Apply diagnostic-reasoning.md DR1-DR6 and failure-taxonomy.md FC1-FC6 throughout retries. Create and maintain \`{WORKTREE_PATH}/diagnosis.md\` per DR2 + FC4 (each attempt entry carries a \`Failure category\` line). Apply DR6 DIVERGENT if the most recent 2 failed attempts in the current phase share the same main failure_category (FC5).

    Include the following in the completion report:
    For Rust projects:
    - tests: pass|fail
    - rustfmt: pass|fail
    - clippy: pass|fail
    - mutation_testing: pass|warn|skip
    For .NET projects:
    - tests: pass|fail
    - dotnet_format: pass|fail
    - dotnet_build: pass|fail
    - dotnet_test: pass|fail
    - stryker: pass|warn|skip
    - test_file_paths: list of test files
    - implementation_file_paths: list of implementation files
    - changed_files: list of all changed files (MUST NOT include diagnosis.md or state.md)
    - divergent_applied: true|false (optional — include only when any retry occurred)
    - diagnosis: include when any retry occurred — summary of the final successful approach per DR2 + FC4 with fields:
      - root_cause: string
      - responsible_files: list of file paths or code locations (e.g., ["src/foo.rs:42"]) — unified across workers
      - approach: string
      - failure_category: FC1 main category (compile_error | test_failure | quality_check_failure | spec_mismatch)
      - failure_subcategory: FC1 subcategory (optional)
`
})
```

Capture from the result: **status**, **test_file_paths**, **implementation_file_paths**, **changed_files**, **mutation_testing**, **stryker** (.NET mutation testing result), **divergent_applied** (if present), and **diagnosis** (if present — retain for diagnostic_history accumulation in rework cycles; failure_category is required in diagnosis per FC2).

Branch based on parallel-worker's `status`:

- **status: completed** → proceed to step 5
- **status: retry_exhausted** → parallel-worker has stopped after exhausting retries. Report the following to the user:
  - Which phase (RED/GREEN/REFACTOR/quality_check) failed
  - The last error message
  - The `failure_category` / `failure_subcategory` (FC1) of the final attempt
  - Whether DR6 DIVERGENT was applied (`divergent_applied`) — if `true`, note that the worker has already tried a fundamentally different premise
  - Files partially created

  User decision: fix manually and resume / skip the task and move on / revisit the design

  **Resume flow (after user decision):**

  | Choice | Steps |
  |--------|-------|
  | **Fix manually and resume** | After the user manually fixes files inside `{WORKTREE_PATH}`, resume from step 5 (UT). Do not reset the rework counter (carry over the cumulative count) |
  | **Skip the task** | Append `<!-- BLOCKED: {reason} -->` as a comment to the relevant task row in tasks.md, revert `[-]` to `[ ]`, and proceed to the next `[ ]` task |
  | **Revisit the design** | Follow the same flow as `review_action: escalate` (user decides whether to adjust within the design.md scope or do a Phase Reset) |

### 5. Unit Test Quality Verification [AGENT CALL REQUIRED]

> ⛔ **Do not add tests yourself. Always call the appropriate test engineer agent.**

> **Agent selection**:
> - Leptos フロントエンドコンポーネント（`#[component]`、`view!`、signal、memo、`#[server]`、`src/pages/`、`src/components/`）が対象なら `frontend-test-engineer`
> - それ以外の Rust ユニットテスト補完なら `unit-test-engineer`
> - C#/.NET プロジェクト（`.cs`、`.csproj` 存在）は `unit-test-engineer`（C#/xUnit セクション対応済み）。Blazor code-behind テストも同エージェントが対応
> - 上記いずれにも該当しないプロジェクトは同じ4カテゴリ基準を満たす汎用サブエージェントを使う

Verify the quality of tests written during the TDD cycle and supplement any missing test perspectives. TDD is "a development method that writes tests first to drive implementation"; this step independently verifies the quality of the implemented code.

Pass the implementation files to the selected test engineer agent and have it confirm coverage of required test perspectives (happy path, boundary values, exception handling, edge cases).

Leptos frontend task detection hints:
- `_Prompt` に `#[component]`、`view!`、signal、memo、`#[server]` が含まれる
- 対象ファイルが `src/pages/`、`src/components/`、`src/server_fns/` 配下にある
- `Cargo.toml` に `[package.metadata.leptos]` があり、実装が UI ロジックを含む

Select the test engineer agent based on the detection hints above, then call:

```javascript
// Leptos frontend task の場合:
//   subagent_type: "spec-workflow-mcp:frontend-test-engineer"
// それ以外の Rust task の場合:
//   subagent_type: "spec-workflow-mcp:unit-test-engineer"
Agent({
  subagent_type: "spec-workflow-mcp:frontend-test-engineer",  // or "spec-workflow-mcp:unit-test-engineer"
  description: "UT: Verify test quality",
  prompt: `Verify the unit test quality for the following implementation files.

    Worktree path: {WORKTREE_PATH}
    Implementation files: {implementation_file_paths from step 4}
    Existing test files: {test_file_paths from step 4}
    Test focus areas: {_TestFocus content from task, if available}

    **Important**: Always run \`cd {WORKTREE_PATH}\` before starting work. All file paths are relative to the worktree.

    Check against required test perspectives (happy path, boundary values, exception handling, edge cases)
    and add any missing test cases.
    Be careful not to duplicate existing tests.
    If Test focus areas are specified, prioritize those verification points.
    If this is a Leptos frontend task, do not test \`view!\` output directly. Extract logic if needed and test the extracted logic instead.

    The completion report must include:
    - ut_action: added (tests were added) | verified_sufficient (no additions needed, already sufficient)
    - added_tests: list of added test function names (if added)
    - added_to_files: list of modified test files (if added)
    - modified_implementation_files: list of implementation files modified during logic extraction (empty if none)
    - coverage_summary: happy path: N cases, boundary values: N cases (+M added), exception handling: N cases (+M added), edge cases: N cases (+M added)
    - excluded_as_e2e: list of concerns intentionally excluded as E2E territory (empty if none)`
})
```

Capture from the result: **ut_action**, **added_tests**, **added_to_files**, **modified_implementation_files**, **coverage_summary**, **excluded_as_e2e**.

- `ut_action: added` → run the tests, confirm all pass, and pass the additional info to step 5.5
- `ut_action: verified_sufficient` → proceed directly to step 5.5

### 5.5. Code Simplification (code-simplifier) [AGENT CALL REQUIRED]

> ⛔ **Do not clean up code yourself. Always call the `code-simplifier` agent.**

After TDD and UT verification are complete, improve code clarity and maintainability while preserving functionality.
The output of `code-simplifier` is comprehensively reviewed by the subsequent step 6 (review-worker), so no dedicated review step is added.

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:code-simplifier",
  description: "Simplify: improve clarity without changing behavior",
  prompt: `Simplify and refine the following implementation files while preserving functionality.

    Worktree path: {WORKTREE_PATH}
    Implementation files: {implementation_file_paths from step 4 + modified_implementation_files from step 5}
    Test files: {test_file_paths from step 4 + added_to_files from step 5}

    **Important**: Always run cd {WORKTREE_PATH} before starting work.

    After completing, run cargo test to confirm all tests pass.
    The completion report must include:
    - simplify_result: simplified (changes made) | no_change (no changes)
    - changed_files: list of changed files (if simplified)
    - test_result: pass | fail`
})
```

Capture from the result: **simplify_result**, **changed_files** (if simplified), **test_result**.

- `test_result: pass` → proceed to step 6 (pass `changed_files`)
- `test_result: fail` → roll back only the files in `changed_files` using `git restore -- {changed_files}`, then proceed to step 6 (record as `simplify_result: reverted`)
- `simplify_result: no_change` → proceed directly to step 6

### 6. Code Review + Commit (review-worker) [AGENT CALL REQUIRED]

> ⛔ **Do not commit yourself. Always call the `review-worker` agent.**

Delegate code review and commit to the `review-worker` agent. Separating implementation (parallel-worker) and review (review-worker) responsibilities ensures quality.

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:review-worker",
  description: "Review and commit",
  prompt: `⚠️ INDEPENDENT REVIEW REQUIRED ⚠️
    This code has passed through parallel-worker (TDD), test engineer (frontend-test-engineer or unit-test-engineer), and code-simplifier.
    However, you MUST NOT assume it is correct because previous steps reported success.
    Previous results are provided as reference ONLY — your independent, critical review is mandatory.
    Treat this as if you are seeing the code for the first time. Your job is to find problems, not confirm success.

    Review the following changes and commit if they meet quality standards.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}
    Changed files: {changed_files from step 4 + added_to_files from step 5 + modified_implementation_files from step 5 + changed_files from step 5.5}
    Task prompt: {paste the full _Prompt content here}

    **Important**: Always run \`cd {WORKTREE_PATH}\` before reviewing and committing.

    Previous step results (reference only — do not let these bias your review):
    UT quality verification results (step 5):
    - ut_action: {ut_action from step 5}
    - added_tests: {added_tests from step 5}
    - modified_implementation_files: {modified_implementation_files from step 5}
    - coverage_summary: {coverage_summary from step 5}
    - excluded_as_e2e: {excluded_as_e2e from step 5}

    Simplification results (step 5.5):
    - simplify_result: {simplify_result from step 5.5} (one of: simplified / no_change / reverted)
    - changed_files: {changed_files from step 5.5 (only if simplified)}

    Notes:
    - Tests listed in added_tests have already been quality-verified by the appropriate test engineer (frontend-test-engineer or unit-test-engineer).
      In category E (final test verification), do not flag these tests as "insufficient".
    - excluded_as_e2e lists concerns intentionally deferred to E2E testing. Do not flag these as missing unit test coverage.
      However, style, naming, and sensitive data checks should be performed as usual.
    - Files with simplify_result: simplified have been confirmed by code-simplifier to preserve functionality and pass tests.
      In category A (style), evaluate the simplified code as the final form.

    ## Review Checklist (各カテゴリの具体的な確認項目)
    以下の各質問に対して、具体的な回答を observations に記録すること:

    **A: Style** — 命名は意図を正確に表現しているか? プロジェクト既存コードとスタイルは一貫しているか?
    **B: Design** — unwrap() を不適切に使用していないか? 各関数は単一責任か? 依存方向は正しいか?
    **C: Security** — 外部入力はバリデーションされているか? レスポンスに内部情報が漏洩していないか? SQL はクエリビルダー経由か?
    **D: Spec** — _Prompt の Success 基準を1つずつ確認し、各基準の充足/不足を明示すること
    **E: Tests** — テストは実装と同期しているか? 値の検証（is_ok() だけでなく具体値の確認）があるか?
    **F: Design Conformance** — design.md に未定義のフィールド/エンドポイントが追加されていないか?
    **G: API Documentation** — API変更（エンドポイント追加・変更・型変更）がある場合、\`docs/openapi.yaml\` の更新を確認。openapi.yaml が存在しない場合はスキップ

    ⚠️ 各カテゴリの observations を完了レポートに必ず含めること。
    「問題なし」の場合でも、何を確認して問題なしと判断したかを記載する。
    review_action が commit であっても observations と auto_fixed は必須。
    report review_action as one of: commit / rework / escalate.`
})
```

The orchestrator branches based on review-worker's `review_action`:

#### review_action: commit (all aspects pass)
→ proceed to step 7

#### review_action: rework (findings in B:design / C:security / E:tests)

Send back to parallel-worker with the review-worker's `findings`:

**Worktree handling**: In a rework cycle, **reuse the same worktree** created in step 3.7. Do not create a new worktree. The `git worktree list` check in step 3.7 ensures this.

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:parallel-worker",
  description: "Rework: fix review findings ({N}/3)",
  prompt: `The review found the following issues. Please fix them.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}

    **Important**: Always run \`cd {WORKTREE_PATH}\` before making fixes.

    rework_attempt: {N} / 3 (maximum 3 times)

    Current findings:
    {findings from review-worker}

    Diagnostic history (prior rework attempts — DO NOT repeat failed approaches):
    {diagnostic_history — use "(First rework — no prior attempts)" on first rework, accumulated on subsequent reworks}

    Apply diagnostic-reasoning.md DR1-DR6 and failure-taxonomy.md FC1-FC6:
    - Before writing any fix, read diagnosis.md and append a DR2 + FC4-formatted attempt entry (\`### Attempt {N}/3\`) under the \`## Rework Cycle\` heading — do not create a separate \`## Diagnosis\` section. Include the \`Failure category\` line
    - Your diagnosis MUST identify a different root cause or approach from the diagnostic history above (DR4)
    - **DR6 DIVERGENT check**: If the most recent 2 entries in diagnostic_history share the same main \`failure_category\` (per FC5), insert a \`### Divergent Analysis (before Attempt {N}/3)\` block above the Attempt heading, articulating the shared implicit assumption and how this attempt invalidates it. The Approach must fundamentally differ, not be a parameter tweak
    - On the final attempt (3/3), call advisor() with your diagnosis before implementing (DR5). Include the Divergent Analysis block if applicable

    Note: This is rework attempt {N}. The maximum is 3; if unresolved after 3 attempts, the issue will be escalated to the user.
    Fix all findings at once. On the final attempt (3/3), choose the minimum fix that will pass review.

    After fixing, run quality checks (rustfmt + clippy + cargo test) to confirm all pass.
    Include changed_files, diagnosis summary (with failure_category), and divergent_applied in the completion report.`
})
```

**Diagnostic history accumulation (orchestrator responsibility)**:

The orchestrator maintains a text block called `diagnostic_history` for each task's rework cycle. Follow these steps:

1. **Before the first rework**: Initialize `diagnostic_history` with the marker string `"(First rework — no prior attempts)"` (this marker makes the prompt clearer than an empty field, which an LLM may misread as "forgot to fill in")
2. **After each rework attempt**: Extract from parallel-worker's completion report:
   - The diagnosis summary fields: `root_cause`, `responsible_files` (list), `approach`, `failure_category`, `failure_subcategory` (optional) — these names are unified across parallel-worker and wave-harness-worker outputs per `failure-taxonomy.md` FC2
   - The `divergent_applied` flag (if present)
   - The quality check results (pass/fail)
3. **Append to diagnostic_history in DR2 + FC4 format** (fields come from the worker's completion report; if a field is absent, note it as `(not reported)`):
   ```
   ### Attempt {N}
   - **Root cause**: {diagnosis.root_cause from worker's report}
   - **Responsible**: {diagnosis.responsible_files joined, or "(not reported)"}
   - **Expected behavior**: {if available in the diagnosis or review findings, otherwise "(not reported)"}
   - **Approach**: {diagnosis.approach — what the worker changed}
   - **Failure category**: `{diagnosis.failure_category}` / `{diagnosis.failure_subcategory or ""}`
   - **Result**: {review-worker's verdict — commit/rework/escalate + specific findings}
   ```
   If `divergent_applied: true`, add a line `- **Divergent applied**: true` after the `Failure category` line. This lets the next attempt know a DIVERGENT attempt has already been spent.
4. **Pass the accumulated diagnostic_history** in the next rework prompt (see template above)

Example after 2 failed rework attempts (same `failure_category` twice → DR6 DIVERGENT required on Attempt 3):
```
### Attempt 1
- **Root cause**: UserRepo.create() returns raw diesel::Error, not AppError
- **Responsible**: src/repos/user.rs:42
- **Expected behavior**: All repository methods return Result<T, AppError> per design.md §3.2
- **Approach**: Added From<diesel::Error> impl for AppError
- **Failure category**: `spec_mismatch` / `design_conformance_violation`
- **Result**: rework — B:design: return type still uses String not AppError in update() and delete()

### Attempt 2
- **Root cause**: 3 repository methods (create, update, delete) all return String errors; attempt 1 only fixed create
- **Responsible**: src/repos/user.rs:42, src/repos/user.rs:58, src/repos/user.rs:73
- **Expected behavior**: All 3 methods return Result<T, AppError> consistently
- **Approach**: Converted all 3 methods to return AppError, added error mapping in handler layer
- **Failure category**: `spec_mismatch` / `design_conformance_violation`
- **Result**: {pending — will be filled after review}
```

The orchestrator manages the rework_attempt counter. After the fix, re-run step 5 (UT quality verification) → step 6 (review). **The rework → re-review cycle has a maximum of 3 times**. If unresolved after 3 times, report to the user with the remaining findings.

**Counter scope:**
- The counter resets **per task** (per task-id)
- Tasks with `_PhaseReview: true` also allow up to 3 reworks
- When a review rework occurs during PhaseReview, identify the root cause task and fix it, but that fix also consumes the rework counter (recorded as the PhaseReview's rework_attempt)
- After resuming from a manual fix following `retry_exhausted`, carry over the counter without resetting it

#### review_action: escalate (D:spec mismatch, F:design conformance violation)

A mismatch with the approved design.md or a specification interpretation discrepancy has been detected. Present review-worker's `findings` to the user and ask for a decision.

**Important: Do not modify design.md during the implementation phase.** If design changes are needed, discard all implementation so far and redo from Phase 2 (spec-design). Therefore, escalate responses are limited to "adjust the implementation within the scope of design.md".

**Response flow:**

1. Present findings to the user and confirm **how to adjust within the scope of design.md**
2. Append the user's response to the `_Prompt`'s Restrictions for the relevant task:
   ```
   Example addition to _Prompt:
   Restrictions: ... | [escalate response] review-worker finding: Use UserDto instead of UserDetailDto. last_login_at is not defined in design.md and must not be included
   ```
3. Send back to parallel-worker as a rework (switch from escalate to rework)
4. After the fix, re-run step 5 (UT) → step 6 (review)

The same cycle limit as rework (maximum 3 times) applies. If unresolved after 3 times, it is likely that the design itself has a problem, so propose redoing from Phase 2 to the user.

### 7. Log Implementation (MANDATORY)

Call the `/log-implementation` skill BEFORE marking the task complete. A task without a log is not complete — this is the most commonly skipped step.

Required fields:
- `specName`: The spec name
- `taskId`: The task ID you just completed
- `summary`: Clear description of what was implemented (1-2 sentences)
- `filesModified`: List of files you edited
- `filesCreated`: List of new files — **include test files**
- `statistics`: `{ linesAdded: number, linesRemoved: number }`
- `artifacts` (REQUIRED — include only applicable categories. Pass an empty object `{}` if the implementation has no applicable content):
  - `apiEndpoints`: API routes created/modified (method, path, purpose). For request/response details, refer to design.md
  - `dbMigrations`: Migration names and tables created
  - `models`: Names and locations of Models / DTOs created or modified
  - `integrations`: Connections to external services (only if applicable)
- `reviewProcess` (optional — only record if review-worker was executed. Review results from steps 4–6):
  - `reworkCount`: Number of reworks (use `0` if committed on the first attempt)
  - `reviewOutcome`: Final result — `"commit"` or `"escalated"`
  - `findings`: Only include if reworkCount > 0. Record of each review attempt:
    ```json
    "reviewProcess": {
      "reworkCount": 2,
      "reviewOutcome": "commit",
      "findings": [
        {
          "attempt": 1,
          "categories": ["B:design", "C:security"],
          "summary": "UserRepo not using AppError. Raw string concatenation in SQL query",
          "action": "rework"
        },
        {
          "attempt": 2,
          "categories": ["B:design"],
          "summary": "Repository method return type does not match design.md",
          "action": "rework"
        },
        {
          "attempt": 3,
          "categories": [],
          "summary": "All aspects passed",
          "action": "commit"
        }
      ]
    }
    ```
  - `observations` (optional — review-worker のレビュー観察ログ。tool schema には未定義の拡張フィールド。review-worker の完了レポートの `observations` キーに対応):
    ```json
    "observations": {
      "style": "checked-ok: 命名規則準拠、create_user/UserDto 等",
      "design": "checked-ok: AppError 変換あり、unwrap() なし",
      "security": "checked-ok: クエリビルダー使用、入力バリデーションあり",
      "spec_compliance": "checked-ok: Success 基準3項目すべて充足",
      "test_quality": "checked-ok: 値の具体的検証あり、境界値テストあり",
      "design_conformance": "checked-ok: design.md 定義外の追加なし"
    }
    ```
  - `auto_fixed` (optional — tool schema には未定義の拡張フィールド。review-worker の完了レポートの `auto_fixed` キーをそのまま記録する): 自動修正した Minor 問題のリスト（0件の場合は空配列 `[]`）:
    ```json
    "auto_fixed": [
      { "category": "A:style", "file": "src/handler.rs:45", "description": "unwrap() を map_err() に修正" }
    ]
    ```
  - If reworkCount is 0 (passed on first attempt), `findings` may be omitted. `observations` and `auto_fixed` are optional extension fields (not in tool schema) but recommended for traceability. オーケストレーターは review-worker から受け取った完了レポートの `auto_fixed` 配列をそのまま記録すること:
    ```json
    "reviewProcess": {
      "reworkCount": 0,
      "reviewOutcome": "commit",
      "observations": { "style": "checked-ok: ...", "design": "checked-ok: ...", ... },
      "auto_fixed": []
    }
    ```

**If `/log-implementation` fails:**
- Do not mark the task as `[x]` (completion without a log is incomplete)
- Report the error to the user and confirm whether to record the log manually or retry
- If the `/log-implementation` skill is unavailable: Creating a markdown file manually in the `.spec-workflow/specs/{spec-name}/Implementation Logs/` directory is an acceptable alternative

### 8. Complete the Task

Only after `/log-implementation` returns success:
- Verify all success criteria from the `_Prompt` are met
- Edit tasks.md: Change `[-]` to `[x]`

#### Worktree Merge and Cleanup

After review-worker commits, integrate the worktree branch into the main branch and clean up:

```bash
# Merge the worktree commits into the main branch
git merge --no-ff "$BRANCH" -m "merge: integrate implementation of {task-id}"

# Remove the worktree
git worktree remove "$WORKTREE_PATH"
git branch -d "$BRANCH"
```

Then move to the next pending wave and repeat.

### 9. Final E2E Gate (全Phase完了後)

全 Phase の実装が完了した後（最後の PhaseReview タスクが `[x]` になった後）、最終的な E2E ゲートを実行する。
これは個別 Phase の統合検証（3.5.1.5）とは異なり、**全成果物を統合した最終確認**である。

#### 9.1 トリガー条件

tasks.md 内の全タスク（PhaseReview 含む）が `[x]` になった時点で自動的に開始する。

#### 9.2 検証ステップ

コマンド定義は `quality-checks.md` の「Integration Verification」セクションを参照。

**Step 1: フルビルド検証**

プロジェクト全体のクリーンビルドが成功することを確認する。

```bash
# Rust
cargo build

# Leptos
cargo leptos build

# Node.js
npm run build
```

**Step 2: 全テスト実行**

ユニットテスト + 統合テストの全件を実行する。

```bash
# Rust
cargo test --quiet

# Node.js
npm test
```

**Step 3: 統合テスト実行**

統合テストが存在する場合、明示的に統合テストのみを実行する。

```bash
# Rust
cargo test --tests --quiet

# Node.js
npm run test:integration
```

**Step 4: フルスモークテスト（API プロジェクトのみ）**

Phase Review のスモークテスト（Step D）と同様の手順だが、ヘルスチェックに加えて、
design.md に定義された主要エンドポイントのレスポンス確認も行う。

- ヘルスチェック: `/health`, `/api/health`, `/healthz` への GET リクエスト
- 主要エンドポイント: design.md の API 定義から GET エンドポイントを抽出し、ステータスコードを確認
  - 認証が必要なエンドポイントは 401 が返ることを確認（認証なしで 200 が返る場合はセキュリティ問題）
  - 認証不要なエンドポイントは 200 または 404（データなし）が返ることを確認

**Step 5: E2E テスト実行（コンテナベース — test-design.md 仕様準拠）**

test-design.md の E2E 仕様に基づくテストが存在する場合に実行する（`/spec-e2e-implement` で作成されたテスト）。

```bash
# テスト用コンテナ起動
if [ -f docker-compose.test.yml ]; then
  docker-compose -f docker-compose.test.yml up -d
  # ヘルスチェック待機（最大60秒）
fi
```

| ランナー | 検出条件 | コマンド |
|---------|----------|---------|
| Playwright | `playwright.config.ts` 存在 | `npx playwright test` |
| Rust E2E | `tests/e2e/` ディレクトリ存在 | `cargo test --tests --quiet` |
| Node.js E2E | `package.json` に `test:e2e` | `npm run test:e2e` |

```bash
# テスト用コンテナ停止・クリーンアップ
if [ -f docker-compose.test.yml ]; then
  docker-compose -f docker-compose.test.yml down -v
fi
```

E2E テストファイルが存在しない場合（優先順位順に判定 — **このルールに厳密に従うこと**）:
1. design.md の「Excluded Test Environments」で E2E テストが明示的に除外されている → **SKIP (設計時除外)**（除外理由をログに記録）
2. test-design.md に E2E テスト仕様が定義されている → **FAIL (実装漏れ)**。E2E テストが未実装であることをユーザーに報告
   - 「仕様あり」の判定: test-design.md に `## E2E Test Specifications` 見出しが存在し、かつそのセクション内に `### E2E-` で始まる見出しが 1 件以上ある場合
3. 上記条件を満たす仕様が存在しない → **SKIP (設計上不要)**。ログに理由を記録し続行

**環境がない、サーバー起動が必要、Chrome が必要 等の理由による SKIP は一切許可しない。** これらのツールは Required Tools として Required=Yes で記載され、Step 0 で検証済みであること。

#### 9.3 結果判定

| 結果 | アクション |
|------|----------|
| **PASS** | 全ステップが PASS のみ（SKIP なし） → Step 10 (PR 作成) に進む |
| **PASS (SKIP含む)** | FAIL はなく、結果が PASS と SKIP のみ → Step 10 (PR 作成) に進む。各 SKIP の理由を PR ボディの Notes に記載 |
| **FAIL** | 失敗箇所を分析し、該当 Phase・タスクを特定。タスクを `[x]` から `[-]` に戻し、該当タスクの step 4 から再実行。PhaseReview も `[ ]` に戻す |
| **FAIL (環境不備)** | 必須ツール・ランタイム未インストール。不足ツールをユーザーに報告し、Required Tools テーブルの Install Command を提示。実装を停止 |
| **FAIL (実装漏れ)** | test-design.md にテスト仕様が定義されているのにテストファイルが存在しない。テスト実装の漏れとしてユーザーに報告 |
| **SKIP (設計上不要)** | テスト仕様自体が設計書に存在しない場合のみ。ログに SKIP 理由を記録し続行 |
| **SKIP (設計時除外)** | design.md の「Excluded Test Environments」で明示的に除外されたテストのみ。除外理由をログに記録 |

**注意**: 環境がない、サーバー起動が必要、Chrome が必要 等の理由による SKIP は一切許可しない。

#### 9.4 最終レポート

Final E2E Gate の結果を `.spec-workflow/specs/{spec-name}/reviews/final-e2e-gate.md` に保存する。

```markdown
# Final E2E Gate Report

## Spec: {spec-name}
## Date: {date}

## Results
| Step | Result | Details |
|------|--------|---------|
| Build | PASS/FAIL/SKIP(ビルドコマンド未検出) | {details} |
| All Tests | PASS/FAIL(テスト失敗)/FAIL(環境不備)/SKIP(設計上不要)/SKIP(設計時除外) | {N} passed, {M} failed / 実行不能理由 等 |
| Integration Tests | PASS/FAIL(統合テスト)/FAIL(実装漏れ)/FAIL(環境不備)/SKIP(設計上不要)/SKIP(設計時除外) | {details} |
| Smoke Test | PASS/FAIL(スモーク)/FAIL(環境不備)/SKIP(設計上不要)/SKIP(設計時除外) | {details} |
| E2E Tests | PASS/FAIL(実装漏れ)/FAIL(環境不備)/SKIP(設計上不要)/SKIP(設計時除外) | {details} |

## Verdict: PASS / PASS(SKIP含む) / FAIL(テスト失敗) / FAIL(環境不備) / FAIL(実装漏れ)

- **PASS**: 全ステップが PASS
- **PASS(SKIP含む)**: SKIP(設計上不要)、SKIP(設計時除外)、SKIP(ビルドコマンド未検出) を含む全ステップが成功。SKIP の理由を Notes に記載
- **FAIL(テスト失敗)**: テスト実行時の失敗
- **FAIL(環境不備)**: 必須ツール・ランタイム未インストール → STOP
- **FAIL(実装漏れ)**: test-design.md に仕様があるのにテストファイルなし

## Notes
{FAIL の詳細、SKIP(設計上不要)の理由、設計時除外の根拠等}
```

#### ウェーブ失敗時の処理

マルチタスクウェーブの処理中に、いずれかのタスクが `retry_exhausted` になった場合:
1. ウェーブ内の残りのタスクは**実行を継続**する — ウェーブ全体を中止しない
2. ウェーブ内の全タスクが完了/失敗した後、ユーザーにサマリーを報告する:
   - 成功: [task-ids]
   - 失敗: [task-ids と理由]
3. 失敗したタスクに依存する後続ウェーブのタスク（`_DependsOn:` 経由）:
   - タスク行に `<!-- BLOCKED: dependency {failed-task-id} failed -->` コメントを追加し、チェックボックスの状態を `- [ ]` にする（チェックボックストークン自体は変更しない）
   - 後続ウェーブではこれらのタスクをスキップする
4. 失敗したタスクに**依存しない**後続ウェーブのタスク:
   - 次のウェーブで通常通り実行を継続する

### 10. PR 作成（Final E2E Gate PASS 後）

Final E2E Gate が PASS（SKIP 含む場合も）となった場合、PR 作成フェーズに進む。
FAIL の場合は PR 作成をスキップし、修正フローに進む（9.3 の結果判定に従う）。

**重要:** オーケストレータ自身は `/create-pr` を直接実行してはならない（⛔ `git commit` 禁止ルール）。PR 作成は **review-worker に委譲**する。`/create-pr` 実行中の `git commit` / `git push`（スクリーンショット追加等）も review-worker の責務とする。

review-worker へ以下の引数・情報を渡す:
- `--spec {spec-name}`
- `--skip-tests`（Final E2E Gate で全テスト実行済みのため）
- `--title "{spec-name に基づく機能の要約}"`
- Final E2E Gate レポート (`final-e2e-gate.md`) の Notes セクションの内容を `/create-pr` に引き継ぎ、PR ボディの Notes セクションに転記する

> review-worker は上記の引数で `/create-pr` スキルを実行する。スキルは Final E2E Gate レポートからテスト結果と Notes を読み取り、UI 変更を検出し、該当する場合はスクリーンショットを取得して PR を作成する。必要なコミット/プッシュも review-worker が担当する。

PR 作成完了後、`/spec-status` スキルで最終ステータスを表示する。

## Monitoring Progress

Use the `/spec-status` skill at any time to check overall progress and task counts. For pending approvals, query the `approvals` MCP tool separately.

## Rules

### ⛔ Orchestrator Prohibited Rules (Highest Priority)
- **Do not write code** — implementation is for parallel-worker only
- **Do not write tests** — tests are also for parallel-worker only
- **Do not run git commit** — commits are for review-worker only
- **Do not skip agent calls** — "it's simple" or "I can do it myself" are not valid reasons
- **Agent calls for steps 4/5/6 are required** — no exceptions

### General Rules
- **Do not use a whiteboard** — the whiteboard is exclusively for workflows that run multiple workers in parallel (e.g., wave-harness). Wave-based parallel execution in spec-implement uses independent worktrees instead. Do not pass `Whiteboard path` to parallel-worker / review-worker.
- Feature names use kebab-case
- One **wave** in-progress at a time (multiple tasks within a wave may be in-progress simultaneously)
- Always search implementation logs before coding (step 2)
- Follow TDD: tests first (RED), then implementation (GREEN), then refactor (REFACTOR)
- **Implementation (parallel-worker) and review (review-worker) are separate agents** — parallel-worker does not commit, review-worker does not implement
- Always call `/log-implementation` skill before marking a task `[x]` (step 7)
- Include test files in `filesCreated` when logging
- A task marked `[x]` without a log is incomplete
- If you encounter blockers, document them and move to another task
