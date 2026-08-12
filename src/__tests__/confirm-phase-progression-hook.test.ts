import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { spawnSync } from 'child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';
import { fileURLToPath } from 'url';

// `.claude-plugin/hooks/confirm-phase-progression.sh`（Stop hook）の回帰テスト。
//
// issue #79 と同種の SIGPIPE バグ。`echo "$RECENT_LINES" | grep -qE "$PATTERN"` は、
// 進行宣言にマッチした瞬間 grep が終了し、書き手の echo が SIGPIPE(141) で落ちる。
// pipefail によりパイプライン全体が偽になり、進行宣言を検出できず素通しする（fail-open）。
//
// $RECENT_LINES は transcript の tail -n 200 で、JSONL 1 行が数 KB になることも珍しくない
// ため、パイプバッファ（64KB）は容易に超える。「宣言が窓の先頭側にあり、その後に大量の
// tool_result が続く」という現実的な形で再現する。

const HERE = resolve(fileURLToPath(import.meta.url), '..');
const HOOK = resolve(HERE, '../../.claude-plugin/hooks/confirm-phase-progression.sh');

const hasJq = spawnSync('jq', ['--version']).status === 0;

const assistant = (text: string) =>
  JSON.stringify({ type: 'assistant', message: { content: [{ type: 'text', text }] } });
const userText = (text: string) =>
  JSON.stringify({ type: 'user', message: { content: [{ type: 'text', text }] } });
const toolResult = (id: string, text: string) =>
  JSON.stringify({
    type: 'user',
    message: { content: [{ type: 'tool_result', tool_use_id: id, content: [{ type: 'text', text }] }] },
  });

/**
 * transcript を組み立てる。
 * @param lastUserMsg 進行宣言の前に置く直近のユーザー発話（同意の有無を制御する）
 * @param declaration 進行宣言（null なら宣言なし）
 * @param fillerCount 宣言のあとに続く tool_result の件数（tail -n 200 窓のサイズを決める）
 */
function buildTranscript(lastUserMsg: string, declaration: string | null, fillerCount: number): string {
  const lines = [userText(lastUserMsg)];
  if (declaration) lines.push(assistant(declaration));
  for (let i = 0; i < fillerCount; i++) {
    lines.push(toolResult(`t${i}`, 'output '.repeat(90) + i));
  }
  return lines.join('\n') + '\n';
}

let workDir: string;

/** hook を実行して exit code を返す */
function runHook(transcriptPath: string): number {
  const result = spawnSync('bash', [HOOK], {
    input: JSON.stringify({ transcript_path: transcriptPath }),
    encoding: 'utf8',
  });
  return result.status ?? -1;
}

/** transcript を書き出し、tail -n 200 のバイト数を返す */
function writeTranscript(name: string, content: string): { path: string; tailBytes: number } {
  const path = join(workDir, name);
  writeFileSync(path, content);
  const tail = content.trimEnd().split('\n').slice(-200).join('\n');
  return { path, tailBytes: Buffer.byteLength(tail) };
}

describe('confirm-phase-progression.sh hook', () => {
  beforeAll(() => {
    workDir = mkdtempSync(join(tmpdir(), 'confirm-phase-progression-'));
  });

  afterAll(() => {
    rmSync(workDir, { recursive: true, force: true });
  });

  it('前提: jq が利用可能であること（無いと hook 自体が無効化される）', () => {
    expect(hasJq, 'jq が必要です。未インストールだと hook は常に exit 0 になります').toBe(true);
  });

  it('tail 窓が 64KB を超えても、同意なしの進行宣言をブロックする（issue #79 同型）', () => {
    const { path, tailBytes } = writeTranscript(
      'large.jsonl',
      buildTranscript('spec-workflow のタスクを見せて', 'Auto Mode のため Wave 2 へ進みます', 199)
    );
    expect(tailBytes).toBeGreaterThan(65536);

    // 修正前は grep -q が SIGPIPE で偽になり、進行宣言を検出できず exit 0（fail-open）
    expect(runHook(path)).toBe(2);
  });

  it('同じ内容でも tail 窓が小さければブロックする（サイズ以外の差が無いことの確認）', () => {
    const { path, tailBytes } = writeTranscript(
      'small.jsonl',
      buildTranscript('spec-workflow のタスクを見せて', 'Auto Mode のため Wave 2 へ進みます', 5)
    );
    expect(tailBytes).toBeLessThan(65536);
    expect(runHook(path)).toBe(2);
  });

  it('直近のユーザー発話に明示同意があれば通す', () => {
    const { path } = writeTranscript(
      'consent.jsonl',
      buildTranscript('spec-workflow の Wave 2 に進めて', 'Auto Mode のため Wave 2 へ進みます', 199)
    );
    expect(runHook(path)).toBe(0);
  });

  it('進行宣言が無ければ通す', () => {
    const { path } = writeTranscript(
      'no-declaration.jsonl',
      buildTranscript('spec-workflow のタスクを見せて', null, 199)
    );
    expect(runHook(path)).toBe(0);
  });
});
