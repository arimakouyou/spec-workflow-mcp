# Whiteboard Template

Created by Command during P1.
Location: `.claude/_docs/plans/integ-test-dotnet-wb-{timestamp}.md`

---

```markdown
# Integration Test (.NET) Whiteboard

## Goal
{Create integration tests for the target domain(s)}

## Team Structure
| Role | Name | Assignment |
|------|------|-----------|
| Command | main | Commander |
| Worker alpha | agent-alpha | {domain_a} |
| Worker bravo | agent-bravo | {domain_b} |
| Pentagon | agent-pentagon | Quality review |

## How Our Work Connects
- alpha and bravo work on independent test classes
- Shared fixtures (IntegrationTestFixture, DatabaseHelper) are prepared by Command in advance
- Pentagon audits each Worker's deliverables at the quality gate

## Key Questions
1. {Question to share across Workers — e.g., Is the error response format consistent (ProblemDetails)?}
2. {e.g., Are there shared seed data patterns that can be extracted?}

## Shared Resources
- Fixtures/IntegrationTestFixture.cs — WebApplicationFactory + Testcontainers
- Fixtures/IntegrationTestCollection.cs — xUnit collection definition
- Fixtures/DatabaseHelper.cs — Seed data and DB verification helpers
- GlobalUsings.cs — Common using statements

## File Assignment
| Worker | File | Status |
|--------|------|--------|
| alpha | {Domain}EndpointTests.cs | pending |
| bravo | {Domain}EndpointTests.cs | pending |

## Analysis Summary
### {domain_a}
- Endpoints: {endpoint_list}
- External deps: {deps}

### {domain_b}
- Endpoints: {endpoint_list}
- External deps: {deps}

## Alpha Findings
(Worker alpha findings — transcribed by Command)

## Bravo Findings
(Worker bravo findings — transcribed by Command)

## Pentagon Reviews
| File | Cycle | Result | Notes |
|------|:-----:|:------:|-------|

## Cross-Cutting Observations
(Observations to share across the entire team)

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
| Fill Analysis Summary | Command | After P0 completes |
| Transcribe Worker Findings | Command | When Worker completes |
| Fill Pentagon Reviews | Command | When Pentagon review completes |
| Update Quality Gate Results | Command | When Pentagon returns PASS |
| Delete (move to `.claude/_docs/deleted/`) | Command | P5 |
