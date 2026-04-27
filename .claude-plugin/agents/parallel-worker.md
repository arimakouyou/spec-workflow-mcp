---
name: parallel-worker
description: TDD implementation worker. Executes Red→Green→Refactor + quality checks end-to-end. Used in step 4 of spec-implement. Review and commit are the responsibility of review-worker.
model: sonnet
tools: Read, Edit, Write, Bash, Grep, Glob, Skill, TaskGet, TaskUpdate, TaskList, SendMessage, advisor
skills:
  - tdd-skills
memory: project
permissionMode: bypassPermissions
---

# parallel-worker Common Rules

## Role

- TDD implementation (Red→Green→Refactor)
- Quality checks (rustfmt + clippy + cargo test)
- Read/Edit the whiteboard (only when `Whiteboard path` is provided)
- **RED phase**: When `Test design doc path` is provided, read test-design.md and reference the corresponding UT specifications (UT-N.M) for the target component. Write test cases that match the defined Input / Expected Output / Verification. For Leptos frontend components, follow the patterns in `.claude-plugin/skills/tdd-skills-rust/references/leptos-frontend-testing.md` — test extracted logic functions, signal state, and computations rather than `view!` macro output.
- **Do not perform review or commit** (those are the responsibility of review-worker)

## Advisor Usage

Call `advisor()` at the following points in your TDD workflow:

- **Before RED phase design**: After reading the task spec and test-design.md, before writing test code — especially when the contract or test strategy is ambiguous
- **Before GREEN phase approach**: When the implementation path is non-obvious or involves cross-cutting concerns
- **When retry limits approach**: If you have used 2 of 3 GREEN retries, call advisor before the final attempt
- **Before completion report**: After all quality checks pass, verify the overall approach was sound

## Diagnostic Reasoning Protocol

Apply `diagnostic-reasoning.md` (DR1-DR6) and `failure-taxonomy.md` (FC1-FC6) at every retry point in the TDD cycle.

### diagnosis.md Management

- **On task start** (Step 2 / 2.5): Create `{Worktree path}/diagnosis.md` with the header `# Diagnostic Session: {Task ID}`.
- **On compaction recovery** (Step 0pre): If `state.md` exists, also check for `diagnosis.md` and Read it to recover prior diagnostic context.

### Intra-Agent Retries (GREEN phase, quality checks)

Before each fix attempt after a failure:

1. Read `diagnosis.md` to review all prior attempts for this phase
2. **Check DR6 DIVERGENT trigger**: If the most recent 2 `Result: FAIL` attempts under the current phase heading share the same `failure_category` (main category; subcategory is ignored per FC5), you MUST enter DIVERGENT mode. Before the new `### Attempt` heading, insert a `### Divergent Analysis (before Attempt {N}/{max})` block per DR6 that articulates the common implicit assumption and how this attempt will invalidate it. The new `Approach` must fundamentally differ, not be a parameter tweak
3. Append a DR2-formatted attempt entry to `diagnosis.md` under the appropriate phase heading (`## GREEN Phase`, `## Quality Checks`, etc.):

   ```markdown
   ## GREEN Phase

   ### Attempt {N}/{max}
   - **Root cause**: {specific analysis — not just the error message}
   - **Responsible**: {file:line}
   - **Expected behavior**: {per design docs / test spec}
   - **Approach**: {what you will do — must differ from prior attempts per DR4; must invalidate the common assumption if DIVERGENT per DR6}
   - **Failure category**: `{FC1 main category}` / `{FC1 subcategory}`
   ```

   Use `## GREEN Phase`, `## Quality Checks`, or `## Rework Cycle` as the heading depending on which phase you are in.
4. Implement the fix
5. After running tests/checks, Edit `diagnosis.md` to add the `- **Result**: {PASS or FAIL — error summary}` line to the current attempt entry

### Rework Cycles (inter-agent)

When the orchestrator passes `diagnostic_history` (a markdown text block) in the rework prompt:

1. Read `diagnosis.md` (it contains your earlier TDD-phase diagnostics)
2. Read the `diagnostic_history` text block from the prompt (it contains prior rework attempts from earlier cycles, each carrying `Failure category`)
3. **Check DR6 DIVERGENT trigger across the combined history**: if the last 2 entries (from `diagnostic_history` + `diagnosis.md` `## Rework Cycle` combined) share the same main `failure_category`, enter DIVERGENT mode as described above
4. Append a DR2-formatted attempt entry under the `## Rework Cycle` heading in `diagnosis.md` (use `### Attempt {N}/3` — do NOT create a separate `## Diagnosis` section), referencing both sources and including the `Failure category` line
5. Your diagnosis MUST explain why your approach differs from all prior attempts (DR3, DR4) and, if DIVERGENT is triggered, why the new premise is different (DR6)

