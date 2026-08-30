---
name: spec-tasks
description: "Phase 4 of spec-driven development: break an approved design into atomic implementation tasks. Use this skill after test design is approved, when the user wants to create tasks, plan implementation steps, or break down work into actionable items. Triggers on: 'create tasks', 'break down into tasks', 'implementation plan', 'task breakdown for X', or any request to create a tasks.md document."
---

# Spec Tasks (Phase 4)

Break the approved design into atomic, implementable tasks. This phase converts architecture decisions into a concrete action plan.

## Prerequisites Check (MANDATORY — DO NOT SKIP)

Before doing anything else, verify all prerequisite files exist:

1. Check `.spec-workflow/specs/{spec-name}/request-spec.md` exists
2. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists
3. Check `.spec-workflow/specs/{spec-name}/design.md` exists
4. Check `.spec-workflow/specs/{spec-name}/test-design.md` exists

**Legacy workflow exception**: If `request-spec.md` does not exist but `requirements.md` already exists, this is a legacy spec created before Phase 0. Skip the `request-spec.md` check and proceed normally.

If `requirements.md`, `design.md`, or `test-design.md` is missing — **STOP immediately.** Inform the user: "{filename} does not exist; cannot begin task breakdown. Please run {skill-name} first." Then exit this skill.

| Missing File | Required Skill | Skip if legacy? |
|-------------|---------------|-----------------|
| request-spec.md | `/spec-request-spec` | Yes (if requirements.md exists) |
| requirements.md | `/spec-requirements` | No |
| design.md | `/spec-design` | No |
| test-design.md | `/spec-test-design` | No |

---

Test design must be approved and cleaned up (Phases 1-3 complete). If not, use `/spec-test-design` first.

## Inputs

The same **spec name** used in previous phases (kebab-case, e.g., `user-authentication`).

## Process

### 1. Load the Template

Check for a custom template first, then fall back to the default:

1. `.spec-workflow/user-templates/tasks-template.md` (custom)
2. `.spec-workflow/templates/tasks-template.md` (default)

### 2. Read Approved Documents

- `.spec-workflow/specs/{spec-name}/request-spec.md`
- `.spec-workflow/specs/{spec-name}/requirements.md`
- `.spec-workflow/specs/{spec-name}/design.md`
- `.spec-workflow/specs/{spec-name}/test-design.md`

### 2.5 Detect New Project

Detect whether this is a new project and decide whether to add a Git initialization task.

```bash
# Check whether a Git repository exists
git -C "{project-path}" rev-parse --is-inside-work-tree 2>/dev/null
echo $?
```

**Branching by result (exit code takes precedence):**

| Exit Code | `--is-inside-work-tree` Output | Verdict | Action |
|-----------|-------------------------------|---------|--------|
| `0` | `true` | Existing repository (with working tree) | No Git init task needed. Do not include in Phase 0 |
| `0` | `false` | Existing repository (bare repo or directly inside `.git` directory) | No Git init task needed. If necessary, consider a separate task to migrate from bare to a normal repository |
| `128` | (any) | New project (Git not initialized) | Add Git init task at the top of Phase 0 |
| `127` | (any) | `git` command not found | Report to user: "git is not installed. Please install git and re-run." Abort task generation |
| Other | (any) | Invalid path / permission error, etc. | Report to user: "An error occurred while checking the project path (exit code: {N}). Please verify the path and access permissions." Abort task generation |

For a new project (exit code 128), automatically add the following task at the top of Phase 0 (before all other tasks):

```markdown
## Phase 0: Project Setup

- [ ] 0.0 Initialize Git repository
  - File: .gitignore
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: Initialize a Git repository, create an appropriate .gitignore for the project type (Rust: target/, *.swp, .env etc.), and make the initial commit | Restrictions: Do not include secrets or build artifacts in the initial commit. The .gitignore must cover the project's language/framework (e.g., /target for Rust, node_modules for Node.js). Do not configure remote repository (user will do this manually) | Success: `git log` shows the initial commit, `.gitignore` exists and covers the project type_
```

