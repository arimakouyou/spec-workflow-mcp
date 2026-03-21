---
name: spec-review
description: "Self-review a specification document before requesting user approval. This skill is designed to run as a subagent — spawn it with the Agent tool to keep review details out of the main context. Use automatically after creating or updating any spec document (requirements.md, design.md, tasks.md) and BEFORE requesting approval. Triggers on: any spec document creation, before approval requests, 'review spec', 'check spec quality'."
---

# Spec Review (Subagent)

This skill is designed to run as a **subagent** via the Agent tool. It has two modes.

## Mode: check (default — review before Approval)

**Do not modify the file.** Only detect and return a list of issues. The caller reviews the issues and makes corrections themselves, then runs check again. Do not add or change content (the reviewer must not "invent" content).

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "Review spec document (check)",
  prompt: `You are a spec document reviewer. Check the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/{doc-type}.md

    Document type: {doc-type}
    Spec name: {spec-name}
    Mode: check

    Follow the /spec-review skill instructions below:

    1. TEMPLATE COMPLIANCE: Re-read the template at .spec-workflow/templates/{doc-type}-template.md
       and verify every section is present with substantive content (no placeholders like [describe...] or TODO).

    2. CROSS-REFERENCE CHECK:
       - For design.md: verify every requirement in requirements.md has a design solution
       - For tasks.md: verify every requirement has a task, every design component has a task,
         _Requirements references match actual IDs, task ordering respects dependencies

    3. QUALITY CHECK: No placeholder text, no duplicates, consistent naming, testable acceptance criteria,
       realistic error scenarios, task descriptions specific enough for AI implementation.

    4. DO NOT modify the file. List all issues found with their location and suggested fix.

    5. Return a structured report (see Output Format below).`
})
```

Caller flow:
1. Run spec-review in check mode
2. If issues = 0 → proceed to Approval
3. If issues >= 1 → caller reviews issues and corrects design.md/tasks.md
4. Run check mode again (repeat until issues = 0, up to 3 times)

## Mode: fix (minor automated fixes only)

Performs **only mechanical fixes** such as removing placeholder text and fixing formatting. Does not add or change content (adding sections, requirements, error codes, etc.) — those are reported as issues.

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "Review spec document (fix)",
  prompt: `You are a spec document reviewer. Check and auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/{doc-type}.md

    Document type: {doc-type}
    Spec name: {spec-name}
    Mode: fix

    Items eligible for auto-fix (may directly modify the file):
    - Remove placeholder text ([describe...], TODO, TBD)
    - Fix markdown formatting (table alignment, heading levels, etc.)
    - Obvious typos

    Items NOT eligible for auto-fix (report as issues only):
    - Adding or removing sections
    - Adding or changing content (requirements, design components, error codes, etc.)
    - Traceability inconsistencies

    Return a structured report with auto-fixed items and remaining issues.`
})
```

## Review Checklist by Document Type

### Requirements (`requirements.md`)

**Template compliance:**
- Introduction section with clear feature overview
- Alignment with Product Vision section (references steering docs if they exist)
- Every requirement has User Story: "As a [role], I want [feature], so that [benefit]"
- Every requirement has Acceptance Criteria using EARS pattern (WHEN/IF...THEN...SHALL)
- Non-Functional Requirements: Code Architecture, Performance, Security, Reliability, Usability

**Quality:**
- No placeholder text (`[describe...]`, `TODO`, `TBD`)
- Acceptance criteria are testable and specific
- Requirements are uniquely identified (REQ-1, REQ-2, etc.)

### Design (`design.md`)

**Template compliance:**
- Overview with architectural description
- Steering Document Alignment (tech.md, structure.md)
- Code Reuse Analysis (see dedicated check below)
- Architecture section with diagram
- Components/Interfaces: Purpose, Interfaces, Dependencies, Reuses
- Data Models with concrete field definitions
- Error Handling with specific scenarios
- Requirements Traceability Matrix (see dedicated check below)

**Code Reuse Analysis (concrete paths required):**
- Is the table format listing "Reuse target / Path / Usage" present?
- Are paths concrete file paths (e.g., `src/middleware/auth.rs`) rather than abstract descriptions (e.g., "leverage existing middleware")?
- Do the paths actually exist in the codebase?
- Is the granularity fine enough to be copied directly into each task's `_Leverage` field in Phase 3?

**Requirements Traceability Matrix:**
- Are all requirement IDs (REQ-1, REQ-2, ...) included in the matrix?
- Is the corresponding design component listed for each requirement?
- Reverse check: are there any design components with no backing requirement?
- Testing Strategy: Unit, Integration, E2E

**Cross-reference (read requirements.md):**
- Every requirement has a corresponding design solution
- No design component without a backing requirement
- Data models cover all entities from requirements

**DB Schema review (strictly validated to prevent post-approval changes):**
- Every table lists column names, types, and constraints (NOT NULL, UNIQUE, DEFAULT, etc.)
- Primary keys, foreign keys, and indexes are defined
- **Each FK explicitly specifies `ON DELETE` behavior (CASCADE / RESTRICT / SET NULL)** — leaving it unspecified is not allowed; this is a design decision directly tied to business logic and must always be explicit
- Relationships between tables (1:1, 1:N, N:M) and cardinality are clear
- Migration strategy is documented (column add/drop order, data migration if needed)
- Normalization level is appropriate (no unnecessary redundancy; denormalization for performance must have justification)
- **The meaning of nullable columns is clear** (why NULL is allowed; if a DEFAULT value exists, its meaning is documented)
- Timestamp columns (created_at, updated_at) are present
- Soft-delete vs. hard-delete policy is explicitly stated (where applicable)

