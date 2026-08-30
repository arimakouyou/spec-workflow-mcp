---
name: spec-implement
description: "Phase 5 of spec-driven development: implement tasks from an approved tasks.md document using TDD (Red-Green-Refactor). ONLY use this skill when ALL FOUR spec documents exist: requirements.md, design.md, test-design.md, AND tasks.md. Use this skill when the user explicitly requests to start implementation, code a specific task ID, or continue implementation of an existing spec. Triggers on: 'implement task', 'start coding', 'work on task 3', 'implement spec X', 'continue implementation', '/spec-implement'. DO NOT trigger on general 'implement X' requests unless spec documents exist."
---

# Spec Implementation (Phase 5) — TDD Orchestrator

Execute tasks systematically from the approved tasks.md using a **TDD-driven workflow**. Each task follows the cycle: Start → Discover → Read Guidance → **TDD Implementation (parallel-worker)** → **UT Quality Verification** → **Code Review + Commit (review-worker)** → Log → Complete.

## MUST-READ: What Implementation-Time UT Verifies (I-5, dapper-hardening)

**Implementation-time UT is NOT a check that `cargo test PASS` (code runs). It is verification of the spec.**

- **Spec satisfaction**: The behavior defined in the spec is performed correctly
- **No out-of-spec behavior**: Behavior not defined in the spec does not occur (no mutation / zero side effects / no panic on unexpected input / no undefined fields)
- **Zero external dependencies**: Do not write direct calls to clock / RNG / env / fs / HTTP / DB in tests (only via Mock, declared in design.md K-3)
- **Order-independent and deterministic**: The result is the same no matter how many times or in what order it is run

Writing only `cargo test PASS` in the `Success` field of `_Prompt` is the **wrong frame**. Instead, write in terms of **behavioral evidence + quality-property evidence** such as "Spec X is verified by UT-N including Negative Assertion" or "QC15 (UT Properties Gate) shows zero violations of clippy `disallowed-methods`".

See `quality-checks.md` **Test Taxonomy** and **QC15** for details. Also see the 6 categories of `_TestFocus` in `spec-tasks/SKILL.md` (Happy Path / Boundary Values / Error Handling / Edge Cases / **Negative Assertions** / **Isolation Properties**).

## ⛔ Orchestrator Prohibited Actions (ABSOLUTE RULES)

You executing this skill are the **orchestrator**, not the **implementer**. Strictly follow these rules:

| Prohibited | Reason |
|-----------|--------|
| **Do not write code yourself** | Implementation must always be delegated to `parallel-worker` |
| **Do not write tests yourself** | The initial TDD tests (RED phase) are `parallel-worker`'s responsibility. Adding supplemental tests is the test engineer's (`frontend-test-engineer` or `unit-test-engineer`) responsibility |
| **Do not run git commit yourself** | Commits must always be delegated to `review-worker` |
| **Do not skip agent calls** | Each step's agent call cannot be skipped |
| **Do not invent concepts not in this spec** (A, dapper-hardening) | Concepts such as "Auto Mode", "continuous mode", or "auto-progression" **must not be invented to skip user confirmation if they do not exist in this SKILL.md**. User confirmation is required before Phase progression / Wave progression. `auto-resume.sh` is for rate-limit recovery only and is not a substitute for user-intent confirmation. Real example from dojin-viewer: Claude said "Proceeding to Wave 2 because of Auto Mode" and the user pointed out "I did not give that instruction" |

**For any reason whatsoever (e.g., "it's a simple task", "I can do it myself"), do not skip agent calls.**

The orchestrator's sole responsibilities:

1. Read tasks.md and identify the next task
2. Call agents with the correct prompts
3. Receive agent completion reports and hand off to the next agent
4. Call `/log-implementation` skill
5. Update task status in tasks.md
6. Update session state via `${CLAUDE_PLUGIN_ROOT}/scripts/session-manage.sh` (init / start-task / complete-task / end; see the "Session Initialization" section for details)

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

## Session Initialization (MANDATORY — DO NOT SKIP)

Immediately after the Prerequisites Check passes, before entering Step 0, **initialize the implementation session**.
This creates `.implement-session.json` and `.implement-session.lock` in the project root and activates the following hooks:

| Hook | Role |
|------|------|
| `inject-spec.sh` (UserPromptSubmit) | Inject spec context every turn (prevents forgetting to read the spec) |
| `resume-hint.sh` (SessionStart) | Present resume status and the actual git state at the top of the context |
| `verify-tests-run.sh` (Stop) | Inspect test runner execution history before declaring completion |
| `detect-new-files.sh` (PostToolUse Write) | Warn about new files not mentioned in the spec |
| `log-implementation.sh` (Stop) | Safety net for forgotten log calls (auto-generates a skeleton) |

Initialization command:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-manage.sh" init {spec-name}
```

In the subsequent Task Cycle:

- Call `session-manage.sh start-task {task-id}` at the start of each task
- Call `session-manage.sh complete-task {task-id} {commit-hash}` after marking each task complete (after the `[x]` mark)
- Call `session-manage.sh end` to release the lockfile when all waves are done or on interruption. `inject-spec.sh` / `verify-tests-run.sh` / `detect-new-files.sh` / `log-implementation.sh` key their dormancy off the lockfile, so they go dormant at this point. `resume-hint.sh` is the exception: it keys off the session file, which `end` preserves as a resume hint, and reports `Active: no` on the next session start

> **Note**: The session file is not the "source of truth". It may be lost before update due to rate limits etc., so the hook side is designed with the premise that the actual git state takes precedence. Best-effort updates are sufficient.

### Auto-Resume on Rate Limit (optional)

If you want to auto-recover from interruptions caused by rate limits or long-running jobs, the user can launch the following wrapper script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/auto-resume.sh" {spec-name}
```

