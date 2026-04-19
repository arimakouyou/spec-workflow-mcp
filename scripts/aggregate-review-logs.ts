#!/usr/bin/env node
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { aggregateReviewProcess } from '../src/core/review-log-parser.js';

function usage(): never {
  process.stderr.write(
    'Usage: aggregate-review-logs <specName> <taskId>\n' +
      '  → reviewProcess JSON を stdout に出力。review log が無ければ空 aggregate。\n',
  );
  process.exit(1);
}

function sanitizeTaskId(taskId: string): string {
  return taskId.replace(/[./]/g, '-');
}

function main(): void {
  const [specName, taskId] = process.argv.slice(2);
  if (!specName || !taskId) usage();

  if (!/^[a-z0-9][a-z0-9-]*$/.test(specName)) {
    process.stderr.write(`invalid spec name: ${specName}\n`);
    process.exit(1);
  }

  const reviewFile = join(
    '.spec-workflow',
    'specs',
    specName,
    'Review Logs',
    `task-${sanitizeTaskId(taskId)}_reviews.md`,
  );

  if (!existsSync(reviewFile)) {
    process.stdout.write(
      JSON.stringify(
        {
          reworkCount: 0,
          reviewOutcome: 'unknown',
          findings: [],
        },
        null,
        2,
      ),
    );
    process.stdout.write('\n');
    return;
  }

  const content = readFileSync(reviewFile, 'utf8');
  const aggregate = aggregateReviewProcess(content);
  process.stdout.write(JSON.stringify(aggregate, null, 2));
  process.stdout.write('\n');
}

main();
