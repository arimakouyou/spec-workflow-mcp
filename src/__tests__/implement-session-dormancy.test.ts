import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { spawnSync } from 'child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync, existsSync, readFileSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';
import { fileURLToPath } from 'url';

// 実装セッション連動 hook の dormancy 回帰テスト。
//
// `session-manage.sh end` は lockfile だけを削除し `.implement-session.json` は
// 再開ヒントとして残す。そのため「セッションファイルの存在」で dormancy を判定すると、
// セッション終了後も hook が armed のままになる（issue #79）。
// 判定を lockfile の存在に統一したので、end 後は no-op になることを確認する。

const HERE = resolve(fileURLToPath(import.meta.url), '..');
const HOOKS = resolve(HERE, '../../.claude-plugin/hooks');

const hasJq = spawnSync('jq', ['--version']).status === 0;

const SPEC_ID = 'demo-spec';

interface Run {
  status: number;
  stdout: string;
}

/** hook を実行する */
function runHook(hook: string, projectDir: string, input: unknown): Run {
  const result = spawnSync('bash', [join(HOOKS, hook)], {
    cwd: projectDir,
    env: { ...process.env, CLAUDE_PROJECT_DIR: projectDir },
    input: JSON.stringify(input ?? {}),
    encoding: 'utf8',
  });
  return { status: result.status ?? -1, stdout: result.stdout ?? '' };
}

let workDir: string;

/**
 * 実装セッションのプロジェクトを作る。
 * @param active true なら lockfile あり（アクティブ）、false なら `end` 後の状態
 */
function makeProject(name: string, active: boolean): string {
  const dir = join(workDir, name);
  const specDir = join(dir, '.spec-workflow', 'specs', SPEC_ID);
  mkdirSync(specDir, { recursive: true });

  writeFileSync(
    join(dir, '.implement-session.json'),
    JSON.stringify({ spec_id: SPEC_ID, current_task: '1.1', current_phase: 'GREEN' })
  );
  if (active) writeFileSync(join(dir, '.implement-session.lock'), 'pid=1\n');

  writeFileSync(join(specDir, 'requirements.md'), '# Requirements\n\n- 要件 A\n');
  writeFileSync(join(specDir, 'design.md'), '# Design\n');
  writeFileSync(join(specDir, 'tasks.md'), '# Tasks\n\n- [x] 1.1 最初のタスク\n');

  spawnSync('git', ['init', '-q'], { cwd: dir });
  return dir;
}

describe('実装セッション連動 hook の dormancy', () => {
  beforeAll(() => {
    workDir = mkdtempSync(join(tmpdir(), 'implement-session-dormancy-'));
  });

  afterAll(() => {
    rmSync(workDir, { recursive: true, force: true });
  });

  it('前提: jq が利用可能であること（無いと hook 自体が無効化される）', () => {
    expect(hasJq, 'jq が必要です。未インストールだと全 hook が常に exit 0 になります').toBe(true);
  });

  describe('inject-spec.sh', () => {
    it('セッションがアクティブなら spec を注入する', () => {
      const dir = makeProject('inject-active', true);
      const run = runHook('inject-spec.sh', dir, {});
      expect(run.status).toBe(0);
      expect(run.stdout).toContain('<spec_context>');
      expect(run.stdout).toContain('要件 A');
    });

    it('end 後（lockfile なし）は何も注入しない', () => {
      const dir = makeProject('inject-ended', false);
      const run = runHook('inject-spec.sh', dir, {});
      expect(run.status).toBe(0);
      expect(run.stdout).toBe('');
    });
  });

  describe('detect-new-files.sh', () => {
    const REL_TARGET = join('src', 'unexpected.ts');

    /**
     * PostToolUse(Write) の実状況を再現する。Write 実行後なので対象ファイルは
     * ディスク上に存在する。hook 側の `realpath --relative-to` は最終要素以外の
     * 存在を要求するため、作らずに呼ぶと raw 絶対パスの fallback 経路に落ちて
     * 相対パス処理の退行を検出できない。
     */
    const writeTarget = (dir: string): { tool_name: string; tool_input: { file_path: string } } => {
      const filePath = join(dir, REL_TARGET);
      mkdirSync(join(dir, 'src'), { recursive: true });
      writeFileSync(filePath, 'export const x = 1;\n');
      return { tool_name: 'Write', tool_input: { file_path: filePath } };
    };

    it('セッションがアクティブなら spec 未言及の新規ファイルを警告する', () => {
      const dir = makeProject('detect-active', true);
      const run = runHook('detect-new-files.sh', dir, writeTarget(dir));
      expect(run.status).toBe(0);
      expect(run.stdout).toContain('<new_file_warning>');
      // 絶対パスではなくプロジェクト相対パスで報告されること
      expect(run.stdout).toContain(`\`${REL_TARGET}\``);
    });

    it('end 後（lockfile なし）は警告しない', () => {
      const dir = makeProject('detect-ended', false);
      const run = runHook('detect-new-files.sh', dir, writeTarget(dir));
      expect(run.status).toBe(0);
      expect(run.stdout).toBe('');
    });
  });

  describe('log-implementation.sh', () => {
    const logPath = (dir: string) =>
      join(dir, '.spec-workflow', 'specs', SPEC_ID, 'task-logs', '1.1.log.md');

    it('セッションがアクティブなら task log に completion sections を追記する', () => {
      const dir = makeProject('log-active', true);
      const run = runHook('log-implementation.sh', dir, {});
      expect(run.status).toBe(0);
      expect(existsSync(logPath(dir))).toBe(true);
      expect(readFileSync(logPath(dir), 'utf8')).toContain('## Summary');
    });

    it('end 後（lockfile なし）は task log を作らない', () => {
      const dir = makeProject('log-ended', false);
      const run = runHook('log-implementation.sh', dir, {});
      expect(run.status).toBe(0);
      expect(existsSync(logPath(dir))).toBe(false);
      expect(run.stdout).toBe('');
    });
  });
});
