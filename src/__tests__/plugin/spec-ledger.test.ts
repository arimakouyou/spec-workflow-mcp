import { describe, it, expect } from 'vitest';
import { spawnSync } from 'child_process';
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync, existsSync } from 'fs';
import { tmpdir } from 'os';
import { join, resolve } from 'path';
import { fileURLToPath } from 'url';
import { SpecLedger, LedgerError, identifyDocument } from '../../core/spec-ledger.js';
import { ApprovalStorage } from '../../dashboard/approval-storage.js';

// 承認台帳(contract/approval-ledger-v1.md)の回帰テスト。
// 共有フィクスチャで TS 実装と Bash 実装(spec-state.sh)の状態判定が一致することと、
// request / approve / undo の拒否条件を確かめる。

const HERE = resolve(fileURLToPath(import.meta.url), '..');
const REPO = resolve(HERE, '../../..');
const FIXTURES = join(REPO, '.claude-plugin/contract/fixtures');
const STATE_SH = join(REPO, '.claude-plugin/scripts/spec-state.sh');

function ledgerFor(root: string) {
  return new SpecLedger(join(root, '.spec-workflow/approvals'), async (rel) => {
    const abs = join(root, rel);
    return existsSync(abs) ? abs : null;
  });
}

function pendingPaths(root: string): string[] {
  const dir = join(root, '.spec-workflow/approvals');
  if (!existsSync(dir)) return [];
  const out: string[] = [];
  for (const key of readdirSync(dir)) {
    const kd = join(dir, key);
    for (const f of readdirSync(kd)) {
      if (!f.endsWith('.json') || f === 'ledger.json') continue;
      const a = JSON.parse(readFileSync(join(kd, f), 'utf-8'));
      if (a.status === 'pending') out.push(a.filePath);
    }
  }
  return out;
}

function parseExpected(file: string): Record<string, string> {
  return Object.fromEntries(
    readFileSync(file, 'utf-8')
      .split('\n')
      .filter(Boolean)
      .map((l) => l.split('\t') as [string, string]),
  );
}

describe('承認台帳: 共有フィクスチャ(TS と Bash の一致)', () => {
  for (const name of readdirSync(FIXTURES)) {
    const root = join(FIXTURES, name, 'project');
    const expected = parseExpected(join(FIXTURES, name, 'expected.tsv'));

    it(`${name}: TS の状態判定が期待値と一致する`, async () => {
      expect(await ledgerFor(root).states('demo', pendingPaths(root))).toEqual(expected);
    });

    it(`${name}: Bash の状態判定が期待値と一致する`, () => {
      const r = spawnSync('bash', [STATE_SH, 'demo', root], { encoding: 'utf-8' });
      expect(r.status).toBe(0);
      expect(parseStates(r.stdout)).toEqual(expected);
    });
  }
});

function parseStates(text: string): Record<string, string> {
  return Object.fromEntries(text.split('\n').filter(Boolean).map((l) => l.split('\t') as [string, string]));
}

/** 空の一時プロジェクトを作り、文書を書く */
function project(files: Record<string, string>): string {
  const root = mkdtempSync(join(tmpdir(), 'ledger-'));
  for (const [rel, content] of Object.entries(files)) {
    mkdirSync(join(root, rel, '..'), { recursive: true });
    writeFileSync(join(root, rel), content);
  }
  return root;
}

const S = '.spec-workflow/specs/demo';
const STEER = '.spec-workflow/steering';

async function approve(l: SpecLedger, filePath: string, id: string) {
  const meta = await l.checkRequest(filePath);
  await l.recordApproval({ id, filePath, metadata: meta ? { ledger: meta } : undefined });
}

async function expectCode(p: Promise<unknown>, code: string) {
  await expect(p).rejects.toBeInstanceOf(LedgerError);
  await p.catch((e: LedgerError) => expect(e.code).toBe(code));
}

