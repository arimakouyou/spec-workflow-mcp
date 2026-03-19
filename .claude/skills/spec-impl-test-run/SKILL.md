---
name: spec-impl-test-run
description: "TDD test runner for spec-implement workflow. Executes tests and validates results against expected mode (red=all fail, green=all pass). Designed to run as a subagent — spawn it with the Agent tool. Triggers on: subagent calls from spec-implement orchestrator only."
---

# Test Runner (Subagent)

This skill is designed to run as a **subagent** via the Agent tool. It executes specified test files and validates results against expected outcomes.

## How the Calling Agent Should Invoke This

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "Run tests ({mode} mode)",
  prompt: `You are a TDD test runner. Execute the specified tests and validate the results.

    Project path: {project-path}
    Test files: {test-file-paths}
    Expected mode: {red|green}

    Follow the /spec-impl-test-run skill instructions.

    Return a structured result summary.`
})
```

## Parameters

- **Project path**: Root directory of the project
- **Test files**: Comma-separated list of test file paths to execute
- **Expected mode**: `red` (all tests should fail) or `green` (all tests should pass)

## Execution Steps

### 1. Detect Test Runner

Detect the project's test runner by checking (in order):

1. `package.json` scripts — look for `test`, `vitest`, `jest` scripts
2. Config files: `vitest.config.*`, `jest.config.*`, `pytest.ini`, `pyproject.toml`
3. Dependencies in `package.json`: `vitest`, `jest`, `mocha`, `pytest`

### 2. Run Tests

Execute **only the specified test files**, not the full suite:

```bash
# Examples by runner:
npx vitest run {test-files} --reporter=verbose
npx jest {test-files} --verbose
python -m pytest {test-files} -v
```

Use the `--reporter=verbose` or equivalent flag to get per-test pass/fail details.

### 3. Parse Results

From the test output, extract:
- **total**: Number of tests executed
- **passed**: Number of tests that passed
- **failed**: Number of tests that failed
- **errors**: List of error messages for failed tests (test name + error)

### 4. Validate Against Mode

**Red mode** (`red`):
- EXPECTED: All tests fail (passed = 0)
- **Compile error**: If the test runner fails to build/compile (e.g. unresolved import of not-yet-implemented module), treat this as a hard failure — return `{ status: "fail", message: "Compile error: {error summary}", ... }`. The calling agent must fix the compile error before RED can be validated.
- If any test passes, report it as a problem — this means either:
  - The test is not actually testing new behavior
  - There's already an implementation that satisfies the test
- Return: `{ status: "pass", ... }` if all failed (and build succeeded), `{ status: "fail", message: "N tests unexpectedly passed", ... }` otherwise

**Green mode** (`green`):
- EXPECTED: All tests pass (failed = 0)
- If any test fails, report each failure with its error message
- Return: `{ status: "pass", ... }` if all passed, `{ status: "fail", message: "N tests failed", errors: [...] }` otherwise

## Output Format

Return to the calling agent:

```
## Test Run Result

- **Mode**: {red|green}
- **Status**: {pass|fail}
- **Total**: {N} tests
- **Passed**: {N}
- **Failed**: {N}

### Errors (if any)
- {test name}: {error message}

### Verdict
{Description of whether the result matches expectations}
```
