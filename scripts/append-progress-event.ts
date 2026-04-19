#!/usr/bin/env node
import { appendFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import {
  computeTaskState,
  syncTasksMarkdown,
} from '../src/core/tasks-auto-update.js';
import { readdirSync } from 'node:fs';
import { basename } from 'node:path';

const VALID_EVENTS = new Set(['BEGIN', 'END', 'VERIFIED', 'FAILED', 'COMPLETE']);
const STEP_ID_PATTERN = /^[a-z0-9-]+$/;

function usage(): never {
  process.stderr.write(
    'Usage: append-progress-event <specName> <taskId> <EVENT> <stepId> [meta_json]\n',
  );
  process.stderr.write(
    '  EVENT ∈ {BEGIN,END,VERIFIED,FAILED,COMPLETE}\n',
  );
  process.stderr.write(
    '  meta_json は単一行 JSON (省略時 {}). 例: \'{"reason":"..."}\'\n',
  );
  process.exit(1);
}

function sanitizeTaskId(taskId: string): string {
  return taskId.replace(/[./]/g, '-');
}

function desanitizeTaskId(sanitized: string): string {
  return sanitized.replace(/-/g, '.');
}

function syncTasks(specName: string): void {
  const specDir = join('.spec-workflow', 'specs', specName);
  const tasksPath = join(specDir, 'tasks.md');
  const progressDir = join(specDir, 'Implementation Logs');

  if (!existsSync(tasksPath) || !existsSync(progressDir)) {
    return;
  }

  const entries = readdirSync(progressDir);
  const taskStates = new Map<string, 'pending' | 'in-progress' | 'completed'>();

  for (const entry of entries) {
    const match = basename(entry).match(/^task-(.+)_progress\.md$/);
    if (match === null) continue;
    const sanitized = match[1];
    if (sanitized === undefined) continue;
    const taskId = desanitizeTaskId(sanitized);
    const content = readFileSync(join(progressDir, entry), 'utf8');
    const state = computeTaskState(content);
    if (state === 'pending') continue;
    taskStates.set(taskId, state);
  }

  if (taskStates.size === 0) return;

  const before = readFileSync(tasksPath, 'utf8');
  const { updatedMarkdown, updates } = syncTasksMarkdown(before, taskStates);
  if (updates.length === 0) return;
  writeFileSync(tasksPath, updatedMarkdown, 'utf8');
}

function main(): void {
  const [specName, taskId, event, stepId, metaJson] = process.argv.slice(2);

  if (!specName || !taskId || !event || !stepId) usage();
  if (!VALID_EVENTS.has(event)) {
    process.stderr.write(`invalid event: ${event}\n`);
    process.exit(1);
  }
  if (!STEP_ID_PATTERN.test(stepId)) {
    process.stderr.write(`invalid step id: ${stepId}\n`);
    process.exit(1);
  }
  if (!/^[a-z0-9][a-z0-9-]*$/.test(specName)) {
    process.stderr.write(`invalid spec name: ${specName}\n`);
    process.exit(1);
  }

  let meta: Record<string, unknown> = {};
  if (metaJson !== undefined && metaJson !== '') {
    try {
      const parsed = JSON.parse(metaJson) as unknown;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('not an object');
      }
      meta = parsed as Record<string, unknown>;
    } catch (e) {
      process.stderr.write(`invalid meta JSON: ${String(e)}\n`);
      process.exit(1);
    }
  }

  const sanitized = sanitizeTaskId(taskId);
  const progressDir = join(
    '.spec-workflow',
    'specs',
    specName,
    'Implementation Logs',
  );
  const progressFile = join(progressDir, `task-${sanitized}_progress.md`);

  mkdirSync(progressDir, { recursive: true });

  if (!existsSync(progressFile)) {
    const header =
      `# Progress Log: Task ${taskId}\n` +
      `# spec=${specName} task=${taskId}\n` +
      `# format: <ISO8601>\\t<EVENT>\\t<STEP_ID>\\t<META_JSON>\n` +
      `# hook + skill が append する append-only ログ (手編集禁止)\n`;
    writeFileSync(progressFile, header, 'utf8');
  }

  const ts = new Date().toISOString();
  const line = `${ts}\t${event}\t${stepId}\t${JSON.stringify(meta)}\n`;
  appendFileSync(progressFile, line, 'utf8');

  process.stdout.write(`appended ${event} ${stepId} to ${progressFile}\n`);

  syncTasks(specName);

  if (event === 'COMPLETE') {
    cleanupCheckpoints(specName, taskId);
  }
}

function cleanupCheckpoints(specName: string, taskId: string): void {
  const prefix = `spec-impl/${specName}/task-${sanitizeTaskId(taskId)}/`;
  let tags: string[];
  try {
    const out = execFileSync('git', ['tag', '-l', `${prefix}*`], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    tags = out
      .split('\n')
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
  } catch {
    return;
  }

  let deleted = 0;
  for (const tag of tags) {
    try {
      execFileSync('git', ['tag', '-d', tag], {
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      deleted += 1;
    } catch {
      // best-effort、失敗しても続行
    }
  }

  if (deleted > 0) {
    process.stdout.write(
      `cleaned up ${deleted} checkpoint tag(s) under ${prefix}\n`,
    );
  }
}

main();