- Runs `/spec-implement --auto-resume` non-interactively via `claude --print`
- Exit code convention: `0` complete / `42` rate-limited (sleep + retry) / `43` user confirmation needed / other values are errors
- `MAX_ATTEMPTS` (default 20) / `INITIAL_SLEEP` (60s) / `MAX_SLEEP` (300s) / `LOG_FILE` (`.auto-resume.log`) can be tuned via environment variables
- When the orchestrator detects a rate limit, it exits with the **convention exit code (42)** and the wrapper restarts it with exponential backoff. It loops while carrying over the state in `.implement-session.json` until completion

---

## Step 0: Tool Verification (MANDATORY — DO NOT SKIP)

After Prerequisites pass, verify the existence of all required tools before starting implementation. Run **only once** before the Task Cycle starts.

### 0.1 Read Tool Requirements

Parse the tool requirements table from these two files:

1. `.spec-workflow/specs/{spec-name}/design.md` → `## Required Build Tools` section
2. `.spec-workflow/specs/{spec-name}/test-design.md` → `#### Required Test Tools` section
3. `${CLAUDE_PLUGIN_ROOT}/rules/quality-checks.md` → the quality-check tools for the detected project type (Rust: `cargo-audit`, `cargo-deny`, `cargo-udeps` + `nightly` toolchain, `cargo-mutants` if declared; Node.js: `knip` if configured; .NET: `snitch`, `dotnet-project-licenses`). Add any of these that the two tables above omit as Required=Yes entries with a `<tool> --version` Check Command (for udeps: `cargo +nightly udeps --version`). This is a backstop for specs whose design.md predates spec-design derivation rule 8; a quality-check tool that is absent must surface here as MISSING_REQUIRED, never as a per-task `skip` that repeats for the life of the project

If either section is missing, emit a warning log (`[tool-verify] WARNING: Required Tools section missing in {filename} — skipping tool verification for that file`) and verify only the section that exists. If both are missing, emit `[tool-verify] WARNING: No Required Tools sections found in design.md or test-design.md — skipping tool verification` and proceed to the Task Cycle (backward compatibility).

**Important:** Subsequent quality-checks may treat the `docker-compose` command (or the `docker compose` subcommand) as required. For projects that use Docker Compose, **always include `docker-compose` (or `docker compose`) as a required tool** in one of the Required Tools tables. If it is not included, Phase Review / smoke tests may FAIL (environment issue) even after Step 0 passes.

### 0.2 Tool Existence Check

Run the Check Command for each tool entry. **The Check Command must follow security constraints:**

**Safety check (always validate before execution — the target is the Check Command string written in the doc itself):**

- The Check Command is allowed only in read-only version-check patterns such as `<tool> --version` or `<tool> -v`
- If the Check Command string in the doc contains shell operators such as pipes (`|`), redirects (`>`, `<`), semicolons (`;`), `&&`, or `$()`, **do not auto-execute** — present the content to the user and obtain approval first
- Auto-execute only for safe patterns (`2>&1` is a wrapper added by the orchestrator and is not part of the Check Command itself):

```bash
# Run each tool's Check Command sequentially (only safe patterns are auto-executed)
# Note: 2>&1 is added by the orchestrator to capture stderr version output
{check_command} 2>&1
echo "EXIT_CODE: $?"
```

- exit 0 → parse the version. If a Min Version is specified, compare versions:
  - Meets version requirement → `[tool-verify] {tool}: OK ({detected_version})`
  - Version is too old → add to VERSION_MISMATCH list
- exit ≠ 0 → classify based on the Required column:
  - `Yes` → add to MISSING_REQUIRED list
  - `Recommended` → emit warning log `[tool-verify] WARNING: {tool} not found (recommended, not required)`, continue

### 0.3 Install Guidance and User Approval

**Do not auto-execute Install Commands without user approval.** Commands sourced from spec documents may carry risks such as `curl|sh` or privilege escalation, so always obtain explicit user approval before running.

If the MISSING_REQUIRED list or the VERSION_MISMATCH list is non-empty, follow these steps:

1. Present the list of missing tools to the user:

   ```text
   The following tools are missing or have insufficient versions:

   | Tool | Purpose | Install Command | Status |
   |------|---------|-----------------|--------|
   | {tool} | {purpose} | `{install_command}` | Missing / Version mismatch |

   Confirm and run the above Install Command? (yes/no)
   ```

2. Run the Install Command only if the user approves, then re-validate with the Check Command:
   - Success → remove from list, log `[tool-verify] {tool}: installed successfully ({version})`
   - Failure → keep in list

3. If the user declines → keep in list and proceed to the 0.4 gate decision.

### 0.4 Gate Decision

```text
if MISSING_REQUIRED is not empty OR VERSION_MISMATCH is not empty:
  Report to user:
    "## Tool Verification Failed

    The following required tools are missing or do not meet requirements, so implementation cannot start:

    | Tool | Purpose | Install Command | Status |
    |------|---------|-----------------|--------|
    | {tool} | {purpose} | {install_command} | Missing / Version too old ({detected} < {required}) |

    After installing/upgrading the above tools, run `/spec-implement` again."

  STOP — do not proceed to the Task Cycle.

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

**Wave processing is serial** (per `${CLAUDE_PLUGIN_ROOT}/rules/serial-execution-policy.md`). Regardless of how many tasks a wave contains, process them one at a time. Concurrent `Agent` launches are prohibited even when the DAG admits parallelism.

- Pick one task in the wave and mark it `[ ]` → `[-]`
- Prepare the worktree for that task (step 3.7)
- In step 4, launch a single `parallel-worker` and wait for completion
- After steps 5-8 finish, pick the next task in the wave, mark it `[ ]` → `[-]`, and repeat
- Once all tasks in the wave are completed (or failed), advance to the next wave

**Session update (at the start of each task)**: Update the session's `current_task` whenever a new task begins:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-manage.sh" start-task {task-id}
```

