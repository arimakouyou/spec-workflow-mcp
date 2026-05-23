---
name: spec-e2e-implement
description: "Implement IT/E2E tests independently from main implementation. Uses test-design.md IT/E2E specifications to generate test code with container-based infrastructure (testcontainers, Playwright, docker-compose). Can run in parallel with /spec-implement. Triggers on: 'implement e2e tests', 'create e2e tests', 'e2e for X', 'integration tests for X', '/spec-e2e-implement'."
user-invokable: true
argument-hint: "<spec-name> [--scope it|e2e|all] [--spec-id IT-1,E2E-1]"
---

# E2E Test Implementation (Independent Line)

Independently of the main implementation (`/spec-implement`), generate test code based on the IT/E2E specifications in test-design.md. Uses container-based test infrastructure (testcontainers, docker-compose.test.yml, Playwright).

## Prerequisites Check (MANDATORY — DO NOT SKIP)

1. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists
2. Check `.spec-workflow/specs/{spec-name}/design.md` exists
3. Check `.spec-workflow/specs/{spec-name}/test-design.md` exists
4. Check `.spec-workflow/specs/{spec-name}/tasks.md` exists

If ANY file is missing — **STOP immediately.** Inform the user which file is missing and which skill to run.

| Missing File | Required Skill |
|-------------|---------------|
| requirements.md | `/spec-requirements` |
| design.md | `/spec-design` |
| test-design.md | `/spec-test-design` |
| tasks.md | `/spec-tasks` |

## Arguments

| Argument | Required | Description |
|----------|:--------:|-------------|
| `spec-name` | YES | Spec name in kebab-case |
| `--scope` | NO | `it` (integration tests only), `e2e` (E2E only), `all` (default: both) |
| `--spec-id` | NO | Implement only specific specs (e.g., `IT-1,E2E-2`) |

## Process

### 1. Read Test Design

1. Read `.spec-workflow/specs/{spec-name}/test-design.md`
2. Extract IT/E2E specifications (filter by `--scope` / `--spec-id`)
3. Get the technology selection from the **E2E Test Infrastructure** section:
   - Test runner (Playwright / reqwest / supertest, etc.)
   - DB strategy (testcontainers / docker-compose.test.yml)
   - Container Test Setup method

### 2. Check Implementation Readiness

Verify that the components targeted by the IT/E2E tests have been implemented in the main implementation:

```bash
# Check the completion status of target tasks in tasks.md
grep -E '\[x\]|\[-\]|\[ \]' .spec-workflow/specs/{spec-name}/tasks.md
```

| Status | Action |
|--------|--------|
| All target components `[x]` | Begin test implementation |
| Some are `[-]` (in progress) | Implement IT only for completed components. E2E waits |
| Targets are `[ ]` (not started) | Report to user: "Target components are not yet implemented. Please advance the main implementation via `/spec-implement` first." |

### 3. Infrastructure Setup (first time only)

If the test infrastructure is not set up, run the following. Equivalent to `_TDDSkip: true` (no test required for the test infrastructure itself).

#### 3.1 Verify docker-compose.test.yml

```bash
# Check whether docker-compose.test.yml exists
test -f docker-compose.test.yml && echo "exists" || echo "missing"
```

- If absent → create docker-compose.test.yml by launching a single `parallel-worker` agent (per `rules/serial-execution-policy.md`, agents MUST be launched one at a time)
- If present → skip

#### 3.2 Test Runner Setup

Based on the E2E Test Infrastructure selection:

| Runner | Setup |
|--------|-------|
| Playwright | `npm init playwright@latest`, generate `playwright.config.ts` |
| reqwest | Add `[dev-dependencies]` to `Cargo.toml` |
| supertest | `npm install --save-dev supertest @types/supertest` |
| testcontainers (Rust) | Add `testcontainers` dependency to `Cargo.toml` |
| testcontainers (Node) | `npm install --save-dev testcontainers` |

#### 3.3 Create Test Helpers and Shared Fixtures

Create the following by launching `parallel-worker` agents one at a time (per `rules/serial-execution-policy.md`). Wait for each to complete before launching the next:

- **Test DB helper**: Centralize testcontainers startup, migration, and seed-data loading
- **Test HTTP client**: Helper for sending requests with authentication tokens
- **Shared fixtures**: Seed data based on the Test Data Requirements in test-design.md

### 4. IT Implementation

