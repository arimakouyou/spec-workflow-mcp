import { describe, it, expect } from 'vitest';
import { spawnSync } from 'child_process';
import { cpSync, mkdtempSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';
import { fileURLToPath } from 'url';

// spec-lint.sh(rules/doc-format.md の決定的 lint)の回帰テスト。
// 正常な見本 spec は違反 0 件で通り、lint-cases.sh の各ケース(見本に違反を 1 つ入れたもの)は
// 期待した lint コードで失敗することを確かめる。

const HERE = resolve(fileURLToPath(import.meta.url), '..');
const REPO = resolve(HERE, '../../..');
const SCRIPTS = join(REPO, '.claude-plugin/scripts');
const FIXTURES = join(REPO, 'tests/fixtures/plugin');
const OK = join(FIXTURES, 'todo-ok');
const CASES = join(FIXTURES, 'lint-cases.sh');

function lint(root: string) {
  const r = spawnSync('bash', [join(SCRIPTS, 'spec-lint.sh'), 'todo-api', root], { encoding: 'utf-8' });
  const codes = new Set(
    r.stdout
      .split('\n')
      .filter(Boolean)
      .map((l) => l.split('\t')[0]),
  );
  return { status: r.status, codes, stdout: r.stdout, stderr: r.stderr };
}

function listCases(): string[] {
  const r = spawnSync('bash', ['-c', `source "${CASES}"; lint_cases`], { encoding: 'utf-8' });
  return r.stdout.split('\n').filter(Boolean);
}

/** 見本をコピーしてケースを適用し、期待コードを返す */
function applyCase(name: string): { root: string; expected: string } {
  const root = join(mkdtempSync(join(tmpdir(), 'spec-lint-')), 'p');
  cpSync(OK, root, { recursive: true });
  const r = spawnSync('bash', ['-c', `source "${CASES}"; ROOT="$1"; case_${name}; printf '%s' "$EXPECT"`, '_', root], {
    encoding: 'utf-8',
  });
  return { root, expected: r.stdout.trim() };
}

describe('spec-lint', () => {
  it('正常な見本 spec は違反 0 件', () => {
    const r = lint(OK);
    expect(r.stdout).toBe('');
    expect(r.status).toBe(0);
  });

  const cases = listCases();

  it('ケースが列挙できる', () => {
    expect(cases.length).toBeGreaterThanOrEqual(30);
  });

  for (const name of cases) {
    it(`${name} は期待した lint コードで失敗する`, () => {
      const { root, expected } = applyCase(name);
      expect(expected).toMatch(/^L\d\d$/);
      const r = lint(root);
      expect(r.status).toBe(1);
      expect([...r.codes]).toContain(expected);
    });
  }
});
