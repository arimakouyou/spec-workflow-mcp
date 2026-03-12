import { Tool } from '@modelcontextprotocol/sdk/types.js';
import { promises as fs } from 'fs';
import { join, dirname, relative } from 'path';
import { fileURLToPath } from 'url';
import { ToolContext, ToolResponse } from '../types.js';
import { PathUtils } from '../core/path-utils.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Package root: dist/tools/ -> package root
const PACKAGE_ROOT = join(__dirname, '..', '..');
const SKILLS_SOURCE = join(PACKAGE_ROOT, '.claude', 'skills');

export const setupClaudeSkillsTool: Tool = {
  name: 'setup-claude-skills',
  description: `Install skill files into a project's .claude/skills/ directory. This is a FILE COPY operation only — it does NOT start any workflow or create any spec documents.

# Instructions
This tool copies .claude/skills/ files from the spec-workflow-mcp package into the target project directory. It is a one-time setup step, not a workflow step. Do NOT call spec-workflow-guide or start any spec creation process when this tool is requested. Just copy the files and report the result.`,
  inputSchema: {
    type: 'object',
    properties: {
      projectPath: {
        type: 'string',
        description: 'Target project path. Defaults to the configured project path.'
      },
      dryRun: {
        type: 'boolean',
        description: 'If true, list files that would be copied without actually copying.'
      }
    },
    additionalProperties: false
  },
  annotations: {
    title: 'Setup Claude Skills',
    destructiveHint: false,
  }
};

/**
 * Recursively collect all files under a directory, returning paths relative to the base.
 */
async function collectFiles(dir: string, base: string): Promise<string[]> {
  const results: string[] = [];
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch {
    return results;
  }
  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      const sub = await collectFiles(fullPath, base);
      results.push(...sub);
    } else {
      results.push(relative(base, fullPath));
    }
  }
  return results;
}

export async function setupClaudeSkillsHandler(args: any, context: ToolContext): Promise<ToolResponse> {
  const targetProject = PathUtils.translatePath(args.projectPath || context.projectPath);
  const dryRun = args.dryRun === true;

  // Verify source skills directory exists
  try {
    await fs.access(SKILLS_SOURCE);
  } catch {
    return {
      success: false,
      message: `Skills source directory not found at ${SKILLS_SOURCE}. Ensure the package is installed correctly.`
    };
  }

  // Collect all skill files
  const relativeFiles = await collectFiles(SKILLS_SOURCE, SKILLS_SOURCE);
  if (relativeFiles.length === 0) {
    return {
      success: false,
      message: 'No skill files found in the package.'
    };
  }

  const targetSkillsDir = join(targetProject, '.claude', 'skills');

  if (dryRun) {
    return {
      success: true,
      message: `Dry run: ${relativeFiles.length} files would be copied to ${targetSkillsDir}`,
      data: {
        targetDir: targetSkillsDir,
        files: relativeFiles
      }
    };
  }

  // Copy files
  const copied: string[] = [];
  const errors: string[] = [];

  for (const relPath of relativeFiles) {
    const srcPath = join(SKILLS_SOURCE, relPath);
    const destPath = join(targetSkillsDir, relPath);

    try {
      await fs.mkdir(dirname(destPath), { recursive: true });
      const content = await fs.readFile(srcPath, 'utf-8');
      await fs.writeFile(destPath, content, 'utf-8');
      copied.push(relPath);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      errors.push(`${relPath}: ${msg}`);
    }
  }

  if (errors.length > 0 && copied.length === 0) {
    return {
      success: false,
      message: `Failed to copy skills: ${errors.join(', ')}`
    };
  }

  return {
    success: true,
    message: `Copied ${copied.length} skill files to ${targetSkillsDir}${errors.length > 0 ? ` (${errors.length} errors)` : ''}`,
    data: {
      targetDir: targetSkillsDir,
      copied,
      errors: errors.length > 0 ? errors : undefined,
      skills: [
        'spec-requirements',
        'spec-design',
        'spec-tasks',
        'spec-implement',
        'spec-review',
        'spec-impl-test-write',
        'spec-impl-test-run',
        'spec-impl-code',
        'spec-impl-review',
        'tdd-skills'
      ]
    },
    nextSteps: [
      'Claude Code skills are now available in your project',
      'Use /spec-requirements to start a new spec',
      'Use /spec-implement to implement tasks with TDD',
      'Skills will be auto-detected by Claude Code from .claude/skills/'
    ]
  };
}
