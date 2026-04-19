import { describe, it, expect } from 'vitest';
import {
  decideResumeAction,
  parseProgressLog,
} from '../progress-log-parser.js';
import {
  computeTaskState,
  syncTasksMarkdown,
  type TaskState,
} from '../tasks-auto-update.js';

const nowIso = (offsetSec = 0): string =>
  new Date(Date.UTC(2026, 3, 19, 14, 14, offsetSec)).toISOString();

function ev(event: string, step: string, meta: unknown = {}): string {
  return `${nowIso()}\t${event}\t${step}\t${JSON.stringify(meta)}\n`;
}

function evAt(sec: number, event: string, step: string, meta: unknown = {}): string {
  return `${nowIso(sec)}\t${event}\t${step}\t${JSON.stringify(meta)}\n`;
}

describe('resume-integration: 中断→再開シナリオ (plan §9.2)', () => {
  it('シナリオ 1: 途中 SIGKILL (green-code BEGIN 後に中断) → 同 step を attempt=2 で redo', () => {
    const log =
      evAt(0, 'BEGIN', 'discover') +
      evAt(1, 'END', 'discover', { status: 'completed' }) +
      evAt(2, 'VERIFIED', 'discover') +
      evAt(3, 'BEGIN', 'red-write') +
      evAt(4, 'END', 'red-write', { status: 'completed' }) +
      evAt(5, 'VERIFIED', 'red-write') +
      evAt(6, 'BEGIN', 'red-verify') +
      evAt(7, 'END', 'red-verify', { status: 'completed' }) +
      evAt(8, 'VERIFIED', 'red-verify') +
      evAt(9, 'BEGIN', 'green-code');

    const action = decideResumeAction(log);
    expect(action).toEqual({
      kind: 'redo-step',
      step: 'green-code',
      attempt: 2,
      reason: 'delegation did not finish (subagent interruption)',
    });
  });

  it('シナリオ 2: subagent rate limit (BEGIN + END あり・VERIFIED 無し) → 同 step を redo', () => {
    const log =
      evAt(0, 'BEGIN', 'green-code') +
      evAt(120, 'END', 'green-code', { status: 'completed' });

    const action = decideResumeAction(log);
    expect(action.kind).toBe('redo-step');
    if (action.kind === 'redo-step') {
      expect(action.step).toBe('green-code');
      expect(action.attempt).toBe(2);
      expect(action.reason).toMatch(/verification was not recorded/);
    }
  });

  it('シナリオ 3: MAX_ATTEMPTS 到達 (同 step の BEGIN 3 回) → reset-to-task-start', () => {
    const log =
      evAt(0, 'BEGIN', 'green-code') +
      evAt(5, 'END', 'green-code') +
      evAt(10, 'BEGIN', 'green-code') +
      evAt(15, 'END', 'green-code') +
      evAt(20, 'BEGIN', 'green-code');

    const action = decideResumeAction(log);
    expect(action.kind).toBe('reset-to-task-start');
  });

  it('シナリオ 4: COMPLETE 後の再実行 → already-done で次 task へ', () => {
    const log =
      evAt(0, 'BEGIN', 'log') +
      evAt(1, 'END', 'log') +
      evAt(2, 'VERIFIED', 'log') +
      evAt(3, 'COMPLETE', 'log', { log_id: 'abc' });

    const action = decideResumeAction(log);
    expect(action).toEqual({ kind: 'already-done' });
  });

  it('シナリオ 5: tasks.md drift 修正 (progress=COMPLETE だが tasks=[-])', () => {
    const progress =
      evAt(0, 'BEGIN', 'log') +
      evAt(1, 'VERIFIED', 'log') +
      evAt(2, 'COMPLETE', 'log', { log_id: 'x' });

    expect(computeTaskState(progress)).toBe('completed');

    const tasksMd = `## Phase 1: Core

- [-] 1.1 Task
  - File: a.ts
`;
    const map = new Map<string, TaskState>([['1.1', 'completed']]);
    const { updatedMarkdown, updates } = syncTasksMarkdown(tasksMd, map);

    expect(updates).toEqual([
      { taskId: '1.1', before: 'in-progress', after: 'completed' },
    ]);
    expect(updatedMarkdown).toContain('[x] 1.1 Task');
  });
});

describe('resume-integration: 多 task spec のマルチ state 同期', () => {
  it('異なる state の progress.md 群 → tasks.md が正しく一括同期される', () => {
    const progressByTask: Record<string, string> = {
      '1.1': evAt(0, 'BEGIN', 'discover'), // in-progress
      '1.2':
        evAt(0, 'BEGIN', 'log') +
        evAt(1, 'COMPLETE', 'log', { log_id: 'y' }), // completed
      '2.1': '', // pending (空)
    };

    const map = new Map<string, TaskState>();
    for (const [taskId, content] of Object.entries(progressByTask)) {
      const state = computeTaskState(content);
      if (state === 'pending') continue;
      map.set(taskId, state);
    }

    const tasksMd = `## Phase 1: Core

- [ ] 1.1 First
  - File: a.ts

- [ ] 1.2 Second
  - File: b.ts

- [ ] 2.1 Third
  - File: c.ts
`;
    const { updatedMarkdown, updates } = syncTasksMarkdown(tasksMd, map);

    expect(updates).toHaveLength(2);
    expect(updatedMarkdown).toContain('[-] 1.1 First');
    expect(updatedMarkdown).toContain('[x] 1.2 Second');
    expect(updatedMarkdown).toContain('[ ] 2.1 Third');
  });
});

describe('resume-integration: 進行中 attempt 番号の正しい増分', () => {
  it('BEGIN + END + BEGIN + END + BEGIN → attempt 3 としての redo (閾値未到達)', () => {
    const log =
      evAt(0, 'BEGIN', 'refactor') +
      evAt(5, 'END', 'refactor') +
      evAt(10, 'BEGIN', 'refactor') +
      evAt(15, 'END', 'refactor') +
      evAt(20, 'BEGIN', 'refactor');

    // default MAX_ATTEMPTS_PER_STEP=3. BEGIN が 3 回 → ちょうど閾値
    const action = decideResumeAction(log);
    expect(action.kind).toBe('reset-to-task-start');
  });

  it('maxAttemptsPerStep を 5 に上げれば redo-step (attempt=4)', () => {
    const log =
      evAt(0, 'BEGIN', 'refactor') +
      evAt(5, 'END', 'refactor') +
      evAt(10, 'BEGIN', 'refactor') +
      evAt(15, 'END', 'refactor') +
      evAt(20, 'BEGIN', 'refactor');

    const action = decideResumeAction(log, { maxAttemptsPerStep: 5 });
    expect(action).toMatchObject({
      kind: 'redo-step',
      step: 'refactor',
      attempt: 4,
    });
  });
});

describe('resume-integration: パーサ健全性 (破損行と有効行の混在)', () => {
  it('壊れた行がある場合も有効行だけで正しく判定される', () => {
    const log =
      '# Progress Log\n' +
      'broken-timestamp\tBEGIN\tgreen-code\t{}\n' +
      evAt(0, 'BEGIN', 'green-code') +
      evAt(5, 'END', 'green-code', { status: 'completed' });

    const { events, warnings } = parseProgressLog(log);
    expect(events).toHaveLength(2);
    expect(warnings).toHaveLength(1);

    const action = decideResumeAction(log);
    expect(action.kind).toBe('redo-step');
    if (action.kind === 'redo-step') {
      expect(action.step).toBe('green-code');
      expect(action.attempt).toBe(2);
    }
  });
});
