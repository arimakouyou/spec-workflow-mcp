import { spawnSync, SpawnSyncReturns } from 'child_process';
import { cpSync, existsSync, mkdtempSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';
import { fileURLToPath } from 'url';
import { SpecLedger } from '../../core/spec-ledger.js';

// プラグインのスクリプト・フックを vitest から動かすための共通処理

const HERE = resolve(fileURLToPath(import.meta.url), '..');
export const REPO = resolve(HERE, '../../..');
export const PLUGIN = join(REPO, '.claude-plugin');
export const SCRIPTS = join(PLUGIN, 'scripts');
export const HOOKS = join(PLUGIN, 'hooks');
export const FIXTURES = join(REPO, 'tests/fixtures/plugin');
export const SPEC = 'todo-api';
export const S = `.spec-workflow/specs/${SPEC}`;

export function run(script: string, args: string[], opts: { cwd?: string; env?: Record<string, string>; input?: string } = {}): SpawnSyncReturns<string> {
  return spawnSync('bash', [script.startsWith('/') ? script : join(SCRIPTS, script), ...args], {
    encoding: 'utf-8',
    cwd: opts.cwd,
    input: opts.input,
    env: { ...process.env, ...opts.env }
  });
}

/** フックを JSON 入力で実行する */
export function runHook(hook: string, root: string, input: Record<string, unknown>) {
  return run(join(HOOKS, hook), [], {
    input: JSON.stringify({ cwd: root, ...input }),
    env: { CLAUDE_PLUGIN_ROOT: PLUGIN, CLAUDE_PROJECT_DIR: root }
  });
}

export function git(root: string, args: string[]): string {
  const r = spawnSync('git', ['-c', 'user.name=test', '-c', 'user.email=test@example.invalid', ...args], { cwd: root, encoding: 'utf-8' });
  if (r.status !== 0) throw new Error(r.stderr);
  return r.stdout;
}

/** 見本 spec を独立した git リポジトリとしてコピーする */
export function copyFixture(name = 'todo-ok'): string {
  const root = join(mkdtempSync(join(tmpdir(), 'spec-plugin-')), 'p');
  cpSync(join(FIXTURES, name), root, { recursive: true });
  git(root, ['init', '-q']);
  git(root, ['add', '-A']);
  git(root, ['commit', '-q', '-m', 'init']);
  return root;
}

export function ledgerFor(root: string): SpecLedger {
  return new SpecLedger(join(root, '.spec-workflow/approvals'), async (rel) => (existsSync(join(root, rel)) ? join(root, rel) : null));
}

/** steering と 4 文書をすべて承認済みにする */
export async function approveAll(root: string): Promise<SpecLedger> {
  const l = ledgerFor(root);
  const files = [
    '.spec-workflow/steering/product.md', '.spec-workflow/steering/tech.md', '.spec-workflow/steering/structure.md',
    `${S}/request-spec.md`, `${S}/requirements.md`, `${S}/design.md`, `${S}/test-design.md`
  ];
  let n = 0;
  for (const fp of files) {
    const meta = await l.checkRequest(fp);
    await l.recordApproval({ id: `a${++n}`, filePath: fp, metadata: { ledger: meta } });
  }
  return l;
}

export const hasCargo = spawnSync('cargo', ['--version']).status === 0;