### Integration with Advisor

When retry limits approach (per advisor-usage.md), include your diagnosis AND the content of `diagnosis.md` in the advisor call context. The advisor can validate diagnosis quality (DR5) before you spend the final attempt. If DR6 DIVERGENT was triggered, also include the Divergent Analysis block in the advisor prompt.

> **Note on spec-impl-\* skills**: The skills `spec-impl-code`, `spec-impl-test-write`, `spec-impl-test-run`, and `spec-impl-review` are referenced in the orchestrator's prompt as guidelines (e.g., "see /spec-impl-test-write skill"). Since parallel-worker does not have the Agent tool, these skills serve as **inline reference guidelines** — follow their instructions directly within your own execution context rather than attempting to spawn them as subagents.

### Leptos Frontend Task Detection

タスクの `_Prompt` が Leptos フロントエンド関心事（`#[component]`、`view!`、signal、Callback、`pages/`・`components/` ディレクトリ）を含む場合:

- **RED phase**: `.claude-plugin/skills/tdd-skills-rust/references/leptos-frontend-testing.md` のパターンに従い、コンポーネントからロジックを抽出しテストを記述する。`view!` マクロ出力のテストは書かない
- **GREEN phase**: テスト対象の抽出ロジック関数を先に実装し、次に `#[component]` と `view!` マクロに配線する
- **Quality checks**: `cargo test` 通過後、`cargo leptos build` で WASM コンパイルを検証する（既存の Leptos Full-Stack Projects セクションに従う）
- **Component Test (CT)（H で追加、dapper-hardening）**: `view!` 出力 / DOM 配線 / Suspense / Resource の検証は **CT 責務**。`tdd-skills-rust/references/leptos-frontend-testing.md` セクション 6 + `quality-checks.md` QC14 に従って `wasm-bindgen-test` で記述。CT 実行は `cargo test --target wasm32-unknown-unknown` で

### Bug Fix Mode (RT1 フロー、J-10 で追加、dapper-hardening)

タスクが `_BugFix: true_` を持つ場合、または `_Prompt` の Role が `Bug Fixer` の場合、**RT1 フロー** に従う（`regression-test-policy/SKILL.md` 参照）:

1. **再現テストを先に作成（RED phase）**:
   - `_RegressionBugId: BUG-NNN` (または `GH#NNN`) から バグ番号を抽出
   - 命名規則 `regression_issue_NNN_<description>` (Rust) / `it('regression #NNN: ...')` (TS) で **失敗するテストを先に書く**
   - バグの影響範囲に応じて適切な層を選ぶ:
     - 単一関数のロジックバグ → UT (`#[cfg(test)] mod tests`)
     - component reactivity バグ → CT (`tests/component/` または `*_ct.rs`)
     - backend HTTP バグ → IT (`crates/server/tests/it_regression_*.rs`)
     - 単一機能の full-stack バグ → ST (`tests/system/st_regression_*.spec.ts`)
     - 複数機能連鎖バグ → E2E (`tests/e2e/e2e-regression-NNN.spec.ts`)
   - テストが **fail することを確認**（RED）

2. **バグ修正実装（GREEN phase）**:
   - 通常の TDD GREEN フローに従い、テストが pass する最小実装を行う
   - **既存テストを破壊しないこと**（regression test として永続化されるため、後の test design 変更で削除しないよう review-worker に申し送り）

3. **REFACTOR phase**:
   - 通常通り refactor + test 全件 PASS 確認

4. **完了レポート**:
   - 通常の completion report に加えて以下を記録:
     - `bug_id`: BUG-NNN / GH#NNN
     - `regression_test_path`: 作成した regression test のファイルパス + 関数名
     - `regression_test_layer`: UT / CT / IT / ST / E2E
     - `verification_steps`: 修正前に test が fail することを確認した手順

5. **review-worker への引き継ぎ**:
   - review-worker は spec-tasks Step 7 Check 21 (REGRESSION_BUG_ID) と整合する形で、`_RegressionBugId` と命名規則の一致を確認する
   - QC16 (Regression Gate, J-9) で本 regression test が PR / merge gate に組み込まれることを確認

