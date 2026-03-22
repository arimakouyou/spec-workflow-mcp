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
| **Do not write tests yourself** | The initial TDD tests (RED phase) are `parallel-worker`'s responsibility. Adding supplemental tests is `unit-test-engineer`'s responsibility |
| **Do not run git commit yourself** | Commits must always be delegated to `review-worker` |
| **Do not skip agent calls** | Each step's agent call cannot be skipped |

**For any reason whatsoever (e.g., "it's a simple task", "I can do it myself"), do not skip agent calls.**

The orchestrator's sole responsibilities:
1. Read tasks.md and identify the next task
2. Call agents with the correct prompts
3. Receive agent completion reports and hand off to the next agent
4. Call log-implementation
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

## Inputs

- **spec name** (kebab-case, e.g., `user-authentication`)
- **task ID** (optional — if not provided, pick the next pending `[ ]` task)

## Task Cycle

Repeat for each wave:

### 1. Start the Wave

Parse `.spec-workflow/specs/{spec-name}/tasks.md` and compute execution waves based on `_DependsOn:` dependencies:

1. Parse tasks.md to identify Phase structure and `_DependsOn:` metadata
2. Compute execution waves using topological sort — tasks with no unresolved dependencies form a wave
3. The **next pending wave** is the first wave (in Phase order) containing at least one `[ ]` task

**Single-task wave**: If the wave contains only one task, process it as before (sequential flow).

**Multi-task wave**: If the wave contains multiple tasks, process them in parallel:
- Mark ALL tasks in the wave from `[ ]` to `[-]` in tasks.md
- Prepare worktrees for all tasks (step 3.7)
- Launch parallel-workers simultaneously (step 4)

> Note: multi-task wave では、複数タスクが同時に `[-]`（進行中）になることは **意図された正常な動作** です。これは `implement-task` プロンプト等の「Only one task should be in-progress at a time」ガイダンスの明示的な例外です。

**Wave 計算時の PhaseReview 除外**: `_PhaseReview: true` のタスクは wave 計算から常に除外する。PhaseReview はフェーズ内の全通常タスク完了後に単独で処理する。

**No `_DependsOn:` metadata**: If no tasks in the Phase have `_DependsOn:`, all non-PhaseReview tasks form Wave 0 and are processed sequentially as before (backward compatible).

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
- **Success**: How to know you're done

### 3.5 Phase Review Tasks

If the task has `_PhaseReview: true_`, **skip the TDD cycle (steps 4-5)** and instead:

#### 3.5.1 Run Tests

