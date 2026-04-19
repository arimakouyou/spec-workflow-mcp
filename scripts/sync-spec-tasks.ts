#!/usr/bin/env node
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join, basename } from 'node:path';
import {
  computeTaskState,
  syncTasksMarkdown,
  type TaskState,
} from '../src/core/tasks-auto-update.js';

function usage(): never {
  process.stderr.write('Usage: sync-spec-tasks <specName>\n');
  process.exit(1);
}

function desanitizeTaskId(sanitized: string): string {
  return sanitized.replace(/-/g, '.');
}

function main(): void {
  const specName = process.argv[2];
  if (!specName || typeof specName !== 'string') {
    usage();
  }

  if (!/^[a-z0-9][a-z0-9-]*$/.test(specName)) {
    process.stderr.write(`invalid spec name: ${specName}\n`);
    process.exit(1);
  }

  const specDir = join('.spec-workflow', 'specs', specName);
  const tasksPath = join(specDir, 'tasks.md');
  const progressDir = join(specDir, 'Implementation Logs');

  if (!existsSync(tasksPath)) {
    process.stderr.write(`tasks.md not found: ${tasksPath}\n`);
    process.exit(1);
  }

  if (!existsSync(progressDir)) {
    return;
  }

  const entries = readdirSync(progressDir);
  const taskStates = new Map<string, TaskState>();

  for (const entry of entries) {
    const match = basename(entry).match(/^task-(.+)_progress\.md$/);
    if (match === null) {
      continue;
    }
    const sanitized = match[1];
    if (sanitized === undefined) {
      continue;
    }
    const taskId = desanitizeTaskId(sanitized);
    const content = readFileSync(join(progressDir, entry), 'utf8');
    const state = computeTaskState(content);
    if (state === 'pending') continue;
    taskStates.set(taskId, state);
  }

  if (taskStates.size === 0) {
    return;
  }

  const before = readFileSync(tasksPath, 'utf8');
  const { updatedMarkdown, updates, missingTaskIds } = syncTasksMarkdown(
    before,
    taskStates,
  );

  if (updates.length === 0) {
    return;
  }

  writeFileSync(tasksPath, updatedMarkdown, 'utf8');

  for (const u of updates) {
    process.stdout.write(`${u.taskId}: ${u.before} -> ${u.after}\n`);
  }

  if (missingTaskIds.length > 0) {
    process.stderr.write(
      `warning: ${missingTaskIds.length} progress log(s) have no matching task in tasks.md: ${missingTaskIds.join(', ')}\n`,
    );
  }
}

main();
