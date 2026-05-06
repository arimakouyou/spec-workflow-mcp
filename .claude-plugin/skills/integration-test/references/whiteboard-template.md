# Whiteboard Template

The whiteboard Command creates in P1.
Location: `.claude/_docs/plans/integ-test-wb-{timestamp}.md`

---

```markdown
# Integration Test Whiteboard

## Goal
{Create integration tests for the target domain}

## Team Structure
| Role | Name | Assignment |
|------|------|-----------|
| Command | main | Orchestrator |
| Worker alpha | agent-alpha | {domain_a} |
| Worker bravo | agent-bravo | {domain_b} |
| Pentagon | agent-pentagon | Quality review |

## How Our Work Connects
- alpha and bravo own independent test files
- Common helpers (such as TestContext) are prepared by Command beforehand
- Pentagon audits each Worker's deliverable against the quality gate

## Key Questions
1. {A question Workers should share — e.g., is the authentication-error response shape shared?}
2. {e.g., which parts of the test data seed pattern can be unified?}

## Shared Resources
- tests/integration/helpers/mod.rs — common helpers
- tests/integration/helpers/app.rs — test Axum app construction
- tests/integration/helpers/db.rs — testcontainers setup

## File Assignment
| Worker | File | Status |
|--------|------|--------|
| alpha | tests/integration/test_{domain_a}.rs | pending |
| bravo | tests/integration/test_{domain_b}.rs | pending |

## Analysis Summary
### {domain_a}
- Endpoints: {endpoint_list}
- External deps: {deps}

### {domain_b}
- Endpoints: {endpoint_list}
- External deps: {deps}

## Alpha Findings
(Worker alpha fills in — Command transcribes)

## Bravo Findings
(Worker bravo fills in — Command transcribes)

## Pentagon Reviews
| File | Cycle | Result | Notes |
|------|:-----:|:------:|-------|

## Cross-Cutting Observations
(Findings to be shared with the entire team)

## Quality Gate Results
| File | Status | Reviewer |
|------|:------:|----------|
```

---

## Read/Write Rules

| Operation | Who | When |
|-----------|-----|------|
| Create | Command | P1 |
| Set Key Questions | Command | P1 |
| Fill in Analysis Summary | Command | At P0 completion |
| Transcribe Worker Findings | Command | When the Worker completes |
| Fill in Pentagon Reviews | Command | When Pentagon review completes |
| Update Quality Gate Results | Command | On Pentagon PASS |
| Delete (move to `.claude/_docs/deleted/`) | Command | P5 |