```bash
cargo test --quiet
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
| `package.json` 存在 | Node.js |
| いずれにも該当しない | Generic（ビルドのみ検証） |

**Step B: ビルド検証（必須）**

成果物のビルドが成功することを確認する。コマンドはプロジェクトタイプに応じて `quality-checks.md` を参照。

**Step C: 統合テスト実行（テストが存在する場合のみ）**

`tests/integration*` ディレクトリまたは同等のテストファイルが存在する場合に実行。存在しない場合は SKIP。

**Step D: スモークテスト（API プロジェクトのみ）**

サーバを一時起動し、ヘルスチェックエンドポイントへの疎通を確認する。外部依存（DB等）で起動不可の場合は SKIP + ログ記録。

**結果判定:**

| 結果 | アクション |
|------|----------|
| PASS | 3.5.2 Expert Team Review に進む |
| FAIL (ビルド) | ビルドエラーを分析、根本原因タスクを特定。Phase 内タスク → `[x]` を `[-]` に戻して差し戻し、PhaseReview を `[ ]` に戻す。根本原因タスクの step 4 から再実行 |
| FAIL (統合テスト) | 失敗テストを分析、根本原因タスク特定。Phase 内タスク → 差し戻し、前 Phase → ユーザーエスカレート |
| FAIL (スモーク) | 起動ログを分析し根本原因特定、差し戻し |
| SKIP (環境依存) | ログに SKIP 理由を記録し、3.5.2 に進む。Expert Team Review で補完 |

統合検証の結果（各ステップの PASS/FAIL/SKIP）は、3.5.2 の Expert Team Review に入力として渡すこと。

#### 3.5.2 Expert Team Review (multi-perspective review)

Phase 完了時は、コミット前に専門家チームによる多角的コードレビューを実施する。詳細は `/phase-review-team` スキルを参照。

**チーム編成（5名を並列起動）:**

| Role | Perspective |
|------|-------------|
| 実装担当 | 仕様書にある機能を網羅しているか、仕様を逸脱していないか |
| セキュリティ担当1 | 認証、認可、データ漏洩 |
| セキュリティ担当2 | OWASP TOP 10、最新の CVE |
| パフォーマンス担当 | ボトルネック、計算量、リソース効率 |
| 品質・保守性担当 | テストカバレッジ、読みやすさ、命名規則、DRY 原則 |

**手順:**

1. 5名の専門家を Agent tool で **並列** 起動（プロンプト詳細は `/phase-review-team` スキルを参照）
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
  subagent_type: "review-worker",
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

    Expert team review report: .spec-workflow/specs/{spec-name}/reviews/phase-{phase-number}-review.md (reference only).
    Focus on final quality checks (rustfmt, clippy, tests) and commit.
    Review across all aspects (A–F) and report review_action as commit / rework / escalate.
    The commit message should summarize the Phase's deliverables.`
})
```

- **review_action: commit** → proceed to 3.5.4
- **review_action: rework** → follow the normal rework flow (identify the root cause task and send it back to that task's parallel-worker)
- **review_action: escalate** → follow the normal escalate flow

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

**Wave parallel execution**: For multi-task waves, launch ALL parallel-worker agents **simultaneously** in a single message with multiple Agent tool calls. Each agent works in its own isolated worktree. Wait for all agents to complete before proceeding to step 5.

```javascript
Agent({
  subagent_type: "parallel-worker",
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
    Design doc path: {project-path}/.spec-workflow/specs/{spec-name}/design.md
    Test design doc path: {project-path}/.spec-workflow/specs/{spec-name}/test-design.md

    **Important**: Always start by running `cd {WORKTREE_PATH}` before beginning implementation. Changes directly in the main repository are prohibited.

    Steps:
    1. RED: Write failing tests (see /spec-impl-test-write skill)
    2. Confirm all tests fail by running them
    3. GREEN: Write the minimum code to make the tests pass (see /spec-impl-code skill)
    4. Confirm all tests pass by running them (retry up to 3 times on failure)
    5. REFACTOR: Clean up the code (see /spec-impl-review skill)
    6. Confirm all tests still pass after refactoring
    7. Run quality checks (rustfmt + clippy + cargo test)

    Include the following in the completion report:
    - tests: pass|fail
    - rustfmt: pass|fail
    - clippy: pass|fail
    - test_file_paths: list of test files
    - implementation_file_paths: list of implementation files
    - changed_files: list of all changed files`
})
```

Capture from the result: **status**, **test_file_paths**, **implementation_file_paths**, **changed_files**.

Branch based on parallel-worker's `status`:

- **status: completed** → proceed to step 5
- **status: retry_exhausted** → parallel-worker has stopped after exhausting retries. Report the following to the user:
  - Which phase (RED/GREEN/REFACTOR/quality_check) failed
  - The last error message
  - Files partially created

  User decision: fix manually and resume / skip the task and move on / revisit the design

  **Resume flow (after user decision):**

  | Choice | Steps |
  |--------|-------|
  | **Fix manually and resume** | After the user manually fixes files inside `{WORKTREE_PATH}`, resume from step 5 (UT). Do not reset the rework counter (carry over the cumulative count) |
  | **Skip the task** | Append `<!-- BLOCKED: {reason} -->` as a comment to the relevant task row in tasks.md, revert `[-]` to `[ ]`, and proceed to the next `[ ]` task |
  | **Revisit the design** | Follow the same flow as `review_action: escalate` (user decides whether to adjust within the design.md scope or do a Phase Reset) |

### 5. Unit Test Quality Verification [AGENT CALL REQUIRED]

> ⛔ **Do not add tests yourself. Always call the `unit-test-engineer` agent.**

Verify the quality of tests written during the TDD cycle and supplement any missing test perspectives. TDD is "a development method that writes tests first to drive implementation"; this step independently verifies the quality of the implemented code.

Pass the implementation files to the `unit-test-engineer` agent and have it confirm coverage of required test perspectives (happy path, boundary values, exception handling, edge cases).

```javascript
Agent({
  subagent_type: "unit-test-engineer",
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

    The completion report must include:
    - ut_action: added (tests were added) | verified_sufficient (no additions needed, already sufficient)
    - added_tests: list of added test function names (if added)
    - added_to_files: list of modified test files (if added)
    - coverage_summary: happy path: N cases, boundary values: N cases (+M added), exception handling: N cases (+M added), edge cases: N cases (+M added)`
})
```

Capture from the result: **ut_action**, **added_tests**, **added_to_files**, **coverage_summary**.

- `ut_action: added` → run the tests, confirm all pass, and pass the additional info to step 5.5
- `ut_action: verified_sufficient` → proceed directly to step 5.5

### 5.5. Code Simplification (code-simplifier) [AGENT CALL REQUIRED]

> ⛔ **Do not clean up code yourself. Always call the `code-simplifier` agent.**

After TDD and UT verification are complete, improve code clarity and maintainability while preserving functionality.
The output of `code-simplifier` is comprehensively reviewed by the subsequent step 6 (review-worker), so no dedicated review step is added.

```javascript
Agent({
  subagent_type: "code-simplifier",
  description: "Simplify: improve clarity without changing behavior",
  prompt: `Simplify and refine the following implementation files while preserving functionality.

    Worktree path: {WORKTREE_PATH}
    Implementation files: {implementation_file_paths from step 4}
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
  subagent_type: "review-worker",
  description: "Review and commit",
  prompt: `⚠️ INDEPENDENT REVIEW REQUIRED ⚠️
    This code has passed through parallel-worker (TDD), unit-test-engineer, and code-simplifier.
    However, you MUST NOT assume it is correct because previous steps reported success.
    Previous results are provided as reference ONLY — your independent, critical review is mandatory.
    Treat this as if you are seeing the code for the first time. Your job is to find problems, not confirm success.

    Review the following changes and commit if they meet quality standards.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}
    Changed files: {changed_files from step 4 + added_to_files from step 5 + changed_files from step 5.5}
    Task prompt: {paste the full _Prompt content here}

    **Important**: Always run `cd {WORKTREE_PATH}` before reviewing and committing.

    Previous step results (reference only — do not let these bias your review):
    UT quality verification results (step 5):
    - ut_action: {ut_action from step 5}
    - added_tests: {added_tests from step 5}
    - coverage_summary: {coverage_summary from step 5}

    Simplification results (step 5.5):
    - simplify_result: {simplify_result from step 5.5} (one of: simplified / no_change / reverted)
    - changed_files: {changed_files from step 5.5 (only if simplified)}

    Notes:
    - Tests listed in added_tests have already been quality-verified by unit-test-engineer.
      In category E (final test verification), do not flag these tests as "insufficient".
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
  subagent_type: "parallel-worker",
  description: "Rework: fix review findings ({N}/3)",
  prompt: `The review found the following issues. Please fix them.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}

    **Important**: Always run `cd {WORKTREE_PATH}` before making fixes.

    rework_attempt: {N} / 3 (maximum 3 times)

    Findings:
    {findings from review-worker}

    Note: This is rework attempt {N}. The maximum is 3; if unresolved after 3 attempts, the issue will be escalated to the user.
    Fix all findings at once. On the final attempt (3/3), avoid large-scale changes and choose the minimum fix that will pass review.

    After fixing, run quality checks (rustfmt + clippy + cargo test) to confirm all pass.
    Include changed_files in the completion report.`
})
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

