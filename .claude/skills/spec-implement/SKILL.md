---
name: spec-implement
description: "Phase 4 of spec-driven development: implement tasks from an approved tasks.md document using TDD (Red-Green-Refactor). ONLY use this skill when ALL THREE spec documents exist: requirements.md, design.md, AND tasks.md. Use this skill when the user explicitly requests to start implementation, code a specific task ID, or continue implementation of an existing spec. Triggers on: 'implement task', 'start coding', 'work on task 3', 'implement spec X', 'continue implementation', '/spec-implement'. DO NOT trigger on general 'implement X' requests unless spec documents exist."
---

# Spec Implementation (Phase 4) — TDD Orchestrator

Execute tasks systematically from the approved tasks.md using a **TDD-driven workflow**. Each task follows the cycle: Start → Discover → Read Guidance → **TDD Implementation (parallel-worker)** → **UT Quality Verification** → **Code Review + Commit (review-worker)** → Log → Complete.

## ⛔ オーケストレーター禁止事項（ABSOLUTE RULES）

このスキルを実行するあなたは**オーケストレーター**であり、**実装者ではない**。以下を厳守すること:

| 禁止 | 理由 |
|-----|------|
| **コードを自分で書かない** | 実装は必ず `parallel-worker` に委譲する |
| **テストを自分で書かない** | TDD の初期テスト（RED フェーズ）は `parallel-worker` の責務。補完テストの追加は `unit-test-engineer` の責務 |
| **git commit を自分でしない** | コミットは必ず `review-worker` に委譲する |
| **エージェント呼び出しを省略しない** | 各ステップのエージェント呼び出しはスキップ不可 |

**どんな理由があっても（「シンプルなタスクだから」「自分でできるから」等）エージェント呼び出しを省略してはならない。**

オーケストレーターの唯一の責務:
1. tasks.md を読んで次のタスクを特定する
2. エージェントを正しいプロンプトで呼び出す
3. エージェントの完了報告を受け取り次のエージェントへ引き継ぐ
4. log-implementation を呼び出す
5. tasks.md のステータスを更新する

## Prerequisites Check (MANDATORY — DO NOT SKIP)

Before doing anything else, verify all prerequisite files exist:

1. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists
2. Check `.spec-workflow/specs/{spec-name}/design.md` exists
3. Check `.spec-workflow/specs/{spec-name}/tasks.md` exists

If ANY file is missing — **STOP immediately. Do NOT start implementing.**

| 不足ファイル | 対応スキル |
|------------|----------|
| requirements.md | `/spec-requirements` |
| design.md | `/spec-design` |
| tasks.md | `/spec-tasks` |

ユーザーに「{ファイル名} が存在しないため実装を開始できません。先に {スキル名} を実行してください。」と伝えてこのスキルを終了する。

---

Tasks must be approved and cleaned up (Phases 1-3 complete). If not, use `/spec-tasks` first.

## Inputs

- **spec name** (kebab-case, e.g., `user-authentication`)
- **task ID** (optional — if not provided, pick the next pending `[ ]` task)

## Task Cycle

Repeat for each task:

### 1. Start the Task

Edit `.spec-workflow/specs/{spec-name}/tasks.md` and change the task marker from `[ ]` to `[-]`. Only one task should be in-progress at a time.

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

#### 3.5.1 テスト実行

```bash
cargo test --quiet
```

- **全パス** → 3.5.2 へ
- **失敗** → 失敗テストのエラー内容を分析し、原因タスクを特定する:
  - **原因が当該 Phase 内のタスク** → 原因タスクを `[x]` → `[-]` に戻し、PhaseReview タスクも `[-]` → `[ ]` に戻す。原因タスクを step 4 から再実行する。
  - **原因が先行 Phase のタスク** → ユーザーにエスカレーション（先行 Phase の修正が必要、影響範囲の判断が必要）

#### 3.5.2 コードレビュー（review-worker に委譲）

当該 Phase で変更された全ファイルを review-worker に渡す:

```javascript
Agent({
  subagent_type: "review-worker",
  description: "Phase review: review all phase changes",
  prompt: `Phase レビューとして、当該 Phase で変更された全ファイルをレビューしてください。

    Project path: {project-path}
    Spec name: {spec-name}
    Phase: {phase-number}
    Changed files: {all files changed in this phase}

    全観点（A〜F）でレビューし、review_action を commit / rework / escalate で報告してください。
    コミットメッセージは Phase の成果物を要約する形式にしてください。`
})
```

