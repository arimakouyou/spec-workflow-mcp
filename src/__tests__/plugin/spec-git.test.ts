import { describe, it, expect } from 'vitest';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { join } from 'path';
import { approveAll, copyFixture, git, ledgerFor, run, S, SPEC } from './helpers.js';

// spec-git.sh(唯一のコミット経路とゲート G0-G9)の回帰テスト。
// テストコマンドは tech.md で `true` に差し替え、ゲートの判定だけを確かめる。

const TODO_RS = `impl Title {
    pub fn parse(raw: &str) -> Result<Title, TodoError> {
        todo!()
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}
`;

const TESTS_RS = ['UT-2.1', 'UT-2.2', 'UT-2.3', 'UT-2.4', 'UT-2.5'].map((id) => `// @test ${id}\n#[test]\nfn t_${id.replace(/[-.]/g, '_')}() {}\n`).join('\n');

/** テストコマンドを速いものに差し替えた見本を、承認済み・記録済みにする */
async function prepared(ut = 'true'): Promise<string> {
  const root = copyFixture();
  const tech = join(root, '.spec-workflow/steering/tech.md');
  writeFileSync(
    tech,
    readFileSync(tech, 'utf-8')
      .replace(/^\| UT \| .* \|$/m, `| UT | ${ut} |`)
      .replace(/^\| IT \| .* \|$/m, '| IT | true |')
      .replace(/^\| E2E \| .* \|$/m, '| E2E | true |')
      .replace(/^\| SMK \| .* \|$/m, '| SMK | true |')
      .replace(/^\| format \| .* \|$/m, '| format | - |')
      .replace(/^\| lint \| .* \|$/m, '| lint | - |')
  );
  await approveAll(root);
  expect(run('spec-git.sh', ['docs', 'steering'], { cwd: root }).status).toBe(0);
  expect(run('spec-git.sh', ['docs', SPEC], { cwd: root }).status).toBe(0);
  return root;
}

function writeImpl(root: string, opts: { src?: string; tests?: string } = {}) {
  mkdirSync(join(root, 'src/domain'), { recursive: true });
  writeFileSync(join(root, 'src/domain/todo.rs'), opts.src ?? TODO_RS);
  writeFileSync(join(root, 'src/domain/todo_tests.rs'), opts.tests ?? TESTS_RS);
}

function writeRuns(root: string, task: string, runs: Record<string, unknown>) {
  const dir = join(root, S, 'runs', task);
  mkdirSync(dir, { recursive: true });
  for (const [name, body] of Object.entries(runs)) writeFileSync(join(dir, `${name}.json`), JSON.stringify(body));
}

const okRuns = {
  impl: { task: 'DES-2', status: 'done', tests: { files: ['src/domain/todo_tests.rs'] } },
  verify: { task: 'DES-2', verdict: 'pass', findings: [] },
  review: { task: 'DES-2', verdict: 'commit', findings: [], rf: ['Title の検証をまとめる'], handoffs: [{ to: 'DES-4', text: 'Title::parse は前後の空白を除く' }] }
};

const sg = (root: string, ...args: string[]) => run('spec-git.sh', args, { cwd: root });

async function started(): Promise<string> {
  const root = await prepared();
  expect(sg(root, 'start', SPEC, 'DES-2').status).toBe(0);
  writeImpl(root);
  expect(sg(root, 'checkpoint', SPEC, 'DES-2', 'src/domain/todo_tests.rs').status).toBe(0);
  return root;
}

