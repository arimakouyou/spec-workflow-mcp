import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { spawnSync } from 'child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync, chmodSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';
import { fileURLToPath } from 'url';

// `.claude-plugin/hooks/security-audit-guard.sh`（PreToolUse Bash）の回帰テスト。
//
// issue #79 と同種の SIGPIPE バグ。`set -o pipefail` 下では、パイプの読み手が短絡終了
// （`grep -q` は最初のマッチで、`head -N` は N 行で）すると書き手が SIGPIPE(141) で落ち、
// パイプライン全体が 141 になる。本 hook では 2 通りの壊れ方をしていた:
//
//   - 判定に使っている場合（grep -q）      → 偽になり脆弱性を見逃す
//   - 単独実行の場合（| head -N）          → errexit でスクリプトごと中断し、
//                                            FAIL=true と exit 2 に到達しない
//
// どちらも「脆弱性があるのにコミットを通す」fail-open。しかも出力が大きいほど、
// つまり脆弱性が多いほど踏みやすい。
//
// 重要: SIGPIPE はパイプバッファ（Linux 64KB）を超えて初めて発生する。行数ではなく
// バイト数で fixture を設計すること（20 行程度では修正前でもテストが緑になる）。

const HERE = resolve(fileURLToPath(import.meta.url), '..');
const HOOK = resolve(HERE, '../../.claude-plugin/hooks/security-audit-guard.sh');

const hasJq = spawnSync('jq', ['--version']).status === 0;
const hasTimeout = spawnSync('timeout', ['--version']).status === 0;
const hasGit = spawnSync('git', ['--version']).status === 0;

let workDir: string;

/** 指定の行を繰り返した出力ファイルを作り、そのバイト数を返す */
function writeOutputFixture(path: string, line: (i: number) => string, count: number): number {
  const body = Array.from({ length: count }, (_, i) => line(i)).join('\n') + '\n';
  writeFileSync(path, body);
  return Buffer.byteLength(body);
}

/** PATH に差し込む偽コマンド（fixture を cat して指定の終了コードで終わる） */
function writeFakeTool(binDir: string, name: string, outputFile: string, exitCode: number): void {
  mkdirSync(binDir, { recursive: true });
  const p = join(binDir, name);
  writeFileSync(p, `#!/usr/bin/env bash\ncat ${JSON.stringify(outputFile)}\nexit ${exitCode}\n`);
  chmodSync(p, 0o755);
}

/** staged 変更を持つ git リポジトリを作る */
function initRepo(name: string, files: Record<string, string>): string {
  const dir = join(workDir, name);
  mkdirSync(dir, { recursive: true });
  spawnSync('git', ['init', '-q'], { cwd: dir });
  for (const [file, content] of Object.entries(files)) {
    writeFileSync(join(dir, file), content);
  }
  spawnSync('git', ['add', '-A'], { cwd: dir });
  return dir;
}

/** hook を PreToolUse Bash として実行し exit code を返す */
function runHook(repoDir: string, binDir?: string, command = 'git commit -m "x"'): number {
  const env = { ...process.env };
  if (binDir) env.PATH = `${binDir}:${process.env.PATH}`;
  const result = spawnSync('bash', [HOOK], {
    cwd: repoDir,
    env,
    input: JSON.stringify({ tool_input: { command } }),
    encoding: 'utf8',
  });
  return result.status ?? -1;
}

