import { describe, it, expect } from 'vitest';
import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';
import { approveAll, copyFixture, run, S, SPEC } from './helpers.js';

// spec-tools-check.sh / spec-run-tests.sh / spec-phase-check.sh の回帰テスト。
// どれも「使わない」と宣言されていない検査を黙って SKIP しないことを確かめる。

function setTech(root: string, edits: [RegExp, string][]) {
  const tech = join(root, '.spec-workflow/steering/tech.md');
  let t = readFileSync(tech, 'utf-8');
  for (const [re, s] of edits) t = t.replace(re, s);
  writeFileSync(tech, t);
}

describe('spec-run-tests', () => {
  it('使わない層(-)は実行せずに成功する', () => {
    const r = run('spec-run-tests.sh', ['CT', copyFixture()]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('使わない層');
  });

  it('層の行が無ければ exit 3(黙って SKIP しない)', () => {
    const root = copyFixture();
    setTech(root, [[/^\| ST \| .* \|\n/m, '']]);
    expect(run('spec-run-tests.sh', ['ST', root]).status).toBe(3);
  });

  it('テストコマンドの失敗はそのまま返す', () => {
    const root = copyFixture();
    setTech(root, [[/^\| UT \| .* \|$/m, '| UT | exit 7 |']]);
    expect(run('spec-run-tests.sh', ['UT', root]).status).toBe(7);
  });
});

describe('spec-tools-check', () => {
  it('必須ツールが無ければ exit 3、推奨ツールの不足は warn', () => {
    const root = copyFixture();
    const design = join(root, S, 'design.md');
    writeFileSync(design, readFileSync(design, 'utf-8').replace('- Check: cargo --version', '- Check: definitely-not-a-tool --version'));
    const r = run('spec-tools-check.sh', [SPEC, root]);
    expect(r.status).toBe(3);
    expect(r.stdout).toMatch(/^TOOL-1\tcargo\tmissing\t/m);
  });

  it('最小バージョンより古いツールは old', () => {
    const root = copyFixture();
    const design = join(root, S, 'design.md');
    writeFileSync(design, readFileSync(design, 'utf-8').replace('- Check: cargo --version', "- Check: echo 'cargo 1.0.0'"));
    const r = run('spec-tools-check.sh', [SPEC, root]);
    expect(r.stdout).toMatch(/^TOOL-1\tcargo\told\t1\.0\.0 < 1\.93/m);
  });
});

describe('spec-phase-check', () => {
  it('すべての検査が通れば exit 0 で結果を runs/ に書く', async () => {
    const root = copyFixture();
    setTech(root, [
      [/^\| UT \| .* \|$/m, '| UT | true |'], [/^\| IT \| .* \|$/m, '| IT | true |'],
      [/^\| SMK \| .* \|$/m, '| SMK | true |'], [/^\| format \| .* \|$/m, '| format | - |'], [/^\| lint \| .* \|$/m, '| lint | - |']
    ]);
    await approveAll(root);
    const r = run('spec-phase-check.sh', [SPEC, '1', root]);
    expect(r.stdout).not.toContain('NG');
    expect(r.status).toBe(0);
    const res = JSON.parse(readFileSync(join(root, S, 'runs/P1-REVIEW/phase-check.json'), 'utf-8'));
    expect(res.ok).toBe(true);
  });

  it('テストが通らなければ NG で exit 1', async () => {
    const root = copyFixture();
    setTech(root, [[/^\| UT \| .* \|$/m, '| UT | false |'], [/^\| format \| .* \|$/m, '| format | - |'], [/^\| lint \| .* \|$/m, '| lint | - |']]);
    await approveAll(root);
    const r = run('spec-phase-check.sh', [SPEC, '1', root]);
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(/^NG\s+test-UT/m);
  });
});