describe('spec-git commit', () => {
  it('ゲートを満たすと trailer 付きで 1 コミットし、tasks.md・タスクログ・backlog・申し送りを同梱する', async () => {
    const root = await started();
    writeRuns(root, 'DES-2', okRuns);
    const r = sg(root, 'commit', SPEC, 'DES-2');
    expect(r.stderr).toBe('');
    expect(r.status).toBe(0);
    const log = git(root, ['log', '-1', '--format=%B']);
    expect(log).toContain(`Spec: ${SPEC}`);
    expect(log).toContain('Spec-Task: DES-2');
    expect(log).toMatch(/Spec-Inputs: [0-9a-f]{12}/);
    expect(readFileSync(join(root, S, 'tasks.md'), 'utf-8')).toContain('- [x] DES-2 ');
    expect(existsSync(join(root, S, 'task-logs/DES-2.md'))).toBe(true);
    expect(readFileSync(join(root, S, 'refactor-backlog.md'), 'utf-8')).toContain('| RF-001 | DES-2 | open | Title の検証をまとめる |');
    expect(readFileSync(join(root, S, 'handoffs.jsonl'), 'utf-8')).toContain('"to":"DES-4"');
    expect(git(root, ['status', '--porcelain'])).toBe('');
    // runs/ は git に載らない
    expect(git(root, ['ls-files', `${S}/runs`])).toBe('');
  });

  it('G0: start していないタスクはコミットできない', async () => {
    const root = await prepared();
    writeImpl(root);
    writeRuns(root, 'DES-2', okRuns);
    expect(sg(root, 'commit', SPEC, 'DES-2').stderr).toContain('G0');
  });

  it('G2: review-worker の commit 判定が無ければコミットできない', async () => {
    const root = await started();
    writeRuns(root, 'DES-2', { impl: okRuns.impl, verify: okRuns.verify });
    expect(sg(root, 'commit', SPEC, 'DES-2').stderr).toContain('G2');
  });

  it('G3: タスクの範囲外のファイルを変更するとコミットできない', async () => {
    const root = await started();
    mkdirSync(join(root, 'src/http'), { recursive: true });
    writeFileSync(join(root, 'src/http/api.rs'), '// out of scope\n');
    writeRuns(root, 'DES-2', okRuns);
    const r = sg(root, 'commit', SPEC, 'DES-2');
    expect(r.stderr).toContain('G3');
    expect(r.stderr).toContain('src/http/api.rs');
  });

  it('G4: design の Interfaces と違うシグネチャはコミットできない', async () => {
    const root = await prepared();
    expect(sg(root, 'start', SPEC, 'DES-2').status).toBe(0);
    writeImpl(root, { src: TODO_RS.replace('parse(raw: &str)', 'parse(raw: String)') });
    expect(sg(root, 'checkpoint', SPEC, 'DES-2', 'src/domain/todo_tests.rs').status).toBe(0);
    writeRuns(root, 'DES-2', okRuns);
    const r = sg(root, 'commit', SPEC, 'DES-2');
    expect(r.stderr).toContain('G4');
    expect(r.stderr).toContain('fnparse(raw:&str)->Result<Title,TodoError>');
  });

  it('G5: テストの @test ID が test-design と一致しなければコミットできない', async () => {
    const root = await prepared();
    expect(sg(root, 'start', SPEC, 'DES-2').status).toBe(0);
    writeImpl(root, { tests: TESTS_RS.replace('// @test UT-2.5', '// UT-2.5 は書かなかった') });
    expect(sg(root, 'checkpoint', SPEC, 'DES-2', 'src/domain/todo_tests.rs').status).toBe(0);
    writeRuns(root, 'DES-2', okRuns);
    expect(sg(root, 'commit', SPEC, 'DES-2').stderr).toContain('G5');
  });

  it('G6: RED 以降にテストを変えるとコミットできない', async () => {
    const root = await started();
    writeFileSync(join(root, 'src/domain/todo_tests.rs'), TESTS_RS + '\n// loosened\n');
    writeRuns(root, 'DES-2', okRuns);
    expect(sg(root, 'commit', SPEC, 'DES-2').stderr).toContain('G6');
  });

  it('G7: テストが通らなければコミットできない', async () => {
    const root = await prepared('false');
    expect(sg(root, 'start', SPEC, 'DES-2').status).toBe(0);
    writeImpl(root);
    expect(sg(root, 'checkpoint', SPEC, 'DES-2', 'src/domain/todo_tests.rs').status).toBe(0);
    writeRuns(root, 'DES-2', okRuns);
    expect(sg(root, 'commit', SPEC, 'DES-2').stderr).toContain('G7');
  });

  it('G0: 前のタスクの残りがある作業ツリーでは開始できない', async () => {
    const root = await started();
    expect(sg(root, 'start', SPEC, 'DES-3').stderr).toContain('G0');
  });
});

