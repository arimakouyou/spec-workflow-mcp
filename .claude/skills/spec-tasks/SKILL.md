---
name: spec-tasks
description: "Phase 3 of spec-driven development: break an approved design into atomic implementation tasks. Use this skill after design is approved, when the user wants to create tasks, plan implementation steps, or break down work into actionable items. Triggers on: 'create tasks', 'break down into tasks', 'implementation plan', 'task breakdown for X', or any request to create a tasks.md document."
---

# Spec Tasks (Phase 3)

Break the approved design into atomic, implementable tasks. This phase converts architecture decisions into a concrete action plan.

## Prerequisites

Design must be approved and cleaned up (Phases 1-2 complete). If not, use `/spec-design` first.

## Inputs

The same **spec name** used in previous phases (kebab-case, e.g., `user-authentication`).

## Process

### 1. Load the Template

Check for a custom template first, then fall back to the default:

1. `.spec-workflow/user-templates/tasks-template.md` (custom)
2. `.spec-workflow/templates/tasks-template.md` (default)

### 2. Read Approved Documents

- `.spec-workflow/specs/{spec-name}/requirements.md`
- `.spec-workflow/specs/{spec-name}/design.md`

### 3. Create Tasks

Convert the design into atomic tasks. Each task should touch 1-3 files and be independently implementable. Include:

- File paths that will be created or modified
- Requirement references (which requirements the task implements)
- Logical ordering (dependencies between tasks)

#### 単一責務の判定基準

タスクの粒度は「ファイル数」だけでなく「責務数」で判定する。1タスク = 1責務。

**判定ルール:**
1. **Task を1文で説明できるか** — "and" で複数の動作を繋ぐ場合は分割を検討
2. **Success 基準が1つの検証対象に集約されるか** — 独立した複数の Success 条件がある場合はタスク分割
3. **TDD の1サイクルで完結するか** — RED で書くテストが全て同じモジュール/関数に属する

**分割が必要な例:**
- "Create model and implement API endpoint" → `model 作成` + `endpoint 実装`
- "Implement CRUD with validation and caching" → `CRUD 実装` + `validation 追加` + `caching 追加`
- "Define DB schema and implement repository" → `migration 作成` + `repository 実装`

**分割不要な例（1責務に収まる）:**
- "Create User model with Queryable/Insertable/AsChangeset derives"
- "Implement GET /users/{id} endpoint returning UserDto"
- "Add email format validation to CreateUserRequest"

### 3.5 Phase-Based Organization

Group tasks into phases using `## Phase N: Title` headings. Each phase is a **vertical slice** — a testable, committable increment that delivers end-to-end value.

- 1 phase = 2-5 implementation tasks + 1 review task
- Each phase ends with a `_PhaseReview: true_` task for review and commit
- Phases are ordered by dependency (core → API → UI → integration)

### 3.6 TDD Task Design Rules

- **No standalone test tasks.** TDD handles testing automatically in each task's RED phase.
- **Each task must be independently testable** — it must produce observable behavior that can be verified.
- **`_TestFocus` field** — unit-test-engineer の必須テスト観点（正常系/境界値/例外処理/エッジケース）の4カテゴリで構造化して記述する。自由記述は禁止。

#### TDD スキップ可能タスク（`_TDDSkip: true`）

実行時の振る舞いがなくテスト不可能なタスクには `_TDDSkip: true` を付与する。該当タスクは parallel-worker が TDD サイクルをスキップし、直接実装 + 品質チェックのみ実行する。

**`_TDDSkip: true` が適用できるタスク:**
- プロジェクト初期化（`cargo init`, ディレクトリ構成作成, `Cargo.toml` 依存追加）
- インフラ/設定ファイル（Dockerfile, docker-compose.yml, CI/CD 設定）
- DB マイグレーション（`diesel migration generate` による up.sql/down.sql 作成）
- 環境設定ファイル（`.env.example`, `diesel.toml`, `.cargo/config.toml`）

**`_TDDSkip: true` が適用できないタスク（マージが必要）:**
- Interface-only task（trait/struct/enum 定義のみ） → 最初の実装タスクにマージ

判定基準: 「そのタスク単独で完結するか」
- Dockerfile は単独で完結する → `_TDDSkip: true`
- trait 定義は実装タスクがないと意味がない → マージ

`_TDDSkip: true` タスクには `_TestFocus` は不要（省略可）。

### 4. Generate _Prompt Fields

This is critical for implementation quality. Each task needs a `_Prompt` field with structured AI guidance, plus a `_TestFocus` field for TDD:

```markdown
## Phase 0: Project Setup

- [ ] 0.1 Initialize project and create Dockerfile
  - File: Cargo.toml, Dockerfile, docker-compose.yml, .env.example
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: Initialize Cargo project, create Dockerfile and docker-compose.yml for Axum + PostgreSQL + Valkey | Restrictions: .env.example にシークレットを含めない | Success: docker-compose up でコンテナが起動する_

- [ ] 0.2 Create DB migration for users table
  - File: migrations/YYYYMMDD_create_users/up.sql, down.sql
  - _TDDSkip: true_
  - _Requirements: REQ-1_
  - _Prompt: Role: Backend Developer | Task: Create users table migration with diesel migration generate | Restrictions: design.md の DB Schema 定義に厳密に従う | Success: diesel migration run が成功する_

## Phase 1: Core Models & Repository

- [ ] 1.1 Create User model with Diesel derives
  - File: src/models/user.rs, src/schema.rs
  - Queryable, Insertable, AsChangeset を実装
  - _Leverage: src/models/mod.rs_
  - _Requirements: REQ-1_
  - _TestFocus: 正常系: User/NewUser/UpdateUser の生成と各フィールドのアクセス | 境界値: name の最小長(1文字)/最大長(255文字) | 例外処理: 空文字 name、不正な email 形式 | エッジケース: マルチバイト文字 name_
  - _Prompt: Role: Backend Developer | Task: Create User model with Queryable/Insertable/AsChangeset derives | Restrictions: schema.rs は diesel print-schema で自動生成、手動編集しない | Success: User, NewUser, UpdateUser 構造体が定義され、コンパイルが通る_

- [ ] 1.2 Implement UserRepository with CRUD operations
  - File: src/db/repository/users.rs
  - find_by_id, list, create, update, delete を実装
  - _Leverage: src/db/mod.rs, src/models/user.rs_
  - _Requirements: REQ-1_
  - _TestFocus: 正常系: 全 CRUD 操作の成功パス | 境界値: list の 0件/1件/多数件 | 例外処理: 存在しない ID の find、重複キーの create、DB 接続エラー | エッジケース: 同時更新_
  - _Prompt: Role: Backend Developer | Task: Implement UserRepository with CRUD operations using diesel-async | Restrictions: 全メソッドは Result<T, AppError> を返す | Success: 全 CRUD メソッドが実装され、テストが通る_

- [ ] 1.3 Review and commit Phase 1
  - _PhaseReview: true_
  - _Prompt: Role: Code reviewer | Task: Review all Phase 1 changes, run tests, commit | Success: All tests pass, committed_
```

**注意:** Task フィールドは1つの責務に集中させる。"Create model and implement repository" のように "and" で複数責務を繋がない。

Also include:
- `_Leverage`: Existing files/utilities to reuse（design.md の Code Reuse Analysis テーブルから転記）
- `_Requirements`: Which requirements this task fulfills (traceability)
- `_TestFocus`: 4カテゴリ構造化形式で記述（下記参照）

#### _TestFocus フォーマット

unit-test-engineer の必須テスト観点と整合させるため、以下の4カテゴリで構造化する。自由記述は禁止。

```
_TestFocus: 正常系: {具体的なテスト対象} | 境界値: {具体的な境界} | 例外処理: {具体的なエラーケース} | エッジケース: {具体的なケース}
```

該当しないカテゴリがある場合は「該当なし」と明記する（省略しない）。
- Instructions about marking task status in tasks.md and logging implementation with `log-implementation` tool

### 5. Create the Document

Write the tasks document to:
```
.spec-workflow/specs/{spec-name}/tasks.md
```

Task status markers:
- `- [ ]` = Pending
- `- [-]` = In progress
- `- [x]` = Completed

### 6. Update Design Traceability Matrix

tasks.md の作成後、design.md の Requirements Traceability Matrix に「対象タスク ID」を逆記入する。これにより design コンポーネント → タスクの照合が可能になる。

1. design.md の Traceability Matrix を Read する
2. 各コンポーネント行に対応するタスク ID を tasks.md から特定する
3. 「対象タスク ID」列を埋める
4. **全コンポーネントにタスクが割り当てられているか確認する** — 割り当てのないコンポーネントが見つかった場合はタスクを追加する

### 7. Self-Review via Subagent (before approval)

Spawn a subagent to review and fix the document before requesting approval:

```
Agent({
  subagent_type: "general-purpose",
  description: "Review tasks spec",
  prompt: "You are a spec document reviewer. Review and fix the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/tasks.md

    Document type: tasks
    Template: {project-path}/.spec-workflow/templates/tasks-template.md
    Requirements: {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    Design: {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Checks:
    1. TEMPLATE: Every task has - [ ] marker, file path(s), _Leverage, _Requirements, _Prompt fields
    2. _Prompt has: Role, Task, Restrictions, Success. Starts with 'Implement the task for spec {spec-name}...'
    3. CROSS-REFERENCE: Read requirements.md and design.md —
       every requirement must have at least one implementing task,
       every design component must have at least one creating task,
       _Requirements IDs must match actual requirement IDs
    4. TRACEABILITY: design.md の Requirements Traceability Matrix の全コンポーネントに対応するタスク ID が記入されているか。
       空欄のコンポーネントがあれば tasks.md にタスクを追加し、design.md のマトリクスも更新する。
    5. Tasks are atomic (1-3 files), in logical dependency order
    6. No placeholder text, descriptions specific enough for AI implementation
    7. PHASE STRUCTURE: Tasks are grouped under ## Phase headings with vertical slices
    8. TDD: No standalone test tasks (e.g., 'write tests', 'create unit tests')
    9. Every non-PhaseReview task has a _TestFocus field
    10. Each phase ends with a _PhaseReview: true_ task

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

Wait for the subagent to complete, then proceed to approval.

### 8. Approval Workflow

Same strict process — verbal approval is never accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only
2. **Poll status**: `approvals` tool, `action: 'status'`, keep polling
3. **Handle result**:
   - **needs-revision**: Update tasks using reviewer comments, spawn the review subagent again, submit NEW approval
   - **approved**: Move to cleanup
4. **Cleanup**: `approvals` tool, `action: 'delete'` — must succeed
   - If delete fails: STOP, return to polling
5. **Spec complete**: After successful cleanup, tell the user: "Spec complete. Ready to implement?" Then use `/spec-implement` to begin.

## Rules

- Feature names use kebab-case
- One spec at a time
- Tasks should be atomic (1-3 files each)
- Every task needs a `_Prompt` field with structured guidance
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