**PhaseReview / PhaseRefactor exclusion during wave computation**: Tasks with `_PhaseReview: true` or `_PhaseRefactor: true` are always excluded from wave computation. After all regular tasks in the phase complete, the PhaseRefactor task is processed alone (Step 3.6), then the PhaseReview task alone.

**No `_DependsOn:` metadata**: If no tasks in the Phase have `_DependsOn:`, all non-PhaseReview tasks form Wave 0. Process them serially per the rule above (one at a time).

**Per-task processing**: Each task runs steps 3-8 (worktree creation → parallel-worker → UT verification → review-worker → log → merge/cleanup → mark `[x]`) **independently and sequentially**. Within a single wave, multiple tasks MUST NOT be in the `[-]` (in-progress) state simultaneously.

> The prior multi-task-wave parallel rules (resource-aware sub-batch splitting and related logic) are archived under `_disabled/parallel-execution/spec-implement-parallel-sections.md`. Consult that file when re-enabling.

### 2. Discover Existing Work

Before writing any code, search implementation logs to understand what's already been built. This prevents duplicate endpoints, reimplemented components, and broken integrations.

Task logs live in: `.spec-workflow/specs/{spec-name}/task-logs/{taskId}.log.md` (new tasks).

Legacy implementation logs from before the task-log consolidation live in: `.spec-workflow/specs/{spec-name}/Implementation Logs/`. Both directories are valuable for the discovery step.

**Search with grep** (fast, recommended):

```bash
# New consolidated task logs
grep -r "GET\|POST\|PUT\|DELETE" ".spec-workflow/specs/{spec-name}/task-logs/"
grep -r "component\|Component" ".spec-workflow/specs/{spec-name}/task-logs/"
grep -r "function\|class" ".spec-workflow/specs/{spec-name}/task-logs/"
grep -r "integration\|dataFlow" ".spec-workflow/specs/{spec-name}/task-logs/"

# Legacy implementation logs (still informative for pre-consolidation work)
grep -r "GET\|POST\|PUT\|DELETE" ".spec-workflow/specs/{spec-name}/Implementation Logs/" 2>/dev/null
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
- **_Evidence**: EV-{category}-{NNN} IDs that scope the existing-code context (`${CLAUDE_PLUGIN_ROOT}/rules/evidence-coverage.md`). For each listed ID, resolve to `.spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md` and pass the resolved paths to the TDD subagent. Do **not** list evidence files that are not referenced by this task's `_Evidence` line — those belong to other tasks
- **Success**: How to know you're done

### 3.6 Phase Refactor Tasks

If the task has `_PhaseRefactor: true_`, it runs through the normal worktree → parallel-worker → review-worker → merge cycle (steps 3-8) with these differences (`${CLAUDE_PLUGIN_ROOT}/rules/refactor-backlog.md` RB4):

1. **Scope comes from the backlog, not from `File:`**. Before launching parallel-worker, read `.spec-workflow/specs/{spec-name}/refactor-backlog.md`. If the file is absent or has no `open` row whose Files belong to this Phase or earlier, mark the task `[x]` directly with a task-log entry `refactor-backlog: none` and skip to the PhaseReview task — do not create a worktree
2. **Prompt**: pass parallel-worker the `_Prompt` of the task plus the full text of every in-scope row, and state: "REFACTOR only — no RED / GREEN. Do not change any test expectation, public API, or design.md. Run the full quality checks after each row. Update each row's Status and Resolved in"
3. **No UT verification step for new tests** (step 5 checks that the existing suite is unchanged in count and all passing; a test count that decreased is a finding)
4. **review-worker** reviews it as a normal task; category D for this task is: every in-scope row is `done` / `deferred` / `rejected` with a reason, and the diff is behavior-preserving
5. The task counts toward the same 3-rework limit as other tasks

### 3.5 Phase Review Tasks

If the task has `_PhaseReview: true_`, **skip the TDD cycle (steps 4-5)** and instead:

#### 3.5.0 Bookkeeping Commit (newly added in B, dapper-hardening)

> Source: `.claude/_docs/plans/dapper-hardening-orchestrator.md` root cause B (B-1).
> Before creating the Phase Review worktree, commit any uncommitted bookkeeping files (tasks.md `[x]` mark updates, task-logs/, and legacy Implementation Logs/ if present) on the main side. Without this, the PhaseReview worktree (derived from HEAD) does not see the bookkeeping, so diffs remain on the main side even after the PhaseReview commit.

```bash
# Check for uncommitted bookkeeping on the main side
SPEC_DIR=".spec-workflow/specs/{spec-name}"
BOOKKEEPING_FILES=$(git status --porcelain | grep -E "${SPEC_DIR}/(tasks\.md|task-logs/|Implementation Logs/)" || true)

if [ -n "$BOOKKEEPING_FILES" ]; then
  echo "Bookkeeping changes detected:"
  echo "$BOOKKEEPING_FILES"

  # Stage bookkeeping only
  git add ".spec-workflow/specs/{spec-name}/tasks.md" \
          ".spec-workflow/specs/{spec-name}/task-logs/" 2>/dev/null
  # Legacy directory (only if it still has uncommitted entries)
  git add ".spec-workflow/specs/{spec-name}/Implementation Logs/" 2>/dev/null || true

  # Commit (mechanical commit message)
  git commit -m "chore({spec-name}): bookkeeping for phase {phase-number}"

  echo "[bookkeeping] committed"
