---
name: integration-test
description: "Creates integration tests in Agent Teams. A single Worker (alpha) implements tests sequentially, and Pentagon performs quality review. Use for tasks related to integration test, Axum, Diesel, testcontainers, Agent Teams, and pentagon."
argument-hint: "<domain>[,<domain>...] [--dry-run] [--base-branch <branch>]"
user-invokable: true
---

# integration-test

A skill that uses Agent Teams to create integration tests under `tests/integration/`.
A single Worker (alpha) implements the tests sequentially, and Pentagon reviews them at the quality gate. Concurrent Worker launches are prohibited per `rules/serial-execution-policy.md`.

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
| **Command** (Leader) | Main agent | Commander, strategy planner, and shared-context holder (in-session) |
| **Worker** (alpha) | Sub-agent x 1 | Test implementation (handles all targets sequentially) |
| **Pentagon** (Reviewer) | Sub-agent (re-launched per review request) | Quality review and judgment |

**Communication model**: Workers and Pentagon communicate with Command via (i) launch-time prompt and (ii) final completion report (the agent's last response). Command holds the shared context in its own session and re-injects relevant parts into each sub-agent prompt.

## Arguments

`$ARGS` is specified as a comma-separated list of domain names (e.g., `users,posts`).

| Argument | Required | Description |
|------|:----:|------|
| `$ARGS` | YES | `{domain}[,{domain}...]` (comma-separated) |
| `--dry-run` | - | Print the assignment plan and exit |
| `--base-branch <branch>` | - | Branch to derive the worktree from |
| `--api <method>` | - | Only target a specific HTTP method |
| `--spec <name>` | - | Spec name to scope the job log under `.spec-workflow/specs/{name}/integ-test-runs/`. Omit to log at `.spec-workflow/integ-test-runs/` |

### Usage Examples

```bash
# Multiple targets (handled sequentially by alpha)
/integration-test users,posts

# dry-run (show plan only)
/integration-test users,posts --dry-run

# Single target
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
    |     +-- For each target: trace handler -> repository -> model
    |     +-- --dry-run: show plan only and exit
    |
    +-- [P1] Setup
    |     +-- Pre-check shared test helpers
    |     +-- Build shared context in Command's session
    |       (Goal, Key Questions, Shared Resources, per-domain analysis)
    |
    +-- [P2] Per-Domain Loop (Implement + Review)
    |     For each domain (one at a time):
    |     +-- Launch alpha (Worker) with full per-domain prompt
    |     +-- Worker returns Findings + self-checked tests in completion report
    |     +-- Launch Pentagon fresh with the Worker's Findings in prompt
    |     +-- PASS  -> next domain
    |     +-- FAIL (cycle < 3) -> re-launch alpha with rework instructions
    |     +-- FAIL (cycle = 3) -> record as complete-with-issues, next domain
    |
    +-- [P3] Final Verification
    |     +-- Run cargo test across all generated test files
    |     +-- rustfmt + clippy
    |
    +-- [P4] Report
          +-- Aggregate results from Command's session state
          +-- Output final report
```

---

## Executor Instructions

**You (Command) manage the team following the steps below.** All shared state lives in your own session context.

### P0: Parse & Analyze

1. Split `$ARGS` by comma to build the target list
2. **For each target**:
   - Identify handler: trace routes and handlers from `src/handlers/{domain}.rs`
   - Identify repository: analyze query logic from `src/db/repository/{domain}.rs`
   - Identify model: check Diesel models from `src/models/{domain}.rs`
   - Identify external dependencies: find trait-based dependencies (e.g., external API clients)
3. **Worker assignment**: launch only alpha (a single Worker) and have it handle all targets sequentially. Concurrent Worker launches are prohibited (`rules/serial-execution-policy.md`).

4. **On `--dry-run`**: output the following and exit

```
[dry-run] Assignment plan:
  alpha: handles all targets sequentially
    - {domain_a} -> tests/integration/test_{domain_a}.rs
        - {method} {path}
    - {domain_b} -> tests/integration/test_{domain_b}.rs
        - {method} {path}
  pentagon: re-launched per review request
```

### P1: Setup

1. Check and update shared test helpers (`tests/integration/helpers/`)
2. Build the **shared context** in your own session memory. The shared context contains:
   - **Goal**: one-line description of what the team is producing
   - **Key Questions** (1-3 items): questions whose answers must be consistent across domains (e.g., "Is the authentication-error response shape shared?")
   - **Shared Resources**: file paths for common helpers (TestContext, db fixtures, mock builders)
   - **Per-domain Analysis Summary**: endpoint list, repository methods, external dependencies, derived from P0

   Keep this in session memory so that each sub-agent launch can include the relevant slice in its prompt.

3. **Create the job log** per `rules/task-log-format.md`:
   - If a spec context is available (`--spec <name>` or detected from cwd): path is `.spec-workflow/specs/{spec-name}/integ-test-runs/{timestamp}.log.md`
   - If no spec context: path is `.spec-workflow/integ-test-runs/{timestamp}.log.md`
   - `{timestamp}` is ISO 8601 UTC with separators stripped (e.g., `20260520T143200`)
   - Create the parent directory and write the header + `## Metadata` (spec, targets, args, created, log-id) + empty `## Events` section
   - Append a `job-start` event with `targets={comma-separated domains}`, `goal`, `key_questions` details

### P2: Per-Domain Loop (Implement + Review)

Process the target list one domain at a time. For each domain, Command also appends events to the job log at each transition (`rules/task-log-format.md` TL4 integration-test events). The Worker and Pentagon do not touch the log themselves — Command extracts info from their final responses and writes the entries.

#### P2.1: Launch alpha (Worker)

Before launch, append a `domain-analysis` event with `domain={domain}` and the endpoint / external_deps details. Then append a `worker-launch` event with `domain={domain}` cycle={N}.

Launch alpha with a single, self-contained prompt. Substitute the variables from your shared context. See [worker-prompt.md](references/worker-prompt.md) for the prompt template.

```
Agent(
  subagent_type: "spec-workflow-mcp:integ-test-worker",
  prompt: "Language: rust
Worker name: alpha
Domain: {domain}
Test file: tests/integration/test_{domain}.rs
Target endpoints:
{endpoint_list}

## Shared Context (from Command)
- Goal: {goal}
- Key Questions:
{key_questions}
- Shared Resources:
{shared_resources}
- Domain Analysis:
{per_domain_analysis}

## Instructions
Implement the integration tests per the procedure in your agent definition.
Return your Findings and quality self-check results in your completion report."
)
```

#### P2.2: Worker returns

The Worker's completion report includes Findings (free text), test counts per category, and self-check results (rustfmt / clippy / cargo test). Extract these into your session state for this domain.

Append a `worker-return` event with `domain={domain}` `cycle={N}` `result={PASS|FAIL based on self-checks}` and `test_counts`, `findings_excerpt` (one-line) details.

#### P2.3: Launch Pentagon fresh

Append a `pentagon-launch` event with `domain={domain}` `cycle={N}`.

Launch Pentagon with the Worker's Findings embedded in the prompt. Pentagon is re-launched per review request — it does NOT persist across domains. See [auditor-prompt.md](references/auditor-prompt.md) for the prompt template.

```
Agent(
  subagent_type: "spec-workflow-mcp:integ-test-auditor",
  prompt: "Language: rust
Test file: tests/integration/test_{domain}.rs

## Target API
{endpoint_list}

## Worker Findings (from alpha)
{worker_findings_block}

## Instructions
Apply the quality gate review per your agent definition and return PASS / FAIL with details in your completion report."
)
```

#### P2.4: Process Pentagon result

Append a `pentagon-return` event with `domain={domain}` `cycle={N}` `verdict={PASS|FAIL}` and `issues_excerpt` detail (one-line summary when FAIL).

| Pentagon verdict | Action |
|---|---|
| **PASS** | Append `domain-done domain={domain} status=PASS cycles={N}`, move to the next domain |
| **FAIL** (cycle < 3) | Re-launch alpha with the same prompt **plus** the Pentagon Issues block. Increment the cycle counter for this domain. |
| **FAIL** (cycle = 3) | Append `domain-done domain={domain} status=done-with-issues cycles=3`, attach Pentagon's remaining Issues to the final report, move to the next domain |

When re-launching alpha for rework, prepend the Pentagon Issues block:

```
## Pentagon Review Feedback (cycle {N})
{issues_block}

Apply the fixes per the issues above, then re-run your quality self-check and return an updated completion report.
```

### P3: Final Verification

After all domains complete:

```bash
# Run all generated integration tests
cargo test --test test_{domain_a} -- --nocapture
cargo test --test test_{domain_b} -- --nocapture

# Code quality
cargo fmt --all -- --check
cargo clippy --quiet --all-targets -- -D warnings
```

If verification fails, Command fixes it directly (do not launch a new Worker for harness-level fixes).

### P4: Report

Append a `job-end` event with `targets={domains}` and `status={success|partial}` (partial = at least one `done-with-issues`).

Aggregate the per-domain state from your session and output:

```
integration-test implementation complete

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Targets: {targets}

Generated files:
  {file_list}

Test results:
  {test_summary}

Quality gate:
  - {domain_a}: PASS / done-with-issues (cycles: {N})
  - {domain_b}: PASS / done-with-issues (cycles: {N})

Remaining issues (if any):
  {remaining_issues_block}
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
