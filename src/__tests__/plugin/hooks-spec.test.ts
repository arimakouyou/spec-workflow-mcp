import { describe, it, expect } from 'vitest';
import { writeFileSync, readFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { approveAll, copyFixture, runHook, S, hasCargo } from './helpers.js';

// 仕様フェーズのフック(guard-edit / guard-approval-request / session-start)の回帰テスト

const edit = (root: string, file: string, extra: Record<string, unknown> = {}) =>
  runHook('guard-edit.sh', root, { tool_name: 'Edit', tool_input: { file_path: join(root, file) }, ...extra });

describe('guard-edit', () => {
  it('承認台帳・承認記録は編集できない', () => {
    const root = copyFixture();
    expect(edit(root, '.spec-workflow/approvals/todo-api/ledger.json').status).toBe(2);
  });

  it('生成物の tasks.md は編集できない', () => {
    const root = copyFixture();
    const r = edit(root, `${S}/tasks.md`);
    expect(r.status).toBe(2);
    expect(r.stderr).toContain('生成物');
  });

  it('未承認の文書は編集できる', () => {
    const root = copyFixture();
    expect(edit(root, `${S}/design.md`).status).toBe(0);
  });

  it('承認済みの文書は編集できず、spec-change で開くと編集できる', async () => {
    const root = copyFixture();
    await approveAll(root);
    const r = edit(root, `${S}/design.md`);
    expect(r.status).toBe(2);
    expect(r.stderr).toContain('/spec-change');
    writeFileSync(join(root, S, '.change-open'), 'design\n');
    expect(edit(root, `${S}/design.md`).status).toBe(0);
  });

  it('上流の再承認で stale になった文書は修正のために編集できる', async () => {
    const root = copyFixture();
    const l = await approveAll(root);
    const fp = `${S}/design.md`;
    writeFileSync(join(root, fp), readFileSync(join(root, fp), 'utf-8') + '\n');
    const meta = await l.checkRequest(fp);
    await l.recordApproval({ id: 'redo', filePath: fp, metadata: { ledger: meta } });
    expect(edit(root, `${S}/test-design.md`).status).toBe(0);
  });

  it('実装セッション中、メインエージェントはソースを編集できず、サブエージェントはできる', () => {
    const root = copyFixture();
    mkdirSync(join(root, 'src'), { recursive: true });
    writeFileSync(join(root, '.spec-workflow/.active'), 'todo-api\n');
    expect(edit(root, 'src/lib.rs').status).toBe(2);
    expect(edit(root, 'src/lib.rs', { agent_id: 'abc', agent_type: 'spec-workflow-mcp:impl-worker' }).status).toBe(0);
  });
});

describe('guard-approval-request', () => {
  const request = (root: string, filePath: string) =>
    runHook('guard-approval-request.sh', root, { tool_name: 'mcp__plugin_spec-workflow-mcp_spec-workflow__approvals', tool_input: { action: 'request', filePath } });

  it('tasks.md の承認依頼は拒否する', () => {
    expect(request(copyFixture(), `${S}/tasks.md`).status).toBe(2);
  });

  it('lint が通らない文書の承認依頼は拒否する', () => {
    const root = copyFixture();
    const fp = join(root, S, 'requirements.md');
    writeFileSync(fp, readFileSync(fp, 'utf-8').replace('### REQ-2: Todo の一覧', '### REQ-1: Todo の一覧'));
    const r = request(root, `${S}/requirements.md`);
    expect(r.status).toBe(2);
    expect(r.stderr).toContain('L01');
  });

  it.skipIf(!hasCargo)('lint と sigcheck が通る design は依頼できる', { timeout: 600_000 }, () => {
    expect(request(copyFixture(), `${S}/design.md`).status).toBe(0);
  });

  it('status の問い合わせは検査しない', () => {
    const r = runHook('guard-approval-request.sh', copyFixture(), { tool_input: { action: 'status', approvalId: 'x' } });
    expect(r.status).toBe(0);
  });
});

describe('session-start', () => {
  it('実装セッション中でなければ何も出さない', () => {
    const r = runHook('session-start.sh', copyFixture(), { source: 'startup' });
    expect(r.status).toBe(0);
    expect(r.stdout).toBe('');
  });

  it('実装セッション中は状態と次のタスクを出す', async () => {
    const root = copyFixture();
    await approveAll(root);
    writeFileSync(join(root, '.spec-workflow/.active'), 'todo-api\n');
    const r = runHook('session-start.sh', root, { source: 'resume' });
    expect(r.stdout).toContain('design\tapproved');
    expect(r.stdout).toContain('次のタスク: P0-TOOLS');
  });
});
