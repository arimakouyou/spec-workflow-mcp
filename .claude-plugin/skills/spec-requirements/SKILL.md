---
name: spec-requirements
description: "Phase 1 of spec-driven development: create a requirements document for a feature. Use this skill when the user wants to start a new spec, define requirements, or begin the spec workflow for a feature. Triggers on: 'create requirements', 'new spec for X', 'start spec workflow', 'define what to build', or any request to create a requirements.md document."
---

# Spec Requirements (Phase 1)

Create a requirements document that defines **what** to build based on user needs. This is the second phase of the spec-driven development workflow (Request Spec -> Requirements -> Design -> Test Design -> Tasks -> Implementation).

## Prerequisites Check (MANDATORY — DO NOT SKIP)

Before doing anything else, verify the prerequisite file exists:

1. Check `.spec-workflow/specs/{spec-name}/request-spec.md` exists

**Legacy workflow exception**: If `request-spec.md` does not exist but `requirements.md` already exists in the spec directory, this is a legacy spec created before Phase 0 was introduced. In this case, skip the request-spec prerequisite and proceed normally.

If missing AND no downstream documents exist — **STOP immediately.** Tell the user: "Cannot start requirements because request-spec.md does not exist. Please run `/spec-request-spec` first." Then exit this skill.

---

Request specification must be approved and cleaned up (Phase 0 complete). If not, use `/spec-request-spec` first.

## Inputs

You need a **spec name** in kebab-case (e.g., `user-authentication`, `data-export`). Ask the user if they haven't provided one.

## Process

### 1. Gather Context

Read the approved request specification and steering documents if they exist:

```
.spec-workflow/specs/{spec-name}/request-spec.md
```

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

Validate the document in **2 stages** before requesting approval.

#### Step A: fix (automated mechanical corrections)

Auto-fix placeholders, formatting, and typos. Do not add or change content:

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Fix requirements spec (auto-fix)",
  prompt: "You are a spec document reviewer. Auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Document type: requirements

    Auto-fix targets (you may directly modify the file):
    - Remove placeholder text ([describe...], TODO, TBD)
    - Fix markdown formatting (table alignment, heading levels, etc.)
    - Fix obvious typos

    Not auto-fix targets (report as issues only):
    - Adding or removing sections
    - Adding or changing content (requirements, Acceptance Criteria, etc.)

    Mode: fix — Return a structured report (auto-fixed items + remaining issues)."
})
```

#### Step B: check (content validation)

After fix is complete, detect content issues. Do not modify the file:

```
Agent({
  subagent_type: "general-purpose",
  model: "opus",
  description: "Review requirements spec (check)",
  prompt: "You are a spec document reviewer. Review the document (do NOT modify the file) at:
    {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Document type: requirements
    Template: {project-path}/.spec-workflow/templates/requirements-template.md

    Checks:
    1. TEMPLATE: Every section from the template must exist with real content (no [describe...] or TODO)
    2. Every requirement needs User Story ('As a [role]...') and EARS Acceptance Criteria (WHEN/IF...THEN...SHALL)
    3. Non-Functional Requirements must cover: Code Architecture, Performance, Security, Reliability, Usability
    4. Requirements should be uniquely identified (REQ-1, REQ-2, etc.)

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 6. Approval Workflow

This is a strict, automated process. Verbal approval from the user is never accepted — only dashboard or VS Code extension approval counts.

1. **Request approval**: Use the `approvals` MCP tool with `action: 'request'`. Pass `filePath` only — never include content in the request. Save the returned `approvalId`.

2. **Automatic polling with auto-transition**: Start approval polling (Bash script with 60-minute timeout):
   ```
   /check-approval <approvalId> next:/spec-design
   ```
   The polling script will automatically check approval status and handle the result:
   - **approved**: Cleanup is performed automatically, and check-approval automatically invokes `/spec-design`
   - **needs-revision**: Reviewer comments are displayed
   - **timeout**: Reported to user, can re-run to resume

3. **Handle needs-revision** (if polling ends with needs-revision):
   - Read the reviewer's comments, update the document accordingly
   - Spawn the review subagent again (Step A + B)
   - Submit a NEW approval request and run `/check-approval <newApprovalId> next:/spec-design`

## Rules

- Feature names use kebab-case (e.g., `user-authentication`)
- One spec at a time
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before moving to design
