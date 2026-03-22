---
name: spec-tasks
description: "Phase 3 of spec-driven development: break an approved design into atomic implementation tasks. Use this skill after design is approved, when the user wants to create tasks, plan implementation steps, or break down work into actionable items. Triggers on: 'create tasks', 'break down into tasks', 'implementation plan', 'task breakdown for X', or any request to create a tasks.md document."
---

# Spec Tasks (Phase 3)

Break the approved design into atomic, implementable tasks. This phase converts architecture decisions into a concrete action plan.

## Prerequisites Check (MANDATORY — DO NOT SKIP)

Before doing anything else, verify all prerequisite files exist:

1. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists
2. Check `.spec-workflow/specs/{spec-name}/design.md` exists

If ANY file is missing — **STOP immediately.** Inform the user: "{filename} does not exist; cannot begin task breakdown. Please run {skill-name} first." Then exit this skill.

---

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

### 2.5 Detect New Project

新規プロジェクトかどうかを検出し、Git 初期化タスクの追加要否を判断する。

```bash
# Git リポジトリが存在するか確認
git -C "${projectPath}" rev-parse --is-inside-work-tree 2>/dev/null
```

**結果に応じた分岐:**

| 結果 | 判定 | アクション |
|------|------|-----------|
| `true` | 既存リポジトリ | Git 初期化タスク不要。Phase 0 に含めない |
| コマンド失敗（exit code 128） | 新規プロジェクト | Phase 0 の先頭に Git 初期化タスクを追加 |

新規プロジェクトの場合、Phase 0 の先頭（他のすべてのタスクの前）に以下のタスクを自動追加する:

```markdown
## Phase 0: Project Setup

- [ ] 0.0 Initialize Git repository
  - File: .gitignore
  - _TDDSkip: true_
  - _Requirements: N/A_
  - _Prompt: Role: DevOps Engineer | Task: Initialize a Git repository, create an appropriate .gitignore for the project type (Rust: target/, *.swp, .env etc.), and make the initial commit | Restrictions: Do not include secrets or build artifacts in the initial commit. The .gitignore must cover the project's language/framework (e.g., /target for Rust, node_modules for Node.js). Do not configure remote repository (user will do this manually) | Success: `git log` shows the initial commit, `.gitignore` exists and covers the project type_
```

**注意:**
- Git 初期化タスクは常に Phase 0 の最初のタスク（0.0）とする
- 後続のタスク番号は 0.1 から始める
- 既存リポジトリの場合、タスク番号は従来通り 0.1 から始まる

### 3. Create Tasks

Convert the design into atomic tasks. Each task should touch 1-3 files and be independently implementable. Include:

- File paths that will be created or modified
- Requirement references (which requirements the task implements)
- Logical ordering (dependencies between tasks)

#### Single Responsibility Criteria

Task granularity is determined by the number of **responsibilities**, not just the number of files. 1 task = 1 responsibility.

**Decision rules:**
1. **Can the task be described in a single sentence?** — If multiple behaviors are joined with "and", consider splitting
2. **Do the Success criteria converge on a single verification target?** — If there are multiple independent Success conditions, split the task
3. **Does it complete within one TDD cycle?** — All tests written in the RED phase belong to the same module/function

**Examples requiring splitting:**
- "Create model and implement API endpoint" → `create model` + `implement endpoint`
- "Implement CRUD with validation and caching" → `implement CRUD` + `add validation` + `add caching`
- "Define DB schema and implement repository" → `create migration` + `implement repository`

**Examples that do NOT require splitting (fit within 1 responsibility):**
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
- **`_TestFocus` field** — Structured in 4 categories (Happy Path / Boundary Values / Error Handling / Edge Cases) as required by the unit-test-engineer. Free-form text is not allowed.

#### Tasks eligible for TDD skip (`_TDDSkip: true`)

Tasks with no runtime behavior and nothing to test receive `_TDDSkip: true`. For these tasks, parallel-worker skips the TDD cycle and performs direct implementation + quality checks only.

