# Parallel Execution Flow Details

Detailed phases of parallel test creation using Agent Teams.

## Team Structure

| Role | Count | Responsibility |
|------|:-----:|----------------|
| Command (orchestrator) | 1 | Analysis, assignment, monitoring, final verification |
| Workers (test implementation) | 1-2 | Test file creation |
| Pentagon (quality review) | 1 | Quality gate decisions |

## Phase Details

### P0: Parse & Analyze

```
Input: /integration-test users,posts
  ↓
Split by comma → ["users", "posts"]
  ↓
Analyze each target:
  users → src/handlers/users.rs → src/db/repository/users.rs → src/models/user.rs
  posts → src/handlers/posts.rs → src/db/repository/posts.rs → src/models/post.rs
  ↓
Worker assignment:
  alpha → users (test_users.rs)
  bravo → posts (test_posts.rs)
```

### P1: Setup Team

1. Verify common helpers
   - Whether `tests/integration/helpers/` exists
   - Whether TestContext works for the target domain
   - Command adds new fixtures if required

2. Create the whiteboard
   - Create following `whiteboard-template.md`
   - Set 1-3 Key Questions

### P2: Launch Agents

Launch Workers and Pentagon as subagents using the agent definitions in `.claude/agents/`.

**Launch order:**
1. Pentagon (`subagent_type: "spec-workflow-mcp:integ-test-auditor"` with the `Language: rust` argument) — waits for review requests after launch
2. Workers (`subagent_type: "spec-workflow-mcp:integ-test-worker"` with the `Language: rust` argument) — alpha and bravo launched in parallel

```
# Launch Pentagon
Agent(subagent_type: "spec-workflow-mcp:integ-test-auditor", prompt: "Language: rust\nWhiteboard: {whiteboard_path}\nWaiting for review requests")

# Launch Workers (parallel)
Agent(subagent_type: "spec-workflow-mcp:integ-test-worker", prompt: "Language: rust\nWorker name: alpha\nDomain: {domain_a}\n...")
Agent(subagent_type: "spec-workflow-mcp:integ-test-worker", prompt: "Language: rust\nWorker name: bravo\nDomain: {domain_b}\n...")
```

### P3: Monitor & Facilitate

```
while open tasks remain:
  ├─ Detect Worker completion
  │   ├─ Transcribe Findings to the whiteboard
  │   ├─ Request a review from Pentagon
  │   └─ Wait for the Pentagon result
  │       ├─ PASS → Update Quality Gate; assign next task if any
  │       └─ FAIL → Check the review count
  │           ├─ < 3 → Send back to the Worker
  │           └─ = 3 → Complete with remaining issues recorded
  └─ All tasks complete → proceed to P4
```

**Worker re-run on send-back:**
- Append Pentagon's findings to the original prompt
- Make the "fix locations" and "reasons for fix" explicit

### P4: Final Verification

```bash
# Run all tests
cargo test --test integration_users --test integration_posts -- --nocapture

# Code quality checks
rustfmt tests/integration/test_users.rs tests/integration/test_posts.rs
cargo clippy --tests --quiet
```

On failure:
- Compile errors → Command fixes directly
- Test failure → identify the cause and have Command fix or re-request the Worker
- clippy warnings → Command fixes

### P5: Cleanup & Report

1. Move the whiteboard to `.claude/_docs/deleted/`
2. Print the final report

```
integration-test parallel implementation complete

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Targets: users, posts

Generated files:
  tests/integration/test_users.rs (12 tests)
  tests/integration/test_posts.rs (10 tests)

Test results:
  22 tests passed, 0 failed

Quality gate:
  test_users.rs: PASS (cycle 1)
  test_posts.rs: PASS (cycle 2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Timeouts and Aborts

| Situation | Remedy |
|-----------|--------|
| Worker silent for 10+ minutes | Command checks state and restarts if needed |
| Pentagon silent for 5+ minutes | Command checks state and restarts if needed |
| Quality still insufficient after 3 send-backs | Complete with remaining issues recorded; note in the report |
