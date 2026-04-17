import { Prompt, PromptMessage } from '@modelcontextprotocol/sdk/types.js';
import { PromptDefinition } from './types.js';
import { ToolContext } from '../types.js';
import { getSpecWorkflowGuide } from '../core/guides.js';

const prompt: Prompt = {
  name: 'inject-spec-workflow-guide',
  title: 'Inject Spec Workflow Guide into Context',
  description: 'Injects the complete spec-driven development workflow guide into the conversation context. This provides immediate access to all workflow phases, tools, and best practices without requiring separate tool calls.'
};

async function handler(args: Record<string, any>, context: ToolContext): Promise<PromptMessage[]> {
  const guide = getSpecWorkflowGuide();

  const dashboardUrl = context.dashboardUrl;
  const dashboardMessage = dashboardUrl ?
    `Monitor progress on dashboard: ${dashboardUrl}` :
    'Please start the dashboard with: spec-workflow-mcp --dashboard';

  const nextSteps = [
    'Follow sequence: spec-request-spec → spec-requirements → spec-design → spec-test-design → spec-tasks → spec-implement',
    'Read templates from .spec-workflow/templates/ (or user-templates/ for overrides)',
    'Request approval after each document using the approvals MCP tool',
    'Use your client adapter (skills, saved prompts, command aliases, or workspace instructions) for workflow phases, and the approvals MCP tool for approval management',
    dashboardMessage
  ];

  const messages: PromptMessage[] = [
    {
      role: 'user',
      content: {
        type: 'text',
        text: `Please review and follow this comprehensive spec-driven development workflow guide:

${guide}

**Current Context:**
- Project: ${context.projectPath}
${dashboardUrl ? `- Dashboard: ${dashboardUrl}` : '- Dashboard: Please start the dashboard or use VS Code extension "Spec Workflow MCP"'}

**Next Steps:**
${nextSteps.map(step => `- ${step}`).join('\n')}

**Important Instructions:**
1. This guide has been injected into your context for immediate reference
2. Follow the workflow sequence exactly: Request Spec → Requirements → Design → Test Design → Tasks → Implementation
3. Use the phase capability names (spec-request-spec, spec-requirements, etc.) through your client's adapter to execute each phase
4. Always request approval between phases using the approvals MCP tool
5. Never proceed to the next phase without successful approval cleanup

Please acknowledge that you've reviewed this workflow guide and are ready to help with spec-driven development.`
      }
    }
  ];

  return messages;
}

export const injectSpecWorkflowGuidePrompt: PromptDefinition = {
  prompt,
  handler
};
