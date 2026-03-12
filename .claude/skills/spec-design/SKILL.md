---
name: spec-design
description: "Phase 2 of spec-driven development: create a technical design document for a feature. Use this skill after requirements are approved, when the user wants to create a design doc, define architecture, or plan how to build a feature. Triggers on: 'create design', 'design document', 'technical architecture for X', 'how should we build X', or any request to create a design.md document."
---

# Spec Design (Phase 2)

Create a technical design document that defines **how** to build the feature. This phase follows approved requirements and precedes task breakdown.

## Prerequisites

Requirements must be approved and cleaned up (Phase 1 complete). If not, use `/spec-requirements` first.

## Inputs

The same **spec name** used in Phase 1 (kebab-case, e.g., `user-authentication`).

## Process

### 1. Load the Template

Check for a custom template first, then fall back to the default:

1. `.spec-workflow/user-templates/design-template.md` (custom)
2. `.spec-workflow/templates/design-template.md` (default)

### 2. Analyze and Research

- Read the approved requirements: `.spec-workflow/specs/{spec-name}/requirements.md`
- Analyze the existing codebase for patterns, conventions, and reusable components
- If web search is available, research technology choices and current best practices
- Ensure every requirement has a corresponding design solution

### 3. Create the Document

Write the design document with all template sections to:
```
.spec-workflow/specs/{spec-name}/design.md
```

The design should address:
- Architecture decisions and rationale
- Component structure and relationships
- Data models and API contracts
- Integration points with existing code
- Error handling and edge cases

### 4. Self-Review via Subagent (before approval)

Spawn a subagent to review and fix the document before requesting approval:

```
Agent({
  subagent_type: "general-purpose",
  description: "Review design spec",
  prompt: "You are a spec document reviewer. Review and fix the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Document type: design
    Template: {project-path}/.spec-workflow/templates/design-template.md
    Requirements: {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Checks:
    1. TEMPLATE: Every section from the template must exist with real content (no placeholders)
    2. CROSS-REFERENCE: Read requirements.md — every requirement must have a corresponding design solution.
       No design component should exist without a backing requirement.
    3. Must include: Overview, Steering Alignment, Code Reuse Analysis, Architecture diagram,
       Components/Interfaces (Purpose, Interfaces, Dependencies, Reuses), Data Models, Error Handling, Testing Strategy
    4. Data models must cover all entities referenced in requirements

    Fix all issues directly in the file. Return a summary of checks and fixes."
})
```

Wait for the subagent to complete, then proceed to approval.

### 5. Approval Workflow

Same strict process as requirements — verbal approval is never accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only
2. **Poll status**: `approvals` tool, `action: 'status'`, keep polling
3. **Handle result**:
   - **needs-revision**: Update document using reviewer comments, spawn the review subagent again, submit NEW approval
   - **approved**: Move to cleanup
4. **Cleanup**: `approvals` tool, `action: 'delete'` — must succeed
   - If delete fails: STOP, return to polling
5. **Next phase**: After successful cleanup, proceed to Phase 3 (Tasks). Use the `/spec-tasks` skill.

## Rules

- Feature names use kebab-case
- One spec at a time
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
- Must have approved status AND successful cleanup before moving to tasks
