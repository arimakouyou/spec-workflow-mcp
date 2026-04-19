#!/usr/bin/env node
import { appendFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const VALID_SOURCES = new Set([
  'pre-push-review',
  'handle-pr-comments',
  'codex-review',
  'phase-review-team',
]);
const VALID_ACTIONS = new Set(['commit', 'rework', 'escalate']);

function usage(): never {
  process.stderr.write(
    'Usage: append-review-log <specName> <taskId> <source> <attempt> <action> <categories_json> <summary>\n' +
      '  source ∈ {pre-push-review, handle-pr-comments, codex-review, phase-review-team}\n' +
      '  action ∈ {commit, rework, escalate}\n' +
      '  categories_json: 文字列配列の JSON (例: \'["naming","security"]\' / \'[]\')\n' +
      '  summary: 自由記述 (タブ文字は NG, 改行は \\n エスケープ)\n',
  );
  process.exit(1);
}

function sanitizeTaskId(taskId: string): string {
  return taskId.replace(/[./]/g, '-');
}

function main(): void {
  const [specName, taskId, source, attemptStr, action, categoriesJson, ...rest] =
    process.argv.slice(2);
  const summary = rest.join(' ');

  if (
    !specName ||
    !taskId ||
    !source ||
    !attemptStr ||
    !action ||
    !categoriesJson ||
    !summary
  ) {
    usage();
  }
  if (!/^[a-z0-9][a-z0-9-]*$/.test(specName)) {
    process.stderr.write(`invalid spec name: ${specName}\n`);
    process.exit(1);
  }
  if (!VALID_SOURCES.has(source)) {
    process.stderr.write(`invalid source: ${source}\n`);
    process.exit(1);
  }
  if (!VALID_ACTIONS.has(action)) {
    process.stderr.write(`invalid action: ${action}\n`);
    process.exit(1);
  }
  const attempt = Number.parseInt(attemptStr, 10);
  if (!Number.isInteger(attempt) || attempt < 1) {
    process.stderr.write(`attempt must be positive integer: ${attemptStr}\n`);
    process.exit(1);
  }
  try {
    const parsed = JSON.parse(categoriesJson) as unknown;
    if (!Array.isArray(parsed) || parsed.some((x) => typeof x !== 'string')) {
      throw new Error('not string array');
    }
  } catch (e) {
    process.stderr.write(`categories_json must be a JSON string array: ${String(e)}\n`);
    process.exit(1);
  }

  if (summary.includes('\t')) {
    process.stderr.write('summary must not contain tab character\n');
    process.exit(1);
  }

  const sanitized = sanitizeTaskId(taskId);
  const reviewDir = join('.spec-workflow', 'specs', specName, 'Review Logs');
  const reviewFile = join(reviewDir, `task-${sanitized}_reviews.md`);

  mkdirSync(reviewDir, { recursive: true });

  if (!existsSync(reviewFile)) {
    const header =
      `# Review Log: Task ${taskId}\n` +
      `# spec=${specName} task=${taskId}\n` +
      `# format: <ISO8601>\\t<SOURCE>\\t<ATTEMPT>\\t<ACTION>\\t<CATEGORIES_JSON>\\t<SUMMARY>\n` +
      `# pre-push-review / handle-pr-comments / codex:review / phase-review-team が append する\n`;
    writeFileSync(reviewFile, header, 'utf8');
  }

  const ts = new Date().toISOString();
  const safeSummary = summary.replace(/\n/g, '\\n');
  const lineStr = `${ts}\t${source}\t${attempt}\t${action}\t${categoriesJson}\t${safeSummary}\n`;
  appendFileSync(reviewFile, lineStr, 'utf8');

  process.stdout.write(`appended review entry to ${reviewFile}\n`);
}

main();