- **review_action: commit** → 3.5.3 へ
- **review_action: rework** → 通常の rework フローに従う（指摘の原因タスクを特定し、そのタスクの parallel-worker に差し戻し）
- **review_action: escalate** → 通常の escalate フローに従う

#### 3.5.3 完了

review-worker がコミット済み。step 7 (Log) へ進む。

### 3.6 TDD Skip Tasks

If the task has `_TDDSkip: true_`（プロジェクト初期化、Dockerfile、マイグレーション等のテスト不可能タスク）, **TDD サイクル（step 4）と UT 品質検証（step 5）をスキップ**し、以下を実行:

1. parallel-worker に TDD なしの直接実装を指示する（prompt に `_TDDSkip: true のため TDD サイクルをスキップし、直接実装 + 品質チェックのみ実行してください` を追加）
2. parallel-worker の完了後、step 5（UT）と step 5.5（code-simplifier）をスキップして step 6（review-worker）へ進む
3. review-worker は通常通り全観点でレビュー（ただしカテゴリ E: テスト最終確認はスキップ）

### 3.7 Worktree の準備

タスクごとに git worktree を用意する。これにより parallel-worker と review-worker が独立したワーキングディレクトリで安全に作業でき、オーケストレーターのメインブランチに影響を与えない。

```bash
WORKTREE_PATH=".worktrees/{spec-name}/{task-id}"
BRANCH="impl/{spec-name}/{task-id}"

# 既存の worktree を確認（rework サイクルでの再利用）
if git worktree list | grep -q "$WORKTREE_PATH"; then
  echo "既存の worktree を再利用: $WORKTREE_PATH (branch: $BRANCH)"
else
  git worktree add "$WORKTREE_PATH" -b "$BRANCH"
  echo "新規 worktree を作成: $WORKTREE_PATH (branch: $BRANCH)"
fi
```

`WORKTREE_PATH` と `BRANCH` を変数として保持し、step 4 および step 6 のエージェントプロンプトに渡す。

### 4. TDD Implementation (parallel-worker) 【エージェント呼び出し必須】

> ⛔ **自分でコードを書かない。必ず `parallel-worker` エージェントを呼び出すこと。**

`parallel-worker` エージェントに TDD サイクル全体（Red → Green → Refactor + 品質チェック）を委譲する。parallel-worker は実装のみ行い、**git commit はしない**（review-worker の責務）。

```javascript
Agent({
  subagent_type: "parallel-worker",
  description: "TDD: Red-Green-Refactor implementation",
  prompt: `以下のタスクを TDD（Red→Green→Refactor）で実装してください。

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

    **重要**: 実装は必ず `cd {WORKTREE_PATH}` してから開始すること。メインリポジトリ直下での変更は禁止。

    手順:
    1. RED: 失敗するテストを書く（/spec-impl-test-write スキル参照）
    2. テスト実行で全テストが失敗することを確認
    3. GREEN: テストを通す最小限のコードを書く（/spec-impl-code スキル参照）
    4. テスト実行で全テストが通ることを確認（失敗時は最大3回リトライ）
    5. REFACTOR: コードを整理する（/spec-impl-review スキル参照）
    6. テスト実行でリファクタリング後も全テストが通ることを確認
    7. 品質チェック（rustfmt + clippy + cargo test）を実行

    完了報告に以下を含めること:
    - tests: pass|fail
    - rustfmt: pass|fail
    - clippy: pass|fail
    - test_file_paths: テストファイルのリスト
    - implementation_file_paths: 実装ファイルのリスト
    - changed_files: 変更された全ファイルのリスト`
})
```

Capture from the result: **status**, **test_file_paths**, **implementation_file_paths**, **changed_files**.

parallel-worker の `status` に応じて分岐:

- **status: completed** → step 5 へ進む
- **status: retry_exhausted** → parallel-worker がリトライ上限に達して停止した。以下をユーザーに報告:
  - どのフェーズ（RED/GREEN/REFACTOR/quality_check）で失敗したか
  - 最後のエラー内容
  - 途中まで作成されたファイル

  ユーザーの判断: 手動修正して再開 / タスクをスキップして次へ / 設計を見直す

  **再開フロー（ユーザーの選択後）:**

  | 選択 | 手順 |
  |------|------|
  | **手動修正して再開** | ユーザーが `{WORKTREE_PATH}` 内を手動修正した後、step 5（UT）から再開する。rework カウンターはリセットしない（通算カウントを引き継ぐ） |
  | **タスクをスキップ** | tasks.md の該当タスク行に `<!-- BLOCKED: {理由} -->` をコメントとして追記し、`[-]` を `[ ]` に戻す。次の `[ ]` タスクに進む |
  | **設計を見直す** | `review_action: escalate` と同じフローに従う（design.md の範囲内で調整するか、Phase Reset かをユーザーが判断） |

