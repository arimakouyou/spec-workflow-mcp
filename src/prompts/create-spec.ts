import { Prompt, PromptMessage } from '@modelcontextprotocol/sdk/types.js';
import { PromptDefinition } from './types.js';
import { ToolContext } from '../types.js';

const prompt: Prompt = {
  name: 'create-spec',
  title: 'Create Specification Document',
  description: 'Guide for creating spec documents directly in the file system. Shows how to use templates and create requirements, design, test-design, or tasks documents at the correct paths.',
  arguments: [
    {
      name: 'specName',
      description: 'Feature name in kebab-case (e.g., user-authentication, data-export)',
      required: true
    },
    {
      name: 'documentType',
      description: 'Type of document to create: request-spec, requirements, design, test-design, or tasks',
      required: true
    },
    {
      name: 'description',
      description: 'Brief description of what this spec should accomplish',
      required: false
    }
  ]
};

async function handler(args: Record<string, any>, context: ToolContext): Promise<PromptMessage[]> {
  const { specName, documentType, description } = args;
  
  if (!specName || !documentType) {
    throw new Error('specName and documentType are required arguments');
  }

  const validDocTypes = ['request-spec', 'requirements', 'design', 'test-design', 'tasks'];
  // ダッシュボードのプレビュー用サンプルコンテキストではバリデーションをスキップ
  const isPreviewContext = context.projectPath === '{{projectPath}}';
  if (!isPreviewContext && !validDocTypes.includes(documentType)) {
    throw new Error(`documentType must be one of: ${validDocTypes.join(', ')}`);
  }

  // Build context-aware messages
  const messages: PromptMessage[] = [
    {
      role: 'user',
      content: {
        type: 'text',
        text: `Create a ${documentType} document for the "${specName}" feature using the spec-workflow methodology.

**Context:**
- Project: ${context.projectPath}
- Feature: ${specName}
- Document type: ${documentType}
${description ? `- Description: ${description}` : ''}
${context.dashboardUrl ? `- Dashboard: ${context.dashboardUrl}` : ''}

**Instructions:**
1. First, read the template at: .spec-workflow/templates/${documentType}-template.md
2. Follow the template structure exactly - this ensures consistency across the project
3. Create comprehensive content that follows spec-driven development best practices
4. Include all required sections from the template
5. Use clear, actionable language
6. Create the document at: .spec-workflow/specs/${specName}/${documentType}.md
7. After creating, use approvals tool with action:'request' to get user approval

**File Paths:**
- Template location: .spec-workflow/templates/${documentType}-template.md
- Document destination: .spec-workflow/specs/${specName}/${documentType}.md

**Workflow Guidelines:**
- Request spec documents define USE CASES, TECH STACK, and EXECUTION ENVIRONMENT
- Requirements documents define WHAT needs to be built
- Design documents define HOW it will be built
- Test design documents define HOW TO TEST the feature (UT/IT/E2E specifications)
- Tasks documents break down implementation into actionable steps
- Sequence: Request Spec → Requirements → Design → Test Design → Tasks
- Each document builds upon the previous one in sequence
- Templates are automatically updated on server start

${documentType === 'tasks' ? `
**Special Instructions for Tasks Document:**
- Group tasks by phases using "## Phase N: Name" headings
- Each task line must follow this exact format: \`- [ ] N.N Description\`
  - N.N = Phase number.Task number (e.g., 1.1, 1.2, 2.1, 2.3.1)
  - Use numeric IDs — do NOT omit them
  - Use hyphen (-) bullets with checkbox \`[ ]\`, NOT asterisks
- For each task, include these metadata fields (all wrapped in underscores):
  - \`_Prompt: Role: [role] | Task: [description] | Restrictions: [constraints] | Success: [criteria]_\`
  - \`_Requirements: [comma-separated requirement IDs]_\`
  - \`_Leverage: [comma-separated file paths to reuse]_\`
  - \`_TestFocus: [what tests should cover in the RED phase]_\`
  - \`_DependsOn: [comma-separated task IDs within same phase]_\` (if applicable)
- End each phase with a PhaseReview task:
  - \`_PhaseReview: true_\`
  - Include a \`_Prompt\` for review and commit instructions
- Tasks should be atomic (1-3 files each) and in logical order
- Make prompts specific to the project context and requirements
- Do NOT create standalone test tasks — TDD handles testing automatically in each task

**Implementation Logging:**
- When implementing tasks, developers will use the \`/log-implementation\` skill to record what was done
- Implementation logs appear in the dashboard's "Logs" tab for easy reference
- These logs prevent implementation details from being lost in chat history
- Good task descriptions help developers write better implementation summaries
` : ''}

Please read the ${documentType} template and create the comprehensive document at the specified path.`
      }
    }
  ];

  return messages;
}

export const createSpecPrompt: PromptDefinition = {
  prompt,
  handler
};