fi
```

As a result:
- The next PhaseReview worktree (derived from HEAD) is cut from a state that includes the bookkeeping
- review-worker may **exclude** bookkeeping under spec/ from the review scope (since it is a mechanical update)
- No uncommitted diff remains on the main side (resolves the B root-cause issue)

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

#### 3.5.1.5 Integration Verification

After unit tests pass, verify that the Phase deliverables work at the integration level.
See the "Integration Verification" section of `quality-checks.md` for command definitions.

##### Step A: Project Type Detection

| Detection condition | Type |
|----------|--------|
| `[package.metadata.leptos]` in `Cargo.toml` | Leptos full-stack |
| `axum` / `actix-web` / `rocket` dependency in `Cargo.toml` | Rust API |
| `BlazorWebAssembly` / `Microsoft.AspNetCore.Components.WebAssembly` in `*.csproj` | .NET Blazor full-stack |
| `*.sln` or `*.csproj` exists (no Cargo.toml) | .NET API |
| `package.json` exists | Node.js |
| None of the above | Generic (build only) |

##### Step B: Build Verification (required)

Confirm the deliverables build successfully. Commands depend on project type — see `quality-checks.md`.

##### Step C: Integration Test Execution

Run if integration test files exist. If they do not exist, decide as follows (**follow this rule strictly**):

- The environment is explicitly excluded under "Excluded Test Environments" in design.md → SKIP (excluded by design)
- An integration test spec exists in test-design.md (spec exists) → FAIL (missing implementation)
  - "Spec exists" criterion: test-design.md has a `## Integration Test Specifications` heading and that section contains at least one heading starting with `### IT-`
- No spec satisfying the above (no spec) → SKIP (not required by design)

##### Step D: Smoke Test (API projects only)

Temporarily start the server and verify connectivity to the health-check endpoint. If the server cannot start due to external dependencies (DB etc.), treat it as FAIL (environment issue) (SKIP is not allowed).

**Result decision:**

| Result | Action |
|------|----------|
| PASS | Proceed to 3.5.2 Code Review + Commit (review-worker) |
| FAIL (build) | Analyze the build error, identify the root cause task. Task within the Phase → revert `[x]` to `[-]` and revert PhaseReview to `[ ]`. Re-run the root cause task from step 4 |
| FAIL (integration tests) | Analyze the failed test, identify the root cause task. Task within the Phase → send back; prior Phase → escalate to user |
| FAIL (smoke) | Analyze startup logs to identify root cause, send back |
| **FAIL (placeholder detected) (added in E-3, dapper-hardening)** | When QC17 UI Smoke Render shows the testid count below the expected minimum / a specific testid is missing. Revert the implementation task for the relevant component from `[x]` to `[-]` and rework |
| FAIL (environment issue) | Required tool / runtime not installed. Report missing tools to the user and present the Install Command from the Required Tools tables in design.md / test-design.md. Stop implementation (STOP) |
| FAIL (missing implementation) | A test spec is defined in test-design.md but the test file does not exist. Report to the user as a missing test implementation |
| **escalate (Phase deliverable absent) (added in E-2, dapper-hardening)** | When the Phase has no deliverable that can be smoke-tested, escalate instead of SKIP. Suggest the user reconsider design.md Phase Deliverables (K-4) and re-design the Phase boundary |
| SKIP (excluded by design) | Test explicitly excluded under "Excluded Test Environments" in design.md. Log the exclusion reason and proceed to 3.5.2 |
| SKIP (not required by design) | (Changed in E-2 to **deprecated for Phase Review smoke**) Only when the test spec itself does not exist in the design doc and there is no corresponding deliverable in Phase Deliverables. Log the SKIP reason with **filename + relevant line** (for transparency). Outside the Final Gate, this is being phased out in favor of escalate |

**Note**: You must not select "SKIP" for reasons such as "no environment", "server startup required", or "Chrome required". When tools or runtimes listed as Required=Yes in the Required Tools tables of test-design.md / design.md are missing, always treat it as "FAIL (environment issue)" above and stop implementation (STOP) (the same applies even if Step C/D in quality-checks.md mentions SKIP).

The integration verification results (PASS/FAIL/SKIP for each step) must be passed as input to the review-worker in 3.5.2.

> **Architectural invariant tests**: Rust: when `tests/architecture.rs` (generated by `/generate-arch-tests`) exists, it runs automatically during `cargo test` in step 3.5.1. .NET: when architecture tests using NetArchTest.Rules / ArchUnitNET exist, they run automatically during `dotnet test`. If a dependency-direction violation is detected, treat it as a test failure and identify and send back the root cause task. If the test does not exist and design.md has a `## Module Boundaries` section, suggest adding architecture tests to the user.

#### 3.5.1.6 CVE Audit (Dependency Vulnerability Audit)

Before invoking review-worker for Phase Review, mechanically inspect dependency libraries for vulnerabilities.

##### Step A: Run the Audit Tool

| Project type | Detection condition | Audit command |
|----------------|----------|------------|
| Rust | `Cargo.lock` exists | `cargo audit` |
| .NET | `*.csproj` exists | `dotnet list package --vulnerable --include-transitive` |
| Node.js (npm) | `package-lock.json` exists | `npm audit` |
| Node.js (Yarn) | `yarn.lock` exists | `yarn audit` (Yarn v1) or `yarn npm audit` (Yarn v2+) |
| Mixed | Multiple lockfiles / project files exist | Run each applicable audit command |

If no lockfile exists, SKIP (new project with unresolved dependencies).

If `cargo audit` is not installed:

```bash
cargo audit --version 2>&1 || echo "NOT_INSTALLED"
```

If not installed, suggest `cargo install cargo-audit` to the user (follow the user-approval rule in Step 0.3). If the user declines, SKIP and defer to the review-worker's security evaluation.

