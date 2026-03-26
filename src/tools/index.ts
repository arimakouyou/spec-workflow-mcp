import { Tool } from '@modelcontextprotocol/sdk/types.js';
import { approvalsTool, approvalsHandler } from './approvals.js';
import { ToolContext, ToolResponse, MCPToolResponse, toMCPResponse } from '../types.js';

export function registerTools(): Tool[] {
  return [approvalsTool];
}

export async function handleToolCall(name: string, args: any, context: ToolContext): Promise<MCPToolResponse> {
  let response: ToolResponse;
  let isError = false;

  try {
    switch (name) {
      case 'approvals':
        response = await approvalsHandler(args, context);
        break;
      default:
        throw new Error(`Unknown tool: ${name}`);
    }

    isError = !response.success;

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    response = {
      success: false,
      message: `Tool execution failed: ${errorMessage}`
    };
    isError = true;
  }

  return toMCPResponse(response, isError);
}
