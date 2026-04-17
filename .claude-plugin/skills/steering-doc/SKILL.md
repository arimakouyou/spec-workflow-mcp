---
name: steering-doc
description: "Create project-level steering documents (product.md, tech.md, structure.md) that define vision, technology stack, and codebase conventions. Use this skill when the user wants to set up steering docs, define project direction, or establish project-level guidance before starting specs. Triggers on: 'create steering document', 'steering doc', 'ステアリングドキュメント', 'setup project guidance', 'define project vision', 'define tech stack', 'project structure doc', 'product vision', or any request to create steering/*.md documents."
---

# Steering Document Creation

Create project-level guidance documents that inform all future spec-driven development. Steering documents are created in sequence: **product.md → tech.md → structure.md**.

## When to Use

- Starting a new project and establishing direction
- Documenting an existing project's vision, tech stack, and structure
- Before beginning the first spec (steering docs feed into Phase 0: Request Spec)

## Document Types

| Document | Purpose | Output Path |
|----------|---------|-------------|
| **product.md** | Product purpose, target users, non-goals, principles, success metrics | `.spec-workflow/steering/product.md` |
| **tech.md** | Technology stack, approved external dependencies, constraints, ADR summary | `.spec-workflow/steering/tech.md` |
| **structure.md** | Directory layout, File Placement Rules (P4-01), project-specific conventions | `.spec-workflow/steering/structure.md` |

General engineering policies (design principles, dependency direction, naming, style, security, testing, documentation) are authoritative in `.claude-plugin/rules/` and must NOT be duplicated into steering documents.

## Inputs

Ask the user which steering document(s) they want to create. If they say "all" or "steering documents", create all three in sequence.

If a specific `docType` is provided (product, tech, or structure), create only that one.

## Process

### 1. Check Existing State

