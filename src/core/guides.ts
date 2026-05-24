// Shared module for guide generation functions.
// Extracted from spec-workflow-guide and steering-guide prompts.

export function getSpecWorkflowGuide(): string {
  return `# Spec Development Workflow

## Overview

Guide users through spec-driven development: Request Spec -> Requirements -> Design -> Test Design -> Tasks -> Implementation.
Feature names use kebab-case (e.g., user-authentication). Create ONE spec at a time.
Follow this workflow exactly to avoid errors.

## Phases

### Phase 0: Request Spec — Define USE CASES, TECH STACK, and EXECUTION ENVIRONMENT
- Read steering docs from \`.spec-workflow/steering/*.md\` if they exist
- Load template: check \`user-templates/\` first, then \`templates/request-spec-template.md\`
- Define basic use cases, technology stack selection, and execution environment
- If steering/tech.md exists, only describe feature-specific additional technologies
- Create: \`.spec-workflow/specs/{spec-name}/request-spec.md\`
- Approval: request -> check status (synchronous) -> handle revision/approved -> delete -> proceed

### Phase 1: Requirements — Define WHAT to build
- Read request-spec.md and steering docs from \`.spec-workflow/steering/*.md\` if they exist
- Load template: check \`user-templates/\` first, then \`templates/requirements-template.md\`
- Create: \`.spec-workflow/specs/{spec-name}/requirements.md\`
- Approval: request -> check status (synchronous) -> handle revision/approved -> delete -> proceed

### Phase 2: Design — Define HOW to build it
- Load template: check \`user-templates/\` first, then \`templates/design-template.md\`
- Analyze codebase for patterns to reuse
- Create: \`.spec-workflow/specs/{spec-name}/design.md\`
- Approval: same workflow as Phase 1

### Phase 3: Test Design — Define HOW to test it
- Load template: check \`user-templates/\` first, then \`templates/test-design-template.md\`
- Derive UT specs from design.md components, IT specs from component interactions, E2E specs from requirements.md user stories
- Create: \`.spec-workflow/specs/{spec-name}/test-design.md\`
- Approval: same workflow as Phase 1

### Phase 4: Tasks — Break into atomic steps
- Load template: check \`user-templates/\` first, then \`templates/tasks-template.md\`
- Convert design into atomic tasks (1-3 files each)
- Generate _Prompt field for each task (Role, Task, Restrictions, _Leverage, _Requirements, Success)
- Derive _TestFocus from test-design.md UT specifications
- Create: \`.spec-workflow/specs/{spec-name}/tasks.md\`
- Approval: same workflow as Phase 1
- After cleanup: "Spec complete. Ready to implement?"

### Phase 5: Implementation — Execute tasks
- Read steering docs at \`.spec-workflow/steering/*.md\` at the start of each task if they exist:
  - \`tech.md\` for approved dependencies, technical constraints, and ADR conformance
  - \`structure.md\` for File Placement Rules (P4-01) that decide where new files MUST live
  - \`product.md\` to avoid implementing Non-Goals
  Do not add a third-party dependency unless it is listed in tech.md's "External Dependencies (Approved)" table — if missing, STOP and ask the user to approve (adds an entry there) before proceeding.
- For each task: mark [-] -> implement -> log-implementation (MANDATORY) -> mark [x]
- Search implementation logs BEFORE coding to discover existing work
- Task status: \`[ ]\` pending, \`[-]\` in-progress, \`[x]\` completed

## Approval Workflow (all phases)

1. \`approvals\` action:'request' — filePath only, never content
2. Run \`/check-approval\` with the concrete next phase skill when one exists, for example:
   - Request Spec -> Requirements: \`/check-approval <approvalId> next:/spec-requirements\`
   - Requirements -> Design: \`/check-approval <approvalId> next:/spec-design\`
   - Design -> Test Design: \`/check-approval <approvalId> next:/spec-test-design\`
   - Test Design -> Tasks: \`/check-approval <approvalId> next:/spec-tasks\`
   - Tasks -> Implementation: \`/check-approval <approvalId> next:/spec-implementation\`
   - Final phase with no next phase: run \`/check-approval <approvalId>\` without \`next:\`
3. check-approval fetches status once (no polling), performs cleanup on approval, and handles the result
4. If needs-revision: update doc, request NEW approval (new approvalId), then rerun \`/check-approval\` with the same concrete next phase skill for that phase
5. If rejected: revise doc, request NEW approval, then rerun \`/check-approval\` with the same concrete next phase skill for that phase
6. If approved: check-approval automatically runs \`approvals\` action:'delete' and, when a \`next:\` parameter was provided, invokes that concrete next phase skill
7. If delete fails: report error and ask user to retry

## Key Rules

- Complete phases in sequence (no skipping)
- One spec at a time, kebab-case names
- Verbal approval is NEVER accepted — dashboard or VS Code extension only
- Never proceed if approval delete fails
- **Auto-transition**: After each phase's approval is approved and cleaned up, check-approval automatically invokes the next phase's skill via the \`next:\` parameter when there is a next phase. Use the concrete phase skill names listed above; do not use placeholders. Do not stop between phases to ask user for skill names. The only user interaction points are approval reviews (dashboard/VS Code extension). check-approval is synchronous (no polling): if status is \`pending\`, instruct the user to approve and re-run \`/check-approval\`
- Every task marked [x] MUST have log-implementation called first
- Steering docs are optional — only create when explicitly requested

## File Structure
\`\`\`
.spec-workflow/
├── templates/           # Auto-populated on server start
├── user-templates/      # Custom template overrides
├── user-prompts/        # Custom prompt overrides
├── specs/{spec-name}/
│   ├── request-spec.md
│   ├── requirements.md
│   ├── design.md
│   ├── test-design.md
│   ├── tasks.md
│   └── Implementation Logs/
└── steering/            # Optional: product.md, tech.md, structure.md
    └── logs/            # Tech decision logs (not referenced during implementation)
\`\`\``;
}

