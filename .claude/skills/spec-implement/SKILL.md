---
name: spec-implement
description: "Phase 4 of spec-driven development: implement tasks from an approved tasks.md document using TDD (Red-Green-Refactor). Use this skill when the user wants to start implementing, code a task, work on a specific task ID, or continue implementation. Triggers on: 'implement task', 'start coding', 'work on task 3', 'implement spec X', 'continue implementation', or any request to write code for a spec task."
---

# Spec Implementation (Phase 4) — TDD Orchestrator

Execute tasks systematically from the approved tasks.md using a **TDD-driven workflow**. Each task follows the cycle: Start → Discover → RED → Verify Red → GREEN → Verify Green → REFACTOR → Verify Refactor → Log → Complete.

## Prerequisites

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

If the task has `_PhaseReview: true_`, **skip the TDD cycle (steps 4-9)** and instead:

1. Run the full test suite and confirm all tests pass
2. Code review all files changed during this phase
3. Use `/commit` skill to stage and commit with a message summarizing the phase deliverables
4. Proceed directly to step 10 (Log)

### 4. RED — Write Failing Tests

Spawn a subagent to write tests before any production code:

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "RED: Write failing tests",
  prompt: `You are a TDD test writer. Write failing tests for the task described below.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Task prompt:
    {paste the full _Prompt content here}

    Test focus areas: {_TestFocus content from task, if available}

    Design doc path: {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Follow the /spec-impl-test-write skill instructions.

    Return the list of test files created and test names.`
})
```

Capture from the result: **test file paths** and **test runner command**.

### 5. Verify Red — All Tests Must Fail

Spawn a subagent to run the tests in `red` mode:

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "Run tests (red mode)",
  prompt: `You are a TDD test runner. Execute the specified tests and validate the results.

    Project path: {project-path}
    Test files: {test-file-paths from step 4}
    Expected mode: red

    Follow the /spec-impl-test-run skill instructions.

    Return a structured result summary.`
})
```

- If **Status: pass** (all tests fail) → proceed to step 6
- If **Status: fail** (some tests pass) → investigate and fix the tests, then re-verify

### 6. GREEN — Write Minimal Production Code

Spawn a subagent to implement just enough code to make tests pass:

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "GREEN: Implement to pass tests",
  prompt: `You are a TDD implementer. Write minimal code to make the failing tests pass.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Task prompt:
    {paste the full _Prompt content here}

    Test files: {test-file-paths from step 4}
    Leverage files: {_Leverage file paths from task}

    Follow the /spec-impl-code skill instructions.

    Return the list of files created/modified and implementation approach.`
})
```

Capture from the result: **implementation file paths**.

### 7. Verify Green — All Tests Must Pass

Spawn a subagent to run the tests in `green` mode:

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "Run tests (green mode)",
  prompt: `You are a TDD test runner. Execute the specified tests and validate the results.

    Project path: {project-path}
    Test files: {test-file-paths from step 4}
    Expected mode: green

    Follow the /spec-impl-test-run skill instructions.

    Return a structured result summary.`
})
```

- If **Status: pass** (all tests pass) → proceed to step 8
- If **Status: fail** → fix the implementation and re-verify. **Retry up to 3 times**. If still failing after 3 retries, stop and report the failure to the user.

### 8. REFACTOR — Review and Clean Up

Spawn a subagent to refactor the code:

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "REFACTOR: Review and clean up",
  prompt: `You are a TDD refactoring reviewer. Review and refactor the code written in the RED-GREEN phases.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Task prompt:
    {paste the full _Prompt content here}

    Test files: {test-file-paths from step 4}
    Implementation files: {implementation-file-paths from step 6}
    Success criteria: {Success field from _Prompt}

    Follow the /spec-impl-review skill instructions.

    Return the list of changes made and quality assessment.`
})
```

### 9. Verify Refactor — Tests Still Pass

Spawn a subagent to re-run tests in `green` mode after refactoring:

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "Run tests (green mode)",
  prompt: `You are a TDD test runner. Execute the specified tests and validate the results.

    Project path: {project-path}
    Test files: {test-file-paths from step 4}
    Expected mode: green

    Follow the /spec-impl-test-run skill instructions.

    Return a structured result summary.`
})
```

- If **Status: pass** → proceed to step 10
- If **Status: fail** → revert the refactoring changes and re-verify. Keep the GREEN phase code.

### 10. Log Implementation (MANDATORY)

Call the `log-implementation` MCP tool BEFORE marking the task complete. A task without a log is not complete — this is the most commonly skipped step.

Required fields:
- `specName`: The spec name
- `taskId`: The task ID you just completed
- `summary`: Clear description of what was implemented (1-2 sentences)
- `filesModified`: List of files you edited
- `filesCreated`: List of new files — **include test files**
- `statistics`: `{ linesAdded: number, linesRemoved: number }`
- `artifacts` (required — enables future discovery):
  - `apiEndpoints`: API routes created/modified (method, path, purpose, request/response formats, location)
  - `components`: UI components created (name, type, purpose, props, location)
  - `functions`: Utility functions (name, signature, location)
  - `classes`: Classes with methods and location
  - `integrations`: How frontend connects to backend, data flow descriptions

### 11. Complete the Task

Only after `log-implementation` returns success:
- Verify all success criteria from the `_Prompt` are met
- Edit tasks.md: Change `[-]` to `[x]`

Then move to the next pending task and repeat.

## Monitoring Progress

Use the `spec-status` MCP tool at any time to check overall progress, task counts, and approval status.

## Rules

- Feature names use kebab-case
- One task in-progress at a time
- Always search implementation logs before coding (step 2)
- Follow TDD: tests first (RED), then implementation (GREEN), then refactor (REFACTOR)
- Each phase is a separate subagent to keep concerns isolated
- Always call log-implementation before marking a task `[x]` (step 10)
- Include test files in `filesCreated` when logging
- A task marked `[x]` without a log is incomplete
- If you encounter blockers, document them and move to another task