**Tasks where `_TDDSkip: true` applies:**
- Project initialization (`cargo init`, directory structure creation, `Cargo.toml` dependency additions)
- Infrastructure/config files (Dockerfile, docker-compose.yml, CI/CD configuration)
- DB migrations (creating up.sql/down.sql via `diesel migration generate`)
- Environment config files (`.env.example`, `diesel.toml`, `.cargo/config.toml`)

**Tasks where `_TDDSkip: true` does NOT apply (must be merged):**
- Interface-only tasks (trait/struct/enum definitions only) → merge into the first implementing task

Decision rule: "Is this task self-contained?"
- A Dockerfile is self-contained → `_TDDSkip: true`
- A trait definition is meaningless without an implementing task → merge

`_TDDSkip: true` tasks do not need a `_TestFocus` field (may be omitted).

### 4. Generate _Prompt Fields

This is critical for implementation quality. Each task needs a `_Prompt` field with structured AI guidance, plus a `_TestFocus` field for TDD:

```markdown
## Phase 0: Project Setup

- [ ] 0.1 Initialize project and create Dockerfile
  - File: Cargo.toml, Dockerfile, docker-compose.yml, .env.example
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: Initialize Cargo project, create Dockerfile and docker-compose.yml for Axum + PostgreSQL + Valkey | Restrictions: Do not include secrets in .env.example | Success: Containers start with docker-compose up_

- [ ] 0.2 Create DB migration for users table
  - File: migrations/YYYYMMDD_create_users/up.sql, down.sql
  - _TDDSkip: true_
  - _Requirements: REQ-1_
  - _Prompt: Role: Backend Developer | Task: Create users table migration with diesel migration generate | Restrictions: Strictly follow the DB Schema definition in design.md | Success: diesel migration run succeeds_

## Phase 1: Core Models & Repository

- [ ] 1.1 Create User model with Diesel derives
  - File: src/models/user.rs, src/schema.rs
  - Implement Queryable, Insertable, AsChangeset
  - _Leverage: src/models/mod.rs_
  - _Requirements: REQ-1_
  - _TestFocus: Happy Path: construction and field access for User/NewUser/UpdateUser | Boundary Values: minimum (1 char) and maximum (255 chars) name length | Error Handling: empty string name, invalid email format | Edge Cases: multi-byte character name_
  - _Prompt: Role: Backend Developer | Task: Create User model with Queryable/Insertable/AsChangeset derives | Restrictions: schema.rs is auto-generated by diesel print-schema — do not edit manually | Success: User, NewUser, UpdateUser structs are defined and the code compiles_

- [ ] 1.2 Implement UserRepository with CRUD operations
  - File: src/db/repository/users.rs
  - Implement find_by_id, list, create, update, delete
  - _Leverage: src/db/mod.rs, src/models/user.rs_
  - _Requirements: REQ-1_
  - _TestFocus: Happy Path: success paths for all CRUD operations | Boundary Values: list with 0 / 1 / many records | Error Handling: find with nonexistent ID, create with duplicate key, DB connection error | Edge Cases: concurrent updates_
  - _Prompt: Role: Backend Developer | Task: Implement UserRepository with CRUD operations using diesel-async | Restrictions: All methods must return Result<T, AppError> | Success: All CRUD methods are implemented and tests pass_

- [ ] 1.3 Review and commit Phase 1
  - _PhaseReview: true_
  - _Prompt: Role: Code reviewer | Task: Review all Phase 1 changes, run tests, commit | Success: All tests pass, committed_
```

**Note:** The Task field must focus on a single responsibility. Do not join multiple responsibilities with "and" (e.g., "Create model and implement repository").

Also include:
- `_Leverage`: Existing files/utilities to reuse (copied from the Code Reuse Analysis table in design.md)
- `_Requirements`: Which requirements this task fulfills (traceability)
- `_TestFocus`: Written in the 4-category structured format (see below)

