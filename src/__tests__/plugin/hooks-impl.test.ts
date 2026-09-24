import { describe, it, expect } from 'vitest';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'fs';
import { join } from 'path';
import { copyFixture, runHook, S, SPEC } from './helpers.js';

// 実装セッションのフック(guard-agent / record-subagent / guard-git / stop-failure)の回帰テスト

function session(): string {
  const root = copyFixture();
  writeFileSync(join(root, '.spec-workflow/.active'), `${SPEC}\n`);
  return root;
}

const agent = (root: string, subagent: string, task: string, spec = SPEC) =>
  runHook('guard-agent.sh', root, {
    tool_name: 'Agent',
    tool_input: { subagent_type: `spec-workflow-mcp:${subagent}`, description: 'x', prompt: `TASK: ${task}\nSPEC: ${spec}\nROOT: ${root}\nMODE: implement` }
  });

const lockPath = (root: string) => join(root, '.spec-workflow/.agent-lock');
const runsDir = (root: string, task: string) => join(root, S, 'runs', task);

describe('guard-agent', () => {
  it('実装セッション外では何もしない', () => {
    const root = copyFixture();
    expect(agent(root, 'impl-worker', 'DES-2').status).toBe(0);
    expect(existsSync(lockPath(root))).toBe(false);
  });

  it('TASK / SPEC の見出しが無い起動は拒否する', () => {
    const root = session();
    const r = runHook('guard-agent.sh', root, { tool_input: { subagent_type: 'spec-workflow-mcp:impl-worker', prompt: 'please implement' } });
    expect(r.status).toBe(2);
  });

  it('直列: 実行中の agent がいれば次を起動しない', () => {
    const root = session();
    expect(agent(root, 'impl-worker', 'DES-2').status).toBe(0);
    expect(existsSync(lockPath(root))).toBe(true);
    const r = agent(root, 'impl-worker', 'DES-3');
    expect(r.status).toBe(2);
    expect(r.stderr).toContain('実行中');
  });

  it('タスクの種類に合わない agent は拒否する', () => {
    const root = session();
    expect(agent(root, 'integ-test-worker', 'DES-2').stderr).toContain('TST / IT');
    expect(agent(root, 'impl-worker', 'P2-IT').status).toBe(2);
  });

  it('順序: 検証は実装の後、レビューは検証の後', () => {
    const root = session();
    expect(agent(root, 'unit-test-engineer', 'DES-2').stderr).toContain('実装の記録が無い');
    mkdirSync(runsDir(root, 'DES-2'), { recursive: true });
    writeFileSync(join(runsDir(root, 'DES-2'), 'impl.json'), '{"task":"DES-2","status":"done"}');
    expect(agent(root, 'review-worker', 'DES-2').stderr).toContain('検証の記録が無い');
    expect(agent(root, 'unit-test-engineer', 'DES-2').status).toBe(0);
    rmSync(lockPath(root));
    writeFileSync(join(runsDir(root, 'DES-2'), 'verify.json'), '{"task":"DES-2","verdict":"pass"}');
    expect(agent(root, 'review-worker', 'DES-2').status).toBe(0);
  });

  it('Phase レビューは機械検査の結果が無ければ起動しない', () => {
    const root = session();
    expect(agent(root, 'review-worker', 'P1-REVIEW').stderr).toContain('spec-phase-check.sh');
  });

  it('別の spec のタスクは拒否し、調査・文書作成の agent は通す', () => {
    const root = session();
    expect(agent(root, 'impl-worker', 'DES-2', 'other-spec').status).toBe(2);
    const r = runHook('guard-agent.sh', root, { tool_input: { subagent_type: 'Explore', prompt: 'look around' } });
    expect(r.status).toBe(0);
  });
});