### 5. Unit Test Quality Verification 【エージェント呼び出し必須】

> ⛔ **自分でテストを追加しない。必ず `unit-test-engineer` エージェントを呼び出すこと。**

TDD サイクルで書いたテストの品質を検証し、不足しているテスト観点を補完する。TDD は「テストを先に書いて実装を進める開発手法」であり、このステップは「実装されたコードの品質を検証する行為」として独立している。

`unit-test-engineer` エージェントに実装ファイルを渡し、必須テスト観点（正常系・境界値・例外処理・エッジケース）の網羅性を確認させる。

```javascript
Agent({
  subagent_type: "unit-test-engineer",
  description: "UT: Verify test quality",
  prompt: `以下の実装ファイルに対して、ユニットテストの品質を検証してください。

    実装ファイル: {implementation_file_paths from step 4}
    既存テストファイル: {test_file_paths from step 4}

    必須テスト観点（正常系・境界値・例外処理・エッジケース）に照らして、
    不足しているテストケースがあれば追加してください。
    既存テストと重複しないよう注意すること。

    完了報告に以下を必ず含めること:
    - ut_action: added（テスト追加あり）| verified_sufficient（追加なし、既に十分）
    - added_tests: 追加したテスト関数名のリスト（added の場合）
    - added_to_files: 変更したテストファイルのリスト（added の場合）
    - coverage_summary: 正常系: N件, 境界値: N件(+M added), 例外処理: N件(+M added), エッジケース: N件(+M added)`
})
```

Capture from the result: **ut_action**, **added_tests**, **added_to_files**, **coverage_summary**.

- `ut_action: added` → テストを実行して全パスを確認し、追加情報を step 5.5 に伝達
- `ut_action: verified_sufficient` → そのまま step 5.5 へ

### 5.5. Code Simplification (code-simplifier) 【エージェント呼び出し必須】

> ⛔ **自分でコードを整理しない。必ず `code-simplifier` エージェントを呼び出すこと。**

TDD と UT 検証が完了した後、機能を保持したままコードの明瞭性・保守性を向上させる。
`code-simplifier` の出力は後続の step 6（review-worker）が包括的にレビューするため、専用レビューステップを追加しない。

```javascript
Agent({
  subagent_type: "code-simplifier",
  description: "Simplify: improve clarity without changing behavior",
  prompt: `以下の実装ファイルを、機能を保持したまま簡潔化・洗練してください。

    Worktree path: {WORKTREE_PATH}
    Implementation files: {implementation_file_paths from step 4}
    Test files: {test_file_paths from step 4 + added_to_files from step 5}

    **重要**: 作業は必ず cd {WORKTREE_PATH} してから行うこと。

    完了後、cargo test を実行してすべてのテストがパスすることを確認してください。
    完了報告に以下を含めること:
    - simplify_result: simplified（変更あり）| no_change（変更なし）
    - changed_files: 変更したファイルのリスト（simplified の場合）
    - test_result: pass | fail`
})
```

Capture from the result: **simplify_result**, **changed_files** (if simplified), **test_result**.

- `test_result: pass` → step 6 へ（`changed_files` を伝達）
- `test_result: fail` → `changed_files` に含まれるファイルのみを `git restore {changed_files}` で巻き戻し、step 6 へ（`simplify_result: reverted` として記録）
- `simplify_result: no_change` → そのまま step 6 へ

### 6. Code Review + Commit (review-worker) 【エージェント呼び出し必須】

> ⛔ **自分でコミットしない。必ず `review-worker` エージェントを呼び出すこと。**

`review-worker` エージェントにコードレビューとコミットを委譲する。実装（parallel-worker）とレビュー（review-worker）の責務を分離することで、品質を担保する。