describe('承認台帳: 操作', () => {
  it('filePath から対象文書を判定する', () => {
    expect(identifyDocument(`${S}/design.md`)).toEqual({ key: 'demo', doc: 'design' });
    expect(identifyDocument(`./${STEER}/tech.md`)).toEqual({ key: 'steering', doc: 'tech' });
    expect(identifyDocument(`${S}/tasks.md`)).toBe('tasks');
    expect(identifyDocument(`${S}/notes.md`)).toBeNull();
  });

  it('tasks.md の承認リクエストは TASKS_GENERATED で拒否する', async () => {
    const root = project({ [`${S}/tasks.md`]: 'x' });
    await expectCode(ledgerFor(root).checkRequest(`${S}/tasks.md`), 'TASKS_GENERATED');
  });

  it('steering が未承認なら request-spec を依頼できない', async () => {
    const root = project({ [`${S}/request-spec.md`]: 'rs' });
    await expectCode(ledgerFor(root).checkRequest(`${S}/request-spec.md`), 'STEERING_NOT_APPROVED:product');
  });

  it('上流が未承認なら依頼できない', async () => {
    const root = project({ [`${S}/requirements.md`]: 'req' });
    await expectCode(ledgerFor(root).checkRequest(`${S}/requirements.md`), 'UPSTREAM_NOT_APPROVED:request-spec');
  });

  it('連鎖を承認でき、上流を承認後に変更すると下流は依頼できず stale になる', async () => {
    const root = project({
      [`${STEER}/product.md`]: 'p', [`${STEER}/tech.md`]: 't', [`${STEER}/structure.md`]: 's',
      [`${S}/request-spec.md`]: 'rs', [`${S}/requirements.md`]: 'req', [`${S}/design.md`]: 'des',
      [`${S}/test-design.md`]: 'td'
    });
    const l = ledgerFor(root);
    for (const d of ['product', 'tech', 'structure']) await approve(l, `${STEER}/${d}.md`, `st-${d}`);
    await approve(l, `${S}/request-spec.md`, 'a1');
    await approve(l, `${S}/requirements.md`, 'a2');
    await approve(l, `${S}/design.md`, 'a3');
    await approve(l, `${S}/test-design.md`, 'a4');
    expect(await l.states('demo', [])).toEqual({
      'request-spec': 'approved', requirements: 'approved', design: 'approved', 'test-design': 'approved'
    });
    // 承認済みの本文は内容ストアに保存される
    expect(existsSync(join(root, '.spec-workflow/approvals/demo/content'))).toBe(true);

    writeFileSync(join(root, `${S}/design.md`), 'des v2');
    await expectCode(l.checkRequest(`${S}/test-design.md`), 'UPSTREAM_MODIFIED:design');
    await approve(l, `${S}/design.md`, 'a5');
    expect((await l.states('demo', []))['test-design']).toBe('stale');
  });

  it('レビュー依頼後に文書が変わると承認できない(CONTENT_CHANGED)', async () => {
    const root = project({
      [`${STEER}/product.md`]: 'p', [`${STEER}/tech.md`]: 't', [`${STEER}/structure.md`]: 's',
      [`${S}/request-spec.md`]: 'rs'
    });
    const l = ledgerFor(root);
    for (const d of ['product', 'tech', 'structure']) await approve(l, `${STEER}/${d}.md`, `st-${d}`);
    const meta = await l.checkRequest(`${S}/request-spec.md`);
    writeFileSync(join(root, `${S}/request-spec.md`), 'rs edited after review request');
    await expectCode(
      l.recordApproval({ id: 'a1', filePath: `${S}/request-spec.md`, metadata: { ledger: meta } }),
      'CONTENT_CHANGED'
    );
  });

  it('取り消し(undo)でひとつ前の承認に戻り、無ければエントリを消す', async () => {
    const root = project({
      [`${STEER}/product.md`]: 'p', [`${STEER}/tech.md`]: 't', [`${STEER}/structure.md`]: 's',
      [`${S}/request-spec.md`]: 'v1'
    });
    const l = ledgerFor(root);
    for (const d of ['product', 'tech', 'structure']) await approve(l, `${STEER}/${d}.md`, `st-${d}`);
    await approve(l, `${S}/request-spec.md`, 'a1');
    writeFileSync(join(root, `${S}/request-spec.md`), 'v2');
    await approve(l, `${S}/request-spec.md`, 'a2');
    await l.revertApproval({ id: 'a2', filePath: `${S}/request-spec.md` });
    expect((await l.read('demo')).entries['request-spec'].approvalId).toBe('a1');
    await l.revertApproval({ id: 'a1', filePath: `${S}/request-spec.md` });
    expect((await l.read('demo')).entries['request-spec']).toBeUndefined();
  });

  it('ApprovalStorage の承認は台帳に記録され、拒否された承認は status を変えない', async () => {
    const root = project({
      [`${STEER}/product.md`]: 'p', [`${STEER}/tech.md`]: 't', [`${STEER}/structure.md`]: 's',
      [`${S}/request-spec.md`]: 'rs'
    });
    const storage = new ApprovalStorage(root);
    for (const d of ['product', 'tech', 'structure']) {
      const fp = `${STEER}/${d}.md`;
      const meta = await storage.ledger.checkRequest(fp);
      const id = await storage.createApproval(d, fp, 'steering', 'steering', 'document', { ledger: meta });
      await storage.updateApproval(id, 'approved', 'ok');
    }
    const fp = `${S}/request-spec.md`;
    const meta = await storage.ledger.checkRequest(fp);
    const id = await storage.createApproval('rs', fp, 'spec', 'demo', 'document', { ledger: meta });
    writeFileSync(join(root, fp), 'edited');
    await expect(storage.updateApproval(id, 'approved', 'ok')).rejects.toThrow('CONTENT_CHANGED');
    expect((await storage.getApproval(id))?.status).toBe('pending');
  });
});

