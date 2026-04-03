---
name: adr
description: >
  Create and manage Architecture Decision Records (ADRs) in .claude/_docs/adr/.
  Each ADR documents a significant architectural decision with status tracking
  (Proposed, Accepted, Deprecated, Superseded). Triggers: 'create ADR', 'record decision',
  'architecture decision', 'ADR', '意思決定記録', 'design decision',
  or any request to document an architectural choice.
argument-hint: "<title> [--status Proposed|Accepted] [--supersedes ADR-NNNN]"
user-invokable: true
---

# Architecture Decision Records (ADR)

Create and manage ADRs in `.claude/_docs/adr/`. ADRs document significant architectural decisions with their context, alternatives, and consequences, providing a version-controlled decision trail.

## ADR Directory Structure

```
.claude/_docs/adr/
  INDEX.md              # ADR index with status summary
  0001-use-axum.md      # Individual ADR files
  0002-postgresql-over-sqlite.md
  ...
```

## Status Lifecycle

```
Proposed → Accepted → (Deprecated | Superseded by ADR-NNNN)
```

| Status | Meaning |
|--------|---------|
| **Proposed** | Decision is under discussion, not yet finalized |
| **Accepted** | Decision is approved and in effect |
| **Deprecated** | Decision is no longer relevant (project evolved beyond it) |
| **Superseded** | Decision replaced by a newer ADR (link to successor) |

## Operations

### Create a New ADR

**Trigger**: User describes a decision, or `/adr <title>`

1. **Determine the next ADR number**:
   ```bash
   ls .claude/_docs/adr/[0-9]*.md 2>/dev/null | sort -V | tail -1
   ```
   Extract the number and increment. If no ADRs exist, start with `0001`.

2. **Create the ADR file** using the template at `.claude-plugin/skills/adr/references/adr-template.md`:
   - Replace `{{NUMBER}}` with zero-padded number (e.g., `0001`)
   - Replace `{{TITLE}}` with the decision title
   - Replace `{{DATE}}` with today's date (YYYY-MM-DD)
   - Set `status: Proposed` (or `Accepted` if `--status Accepted` specified)

3. **Fill in the content** based on the user's description:
   - **Context**: Why this decision is needed
   - **Decision**: What was decided
   - **Alternatives Considered**: What other options were evaluated and why they were rejected
   - **Consequences**: Positive outcomes, negative trade-offs, and risks

4. **Write the file** to `.claude/_docs/adr/{NNNN}-{slug}.md` (slug = kebab-case title)

5. **Update INDEX.md** (create if it doesn't exist):

   ```markdown
   # Architecture Decision Records

   | ADR | Title | Status | Date |
   |-----|-------|--------|------|
   | [ADR-0001](0001-use-axum.md) | Use Axum as HTTP framework | Accepted | 2026-04-02 |
   ```

### Update ADR Status

**Trigger**: User says "accept ADR-NNNN", "deprecate ADR-NNNN", or "supersede ADR-NNNN with ..."

1. Read the target ADR file
2. Update the `status` field in frontmatter
3. If superseding, add `superseded-by: ADR-NNNN` to frontmatter and note in the body
4. Update INDEX.md

### List ADRs

**Trigger**: User says "list ADRs", "show decisions"

Read INDEX.md and present the summary table.

## Integration with spec-design

When `/spec-design` creates Key Design Decisions in Wave 1, it automatically generates ADRs for each significant decision. See the spec-design skill for details.

The ADRs created during design use `status: Accepted` because the design approval process serves as the decision approval.

## Integration with feedback-loop

Architectural decisions discovered through know-how accumulation can be promoted to ADRs:
- know-how with domain `architecture` → candidate for ADR
- When a know-how entry represents a significant irreversible decision, promote it to an ADR via this skill

## When to Create ADRs

Create an ADR when a decision:
- Is **difficult to reverse** (framework choice, database choice, protocol choice)
- **Affects multiple components** (cross-cutting concerns)
- Was **debated** among alternatives (the "why not X?" question is valuable)
- Has **significant consequences** (performance, security, maintainability trade-offs)

Do NOT create ADRs for:
- Obvious choices with no real alternatives
- Trivial implementation details
- Temporary workarounds (use know-how instead)
