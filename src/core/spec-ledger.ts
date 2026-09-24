import { createHash } from 'crypto';
import { promises as fs } from 'fs';
import { join } from 'path';

// 承認台帳(.claude-plugin/contract/approval-ledger-v1.md の TS 実装)。
// 承認した文書の sha256 と、承認時点の上流文書の sha256 を記録し、上流が変われば下流を stale と判定する。

export type LedgerDoc = 'request-spec' | 'requirements' | 'design' | 'test-design' | 'product' | 'tech' | 'structure';
export type DocState = 'pending' | 'unapproved' | 'modified' | 'stale' | 'approved';

export interface LedgerTarget {
  key: string;
  doc: LedgerDoc;
}

export interface LedgerMeta extends LedgerTarget {
  contentSha256: string;
  upstream: Record<string, string>;
}

export interface LedgerEntry {
  sha256: string;
  approvalId: string;
  approvedAt: string;
  upstream: Record<string, string>;
}

export type LedgerEvent =
  | { event: 'approved'; doc: string; sha256: string; approvalId: string; at: string; upstream: Record<string, string> }
  | { event: 'reverted'; doc: string; approvalId: string; at: string };

export interface Ledger {
  version: 1;
  entries: Record<string, LedgerEntry>;
  history: LedgerEvent[];
}

export const SPEC_DOCS: LedgerDoc[] = ['request-spec', 'requirements', 'design', 'test-design'];
export const STEERING_DOCS: LedgerDoc[] = ['product', 'tech', 'structure'];
export const STEERING_KEY = 'steering';

export const UPSTREAM: Record<LedgerDoc, LedgerDoc[]> = {
  'request-spec': [],
  requirements: ['request-spec'],
  design: ['requirements'],
  'test-design': ['requirements', 'design'],
  product: [],
  tech: [],
  structure: []
};

export class LedgerError extends Error {
  constructor(public readonly code: string, message: string) {
    super(`${code}: ${message}`);
    this.name = 'LedgerError';
  }
}