describe('spec-git verdict / reopen', () => {
  const verdict = (root: string, task: string, body: unknown) =>
    run('spec-git.sh', ['verdict', SPEC, task], { cwd: root, input: JSON.stringify(body) });

  it('verdict は形式を検査して review.json に記録する', async () => {
    const root = await prepared();
    expect(verdict(root, 'DES-2', { task: 'DES-2', verdict: 'maybe' }).status).toBe(1);
    expect(verdict(root, 'DES-2', { task: 'DES-2', verdict: 'rework' }).status).toBe(1);
    expect(verdict(root, 'DES-2', { task: 'DES-3', verdict: 'commit' }).status).toBe(1);
    expect(verdict(root, 'DES-2', { task: 'DES-2', verdict: 'rework', rework_from: 'green', findings: [] }).status).toBe(0);
    expect(JSON.parse(readFileSync(join(root, S, 'runs/DES-2/review.json'), 'utf-8')).verdict).toBe('rework');
  });

  it('完了済みのタスクを再オープンすると未完了に戻り、rf_done は backlog の行を done にする', async () => {
    const root = await started();
    writeRuns(root, 'DES-2', okRuns);
    expect(sg(root, 'commit', SPEC, 'DES-2').status).toBe(0);
    expect(readFileSync(join(root, S, 'tasks.md'), 'utf-8')).toContain('- [x] DES-2 ');

    expect(sg(root, 'reopen', SPEC, 'DES-2', 'Title の仕様変更').status).toBe(0);
    expect(git(root, ['log', '-1', '--format=%B'])).toContain('Spec-Reopen: DES-2');
    expect(readFileSync(join(root, S, 'tasks.md'), 'utf-8')).toContain('- [ ] DES-2 ');
    expect(sg(root, 'reopen', SPEC, 'DES-2').status).toBe(1);

    // P1-REFACTOR が RF-001 を消化する
    expect(sg(root, 'start', SPEC, 'P1-REFACTOR').status).toBe(0);
    writeRuns(root, 'P1-REFACTOR', {
      impl: { task: 'P1-REFACTOR', status: 'done', tests: { files: [] }, rf_done: ['RF-001'] },
      verify: { task: 'P1-REFACTOR', verdict: 'pass' },
      review: { task: 'P1-REFACTOR', verdict: 'commit' }
    });
    const r = sg(root, 'commit', SPEC, 'P1-REFACTOR');
    expect(r.stderr).toBe('');
    expect(readFileSync(join(root, S, 'refactor-backlog.md'), 'utf-8')).toContain('| RF-001 | DES-2 | done |');
  });
});