**Notes:**
- The Git init task is always the first task in Phase 0 (0.0)
- Subsequent task numbers start from 0.1
- For existing repositories, task numbers start from 0.1 as before

### 2.6 Detect Container Requirements

Read the Container Architecture section of design.md and decide whether to add container setup tasks.

**Detection logic:**
1. Whether design.md has a "Container Architecture" section
2. Whether services are listed in the Service Dependencies table

**If Container Architecture exists**, add the following tasks to Phase 0 (after the Git init task, before other setup tasks):

```markdown
- [ ] 0.1 Create Dockerfile and docker-compose.yml
  - File: Dockerfile, docker-compose.yml, .dockerignore
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: Create a Dockerfile (multi-stage build) and docker-compose.yml based on the Container Architecture in design.md. Include all services from the Service Dependencies table | Restrictions: Do not embed secrets in the Dockerfile. Exclude unnecessary files via .dockerignore. Port numbers must follow the definitions in design.md | Success: `docker-compose up -d` starts all services_

- [ ] 0.2 Create test container configuration
  - File: docker-compose.test.yml
  - _TDDSkip: true_
  - _DependsOn: 0.1_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: Create docker-compose.test.yml for tests. External ports must be specified via environment variables (e.g., ${TEST_DB_PORT}:5432) rather than fixed values; the startup script generates a random 5-digit port (10000-65535) and passes it in. If TEST_DB_PORT is unset, fail startup. Include a test initialization script for the DB | Restrictions: Do not modify the production docker-compose.yml. Do not persist test volumes (tmpfs recommended). Do not use fixed offset ports (e.g., 5432→15432) since they risk collision with other processes | Success: `docker-compose -f docker-compose.test.yml up -d` starts on a random port and coexists with the production stack_
```

**If Container Architecture does not exist**: Do not add container tasks (as before).

**Note:** When the Git init task (0.0) exists, the container tasks become 0.1 and 0.2, and other setup tasks start from 0.3.

### 2.7 Detect CI Workflow Requirements

Check whether a PR-triggered CI workflow exists under `.github/workflows/`, and decide whether to add a CI setup task.

**Detection logic:**

```bash
# Whether a PR-triggered CI workflow exists
# Detects pull_request: (mapping form), - pull_request (list form), [..., pull_request, ...] (inline array form)
if test -d .github/workflows; then
  grep -rEl '(^\s*pull_request:|^\s*-\s*pull_request|\[\s*.*pull_request)' .github/workflows --include='*.yml' --include='*.yaml'
  echo $?
else
  echo "1"
fi
```

| Result | Verdict | Action |
|--------|---------|--------|
| File found (exit 0) | PR-triggered CI workflow already exists | Do not add a CI task |
| No file found (exit 1) | PR-triggered CI workflow not yet created | Add a CI setup task to Phase 0 |
| `.github/workflows/` does not exist | CI not configured | Add a CI setup task to Phase 0 |

**If no PR-triggered CI workflow exists**, add the following task to Phase 0 (in the order: Git init → container → CI):

```markdown
- [ ] 0.N Create CI workflow
  - File: .github/workflows/ci.yml
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: Use the /setup-ci skill to generate a PR-triggered GitHub Actions CI workflow appropriate for the project type. Include the same steps as the quality check commands defined in ${CLAUDE_PLUGIN_ROOT}/rules/quality-checks.md. If design.md has a Container Architecture, use the --with-services option | Restrictions: Do not hard-code secrets in the workflow. Do not modify existing CI workflows (e.g., npm-publish.yml) | Success: CI runs automatically on PR creation and the quality checks defined in ${CLAUDE_PLUGIN_ROOT}/rules/quality-checks.md pass_
```

**Note:** Assign the task number `0.N` based on the order within Phase 0 (Git init 0.0 → container 0.1, 0.2 → CI 0.3. If there is no container task, shift up).

### 2.8 Detect ADR Directory

Check whether the `.claude/_docs/adr/` directory exists and decide whether to add an ADR process initialization task.

**Detection logic:**

```bash
test -d .claude/_docs/adr && test -f .claude/_docs/adr/INDEX.md
echo $?
```

