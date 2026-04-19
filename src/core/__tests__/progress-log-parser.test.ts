import { describe, it, expect } from 'vitest';
import {
  DEFAULT_STEP_ORDER,
  DEFAULT_MAX_ATTEMPTS_PER_STEP,
  decideResumeAction,
  decideResumeActionFromEvents,
  parseProgressLog,
  type ProgressEvent,
  type ResumeAction,
} from '../progress-log-parser.js';

const ts = (suffix: string): string => `2026-04-19T14:14:${suffix}Z`;

function line(
  timestamp: string,
  event: string,
  stepId: string,
  meta: unknown,
): string {
  return `${timestamp}\t${event}\t${stepId}\t${JSON.stringify(meta)}`;
}

function logText(...lines: readonly string[]): string {
  return lines.map((l) => `${l}\n`).join('');
}

describe('progress-log-parser / parseProgressLog', () => {
  it('空文字列を受け取ったら events も warnings も空', () => {
    const result = parseProgressLog('');
    expect(result.events).toEqual([]);
    expect(result.warnings).toEqual([]);
  });

  it('ヘッダコメント (#) と空行はスキップされる', () => {
    const content = logText(
      '# Progress Log: Task 1.2',
      '',
      '# spec=foo task=1.2',
      '',
    );
    const result = parseProgressLog(content);
    expect(result.events).toEqual([]);
    expect(result.warnings).toEqual([]);
  });

  it('有効な 1 行をパースできる', () => {
    const content = logText(
      line(ts('11.000'), 'BEGIN', 'red-write', { checkpoint: 'tag-1' }),
    );
    const result = parseProgressLog(content);
    expect(result.events).toHaveLength(1);
    expect(result.events[0]).toMatchObject({
      timestamp: ts('11.000'),
      event: 'BEGIN',
      stepId: 'red-write',
      meta: { checkpoint: 'tag-1' },
      lineNumber: 1,
    });
    expect(result.warnings).toEqual([]);
  });

  it('複数行を時系列通りにパースする', () => {
    const content = logText(
      '# Progress Log',
      line(ts('11.000'), 'BEGIN', 'red-write', {}),
      line(ts('12.000'), 'END', 'red-write', { status: 'ok' }),
      line(ts('13.000'), 'VERIFIED', 'red-write', { evidence: 'tests_failed' }),
    );
    const result = parseProgressLog(content);
    expect(result.events.map((e) => e.event)).toEqual([
      'BEGIN',
      'END',
      'VERIFIED',
    ]);
  });

  it('タブ区切りのフィールド数が 4 でない行は warning でスキップ', () => {
    const content = logText(
      `${ts('11.000')}\tBEGIN\tred-write`,
      line(ts('12.000'), 'END', 'red-write', {}),
    );
    const result = parseProgressLog(content);
    expect(result.events).toHaveLength(1);
    expect(result.events[0]?.event).toBe('END');
    expect(result.warnings).toHaveLength(1);
    expect(result.warnings[0]?.reason).toMatch(/4 tab-separated/);
  });

  it('末尾に改行がない最終行は不完全として warning', () => {
    const content =
      `${line(ts('11.000'), 'BEGIN', 'red-write', {})}\n` +
      `${line(ts('12.000'), 'END', 'red-write', {})}`;
    const result = parseProgressLog(content);
    expect(result.events.map((e) => e.event)).toEqual(['BEGIN']);
    expect(result.warnings).toHaveLength(1);
    expect(result.warnings[0]?.reason).toMatch(/no newline/);
  });

  it('不正な timestamp の行は warning でスキップ', () => {
    const content = logText(
      `not-a-timestamp\tBEGIN\tred-write\t{}`,
      line(ts('12.000'), 'BEGIN', 'red-write', {}),
    );
    const result = parseProgressLog(content);
    expect(result.events).toHaveLength(1);
    expect(result.warnings[0]?.reason).toMatch(/invalid ISO 8601/);
  });

  it('未知の event 種別は warning でスキップ', () => {
    const content = logText(
      `${ts('11.000')}\tWEIRD\tred-write\t{}`,
      line(ts('12.000'), 'BEGIN', 'red-write', {}),
    );
    const result = parseProgressLog(content);
    expect(result.events).toHaveLength(1);
    expect(result.warnings[0]?.reason).toMatch(/unknown event kind/);
  });

  it('step id に不正な文字が含まれる行は warning でスキップ', () => {
    const content = logText(
      `${ts('11.000')}\tBEGIN\tRED_WRITE\t{}`,
      line(ts('12.000'), 'BEGIN', 'red-write', {}),
    );
    const result = parseProgressLog(content);
    expect(result.events).toHaveLength(1);
    expect(result.warnings[0]?.reason).toMatch(/invalid step id/);
  });

  it('meta が不正 JSON の行は warning でスキップ', () => {
    const content = logText(
      `${ts('11.000')}\tBEGIN\tred-write\t{not json`,
      line(ts('12.000'), 'BEGIN', 'red-write', {}),
    );
    const result = parseProgressLog(content);
    expect(result.events).toHaveLength(1);
    expect(result.warnings[0]?.reason).toMatch(/meta is not a valid/);
  });

  it('meta が JSON 配列の行は warning でスキップ (object 必須)', () => {
    const content = logText(
      `${ts('11.000')}\tBEGIN\tred-write\t[1,2,3]`,
    );
    const result = parseProgressLog(content);
    expect(result.events).toHaveLength(0);
    expect(result.warnings).toHaveLength(1);
  });
});