/** approval の filePath から台帳の対象を決める。tasks.md は 'tasks'、対象外は null */
export function identifyDocument(filePath: string): LedgerTarget | 'tasks' | null {
  const p = filePath.replace(/\\/g, '/').replace(/^\.\//, '');
  const spec = p.match(/^\.spec-workflow\/specs\/([^/]+)\/([^/]+)\.md$/);
  if (spec) {
    if (spec[2] === 'tasks') return 'tasks';
    if ((SPEC_DOCS as string[]).includes(spec[2])) return { key: spec[1], doc: spec[2] as LedgerDoc };
    return null;
  }
  const steering = p.match(/^\.spec-workflow\/steering\/([^/]+)\.md$/);
  if (steering && (STEERING_DOCS as string[]).includes(steering[1])) {
    return { key: STEERING_KEY, doc: steering[1] as LedgerDoc };
  }
  return null;
}

/** 台帳の対象文書の、プロジェクトルートからの相対パス */
export function documentPath(target: LedgerTarget): string {
  return target.key === STEERING_KEY
    ? `.spec-workflow/steering/${target.doc}.md`
    : `.spec-workflow/specs/${target.key}/${target.doc}.md`;
}

export function sha256(content: Buffer | string): string {
  return createHash('sha256').update(content).digest('hex');
}

export class SpecLedger {
  constructor(
    private readonly approvalsDir: string,
    /** 相対パスから実在するファイルの絶対パスを返す(見つからなければ null) */
    private readonly resolveFile: (relativePath: string) => Promise<string | null>
  ) {}

  private ledgerPath(key: string): string {
    return join(this.approvalsDir, key, 'ledger.json');
  }

  async read(key: string): Promise<Ledger> {
    try {
      const raw = await fs.readFile(this.ledgerPath(key), 'utf-8');
      const parsed = JSON.parse(raw) as Ledger;
      return { version: 1, entries: parsed.entries ?? {}, history: parsed.history ?? [] };
    } catch (error: any) {
      if (error?.code === 'ENOENT') return { version: 1, entries: {}, history: [] };
      throw error;
    }
  }

  private async write(key: string, ledger: Ledger): Promise<void> {
    const path = this.ledgerPath(key);
    await fs.mkdir(join(this.approvalsDir, key), { recursive: true });
    const tmp = `${path}.${process.pid}.${Date.now()}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(ledger, null, 2) + '\n', 'utf-8');
    await fs.rename(tmp, path);
  }

  /** 対象文書の現在の sha256(ファイルが無ければ null) */
  async currentSha(target: LedgerTarget): Promise<string | null> {
    const abs = await this.resolveFile(documentPath(target));
    if (!abs) return null;
    return sha256(await fs.readFile(abs));
  }

  /** 上流(と request-spec の場合は steering)が承認済みかつ未変更であることを確かめ、上流の sha を返す */
  async checkUpstream(target: LedgerTarget): Promise<Record<string, string>> {
    const ledger = await this.read(target.key);
    const upstream: Record<string, string> = {};
    for (const u of UPSTREAM[target.doc]) {
      const entry = ledger.entries[u];
      if (!entry) throw new LedgerError(`UPSTREAM_NOT_APPROVED:${u}`, `${u} が承認されていない`);
      const current = await this.currentSha({ key: target.key, doc: u });
      if (current !== entry.sha256) throw new LedgerError(`UPSTREAM_MODIFIED:${u}`, `${u} は承認後に変更されている`);
      upstream[u] = entry.sha256;
    }
    if (target.doc === 'request-spec') {
      const steering = await this.read(STEERING_KEY);
      for (const s of STEERING_DOCS) {
        const entry = steering.entries[s];
        if (!entry) throw new LedgerError(`STEERING_NOT_APPROVED:${s}`, `steering/${s}.md が承認されていない`);
        const current = await this.currentSha({ key: STEERING_KEY, doc: s });
        if (current !== entry.sha256) throw new LedgerError(`STEERING_MODIFIED:${s}`, `steering/${s}.md は承認後に変更されている`);
      }
    }
    return upstream;
  }

  /** request 時の検査。対象外の文書なら null、tasks.md なら TASKS_GENERATED */
  async checkRequest(filePath: string): Promise<LedgerMeta | null> {
    const target = identifyDocument(filePath);
    if (target === 'tasks') {
      throw new LedgerError('TASKS_GENERATED', 'tasks.md は spec-plan.sh の生成物で、承認の対象ではない');
    }
    if (!target) return null;
    const upstream = await this.checkUpstream(target);
    const contentSha256 = await this.currentSha(target);
    if (!contentSha256) throw new LedgerError('DOCUMENT_MISSING', `${documentPath(target)} が無い`);
    return { ...target, contentSha256, upstream };
  }

  /** 承認を台帳に記録する。request 時の sha と現在の sha が違えば CONTENT_CHANGED */
  async recordApproval(approval: { id: string; filePath: string; metadata?: Record<string, any> }): Promise<void> {
    const target = identifyDocument(approval.filePath);
    if (target === 'tasks') throw new LedgerError('TASKS_GENERATED', 'tasks.md は承認の対象ではない');
    if (!target) return;
    const abs = await this.resolveFile(documentPath(target));
    if (!abs) throw new LedgerError('DOCUMENT_MISSING', `${documentPath(target)} が無い`);
    const content = await fs.readFile(abs);
    const current = sha256(content);
    const requested: string | undefined = approval.metadata?.ledger?.contentSha256;
    if (requested && requested !== current) {
      throw new LedgerError('CONTENT_CHANGED', 'レビュー依頼の後に文書が変更されている。再度レビューを依頼する');
    }
    const upstream = await this.checkUpstream(target);

    const contentDir = join(this.approvalsDir, target.key, 'content');
    await fs.mkdir(contentDir, { recursive: true });
    await fs.writeFile(join(contentDir, `${current}.md`), content);

    const ledger = await this.read(target.key);
    const at = new Date().toISOString();
    ledger.entries[target.doc] = { sha256: current, approvalId: approval.id, approvedAt: at, upstream };
    ledger.history.push({ event: 'approved', doc: target.doc, sha256: current, approvalId: approval.id, at, upstream });
    await this.write(target.key, ledger);
  }

  /** 承認の取り消し(undo)。現行の承認がこの approval なら、それ以前の承認に戻す */
  async revertApproval(approval: { id: string; filePath: string }): Promise<void> {
    const target = identifyDocument(approval.filePath);
    if (!target || target === 'tasks') return;
    const ledger = await this.read(target.key);
    const entry = ledger.entries[target.doc];
    const at = new Date().toISOString();
    ledger.history.push({ event: 'reverted', doc: target.doc, approvalId: approval.id, at });
    if (entry && entry.approvalId === approval.id) {
      const reverted = new Set(
        ledger.history.filter((e) => e.event === 'reverted' && e.doc === target.doc).map((e) => e.approvalId)
      );
      const previous = [...ledger.history]
        .reverse()
        .find((e): e is Extract<LedgerEvent, { event: 'approved' }> => e.event === 'approved' && e.doc === target.doc && !reverted.has(e.approvalId));
      if (previous) {
        ledger.entries[target.doc] = { sha256: previous.sha256, approvalId: previous.approvalId, approvedAt: previous.at, upstream: previous.upstream };
      } else {
        delete ledger.entries[target.doc];
      }
    }
    await this.write(target.key, ledger);
  }

  /** spec の各文書の状態(契約 §5)。pendingPaths は status が pending の承認リクエストの filePath */
  async states(key: string, pendingPaths: string[]): Promise<Record<string, DocState>> {
    const docs = key === STEERING_KEY ? STEERING_DOCS : SPEC_DOCS;
    const ledger = await this.read(key);
    const pending = new Set(pendingPaths.map((p) => p.replace(/\\/g, '/').replace(/^\.\//, '')));
    const result: Record<string, DocState> = {};
    for (const doc of docs) {
      const target = { key, doc };
      if (pending.has(documentPath(target))) { result[doc] = 'pending'; continue; }
      const entry = ledger.entries[doc];
      if (!entry) { result[doc] = 'unapproved'; continue; }
      if ((await this.currentSha(target)) !== entry.sha256) { result[doc] = 'modified'; continue; }
      const stale = UPSTREAM[doc].some(
        (u) => result[u] !== 'approved' || entry.upstream[u] !== ledger.entries[u]?.sha256
      );
      result[doc] = stale ? 'stale' : 'approved';
    }
    return result;
  }
}