| Result | Verdict | Action |
|--------|---------|--------|
| exit 0 | ADR directory and INDEX.md exist | Do not add a task |
| exit 1 | ADR not initialized | Add an ADR init task to Phase 0 |

**If ADR is not initialized**, add the following task to Phase 0 (after the CI task):

```markdown
- [ ] 0.N Initialize ADR directory
  - File: .claude/_docs/adr/INDEX.md
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: Create the .claude/_docs/adr/ directory and INDEX.md. INDEX.md should contain only the ADR table header (ADR, Title, Status, Date). Use the /adr skill to generate initial ADRs from design.md's Key Design Decisions | Restrictions: Do not modify existing files under .claude/ | Success: .claude/_docs/adr/INDEX.md exists, and ADR files corresponding to the major decisions in design.md have been created_
```

**Note:** This task number is the last setup task in Phase 0 (in the order: Git init → container → CI → ADR).

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

- 1 phase = 2-5 implementation tasks + 1 refactor task + 1 review task
- Each phase ends with a `_PhaseRefactor: true_` task followed by a `_PhaseReview: true_` task
  - The refactor task consumes `.spec-workflow/specs/{spec-name}/refactor-backlog.md` (`${CLAUDE_PLUGIN_ROOT}/rules/refactor-backlog.md`): restructuring that implementation and review tasks noticed but could not do within their own scope (cross-file duplication, shared helpers, placement). It has no `_TestFocus` (behavior-preserving, no new tests) and no `File:` list (its files are whatever the backlog names). Always generate it, even though the backlog does not exist at planning time — an empty backlog completes the task as a no-op
- Phases are ordered by dependency (core → API → UI → integration)

### 3.6 IT / ST / E2E Test Tasks (revised by J-5)

Based on the IT / ST / E2E specs in test-design.md, place test tasks at the appropriate position in each Phase. See `quality-checks.md` Test Taxonomy for the responsibilities of each layer.

#### IT tasks (backend HTTP API only)
- Create one task per IT spec (IT-1, IT-2, ...) in test-design.md
- **Placement**: in the Phase where all target components are already implemented (typically immediately before PhaseReview at the end of the backend Phase)
- `_TestFocus` references the IT spec in test-design.md and enumerates Verification Points
- The `_Prompt` Task explicitly states "Implement a backend HTTP API integration test based on the IT-{N} spec in test-design.md"
- **Scope**: Do not include UI operations / DOM checks (see `quality-checks.md` Test Taxonomy)

#### ST tasks (single-feature full-stack, newly introduced by J-7)
- Create one task per ST spec (ST-1, ST-2, ...) in test-design.md
- **Placement**: at the **end** of the Phase that completes all components / endpoints for the target feature (after CT/IT, before E2E)
- `_TestFocus` references the ST spec in test-design.md and enumerates Test Path / Verification Points
- The `_Prompt` Task explicitly states "Implement a single-feature full-stack test based on the ST-{N} spec in test-design.md"
- **Scope**: A single feature only (do not chain multiple features)

#### E2E tasks (user journey only)
- Place a task per E2E spec (E2E-1, E2E-2, ...) in the **final Phase**
- `_TestFocus` references the E2E spec in test-design.md and enumerates Scenario Steps and Success Criteria
- The `_Prompt` Task explicitly states "Implement a user journey E2E test based on the E2E-{N} spec in test-design.md"
- **Scope**: Only user journeys that chain multiple features (assign individual feature tests to ST)

#### Placement order

```
Phase N (backend implementation):  ... → IT-N tasks → PhaseRefactor → PhaseReview
Phase M (UI implementation):       ... → CT-N tasks (after H implementation) → PhaseRefactor → PhaseReview
Phase L (feature completion):      ... → ST-N tasks → PhaseRefactor → PhaseReview
Final Phase:                       E2E-N tasks → PhaseRefactor → Final PhaseReview
```

### 3.7 TDD Task Design Rules

