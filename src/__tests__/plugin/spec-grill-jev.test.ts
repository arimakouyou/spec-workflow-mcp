import { describe, it, expect } from 'vitest';
import { mkdtempSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { run } from './helpers.js';

// spec-grill-jev.sh の回帰テスト。jevcli は応答を固定したスタブに差し替える。

function stub(body: string, exit = 0): { dir: string; jev: string; req: string } {
  const dir = mkdtempSync(join(tmpdir(), 'grill-jev-'));
  const jev = join(dir, 'jevcli');
  writeFileSync(jev, `#!/usr/bin/env bash\ncat >/dev/null\ncat <<'EOF'\n${body}\nEOF\nexit ${exit}\n`, { mode: 0o755 });
  const req = join(dir, 'req.json');
  writeFileSync(req, '{"state": "s", "questions": {}}');
  return { dir, jev, req };
}

const answers = {
  answers: {
    yes_hi: { type: 'noul', noul: 0.9 },
    no_lo: { type: 'noul', noul: 0.1 },
    mid: { type: 'noul', noul: 0.5 },
    // confidence と最大確率が閾値をまたいで食い違う場合は、最大確率で判定する
    pick: { type: 'choice', choice: 'a', confidence: 0.5, probabilities: { a: 0.7, b: 0.2, c: 0.1 } },
    conf_only: { type: 'choice', choice: 'a', confidence: 0.9, probabilities: { a: 0.55, b: 0.3, c: 0.15 } },
    close: { type: 'choice', choice: 'a', confidence: 0.6, probabilities: { a: 0.5, b: 0.45, c: 0.05 } },
    level: { type: 'score', score: 1.1, confidence: 0.4, probabilities: { '0': 0.1, '1': 0.8, '2': 0.1 }, legend: { '0': 'low', '1': 'mid', '2': 'high' } },
    flat: { type: 'score', score: 1, confidence: 0.6, probabilities: { '0': 0.3, '1': 0.4, '2': 0.3 }, legend: { '0': 'low', '1': 'mid', '2': 'high' } }
  },
  model: 'typesafe/jev', usage: { cost: 0.001 }
};

describe('spec-grill-jev', () => {
  it('閾値を満たした問いだけを decided に入れる', () => {
    const s = stub(JSON.stringify(answers));
    const r = run('spec-grill-jev.sh', [s.req], { env: { JEVCLI: s.jev } });
    expect(r.status).toBe(0);
    const out = JSON.parse(r.stdout);
    expect(Object.keys(out.decided).sort()).toEqual(['level', 'no_lo', 'pick', 'yes_hi']);
    expect(Object.keys(out.undecided).sort()).toEqual(['close', 'conf_only', 'flat', 'mid']);
    expect(out.decided.yes_hi.answer).toBe('yes');
    expect(out.decided.no_lo.answer).toBe('no');
    expect(out.decided.pick.answer).toBe('a');
    expect(out.decided.level.answer).toBe('mid');
    expect(out.cost).toBe(0.001);
  });

  it('jevcli の失敗は exit 1 で error JSON をそのまま返す', () => {
    const s = stub('{"error": {"kind": "config", "message": "LITELLM_API_KEY が無い"}}', 1);
    const r = run('spec-grill-jev.sh', [s.req], { env: { JEVCLI: s.jev } });
    expect(r.status).toBe(1);
    expect(JSON.parse(r.stdout).error.kind).toBe('config');
  });

  it('jevcli が無ければ exit 4', () => {
    const s = stub('{}');
    const r = run('spec-grill-jev.sh', [s.req], { env: { JEVCLI: join(s.dir, 'missing') } });
    expect(r.status).toBe(4);
  });
});
