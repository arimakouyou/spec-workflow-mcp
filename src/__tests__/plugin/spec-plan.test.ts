import { describe, it, expect } from 'vitest';
import { spawnSync } from 'child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';
import { fileURLToPath } from 'url';
import { SpecLedger } from '../../core/spec-ledger.js';

// spec-plan.sh / spec-next.sh / spec-brief.sh の回帰テスト。
// tasks.md は design / test-design とコミット trailer だけから決定的に生成され、
// 次のタスクは台帳が ready のときだけ返り、brief は承認済み文書の断片だけで組み立てられることを確かめる。

const HERE = resolve(fileURLToPath(import.meta.url), '..');
const REPO = resolve(HERE, '../../..');
const SCRIPTS = join(REPO, '.claude-plugin/scripts');
const FIXTURES = join(REPO, 'tests/fixtures/plugin');
const SPEC = 'todo-api';
const S = `.spec-workflow/specs/${SPEC}`;

function run(script: string, args: string[], cwd?: string) {
  return spawnSync('bash', [join(SCRIPTS, script), ...args], { encoding: 'utf-8', cwd });
}

function git(root: string, args: string[]) {
  const r = spawnSync('git', ['-c', 'user.name=test', '-c', 'user.email=test@example.invalid', ...args], {
    cwd: root,
    encoding: 'utf-8'
  });
  if (r.status !== 0) throw new Error(r.stderr);
  return r.stdout;
}

/** 見本を独立した git リポジトリとしてコピーする */
function copyFixture(): string {
  const root = join(mkdtempSync(join(tmpdir(), 'spec-plan-')), 'p');
  cpSync(join(FIXTURES, 'todo-ok'), root, { recursive: true });
  git(root, ['init', '-q']);
  git(root, ['add', '-A']);
  git(root, ['commit', '-q', '-m', 'init']);
  return root;
}

/** steering と 4 文書をすべて承認済みにする */
async function approveAll(root: string) {
  const l = new SpecLedger(join(root, '.spec-workflow/approvals'), async (rel) => (existsSync(join(root, rel)) ? join(root, rel) : null));
  const files = [
    '.spec-workflow/steering/product.md', '.spec-workflow/steering/tech.md', '.spec-workflow/steering/structure.md',
    `${S}/request-spec.md`, `${S}/requirements.md`, `${S}/design.md`, `${S}/test-design.md`
  ];
  let n = 0;
  for (const fp of files) {
    const meta = await l.checkRequest(fp);
    await l.recordApproval({ id: `a${++n}`, filePath: fp, metadata: { ledger: meta } });
  }
}

describe('spec-plan', () => {
  it('見本の tasks.md は正解ファイルと一致する(決定的に生成される)', () => {
    const r = run('spec-plan.sh', [SPEC, join(FIXTURES, 'todo-ok'), '--stdout']);
    expect(r.status).toBe(0);
    expect(r.stdout).toBe(readFileSync(join(FIXTURES, 'todo-ok.tasks.md'), 'utf-8'));
  });

  it('--check は手編集された tasks.md を検出する', () => {
    const root = copyFixture();
    expect(run('spec-plan.sh', [SPEC, root]).status).toBe(0);
    expect(run('spec-plan.sh', [SPEC, root, '--check']).status).toBe(0);
    const p = join(root, S, 'tasks.md');
    writeFileSync(p, readFileSync(p, 'utf-8').replace('- [ ] DES-2 ', '- [x] DES-2 '));
    expect(run('spec-plan.sh', [SPEC, root, '--check']).status).toBe(1);
  });

  it('完了状態はコミット trailer から求め、Spec-Reopen で再オープンする', () => {
    const root = copyFixture();
    git(root, ['commit', '-q', '--allow-empty', '-m', 'done', '-m', `Spec: ${SPEC}\nSpec-Task: P0-TOOLS`]);
    const done = run('spec-plan.sh', [SPEC, root, '--tsv']).stdout;
    expect(done).toMatch(/^P0-TOOLS\t.*\tdone$/m);
    git(root, ['commit', '-q', '--allow-empty', '-m', 'reopen', '-m', `Spec: ${SPEC}\nSpec-Reopen: P0-TOOLS`]);
    expect(run('spec-plan.sh', [SPEC, root, '--tsv']).stdout).toMatch(/^P0-TOOLS\t.*\topen$/m);
  });
});

describe('spec-next', () => {
  it('仕様が ready でなければ exit 3', () => {
    expect(run('spec-next.sh', [SPEC, copyFixture()]).status).toBe(3);
  });

  it('ready なら未完了の先頭タスクを返し、完了すると次に進む', async () => {
    const root = copyFixture();
    await approveAll(root);
    const first = run('spec-next.sh', [SPEC, root]);
    expect(first.status).toBe(0);
    expect(first.stdout.split('\t')[0]).toBe('P0-TOOLS');
    git(root, ['commit', '-q', '--allow-empty', '-m', 'done', '-m', `Spec: ${SPEC}\nSpec-Task: P0-TOOLS`]);
    expect(run('spec-next.sh', [SPEC, root]).stdout.split('\t')[0]).toBe('DES-1');
  });
});

describe('spec-brief', () => {
  it('DES の brief は対象・依存先・受入基準・そのテスト・使うテストダブルだけを含む', () => {
    const r = run('spec-brief.sh', [SPEC, 'DES-4', join(FIXTURES, 'todo-ok')]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('### DES-4: Todo サービス');
    expect(r.stdout).toContain('### DES-3: Todo ストア');
    expect(r.stdout).toContain('- REQ-1.2: IF');
    expect(r.stdout).toContain('#### UT-4.4: 拒否したタイトルはストアに渡さない');
    expect(r.stdout).toContain('### TST-2: 記録するストア');
    expect(r.stdout).not.toContain('#### UT-2.1');
    expect(r.stdout).not.toContain('### IT-1');
  });

  it('IT の brief は対象 API・テスト支援・ライブラリ契約を含む', () => {
    const r = run('spec-brief.sh', [SPEC, 'P2-IT', join(FIXTURES, 'todo-ok')]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('### IT-4: title 以外の項目を含む本文は 422 を返す');
    expect(r.stdout).toContain('### API-1: POST /todos');
    expect(r.stdout).toContain('### TST-1: テストサーバー');
    expect(r.stdout).toContain('### DEP-1: axum');
  });
});