- **No standalone unit test tasks.** TDD handles unit testing automatically in each task's RED phase. However, IT/E2E test tasks (defined in section 3.6) are **allowed and expected** as separate tasks — they implement integration and end-to-end tests from test-design.md specifications.
- **Each task must be independently testable** — it must produce observable behavior that can be verified.
- **`_TestFocus` field** — Structured in 4 categories (Happy Path / Boundary Values / Error Handling / Edge Cases) as required by the unit-test-engineer. Free-form text is not allowed. **Must be derived from test-design.md**: reference the corresponding UT spec IDs (e.g., UT-1.1, UT-1.2) and include the concrete test cases defined there.

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
  - _DependsOn: 1.1_
  - _Leverage: src/db/mod.rs, src/models/user.rs_
  - _Requirements: REQ-1_
  - _TestFocus: Happy Path: success paths for all CRUD operations | Boundary Values: list with 0 / 1 / many records | Error Handling: find with nonexistent ID, create with duplicate key, DB connection error | Edge Cases: concurrent updates_
  - _Prompt: Role: Backend Developer | Task: Implement UserRepository with CRUD operations using diesel-async | Restrictions: All methods must return Result<T, AppError> | Success: All CRUD methods are implemented and tests pass_

- [ ] 1.3 Refactor Phase 1 from the backlog
  - _PhaseRefactor: true_
  - _Prompt: Role: Refactoring engineer | Task: Consume every open entry of .spec-workflow/specs/{spec-name}/refactor-backlog.md whose files belong to Phase 1 or earlier, per rules/refactor-backlog.md RB4 | Restrictions: Behavior-preserving only — no test expectation changes, no public API changes, no design.md changes, no new features; mark entries that would need any of those as deferred or rejected with a reason | Success: No open backlog entry remains for Phase 1, every touched entry has a Resolved in value, all existing tests pass, quality checks pass. An absent or empty backlog completes the task as a no-op_

- [ ] 1.4 Review and commit Phase 1
  - _PhaseReview: true_
  - _Prompt: Role: Code reviewer | Task: Review all Phase 1 changes, run tests, verify the refactor backlog per rules/refactor-backlog.md RB5, commit | Success: All tests pass, no open backlog entry for Phase 1, committed_
```

#### UI Component task template (added by D, dapper-hardening)

A task for a UI component (Leptos / Blazor / React, etc.) **must describe** all of the following in `_Prompt.Task`:

1. **view! / output DOM**: Explicitly state "render {expected elements} such as `<img src=...>` and `<button>...</button>` inside view!"
2. **Dependency wiring**: For each server fn / external API / sibling component listed in design.md DES-N's `Dependencies:` column, explicitly state "call / integrate with / receive {dependency name}"
3. **data-testid attachment**: Attach the testids referenced in the CT/E2E specs of test-design.md at the corresponding positions in view! (defining constants in test_ids.rs etc. is recommended)
4. **Event listener attach**: Wire event handlers such as `on:click` / `on:submit` / `on:input` so they update signals

Write `_Prompt.Success` as **behavioral evidence** (grep alone is insufficient; Check 18 SUCCESS_BEHAVIORAL_VERIFICATION will error):

- CT-N PASSes (mount + signal + DOM observation chain)
- Auxiliary checks such as grep may be added if needed (cannot stand alone)

```markdown
- [ ] 4.4 Implement ThumbnailGrid component
  - File: crates/app/src/components/thumbnail_grid.rs
  - Render thumbnail items from list_folder Resource
  - _DependsOn: 4.3
  - _Leverage: crates/app/src/server_fns/list_folder.rs, crates/app/src/test_ids.rs
  - _Requirements: REQ-2.1, REQ-2.2
  - _TestFocus: Happy Path: render 5 images / Boundary Values: 0 / 1 / 200 images / Error Handling: error display when list_folder errors / Edge Cases: multi-byte path / Negative Assertions: list_folder is called only once / Isolation Properties: list_folder goes through MockServer
  - _Prompt: Role: Frontend Component Engineer | Task: Implement the ThumbnailGrid component. Inside view!, call list_folder via Resource::new, show pending state with Suspense, attach <img src="/api/thumbnails/{path}"> + data-testid="thumbnail-item" to each image, and execute the on_open callback on:click | Restrictions: Do not change the Interfaces of design.md DES-12. Do not stop at extracting pure helpers only (Check 18) | Success: CT-12.1 (initial render) / CT-12.2 (5-image render) / CT-12.3 (click → on_open invocation) all PASS, and grep detects data-testid="thumbnail-grid" / "thumbnail-item" inside view!_
