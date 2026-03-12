---
name: spec-requirements
description: "Phase 1 of spec-driven development: create a requirements document for a feature. Use this skill when the user wants to start a new spec, define requirements, or begin the spec workflow for a feature. Triggers on: 'create requirements', 'new spec for X', 'start spec workflow', 'define what to build', or any request to create a requirements.md document."
---

# Spec Requirements (Phase 1)

Create a requirements document that defines **what** to build based on user needs. This is the first phase of the spec-driven development workflow (Requirements -> Design -> Tasks -> Implementation).

## Inputs

You need a **spec name** in kebab-case (e.g., `user-authentication`, `data-export`). Ask the user if they haven't provided one.

## Process

### 1. Gather Context

Read steering documents if they exist — these contain project-level guidance that should inform your requirements:

```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

### 2. Load the Template

Check for a custom template first. If none exists, fall back to the default:

1. `.spec-workflow/user-templates/requirements-template.md` (custom)
2. `.spec-workflow/templates/requirements-template.md` (default)

Follow the template structure exactly for consistency across the project.

### 3. Research and Write

- If web search is available, research current market expectations and best practices
- Generate requirements as user stories using EARS criteria (Event, Action, Response, State)
- Cover all functional and non-functional requirements
- Be comprehensive — the design phase depends on complete requirements

### 4. Create the Document

Write the file to:
```
.spec-workflow/specs/{spec-name}/requirements.md
```

### 5. Self-Review via Subagent (before approval)

Spawn a subagent to review and fix the document before requesting approval. This keeps review details out of your main context:

```
Agent({
  subagent_type: "general-purpose",
  description: "Review requirements spec",
  prompt: "You are a spec document reviewer. Review and fix the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Document type: requirements
    Template: {project-path}/.spec-workflow/templates/requirements-template.md

    Checks:
    1. TEMPLATE: Every section from the template must exist with real content (no [describe...] or TODO)
    2. Every requirement needs User Story ('As a [role]...') and EARS Acceptance Criteria (WHEN/IF...THEN...SHALL)
    3. Non-Functional Requirements must cover: Code Architecture, Performance, Security, Reliability, Usability
    4. Requirements should be uniquely identified (REQ-1, REQ-2, etc.)

    Fix all issues directly in the file. Return a summary of checks and fixes."
})
```

Wait for the subagent to complete, then proceed to approval.

### 6. Approval Workflow

This is a strict, automated process. Verbal approval from the user is never accepted — only dashboard or VS Code extension approval counts.

1. **Request approval**: Use the `approvals` MCP tool with `action: 'request'`. Pass `filePath` only — never include content in the request.

2. **Poll for status**: Use `approvals` with `action: 'status'`. Keep polling until the status changes from `pending`.

3. **Handle the result**:
   - **needs-revision**: Read the reviewer's comments, update the document accordingly, spawn the review subagent again, then submit a NEW approval request. Do not proceed to design.
   - **approved**: Move to cleanup.

4. **Cleanup**: Use `approvals` with `action: 'delete'`. This must succeed before proceeding.
   - If delete fails: STOP. Return to polling. Never proceed without successful cleanup.

5. **Next phase**: Only after cleanup succeeds, proceed to Phase 2 (Design). Use the `/spec-design` skill.

## Rules

- Feature names use kebab-case (e.g., `user-authentication`)
- One spec at a time
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before moving to design