Call the `log-implementation` MCP tool BEFORE marking the task complete. A task without a log is not complete — this is the most commonly skipped step.

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
  - `autoFixed` (optional — tool schema には未定義の拡張フィールド。review-worker の完了レポートの `auto_fixed` キーに対応): 自動修正した Minor 問題のリスト（0件の場合は空配列 `[]`）:
    ```json
    "autoFixed": [
      { "category": "A:style", "file": "src/handler.rs:45", "description": "unwrap() を map_err() に修正" }
    ]
    ```
  - If reworkCount is 0 (passed on first attempt), `findings` may be omitted. `observations` and `autoFixed` are optional extension fields (not in tool schema) but recommended for traceability:
    ```json
    "reviewProcess": {
      "reworkCount": 0,
      "reviewOutcome": "commit",
      "observations": { "style": "checked-ok: ...", "design": "checked-ok: ...", ... },
      "autoFixed": []
    }
    ```

**If log-implementation fails:**
- Do not mark the task as `[x]` (completion without a log is incomplete)
- Report the error to the user and confirm whether to record the log manually or retry
- If the MCP tool itself is unavailable: Creating a markdown file manually in the `.spec-workflow/specs/{spec-name}/Implementation Logs/` directory is an acceptable alternative

### 8. Complete the Task

