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
  model: "sonnet",
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
- **Compile error**: If the test runner fails to build/compile (e.g. unresolved import of not-yet-implemented module), treat this as a hard failure — return `{ status: "fail", failure_category: "compile_error", failure_subcategory: "unresolved_import" | "syntax_error" | "type_error" | "missing_symbol", message: "Compile error: {error summary}", ... }`. The calling agent must fix the compile error before RED can be validated.
- If any test passes, report it as a problem — this means either:
  - The test is not actually testing new behavior
  - There's already an implementation that satisfies the test
  - Return `failure_category: "test_failure"` / `failure_subcategory: "unexpected_pass"`
- Return: `{ status: "pass", ... }` if all failed (and build succeeded), `{ status: "fail", failure_category: ..., message: "N tests unexpectedly passed", ... }` otherwise

**Green mode** (`green`):
- EXPECTED: All tests pass (failed = 0)
- If any test fails, report each failure with its error message
- Classify the first failing test per `failure-taxonomy.md` FC1:
  - Build/compile failure → `failure_category: "compile_error"`
  - Assertion failure (expected != actual) → `failure_category: "test_failure"` / `failure_subcategory: "assertion_failure"`
  - Uncaught exception / panic → `failure_category: "test_failure"` / `failure_subcategory: "panic"`
  - Test runner timeout → `failure_category: "test_failure"` / `failure_subcategory: "timeout"`
- Return: `{ status: "pass", ... }` if all passed, `{ status: "fail", failure_category: ..., failure_subcategory: ..., message: "N tests failed", errors: [...] }` otherwise

## Output Format

Return to the calling agent:

```
## Test Run Result

- **Mode**: {red|green}
- **Status**: {pass|fail}
- **Total**: {N} tests
- **Passed**: {N}
- **Failed**: {N}
- **Failure Category**: {FC1 main category — only when Status=fail; see failure-taxonomy.md FC1}
- **Failure Subcategory**: {FC1 subcategory — only when Status=fail; optional}

### Errors (if any)
- {test name}: {error message}

### Verdict
{Description of whether the result matches expectations}
```

The `Failure Category` / `Failure Subcategory` fields are required when `Status=fail` per `failure-taxonomy.md` FC2. The calling agent uses these values when writing the DR2 attempt entry (FC4) and when deciding whether DR6 DIVERGENT applies (FC5).