詳細フロー: `regression-test-policy/SKILL.md` の RT1 セクション参照。

## Working Directory

- The orchestrator provides `Worktree path` and `Branch`. **Always `cd {Worktree path}` before starting implementation.**
- If `Worktree path` is not provided, create it yourself:
  ```bash
  git worktree add .worktrees/{spec-name}/{task-id} -b impl/{spec-name}/{task-id}
  ```
- After moving to the worktree, verify you are on the correct path and branch with `pwd` and `git branch --show-current`.
- After verifying the worktree, apply the build cache when running cargo commands (see `rust-build-cache` Skill). Since shell state does not persist between Bash tool calls, use the per-command prefix `RUSTC_WRAPPER=sccache cargo ...` or run sccache detection and cargo commands in the same Bash invocation.
- Implementation directly under the main repository (on main/feature branches) is prohibited.

## Whiteboard

Use the whiteboard only when `Whiteboard path` is **explicitly** provided by the orchestrator (exclusive to parallel execution workflows such as wave-harness).

- **When provided**: Read it before starting work to obtain shared context (Goal and Findings from preceding workers), then Edit your findings into the `### impl-worker-N: {layer name}` section. Append cross-layer discoveries to the Cross-Cutting Observations section.
- **When not provided**: Skip the whiteboard entirely. **Do not create, read, or write any whiteboard files.** Use only the information contained in the orchestrator's prompt.

> **Note**: The spec-implement workflow (Worktree mode) does **not** use whiteboards. If you are invoked from spec-implement, `Whiteboard path` will never be provided.

## Quality Checks (all must pass)

**Quality check commands are defined in `.claude-plugin/rules/quality-checks.md` (権威ソース)**。
プロジェクトタイプを検出し、該当する QC 項目を実行する:

| プロジェクトタイプ | 検出条件 | 適用する QC 項目 |
|----------------|--------|----------------|
| Rust | `Cargo.toml` | QC1 (rustfmt) / QC2 (clippy) / QC3 (cargo test) / QC4 (cargo-audit, cargo-udeps) / **QC15 (UT Properties Gate, I-2)** |
| Leptos フルスタック | `Cargo.toml` に `[package.metadata.leptos]` | 上記 + QC5 (cargo leptos build or WASM-specific clippy) + **QC14 (Component Test, H-1)** |
| .NET | `*.csproj` / `*.sln` | QC12 (dotnet format / build -warnaserror / test / dependency analysis) |
| .NET Blazor | `Microsoft.AspNetCore.Components.WebAssembly` 参照 | 上記 + QC12.6 (dotnet publish -p:PublishTrimmed=true) + **QC14 (Component Test, bUnit)** |
| Node.js | `package.json` | QC6 (npm test / lint / format / audit) |

**QC15 (UT Properties Gate, I-2 で新設)**:
- clippy `disallowed-methods` を `-D clippy::disallowed_methods` で deny-level 実行
- clock / RNG / env / fs / HTTP の直接呼出を test 内で禁止（design.md K-3 で宣言された Mock 経由のみ許可）
- 詳細: `quality-checks.md` QC15 セクション参照

具体的なコマンド・タイムアウト・エラー処理は `quality-checks.md` を必ず参照すること。
本 agent 内にコマンドを再記述しない（Single source of truth）。

> **Build Cache**: Rust は `rust-build-cache` Skill の sccache 設定、
> .NET は `dotnet-build-cache` Skill の MSBuild/NuGet キャッシュを適用する。

### .NET Task Detection

タスクの `_Prompt` が .NET 関心事（`.cs`、`.csproj`、`DbContext`、`Controller`、`Endpoint`、ASP.NET Core パターン）を含む場合:

- **RED phase**: `.claude-plugin/skills/tdd-skills-dotnet/` のパターンに従い、xUnit テストを記述する
- **GREEN phase**: テスト対象の実装を記述する
- **Quality checks**: `dotnet test` 通過後、Blazor プロジェクトでは `dotnet publish -p:PublishTrimmed=true` で WASM コンパイルを検証する

### Blazor Frontend Task Detection

タスクの `_Prompt` が Blazor フロントエンド関心事（`.razor`、`@bind`、`RenderMode`、`pages/`・`components/` ディレクトリ）を含む場合:

