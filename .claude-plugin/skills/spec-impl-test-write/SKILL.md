---
name: spec-impl-test-write
description: "TDD RED phase for spec-implement workflow. Writes failing tests before any production code. Designed to run as a subagent — spawn it with the Agent tool. Triggers on: subagent calls from spec-implement orchestrator only."
---

# Test Writer — RED Phase (Subagent)

This skill is designed to run as a **subagent** via the Agent tool. It writes failing tests based on task specifications, following TDD's RED phase.

## How the Calling Agent Should Invoke This

```javascript
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "RED: Write failing tests",
  prompt: `You are a TDD test writer. Write failing tests for the task described below.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Task prompt: {task _Prompt content}
    Test focus areas: {_TestFocus content from task, if available}
    Design doc path: {project-path}/.spec-workflow/specs/{spec-name}/design.md
    Evidence files: {_Evidence EV IDs, resolved to full paths by the orchestrator}

    Follow the /spec-impl-test-write skill instructions.
    Read ONLY the listed evidence files — do not load other EV-*.md files.

    Return the list of test files created and test names.`
})
```

## RED Phase Rules

1. **Write tests FIRST** — before any production code exists
2. **Tests MUST fail** — imports will reference modules that don't exist yet, and that's correct
3. **Do NOT write production code** — not even stubs or empty implementations
4. **Do NOT modify existing production code**

## Execution Steps

### 0. Load Project-Level Context (Steering)

Before planning tests, load project-level instance information from steering documents **if they exist**:

- `{project-path}/.spec-workflow/steering/tech.md` — confirms the test framework actually in use for this project (e.g., vitest vs jest, cargo test vs nextest) and any performance/compatibility targets the tests may need to guard. Treat this as the tie-breaker when multiple frameworks could apply.
- `{project-path}/.spec-workflow/steering/structure.md` — **File Placement Rules (P4-01)**. Use the "Unit Test" / "Integration Test" / "E2E Test" rows to decide **where the test file must live** and **how it must be named**. Do not invent a location if the rule exists.
- `{project-path}/.spec-workflow/steering/product.md` — product principles / non-goals (skip if absent; used only to resolve ambiguity about scope).

Skip any file that does not exist; steering docs are optional.

### 1. Understand What to Test

- Read the task's `_Prompt` field (provided in the prompt) for Role, Task, Restrictions, Success criteria
- If a `_TestFocus` field is provided (via the "Test focus areas" parameter), it is structured in 4 categories: **Happy Path / Boundary Values / Error Handling / Edge Cases**. Write tests covering **all 4 categories** as specified — these categories are aligned with the unit-test-engineer's quality verification criteria to minimize rework
- Read the design document to understand interfaces, data models, and expected behavior
- Identify the public API surface: functions, methods, endpoints, components

### 1.5 Load Evidence (Selective)

If the task carries an `_Evidence:` line (`.claude-plugin/rules/evidence-coverage.md` EC2) — resolved by the orchestrator to full `.spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md` paths — read **only those files**.

- Evidence files typically cite the current contract (`EV-contract-current-*`), branches (`EV-branches-*`), regressions (`EV-regressions-*`), or harness (`EV-test-harness-*`) that the tests must guard. Use the `sources:` frontmatter entries to locate the exact code ranges the tests should lock in.
- Do **not** read other EV files from the spec's `evidence/` directory — they belong to other tasks.
- Do **not** re-derive the current behavior from scratch. If an evidence file cites `path:Lx-Ly` showing the existing contract, your tests should assert compatibility with that contract, not guess at it.
- If the task has no `_Evidence:` line, skip this step. Legacy specs (no `task_type`) will also have no evidence.

### 2. Discover Existing Test Patterns

Before writing tests, understand the project's testing conventions. When `tech.md` and `structure.md` from step 0 already state the framework and test placement, trust them first and only fall back to filesystem discovery for gaps:

- Search for existing test files to determine:
  - Test framework (vitest, jest, pytest, etc.) — prefer the one recorded in `tech.md` if set
  - File naming convention (`*.test.ts`, `*.spec.ts`, `*_test.py`, etc.) — prefer the `structure.md` P4-01 row for the relevant test type
  - Directory structure (`__tests__/`, `tests/`, co-located, etc.) — same: P4-01 wins when it specifies
  - Import patterns and test utilities
  - Assertion style (`expect()`, `assert`, etc.)

```bash
# Find existing test files
find . -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" | head -20
```

### 3. Write Tests

Follow `/tdd-skills` principles:

**Test Structure** — Use Given-When-Then:
```
// Given — set up preconditions
// When  — perform the action
// Then  — verify the outcome
```

**Test Naming** — Use descriptive names:
- `test_{action}_when_{condition}` (e.g., `test_returns_empty_when_no_users`)
- `test_{action}_raises_{error}_when_{condition}` (e.g., `test_raises_not_found_when_invalid_id`)

**What to Test:**
- Happy path: Normal expected behavior from Success criteria
- Edge cases: Empty inputs, boundary values, nulls
- Error cases: Invalid inputs, missing data, error scenarios from design doc
- Refer to `/tdd-skills` references for boundary value analysis and test design

**Leptos Frontend Components:**
When the task involves Leptos components, signals, or `view!`:
- Extract testable logic from components (validation, computation, state transitions)
- Write tests for the extracted functions. Do not write tests for `view!` macro output
- Test signal behavior: creation, updates, derived state
- Refer to patterns in `../tdd-skills-rust/references/leptos-frontend-testing.md`

**Test Organization:**
- One test file per component/module being tested
- Group related tests with `describe`/`context` blocks
- Keep tests independent (F.I.R.S.T principles)

### 4. Verify Test Imports Reference Non-Existent Code

The tests should import from modules that will be created during the GREEN phase. For example:

```typescript
// This import WILL fail — the module doesn't exist yet. That's correct.
import { createUser } from '../services/user-service';
```

This is the expected state in the RED phase.

## Output Format

Return to the calling agent:

```
## RED Phase Complete

### Test Files Created
- {path/to/test-file-1}
- {path/to/test-file-2}

### Tests Written
- {describe block}: {test name 1}
- {describe block}: {test name 2}
- ...

### Test Runner Command
{command to run these specific test files}

### Notes
- {any assumptions or decisions made}
```