describe('承認台帳: steering の上流(同時に依頼し、変更は stale で伝える)', () => {
  const steeringStates = (root: string) => {
    const r = spawnSync('bash', [STATE_SH, 'steering', root], { encoding: 'utf-8' });
    expect(r.status).toBe(0);
    return parseStates(r.stdout);
  };
  const setup = () =>
    project({ [`${STEER}/product.md`]: 'p', [`${STEER}/tech.md`]: 't', [`${STEER}/structure.md`]: 's', [`${S}/request-spec.md`]: 'rs' });

  it('上流が未承認でも 3 文書を同時に依頼でき、下流から先に承認できる', async () => {
    const root = setup();
    const l = ledgerFor(root);
    const metas = await Promise.all(['product', 'tech', 'structure'].map((d) => l.checkRequest(`${STEER}/${d}.md`)));
    expect(metas[2]?.upstream).toEqual({ product: expect.any(String), tech: expect.any(String) });
    for (const d of ['structure', 'tech', 'product']) await approve(l, `${STEER}/${d}.md`, `st-${d}`);
    const all = { product: 'approved', tech: 'approved', structure: 'approved' };
    expect(await l.states('steering', [])).toEqual(all);
    expect(steeringStates(root)).toEqual(all);
  });

  it('上流を改訂して承認すると下流は stale になり、request-spec を依頼できない', async () => {
    const root = setup();
    const l = ledgerFor(root);
    for (const d of ['product', 'tech', 'structure']) await approve(l, `${STEER}/${d}.md`, `st-${d}`);
    const old = (await l.read('steering')).entries.tech.upstream.product;
    writeFileSync(join(root, `${STEER}/product.md`), 'p v2');
    await approve(l, `${STEER}/product.md`, 'st-product-2');
    const expected = { product: 'approved', tech: 'stale', structure: 'stale' };
    expect(await l.states('steering', [])).toEqual(expected);
    expect(steeringStates(root)).toEqual(expected);
    // 差分を取れるよう、承認時の上流の内容が保存されている
    expect(readFileSync(join(root, `.spec-workflow/approvals/steering/content/${old}.md`), 'utf-8')).toBe('p');
    await expectCode(l.checkRequest(`${S}/request-spec.md`), 'STEERING_STALE:tech');
  });

  it('stale の文書は内容を変えずに再承認すれば approved に戻る', async () => {
    const root = setup();
    const l = ledgerFor(root);
    for (const d of ['product', 'tech', 'structure']) await approve(l, `${STEER}/${d}.md`, `st-${d}`);
    writeFileSync(join(root, `${STEER}/product.md`), 'p v2');
    await approve(l, `${STEER}/product.md`, 'st-product-2');
    await approve(l, `${STEER}/tech.md`, 'st-tech-2');
    await approve(l, `${STEER}/structure.md`, 'st-structure-2');
    const all = { product: 'approved', tech: 'approved', structure: 'approved' };
    expect(await l.states('steering', [])).toEqual(all);
    expect(steeringStates(root)).toEqual(all);
    expect(await l.checkRequest(`${S}/request-spec.md`)).not.toBeNull();
  });
});
