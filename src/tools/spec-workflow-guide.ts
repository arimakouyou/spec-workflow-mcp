import { Tool } from '@modelcontextprotocol/sdk/types.js';
import { ToolContext, ToolResponse } from '../types.js';

export const specWorkflowGuideTool: Tool = {
  name: 'spec-workflow-guide',
  description: `Load essential spec workflow instructions to guide feature development from idea to implementation.

# Instructions
Call this tool FIRST when users request spec creation, feature development, or mention specifications. This provides the complete workflow sequence (Requirements → Design → Test Design → Tasks → Implementation) that must be followed. Always load before any other spec tools to ensure proper workflow understanding. It's important that you follow this workflow exactly to avoid errors.

NOTE: Do NOT call this tool when the user requests setup-claude-skills. That tool is a standalone file-copy operation and does not require loading the workflow guide.`,
  inputSchema: {
    type: 'object',
    properties: {},
    additionalProperties: false
  },
  annotations: {
    title: 'Spec Workflow Guide',
    readOnlyHint: true,
  }
};

export async function specWorkflowGuideHandler(args: any, context: ToolContext): Promise<ToolResponse> {
  // Dashboard URL is populated from registry in server.ts
  const dashboardMessage = context.dashboardUrl ?
    `Monitor progress on dashboard: ${context.dashboardUrl}` :
    'Please start the dashboard with: spec-workflow-mcp --dashboard';

  return {
    success: true,
    message: 'Complete spec workflow guide loaded - follow this workflow exactly',
    data: {
      guide: getSpecWorkflowGuide(),
      dashboardUrl: context.dashboardUrl,
      dashboardAvailable: !!context.dashboardUrl
    },
    nextSteps: [
      'Follow sequence: Requirements → Design → Test Design → Tasks → Implementation',
      'Load templates with get-template-context first',
      'Request approval after each document',
      'Use MCP tools only',
      dashboardMessage
    ]
  };
}

function getSpecWorkflowGuide(): string {
  return `# Spec Development Workflow

## Overview

Guide users through spec-driven development: Requirements -> Design -> Test Design -> Tasks -> Implementation.
Feature names use kebab-case (e.g., user-authentication). Create ONE spec at a time.
Follow this workflow exactly to avoid errors.

## Phases

### Phase 1: Requirements — Define WHAT to build
- Read steering docs from \`.spec-workflow/steering/*.md\` if they exist
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
2. \`approvals\` action:'status' — poll until approved/needs-revision
3. If needs-revision: update doc, create NEW approval, do NOT proceed
4. If approved: \`approvals\` action:'delete' — must succeed before next phase
5. If delete fails: STOP, return to polling

## Key Rules

- Complete phases in sequence (no skipping)
- One spec at a time, kebab-case names
- Verbal approval is NEVER accepted — dashboard or VS Code extension only
- Never proceed if approval delete fails
- Every task marked [x] MUST have log-implementation called first
- Steering docs are optional — only create when explicitly requested

## File Structure
\`\`\`
.spec-workflow/
├── templates/           # Auto-populated on server start
├── user-templates/      # Custom template overrides
├── user-prompts/        # Custom prompt overrides
├── specs/{spec-name}/
│   ├── requirements.md
│   ├── design.md
│   ├── test-design.md
│   ├── tasks.md
│   └── Implementation Logs/
└── steering/            # Optional: product.md, tech.md, structure.md
\`\`\``;
}