describe('spec-reopen', () => {
  it('仕様の変更で入力が変わった完了済みタスクだけを再オープンする', async () => {
    const root = await started();
    writeRuns(root, 'DES-2', okRuns);
    expect(sg(root, 'commit', SPEC, 'DES-2').status).toBe(0);

    // 変更なし → 候補なし
    expect(run('spec-reopen.sh', [SPEC, root]).stdout).toBe('');

    // design の DES-2 を変更して再承認する(spec-change の後の状態)
    const fp = `${S}/design.md`;
    writeFileSync(join(root, fp), readFileSync(join(root, fp), 'utf-8').replace('- Purpose: 検証済みのタイトルと Todo を表す', '- Purpose: 検証済みのタイトルと Todo を不変の値として表す'));
    const l = ledgerFor(root);
    const meta = await l.checkRequest(fp);
    await l.recordApproval({ id: 'change-1', filePath: fp, metadata: { ledger: meta } });

    const r = run('spec-reopen.sh', [SPEC, root]);
    expect(r.stdout).toMatch(/^reopen\tDES-2\t[0-9a-f]{12}\t[0-9a-f]{12}$/m);
    expect(r.stdout.split('\n').filter(Boolean)).toHaveLength(1);

    const applied = run('spec-reopen.sh', [SPEC, root, '--apply']);
    expect(applied.status, applied.stderr).toBe(0);
    expect(run('spec-plan.sh', [SPEC, root, '--tsv']).stdout).toMatch(/^DES-2\t.*\topen$/m);
  });
});

describe('spec-git 開始前からある利用者のファイル', () => {
  it('開始前からの未追跡ファイルは G0 / G3 に影響せず、discard で消えず、コミットにも入らない', async () => {
    const root = await prepared();
    mkdirSync(join(root, '.claude'), { recursive: true });
    writeFileSync(join(root, '.claude/notes.md'), 'mine');

    expect(sg(root, 'start', SPEC, 'DES-2').status).toBe(0);
    writeImpl(root);
    expect(sg(root, 'discard', SPEC, 'DES-2').status).toBe(0);
    expect(existsSync(join(root, '.claude/notes.md'))).toBe(true);
    expect(existsSync(join(root, 'src/domain/todo.rs'))).toBe(false);

    expect(sg(root, 'start', SPEC, 'DES-2').status).toBe(0);
    writeImpl(root);
    expect(sg(root, 'checkpoint', SPEC, 'DES-2', 'src/domain/todo_tests.rs').status).toBe(0);
    writeRuns(root, 'DES-2', okRuns);
    const r = sg(root, 'commit', SPEC, 'DES-2');
    expect(r.stderr).toBe('');
    expect(git(root, ['ls-files', '.claude/notes.md'])).toBe('');
    expect(git(root, ['ls-files', 'src/domain/todo.rs'])).toContain('src/domain/todo.rs');
    expect(existsSync(join(root, '.claude/notes.md'))).toBe(true);
  });

  it('.gitignore が spec 文書を除外していれば、docs は理由を示して止まる', async () => {
    const root = await prepared();
    git(root, ['rm', '-rq', '--cached', '.spec-workflow']);
    writeFileSync(join(root, '.gitignore'), '.spec-workflow\n');
    git(root, ['add', '.gitignore']);
    git(root, ['commit', '-qm', 'ignore spec-workflow']);
    const r = sg(root, 'docs', SPEC);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('.gitignore');
  });
});

describe('spec-git その他', () => {
  it('docs は文書以外がステージされていれば拒否する', async () => {
    const root = await prepared();
    writeFileSync(join(root, 'README.md'), 'x');
    git(root, ['add', 'README.md']);
    expect(sg(root, 'docs', SPEC).status).toBe(1);
  });

  it('discard は .spec-workflow を除いてタスクの変更を捨てる', async () => {
    const root = await started();
    expect(sg(root, 'discard', SPEC, 'DES-2').status).toBe(0);
    expect(existsSync(join(root, 'src/domain/todo.rs'))).toBe(false);
    expect(existsSync(join(root, S, 'runs/DES-2/start.json'))).toBe(true);
  });

  it('record はコード変更を含められない', async () => {
    const root = await prepared();
    expect(sg(root, 'start', SPEC, 'P0-REVIEW').status).toBe(0);
    writeFileSync(join(root, 'stray.txt'), 'x');
    writeRuns(root, 'P0-REVIEW', { review: { task: 'P0-REVIEW', verdict: 'commit' } });
    expect(sg(root, 'record', SPEC, 'P0-REVIEW').stderr).toContain('G3');
  });
});