##### Step B: Classify Results

| Severity | Action |
|-------|----------|
| Critical / High | Add to CVE_FOUND list |
| Medium/Moderate / Low | Record in warning log |

* `cargo audit` `medium` and `npm audit` `moderate` are treated as the same severity.

##### Step C: Hand Off Results

Add the CVE audit results to the review-worker's input:

```text
CVE Audit Results:
- cargo audit: {PASS / N vulnerabilities detected / SKIP}
- npm audit: {PASS / N vulnerabilities detected / SKIP / N/A}
- Critical/High CVEs: {CVE_FOUND list or none}
  - Each entry format: CVE-ID | package name | current version | fixed version | recommended action
```

The Phase Review review-worker performs a security evaluation based on these results and decides the `review_action` (commit / rework / escalate). The final decision on CVE severity and response policy is delegated to the review-worker.

The CVE audit results must be passed to the review-worker in 3.5.2 together with the integration verification results.

#### 3.5.2 Code Review + Commit (delegate to review-worker)

On Phase completion, gather the Pre-Phase CVE Audit and integration verification results, create a dedicated PhaseReview worktree, and delegate the commit to review-worker. The Phase-wide final review and commit are done in a single review-worker invocation:

```bash
# Create a dedicated worktree for PhaseReview
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
    As a phase review, please perform a final review and commit all files changed in the current Phase.
    This is the **single review pass for the Phase** — earlier per-task reviews are scoped to individual tasks; the Phase-wide multi-perspective evaluation is your responsibility here.

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

    Pre-Phase CVE Audit Results (from step 3.5.1):
    - cargo audit: {pre-phase-cve.cargo-audit}
    - npm audit: {pre-phase-cve.npm-audit}
    - Critical/High CVEs: {pre-phase-cve.critical-high-list}

    Perform multi-perspective review covering:
    - Spec conformance (verify each Success criterion in _Prompt)
    - Authentication / authorization / data leakage (C2-C4)
    - OWASP TOP 10 and CVE audit assessment (C1-C8 + the Pre-Phase CVE results above)
    - Performance (bottlenecks, complexity, resource efficiency)
    - Quality concerns such as test coverage, naming, DRY

    Focus on final quality checks (rustfmt, clippy, tests) and commit.
    Review across all aspects (A–G) and report review_action as commit / rework / escalate.
    Include integration-verification results in your completion report.
    G: API Documentation — When docs/openapi.yaml exists and API-related files have changed,
    verify that openapi.yaml has been updated. If not updated, report a recommendation to run /generate-api-docs.
    The commit message should summarize the Phase's deliverables.`
})
```

- **review_action: commit** → proceed to 3.5.3
- **review_action: rework** → follow the normal rework flow (identify the root cause task and send it back to that task's parallel-worker)
- **review_action: escalate** → follow the normal escalate flow

> **CI feedback**: When the CI workflow is configured via `/setup-ci`, the test result summary is auto-posted to PR comments (updated via the sticky comment scheme). When you create a PR with `/create-pr` after Phase Review, you can check CI results from the PR comments. If `--no-pr-comments` is set, no comments are posted.

#### 3.5.3 Complete

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
2. After parallel-worker completes, skip step 5 (UT) and proceed to step 6 (review-worker)
3. review-worker reviews across all aspects as usual (but skip category E: final test verification)

### 3.7 Prepare Worktrees

Prepare a git worktree for each task in the wave. This allows parallel-worker and review-worker to work safely in independent working directories without affecting the orchestrator's main branch.

**For multi-task waves**: Per `${CLAUDE_PLUGIN_ROOT}/rules/serial-execution-policy.md`, tasks in a wave are launched one at a time. Create the worktree for the current task, run steps 4-8 to completion, then create the worktree for the next task. Do NOT pre-create worktrees for all tasks in the wave up front.

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

**Tasks within a wave are launched serially** (`${CLAUDE_PLUGIN_ROOT}/rules/serial-execution-policy.md`). A single message MAY contain at most one `Agent` tool invocation. Wait until the prior `parallel-worker` returns `completed` or `retry_exhausted` before launching the next task. Concurrent launches are prohibited even when the wave contains multiple tasks.

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
    Task log path: {project-path}/.spec-workflow/specs/{spec-name}/task-logs/{task-id}.log.md
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

    Apply ${CLAUDE_PLUGIN_ROOT}/rules/diagnostic-reasoning.md DR1-DR6 and ${CLAUDE_PLUGIN_ROOT}/rules/failure-taxonomy.md FC1-FC6 throughout retries. Persist all diagnostic state as \`## Events\` entries in the task log at \`{Task log path}\` per \`${CLAUDE_PLUGIN_ROOT}/rules/task-log-format.md\` (each attempt-result event carries a \`category\` inline key). Apply DR6 DIVERGENT if the most recent 2 failed attempts in the current phase share the same main failure_category (FC5).

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
    - changed_files: list of all changed files (the task log lives outside the worktree, so it will not appear in worktree diffs anyway)
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
>
> **Agent selection**:
>
> - For Leptos frontend components (`#[component]`, `view!`, signal, memo, `#[server]`, `src/pages/`, `src/components/`): `frontend-test-engineer`
> - For other Rust unit test supplementation: `unit-test-engineer`
> - C#/.NET projects (presence of `.cs`, `.csproj`): `unit-test-engineer` (already supports the C#/xUnit section). Blazor code-behind tests are also handled by the same agent
> - Projects matching none of the above use a general-purpose subagent that meets the same 4-category criteria

Verify the quality of tests written during the TDD cycle and supplement any missing test perspectives. TDD is "a development method that writes tests first to drive implementation"; this step independently verifies the quality of the implemented code.

