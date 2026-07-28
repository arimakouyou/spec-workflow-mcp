import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { spawnSync } from 'child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';
import { fileURLToPath } from 'url';

// `.claude-plugin/hooks/verify-tests-run.sh`（Stop hook）の回帰テスト。
//
// issue #79: `set -o pipefail` 環境で `printf ... | grep -q` を使うと、grep が最初の
// マッチで即終了した際に書き手が SIGPIPE（141）で落ち、パイプライン全体が偽になる。
// 入力がパイプバッファ（Linux 64KB）を超える長いセッションで必ず踏むため、
// テストしたコミットでもブロックされる / 失敗を見逃す、という誤判定が起きていた。
//
// 本テストは「64KB を超える入力」かつ「マッチが先頭側にある」fixture を使う。
// この 2 条件が揃わないと SIGPIPE は発生せず、修正前でもテストが通ってしまう。

const HERE = resolve(fileURLToPath(import.meta.url), '..');
const HOOK = resolve(HERE, '../../.claude-plugin/hooks/verify-tests-run.sh');

/** assistant の Bash tool_use エントリ */
function toolUse(id: string, command: string): string {
  return JSON.stringify({
    type: 'assistant',
    message: { content: [{ type: 'tool_use', id, name: 'Bash', input: { command } }] },
  });
}

/** user の tool_result エントリ */
function toolResult(id: string, text: string): string {
  return JSON.stringify({
    type: 'user',
    message: { content: [{ type: 'tool_result', tool_use_id: id, content: [{ type: 'text', text }] }] },
  });
}

type FixtureMode = 'pass' | 'fail' | 'notest';

/**
 * transcript fixture を生成する。
 * 抽出後の Bash コマンド列が 64KB を超えるよう filler を積み、
 * テストコマンドは先頭に置く（= grep -q がそこで短絡する）。
 */
function buildTranscript(mode: FixtureMode): string {
  const lines: string[] = [];

  if (mode !== 'notest') {
    lines.push(toolUse('toolu_first', 'cargo test --workspace --all-features'));
    lines.push(toolResult('toolu_first', 'test result: ok. 42 passed; 0 failed; 0 ignored'));
  }

  const filler = 'x'.repeat(80);
  for (let i = 0; i < 800; i++) {
    lines.push(toolUse(`toolu_f${i}`, `git status --short # ${filler}-${i}`));
  }

  if (mode === 'fail') {
    // 直近のテスト実行が失敗。出力も 64KB 超で、失敗シグナルは先頭にある
    const big = 'ok some passing line\n'.repeat(4000);
    lines.push(toolUse('toolu_last', 'cargo test --workspace'));
    lines.push(toolResult('toolu_last', `test result: FAILED. 1 passed; 1 failed\n${big}`));
  }

  return lines.join('\n') + '\n';
}

// hook は jq が無い環境では即 exit 0 する。この場合テストをスキップすると
// 「ガードが働いていないのに緑」になり、本 issue と同じ fail-open になるため、
// 前提条件として明示的に検証する（下の precondition テスト）。
const hasJq = spawnSync('jq', ['--version']).status === 0;

/** hook を実行して exit code を返す */
function runHook(projectDir: string, transcriptPath: string): number {
  const result = spawnSync('bash', [HOOK], {
    input: JSON.stringify({ transcript_path: transcriptPath }),
    env: { ...process.env, CLAUDE_PROJECT_DIR: projectDir },
    encoding: 'utf8',
  });
  return result.status ?? -1;
}

describe('verify-tests-run.sh hook', () => {
  let workDir: string;
  let activeDir: string;
  let endedDir: string;
  const transcripts: Record<FixtureMode, string> = { pass: '', fail: '', notest: '' };

  beforeAll(() => {
    workDir = mkdtempSync(join(tmpdir(), 'verify-tests-run-'));

    // アクティブなセッション（init 直後の状態）
    activeDir = join(workDir, 'active');
    mkdirSync(activeDir);
    writeFileSync(join(activeDir, '.implement-session.json'), '{}');
    writeFileSync(join(activeDir, '.implement-session.lock'), 'pid=1\n');

    // `session-manage.sh end` 後の状態（lockfile のみ削除、セッション本体は残る）
    endedDir = join(workDir, 'ended');
    mkdirSync(endedDir);
    writeFileSync(join(endedDir, '.implement-session.json'), '{}');

    for (const mode of ['pass', 'fail', 'notest'] as FixtureMode[]) {
      const path = join(workDir, `transcript-${mode}.jsonl`);
      writeFileSync(path, buildTranscript(mode));
      transcripts[mode] = path;
    }
  });

  afterAll(() => {
    rmSync(workDir, { recursive: true, force: true });
  });

  it('前提: jq が利用可能であること（無いと hook 自体が無効化される）', () => {
    expect(hasJq, 'jq が必要です。未インストールだと hook は常に exit 0 になり、本テストは意味を持ちません').toBe(true);
  });

  it('64KB 超の transcript でもテスト実行を検出し、ブロックしない（issue #79）', () => {
    expect(runHook(activeDir, transcripts.pass)).toBe(0);
  });

  it('64KB 超の出力でも直近テストの失敗を検出してブロックする（issue #79）', () => {
    expect(runHook(activeDir, transcripts.fail)).toBe(2);
  });

  it('テスト実行履歴がなければブロックする', () => {
    expect(runHook(activeDir, transcripts.notest)).toBe(2);
  });

  it('セッション終了後（lockfile なし）は dormant になる', () => {
    expect(runHook(endedDir, transcripts.notest)).toBe(0);
  });

  it('実装セッション外では dormant になる', () => {
    const plainDir = join(workDir, 'plain');
    mkdirSync(plainDir, { recursive: true });
    expect(runHook(plainDir, transcripts.notest)).toBe(0);
  });
});