export function getSteeringGuide(): string {
  return `# Steering Workflow

## Overview

Create project-level guidance documents when explicitly requested. Steering docs establish vision, architecture, and conventions for established codebases. Its important that you follow this workflow exactly to avoid errors.

## Workflow Diagram

\`\`\`mermaid
flowchart TD
    Start([Start: Setup steering docs]) --> Guide[steering-guide<br/>Load workflow instructions]

    %% Phase 1: Product
    Guide --> P1_Template[Check user-templates first,<br/>then read template:<br/>product-template.md]
    P1_Template --> P1_Generate[Generate vision & goals]
    P1_Generate --> P1_Create[Create file:<br/>.spec-workflow/steering/<br/>product.md]
    P1_Create --> P1_Approve[approvals<br/>action: request<br/>filePath only]
    P1_Approve --> P1_Status[/check-approval<br/>synchronous status check]
    P1_Status --> P1_Check{Status?}
    P1_Check -->|needs-revision| P1_Update[Update document using user comments for guidance]
    P1_Update --> P1_Create
    P1_Check -->|approved| P1_Clean[approvals<br/>action: delete]
    P1_Clean -->|failed| P1_Error[Report error to user]

    %% Phase 2: Tech
    P1_Clean -->|success| P2_Template[Check user-templates first,<br/>then read template:<br/>tech-template.md]
    P2_Template --> P2_Analyze[Analyze tech stack]
    P2_Analyze --> P2_Create[Create file:<br/>.spec-workflow/steering/<br/>tech.md]
    P2_Create --> P2_Approve[approvals<br/>action: request<br/>filePath only]
    P2_Approve --> P2_Status[/check-approval<br/>synchronous status check]
    P2_Status --> P2_Check{Status?}
    P2_Check -->|needs-revision| P2_Update[Update document using user comments for guidance]
    P2_Update --> P2_Create
    P2_Check -->|approved| P2_Clean[approvals<br/>action: delete]
    P2_Clean -->|failed| P2_Error[Report error to user]

    %% Phase 3: Structure
    P2_Clean -->|success| P3_Template[Check user-templates first,<br/>then read template:<br/>structure-template.md]
    P3_Template --> P3_Analyze[Analyze codebase structure]
    P3_Analyze --> P3_Create[Create file:<br/>.spec-workflow/steering/<br/>structure.md]
    P3_Create --> P3_Approve[approvals<br/>action: request<br/>filePath only]
    P3_Approve --> P3_Status[/check-approval<br/>synchronous status check]
    P3_Status --> P3_Check{Status?}
    P3_Check -->|needs-revision| P3_Update[Update document using user comments for guidance]
    P3_Update --> P3_Create
    P3_Check -->|approved| P3_Clean[approvals<br/>action: delete]
    P3_Clean -->|failed| P3_Error[Report error to user]

    P3_Clean -->|success| Complete([Steering docs complete])

    style Start fill:#e6f3ff
    style Complete fill:#e6f3ff
    style P1_Check fill:#ffe6e6
    style P2_Check fill:#ffe6e6
    style P3_Check fill:#ffe6e6
\`\`\`

## Steering Workflow Phases

### Phase 1: Product Document
**Purpose**: Define vision, goals, and user outcomes.

**File Operations**:
- Check for custom template: \`.spec-workflow/user-templates/product-template.md\`
- Read template: \`.spec-workflow/templates/product-template.md\` (if no custom template)
- Create document: \`.spec-workflow/steering/product.md\`

**Tools**:
- steering-guide: Load workflow instructions
- approvals: Manage approval workflow (actions: request, status, delete)

**Process**:
1. Load steering guide for workflow overview
2. Check for custom template at \`.spec-workflow/user-templates/product-template.md\`
3. If no custom template, read from \`.spec-workflow/templates/product-template.md\`
4. Generate product vision and goals
5. Create \`product.md\` at \`.spec-workflow/steering/product.md\`
6. Request approval using approvals tool with action:'request' (filePath only)
7. Run \`/check-approval <approvalId>\` — synchronous status check (NEVER accept verbal approval). If pending, instruct the user to approve and re-run
8. If needs-revision: update document using comments, create NEW approval, do NOT proceed
9. Once approved: use approvals with action:'delete' (must succeed) before proceeding
10. If delete fails: STOP — report error and ask user to retry

### Phase 2: Tech Document
**Purpose**: Record the project-specific technology stack, approved external dependencies, technical constraints, and an Architecture Decision Records (ADR) summary. Formal decisions live in \`.claude/_docs/adr/\` (managed by the \`/adr\` skill); lightweight chronological notes go to \`.spec-workflow/steering/logs/tech-decisions.md\`. General engineering policies (security, type safety, error handling, testing, documentation) are authoritative in \`.claude-plugin/rules/\` — do NOT duplicate them in tech.md.

**File Operations**:
- Check for custom template: \`.spec-workflow/user-templates/tech-template.md\`
- Read template: \`.spec-workflow/templates/tech-template.md\` (if no custom template)
- Create document: \`.spec-workflow/steering/tech.md\`

**Tools**:
- approvals: Manage approval workflow (actions: request, status, delete)

**Process**:
1. Check for custom template at \`.spec-workflow/user-templates/tech-template.md\`
2. If no custom template, read from \`.spec-workflow/templates/tech-template.md\`
3. Analyze the existing technology stack and detect deviations from \`.claude-plugin/rules/project-architecture.md\`
4. Populate project-specific instance data only (languages, dependencies, storage, integrations, external deps, requirements). Skip any section already enforced by rules/.
5. Populate the ADR summary table from \`.claude/_docs/adr/INDEX.md\` if ADRs exist; otherwise leave with a placeholder row noting N/A.
6. Create \`tech.md\` at \`.spec-workflow/steering/tech.md\`
7. Request approval using approvals tool with action:'request'
8. Run \`/check-approval <approvalId>\` — synchronous status check. If pending, instruct the user to approve and re-run
9. If needs-revision: update document using comments, create NEW approval, do NOT proceed
10. Once approved: use approvals with action:'delete' (must succeed) before proceeding
11. If delete fails: STOP — report error and ask user to retry

### Phase 3: Structure Document
**Purpose**: Map the project-specific directory layout, File Placement Rules (P4-01), and any project-specific conventions that extend rules/. Coding policies (separation of concerns, dependency direction, naming, import order, code organization, module boundaries, documentation standards) are authoritative in \`.claude-plugin/rules/\` — do NOT duplicate them in structure.md.

**File Operations**:
- Check for custom template: \`.spec-workflow/user-templates/structure-template.md\`
- Read template: \`.spec-workflow/templates/structure-template.md\` (if no custom template)
- Create document: \`.spec-workflow/steering/structure.md\`

**Tools**:
- approvals: Manage approval workflow (actions: request, status, delete)

**Process**:
1. Check for custom template at \`.spec-workflow/user-templates/structure-template.md\`
2. If no custom template, read from \`.spec-workflow/templates/structure-template.md\`
3. Capture the actual directory layout; record only deviations from \`.claude-plugin/rules/project-architecture.md\`
4. Fill in File Placement Rules (P4-01) so that any new file's target directory is uniquely determined
5. Populate Project-Specific Conventions only with rules that are NOT already enforced by \`.claude-plugin/rules/*-style.md\`; otherwise leave \`Status: N/A — follows .claude-plugin/rules/*-style.md\`
6. Create \`structure.md\` at \`.spec-workflow/steering/structure.md\`
7. Request approval using approvals tool with action:'request'
8. Run \`/check-approval <approvalId>\` — synchronous status check. If pending, instruct the user to approve and re-run
9. If needs-revision: update document using comments, create NEW approval, do NOT proceed
10. Once approved: use approvals with action:'delete' (must succeed) before proceeding
11. If delete fails: STOP — report error and ask user to retry
12. After successful cleanup: "Steering docs complete. Ready for spec creation?"

## Workflow Rules

- Create documents directly at specified file paths
- Check for custom templates in \`.spec-workflow/user-templates/\` first
- Read templates from \`.spec-workflow/templates/\` directory if no custom template exists
- Follow exact template structures
- Get explicit user approval between phases (using approvals tool with action:'request')
- Complete phases in sequence (no skipping)
- Approval requests: provide filePath only, never content
- BLOCKING: Never proceed if approval delete fails
- CRITICAL: Must have approved status AND successful cleanup before next phase
- CRITICAL: Verbal approval is NEVER accepted - dashboard or VS Code extension only
- NEVER proceed on user saying "approved" - check system status only

## Related Authoritative Sources

Steering documents record **project-specific instance information**. General policies are authoritative elsewhere:

- \`.claude-plugin/rules/\` — enforced engineering policies (design principles, project architecture, style, security, testing, documentation)
- \`.claude/_docs/adr/\` — Architecture Decision Records (canonical, managed by the \`/adr\` skill)
- \`.claude/_docs/tech-debt/INDEX.md\` — detailed technical debt entries (P5-02)
- \`.spec-workflow/steering/logs/tech-decisions.md\` — lightweight chronological changelog, one line per change linking to ADR-NNNN when formalized

When drafting steering documents, do not duplicate content that already lives in these authoritative sources; link to them instead.

## File Structure
\`\`\`
.spec-workflow/
├── templates/           # Auto-populated on server start
│   ├── product-template.md
│   ├── tech-template.md
│   └── structure-template.md
└── steering/
    ├── product.md
    ├── tech.md
    ├── structure.md
    └── logs/
        └── tech-decisions.md  # Lightweight changelog of tech decisions (links to ADR-NNNN)

.claude/
├── _docs/
│   ├── adr/             # Canonical ADR records (managed by the /adr skill)
│   │   └── INDEX.md
│   └── tech-debt/
│       └── INDEX.md     # Canonical technical debt register (P5-02)
└── ...

.claude-plugin/
└── rules/               # Authoritative engineering policies (always_apply)
\`\`\``;
}