Only after `log-implementation` returns success:
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
cargo test --test 'integration*' --quiet

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
| Rust E2E | `tests/e2e/` ディレクトリ存在 | `cargo test --test 'e2e*' --quiet` |
| Node.js E2E | `package.json` に `test:e2e` | `npm run test:e2e` |

```bash
# テスト用コンテナ停止・クリーンアップ
if [ -f docker-compose.test.yml ]; then
  docker-compose -f docker-compose.test.yml down -v
fi
```

E2E テストが存在しない場合は SKIP（`/spec-e2e-implement` 未実行と判断）。

#### 9.3 結果判定

| 結果 | アクション |
|------|----------|
| **PASS** | 全検証クリア → 実装完了をユーザーに報告。`spec-status` ツールで最終ステータスを表示 |
| **FAIL** | 失敗箇所を分析し、該当 Phase・タスクを特定。タスクを `[x]` から `[-]` に戻し、該当タスクの step 4 から再実行。PhaseReview も `[ ]` に戻す |
| **SKIP (環境依存)** | ユーザーに手動検証を依頼。SKIP した検証項目と理由を明示的にリストし、ユーザーが自分で確認できるコマンドを提示する |

#### 9.4 最終レポート

Final E2E Gate の結果を `.spec-workflow/specs/{spec-name}/reviews/final-e2e-gate.md` に保存する。

```markdown
# Final E2E Gate Report

## Spec: {spec-name}
## Date: {date}

## Results
| Step | Result | Details |
|------|--------|---------|
| Build | PASS/FAIL/SKIP | {details} |
| All Tests | PASS/FAIL/SKIP | {N} passed, {M} failed |
| Integration Tests | PASS/FAIL/SKIP | {N} passed, {M} failed |
| Smoke Test | PASS/FAIL/SKIP | {details} |
| E2E Tests | PASS/FAIL/SKIP | {N} passed, {M} failed |

## Verdict: PASS / FAIL / PARTIAL (SKIP あり)

## Notes
{SKIP の理由、手動検証が必要な項目等}
```

#### Wave Failure Handling

When processing a multi-task wave, if any task results in `retry_exhausted`:
1. **Continue executing** remaining tasks in the wave — do not abort the entire wave
2. After all tasks in the wave complete/fail, report a summary to the user:
   - Succeeded: [task-ids]
   - Failed: [task-ids with reasons]
3. Tasks in subsequent waves that depend on a failed task (via `_DependsOn:`):
   - Add `<!-- BLOCKED: dependency {failed-task-id} failed -->` comment to the task line and ensure its checkbox state is `- [ ]` (do not change the checkbox token itself)
   - Skip these tasks in subsequent waves
4. Tasks in subsequent waves with **no dependency** on failed tasks:
   - Continue execution normally in the next wave

## Monitoring Progress

Use the `spec-status` MCP tool at any time to check overall progress, task counts, and approval status.

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
- Always call log-implementation before marking a task `[x]` (step 7)
- Include test files in `filesCreated` when logging
- A task marked `[x]` without a log is incomplete
- If you encounter blockers, document them and move to another task