Pass the implementation files to the selected test engineer agent and have it confirm coverage of required test perspectives (happy path, boundary values, exception handling, edge cases).

Leptos frontend task detection hints:

- `_Prompt` contains `#[component]`, `view!`, signal, memo, `#[server]`
- Target files are under `src/pages/`, `src/components/`, `src/server_fns/`
- `Cargo.toml` contains `[package.metadata.leptos]` and the implementation contains UI logic

Select the test engineer agent based on the detection hints above, then call:

```javascript
// For Leptos frontend tasks:
//   subagent_type: "spec-workflow-mcp:frontend-test-engineer"
// For other Rust tasks:
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

- `ut_action: added` → run the tests, confirm all pass, and proceed to step 6
- `ut_action: verified_sufficient` → proceed directly to step 6

### 6. Code Review + Commit (review-worker) [AGENT CALL REQUIRED]

> ⛔ **Do not commit yourself. Always call the `review-worker` agent.**

Delegate code review and commit to the `review-worker` agent. Separating implementation (parallel-worker) and review (review-worker) responsibilities ensures quality.

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:review-worker",
  description: "Review and commit",
  prompt: `⚠️ INDEPENDENT REVIEW REQUIRED ⚠️
    This code has passed through parallel-worker (TDD) and test engineer (frontend-test-engineer or unit-test-engineer).
    However, you MUST NOT assume it is correct because previous steps reported success.
    Previous results are provided as reference ONLY — your independent, critical review is mandatory.
    Treat this as if you are seeing the code for the first time. Your job is to find problems, not confirm success.

    Review the following changes and commit if they meet quality standards.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}
    Changed files: {changed_files from step 4 + added_to_files from step 5 + modified_implementation_files from step 5}
    Task prompt: {paste the full _Prompt content here}

    **Important**: Always run \`cd {WORKTREE_PATH}\` before reviewing and committing.

    Previous step results (reference only — do not let these bias your review):
    UT quality verification results (step 5):
    - ut_action: {ut_action from step 5}
    - added_tests: {added_tests from step 5}
    - modified_implementation_files: {modified_implementation_files from step 5}
    - coverage_summary: {coverage_summary from step 5}
    - excluded_as_e2e: {excluded_as_e2e from step 5}

    Notes:
    - Tests listed in added_tests have already been quality-verified by the appropriate test engineer (frontend-test-engineer or unit-test-engineer).
      In category E (final test verification), do not flag these tests as "insufficient".
    - excluded_as_e2e lists concerns intentionally deferred to E2E testing. Do not flag these as missing unit test coverage.
      However, style, naming, and sensitive data checks should be performed as usual.

    ## Review Checklist (specific checks per category)
    For each question below, record a concrete answer in observations:

    **A: Style** — Do the names accurately express intent? Is the style consistent with existing project code?
    **B: Design** — Is unwrap() being used inappropriately? Does each function have a single responsibility? Is the dependency direction correct?
    **C: Security** — Is external input validated? Are internal details leaking in responses? Is SQL going through a query builder?
    **D: Spec** — Verify each Success criterion in _Prompt one by one and explicitly state whether each is satisfied or unmet
    **E: Tests** — Are tests in sync with the implementation? Is there value verification (not just is_ok() but checking concrete values)?
    **F: Design Conformance** — Have any fields / endpoints undefined in design.md been added?
    **G: API Documentation** — On API changes (endpoint additions / changes / type changes), verify that \`docs/openapi.yaml\` is updated. Skip if openapi.yaml does not exist.

    Important: Always include the observations for each category in the completion report.
    Even when "no issues", record what was checked to reach that judgment.
    Even when review_action is commit, observations and auto_fixed are required.
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
    Task log path: {project-path}/.spec-workflow/specs/{spec-name}/task-logs/{task-id}.log.md

    **Important**: Always run \`cd {WORKTREE_PATH}\` before making fixes.

    rework_attempt: {N} / 3 (maximum 3 times)

    Current findings:
    {findings from review-worker}

    Diagnostic history (prior rework attempts — DO NOT repeat failed approaches):
    {diagnostic_history — use "(First rework — no prior attempts)" on first rework, accumulated on subsequent reworks}

    Apply diagnostic-reasoning.md DR1-DR6 and failure-taxonomy.md FC1-FC6:
    - Append a \`rework-start cycle={N}\` event to the task log's \`## Events\` section, then \`attempt-start\` / \`attempt-result\` events per DR2 (each \`attempt-result\` carries the \`category\` inline key per FC4)
    - Your diagnosis MUST identify a different root cause or approach from the diagnostic history above (DR4)
    - **DR6 DIVERGENT check**: If the most recent 2 \`attempt-result\` FAIL entries (combining task log events + diagnostic_history) share the same main \`failure_category\` (per FC5), append a \`divergent-analysis\` event before the next \`attempt-start\`, articulating the shared implicit assumption and how this attempt invalidates it. The Approach must fundamentally differ, not be a parameter tweak
    - On the final attempt (3/3), call advisor() with your diagnosis before implementing (DR5). Include the \`divergent-analysis\` event details if applicable
    - On rework completion, append a \`rework-complete cycle={N} changed_files=...\` event

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
   - The diagnosis summary fields: `root_cause`, `responsible_files` (list), `approach`, `failure_category`, `failure_subcategory` (optional) — these names follow `failure-taxonomy.md` FC2
   - The `divergent_applied` flag (if present)
   - The quality check results (pass/fail)
3. **Append to diagnostic_history in DR2 + FC4 format** (fields come from the worker's completion report; if a field is absent, note it as `(not reported)`):

   ```text
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

