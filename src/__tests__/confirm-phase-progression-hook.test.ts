import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { spawnSync } from 'child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';
import { fileURLToPath } from 'url';

// `.claude-plugin/hooks/confirm-phase-progression.sh`（Stop hook）の回帰テスト。
//
// 過剰ブロック（誤検知）:
//   進行宣言の検出対象は「今ターンの最終 assistant 発言」＝ Stop hook 入力の
//   last_assistant_message のみ。transcript の tail を丸ごと grep していた頃は
//   tool_result や過去の発言に含まれる "Auto Mode" 等に一致し、無関係な文脈で
//   ブロックしていた（手元 12 transcript 中 4 件が誤 block）。
//
// SIGPIPE（issue #79 同型）:
//   `echo "$VAR" | grep -qE` は一致した瞬間 grep が終了し、echo が SIGPIPE(141) で
//   落ちて pipefail によりパイプライン全体が偽になる。検査は here-string で行う。
//   最終 assistant 発言がパイプバッファ（64KB）を超える場合に再現する。

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

const DECLARATION = 'Auto Mode のため Wave 2 へ進みます';

let workDir: string;
let seq = 0;

/** transcript を書き出してパスを返す */
function writeTranscript(lines: string[]): string {
  const path = join(workDir, `t${seq++}.jsonl`);
  writeFileSync(path, lines.join('\n') + '\n');
  return path;
}

