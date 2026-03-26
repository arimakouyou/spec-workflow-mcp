// ガイド関数の共有モジュール
// spec-workflow-guide と steering-guide からガイドテキスト生成ロジックを抽出

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
- Approval: request -> poll status -> handle revision/approved -> delete -> proceed

### Phase 1: Requirements — Define WHAT to build
- Read request-spec.md and steering docs from \`.spec-workflow/steering/*.md\` if they exist
- Load template: check \`user-templates/\` first, then \`templates/requirements-template.md\`
- Create: \`.spec-workflow/specs/{spec-name}/requirements.md\`
- Approval: request -> poll status -> handle revision/approved -> delete -> proceed

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
- For each task: mark [-] -> implement -> log-implementation (MANDATORY) -> mark [x]
- Search implementation logs BEFORE coding to discover existing work
- Task status: \`[ ]\` pending, \`[-]\` in-progress, \`[x]\` completed

## Approval Workflow (all phases)

1. \`approvals\` action:'request' — filePath only, never content
2. Start automated polling: \`/loop 1m /check-approval <approvalId>\`
3. The check-approval skill handles status polling, cleanup on approval, and loop termination
4. If needs-revision: update doc, create NEW approval with new \`/loop\`
5. If approved: check-approval automatically runs \`approvals\` action:'delete' and stops the loop
6. If delete fails: check-approval retries on next loop iteration

## Key Rules

- Complete phases in sequence (no skipping)
- One spec at a time, kebab-case names
- Verbal approval is NEVER accepted — dashboard or VS Code extension only
- Never proceed if approval delete fails
- **Auto-transition**: After each phase's approval is approved and cleaned up, automatically proceed to the next phase. Do not stop between phases to ask user for skill names. The only user interaction points are approval reviews (dashboard/VS Code extension)
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
    P1_Approve --> P1_Status[approvals<br/>action: status<br/>poll status]
    P1_Status --> P1_Check{Status?}
    P1_Check -->|needs-revision| P1_Update[Update document using user comments for guidance]
    P1_Update --> P1_Create
    P1_Check -->|approved| P1_Clean[approvals<br/>action: delete]
    P1_Clean -->|failed| P1_Status

    %% Phase 2: Tech
    P1_Clean -->|success| P2_Template[Check user-templates first,<br/>then read template:<br/>tech-template.md]
    P2_Template --> P2_Analyze[Analyze tech stack]
    P2_Analyze --> P2_Create[Create file:<br/>.spec-workflow/steering/<br/>tech.md]
    P2_Create --> P2_Approve[approvals<br/>action: request<br/>filePath only]
    P2_Approve --> P2_Status[approvals<br/>action: status<br/>poll status]
    P2_Status --> P2_Check{Status?}
    P2_Check -->|needs-revision| P2_Update[Update document using user comments for guidance]
    P2_Update --> P2_Create
    P2_Check -->|approved| P2_Clean[approvals<br/>action: delete]
    P2_Clean -->|failed| P2_Status

    %% Phase 3: Structure
    P2_Clean -->|success| P3_Template[Check user-templates first,<br/>then read template:<br/>structure-template.md]
    P3_Template --> P3_Analyze[Analyze codebase structure]
    P3_Analyze --> P3_Create[Create file:<br/>.spec-workflow/steering/<br/>structure.md]
    P3_Create --> P3_Approve[approvals<br/>action: request<br/>filePath only]
    P3_Approve --> P3_Status[approvals<br/>action: status<br/>poll status]
    P3_Status --> P3_Check{Status?}
    P3_Check -->|needs-revision| P3_Update[Update document using user comments for guidance]
    P3_Update --> P3_Create
    P3_Check -->|approved| P3_Clean[approvals<br/>action: delete]
    P3_Clean -->|failed| P3_Status

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
7. Poll status using approvals with action:'status' until approved/needs-revision (NEVER accept verbal approval)
8. If needs-revision: update document using comments, create NEW approval, do NOT proceed
9. Once approved: use approvals with action:'delete' (must succeed) before proceeding
10. If delete fails: STOP - return to polling

### Phase 2: Tech Document
**Purpose**: Document project-level technology stack and architecture. Technology selection rationale and decision history should be recorded in \`.spec-workflow/steering/logs/tech-decisions.md\`, not in the tech.md document itself.

**File Operations**:
- Check for custom template: \`.spec-workflow/user-templates/tech-template.md\`
- Read template: \`.spec-workflow/templates/tech-template.md\` (if no custom template)
- Create document: \`.spec-workflow/steering/tech.md\`

**Tools**:
- approvals: Manage approval workflow (actions: request, status, delete)

**Process**:
1. Check for custom template at \`.spec-workflow/user-templates/tech-template.md\`
2. If no custom template, read from \`.spec-workflow/templates/tech-template.md\`
3. Analyze existing technology stack
4. Document architectural decisions and patterns
5. Create \`tech.md\` at \`.spec-workflow/steering/tech.md\`
6. Request approval using approvals tool with action:'request'
7. Poll status using approvals with action:'status' until approved/needs-revision
8. If needs-revision: update document using comments, create NEW approval, do NOT proceed
9. Once approved: use approvals with action:'delete' (must succeed) before proceeding
10. If delete fails: STOP - return to polling

### Phase 3: Structure Document
**Purpose**: Map codebase organization and patterns.

**File Operations**:
- Check for custom template: \`.spec-workflow/user-templates/structure-template.md\`
- Read template: \`.spec-workflow/templates/structure-template.md\` (if no custom template)
- Create document: \`.spec-workflow/steering/structure.md\`

**Tools**:
- approvals: Manage approval workflow (actions: request, status, delete)

**Process**:
1. Check for custom template at \`.spec-workflow/user-templates/structure-template.md\`
2. If no custom template, read from \`.spec-workflow/templates/structure-template.md\`
3. Analyze directory structure and file organization
4. Document coding patterns and conventions
5. Create \`structure.md\` at \`.spec-workflow/steering/structure.md\`
6. Request approval using approvals tool with action:'request'
7. Poll status using approvals with action:'status' until approved/needs-revision
8. If needs-revision: update document using comments, create NEW approval, do NOT proceed
9. Once approved: use approvals with action:'delete' (must succeed) before proceeding
10. If delete fails: STOP - return to polling
11. After successful cleanup: "Steering docs complete. Ready for spec creation?"

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
        └── tech-decisions.md  # 技術選定の経緯・根拠（実装時参照不要）
\`\`\``;
}
