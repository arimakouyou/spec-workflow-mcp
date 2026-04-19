#!/usr/bin/env node
import { execFileSync } from 'node:child_process';

function sanitizeTaskId(taskId: string): string {
  return taskId.replace(/[./]/g, '-');
}

function usage(): never {
  process.stderr.write(
    'Usage: cleanup-spec-checkpoints <specName> [taskId]\n' +
      '  - specName のみ → spec 配下全 checkpoint tag を削除\n' +
      '  - specName + taskId → 指定 task 配下の tag のみ削除\n',
  );
  process.exit(1);
}

function listTags(pattern: string): string[] {
  try {
    const out = execFileSync('git', ['tag', '-l', pattern], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return out
      .split('\n')
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
  } catch {
    return [];
  }
}

function deleteTag(tag: string): boolean {
  try {
    execFileSync('git', ['tag', '-d', tag], {
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return true;
  } catch {
    return false;
  }
}

function main(): void {
  const [specName, taskId] = process.argv.slice(2);
  if (!specName) usage();

  if (!/^[a-z0-9][a-z0-9-]*$/.test(specName)) {
    process.stderr.write(`invalid spec name: ${specName}\n`);
    process.exit(1);
  }

  const prefix =
    taskId !== undefined && taskId !== ''
      ? `spec-impl/${specName}/task-${sanitizeTaskId(taskId)}/`
      : `spec-impl/${specName}/`;

  const tags = listTags(`${prefix}*`);
  if (tags.length === 0) {
    process.stdout.write(`no tags matching ${prefix}\n`);
    return;
  }

  let deleted = 0;
  const failed: string[] = [];
  for (const tag of tags) {
    if (deleteTag(tag)) {
      deleted += 1;
    } else {
      failed.push(tag);
    }
  }

  process.stdout.write(`deleted ${deleted} tag(s) matching ${prefix}\n`);
  if (failed.length > 0) {
    process.stderr.write(
      `failed to delete ${failed.length} tag(s): ${failed.join(', ')}\n`,
    );
    process.exit(1);
  }
}

main();