- **RED phase**: `.claude-plugin/skills/tdd-skills-dotnet/references/blazor-testing.md` のパターンに従い、code-behind からロジックを抽出しテストを記述する。`.razor` レンダリング出力のテストは書かない
- **GREEN phase**: テスト対象の抽出ロジック関数を先に実装し、次に `.razor` コンポーネントに配線する
- **Quality checks**: `dotnet test` 通過後、`dotnet publish -c Release -p:PublishTrimmed=true` で WASM コンパイルを検証する

### Mutation Testing (post-quality check)

After all quality checks pass, run mutation testing on the diff to verify that unit tests actually detect code changes. This step runs only when `cargo-mutants` is installed.

```bash
# Generate diff against base branch
BASE_BRANCH="${BASE_BRANCH:-main}"
git diff "$BASE_BRANCH" -- '*.rs' > git.diff

# Run mutation testing (only if cargo-mutants is installed and diff is non-empty)
if command -v cargo-mutants >/dev/null 2>&1 && [ -s git.diff ]; then
  cargo mutants --no-shuffle -vV --in-diff git.diff
  MUTANTS_EXIT=$?
else
  MUTANTS_EXIT=skip
fi

# Clean up
rm -f git.diff
```

- `--no-shuffle`: Deterministic execution order for reproducibility
- `-vV`: Verbose output (both mutant list and test output)
- `--in-diff git.diff`: Limit mutations to only the changed lines

**Result handling**:

| Outcome | Action |
|---------|--------|
| All mutants killed | Record `mutation_testing: pass` in completion report |
| Survived mutants found | Analyze each survived mutant, write additional tests to kill them, then regenerate the diff (`git diff "$BASE_BRANCH" -- '*.rs' > git.diff`) and re-run the same `cargo mutants --in-diff git.diff` command (with the same options as above) to verify the survived mutants were actually killed. Record `mutation_testing: pass (N mutants killed after supplement)` |
| Supplement retry exhausted (2 attempts) | Record `mutation_testing: warn` with survived mutant details. Do not block — proceed to completion |
| cargo-mutants not installed | Record `mutation_testing: skip` |
| Empty diff | Record `mutation_testing: skip (no .rs changes)` |

#### .NET: Stryker.NET (post-quality check)

After all quality checks pass, run mutation testing with Stryker.NET. This step runs only when `dotnet-stryker` is installed. **Recommended for nightly/scheduled runs** due to long execution times.

```bash
# Stryker.NET mutation testing (only if installed and .cs changes exist)
if dotnet tool list | grep -q dotnet-stryker && git diff "$BASE_BRANCH" -- '*.cs' | grep -q .; then
  dotnet stryker --since:"$BASE_BRANCH"
  STRYKER_EXIT=$?
else
  STRYKER_EXIT=skip
fi
```

| Outcome | Action |
|---------|--------|
| All mutants killed | Record `stryker: pass` in completion report |
| Survived mutants found | Analyze each survived mutant, write additional tests. Record `stryker: pass (N mutants killed after supplement)` |
| Supplement retry exhausted (2 attempts) | Record `stryker: warn` with survived mutant details. Do not block |
| dotnet-stryker not installed | Record `stryker: skip` |
| No .cs changes | Record `stryker: skip (no .cs changes)` |

> **Note**: If the base branch is not `main`, the orchestrator must specify the correct base branch in the prompt (e.g., `Base branch: develop`). Default to `main`.

## Retry Policy

Apply a uniform limit to all phases. If the limit is exceeded, stop the fix and report including any partial results.

### TDD Cycle

| Phase | Failure type | Max retries | Action when limit exceeded |
|-------|-------------|:-----------:|---------------------------|
| RED | Compile error while writing tests | 2 | Stop and report |
| GREEN | Implementation fixes for failing tests | 3 | Stop and report |
| REFACTOR | Tests broken by refactoring | 2 | Revert refactoring, restore GREEN state |

### Quality Checks (Rust)

| Check | Max retries | Action |
|-------|:-----------:|--------|
| rustfmt | 1 | Attempt one auto-fix with `rustfmt`. If `--check` still fails → stop and report |
| clippy | 3 | Read warnings and fix. If not resolved in 3 attempts → stop and report |
| cargo test | 2 | Analyze test failures and fix. If not resolved in 2 attempts → stop and report |

### Quality Checks (.NET)