/** hook を実行して exit code を返す */
function runHook(input: {
  transcript_path: string;
  last_assistant_message?: string;
  stop_hook_active?: boolean;
}): number {
  const result = spawnSync('bash', [HOOK], { input: JSON.stringify(input), encoding: 'utf8' });
  return result.status ?? -1;
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

  it('同意なしの進行宣言をブロックする', () => {
    const path = writeTranscript([userText('spec-workflow のタスクを見せて'), assistant(DECLARATION)]);
    expect(runHook({ transcript_path: path, last_assistant_message: DECLARATION })).toBe(2);
  });

  it('進行宣言の各表現をブロックする（パターン網羅）', () => {
    for (const msg of [
      'Auto Mode のため Wave 2 へ進みます。',
      'Wave 1 の全タスクが完了しました。Wave 2 の並列起動を開始します。',
      '継続モードにつき、ユーザー確認を省略して続行します。',
      'Phase 3 が完了しました。続けて Phase 4 に着手します。',
      '次の Wave へ進みます。',
      'Phase 4 へ進みます。',
      'Wave 3 に進みます。',
      'ユーザー確認は不要と判断し、省略します。',
      'Phase 1 が完了しました。続けて Phase 2 に着手します。問題があれば知らせてください。',
      'Auto Mode のため Wave 2 へ進みます。何か問題はありますか？',
    ]) {
      const path = writeTranscript([userText('spec-workflow のタスクを見せて'), assistant(msg)]);
      expect(runHook({ transcript_path: path, last_assistant_message: msg }), msg).toBe(2);
    }
  });

  it('LC_ALL=C でも判定が変わらない（マルチバイト×バイト単位正規表現の回帰）', () => {
    const path = writeTranscript([userText('spec-workflow のタスクを見せて'), assistant(DECLARATION)]);
    const runC = (msg: string) =>
      spawnSync('bash', [HOOK], {
        input: JSON.stringify({ transcript_path: path, last_assistant_message: msg }),
        encoding: 'utf8',
        env: { ...process.env, LC_ALL: 'C' },
      }).status;
    expect(runC(DECLARATION)).toBe(2);
    expect(runC('仕様上、ユーザー確認を省略してはならない。')).toBe(0);
  });

  it('宣言が 64KB を超えてもブロックする（issue #79 同型の SIGPIPE 回帰）', () => {
    const huge = 'この行は詰め物です。'.repeat(6000) + '\n' + DECLARATION;
    expect(Buffer.byteLength(huge)).toBeGreaterThan(65536);
    const path = writeTranscript([userText('spec-workflow のタスクを見せて'), assistant(huge)]);
    expect(runHook({ transcript_path: path, last_assistant_message: huge })).toBe(2);
  });

  it('直近のユーザー発話に明示同意があれば通す', () => {
    const path = writeTranscript([userText('spec-workflow の Wave 2 に進めて'), assistant(DECLARATION)]);
    expect(runHook({ transcript_path: path, last_assistant_message: DECLARATION })).toBe(0);
  });

  it('ダッシュボード承認を伝えられていれば通す（フェーズ遷移の正規ゲート）', () => {
    const msg = 'Phase 2 に進みます。';
    for (const u of ['承認したので確認して', 'ダッシュボードで承認しました', '承認済みです']) {
      const path = writeTranscript([userText(u), assistant(msg)]);
      expect(runHook({ transcript_path: path, last_assistant_message: msg }), u).toBe(0);
    }
  });

  it('承認の否定形は同意として扱わない', () => {
    const msg = 'Phase 2 に進みます。';
    for (const u of ['まだ承認されていない', '承認しないでほしい']) {
      const path = writeTranscript([userText(u), assistant(msg)]);
      expect(runHook({ transcript_path: path, last_assistant_message: msg }), u).toBe(2);
    }
  });

  it('進行宣言が無ければ通す', () => {
    const msg = 'tasks.md の Phase 1 の内容は次のとおりです。';
    const path = writeTranscript([userText('spec-workflow のタスクを見せて'), assistant(msg)]);
    expect(runHook({ transcript_path: path, last_assistant_message: msg })).toBe(0);
  });

  it('進行宣言が tool_result にあるだけならブロックしない（過剰ブロック回帰）', () => {
    const benign = 'hook スクリプトの内容を確認しました。';
    const path = writeTranscript([
      userText('confirm-phase-progression.sh の中身を見せて'),
      toolResult('t1', `PROGRESSION_PATTERNS には "Auto Mode" や "継続モード" が並んでいる`),
      assistant(benign),
    ]);
    expect(runHook({ transcript_path: path, last_assistant_message: benign })).toBe(0);
  });

  it('過去の assistant 発言に宣言があっても、今ターンの発言が無害なら通す（過剰ブロック回帰）', () => {
    const benign = '修正が完了しました。';
    const path = writeTranscript([
      userText('spec-workflow のタスクを見せて'),
      assistant(DECLARATION),
      userText('その宣言は取り下げて、別の作業をして'),
      assistant(benign),
    ]);
    expect(runHook({ transcript_path: path, last_assistant_message: benign })).toBe(0);
  });

  it('概念名に言及しただけではブロックしない（過剰ブロック回帰）', () => {
    for (const msg of [
      'Auto Mode という概念はこの仕様には存在しません。',
      'この hook は「継続モード」という語を検出します。',
      'ビルドを続行します。',
      '仕様上、ユーザー確認を省略してはならない。',
      'Phase 3 に進みますか？',
      'この hook は「Phase 4 へ進みます」という宣言を検出しますか？ いいえ、検出しません。',
      '先ほどの「Phase 3 に進みます」という記述は取り下げます。',
      'Wave 2 完了の報告と Wave 3 着手を同じメッセージに書いたことがパターンに一致しました。',
      'PROGRESSION_PATTERNS に Auto Mode があるため、Wave 2 へ進みますという文が誤検知されていました。',
    ]) {
      const path = writeTranscript([userText('spec-workflow の hook を説明して'), assistant(msg)]);
      expect(runHook({ transcript_path: path, last_assistant_message: msg }), msg).toBe(0);
    }
  });

  it('ユーザーに選択肢を提示していればブロックしない（過剰ブロック回帰）', () => {
    const msg = 'Phase 2 が完了しました。次はどうしますか？ 1. Phase 3 へ進む 2. レビューする';
    const path = writeTranscript([userText('spec-workflow のタスクを進めて確認して'), assistant(msg)]);
    expect(runHook({ transcript_path: path, last_assistant_message: msg })).toBe(0);
  });

  it('stop_hook_active=true なら素通しする（ブロック後の無限ループ防止）', () => {
    const path = writeTranscript([userText('spec-workflow のタスクを見せて'), assistant(DECLARATION)]);
    expect(
      runHook({ transcript_path: path, last_assistant_message: DECLARATION, stop_hook_active: true })
    ).toBe(0);
  });

  it('サブエージェント完了通知がユーザーの同意を上書きしない（過剰ブロック回帰）', () => {
    // <task-notification> は type="user" / isMeta=false で記録されるため、除外しないと
    // ユーザーの「進めて」を毎回上書きし、1 タスク 3 エージェントの並列実装では
    // 停止のたびにブロックされる（specrail の履歴で確認。全 transcript で最多の混入源）
    const notification =
      '<task-notification>\n<task-id>abc123</task-id>\n<status>completed</status>\n</task-notification>';
    const path = writeTranscript([
      userText('spec-workflow の Wave 2 に進めて'),
      userText(notification),
      assistant(DECLARATION),
    ]);
    expect(runHook({ transcript_path: path, last_assistant_message: DECLARATION })).toBe(0);
  });

  it('スラッシュコマンド出力を「直近のユーザー発話」と誤認しない（過剰ブロック回帰）', () => {
    // /exit 直後の transcript。素の実装は <local-command-stdout> を最終ユーザー発話として
    // 採用し、同意なし扱いでブロックしていた。同意が読み取れないなら fail-open で通す
    const path = writeTranscript([
      userText('spec-workflow の Wave 2 に進めて'),
      assistant(DECLARATION),
      JSON.stringify({
        type: 'user',
        isMeta: true,
        message: { role: 'user', content: [{ type: 'text', text: '<local-command-caveat>Caveat: ...</local-command-caveat>' }] },
      }),
      userText('<command-name>/exit</command-name>\n<command-message>exit</command-message>'),
      userText('<local-command-stdout>See ya!</local-command-stdout>'),
    ]);
    expect(runHook({ transcript_path: path, last_assistant_message: DECLARATION })).toBe(0);
  });

  it('last_assistant_message が無ければ transcript の最終 assistant 発言にフォールバックする', () => {
    const path = writeTranscript([userText('spec-workflow のタスクを見せて'), assistant(DECLARATION)]);
    expect(runHook({ transcript_path: path })).toBe(2);
  });
});
