import { Tool } from '@modelcontextprotocol/sdk/types.js';
import { promises as fs } from 'fs';
import { join, dirname, relative } from 'path';
import { fileURLToPath } from 'url';
import { ToolContext, ToolResponse } from '../types.js';
import { PathUtils } from '../core/path-utils.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Package root: dist/tools/ -> package root
const PACKAGE_ROOT = join(__dirname, '..', '..');
const CLAUDE_SOURCE = join(PACKAGE_ROOT, '.claude');

// Files to exclude from copying (project-specific settings)
const EXCLUDED_FILES = new Set(['settings.json', 'settings.local.json']);

export const setupClaudeSkillsTool: Tool = {
  name: 'setup-claude-skills',
  description: `Install .claude/ configuration files (skills, rules, agents, commands, _docs) into a target project. This is a FILE COPY operation only — it does NOT start any workflow or create any spec documents.

# Instructions
This tool copies .claude/ files from the spec-workflow-mcp package into the target project directory. It copies skills/, rules/, agents/, commands/, and _docs/ — but excludes settings.json and settings.local.json (project-specific). It is a one-time setup step, not a workflow step. Do NOT call spec-workflow-guide or start any spec creation process when this tool is requested. Just copy the files and report the result.`,
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

  // Verify source .claude directory exists
  try {
    await fs.access(CLAUDE_SOURCE);
  } catch {
    return {
      success: false,
      message: `Source .claude directory not found at ${CLAUDE_SOURCE}. Ensure the package is installed correctly.`
    };
  }

  // Collect all files from .claude/, excluding settings files
  const allFiles = await collectFiles(CLAUDE_SOURCE, CLAUDE_SOURCE);
  const relativeFiles = allFiles.filter(f => !EXCLUDED_FILES.has(f));
  if (relativeFiles.length === 0) {
    return {
      success: false,
      message: 'No files found in the package .claude/ directory.'
    };
  }

  // Categorize files for reporting
  const categories: Record<string, string[]> = {};
  for (const f of relativeFiles) {
    const category = f.split('/')[0] || 'root';
    if (!categories[category]) categories[category] = [];
    categories[category].push(f);
  }

  const targetClaudeDir = join(targetProject, '.claude');

  if (dryRun) {
    return {
      success: true,
      message: `Dry run: ${relativeFiles.length} files would be copied to ${targetClaudeDir}`,
      data: {
        targetDir: targetClaudeDir,
        files: relativeFiles,
        categories: Object.fromEntries(
          Object.entries(categories).map(([k, v]) => [k, v.length])
        ),
        excluded: Array.from(EXCLUDED_FILES)
      }
    };
  }

  // Copy files
  const copied: string[] = [];
  const errors: string[] = [];

  for (const relPath of relativeFiles) {
    const srcPath = join(CLAUDE_SOURCE, relPath);
    const destPath = join(targetClaudeDir, relPath);

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
      message: `Failed to copy files: ${errors.join(', ')}`
    };
  }

  // Categorize copied files for response
  const copiedCategories: Record<string, number> = {};
  for (const f of copied) {
    const category = f.split('/')[0] || 'root';
    copiedCategories[category] = (copiedCategories[category] || 0) + 1;
  }

  return {
    success: true,
    message: `Copied ${copied.length} files to ${targetClaudeDir}${errors.length > 0 ? ` (${errors.length} errors)` : ''}`,
    data: {
      targetDir: targetClaudeDir,
      copied,
      copiedCategories,
      errors: errors.length > 0 ? errors : undefined,
      excluded: Array.from(EXCLUDED_FILES),
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
        'tdd-skills',
        'tdd-skills-rust',
        'knowhow-capture',
        'integration-test'
      ]
    },
    nextSteps: [
      'Claude Code configuration is now available in your project',
      'Use /spec-requirements to start a new spec',
      'Use /spec-implement to implement tasks with TDD',
      'Skills will be auto-detected by Claude Code from .claude/skills/',
      'Rules from .claude/rules/ will be applied based on file path patterns',
      'Agents from .claude/agents/ are available for subagent workflows'
    ]
  };
}
