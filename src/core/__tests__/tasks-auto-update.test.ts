import { describe, it, expect } from 'vitest';
import {
  computeTaskState,
  syncTasksMarkdown,
  type TaskState,
} from '../tasks-auto-update.js';

const ts = (s: string): string => `2026-04-19T14:14:${s}Z`;

function ev(event: string, step: string, meta: unknown = {}): string {
  return `${ts('10.000')}\t${event}\t${step}\t${JSON.stringify(meta)}\n`;
}

describe('tasks-auto-update / computeTaskState', () => {
  it('null なら pending', () => {
    expect(computeTaskState(null)).toBe('pending');
  });

  it('undefined なら pending', () => {
    expect(computeTaskState(undefined)).toBe('pending');
  });

  it('空文字列なら pending', () => {
    expect(computeTaskState('')).toBe('pending');
  });

  it('ヘッダのみなら pending', () => {
    expect(computeTaskState('# header only\n')).toBe('pending');
  });

  it('BEGIN が最後にあれば in-progress', () => {
    const content = ev('BEGIN', 'red-write');
    expect(computeTaskState(content)).toBe('in-progress');
  });

  it('END が最後にあれば in-progress', () => {
    const content = ev('BEGIN', 'red-write') + ev('END', 'red-write');
    expect(computeTaskState(content)).toBe('in-progress');
  });

  it('VERIFIED が最後にあれば in-progress', () => {
    const content =
      ev('BEGIN', 'red-write') +
      ev('END', 'red-write') +
      ev('VERIFIED', 'red-write');
    expect(computeTaskState(content)).toBe('in-progress');
  });

  it('COMPLETE が最後にあれば completed', () => {
    const content =
      ev('BEGIN', 'log') + ev('COMPLETE', 'log', { log_id: 'x' });
    expect(computeTaskState(content)).toBe('completed');
  });

  it('FAILED が最後にあっても in-progress (pending に戻さない)', () => {
    const content =
      ev('BEGIN', 'green-code') + ev('FAILED', 'green-code', { reason: 'x' });
    expect(computeTaskState(content)).toBe('in-progress');
  });
});

describe('tasks-auto-update / syncTasksMarkdown', () => {
  const tasksMd = `## Phase 1: Core

- [ ] 1.1 First task
  - File: a.ts

- [ ] 1.2 Second task
  - File: b.ts

- [ ] 2.1 Third task
  - File: c.ts
`;

  it('pending → in-progress を反映する', () => {
    const map = new Map<string, TaskState>([['1.1', 'in-progress']]);
    const result = syncTasksMarkdown(tasksMd, map);
    expect(result.updates).toEqual([
      { taskId: '1.1', before: 'pending', after: 'in-progress' },
    ]);
    expect(result.updatedMarkdown).toContain('[-] 1.1 First task');
  });

  it('pending → completed を反映する', () => {
    const map = new Map<string, TaskState>([['1.2', 'completed']]);
    const result = syncTasksMarkdown(tasksMd, map);
    expect(result.updates).toHaveLength(1);
    expect(result.updatedMarkdown).toContain('[x] 1.2 Second task');
  });

  it('変化なしの taskId は updates に含めない', () => {
    const map = new Map<string, TaskState>([['1.1', 'pending']]);
    const result = syncTasksMarkdown(tasksMd, map);
    expect(result.updates).toEqual([]);
    expect(result.updatedMarkdown).toBe(tasksMd);
  });

  it('複数 task を同時に更新する', () => {
    const map = new Map<string, TaskState>([
      ['1.1', 'completed'],
      ['1.2', 'in-progress'],
      ['2.1', 'completed'],
    ]);
    const result = syncTasksMarkdown(tasksMd, map);
    expect(result.updates).toHaveLength(3);
    expect(result.updatedMarkdown).toContain('[x] 1.1 First task');
    expect(result.updatedMarkdown).toContain('[-] 1.2 Second task');
    expect(result.updatedMarkdown).toContain('[x] 2.1 Third task');
  });

  it('tasks.md に無い taskId は missingTaskIds に入り updates には入らない', () => {
    const map = new Map<string, TaskState>([
      ['1.1', 'completed'],
      ['9.9', 'completed'],
    ]);
    const result = syncTasksMarkdown(tasksMd, map);
    expect(result.missingTaskIds).toEqual(['9.9']);
    expect(result.updates).toHaveLength(1);
    expect(result.updates[0]?.taskId).toBe('1.1');
  });

  it('既に completed な task を completed で同期しても副作用なし', () => {
    const md = tasksMd.replace('[ ] 1.1 First task', '[x] 1.1 First task');
    const map = new Map<string, TaskState>([['1.1', 'completed']]);
    const result = syncTasksMarkdown(md, map);
    expect(result.updates).toEqual([]);
    expect(result.updatedMarkdown).toBe(md);
  });
});