For each IT spec in test-design.md, generate test code by launching a `parallel-worker` agent. **One agent at a time** — do not launch IT-1 and IT-2 in parallel (per `rules/serial-execution-policy.md`). Wait for each to complete before launching the next.

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:parallel-worker",
  description: "IT: Implement integration test IT-{N}",
  prompt: `Implement integration test based on the following specification.

    Project path: {project-path}
    Spec name: {spec-name}
    Worktree path: {WORKTREE_PATH}
    Branch: {BRANCH}

    IT Specification (from test-design.md):
    {paste IT-N specification including Technology, Steps, Verification Points}

    Test design doc path: {project-path}/.spec-workflow/specs/{spec-name}/test-design.md
    Design doc path: {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Container setup:
    - DB: Use testcontainers to start a clean DB container for each test
    - Apply migrations before test execution
    - Seed test data as defined in Test Data Requirements

    Important:
    - Always cd {WORKTREE_PATH} before starting
    - Test must be self-contained: start container → migrate → seed → test → cleanup
    - Each test function must clean up its own state
    - Use the test helpers created in step 3.3

    After implementation, run the test to confirm it passes.`
})
```

### 5. E2E Implementation

For each E2E spec in test-design.md, generate test code. **Launch one `parallel-worker` agent at a time** (per `rules/serial-execution-policy.md`); do not launch multiple E2E-N agents concurrently.

#### 5.1 API E2E (Test Type: API E2E)

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:parallel-worker",
  description: "E2E: Implement API E2E test E2E-{N}",
  prompt: `Implement API E2E test based on the following specification.

    {same context as IT implementation}

    E2E Specification (from test-design.md):
    {paste E2E-N specification}

    Server startup:
    1. docker-compose -f docker-compose.test.yml up -d
    2. Wait for health check to pass
    3. Run test scenarios against the running server
    4. docker-compose -f docker-compose.test.yml down after tests

    Use reqwest (Rust) or supertest (Node.js) to send HTTP requests.`
})
```

#### 5.2 Browser E2E (Test Type: Browser E2E / Full-Stack E2E)

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:parallel-worker",
  description: "E2E: Implement browser E2E test E2E-{N}",
  prompt: `Implement browser E2E test using Playwright based on the following specification.

    {same context as IT implementation}

    E2E Specification (from test-design.md):
    {paste E2E-N specification including Scenario Steps}

    Server startup:
    1. docker-compose -f docker-compose.test.yml up -d
    2. Wait for health check + frontend readiness
    3. Run Playwright tests (Scenario Steps → test code conversion)
    4. Capture screenshots on failure
    5. docker-compose -f docker-compose.test.yml down after tests

    Playwright guidelines:
    - Use page.goto(), page.click(), page.fill() for user interactions
    - Use page.waitForSelector() for dynamic content
    - Use expect(page).toHaveURL() for navigation assertions
    - Use expect(locator).toHaveText() for content assertions

    Playwright MCP integration (via CDP, when configured in .mcp.json):
    - Use browser_snapshot to capture DOM snapshots and the accessibility tree for structural verification
    - Use browser_take_screenshot to capture runtime screenshots for VRT
    - Use browser_evaluate for JavaScript execution via CDP (performance measurement, etc.)
    - These complement standard Playwright test assertions; they do not replace them.`
})
```

### 6. Quality Verification

Run all IT/E2E tests and verify quality.

```bash
# Run IT tests
cargo test --tests --quiet                 # Rust
npm run test:integration                   # Node.js

# Run E2E tests
docker-compose -f docker-compose.test.yml up -d
npx playwright test                        # Browser E2E
cargo test --tests --quiet                 # Rust API E2E
npm run test:e2e                           # Node.js API E2E
docker-compose -f docker-compose.test.yml down
```

Review the test code with review-worker:
- Whether the tests correctly reflect the specs in test-design.md
- Test independence (no dependency between tests)
- Proper container cleanup
- Proper management of test data

### 7. Report

Save the result to `.spec-workflow/specs/{spec-name}/reviews/e2e-implementation.md`:

```markdown
# E2E Test Implementation Report

## Spec: {spec-name}
## Date: {date}
## Scope: {it|e2e|all}

## IT Tests
| Spec ID | Test File | Status | Notes |
|---------|-----------|--------|-------|
| IT-1 | tests/integration/test_xxx.rs | PASS | |
| IT-2 | tests/integration/test_yyy.rs | PASS | |

## E2E Tests
| Spec ID | Test File | Type | Status | Notes |
|---------|-----------|------|--------|-------|
| E2E-1 | tests/e2e/test_xxx.rs | API | PASS | |
| E2E-2 | e2e/journey.spec.ts | Browser | PASS | |

## Infrastructure
- docker-compose.test.yml: [created|existing]
- Test helpers: [created|existing]
- Playwright config: [created|N/A]

## Coverage
| Spec Type | Total | Implemented | Skipped (not ready) |
|-----------|-------|-------------|---------------------|
| IT | {N} | {M} | {K} |
| E2E | {N} | {M} | {K} |
```

## Relationship with the Main Implementation

- `/spec-implement` and `/spec-e2e-implement` can run **independently**
- The Final E2E Gate of `/spec-implement` (Step 9) automatically runs the tests created by `/spec-e2e-implement` as well
- IT tests can be created incrementally for components that are already implemented, as the main implementation progresses
- E2E tests should run only after all components have been implemented

## Rules

- Feature names use kebab-case
- Implement test code on a container-based foundation (testcontainers / docker-compose.test.yml)
- Tests must be self-contained (no dependency on other tests)
- Always clean up containers
- Implement faithfully to the specs in test-design.md
- No verbal approval required (test implementation has no approval step; verification happens at the Final E2E Gate)
