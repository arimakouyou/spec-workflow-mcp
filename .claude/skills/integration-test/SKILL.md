---
name: integration-test
description: "Parallelizes integration test creation in Agent Teams. Workers (alpha/bravo) implement tests, and Pentagon performs quality review. Use for tasks related to integration test, Axum, Diesel, testcontainers, Agent Teams, and pentagon."
argument-hint: "<domain>[,<domain>...] [--dry-run] [--base-branch <branch>]"
user-invokable: true
---

# integration-test

A skill that uses Agent Teams to create integration tests under `tests/integration/` in parallel.
Workers (alpha/bravo) implement the tests, and Pentagon reviews them at the quality gate.

Tech stack: Axum + Diesel + diesel-async + Valkey (redis-rs) + testcontainers-rs

## Execution Environment Rules

| Rule | Description |
|--------|------|
| **No self-created branches/worktrees** | Do not directly run `git checkout -b` / `git worktree add` |
| **When `--base-branch` is not specified** | Work in the current directory on the current branch |
| **When `--base-branch` is specified** | Create a worktree via the `create-git-worktree` skill |

## Design Policy

| Dependency Type | Policy |
|----------|------|
| **DB (PostgreSQL)** | Use a real PostgreSQL container via testcontainers-rs (no mocking) |
| **External HTTP APIs** | Swap in test doubles via trait-based DI |
| **Valkey / Cache** | testcontainers-rs or trait DI override |

## Team Composition (always 3 roles)

| Role | Agent | Responsibility |
|------|------------|------|
| **Command** (Leader) | Main agent | Commander and strategy planner |
| **Workers** (alpha/bravo) | Sub-agent x 1-2 | Test implementation |
| **Pentagon** (Reviewer) | Sub-agent | Quality review and judgment |

## Arguments

`$ARGS` is specified as a comma-separated list of domain names (e.g., `users,posts`).

| Argument | Required | Description |
|------|:----:|------|
| `$ARGS` | YES | `{domain}[,{domain}...]` (comma-separated) |
| `--dry-run` | - | Print the assignment plan and exit |
| `--base-branch <branch>` | - | Branch to derive the worktree from |
| `--api <method>` | - | Only target a specific HTTP method |

### Usage Examples

```bash
# Parallel execution (2 targets)
/integration-test users,posts

# dry-run (show plan only)
/integration-test users,posts --dry-run

# Single target (alpha 1 + Pentagon 1)
/integration-test sessions

# Specific method only
/integration-test users --api GET
```

---

## Flow Overview

```
/integration-test users,posts
    |
    +-- [P0] Parse & Analyze
    |     +-- Parse arguments (comma-separated)
    |     +-- For each target: trace handler → repository → model
    |     +-- Worker assignment plan
    |     +-- --dry-run: show plan only and exit
    |
    +-- [P1] Setup Team
    |     +-- Pre-check test helpers and shared fixtures
    |     +-- Create whiteboard
    |
    +-- [P2] Launch Agents
    |     +-- Launch Workers (alpha/bravo) x 1-2
    |     +-- Launch Pentagon x 1
    |     +-- Assign initial tasks
    |
    +-- [P3] Monitor & Facilitate
    |     +-- Worker completes -> Request Pentagon review
    |     +-- PASS -> Update whiteboard, assign next task
    |     +-- FAIL -> Send back to Worker (max 3 times)
    |
    +-- [P4] Final Verification
    |     +-- Run cargo test across all test files
    |     +-- rustfmt + clippy
    |
    +-- [P5] Cleanup & Report
          +-- Aggregate results
          +-- Clean up whiteboard
          +-- Output final report
```

---

## Executor Instructions

**You (Command) manage the team following the steps below.**

### P0: Parse & Analyze