```

**Note:** The Task field must focus on a single responsibility. Do not join multiple responsibilities with "and" (e.g., "Create model and implement repository").

Also include:
- `_Leverage`: Existing files/utilities to reuse (copied from the Code Reuse Analysis table in design.md)
- `_Requirements`: Which requirements this task fulfills (traceability)
- `_DependsOn`: IDs (comma-separated) of other tasks within the same Phase that this task depends on. Omit if there are no dependencies. A task with dependencies is not run until its dependencies finish. Cross-Phase dependencies are unnecessary (implicitly guaranteed by Phase order). Example: `_DependsOn: 1.1, 1.2_`
- `_TestFocus`: Written in the 4-category structured format (see below)
- `_BugFix` / `_RegressionBugId` (made mandatory by J-10; see `dapper-hardening-orchestrator.md`):
  - For bug-fix tasks, `_BugFix: true_` is mandatory, along with `_RegressionBugId: BUG-NNN_` (or `GH#NNN_`)
  - Example: `- _BugFix: true_\n- _RegressionBugId: GH#123_`
  - The corresponding regression test is implemented under the naming convention of `regression-test-policy/SKILL.md` (`regression_issue_NNN_*` / `it('regression #NNN: ...')`)
  - When parallel-worker detects `_BugFix: true`, it follows the RT1 flow (write a reproducing test in the RED phase before fixing, then make it GREEN after the fix)

#### _BugFix task example (J-10)

```markdown
- [ ] N.M Fix login failure on multibyte usernames
  - File: src/services/login.rs, tests/regression/issue_123.rs
  - _BugFix: true_
  - _RegressionBugId: GH#123_
  - _DependsOn: ...
  - _Requirements: REQ-N
  - _TestFocus: Happy Path: multibyte username login succeeds | Boundary Values: empty / 1-char / 256-char username | Error Handling: invalid byte sequence | Edge Cases: combining characters | Negative Assertions: login does NOT panic on invalid UTF-8 | Isolation Properties: Mock-only clock for token expiry test
  - _Prompt: Role: Bug Fixer | Task: Fix GH#123. First write the reproducing test regression_issue_123_login_fails_with_multibyte_username in the RED phase, then implement the fix | Restrictions: Do not break the existing login flow | Success: Regression test PASSes, all existing tests PASS_
```

#### _TestFocus Format (extended from 4 to 6 categories by I-1)

To align with the unit-test-engineer's required test coverage, use the following **6-category structure** (extended from 4 to 6 per I-1, `dapper-hardening-orchestrator.md`). Free-form text is not allowed.

```
_TestFocus: Happy Path: {specific test targets} | Boundary Values: {specific boundaries} | Error Handling: {specific error cases} | Edge Cases: {specific cases} | Negative Assertions: {specific behaviors that must NOT happen} | Isolation Properties: {external dependency strategy}
```

Category descriptions:

1. **Happy Path**: Verify normal-path behavior per the spec
2. **Boundary Values**: Behavior at boundaries (minimum / maximum / just before and after thresholds)
3. **Error Handling**: Handling of error conditions (invalid input / failures / timeouts, etc.)
4. **Edge Cases**: Exceptional situations (multi-byte, duplicates, repeated operations)
5. **Negative Assertions (added by I-1)**: **Confirm that out-of-spec behavior does not occur**:
   - No input mutation (pure functions have zero side effects)
   - Do not emit unnecessary logs / metrics / events
   - Do not panic on unexpected input (fail with an appropriate error)
   - Do not return out-of-spec fields
