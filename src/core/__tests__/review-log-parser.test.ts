import { describe, it, expect } from 'vitest';
import {
  aggregateReviewProcess,
  parseReviewLog,
} from '../review-log-parser.js';

const ts = (s: string): string => `2026-04-19T14:14:${s}Z`;

function line(
  timestamp: string,
  source: string,
  attempt: number,
  action: string,
  categories: string[],
  summary: string,
): string {
  return [
    timestamp,
    source,
    String(attempt),
    action,
    JSON.stringify(categories),
    summary,
  ].join('\t');
}

function logText(...lines: readonly string[]): string {
  return lines.map((l) => `${l}\n`).join('');
}

describe('review-log-parser / parseReviewLog', () => {
  it('空文字列なら entries も warnings も空', () => {
    const r = parseReviewLog('');
    expect(r.entries).toEqual([]);
    expect(r.warnings).toEqual([]);
  });

  it('ヘッダと空行はスキップ', () => {
    const r = parseReviewLog('# Review Log\n\n# task=1.1\n\n');
    expect(r.entries).toEqual([]);
    expect(r.warnings).toEqual([]);
  });

  it('有効な 1 行をパース', () => {
    const c = logText(
      line(
        ts('00.000'),
        'pre-push-review',
        1,
        'commit',
        ['naming'],
        'minor rename',
      ),
    );
    const r = parseReviewLog(c);
    expect(r.entries).toHaveLength(1);
    expect(r.entries[0]).toMatchObject({
      timestamp: ts('00.000'),
      source: 'pre-push-review',
      attempt: 1,
      action: 'commit',
      categories: ['naming'],
      summary: 'minor rename',
    });
  });

  it('未知の source は warning でスキップ', () => {
    const c = logText(
      line(ts('00.000'), 'weird-source', 1, 'commit', [], 'x'),
      line(ts('00.100'), 'codex-review', 1, 'commit', [], 'y'),
    );
    const r = parseReviewLog(c);
    expect(r.entries).toHaveLength(1);
    expect(r.warnings[0]?.reason).toMatch(/unknown review source/);
  });

  it('未知の action は warning でスキップ', () => {
    const c = logText(
      line(ts('00.000'), 'pre-push-review', 1, 'weird', [], 'x'),
    );
    const r = parseReviewLog(c);
    expect(r.entries).toHaveLength(0);
    expect(r.warnings[0]?.reason).toMatch(/unknown action/);
  });

  it('attempt が非正整数なら warning', () => {
    const c =
      `${ts('00.000')}\tpre-push-review\t0\tcommit\t[]\tx\n` +
      `${ts('00.100')}\tpre-push-review\tzero\tcommit\t[]\ty\n`;
    const r = parseReviewLog(c);
    expect(r.entries).toHaveLength(0);
    expect(r.warnings).toHaveLength(2);
  });

  it('categories が配列でなければ warning', () => {
    const c =
      `${ts('00.000')}\tpre-push-review\t1\tcommit\t{"not":"array"}\tx\n`;
    const r = parseReviewLog(c);
    expect(r.entries).toHaveLength(0);
    expect(r.warnings[0]?.reason).toMatch(/string array/);
  });
});

describe('review-log-parser / aggregateReviewProcess', () => {
  it('空ログなら unknown outcome', () => {
    const r = aggregateReviewProcess('');
    expect(r).toEqual({
      reworkCount: 0,
      reviewOutcome: 'unknown',
      findings: [],
    });
  });

  it('最後が commit なら approved', () => {
    const c = logText(
      line(ts('00.000'), 'codex-review', 1, 'rework', ['security'], 'CVE found'),
      line(ts('00.100'), 'codex-review', 2, 'commit', [], 'fixed'),
    );
    const r = aggregateReviewProcess(c);
    expect(r.reviewOutcome).toBe('approved');
    expect(r.reworkCount).toBe(1);
    expect(r.findings).toHaveLength(2);
  });

  it('最後が rework なら rejected', () => {
    const c = logText(
      line(ts('00.000'), 'pre-push-review', 1, 'rework', ['tests'], 'missing'),
    );
    const r = aggregateReviewProcess(c);
    expect(r.reviewOutcome).toBe('rejected');
    expect(r.reworkCount).toBe(1);
  });

  it('最後が escalate なら escalated', () => {
    const c = logText(
      line(ts('00.000'), 'pre-push-review', 1, 'escalate', [], 'spec mismatch'),
    );
    const r = aggregateReviewProcess(c);
    expect(r.reviewOutcome).toBe('escalated');
  });
});