1. Split `$ARGS` by comma to build the target list
2. **For each target**:
   - Identify handler: trace routes and handlers from `src/handlers/{domain}.rs`
   - Identify repository: analyze query logic from `src/db/repository/{domain}.rs`
   - Identify model: check Diesel models from `src/models/{domain}.rs`
   - Identify external dependencies: find trait-based dependencies (e.g., external API clients)
3. **Worker assignment**: assign to Workers per test file

   | # of Targets | # of Workers | Assignment Method |
   |:------:|:---------:|---------|
   | 1 | 1 | All to alpha |
   | 2 | 2 | One each to alpha / bravo |
   | 3+ | 2 | Round-robin |

4. **On `--dry-run`**: output the following and exit

```
[dry-run] Assignment plan:
  alpha: {domain_a} -> tests/integration/test_{domain_a}.rs
    - {method} {path}
  bravo: {domain_b} -> tests/integration/test_{domain_b}.rs
    - {method} {path}
  pentagon: quality review
```

### P1: Setup Team

1. Check and update shared test helpers (`tests/integration/helpers/`)
2. Create whiteboard: Write following [whiteboard-template.md](references/whiteboard-template.md)
   - **Always set Key Questions** (1-3 items)

### P2: Launch Agents

Launch Workers and Pentagon as sub-agents. Specify the agent definition under `.claude/agents/` via `subagent_type`.

**Launch Pentagon** (launch first to put it in a review-request waiting state):
```
Agent(
  subagent_type: "integ-test-auditor",
  prompt: "Whiteboard: {whiteboard_path}\nPlease wait for a review request from Command."
)
```

**Launch Workers** (fill in variables from [worker-prompt.md](references/worker-prompt.md)):
```
Agent(
  subagent_type: "integ-test-worker",
  prompt: "Worker name: {worker_name}\nDomain: {domain}\nTest file: tests/integration/test_{domain}.rs\nTarget endpoints:\n{endpoint_list}\nWhiteboard: {whiteboard_path}"
)
```

If there are 2 or more targets, launch alpha/bravo in parallel.

### P3: Monitor & Facilitate

Main loop: monitor until all tasks are complete.

**When a Worker completes**:
1. Copy Worker Findings to the whiteboard
2. Request a review from Pentagon

**When Pentagon returns PASS**:
1. Update the Quality Gate Results on the whiteboard
2. Assign the next unassigned task to a Worker if one exists

**When Pentagon returns FAIL**:
1. Count the number of reviews (per test file)
2. Under 3 times: re-run the Worker with a prompt including the review comments
3. 3rd time: mark as complete with remaining issues noted on the whiteboard

### P4: Final Verification

```bash
# Run across all test files
cargo test --test integration_{domain} -- --nocapture

# Code quality
cargo fmt --all -- --check
cargo clippy --quiet --all-targets -- -D warnings
```

If verification fails, Command fixes it directly.

### P5: Cleanup & Report

1. Move the whiteboard to `.claude/_docs/deleted/`
2. Output the final report:

```
integration-test parallel implementation complete

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Targets: {targets}

Generated files:
  {file_list}

Test results:
  {test_summary}

Quality gate:
  {quality_gate_results}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## References

| Document | Purpose |
|------------|------|
| [quality-gate.md](references/quality-gate.md) | Pentagon's judgment criteria |
| [test-case-design.md](references/test-case-design.md) | 5 test case classifications |
| [test-patterns.md](references/test-patterns.md) | Test implementation patterns |
| [fixture-catalog.md](references/fixture-catalog.md) | Shared helpers and fixture catalog |
| [external-api-mock.md](references/external-api-mock.md) | External API mock patterns |
| [worker-prompt.md](references/worker-prompt.md) | Worker prompt template |
| [auditor-prompt.md](references/auditor-prompt.md) | Pentagon prompt template |
| [whiteboard-template.md](references/whiteboard-template.md) | Whiteboard template |
| [parallel-execution.md](references/parallel-execution.md) | Parallel execution flow details |