6. **Isolation Properties (added by I-1)**: **Zero external dependencies + order-independent + deterministic**:
   - Zero direct calls to clock / RNG / env / fs / HTTP / DB (Mock only)
   - Order-independent (does not depend on other tests' state, no shared global state)
   - Deterministic (same input always yields the same result; does not depend on clock or RNG)

If a category does not apply, explicitly write "N/A" (do not omit it). When Negative Assertions / Isolation Properties is "N/A", explicitly note the reason (only when the function is pure and side effects are impossible by design).
- Instructions about marking task status in tasks.md and logging implementation with `/log-implementation` skill

### 5. Create the Document

Write the tasks document to:
```
.spec-workflow/specs/{spec-name}/tasks.md
```

**Frontmatter (required for new specs, per `${CLAUDE_PLUGIN_ROOT}/rules/spec-dependency-graph.md` SD2, SD6):**

Add the following YAML frontmatter to the top of the file. This declares the upstream spec IDs that tasks.md as a **whole** depends on; it is orthogonal to per-task `_Requirements:` / `_DependsOn:` metadata, which operate at a different granularity:

```yaml
---
spec_id: {spec-name}
phase: tasks
version: 1
depends_on:
  - file: design.md
    refs: [DES-1, DES-2]  # Components to implement
  - file: test-design.md
    refs: [UT-1.1, IT-1]  # Test specs to satisfy
---
```

Per-task metadata (`_Requirements:` / `_Leverage:` / `_DependsOn:` / `_PhaseReview:` / `_PhaseRefactor:` / `_TDDSkip:` / `_TestFocus:`) is preserved as before (SD6).

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
  model: "sonnet",
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
  model: "opus",
  description: "Review tasks spec (check)",
  prompt: "You are a spec document reviewer. Review the document (do NOT modify the file) at:
    {project-path}/.spec-workflow/specs/{spec-name}/tasks.md

    Document type: tasks
    Template: {project-path}/.spec-workflow/templates/tasks-template.md
    Requirements: {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    Design: {project-path}/.spec-workflow/specs/{spec-name}/design.md
    Test Design: {project-path}/.spec-workflow/specs/{spec-name}/test-design.md

    Checks:
    1. TEMPLATE: Every task has - [ ] marker, file path(s), _Requirements, _Prompt fields. Every implementation task also has _Leverage (Phase 0 setup tasks, PhaseReview tasks, and IT/E2E test tasks may omit _Leverage)
    2. _Prompt has: Role, Task, Restrictions, Success fields in the format "Role: ... | Task: ... | Restrictions: ... | Success: ..."
    3. CROSS-REFERENCE: Read requirements.md and design.md —
       every requirement must have at least one implementing task,
       every design component must have at least one creating task,
       _Requirements IDs must match actual requirement IDs,
       **(D extension, dapper-hardening)** verify that every server fn / external API / sibling component listed in each DES-N's `Dependencies:` column appears as an **explicit string in the corresponding task's `_Prompt.Task`, e.g., "call / integrate with / receive {dependency name}"**
    4. TRACEABILITY: Verify that the Target Task ID column is filled in for all components in the Requirements Traceability Matrix in design.md.
       If any component row is empty, add a task to tasks.md and update the matrix in design.md.
    5. Tasks are atomic (1-3 files), in logical dependency order
    6. No placeholder text, descriptions specific enough for AI implementation
    7. PHASE STRUCTURE: Tasks are grouped under ## Phase headings with vertical slices
    8. TDD: No standalone unit test tasks (e.g., 'write tests', 'create unit tests'). IT/E2E test tasks are allowed as separate tasks.
    9. Every task that is neither _PhaseReview nor _PhaseRefactor has a _TestFocus field; _PhaseRefactor tasks must NOT have one
    10. Each phase ends with a _PhaseRefactor: true_ task immediately followed by a _PhaseReview: true_ task (rules/refactor-backlog.md RB4); the _PhaseRefactor _Prompt must reference refactor-backlog.md and state the behavior-preserving Restrictions
    11. DEPENDENCIES: _DependsOn references point to valid task IDs within the same Phase. No circular dependencies. No self-references. Tasks that use types/models/outputs created by another task declare the dependency.
    12. TEST-DESIGN TRACEABILITY: Read test-design.md —
        every UT spec must have a corresponding task with matching _TestFocus,
        every IT spec must have an integration test task,
        every ST spec must have a system test task (J-7),
        every E2E spec must have an E2E test task
    13. FRONTMATTER (spec-dependency-graph.md SD2, SD6): Valid YAML frontmatter with spec_id, phase: tasks, version, depends_on (file entries pointing to design.md and test-design.md with refs) must exist at the top of the file. DES-/UT-/IT-/ST-/E2E- IDs in depends_on.refs must exist in the referenced upstream files (SD4). Task-level metadata (_Requirements, _Leverage, _DependsOn) remains orthogonal to this frontmatter
    14. COMPOSITION_TASK (D, dapper-hardening): If a top-level (root) component exists in design.md's Component List (e.g., AppRoot, MainShell, RootRoute), verify that tasks.md has a **dedicated composition task** that assembles the child components beneath it. The task's `_Prompt.Task` must explicitly state "place N child components inside view! and wire up props / signals", and `_Prompt.Success` must explicitly state "satisfies the preconditions for an E2E smoke (in a later Phase) where all child components appear in the DOM tree"
    15. UI_OBSERVABILITY (D, dapper-hardening): Verify that a UI component task's `_Prompt.Success` includes "attach data-testid with {expected values}" and "the actual view! renders {required elements (`<img>`, `<button>`, etc.)}". Verify that any testid referenced by `getByTestId(...)` / `query_selector("[data-testid=...]")` in the E2E / CT specs of test-design.md is explicitly stated in the corresponding component task's `_Prompt.Success`
    16. FIXTURE_REALIZATION (D, dapper-hardening): Verify that fixture paths listed in test-design.md's Test Data Requirements (e.g., `tests/fixtures/...`, `photos/landscape/...`) are stated as being created or placed in some task's `File:` column or `_Prompt.Task` body
    17. PHASE_SMOKEABLE (E-2, dapper-hardening): Before the last `_PhaseReview: true_` task of each Phase, verify that **at least one smokeable deliverable exists** in that Phase. Cross-check against design.md's Phase Deliverables (made mandatory by K-4); if a Phase has zero deliverables, escalate (propose revising Phase boundaries)
    18. SUCCESS_BEHAVIORAL_VERIFICATION (H-4, dapper-hardening): The `_Success` field must NOT be completed by static checks alone (e.g., grep for string existence / "the file exists" / "implementation contains X"). At least one piece of **behavioral evidence** is required: test PASS (UT-N / CT-N / IT-N / ST-N) / smoke PASS / DOM observation. A UI component task's `_Success` must require CT-N PASS (mount + signal manipulation + DOM observation)
    19. TESTFOCUS_NEGATIVE (I-1, dapper-hardening): _TestFocus must include all 6 categories (Happy Path / Boundary Values / Error Handling / Edge Cases / Negative Assertions / Isolation Properties). If Negative Assertions or Isolation Properties is "N/A", the task must be a pure function with no side effects (and the reason must be explicitly noted)
    20. ST_PLACEMENT (J-7, dapper-hardening): For every ST-N spec in test-design.md, a corresponding task must exist in tasks.md, placed at the end of the Phase that completes the target feature's component / endpoint dependencies (after CT/IT, before final E2E Phase).
    21. REGRESSION_BUG_ID (J-10, dapper-hardening): Tasks marked with `_BugFix: true` (or with `Role: Bug Fixer` in _Prompt) must include a `_RegressionBugId: BUG-NNN` (or `GH#NNN`) metadata field. The corresponding regression test must follow the naming convention `regression_issue_NNN_*` (Rust) / `regression #NNN` (TS) per regression-test-policy/SKILL.md.
    22. EVIDENCE CITATIONS (evidence-coverage.md EC1): Read task_type from .spec-workflow/specs/{spec-name}/request-spec.md frontmatter and detect whether this document contains any EV-{category}-{NNN} citation (HTML comment, inline paren form, frontmatter depends_on.refs, or _Evidence: task-level metadata).
        - If request-spec.md does not exist, or task_type is absent → SKIP checks 22-25 (EC5) and note 'evidence checks skipped (no request-spec / unclassified)' in the report.
        - If task_type is 'legacy' AND no EV-{category}-{NNN} citation is present in this document → SKIP checks 22-25 (EC5) and note 'evidence checks skipped (legacy, no EV citations)' in the report.
        - If task_type is 'legacy' AND at least one EV-{category}-{NNN} citation is present (opt-in legacy mode, EC5):
            Run check 22 (EC1 integrity) on every citation as described below.
            SKIP checks 23-25 and note 'legacy spec: ran EC1 only due to EV citations; skipped EC2 / EC3' in the report.
        - If task_type is any other declared value, run checks 22-25 normally.
        - For every EV-{category}-{NNN} citation in this document (HTML comment, inline paren form, frontmatter depends_on.refs, or _Evidence: task-level metadata) when check 22 applies:
            a. .spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md must exist.
            b. The referenced file's frontmatter spec_name: must equal this spec-name.
            c. The {category} must be listed in ${CLAUDE_PLUGIN_ROOT}/rules/task-types.md TT3 (or the project's user-config/task-types.yml TT4).
          Any failure = FAIL with rule_id EC1.
    23. INLINE CODE BUDGET (evidence-coverage.md EC3): Apply this check only when check 22 routed to full enforcement (non-legacy classified task_type). Count fenced code block lines (between opening and closing fences, exclusive). Fail if any of:
            - A single fenced block exceeds 10 lines.
            - Cumulative fenced-block lines within a single H2 or H3 section exceed 20 lines.
            - Total fenced-block lines in the document exceed 60 lines.
          For each violation FAIL with rule_id EC3; fix_hint: 'tasks.md should carry task descriptions and metadata, not code. Move any illustrative code to an evidence file and cite it via _Evidence'. Markdown tables are NOT counted.
    24. _Evidence METADATA (evidence-coverage.md EC2, per task): Apply this check only when check 22 routed to full enforcement (non-legacy classified task_type). Every implementation task MUST have an _Evidence line listing at least one EV-{category}-{NNN}. Exempt from this requirement: Phase 0 setup tasks (Git init, container setup, CI bootstrap) and tasks whose title starts with 'PhaseReview'. IT and E2E test tasks MUST carry _Evidence (typically EV-test-harness-* or EV-contract-current-*). Missing _Evidence on a non-exempt task = FAIL rule_id EC2_taskEvidence with fix_hint 'Add: _Evidence: EV-{category}-{NNN} on the line under the task header, parallel to _Leverage. Pick the EV(s) the implementer will need to open while coding this task.'
    25. _Evidence FORMAT: Apply this check only when check 22 routed to full enforcement (non-legacy classified task_type). The _Evidence line format is `_Evidence: EV-{category}-{NNN}[ EV-{category}-{NNN}[, ...]]` — space or comma separated EV IDs. Each listed EV must exist on disk (covered by EC1 check 22). A single task should cite no more than 4 EVs; more than 4 signals the task is not atomic and should be split. = WARN rule_id EC2_taskEvidenceSplit (not blocking).

    Reporting: for EC1/EC2/EC3 issues, include fields rule_id, location, message, fix_hint.
    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 8. Approval Workflow

Same strict process — verbal approval is never accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only. Save the returned `approvalId`.

2. **Check approval (synchronous)**: After the user approves via the dashboard / VS Code extension, run:
   ```
   /check-approval <approvalId> next:/spec-implement
   ```
   `check-approval` fetches status once via the `approvals` MCP tool (no polling) and branches:
   - **pending**: User has not acted yet — instruct the user to approve, then re-run `/check-approval`
   - **approved**: Cleanup is performed automatically, and `check-approval` automatically invokes `/spec-implement`
   - **needs-revision**: Reviewer comments are displayed
   - **rejected**: Rejection reason is displayed — revise and create a new approval

3. **Handle needs-revision** (if status was needs-revision):
   - Update tasks using reviewer comments, spawn the review subagent again
   - Submit a NEW approval request and run `/check-approval <newApprovalId> next:/spec-implement`

## Rules

- Feature names use kebab-case
- One spec at a time
- Cite locations by stable anchor (ID / heading / table row key / verbatim phrase / symbol), never by line number — `rules/doc-crossref.md` "Reference Form". A `file:line` reference is stale after the first revision of the target
- Tasks should be atomic (1-3 files each)
- Every task needs a `_Prompt` field with structured guidance
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