describe('progress-log-parser / decideResumeAction', () => {
  it('content が null の場合は start-fresh (先頭 step)', () => {
    const action = decideResumeAction(null);
    expect(action).toEqual({
      kind: 'start-fresh',
      step: DEFAULT_STEP_ORDER[0],
      attempt: 1,
    });
  });

  it('content が undefined の場合は start-fresh', () => {
    const action = decideResumeAction(undefined);
    expect(action.kind).toBe('start-fresh');
  });

  it('空文字列なら start-fresh', () => {
    const action = decideResumeAction('');
    expect(action.kind).toBe('start-fresh');
  });

  it('ヘッダだけで event が無ければ start-fresh', () => {
    const action = decideResumeAction('# header\n\n');
    expect(action.kind).toBe('start-fresh');
  });

  it('最後が VERIFIED なら次 step の resume-next', () => {
    const content = logText(
      line(ts('11.000'), 'BEGIN', 'discover', {}),
      line(ts('12.000'), 'END', 'discover', { status: 'ok' }),
      line(ts('13.000'), 'VERIFIED', 'discover', {}),
    );
    const action = decideResumeAction(content);
    expect(action).toEqual({
      kind: 'resume-next',
      step: 'red-write',
      attempt: 1,
    });
  });

  it('最後が VERIFIED で、それが stepOrder の末尾なら needs-complete', () => {
    const content = logText(
      line(ts('11.000'), 'BEGIN', 'phase-commit', {}),
      line(ts('12.000'), 'VERIFIED', 'phase-commit', {}),
    );
    const action = decideResumeAction(content);
    expect(action).toEqual({ kind: 'needs-complete', step: 'phase-commit' });
  });

  it('最後が END で VERIFIED 無しなら redo-step attempt=2', () => {
    const content = logText(
      line(ts('11.000'), 'BEGIN', 'green-code', {}),
      line(ts('12.000'), 'END', 'green-code', { status: 'ok' }),
    );
    const action = decideResumeAction(content);
    expect(action).toEqual({
      kind: 'redo-step',
      step: 'green-code',
      attempt: 2,
      reason: 'delegation returned but verification was not recorded',
    });
  });

  it('最後が BEGIN で END 無しなら redo-step attempt=1+BEGIN 数', () => {
    const content = logText(
      line(ts('11.000'), 'BEGIN', 'green-code', {}),
    );
    const action = decideResumeAction(content);
    expect(action).toEqual({
      kind: 'redo-step',
      step: 'green-code',
      attempt: 2,
      reason: 'delegation did not finish (subagent interruption)',
    });
  });

  it('同 step の BEGIN が max に達したら reset-to-task-start', () => {
    const content = logText(
      line(ts('11.000'), 'BEGIN', 'green-code', {}),
      line(ts('11.500'), 'END', 'green-code', { status: 'error' }),
      line(ts('12.000'), 'BEGIN', 'green-code', {}),
      line(ts('12.500'), 'END', 'green-code', { status: 'error' }),
      line(ts('13.000'), 'BEGIN', 'green-code', {}),
      line(ts('13.500'), 'END', 'green-code', { status: 'error' }),
    );
    const action = decideResumeAction(content);
    expect(action.kind).toBe('reset-to-task-start');
    if (action.kind === 'reset-to-task-start') {
      expect(action.reason).toMatch(/green-code/);
    }
  });

  it('maxAttemptsPerStep を option で調整できる', () => {
    const content = logText(
      line(ts('11.000'), 'BEGIN', 'green-code', {}),
      line(ts('12.000'), 'END', 'green-code', {}),
      line(ts('13.000'), 'BEGIN', 'green-code', {}),
    );
    const action = decideResumeAction(content, { maxAttemptsPerStep: 2 });
    expect(action.kind).toBe('reset-to-task-start');
  });

  it('最後が COMPLETE なら already-done', () => {
    const content = logText(
      line(ts('11.000'), 'BEGIN', 'log', {}),
      line(ts('12.000'), 'COMPLETE', 'log', { log_id: 'abc' }),
    );
    const action = decideResumeAction(content);
    expect(action).toEqual({ kind: 'already-done' });
  });

  it('最後が FAILED なら escalate、meta.reason を引き継ぐ', () => {
    const content = logText(
      line(ts('11.000'), 'BEGIN', 'green-code', {}),
      line(ts('12.000'), 'END', 'green-code', {}),
      line(ts('13.000'), 'FAILED', 'green-code', { reason: '回復不能エラー' }),
    );
    const action = decideResumeAction(content);
    expect(action).toEqual({
      kind: 'escalate',
      step: 'green-code',
      reason: '回復不能エラー',
    });
  });

  it('FAILED の meta に reason が無い場合はフォールバック文言', () => {
    const content = logText(
      line(ts('11.000'), 'BEGIN', 'green-code', {}),
      line(ts('12.000'), 'FAILED', 'green-code', {}),
    );
    const action = decideResumeAction(content);
    expect(action.kind).toBe('escalate');
    if (action.kind === 'escalate') {
      expect(action.reason).toBe('step failed');
    }
  });

  it('壊れた行が混じっていても有効行の末尾から判定する', () => {
    const content =
      '# Progress Log\n' +
      'garbage-line\n' +
      `${line(ts('11.000'), 'BEGIN', 'green-code', {})}\n` +
      `${line(ts('12.000'), 'END', 'green-code', {})}\n` +
      `${line(ts('13.000'), 'VERIFIED', 'green-code', {})}\n`;
    const action = decideResumeAction(content);
    expect(action).toEqual({
      kind: 'resume-next',
      step: 'green-verify',
      attempt: 1,
    });
  });

  it('カスタム stepOrder を受け付ける', () => {
    const customOrder = ['alpha', 'bravo', 'charlie'] as const;
    const content = logText(line(ts('11.000'), 'VERIFIED', 'alpha', {}));
    const action = decideResumeAction(content, { stepOrder: customOrder });
    expect(action).toEqual({
      kind: 'resume-next',
      step: 'bravo',
      attempt: 1,
    });
  });

  it('VERIFIED の step が stepOrder に無い場合は needs-complete', () => {
    const content = logText(line(ts('11.000'), 'VERIFIED', 'unknown-step', {}));
    const action = decideResumeAction(content);
    expect(action).toEqual({
      kind: 'needs-complete',
      step: 'unknown-step',
    });
  });
});

describe('progress-log-parser / decideResumeActionFromEvents', () => {
  it('events 配列を直接渡しても動く', () => {
    const events: ProgressEvent[] = [
      {
        timestamp: ts('11.000'),
        event: 'VERIFIED',
        stepId: 'discover',
        meta: {},
        rawLine: '',
        lineNumber: 1,
      },
    ];
    const action = decideResumeActionFromEvents(events);
    const expected: ResumeAction = {
      kind: 'resume-next',
      step: 'red-write',
      attempt: 1,
    };
    expect(action).toEqual(expected);
  });

  it('空配列なら start-fresh', () => {
    const action = decideResumeActionFromEvents([]);
    expect(action.kind).toBe('start-fresh');
  });
});

describe('progress-log-parser / 定数', () => {
  it('DEFAULT_STEP_ORDER は凍結されている', () => {
    expect(Object.isFrozen(DEFAULT_STEP_ORDER)).toBe(true);
  });

  it('DEFAULT_MAX_ATTEMPTS_PER_STEP は 3', () => {
    expect(DEFAULT_MAX_ATTEMPTS_PER_STEP).toBe(3);
  });
});
