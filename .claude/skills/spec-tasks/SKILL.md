---
name: spec-tasks
description: "Phase 3 of spec-driven development: break an approved design into atomic implementation tasks. Use this skill after design is approved, when the user wants to create tasks, plan implementation steps, or break down work into actionable items. Triggers on: 'create tasks', 'break down into tasks', 'implementation plan', 'task breakdown for X', or any request to create a tasks.md document."
---

# Spec Tasks (Phase 3)

Break the approved design into atomic, implementable tasks. This phase converts architecture decisions into a concrete action plan.

## Prerequisites

Design must be approved and cleaned up (Phases 1-2 complete). If not, use `/spec-design` first.

## Inputs

The same **spec name** used in previous phases (kebab-case, e.g., `user-authentication`).

## Process

### 1. Load the Template

Check for a custom template first, then fall back to the default:

1. `.spec-workflow/user-templates/tasks-template.md` (custom)
2. `.spec-workflow/templates/tasks-template.md` (default)

### 2. Read Approved Documents

- `.spec-workflow/specs/{spec-name}/requirements.md`
- `.spec-workflow/specs/{spec-name}/design.md`

### 3. Create Tasks

Convert the design into atomic tasks. Each task should touch 1-3 files and be independently implementable. Include:

- File paths that will be created or modified
- Requirement references (which requirements the task implements)
- Logical ordering (dependencies between tasks)

### 3.5 Phase-Based Organization

Group tasks into phases using `## Phase N: Title` headings. Each phase is a **vertical slice** — a testable, committable increment that delivers end-to-end value.

- 1 phase = 2-5 implementation tasks + 1 review task
- Each phase ends with a `_PhaseReview: true_` task for review and commit
- Phases are ordered by dependency (core → API → UI → integration)

### 3.6 TDD Task Design Rules

- **No standalone test tasks.** TDD handles testing automatically in each task's RED phase.
- **Each task must be independently testable** — it must produce observable behavior that can be verified.
- **Interface-only tasks** should be merged with the first task that uses the interface.
- **`_TestFocus` field** describes what the RED phase should test (e.g., "CRUD success/failure, validation boundaries").

### 4. Generate _Prompt Fields

This is critical for implementation quality. Each task needs a `_Prompt` field with structured AI guidance, plus a `_TestFocus` field for TDD:

```markdown
- [ ] 1.1 Create core interfaces and model
  - File: src/types/feature.ts, src/models/FeatureModel.ts
  - Define TypeScript interfaces and implement model with validation/CRUD
  - _Leverage: src/types/base.ts, src/models/BaseModel.ts_
  - _Requirements: 1.1, 2.1_
  - _TestFocus: Interface contract validation, CRUD success/failure, validation boundaries_
  - _Prompt: Role: TypeScript Developer | Task: Create interfaces and model following requirements 1.1, 2.1 | Restrictions: Do not modify base interfaces | Success: All interfaces compile, model validation works_

- [ ] 1.2 Review and commit Phase 1
  - _PhaseReview: true_
  - _Prompt: Role: Code reviewer | Task: Review all Phase 1 changes, run tests, commit | Success: All tests pass, committed_
```

Also include:
- `_Leverage`: Existing files/utilities to reuse (prevents reinventing the wheel)
- `_Requirements`: Which requirements this task fulfills (traceability)
- `_TestFocus`: Key behaviors to test in the RED phase (guides test writing)
- Instructions about marking task status in tasks.md and logging implementation with `log-implementation` tool

### 5. Create the Document

Write the tasks document to:
```
.spec-workflow/specs/{spec-name}/tasks.md
```

Task status markers:
- `- [ ]` = Pending
- `- [-]` = In progress
- `- [x]` = Completed

### 6. Self-Review via Subagent (before approval)

Spawn a subagent to review and fix the document before requesting approval:

```
Agent({
  subagent_type: "general-purpose",
  description: "Review tasks spec",
  prompt: "You are a spec document reviewer. Review and fix the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/tasks.md

    Document type: tasks
    Template: {project-path}/.spec-workflow/templates/tasks-template.md
    Requirements: {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    Design: {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Checks:
    1. TEMPLATE: Every task has - [ ] marker, file path(s), _Leverage, _Requirements, _Prompt fields
    2. _Prompt has: Role, Task, Restrictions, Success. Starts with 'Implement the task for spec {spec-name}...'
    3. CROSS-REFERENCE: Read requirements.md and design.md —
       every requirement must have at least one implementing task,
       every design component must have at least one creating task,
       _Requirements IDs must match actual requirement IDs
    4. Tasks are atomic (1-3 files), in logical dependency order
    5. No placeholder text, descriptions specific enough for AI implementation
    6. PHASE STRUCTURE: Tasks are grouped under ## Phase headings with vertical slices
    7. TDD: No standalone test tasks (e.g., 'write tests', 'create unit tests')
    8. Every non-PhaseReview task has a _TestFocus field
    9. Each phase ends with a _PhaseReview: true_ task

    Fix all issues directly in the file. Return a summary of checks and fixes."
})
```

Wait for the subagent to complete, then proceed to approval.

### 7. Approval Workflow

Same strict process — verbal approval is never accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only
2. **Poll status**: `approvals` tool, `action: 'status'`, keep polling
3. **Handle result**:
   - **needs-revision**: Update tasks using reviewer comments, spawn the review subagent again, submit NEW approval
   - **approved**: Move to cleanup
4. **Cleanup**: `approvals` tool, `action: 'delete'` — must succeed
   - If delete fails: STOP, return to polling
5. **Spec complete**: After successful cleanup, tell the user: "Spec complete. Ready to implement?" Then use `/spec-implement` to begin.

## Rules

- Feature names use kebab-case
- One spec at a time
- Tasks should be atomic (1-3 files each)
- Every task needs a `_Prompt` field with structured guidance
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