```text
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

   ```text
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

  - `observations` (optional — review-worker's review observation log. An extension field not in the tool schema. Maps to the `observations` key in the review-worker completion report):

    ```json
    "observations": {
      "style": "checked-ok: naming conventions followed, create_user/UserDto etc.",
      "design": "checked-ok: AppError conversion present, no unwrap()",
      "security": "checked-ok: query builder used, input validation present",
      "spec_compliance": "checked-ok: all 3 Success criteria satisfied",
      "test_quality": "checked-ok: concrete value verification present, boundary value tests present",
      "design_conformance": "checked-ok: no additions outside design.md definitions"
    }
    ```

  - `auto_fixed` (optional — an extension field not in the tool schema. Record review-worker's completion report `auto_fixed` key verbatim): list of auto-fixed Minor issues (empty array `[]` when zero):

    ```json
    "auto_fixed": [
      { "category": "A:style", "file": "src/handler.rs:45", "description": "Changed unwrap() to map_err()" }
    ]
    ```

  - If reworkCount is 0 (passed on first attempt), `findings` may be omitted. `observations` and `auto_fixed` are optional extension fields (not in tool schema) but recommended for traceability. The orchestrator must record the `auto_fixed` array from the review-worker completion report verbatim:

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
- If the `/log-implementation` skill is unavailable: Manually append the `## Summary` / `## Statistics` / `## Files Modified` / `## Files Created` / `## Artifacts` / `## Review Process` sections to the task log at `.spec-workflow/specs/{spec-name}/task-logs/{taskId}.log.md` per `${CLAUDE_PLUGIN_ROOT}/rules/task-log-format.md` TL5

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

#### Session update (on task completion)

After the merge, record this in the session's `completed_tasks`.
`{commit-hash}` is the commit hash created by review-worker (the task commit before merge):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-manage.sh" complete-task {task-id} {commit-hash}
```

This clears `current_task`, which is then re-set by start-task when the next task is selected.

Then move to the next pending wave and repeat.

### 9. Final E2E Gate (after all Phases complete)

After all Phase implementations finish (after the last PhaseReview task is `[x]`), run the final E2E gate.
Unlike per-Phase integration verification (3.5.1.5), this is the **final check that integrates all deliverables**.

#### 9.1 Trigger Condition

Auto-starts when every task in tasks.md (including PhaseReview) is `[x]`.

#### 9.2 Verification Steps

For command definitions, see the "Integration Verification" section in `quality-checks.md`.

##### Step 1: Full Build Verification

Verify that a clean build of the whole project succeeds.

```bash
# Rust
cargo build

# Leptos
cargo leptos build

# Node.js
npm run build
```

##### Step 2: Run All Tests

Run all unit tests + integration tests.

```bash
# Rust
cargo test --quiet

# Node.js
npm test
```

##### Step 3: Run Integration Tests

If integration tests exist, run integration tests explicitly.

```bash
# Rust
cargo test --tests --quiet

# Node.js
npm run test:integration
```

##### Step 4: Full Smoke Test (API projects only)

Same procedure as the Phase Review smoke test (Step D), but in addition to the health check, also check responses for the major endpoints defined in design.md.

- Health check: GET requests to `/health`, `/api/health`, `/healthz`
- Major endpoints: extract GET endpoints from the API definitions in design.md and verify status codes
  - Endpoints requiring authentication must return 401 (returning 200 without auth indicates a security issue)
  - Endpoints not requiring authentication must return 200 or 404 (no data)

##### Step 5: Run E2E Tests (container-based — per test-design.md spec)

Run when tests based on the E2E specs in test-design.md exist (tests created by `/spec-e2e-implement`).

```bash
# Start test container
if [ -f docker-compose.test.yml ]; then
  docker-compose -f docker-compose.test.yml up -d
  # Wait for health check (up to 60 seconds)
fi
```

| Runner | Detection Condition | Command |
|--------|---------------------|---------|
| Playwright | `playwright.config.ts` exists | `npx playwright test` |
| Rust E2E | `tests/e2e/` directory exists | `cargo test --tests --quiet` |
| Node.js E2E | `package.json` has `test:e2e` | `npm run test:e2e` |

```bash
# Stop and clean up test container
if [ -f docker-compose.test.yml ]; then
  docker-compose -f docker-compose.test.yml down -v
fi
```

When no E2E test files exist (judged in priority order — **follow this rule strictly**):

1. design.md's "Excluded Test Environments" explicitly excludes E2E tests → **SKIP (excluded at design time)** (record exclusion reason in log)
2. test-design.md defines E2E test specs → **FAIL (missing implementation)**. Report to the user that E2E tests are not implemented
   - "Spec exists" criterion: test-design.md contains a `## E2E Test Specifications` heading with at least one heading starting with `### E2E-` inside it
3. No spec satisfying the above conditions → **SKIP (not needed by design)**. Record reason in log and continue

**SKIPs for reasons such as "no environment", "server needed", "Chrome needed" are not allowed at all.** Such tools must be listed as Required=Yes in Required Tools and verified in Step 0.

#### 9.3 Result Judgment

| Result | Action |
|--------|--------|
| **PASS** | All steps are PASS only (no SKIP) → proceed to Step 10 (PR creation) |
| **PASS (with SKIP)** | No FAIL; results are PASS and SKIP only → proceed to Step 10 (PR creation). Note each SKIP reason in the PR body Notes section |
| **FAIL** | Analyze the failure location and identify the relevant Phase / task. Revert the task from `[x]` to `[-]` and re-run that task's step 4. Revert PhaseReview to `[ ]` as well |
| **FAIL (environment issue)** | Required tool / runtime not installed. Report missing tools to the user and present the Install Command from the Required Tools table. Halt implementation |
| **FAIL (missing implementation)** | test-design.md defines test specs but no test file exists. Report the missing implementation to the user |
| **SKIP (not needed by design)** | Only when the test spec itself does not exist in design docs. Record SKIP reason in log and continue |
| **SKIP (excluded at design time)** | Only for tests explicitly excluded under design.md's "Excluded Test Environments". Record exclusion reason in log |

**Note**: SKIPs for reasons such as "no environment", "server needed", "Chrome needed" are not allowed at all.

#### 9.4 Final Report

Save the Final E2E Gate result to `.spec-workflow/specs/{spec-name}/reviews/final-e2e-gate.md`.

```markdown
# Final E2E Gate Report

## Spec: {spec-name}

## Date: {date}

## Results

| Step | Result | Details |
|------|--------|---------|
| Build | PASS/FAIL/SKIP(build command not detected) | {details} |
| All Tests | PASS/FAIL(test failure)/FAIL(environment issue)/SKIP(not needed by design)/SKIP(excluded at design time) | {N} passed, {M} failed / reason for inability to run, etc. |
| Integration Tests | PASS/FAIL(integration test)/FAIL(missing implementation)/FAIL(environment issue)/SKIP(not needed by design)/SKIP(excluded at design time) | {details} |
| Smoke Test | PASS/FAIL(smoke)/FAIL(environment issue)/SKIP(not needed by design)/SKIP(excluded at design time) | {details} |
| E2E Tests | PASS/FAIL(missing implementation)/FAIL(environment issue)/SKIP(not needed by design)/SKIP(excluded at design time) | {details} |

## Verdict: PASS / PASS(with SKIP) / FAIL(test failure) / FAIL(environment issue) / FAIL(missing implementation)

- **PASS**: All steps are PASS
- **PASS(with SKIP)**: All steps succeed including SKIP(not needed by design), SKIP(excluded at design time), SKIP(build command not detected). Note SKIP reasons in Notes
- **FAIL(test failure)**: Failure during test execution
- **FAIL(environment issue)**: Required tool / runtime not installed → STOP
- **FAIL(missing implementation)**: test-design.md has a spec but no test file

## Notes

{FAIL details, SKIP(not needed by design) reason, exclusion-at-design-time rationale, etc.}
```

#### Handling wave failure

When any task becomes `retry_exhausted` during a multi-task wave:

1. **Continue executing** the remaining tasks in the wave — do not abort the entire wave
2. After all tasks in the wave have completed / failed, report a summary to the user:
   - Succeeded: [task-ids]
   - Failed: [task-ids with reasons]
3. Subsequent-wave tasks that depend on a failed task (via `_DependsOn:`):
   - Add a `<!-- BLOCKED: dependency {failed-task-id} failed -->` comment to the task line and set the checkbox state to `- [ ]` (do not change the checkbox token itself)
   - Skip these tasks in subsequent waves
4. Subsequent-wave tasks that **do not depend** on a failed task:
   - Continue executing as usual in the next wave

### 10. PR Creation (after Final E2E Gate PASS)

If the Final E2E Gate is PASS (including with SKIPs), proceed to the PR creation phase.
On FAIL, skip PR creation and proceed to the fix flow (per the result judgment in 9.3).

**Important:** The orchestrator itself must NOT run `/create-pr` directly (⛔ `git commit` prohibition rule). PR creation is **delegated to review-worker**. `git commit` / `git push` during `/create-pr` (e.g., screenshot additions) is also review-worker's responsibility.

Pass the following arguments / information to review-worker:

- `--spec {spec-name}`
- `--skip-tests` (since all tests already ran in the Final E2E Gate)
- `--title "{feature summary based on spec-name}"`
- Hand off the contents of the Notes section in the Final E2E Gate report (`final-e2e-gate.md`) to `/create-pr` and copy them into the PR body's Notes section

> review-worker runs the `/create-pr` skill with the arguments above. The skill reads test results and Notes from the Final E2E Gate report, detects UI changes, takes screenshots if applicable, and creates the PR. Any required commits / pushes are also handled by review-worker.

After PR creation, display the final status via the `/spec-status` skill.

### Session Termination

After all waves complete (or after a user escalation due to Final E2E Gate FAIL), terminate the implementation session:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-manage.sh" end
```

The lockfile is removed and the session body remains as `.implement-session.json` (for later reference).

### Spec Archive (when Orchestrator completes)

After all waves complete (Final E2E Gate PASS) and PR creation succeeds, archive the implementation spec itself with `/spec-archive` to
`.spec-workflow/archive/specs/{spec-name}/`:

```text
/spec-archive {spec-name}
```

This:

- Renames `.spec-workflow/specs/{spec-name}/` → `.spec-workflow/archive/specs/{spec-name}/`
  (same path convention as archive-service)
- Removes the spec from the dashboard's Active tab and shows it on the Archived tab
- Can be reverted via the unarchive button if needed
- `.implement-session.json` can also be archived to `.spec-workflow/archive/sessions/` via `session-manage.sh archive`

On FAIL / escalation, do not archive (leave active so implementation can continue).

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

- Feature names use kebab-case
- One **wave** in-progress at a time, and within a wave **only one task** is in-progress at a time (per `${CLAUDE_PLUGIN_ROOT}/rules/serial-execution-policy.md`)
- Always search implementation logs before coding (step 2)
- Follow TDD: tests first (RED), then implementation (GREEN), then refactor (REFACTOR)
- **Implementation (parallel-worker) and review (review-worker) are separate agents** — parallel-worker does not commit, review-worker does not implement
- Always call `/log-implementation` skill before marking a task `[x]` (step 7)
- Include test files in `filesCreated` when logging
- A task marked `[x]` without a log is incomplete
- If you encounter blockers, document them and move to another task