```javascript
Agent({
  subagent_type: "review-worker",
  description: "Review and commit",
  prompt: `以下の変更をレビューし、品質基準を満たしていればコミットしてください。

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}
    Changed files: {changed_files from step 4 + added_to_files from step 5 + changed_files from step 5.5}
    Task prompt: {paste the full _Prompt content here}

    **重要**: レビュー・コミットは必ず `cd {WORKTREE_PATH}` してから行うこと。

    UT 品質検証結果（step 5）:
    - ut_action: {ut_action from step 5}
    - added_tests: {added_tests from step 5}
    - coverage_summary: {coverage_summary from step 5}

    簡潔化結果（step 5.5）:
    - simplify_result: {simplify_result from step 5.5}（simplified / no_change / reverted のいずれか）
    - changed_files: {changed_files from step 5.5（simplified の場合のみ）}

    注意:
    - added_tests に含まれるテストは unit-test-engineer が品質検証済みです。
      カテゴリ E（テスト最終確認）でこれらのテストに対して「不足」の指摘を出さないでください。
      ただし、スタイル・命名・機密情報の混入等の観点は通常通りチェックしてください。
    - simplify_result: simplified のファイルは code-simplifier が機能保持・テスト通過を確認済みです。
      カテゴリ A（スタイル）では簡潔化後のコードを最終形として評価してください。

    全観点（A:スタイル, B:設計, C:セキュリティ, D:仕様照合, E:テスト, F:設計適合）でレビューし、
    review_action を commit / rework / escalate のいずれかで報告してください。`
})
```

review-worker の `review_action` に応じてオーケストレーターが分岐する:

#### review_action: commit（全観点 pass）
→ step 7 へ進む

#### review_action: rework（B:設計 / C:セキュリティ / E:テスト の指摘）

review-worker の `findings` を含めて parallel-worker に差し戻す:

**worktree の扱い**: rework サイクルでは step 3.7 で作成した**同一 worktree を再利用**する。新規 worktree は作成しない。step 3.7 の `git worktree list` チェックがこれを保証する。

```javascript
Agent({
  subagent_type: "parallel-worker",
  description: "Rework: fix review findings ({N}/3)",
  prompt: `レビューで以下の指摘がありました。修正してください。

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}

    **重要**: 修正は必ず `cd {WORKTREE_PATH}` してから行うこと。

    rework_attempt: {N} / 3（最大3回）

    指摘内容:
    {findings from review-worker}

    注意: これは {N} 回目の差し戻しです。最大3回で、3回で解決しない場合はユーザーにエスカレーションされます。
    全指摘を一括で修正してください。最終回（3/3）の場合は大規模変更を避け、確実にレビューを通過する最小修正を選んでください。

    修正後、品質チェック（rustfmt + clippy + cargo test）を実行して全パスを確認してください。
    完了報告に changed_files を含めること。`
})
```

オーケストレーターは rework_attempt のカウンタを管理する。修正後、再度 step 5（UT 品質検証）→ step 6（レビュー）を実行する。**差し戻し → 再レビューのサイクルは最大 3 回**。3 回で解決しない場合は残存指摘を添えてユーザーに報告する。

**カウンターのスコープ:**
- カウンターは**タスクごと**（task-id 単位）にリセットされる
- `_PhaseReview: true` のタスクも同様に最大 3 回まで差し戻し可能
- PhaseReview でのレビュー差し戻し時は、原因タスクを特定して修正するが、その修正も rework カウンターを消費する（PhaseReview の rework_attempt として記録）
- `retry_exhausted` の手動修正後に再開した場合、カウンターはリセットせずに引き継ぐ

#### review_action: escalate（D:仕様不一致、F:設計適合違反）

承認済み design.md との不一致、または仕様の解釈違いが検出された。ユーザーに review-worker の `findings` を提示し、判断を仰ぐ。

**重要: design.md は実装フェーズで変更しない。** 設計変更が必要な場合はそれまでの実装を破棄し、Phase 2（spec-design）からやり直す。したがって escalate の対応は「design.md の範囲内で実装を調整する」に限定される。

**対応フロー:**

1. ユーザーに findings を提示し、**design.md の範囲内でどう調整すべきか**を確認する
2. ユーザーの回答を当該タスクの `_Prompt` の Restrictions に追記する
   ```
   _Prompt 追記例:
   Restrictions: ... | [escalate対応] review-worker指摘: UserDetailDtoではなくUserDtoを使用すること。last_login_atはdesign.mdに未定義のため含めない
   ```
3. parallel-worker に rework として差し戻す（escalate → rework に切り替え）
4. 修正後、再度 step 5（UT）→ step 6（レビュー）を実行

rework と同じサイクル上限（最大3回）が適用される。3回で解決しない場合は、設計自体に問題がある可能性が高いため、ユーザーに Phase 2 からのやり直しを提案する。

### 7. Log Implementation (MANDATORY)