**API Design review (strictly validated to prevent post-approval changes):**
- All endpoints list HTTP method, path, and description
- Each endpoint defines request body / query parameter types, required/optional status, and validation rules
- Each endpoint defines response types (success + error) and HTTP status codes
- Error response format is consistent (e.g., `{ "error": { "code": "...", "message": "..." } }`)
- **Error codes are defined in a table** (columns: error code name, HTTP Status, trigger condition). Must be exhaustive to prevent undeclared error codes from being added during implementation
- Authentication/authorization requirements are specified per endpoint
- Pagination, filtering, and sorting parameter design is documented (where applicable)
- RESTful conventions are followed (plural resource names, appropriate HTTP methods)

**Data Model review (strictly validated to prevent post-approval changes):**
- DB Model (e.g., Queryable) and DTOs (request/response types) are defined separately
- DTO fields match the request/response definitions in the API Design
- Fields that must not be exposed (e.g., password_hash) are excluded in the Model → DTO conversion
- Validation rules are defined in request DTOs
- Enum values (status, role, etc.) are exhaustive

**Quality:**
- No placeholder text
- Consistent component naming
- Error scenarios cover realistic failure modes
- DB Schema / API / Data Model are concrete enough that implementers have minimal room to interpret the design

### Tasks (`tasks.md`)

**Template compliance:**
- Every task has `- [ ]` checkbox marker
- Every task specifies target file path(s)
- Every task has `_Leverage` field
- Every task has `_Requirements` field
- Every task has `_Prompt` field with: Role, Task, Restrictions, Success
- `_Prompt` contains Role, Task, Restrictions, Success fields in the format "Role: ... | Task: ... | Restrictions: ... | Success: ..."
- Tasks are atomic (1-3 files each)

**Cross-reference (read requirements.md and design.md):**
- Every requirement has at least one implementing task
- Every design component has at least one creating task
- `_Requirements` IDs match actual requirement IDs
- `_Leverage` paths are plausible (match paths in the design.md Code Reuse Analysis table)
- Task ordering respects dependencies (interfaces before implementations, models before services)

**Traceability Matrix back-fill validation (read design.md):**
- Are all rows in the Requirements Traceability Matrix in design.md filled in with a "Target Task ID"?
- Do the "Target Task ID" values match actual task IDs that exist in tasks.md?
- If any component row is empty, a task must be added to tasks.md and the matrix must be updated

**`_TDDSkip` and Interface-only task validation:**
- Is `_TDDSkip: true` applied appropriately (only to tasks that cannot be tested in isolation)?
  - OK: project initialization, Dockerfile, migrations, config files (tasks that are self-contained)
  - NG: tasks that only define a trait/struct (not self-contained → should be merged into an implementation task)
- If an interface-only task is detected (`_TestFocus` all "N/A" + Success is only "compiles" + no `_TDDSkip`):
  - Either add `_TDDSkip: true`, or merge into the first task that references it via `_Leverage`
  - Decision rule: "Is this task self-contained?" → Yes: `_TDDSkip`, No: merge

**`_TestFocus` format validation:**
- Does every non-PhaseReview task's `_TestFocus` use the 4-category structure (Happy Path / Boundary Values / Error Handling / Edge Cases)?
- Is free-form text being used instead (e.g., "CRUD success/failure, validation boundaries")?
- Are categories that do not apply explicitly marked as "N/A" (not omitted)?
- Is each category's content specific (not abstract like "Happy Path: success path" but rather "Happy Path: all CRUD operation success paths")?

**Single responsibility validation:**
- Does the `_Prompt` Task field join multiple behaviors with "and"?
- Can the task be described in a single sentence? (If multiple sentences are needed → consider splitting)
- Do the Success criteria contain multiple independent conditions? (e.g., "A compiles and B validates and C works" → split into 3 tasks)
- If a task needs splitting, split it and update tasks.md

**Quality:**
- No placeholder text
- Task descriptions specific enough for AI agent implementation
- No duplicate tasks

## Output Format

### check mode

```
## Spec Review: {spec-name}/{doc-type}.md (check)

### Checks Performed
- Template compliance: {PASS / N issues}
- Cross-references: {PASS / N issues / N/A for requirements}
- Quality: {PASS / N issues}

### Issues (caller must fix)
1. [category: Template/CrossRef/Quality] {description of issue} — location: {section name or line number} — suggested fix: {concrete suggestion}
2. ...

### Items for User Attention
- [any gaps requiring human judgment, if any]

### Result: {PASS (issues 0) / FAIL (issues N)}
```

### fix mode

```
## Spec Review: {spec-name}/{doc-type}.md (fix)

### Auto-Fixed
- [list of auto-fixed items with before/after]

### Remaining Issues (caller must fix)
1. [category] {description of issue} — location: {section name} — suggested fix: {suggestion}
2. ...

### Result: {PASS (remaining 0) / FAIL (remaining N)}
```
