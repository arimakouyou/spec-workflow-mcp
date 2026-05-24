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
- **Decide `task_type`** (required in frontmatter — see `.claude-plugin/rules/task-types.md` TT1/TT2). Ask the user to confirm which of `feature-add` / `feature-modify` / `bugfix` / `refactor` / `legacy-migration` best describes the work. Use `legacy` only for throwaway prototypes that should skip Phase 0.5; that value requires a `legacy_reason:` sibling. If the user is unsure between two types, prefer the one whose required evidence categories (TT2) better match the work (e.g. anything touching existing callers is `feature-modify`, not `feature-add`).
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
    6. TASK_TYPE: The frontmatter contains a task_type field whose value is one of
       {feature-add, feature-modify, bugfix, refactor, legacy-migration, legacy}.
       Consult .claude-plugin/rules/task-types.md TT1/TT2/TT5 and
       .spec-workflow/user-config/task-types.yml if it exists (TT4 overrides add more valid values).
       If task_type is 'legacy', require a non-empty legacy_reason: sibling field; WARN but do not FAIL.
       Missing task_type is WARN (legacy exception) only if requirements.md already exists for this spec
       in a pre-existing state; otherwise FAIL and ask the user to declare one.

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 6. Approval Workflow

This is a strict, automated process. Verbal approval from the user is never accepted — only dashboard or VS Code extension approval counts.

1. **Request approval**: Use the `approvals` MCP tool with `action: 'request'`. Pass `filePath` only — never include content in the request. Save the returned `approvalId`.

2. **Check approval (synchronous)**: After the user approves via the dashboard / VS Code extension, run `/check-approval` with a `next:` argument chosen based on the document's frontmatter `task_type`:

   - `feature-add` / `feature-modify` / `bugfix` / `refactor` / `legacy-migration` → `next:/spec-investigate`
   - `legacy` or missing `task_type` → `next:/spec-requirements` (Phase 0.5 is skipped for these specs, per `.claude-plugin/rules/task-types.md` TT5)

   ```
   /check-approval <approvalId> next:/spec-investigate      # default for classified specs
   /check-approval <approvalId> next:/spec-requirements     # legacy / unclassified specs only
   ```
   `check-approval` fetches status once via the `approvals` MCP tool (no polling) and branches:
   - **pending**: User has not acted yet — instruct the user to approve, then re-run `/check-approval`
   - **approved**: Cleanup is performed automatically, and `check-approval` automatically invokes the chosen `next:` skill
   - **needs-revision**: Reviewer comments are displayed
   - **rejected**: Rejection reason is displayed — revise and create a new approval

3. **Handle needs-revision** (if status was needs-revision):
   - Read the reviewer's comments, update the document accordingly
   - Spawn the review subagent again (Step A + B)
   - Submit a NEW approval request and run `/check-approval <newApprovalId> next:/spec-investigate` (or `next:/spec-requirements` if the spec is legacy/unclassified)

## Rules

- Feature names use kebab-case (e.g., `user-authentication`)
- One spec at a time
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before moving to the next phase
- The next phase is `/spec-investigate` for classified task types and `/spec-requirements` for legacy/unclassified specs — never skip `/spec-investigate` when a non-legacy `task_type` is declared
- If steering/tech.md exists, only describe feature-specific technology additions
