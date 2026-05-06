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
| **product.md** | Vision, goals, target users, success metrics | `.spec-workflow/steering/product.md` |
| **tech.md** | Project-level technology stack and architecture | `.spec-workflow/steering/tech.md` |
| **structure.md** | Codebase organization, naming conventions, patterns | `.spec-workflow/steering/structure.md` |

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
- Discuss with the user to understand the product vision and goals
- Define target users, key features, and success metrics
- Establish product principles that guide decisions
- If web search is available, research market context

**For tech.md:**
- Analyze the existing codebase to detect technology stack (package.json, Cargo.toml, etc.)
- Document programming languages, frameworks, and key libraries
- Record architectural patterns and decisions
- Technology selection rationale and decision history go to `.spec-workflow/steering/logs/tech-decisions.md`, not in tech.md itself

**For structure.md:**
- Analyze the actual directory structure and file organization
- Document naming conventions, import patterns, and code structure
- Define module boundaries and code organization principles
- Include dashboard/monitoring structure if applicable

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
    3. COMPLETENESS: All tables must have concrete entries, not placeholder rows
    4. ACTIONABILITY: Guidance must be clear enough to inform future spec development

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

#### Step E: Approval Workflow

This is a strict, automated process. Verbal approval from the user is never accepted — only dashboard or VS Code extension approval counts.

1. **Request approval**: Use the `approvals` MCP tool with `action: 'request'`. Pass `filePath` only — never include content in the request. Save the returned `approvalId`.

2. **Check approval (synchronous)**: After the user approves via the dashboard / VS Code extension, run:
   ```
   /check-approval <approvalId>
   ```
   `check-approval` fetches status once via the `approvals` MCP tool (no polling) and branches:
   - **pending**: User has not acted yet — instruct the user to approve, then re-run `/check-approval`
   - **approved**: Cleanup is performed automatically
   - **needs-revision**: Reviewer comments are displayed
   - **rejected**: Rejection reason is displayed — revise and create a new approval

3. **Handle needs-revision** (if status was needs-revision):
   - Read the reviewer's comments, update the document accordingly
   - Re-run the review subagent (fix + check)
   - Submit a NEW approval request and run `/check-approval <newApprovalId>`

4. **Next document**: After approval and cleanup succeed, proceed to the next document in sequence (product → tech → structure). If this was the last document, inform the user that steering docs are complete.

### 3. Completion

After all requested steering documents are approved:
- Inform the user: "Steering documents are complete. These will be referenced automatically during spec creation phases."
- If the user wants to start spec development, suggest: "Ready to create a spec? Use `/spec-request-spec` to begin Phase 0."

### 4. CLAUDE.md Setup Guidance (P1-02)

> **P1-02**: Item P1-02 of the harness-maturity-check checklist P1 (context engineering),
> "Agent-facing instruction file is in place."

After steering doc creation is finished, check the state of `CLAUDE.md` at the project root (or other agent-facing instruction files such as `.cursorrules` or `.github/copilot-instructions.md`).

**Checklist:**

1. **Existence**: Does an agent-facing instruction file exist at the project root?
2. **Conciseness**: Aim for under 100 lines; defer details via pointers to other files
3. **Pointer design**: Compose concrete rules and patterns as references to `.claude-plugin/rules/` or steering docs

**Recommended structure:**

```markdown
# CLAUDE.md

## Project Overview
{1-2 line overview. See .spec-workflow/steering/product.md for details}

## Architecture
{1-2 line structural overview. See .spec-workflow/steering/structure.md for details}

## Technology Stack
{List of primary technologies. See .spec-workflow/steering/tech.md for details}

## Coding Rules
- Rule index: under the `.claude-plugin/rules/` directory
- Style: `.claude-plugin/rules/rust-style.md`
- Security: `.claude-plugin/rules/security.md`

## Workflow
- Adopt spec-driven development via spec-workflow
- Always obtain design approval before implementation
```

If CLAUDE.md does not exist, propose the structure above to the user. If it exists, check its conciseness and pointer design and propose improvements.

## Rules

- Create documents in sequence: product.md → tech.md → structure.md
- Check for custom templates in `.spec-workflow/user-templates/` first
- Follow exact template structures
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before next document
- tech.md: selection rationale goes to `.spec-workflow/steering/logs/tech-decisions.md`
- When the user requests the full steering-doc set, complete documents in the specified sequence (no skipping); users may still request or update individual documents directly.