describe('record-subagent', () => {
  const stop = (root: string, agentType: string, message: string, stopActive = false) =>
    runHook('record-subagent.sh', root, {
      hook_event_name: 'SubagentStop',
      agent_id: 'a1',
      agent_type: `spec-workflow-mcp:${agentType}`,
      last_assistant_message: message,
      stop_hook_active: stopActive
    });

  it('最終メッセージ末尾の JSON を role ごとに記録し、ロックを解除する', () => {
    const root = session();
    writeFileSync(lockPath(root), 'impl-worker DES-2');
    const r = stop(root, 'impl-worker', 'done.\n```json\n{"task": "DES-2", "status": "done", "tests": {"files": ["a"]}}\n```\n');
    expect(r.status).toBe(0);
    expect(JSON.parse(readFileSync(join(runsDir(root, 'DES-2'), 'impl.json'), 'utf-8')).status).toBe('done');
    expect(readFileSync(join(runsDir(root, 'DES-2'), 'history.jsonl'), 'utf-8')).toContain('"role":"impl"');
    expect(existsSync(lockPath(root))).toBe(false);
  });

  it('JSON が無ければ出し直させ、二度目(stop_hook_active)はロックを解除して通す', () => {
    const root = session();
    writeFileSync(lockPath(root), 'review-worker DES-2');
    expect(stop(root, 'review-worker', 'looks good').status).toBe(2);
    expect(existsSync(lockPath(root))).toBe(true);
    expect(stop(root, 'review-worker', 'looks good', true).status).toBe(0);
    expect(existsSync(lockPath(root))).toBe(false);
  });

  it('対象外の agent は記録しない', () => {
    const root = session();
    expect(stop(root, 'spec-author', 'no json').status).toBe(0);
  });
});

describe('guard-git', () => {
  const bash = (root: string, command: string, agentType?: string) =>
    runHook('guard-git.sh', root, {
      tool_name: 'Bash',
      tool_input: { command },
      ...(agentType ? { agent_id: 'a1', agent_type: `spec-workflow-mcp:${agentType}` } : {})
    });

  it('実装セッション中は生の git commit / push / reset を拒否する(cd && や -C も)', () => {
    const root = session();
    expect(bash(root, 'git commit -m x').status).toBe(2);
    expect(bash(root, 'cd sub && git commit -am x').status).toBe(2);
    expect(bash(root, 'git -C /tmp/x push origin main').status).toBe(2);
    expect(bash(root, 'git reset --hard HEAD~1').status).toBe(2);
    expect(bash(root, 'git status --porcelain').status).toBe(0);
    expect(bash(root, 'git diff HEAD').status).toBe(0);
  });

  it('実装セッション外の git はそのまま通す', () => {
    expect(bash(copyFixture(), 'git commit -m x').status).toBe(0);
  });

  it('spec-git.sh のサブコマンドは決められた主体だけが実行できる', () => {
    const root = session();
    expect(bash(root, 'bash scripts/spec-git.sh commit todo-api DES-2').status).toBe(2);
    expect(bash(root, 'bash scripts/spec-git.sh commit todo-api DES-2', 'review-worker').status).toBe(0);
    expect(bash(root, 'bash scripts/spec-git.sh start todo-api DES-2', 'impl-worker').status).toBe(2);
    expect(bash(root, 'bash scripts/spec-git.sh start todo-api DES-2').status).toBe(0);
    expect(bash(root, 'bash scripts/spec-git.sh checkpoint todo-api DES-2 a_tests.rs', 'impl-worker').status).toBe(0);
    expect(bash(root, 'bash scripts/spec-git.sh record todo-api P0-TOOLS').status).toBe(0);
    expect(bash(root, 'bash scripts/spec-git.sh record todo-api P1-REVIEW').status).toBe(2);
  });

  it('承認台帳への Bash での書き込みはセッションの内外を問わず拒否する', () => {
    expect(bash(copyFixture(), 'echo {} > .spec-workflow/approvals/todo-api/ledger.json').status).toBe(2);
  });
});

describe('stop-failure', () => {
  it('実装セッション中の API エラーを .resume に記録する', () => {
    const root = session();
    writeFileSync(lockPath(root), 'impl-worker DES-2');
    const r = runHook('stop-failure.sh', root, { hook_event_name: 'StopFailure', error: 'rate_limit' });
    expect(r.status).toBe(0);
    const resume = JSON.parse(readFileSync(join(root, '.spec-workflow/.resume'), 'utf-8'));
    expect(resume).toMatchObject({ spec: SPEC, reason: 'rate_limit' });
    expect(existsSync(lockPath(root))).toBe(false);
  });
});
