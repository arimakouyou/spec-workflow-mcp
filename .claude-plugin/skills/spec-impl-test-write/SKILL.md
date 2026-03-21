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
  description: "RED: Write failing tests",
  prompt: `You are a TDD test writer. Write failing tests for the task described below.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Task prompt: {task _Prompt content}
    Test focus areas: {_TestFocus content from task, if available}
    Design doc path: {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Follow the /spec-impl-test-write skill instructions.

    Return the list of test files created and test names.`
})
```

## RED Phase Rules

1. **Write tests FIRST** — before any production code exists
2. **Tests MUST fail** — imports will reference modules that don't exist yet, and that's correct
3. **Do NOT write production code** — not even stubs or empty implementations
4. **Do NOT modify existing production code**

## Execution Steps

### 1. Understand What to Test

- Read the task's `_Prompt` field (provided in the prompt) for Role, Task, Restrictions, Success criteria
- If a `_TestFocus` field is provided (via the "Test focus areas" parameter), it is structured in 4 categories: **正常系 / 境界値 / 例外処理 / エッジケース**. Write tests covering **all 4 categories** as specified — these categories are aligned with the unit-test-engineer's quality verification criteria to minimize rework
- Read the design document to understand interfaces, data models, and expected behavior
- Identify the public API surface: functions, methods, endpoints, components

### 2. Discover Existing Test Patterns

Before writing tests, understand the project's testing conventions:

- Search for existing test files to determine:
  - Test framework (vitest, jest, pytest, etc.)
  - File naming convention (`*.test.ts`, `*.spec.ts`, `*_test.py`, etc.)
  - Directory structure (`__tests__/`, `tests/`, co-located, etc.)
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
