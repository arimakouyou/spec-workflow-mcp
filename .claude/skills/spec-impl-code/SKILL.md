---
name: spec-impl-code
description: "TDD GREEN phase for spec-implement workflow. Writes minimal production code to make failing tests pass. Designed to run as a subagent — spawn it with the Agent tool. Triggers on: subagent calls from spec-implement orchestrator only."
---

# Code Writer — GREEN Phase (Subagent)

This skill is designed to run as a **subagent** via the Agent tool. It writes the minimal production code needed to make failing tests pass, following TDD's GREEN phase.

## How the Calling Agent Should Invoke This

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "GREEN: Implement to pass tests",
  prompt: `You are a TDD implementer. Write minimal code to make the failing tests pass.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Task prompt: {task _Prompt content}
    Test files: {test-file-paths}
    Leverage files: {_Leverage file paths}

    Follow the /spec-impl-code skill instructions.

    Return the list of files created/modified and implementation approach.`
})
```

## GREEN Phase Rules

1. **Make the tests pass** — that is the only goal
2. **Write minimal code** — just enough to satisfy the tests (YAGNI)
3. **Do NOT modify test files** — tests are the specification
4. **Do NOT add untested features** — if there's no test for it, don't build it

## Execution Steps

### 1. Read and Understand the Tests

- Read each test file to understand:
  - What modules/functions are imported (these need to be created)
  - What interfaces are expected (parameters, return types)
  - What behavior is verified (assertions define the contract)
  - What error conditions are tested

### 2. Plan the Implementation

From the tests, derive:
- Which files need to be created
- What functions/classes/methods are needed
- What types/interfaces are expected
- What the input/output contracts are

### 3. Choose a Green Strategy

Follow `/tdd-skills` Green Strategies:

1. **Obvious Implementation** (preferred when solution is clear): Implement the real logic directly
2. **Fake It** (when uncertain): Return a constant first, then generalize
3. **Triangulation** (when multiple cases exist): Generalize from multiple test assertions

### 4. Implement

- Read `_Leverage` files to understand existing patterns and utilities
- Follow the codebase's existing conventions (naming, structure, error handling)
- Create the modules that tests import
- Implement functions/classes with the expected signatures
- Handle all test cases including error scenarios

**Key constraint**: Write only what the tests demand. If a test doesn't check for input validation, don't add it. If a test doesn't verify logging, don't add it.

### 5. Verify Locally (Optional Quick Check)

If possible, do a quick mental check that:
- All imported modules now exist
- All expected exports are present
- Function signatures match what tests call
- Return types match what tests assert

## Output Format

Return to the calling agent:

```
## GREEN Phase Complete

### Files Created
- {path/to/new-file-1}: {brief description}
- {path/to/new-file-2}: {brief description}

### Files Modified
- {path/to/existing-file}: {what was changed}

### Implementation Approach
{1-3 sentences describing the approach taken and key decisions}

### Green Strategy Used
{Obvious Implementation / Fake It / Triangulation} — {reason}
```