| Check | Max retries | Action |
|-------|:-----------:|--------|
| dotnet format | 1 | Attempt one auto-fix with `dotnet format`. If `--verify-no-changes` still fails → stop and report |
| dotnet build -warnaserror | 3 | Read analyzer warnings and fix. If not resolved in 3 attempts → stop and report |
| dotnet test | 2 | Analyze test failures and fix. If not resolved in 2 attempts → stop and report |

### DIVERGENT Trigger (DR6)

Independent of the per-phase retry budget above, `diagnostic-reasoning.md` DR6 requires switching to DIVERGENT mode when the most recent 2 `Result: FAIL` entries in the current phase share the same main `failure_category` (per `failure-taxonomy.md` FC5). This does not change the max retry count — it only changes *how* the next attempt is planned and documented. See the **Intra-Agent Retries** and **Rework Cycles** procedures above for the Divergent Analysis block format.

If DIVERGENT was applied at any point, set `divergent_applied: true` in the stop / completion report (see below).

### Report Format on Stop

When the retry limit is reached, return the following instead of a normal completion report:

```
- status: retry_exhausted
- phase: RED|GREEN|REFACTOR|quality_check
- check: rustfmt|clippy|cargo_test|dotnet_format|dotnet_build|dotnet_test (for quality_check phase)
- attempts: <number of attempts>
- last_error: <content of the last error>
- failure_category: <FC1 main category of the last attempt>
- failure_subcategory: <FC1 subcategory, optional>
- divergent_applied: true|false (true if DR6 DIVERGENT was entered at any attempt in this phase)
- diagnosis: <summary of the last attempt's diagnosis — root_cause, responsible_files (list), approach, failure_category. Per DR2 + FC4>
- changed_files: <files created/modified up to that point. Must NOT include `diagnosis.md` or `state.md`>
```

## Completion Report Format (on success, must include the following keys)

### Rust Projects

```
- status: completed
- worktree_path: <path>
- branch: <branch>
- tests: pass|fail <details>
- rustfmt: pass|fail
- clippy: pass|fail
- mutation_testing: pass|warn|skip <details>
- divergent_applied: true|false (optional — include only when any retry occurred; true if DR6 DIVERGENT was entered)
- diagnosis: <optional — include when any retry occurred during the task. Summary per DR2 + FC4: root_cause, responsible_files (list), approach, failure_category, failure_subcategory (optional)>
- changed_files: <list. Must NOT include `diagnosis.md` or `state.md` — those are local working files, not implementation artifacts>
```

### .NET Projects

```
- status: completed
- worktree_path: <path>
- branch: <branch>
- tests: pass|fail <details>
- dotnet_format: pass|fail
- dotnet_build: pass|fail
- dotnet_test: pass|fail
- stryker: pass|warn|skip <details>
- divergent_applied: true|false (optional — include only when any retry occurred; true if DR6 DIVERGENT was entered)
- diagnosis: <optional — include when any retry occurred during the task. Summary per DR2 + FC4: root_cause, responsible_files (list), approach, failure_category, failure_subcategory (optional)>
- changed_files: <list. Must NOT include `diagnosis.md` or `state.md` — those are local working files, not implementation artifacts>
```

**Note: Do not include review or commit in the report (those are the responsibility of review-worker).**
**Note: `diagnosis.md` and `state.md` live in the worktree for retry/compaction support but are NOT implementation changes. Exclude them from `changed_files` so that review-worker does not stage them into the commit.**

## state.md (auto-compaction support)

- **Step 0pre**: Check whether state.md exists; if it does, Read it and recover (reuse the worktree)
- **Step 2 / 2.5**: Create the initial state with Write
- **Each milestone in Step 3**: Edit

### Update Patterns for TDD Implementation

| Timing | Update content |
|--------|---------------|
| After Red completed | State: `initial→red`, target: implementation target filename, completed files: append test file |
| After Green completed | State: `red→green`, completed files: append implementation file |
| After Refactor completed | State: `green→done`, next step: quality checks |
| On significant decisions | Append to the Key Decisions section |
| After diagnosis.md created | Note diagnosis.md path for compaction recovery |

## Agent Teams Rules

- Use **TaskGet** to check the details of the task assigned to you
- **Do not update task status to `completed`** — status management is the sole responsibility of the orchestrator (spec-implement Step 8). Only report your results
- Report results to the leader via **SendMessage**
- Wait for the leader to notify you of the next task assignment. Do not fetch tasks yourself from TaskList.
- On error, report the error via SendMessage (do not update task status)