describe('security-audit-guard.sh hook', () => {
  beforeAll(() => {
    workDir = mkdtempSync(join(tmpdir(), 'security-audit-guard-'));
  });

  afterAll(() => {
    rmSync(workDir, { recursive: true, force: true });
  });

  it('前提: jq / timeout / git が利用可能であること', () => {
    expect(hasJq, 'jq が無いと hook は即 exit 0 になる').toBe(true);
    expect(hasTimeout, 'timeout が無いと audit の実行結果が変わる').toBe(true);
    expect(hasGit, 'git が無いとステージ差分を判定できない').toBe(true);
  });

  it('npm audit のマッチ行が 64KB を超えてもコミットをブロックする（issue #79 同型 / L122）', () => {
    const repo = initRepo('node-large-match', {
      'package.json': '{"name":"x","version":"1.0.0","dependencies":{"a":"1.0.0"}}',
      'package-lock.json': '{}',
    });
    const out = join(repo, 'npm-output.txt');
    const bytes = writeOutputFixture(out, i => `high severity vulnerability in package-${i} (>=1.0.0)`, 3000);
    expect(bytes).toBeGreaterThan(65536);

    const bin = join(repo, 'fakebin');
    writeFakeTool(bin, 'npm', out, 1);

    // 修正前は `printf | grep -iE | head -5` が SIGPIPE で中断し exit 141（= 非ブロッキング）
    expect(runHook(repo, bin)).toBe(2);
  });

  it('dotnet の出力が 64KB を超えても脆弱性を検出してブロックする（L169）', () => {
    const repo = initRepo('dotnet-large-output', {
      'packages.lock.json': '{}',
      'app.csproj': '<Project/>',
    });
    const out = join(repo, 'dotnet-output.txt');
    // マッチは先頭 1 行のみ（grep -q がそこで短絡する）。残りは非マッチの filler
    const lines = ['   > Vulnerable.Pkg   1.0.0   1.0.0   High   https://example.test/1'];
    for (let i = 0; i < 3000; i++) lines.push(`   > Fine.Pkg.${i}   1.0.0   1.0.0   no-finding-here`);
    const body = lines.join('\n') + '\n';
    writeFileSync(out, body);
    expect(Buffer.byteLength(body)).toBeGreaterThan(65536);

    const bin = join(repo, 'fakebin');
    writeFakeTool(bin, 'dotnet', out, 0);

    // 修正前は grep -q が SIGPIPE で偽になり、脆弱性を見逃して exit 0
    expect(runHook(repo, bin)).toBe(2);
  });

  it('dotnet のマッチ行が 64KB を超えてもコミットをブロックする（L171）', () => {
    const repo = initRepo('dotnet-large-match', {
      'packages.lock.json': '{}',
      'app.csproj': '<Project/>',
    });
    const out = join(repo, 'dotnet-output.txt');
    const bytes = writeOutputFixture(
      out,
      i => `   > Vulnerable.Pkg.${i}   1.0.0   1.0.0   High   https://example.test/${i}`,
      3000
    );
    expect(bytes).toBeGreaterThan(65536);

    const bin = join(repo, 'fakebin');
    writeFakeTool(bin, 'dotnet', out, 0);

    // 修正前は検出行の出力（| head -10）が SIGPIPE で中断し exit 141
    expect(runHook(repo, bin)).toBe(2);
  });

  it('脆弱性が無ければコミットを通す', () => {
    const repo = initRepo('dotnet-clean', {
      'packages.lock.json': '{}',
      'app.csproj': '<Project/>',
    });
    const out = join(repo, 'dotnet-output.txt');
    writeOutputFixture(out, i => `   > Fine.Pkg.${i}   1.0.0   1.0.0   no-finding-here`, 3000);

    const bin = join(repo, 'fakebin');
    writeFakeTool(bin, 'dotnet', out, 0);

    expect(runHook(repo, bin)).toBe(0);
  });

  it('依存関係の変更が無いコミットは audit せず素通しする', () => {
    const repo = initRepo('no-dep-change', { 'README.md': '# hello' });
    expect(runHook(repo)).toBe(0);
  });

  // `git commit` の判定は POSIX ERE で書く必要がある。`\s` は GNU 拡張で、
  // 非対応環境では文字 `s` として解釈され判定が常に外れる（ガードが丸ごと素通しする）
  describe('git commit の判定', () => {
    function vulnerableRepo(name: string): { repo: string; bin: string } {
      const repo = initRepo(name, { 'packages.lock.json': '{}', 'app.csproj': '<Project/>' });
      const out = join(repo, 'dotnet-output.txt');
      writeOutputFixture(out, i => `   > Vulnerable.Pkg.${i}   1.0.0   1.0.0   High`, 10);
      const bin = join(repo, 'fakebin');
      writeFakeTool(bin, 'dotnet', out, 0);
      return { repo, bin };
    }

    it('先頭に空白があるコミットでも発火する', () => {
      const { repo, bin } = vulnerableRepo('commit-leading-space');
      expect(runHook(repo, bin, '  git   commit -m "x"')).toBe(2);
    });

    it('commit 以外のコマンドでは発火しない', () => {
      const { repo, bin } = vulnerableRepo('non-commit-command');
      expect(runHook(repo, bin, 'ls -la')).toBe(0);
    });
  });
});
