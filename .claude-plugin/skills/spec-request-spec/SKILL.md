---
name: spec-request-spec
description: "Phase 0 of spec-driven development: create a request specification document that defines use cases, technology stack, and execution environment. Use this skill when starting a new spec, as the very first phase before requirements definition. Triggers on: 'create request spec', 'new spec for X', 'start spec workflow', 'define use cases', 'select tech stack', or any request to create a request-spec.md document."
---

# Spec Request Spec (Phase 0)

Create a request specification document that defines **use cases**, **technology stack**, and **execution environment** before diving into detailed requirements. This is the first phase of the spec-driven development workflow (Request Spec -> Requirements -> Design -> Test Design -> Tasks -> Implementation).

## Inputs

You need a **spec name** in kebab-case (e.g., `user-authentication`, `data-export`). Ask the user if they haven't provided one.

## Process

### 1. Gather Context

Read steering documents if they exist — these contain project-level guidance that should inform your request specification:

```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

If `tech.md` exists, the technology stack section of the request spec should only describe **feature-specific additions** — do not duplicate project-level base technologies.

### 2. Load the Template

Check for a custom template first. If none exists, fall back to the default:

1. `.spec-workflow/user-templates/request-spec-template.md` (custom)
2. `.spec-workflow/templates/request-spec-template.md` (default)

Follow the template structure exactly for consistency across the project.

### 3. Research and Write

- Discuss with the user to confirm basic use cases for the feature
- Identify the technology stack needed (feature-specific additions only if tech.md exists)
- Confirm the execution environment and its constraints
- Define clear scope boundaries (what's in scope and what's explicitly out of scope)
- If web search is available, research relevant technology options and best practices

### 4. Create the Document

Write the file to:
```
.spec-workflow/specs/{spec-name}/request-spec.md
```

### 5. Self-Review via Subagent (before approval)

Validate the document in **2 stages** before requesting approval.

#### Step A: fix (automated mechanical corrections)

Auto-fix placeholders, formatting, and typos. Do not add or change content:

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Fix request-spec (auto-fix)",
  prompt: "You are a spec document reviewer. Auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/request-spec.md

    Document type: request-spec

    Auto-fix targets (you may directly modify the file):
    - Remove placeholder text ([describe...], TODO, TBD)
    - Fix markdown formatting (table alignment, heading levels, etc.)
    - Fix obvious typos

    Not auto-fix targets (report as issues only):
    - Adding or removing sections
    - Adding or changing content (use cases, technology selections, etc.)

    Mode: fix — Return a structured report (auto-fixed items + remaining issues)."
})
```

#### Step B: check (content validation)

After fix is complete, detect content issues. Do not modify the file:

```
Agent({
  subagent_type: "general-purpose",
  model: "opus",
  description: "Review request-spec (check)",
  prompt: "You are a spec document reviewer. Review the document (do NOT modify the file) at:
    {project-path}/.spec-workflow/specs/{spec-name}/request-spec.md

    Document type: request-spec
    Template: {project-path}/.spec-workflow/templates/request-spec-template.md

    Checks:
    1. TEMPLATE: Every section from the template must exist with real content (no [describe...] or TODO)
    2. USE CASES: At least one use case with Actor, Purpose, Basic Flow, and Post-conditions defined
    3. TECH STACK: Technology selections table is filled with concrete entries (no placeholders)
    4. EXECUTION ENVIRONMENT: Target environment and constraints are specified
    5. SCOPE: Both 'In Scope' and 'Out of Scope' sections have concrete entries

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 6. Approval Workflow

This is a strict, automated process. Verbal approval from the user is never accepted — only dashboard or VS Code extension approval counts.

1. **Request approval**: Use the `approvals` MCP tool with `action: 'request'`. Pass `filePath` only — never include content in the request. Save the returned `approvalId`.

2. **Automatic polling**: Start automatic status checking:
   ```
   /loop 1m /check-approval <approvalId>
   ```
   The loop will automatically check approval status every minute and handle the result:
   - **pending**: Continue polling (no action needed)
   - **approved**: Cleanup is performed automatically, loop stops
   - **needs-revision**: Loop stops, reviewer comments are displayed

3. **Handle needs-revision** (if loop stopped with revision request):
   - Read the reviewer's comments, update the document accordingly
   - Spawn the review subagent again (Step A + B)
   - Submit a NEW approval request and start a new `/loop 1m /check-approval <newApprovalId>`

4. **Next phase**: After approval and cleanup succeed, **automatically** proceed to Phase 1 (Requirements).
   Load the `/spec-requirements` skill and begin immediately — do not wait for user input.

## Rules

- Feature names use kebab-case (e.g., `user-authentication`)
- One spec at a time
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before moving to requirements
- If steering/tech.md exists, only describe feature-specific technology additions
