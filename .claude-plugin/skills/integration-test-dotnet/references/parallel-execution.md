# Parallel Execution Flow Details

Full phase details for parallel test creation using Agent Teams.

## Team Composition

| Role | Count | Responsibility |
|------|:-----:|------|
| Command (Commander) | 1 | Analysis, assignment, monitoring, final verification |
| Workers (Test Implementation) | 1-2 | Test class creation |
| Pentagon (Quality Review) | 1 | Quality gate judgment |

## Phase Details

### P0: Parse & Analyze

```
Input: /integration-test-dotnet users,orders
  |
Split by comma -> ["users", "orders"]
  |
Analyze each target:
  users -> Controllers/UsersController.cs -> Services/UserService.cs -> Entities/User.cs
  orders -> Controllers/OrdersController.cs -> Services/OrderService.cs -> Entities/Order.cs
  |
Worker assignment:
  alpha -> users (UserEndpointTests.cs)
  bravo -> orders (OrderEndpointTests.cs)
```

### P1: Setup Team

1. Verify shared fixtures
   - Does `Fixtures/` directory exist in the test project?
   - Does `IntegrationTestFixture` work for the target domains?
   - Add new fixtures if needed (Command adds them directly)

2. Create whiteboard
   - Create following `whiteboard-template.md`
   - Set 1-3 Key Questions

### P2: Launch Agents

Launch Workers and Pentagon as sub-agents using agent definitions under `.claude/agents/`.

**Launch order:**
1. Pentagon (`subagent_type: "spec-workflow-mcp:integ-test-dotnet-auditor"`) — waits for review requests after launch
2. Workers (`subagent_type: "spec-workflow-mcp:integ-test-dotnet-worker"`) — launch alpha and bravo in parallel

```
# Launch Pentagon
Agent(subagent_type: "spec-workflow-mcp:integ-test-dotnet-auditor", prompt: "Whiteboard: {whiteboard_path}\nWait for review request.")

# Launch Workers (parallel)
Agent(subagent_type: "spec-workflow-mcp:integ-test-dotnet-worker", prompt: "Worker name: alpha\nDomain: {domain_a}\n...")
Agent(subagent_type: "spec-workflow-mcp:integ-test-dotnet-worker", prompt: "Worker name: bravo\nDomain: {domain_b}\n...")
```

### P3: Monitor & Facilitate

```
while incomplete tasks exist:
  +-- Detect Worker completion
  |   +-- Transcribe Findings to whiteboard
  |   +-- Request Pentagon review
  |   +-- Wait for Pentagon result
  |       +-- PASS -> Update Quality Gate, assign next task if available
  |       +-- FAIL -> Check review count
  |           +-- < 3 -> Return to Worker with fix instructions
  |           +-- = 3 -> Complete with remaining issues noted
  +-- All tasks complete -> Proceed to P4
```

**Worker re-run on rejection:**
- Append Pentagon's specific fix instructions to the original prompt
- Clearly state "what to fix" and "why"

### P4: Final Verification

```bash
# Run all integration tests
dotnet test tests/<ProjectName>.IntegrationTests/ --verbosity normal

# Code quality
dotnet format tests/<ProjectName>.IntegrationTests/ --verify-no-changes
dotnet build tests/<ProjectName>.IntegrationTests/ --warnaserror
```

On failure:
- Compilation error -> Command fixes directly
- Test failure -> Identify cause; Command fixes or re-assigns to Worker
- Format violations -> Command fixes directly

### P5: Cleanup & Report

1. Move whiteboard to `.claude/_docs/deleted/`
2. Output final report

```
integration-test-dotnet parallel implementation complete

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Targets: users, orders

Generated files:
  UserEndpointTests.cs (12 tests)
  OrderEndpointTests.cs (10 tests)

Test results:
  22 tests passed, 0 failed

Quality gate:
  UserEndpointTests.cs: PASS (cycle 1)
  OrderEndpointTests.cs: PASS (cycle 2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Timeouts and Interruptions

| Situation | Resolution |
|-----------|------------|
| Worker unresponsive for over 10 minutes | Command checks status, restarts if needed |
| Pentagon unresponsive for over 5 minutes | Command checks status, restarts if needed |
| Quality insufficient after 3 rejections | Complete with remaining issues noted in report |