#### _TestFocus Format

To align with the unit-test-engineer's required test coverage, use the following 4-category structure. Free-form text is not allowed.

```
_TestFocus: Happy Path: {specific test targets} | Boundary Values: {specific boundaries} | Error Handling: {specific error cases} | Edge Cases: {specific cases}
```

If a category does not apply, explicitly write "N/A" (do not omit it).
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

After creating tasks.md, back-fill the "Target Task ID" column in the Requirements Traceability Matrix in design.md. This enables tracing from design components to tasks.

1. Read the Traceability Matrix in design.md
2. Identify the corresponding task ID from tasks.md for each component row
3. Fill in the "Target Task ID" column
4. **Verify that every component has an assigned task** — if any component row is unassigned, add a task and update the matrix

### 7. Self-Review via Subagent (before approval)

Validate the document in **2 stages** before approval.

#### Step A: fix (mechanical auto-fixes)

Auto-fix placeholders, formatting, and typos. Do not add or change content:

```
Agent({
  subagent_type: "general-purpose",
  description: "Fix tasks spec (auto-fix)",
  prompt: "You are a spec document reviewer. Auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/tasks.md

    Document type: tasks

    Items eligible for auto-fix (may directly modify the file):
    - Remove placeholder text ([describe...], TODO, TBD)
    - Fix markdown formatting (table alignment, heading levels, etc.)
    - Obvious typos

    Items NOT eligible for auto-fix (report as issues only):
    - Adding, removing, or merging tasks
    - Changing the content of _Prompt, _Leverage, _Requirements, etc.
    - Traceability inconsistencies

    Mode: fix — Return a structured report (auto-fixed items + remaining issues)."
})
```

#### Step B: check (content validation)

After fix completes, detect content issues. Do not modify the file:

```
Agent({
  subagent_type: "general-purpose",
  description: "Review tasks spec (check)",
  prompt: "You are a spec document reviewer. Review the document (do NOT modify the file) at:
    {project-path}/.spec-workflow/specs/{spec-name}/tasks.md

    Document type: tasks
    Template: {project-path}/.spec-workflow/templates/tasks-template.md
    Requirements: {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    Design: {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Checks:
    1. TEMPLATE: Every task has - [ ] marker, file path(s), _Leverage, _Requirements, _Prompt fields
    2. _Prompt has: Role, Task, Restrictions, Success fields in the format "Role: ... | Task: ... | Restrictions: ... | Success: ..."
    3. CROSS-REFERENCE: Read requirements.md and design.md —
       every requirement must have at least one implementing task,
       every design component must have at least one creating task,
       _Requirements IDs must match actual requirement IDs
    4. TRACEABILITY: Verify that the Target Task ID column is filled in for all components in the Requirements Traceability Matrix in design.md.
       If any component row is empty, add a task to tasks.md and update the matrix in design.md.
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

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 8. Approval Workflow

Same strict process — verbal approval is never accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only
2. **Poll status**: `approvals` tool, `action: 'status'`, keep polling
3. **Handle result**:
   - **needs-revision**: Update tasks using reviewer comments, spawn the review subagent again, submit NEW approval
   - **approved**: Move to cleanup
4. **Cleanup**: `approvals` tool, `action: 'delete'` — must succeed
   - If delete fails: STOP, return to polling
5. **Spec complete**: After successful cleanup, tell the user:
   > "Spec complete. tasks.md has been approved. To begin implementation, run `/spec-implement`."
   **Stop here.** No automatic startup of any kind until the user personally types `/spec-implement` or an implementation trigger phrase (e.g., "implement task X", "start coding"). Auto-triggering on confirmation responses like "yes" or "go ahead" is also prohibited.

## Rules

- Feature names use kebab-case
- One spec at a time
- Tasks should be atomic (1-3 files each)
- Every task needs a `_Prompt` field with structured guidance
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
