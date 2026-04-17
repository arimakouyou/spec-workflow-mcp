import { Prompt, PromptMessage } from '@modelcontextprotocol/sdk/types.js';
import { PromptDefinition } from './types.js';
import { ToolContext } from '../types.js';

const prompt: Prompt = {
  name: 'create-steering-doc',
  title: 'Create Steering Document',
  description: 'Guide for creating project steering documents (product, tech, structure) directly in the file system. These provide high-level project guidance.',
  arguments: [
    {
      name: 'docType',
      description: 'Type of steering document: product, tech, or structure',
      required: true
    },
    {
      name: 'scope',
      description: 'Scope of the steering document (e.g., frontend, backend, full-stack)',
      required: false
    }
  ]
};

async function handler(args: Record<string, any>, context: ToolContext): Promise<PromptMessage[]> {
  const { docType, scope } = args;
  
  if (!docType) {
    throw new Error('docType is a required argument');
  }

  const validDocTypes = ['product', 'tech', 'structure'];
  // Skip validation for the dashboard preview sample context.
  const isPreviewContext = context.projectPath === '{{projectPath}}';
  if (!isPreviewContext && !validDocTypes.includes(docType)) {
    throw new Error(`docType must be one of: ${validDocTypes.join(', ')}`);
  }

  const messages: PromptMessage[] = [
    {
      role: 'user',
      content: {
        type: 'text',
        text: `Create a ${docType} steering document for the project.

**Context:**
- Project: ${context.projectPath}
- Steering document type: ${docType}
${scope ? `- Scope: ${scope}` : ''}
${context.dashboardUrl ? `- Dashboard: ${context.dashboardUrl}` : ''}

**Instructions:**
1. First, read the template at: .spec-workflow/templates/${docType}-template.md
2. Check if steering docs exist at: .spec-workflow/steering/
3. Before writing, review \`.claude-plugin/rules/\` (authoritative engineering policies). DO NOT duplicate any policy already enforced there — link to the relevant rule file instead.
4. Fill the template with project-specific instance information only (what this project chose, where files live, which ADRs exist, which external dependencies are approved).
5. Create the document at: .spec-workflow/steering/${docType}.md
6. After creating, use approvals tool with action:'request' to get user approval

**File Paths:**
- Template location: .spec-workflow/templates/${docType}-template.md
- Document destination: .spec-workflow/steering/${docType}.md

**Steering Document Types:**
- **product**: Defines project purpose, target users, non-goals, product principles, and success metrics.
- **tech**: Records the technology stack, approved external dependencies, technical constraints, and an ADR summary. Formal decisions live in .claude/_docs/adr/ (managed by the /adr skill); lightweight changelog entries go to .spec-workflow/steering/logs/tech-decisions.md.
- **structure**: Maps the project-specific directory layout, File Placement Rules (P4-01), and any Project-Specific Conventions that extend .claude-plugin/rules/*-style.md.

**Key Principles:**
- Keep content project-specific and instance-level. Defer general policies to .claude-plugin/rules/.
- Prefer tables with one fact per row. Reserve prose for Purpose / Principles / Vision only.
- Use \`Status: N/A — {{reason}}\` instead of leaving sections blank.
- Templates are automatically updated on server start.

Please read the ${docType} template and create a comprehensive steering document at the specified path.`
      }
    }
  ];

  return messages;
}

export const createSteeringDocPrompt: PromptDefinition = {
  prompt,
  handler
};