Check which steering documents already exist:
```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

If a document already exists, inform the user and ask whether to overwrite or skip.

### 2. Create Each Document in Sequence

For each document to create, follow this process:

#### Step A: Load the Template

Check for a custom template first. If none exists, fall back to the default:

1. `.spec-workflow/user-templates/{docType}-template.md` (custom)
2. `.spec-workflow/templates/{docType}-template.md` (default)

Follow the template structure exactly for consistency.

#### Step B: Research and Write

**For product.md:**
- Discuss with the user to understand the product purpose, target users, and success metrics
- Define non-goals explicitly to bound scope
- Establish product principles that guide decisions
- If web search is available, research market context

**For tech.md:**
- Analyze the existing codebase to detect technology stack (package.json, Cargo.toml, *.csproj, etc.)
- Record project-specific instance data only: languages, approved dependencies, storage, integrations, constraints
- Detect deviations from `.claude-plugin/rules/project-architecture.md`; document them rather than restating the standard
- Populate the ADR summary table from `.claude/_docs/adr/INDEX.md` if any ADRs exist
- Formal decisions belong to ADRs (`.claude/_docs/adr/`, managed by the `/adr` skill). Lightweight chronological notes go to `.spec-workflow/steering/logs/tech-decisions.md`
- DO NOT duplicate policies that are already in `.claude-plugin/rules/` (security, type safety, error handling, testing, etc.); link to them instead

**For structure.md:**
- Capture the actual top-level directory layout as the instance record for this project
- Fill in File Placement Rules (P4-01) so that any new file's target directory is uniquely determined
- Record deviations from `.claude-plugin/rules/project-architecture.md` if any
- Fill Project-Specific Conventions only with rules NOT already covered by `.claude-plugin/rules/*-style.md`; otherwise state `Status: N/A — follows .claude-plugin/rules/*-style.md`
- DO NOT restate naming conventions, import order, module boundaries, code organization principles, or documentation standards that are already enforced by rules/

#### Step C: Create the Document

Write the file to:
```
.spec-workflow/steering/{docType}.md
```

#### Step D: Self-Review via Subagent (before approval)

Validate the document in **2 stages** before requesting approval.

**fix (automated mechanical corrections):**

Auto-fix placeholders, formatting, and typos. Do not add or change content:

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Fix steering doc (auto-fix)",
  prompt: "You are a spec document reviewer. Auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/steering/{docType}.md

    Document type: steering ({docType})

    Auto-fix targets (you may directly modify the file):
    - Remove placeholder text ([describe...], [e.g., ...], TODO, TBD)
    - Fix markdown formatting (table alignment, heading levels, etc.)
    - Fix obvious typos

    Not auto-fix targets (report as issues only):
    - Adding or removing sections
    - Adding or changing content

    Mode: fix — Return a structured report (auto-fixed items + remaining issues)."
})
```

**check (content validation):**

After fix is complete, detect content issues. Do not modify the file:

```
Agent({
  subagent_type: "general-purpose",
  model: "opus",
  description: "Review steering doc (check)",
  prompt: "You are a spec document reviewer. Review the document (do NOT modify the file) at:
    {project-path}/.spec-workflow/steering/{docType}.md

    Document type: steering ({docType})
    Template: {project-path}/.spec-workflow/templates/{docType}-template.md

    Checks:
    1. TEMPLATE: Every section from the template must exist with real content (no placeholders)
    2. SPECIFICITY: Content must be specific to this project, not generic boilerplate
    3. COMPLETENESS: All tables must have concrete entries, not placeholder rows. Sections that do not apply must read \`Status: N/A — {{reason}}\` rather than being blank
    4. ACTIONABILITY: Guidance must be clear enough to inform future spec development
    5. RULES NON-DUPLICATION: The document must not restate policies already enforced by \`.claude-plugin/rules/\`. Flag any of the following as issues (each section name maps to the \`.claude-plugin/rules/\` file that already owns it):
       - For structure.md:
         * \`Naming Conventions\` → owned by \`.claude-plugin/rules/*-style.md\` (rust-style.md / csharp-style.md / axum.md / etc.)
         * \`Import Patterns\` → owned by \`.claude-plugin/rules/*-style.md\`
         * \`Code Structure Patterns\` → owned by \`.claude-plugin/rules/design-principles.md\` / \`.claude-plugin/rules/*-style.md\`
         * \`Code Organization Principles\` → owned by \`.claude-plugin/rules/design-principles.md\`
         * \`Module Boundaries\` → owned by \`.claude-plugin/rules/design-principles.md\` / \`.claude-plugin/rules/project-architecture.md\`
         * \`Documentation Standards\` → owned by \`.claude-plugin/rules/doc-crossref.md\` / \`.claude-plugin/rules/doc-freshness.md\`
       - For tech.md:
         * \`Prohibited Patterns\` containing general language-level prohibitions → owned by \`.claude-plugin/rules/*-style.md\` / \`.claude-plugin/rules/security.md\`
         * Generic security policies → owned by \`.claude-plugin/rules/security.md\`
         * Generic testing policies → owned by \`.claude-plugin/rules/flaky-test-management.md\` / \`.claude-plugin/rules/regression-test-policy.md\`
         * Generic documentation policies → owned by \`.claude-plugin/rules/doc-crossref.md\` / \`.claude-plugin/rules/doc-freshness.md\`
       - Generic restatements of design principles D1–D6 → owned by \`.claude-plugin/rules/design-principles.md\`
       In each case, the fix is to remove the duplicated content and link to the authoritative \`.claude-plugin/rules/\` file named above.
    6. ADR LINKAGE (tech.md only): The Architecture Decision Records section should either contain a populated summary table matching \`.claude/_docs/adr/INDEX.md\`, or show \`Status: N/A — no ADRs yet\` if none exist.

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

#### Step E: Approval Workflow

This is a strict, automated process. Verbal approval from the user is never accepted — only dashboard or VS Code extension approval counts.

1. **Request approval**: Use the `approvals` MCP tool with `action: 'request'`. Pass `filePath` only — never include content in the request. Save the returned `approvalId`.

2. **Automatic polling**: Start approval polling (Bash script with 60-minute timeout):
   ```
   /check-approval <approvalId>
   ```
   The polling script will automatically check approval status and handle the result:
   - **approved**: Cleanup is performed automatically
   - **needs-revision**: Reviewer comments are displayed
   - **rejected**: Rejection reason is displayed — revise and create a new approval
   - **timeout**: Reported to user, can re-run to resume

3. **Handle needs-revision** (if polling ends with needs-revision):
   - Read the reviewer's comments, update the document accordingly
   - Re-run the review subagent (fix + check)
   - Submit a NEW approval request and run `/check-approval <newApprovalId>`

4. **Next document**: After approval and cleanup succeed, proceed to the next document in sequence (product → tech → structure). If this was the last document, inform the user that steering docs are complete.

### 3. Completion

After all requested steering documents are approved:
- Inform the user: "Steering documents are complete. These will be referenced automatically during spec creation phases."
- If the user wants to start spec development, suggest: "Ready to create a spec? Use `/spec-request-spec` to begin Phase 0."

### 4. CLAUDE.md Maintenance Guidance (P1-02)

> **P1-02**: This step addresses item P1-02 of the harness-maturity-check P1 (context engineering) checklist:
> "An agent-facing instruction file is in place."

After steering docs are created, verify the state of the project's root-level agent instruction file (`CLAUDE.md`, or equivalents such as `.cursorrules`, `.github/copilot-instructions.md`).

**Checks:**

1. **Existence**: An agent instruction file exists at the project root.
2. **Conciseness**: Aim for ≤ 100 lines; push details behind pointers to other files.
3. **Pointer design**: Concrete rules and patterns should be expressed as links to `.claude-plugin/rules/` and steering docs, not inlined.

**Recommended structure:**

```markdown
# CLAUDE.md

## Project Overview
{1-2 lines. Details: .spec-workflow/steering/product.md}

## Architecture
{1-2 lines. Details: .spec-workflow/steering/structure.md}

## Tech Stack
{Key technologies. Details: .spec-workflow/steering/tech.md}

## Coding Rules
- Rule index: `.claude-plugin/rules/INDEX.md`
- Style: `.claude-plugin/rules/rust-style.md` (or `csharp-style.md`)
- Security: `.claude-plugin/rules/security.md`

## Workflow
- Spec-driven development via spec-workflow.
- Always obtain design approval before implementation.
```

If no CLAUDE.md exists, propose the above structure. If one exists, review for conciseness and pointer design and suggest improvements.

## Rules

- Create documents in sequence: product.md → tech.md → structure.md
- Check for custom templates in `.spec-workflow/user-templates/` first
- Follow exact template structures
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before next document
- tech.md: formal architectural decisions go to ADRs under `.claude/_docs/adr/` (use the `/adr` skill); lightweight chronological notes go to `.spec-workflow/steering/logs/tech-decisions.md`
- Do not duplicate general engineering policies from `.claude-plugin/rules/` into steering documents; link to them instead
- When the user requests the full steering-doc set, complete documents in the specified sequence (no skipping); users may still request or update individual documents directly.