Call the `log-implementation` MCP tool BEFORE marking the task complete. A task without a log is not complete — this is the most commonly skipped step.

Required fields:
- `specName`: The spec name
- `taskId`: The task ID you just completed
- `summary`: Clear description of what was implemented (1-2 sentences)
- `filesModified`: List of files you edited
- `filesCreated`: List of new files — **include test files**
- `statistics`: `{ linesAdded: number, linesRemoved: number }`
- `artifacts` (REQUIRED — 該当するカテゴリのみ記載。実装内容がない場合は空オブジェクト `{}` を渡す):
  - `apiEndpoints`: API routes created/modified (method, path, purpose)。request/response の詳細は design.md 参照
  - `dbMigrations`: 作成したマイグレーション名とテーブル
  - `models`: 作成/変更した Model / DTO の名前と場所
  - `integrations`: 外部サービスとの接続（該当する場合のみ）
- `reviewProcess` (optional — review-worker が実行された場合のみ記録する。step 4〜6 のレビュー結果):
  - `reworkCount`: やり直し回数（一発でコミットできた場合は `0`）
  - `reviewOutcome`: 最終結果 — `"commit"` または `"escalated"`
  - `findings`: reworkCount > 0 の場合のみ記載。各レビュー試行の記録:
    ```json
    "reviewProcess": {
      "reworkCount": 2,
      "reviewOutcome": "commit",
      "findings": [
        {
          "attempt": 1,
          "categories": ["B:設計", "C:セキュリティ"],
          "summary": "UserRepo が AppError を使っていない。SQL クエリに生文字列連結あり",
          "action": "rework"
        },
        {
          "attempt": 2,
          "categories": ["B:設計"],
          "summary": "repository メソッドの戻り値型が design.md と不一致",
          "action": "rework"
        },
        {
          "attempt": 3,
          "categories": [],
          "summary": "全観点パス",
          "action": "commit"
        }
      ]
    }
    ```
  - reworkCount が 0 の場合（一発パス）は `findings` を省略してよい:
    ```json
    "reviewProcess": { "reworkCount": 0, "reviewOutcome": "commit" }
    ```

**log-implementation が失敗した場合:**
- タスクを `[x]` にしてはならない（ログなし完了は不完全）
- エラー内容をユーザーに報告し、手動でログを記録するか再試行するかを確認する
- MCP ツール自体が利用不可の場合: `.spec-workflow/specs/{spec-name}/Implementation Logs/` ディレクトリに手動でマークダウンファイルを作成することで代替可能

### 8. Complete the Task

Only after `log-implementation` returns success:
- Verify all success criteria from the `_Prompt` are met
- Edit tasks.md: Change `[-]` to `[x]`

#### Worktree のマージとクリーンアップ

review-worker がコミットした後、worktree ブランチをメインブランチに統合してクリーンアップする:

```bash
# メインブランチで worktree のコミットをマージ
git merge --no-ff "$BRANCH" -m "merge: {task-id} の実装を統合"

# worktree の削除
git worktree remove "$WORKTREE_PATH"
git branch -d "$BRANCH"
```

Then move to the next pending task and repeat.

## Monitoring Progress

Use the `spec-status` MCP tool at any time to check overall progress, task counts, and approval status.

## Rules

### ⛔ オーケストレーター禁止ルール（最優先）
- **コードを書かない** — 実装は parallel-worker のみ
- **テストを書かない** — テストも parallel-worker のみ
- **git commit しない** — コミットは review-worker のみ
- **エージェント呼び出しを省略しない** — 「シンプルだから」「自分でできるから」は理由にならない
- **step 4/5/6 のエージェント呼び出しは必須** — 例外なし

### 通常ルール
- **ホワイトボードは使用しない** — ホワイトボードは wave-harness 等の複数ワーカーを並列実行するワークフロー専用。spec-implement はタスクを逐次・1 ワーカーで処理するため、parallel-worker / review-worker に `Whiteboard path` を渡さない。
- Feature names use kebab-case
- One task in-progress at a time
- Always search implementation logs before coding (step 2)
- Follow TDD: tests first (RED), then implementation (GREEN), then refactor (REFACTOR)
- **Implementation (parallel-worker) and review (review-worker) are separate agents** — parallel-worker does not commit, review-worker does not implement
- Always call log-implementation before marking a task `[x]` (step 7)
- Include test files in `filesCreated` when logging
- A task marked `[x]` without a log is incomplete
- If you encounter blockers, document them and move to another task
