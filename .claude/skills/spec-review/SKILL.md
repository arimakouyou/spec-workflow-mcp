---
name: spec-review
description: "Self-review a specification document before requesting user approval. This skill is designed to run as a subagent — spawn it with the Agent tool to keep review details out of the main context. Use automatically after creating or updating any spec document (requirements.md, design.md, tasks.md) and BEFORE requesting approval. Triggers on: any spec document creation, before approval requests, 'review spec', 'check spec quality'."
---

# Spec Review (Subagent)

This skill is designed to run as a **subagent** via the Agent tool. The calling agent should spawn this as a subagent with a prompt like:

```
Review the spec document at {file-path} using the /spec-review skill.
Spec name: {spec-name}
Document type: {requirements|design|tasks}
Project path: {project-path}
Fix any issues directly in the file. Return a summary of what was checked and what was fixed.
```

## How the Calling Agent Should Invoke This

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "Review spec document",
  prompt: `You are a spec document reviewer. Review and fix the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/{doc-type}.md

    Document type: {doc-type}
    Spec name: {spec-name}

    Follow the /spec-review skill instructions below:

    1. TEMPLATE COMPLIANCE: Re-read the template at .spec-workflow/templates/{doc-type}-template.md
       and verify every section is present with substantive content (no placeholders like [describe...] or TODO).

    2. CROSS-REFERENCE CHECK:
       - For design.md: verify every requirement in requirements.md has a design solution
       - For tasks.md: verify every requirement has a task, every design component has a task,
         _Requirements references match actual IDs, task ordering respects dependencies

    3. QUALITY CHECK: No placeholder text, no duplicates, consistent naming, testable acceptance criteria,
       realistic error scenarios, task descriptions specific enough for AI implementation.

    4. FIX all issues directly in the file. Do not just list problems — fix them.

    5. Return a brief summary:
       - What was checked
       - What issues were found and fixed
       - Any items needing human judgment (flag but don't invent requirements)`
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
- Code Reuse Analysis with specific existing components
- Architecture section with diagram
- Components/Interfaces: Purpose, Interfaces, Dependencies, Reuses
- Data Models with concrete field definitions
- Error Handling with specific scenarios
- Testing Strategy: Unit, Integration, E2E

**Cross-reference (read requirements.md):**
- Every requirement has a corresponding design solution
- No design component without a backing requirement
- Data models cover all entities from requirements

**Quality:**
- No placeholder text
- Consistent component naming
- Error scenarios cover realistic failure modes

### Tasks (`tasks.md`)

**Template compliance:**
- Every task has `- [ ]` checkbox marker
- Every task specifies target file path(s)
- Every task has `_Leverage` field
- Every task has `_Requirements` field
- Every task has `_Prompt` field with: Role, Task, Restrictions, Success
- `_Prompt` starts with "Implement the task for spec {spec-name}, first run spec-workflow-guide..."
- Tasks are atomic (1-3 files each)

**Cross-reference (read requirements.md and design.md):**
- Every requirement has at least one implementing task
- Every design component has at least one creating task
- `_Requirements` IDs match actual requirement IDs
- `_Leverage` paths are plausible
- Task ordering respects dependencies (interfaces before implementations, models before services)

**Quality:**
- No placeholder text
- Task descriptions specific enough for AI agent implementation
- No duplicate tasks

## Output Format

Return to the calling agent:

```
## Spec Review: {spec-name}/{doc-type}.md

### Checks Performed
- Template compliance: {PASS / N issues fixed}
- Cross-references: {PASS / N issues fixed / N/A for requirements}
- Quality: {PASS / N issues fixed}

### Issues Fixed
- [list of specific fixes made, if any]

### Items for User Attention
- [any gaps requiring human judgment, if any]

### Result: READY FOR APPROVAL
```
