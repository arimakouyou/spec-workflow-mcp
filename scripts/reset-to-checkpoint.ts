#!/usr/bin/env node
import { execFileSync, spawnSync } from 'node:child_process';

function sanitizeTaskId(taskId: string): string {
  return taskId.replace(/[./]/g, '-');
}

function usage(): never {
  process.stderr.write(
    'Usage: reset-to-checkpoint <specName> <taskId> <stepId> <attempt> [--force]\n' +
      '  破壊的操作: 現在 HEAD を spec-impl-backup/<timestamp> へ退避したあと\n' +
      '  指定 checkpoint tag へ git reset --hard する。\n' +
      '  --force 指定時のみ実行。未指定なら tag の存在確認と退避先の表示のみ。\n',
  );
  process.exit(1);
}

function tagExists(tag: string): boolean {
  const result = spawnSync('git', ['rev-parse', '--verify', `refs/tags/${tag}`], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return result.status === 0;
}

function currentHead(): string {
  return execFileSync('git', ['rev-parse', 'HEAD'], {
    encoding: 'utf8',
  }).trim();
}

function runGit(args: string[]): void {
  execFileSync('git', args, { stdio: ['ignore', 'inherit', 'inherit'] });
}

function main(): void {
  const args = process.argv.slice(2);
  const force = args.includes('--force');
  const positional = args.filter((a) => a !== '--force');
  const [specName, taskId, stepId, attempt] = positional;

  if (!specName || !taskId || !stepId || !attempt) usage();
  if (!/^[a-z0-9][a-z0-9-]*$/.test(specName)) {
    process.stderr.write(`invalid spec name: ${specName}\n`);
    process.exit(1);
  }
  if (!/^[a-z0-9-]+$/.test(stepId)) {
    process.stderr.write(`invalid step id: ${stepId}\n`);
    process.exit(1);
  }
  if (!/^\d+$/.test(attempt)) {
    process.stderr.write(`attempt must be positive integer: ${attempt}\n`);
    process.exit(1);
  }

  const tag = `spec-impl/${specName}/task-${sanitizeTaskId(taskId)}/step-${stepId}/attempt-${attempt}`;

  if (!tagExists(tag)) {
    process.stderr.write(`checkpoint tag not found: ${tag}\n`);
    process.exit(1);
  }

  const head = currentHead();
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const backupTag = `spec-impl-backup/${ts}`;

  process.stdout.write(`checkpoint tag    : ${tag}\n`);
  process.stdout.write(`current HEAD      : ${head}\n`);
  process.stdout.write(`planned backup tag: ${backupTag}\n`);

  if (!force) {
    process.stdout.write(
      '\n--force を付けて再実行すると以下を実行します:\n' +
        `  1. git tag ${backupTag} ${head}\n` +
        `  2. git reset --hard ${tag}\n`,
    );
    return;
  }

  process.stdout.write('\nexecuting reset...\n');
  runGit(['tag', backupTag, head]);
  runGit(['reset', '--hard', tag]);
  process.stdout.write(
    `\nreset complete. rollback: git reset --hard ${backupTag}\n`,
  );
}

main();
