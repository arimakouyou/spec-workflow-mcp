import { describe, it, expect } from 'vitest';
import { spawnSync } from 'child_process';
import { cpSync, mkdtempSync, readFileSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';
import { fileURLToPath } from 'url';

// spec-sigcheck.sh(design のシグネチャを承認前にコンパイルで確かめる)の回帰テスト。
// 見本 spec はコンパイルに成功し、sigcheck-cases.sh の各ケース(specrail で実装時に初めて
// 表に出た設計段階の欠陥)は、期待した ID に対応づいたコンパイルエラーになることを確かめる。
// cargo が無い環境、または crate を取得できない環境では実行しない。

const HERE = resolve(fileURLToPath(import.meta.url), '..');
const REPO = resolve(HERE, '../../..');
const SCRIPT = join(REPO, '.claude-plugin/scripts/spec-sigcheck.sh');
const FIXTURES = join(REPO, 'tests/fixtures/plugin');
const OK = join(FIXTURES, 'todo-ok');
const CASES = join(FIXTURES, 'sigcheck-cases.sh');

const hasCargo = spawnSync('cargo', ['--version']).status === 0;

function sigcheck(root: string) {
  const r = spawnSync('bash', [SCRIPT, 'todo-api', root], { encoding: 'utf-8' });
  const rows = r.stdout
    .split('\n')
    .filter((l) => l.startsWith('SIG\t'))
    .map((l) => {
      const [, id, msg] = l.split('\t');
      return { id, msg };
    });
  return { status: r.status, rows, stdout: r.stdout, stderr: r.stderr };
}

function listCases(): string[] {
  const r = spawnSync('bash', ['-c', `source "${CASES}"; sigcheck_cases`], { encoding: 'utf-8' });
  return r.stdout.split('\n').filter(Boolean);
}

function applyCase(name: string) {
  const root = join(mkdtempSync(join(tmpdir(), 'spec-sigcheck-')), 'p');
  cpSync(OK, root, { recursive: true });
  const r = spawnSync(
    'bash',
    ['-c', `source "${CASES}"; ROOT="$1"; case_${name}; printf '%s\\t%s' "$EXPECT_ID" "$EXPECT"`, '_', root],
    { encoding: 'utf-8' },
  );
  const [expectId, expectMsg] = r.stdout.split('\t');
  return { root, expectId, expectMsg };
}

describe.skipIf(!hasCargo)('spec-sigcheck', () => {
  it('見本 spec の design はコンパイルに成功する', { timeout: 600_000 }, () => {
    const r = sigcheck(OK);
    expect(r.rows).toEqual([]);
    expect(r.status).toBe(0);
  });

  for (const name of listCases()) {
    it(`${name} は設計段階でコンパイルエラーになる`, { timeout: 600_000 }, () => {
      const { root, expectId, expectMsg } = applyCase(name);
      const design = readFileSync(join(root, '.spec-workflow/specs/todo-api/design.md'), 'utf-8');
      expect(design, 'ケースが見本を書き換えていない').not.toBe(readFileSync(join(OK, '.spec-workflow/specs/todo-api/design.md'), 'utf-8'));
      const r = sigcheck(root);
      const detail = `stdout:\n${r.stdout}\nstderr:\n${r.stderr}`;
      expect(r.status, detail).toBe(1);
      expect(r.rows.some((row) => row.id === expectId && row.msg.includes(expectMsg)), detail).toBe(true);
    });
  }
});
