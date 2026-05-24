# spec-e2e-implement Parallel Sections (archived)

Origin: `.claude-plugin/skills/spec-e2e-implement/SKILL.md`

This Skill previously launched multiple `parallel-worker` agents concurrently to generate IT/E2E test code in parallel. Under `serial-execution-policy`, they MUST be launched one at a time. This file preserves the original pattern for reference.

> Note: The Skill description's phrase "Can run in parallel with /spec-implement" refers to running this Skill in a separate session alongside `/spec-implement`, NOT to in-Skill subagent parallelism. That phrase is preserved unchanged.

---

## (former) Section: 3.3 Test Helpers and Fixtures via parallel-worker (was around L90)

```markdown
Create the following via parallel-worker:

- **Test DB helper**: Centralize testcontainers startup, migration, and seed-data loading
- **Test HTTP client**: Helper for sending requests with authentication tokens
- **Shared fixtures**: Seed data based on the Test Data Requirements in test-design.md
```

## (former) Section: 4. IT Implementation (was around L98-130)

```markdown
For each IT spec in test-design.md, generate test code via parallel-worker.

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:parallel-worker",
  description: "IT: Implement integration test IT-{N}",
  prompt: `Implement integration test based on the following specification.
    ...
  `
})
```
```

(Multiple `Agent` calls were issued in parallel — one per IT-N spec.)

## (former) Section: 5. E2E Implementation (was around L132-191)

```markdown
For each E2E spec in test-design.md, generate test code.

#### 5.1 API E2E (Test Type: API E2E)

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:parallel-worker",
  description: "E2E: Implement API E2E test E2E-{N}",
  prompt: ...
})
```

#### 5.2 Browser E2E (Test Type: Browser E2E / Full-Stack E2E)

```javascript
Agent({
  subagent_type: "spec-workflow-mcp:parallel-worker",
  description: "E2E: Implement browser E2E test E2E-{N}",
  prompt: ...
})
```
```

(Multiple `Agent` calls were issued in parallel — one per E2E-N spec.)
