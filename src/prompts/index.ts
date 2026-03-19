import { Prompt, PromptMessage, ListPromptsResult, GetPromptResult } from '@modelcontextprotocol/sdk/types.js';
import { promises as fs } from 'fs';
import { join } from 'path';
import { ToolContext } from '../types.js';
import { PromptDefinition, PromptHandler } from './types.js';

// Import individual prompt definitions
import { createSpecPrompt } from './create-spec.js';
import { createSteeringDocPrompt } from './create-steering-doc.js';
import { implementTaskPrompt } from './implement-task.js';
import { specStatusPrompt } from './spec-status.js';
import { injectSpecWorkflowGuidePrompt } from './inject-spec-workflow-guide.js';
import { injectSteeringGuidePrompt } from './inject-steering-guide.js';
import { refreshTasksPrompt } from './refresh-tasks.js';

// Registry of all prompts
const promptDefinitions: PromptDefinition[] = [
  createSpecPrompt,
  createSteeringDocPrompt,
  implementTaskPrompt,
  specStatusPrompt,
  injectSpecWorkflowGuidePrompt,
  injectSteeringGuidePrompt,
  refreshTasksPrompt
];

/**
 * Get all prompt definitions (used by dashboard API)
 */
export function getPromptDefinitions(): PromptDefinition[] {
  return promptDefinitions;
}

/**
 * Get all registered prompts
 */
export function registerPrompts(): Prompt[] {
  return promptDefinitions.map(def => def.prompt);
}

/**
 * Handle prompts/list request
 */
export async function handlePromptList(): Promise<ListPromptsResult> {
  return {
    prompts: registerPrompts()
  };
}

/**
 * Read user prompt override file if it exists
 */
async function readUserPromptOverride(projectPath: string, name: string): Promise<{ customContent: string; lastModified: string } | null> {
  try {
    const filePath = join(projectPath, '.spec-workflow', 'user-prompts', `${name}.json`);
    const content = await fs.readFile(filePath, 'utf-8');
    const data = JSON.parse(content);
    if (data.customContent) {
      return { customContent: data.customContent, lastModified: data.lastModified || '' };
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Replace template variables in custom prompt content
 */
function replaceTemplateVariables(content: string, args: Record<string, any>, context: ToolContext): string {
  let result = content;
  // Replace context variables
  result = result.replace(/\{\{projectPath\}\}/g, context.projectPath || '');
  result = result.replace(/\{\{dashboardUrl\}\}/g, context.dashboardUrl || '');
  // Replace all argument variables
  for (const [key, value] of Object.entries(args)) {
    if (typeof value === 'string') {
      result = result.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), value);
    }
  }
  return result;
}

/**
 * Handle prompts/get request
 */
export async function handlePromptGet(
  name: string,
  args: Record<string, any> = {},
  context: ToolContext
): Promise<GetPromptResult> {
  const promptDef = promptDefinitions.find(def => def.prompt.name === name);

  if (!promptDef) {
    throw new Error(`Prompt not found: ${name}`);
  }

  // Check for user prompt override
  if (context.projectPath) {
    const override = await readUserPromptOverride(context.projectPath, name);
    if (override) {
      const customText = replaceTemplateVariables(override.customContent, args, context);
      return {
        messages: [{
          role: 'user',
          content: { type: 'text', text: customText }
        }]
      };
    }
  }

  try {
    const messages = await promptDef.handler(args, context);
    return { messages };
  } catch (error: any) {
    throw new Error(`Failed to generate prompt messages: ${error.message}`);
  }
}
