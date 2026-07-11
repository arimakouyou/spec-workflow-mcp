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

**Frontmatter (required for new specs, per `${CLAUDE_PLUGIN_ROOT}/rules/spec-dependency-graph.md` SD2-SD3):**

Include the following YAML frontmatter at the top of the file:

```yaml
---
spec_id: {spec-name}
phase: requirements
version: 1
depends_on: []
---
```

`requirements.md` is the upstream root, so `depends_on` is always an empty array.

**Requirement IDs (per SD1):**

Use `### REQ-N: [Requirement Name]` for each requirement heading. Acceptance Criteria are numbered `1.`, `2.`, `3.` within the requirement — they form the implicit `REQ-N.M` identifiers that downstream specs reference. Add `<!-- REQ-N.M -->` comments after each Acceptance Criterion line so that downstream agents can locate them precisely.

**Test Layers per Acceptance Criterion (per K-1, `dapper-hardening-orchestrator.md`):**

Each Acceptance Criterion must declare which test layers verify it, by adding a `- Test Layers: ...` line immediately below the AC. Allowed layer values are defined in the **Test Taxonomy** section of `quality-checks.md`:

- `UT` — pure unit test
- `CT` — component reactivity test (targets UI framework components)
- `IT-N` — backend HTTP integration test (specific spec ID; `N` is finalized in test-design.md)
- `ST-N` — system test (single feature full-stack)
- `E2E-N` — end-to-end (user journey)

Multiple layers may be combined in one declaration. Specific test IDs (the `N` in IT-N / ST-N / E2E-N) are finalized in test-design.md, so at the requirements.md stage either tentative IDs or layer names alone are acceptable (e.g., `Test Layers: UT, IT, ST`). They are back-filled once test-design.md is complete.

Format example:
```markdown
1. WHEN [event] THEN [system] SHALL [response]  <!-- REQ-1.1 -->
   - Test Layers: UT, IT-1, ST-3
2. IF [precondition] THEN [system] SHALL [response]  <!-- REQ-1.2 -->
   - Test Layers: UT, CT
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
    3. Non-Functional Requirements must cover: Code Architecture, Performance, Security, Reliability, Usability, **Testability** (6 categories; Testability added in K-5)
    4. Requirements must be uniquely identified as '### REQ-N:' headings (per spec-dependency-graph.md SD1)
    5. FRONTMATTER (spec-dependency-graph.md SD2): Valid YAML frontmatter with spec_id, phase: requirements, version, depends_on: [] must exist at the top of the file
    6. TEST LAYERS (per K-1): Every Acceptance Criterion must have a `- Test Layers: ...` line declaring which test layers verify it. Layer values must be drawn from quality-checks.md Test Taxonomy (UT / CT / IT / ST / E2E)
    7. EVIDENCE CITATIONS (evidence-coverage.md EC1): Read task_type from .spec-workflow/specs/{spec-name}/request-spec.md frontmatter and detect whether this document contains any EV-{category}-{NNN} citation (HTML comment, inline paren form, or frontmatter depends_on.refs).
       - If request-spec.md does not exist, or task_type is absent → SKIP checks 7-10 (EC5) and note 'evidence checks skipped (no request-spec / unclassified)' in the report.
       - If task_type is 'legacy' AND no EV-{category}-{NNN} citation is present in this document → SKIP checks 7-10 (EC5) and note 'evidence checks skipped (legacy, no EV citations)' in the report.
       - If task_type is 'legacy' AND at least one EV-{category}-{NNN} citation is present (opt-in legacy mode, EC5):
           Run check 7 (EC1 integrity) on every citation as described below.
           SKIP checks 8-10 and note 'legacy spec: ran EC1 only due to EV citations; skipped EC2 / EC3' in the report.
       - If task_type is any other declared value, run checks 7-10 normally.
       - For every EV-{category}-{NNN} citation in this document (HTML comment, inline paren form, or frontmatter depends_on.refs) when check 7 applies:
           a. The file .spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md must exist (use Read to probe).
           b. The referenced file's frontmatter spec_name: must equal this spec-name.
           c. The {category} must be one of the categories listed in ${CLAUDE_PLUGIN_ROOT}/rules/task-types.md TT3 (and .spec-workflow/user-config/task-types.yml TT4 if present).
         Any failure = FAIL with rule_id EC1.
    8. INLINE CODE BUDGET (evidence-coverage.md EC3): Apply this check only when check 7 routed to full enforcement (non-legacy classified task_type). Count fenced code block lines (between opening and closing fences, excluding the fence lines themselves; any language or no language counts). Fail if any of:
           - A single fenced block exceeds 10 lines.
           - Cumulative fenced-block lines within a single H2 or H3 section exceed 20 lines.
           - Total fenced-block lines in the document exceed 80 lines.
         For each violation, produce a FAIL with rule_id EC3, location, and a fix_hint like 'Move the N-line excerpt to a new EV-{category}-{NNN}.md under evidence/{category}/ and leave a 1-2 sentence summary with the EV citation'. Markdown tables, block-quoted prose, and ASCII diagrams are NOT counted.
    9. CATEGORY COVERAGE (evidence-coverage.md EC2, doc-level): Apply this check only when check 7 routed to full enforcement (non-legacy classified task_type). For the declared task_type, read the required categories from ${CLAUDE_PLUGIN_ROOT}/rules/task-types.md TT2 (merged with .spec-workflow/user-config/task-types.yml TT4 if present). Every required category must appear at least once across either:
           - EV-{category}-... citations in the body (HTML comment, inline paren, or anywhere in fenced prose), OR
           - frontmatter depends_on.refs entries that start with EV-{category}-.
         Missing category = FAIL rule_id EC2 with fix_hint 'Add at least one EV-{category}-... citation somewhere in requirements.md (any REQ or the Non-Functional Requirements section) and ensure a matching evidence file exists under evidence/{category}/. If the category legitimately does not apply to this spec, add <!-- no-evidence: {category} — {reason} --> at the top of the document (doc-level category waiver format defined in evidence-coverage.md EC2).'
         A <!-- no-evidence: {category} — {reason} --> comment at the top of the document waives coverage for the named {category} when both {category} and {reason} are non-empty and {category} matches a task-types.md TT3 / TT4 entry; record it as WARN rather than FAIL. One comment per waived category.
    10. PER-REQ EVIDENCE (evidence-coverage.md EC2, per-REQ): Apply this check only when check 7 routed to full enforcement (non-legacy classified task_type). Each '### REQ-N:' heading SHOULD have at least one EV-... citation on one of its Acceptance Criteria. Missing = WARN with rule_id EC2_perREQ (not blocking).

    Reporting: for issues triggered by rules EC1/EC2/EC3, include fields rule_id, location, message, fix_hint.
    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 6. Approval Workflow

This is a strict, automated process. Verbal approval from the user is never accepted — only dashboard or VS Code extension approval counts.

1. **Request approval**: Use the `approvals` MCP tool with `action: 'request'`. Pass `filePath` only — never include content in the request. Save the returned `approvalId`.

2. **Check approval (synchronous)**: After the user approves via the dashboard / VS Code extension, run:
   ```
   /check-approval <approvalId> next:/spec-design
   ```
   `check-approval` fetches status once via the `approvals` MCP tool (no polling) and branches:
   - **pending**: User has not acted yet — instruct the user to approve, then re-run `/check-approval`
   - **approved**: Cleanup is performed automatically, and `check-approval` automatically invokes `/spec-design`
   - **needs-revision**: Reviewer comments are displayed
   - **rejected**: Rejection reason is displayed — revise and create a new approval

3. **Handle needs-revision** (if status was needs-revision):
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
