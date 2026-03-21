import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { logImplementationHandler } from '../log-implementation.js';
import { ImplementationLogManager } from '../../dashboard/implementation-log-manager.js';
import { ToolContext, ImplementationLogEntry } from '../../types.js';
import { mkdir, rm } from 'fs/promises';
import { join } from 'path';
import { tmpdir } from 'os';

const mockContext: ToolContext = {
  projectPath: '',
  dashboardUrl: 'http://localhost:5000'
};

const baseArgs = {
  specName: 'test-spec',
  taskId: '1.1',
  summary: 'テスト実装',
  filesModified: [],
  filesCreated: [],
  statistics: { linesAdded: 10, linesRemoved: 0 },
  artifacts: {}
};

describe('log-implementation reviewProcess バリデーション', () => {
  describe('reworkCount > 0 で findings なし → エラー', () => {
    it('findings が省略された場合はエラーを返す', async () => {
      const result = await logImplementationHandler(
        {
          ...baseArgs,
          reviewProcess: { reworkCount: 1, reviewOutcome: 'commit' }
        },
        { ...mockContext, projectPath: '/tmp/unused' }
      );
      expect(result.success).toBe(false);
      expect(result.message).toMatch(/findings.*required|required.*findings/i);
    });

    it('findings が空配列の場合はエラーを返す', async () => {
      const result = await logImplementationHandler(
        {
          ...baseArgs,
          reviewProcess: { reworkCount: 2, reviewOutcome: 'commit', findings: [] }
        },
        { ...mockContext, projectPath: '/tmp/unused' }
      );
      expect(result.success).toBe(false);
      expect(result.message).toMatch(/findings.*required|required.*findings/i);
    });
  });

  describe('reworkCount === 0 で findings あり → エラー', () => {
    it('findings に要素がある場合はエラーを返す', async () => {
      const result = await logImplementationHandler(
        {
          ...baseArgs,
          reviewProcess: {
            reworkCount: 0,
            reviewOutcome: 'commit',
            findings: [{ attempt: 1, categories: [], summary: '全パス', action: 'commit' }]
          }
        },
        { ...mockContext, projectPath: '/tmp/unused' }
      );
      expect(result.success).toBe(false);
      expect(result.message).toMatch(/findings.*empty|reworkCount.*0/i);
    });
  });

  describe('findings.length !== reworkCount + 1 → エラー', () => {
    it('findings が少ない場合はエラーを返す', async () => {
      const result = await logImplementationHandler(
        {
          ...baseArgs,
          reviewProcess: {
            reworkCount: 2,
            reviewOutcome: 'commit',
            findings: [
              { attempt: 1, categories: ['B:設計'], summary: '指摘あり', action: 'rework' }
              // reworkCount=2 なので 3 件必要だが 1 件しかない
            ]
          }
        },
        { ...mockContext, projectPath: '/tmp/unused' }
      );
      expect(result.success).toBe(false);
      expect(result.message).toMatch(/findings.*件数|件数.*findings/);
    });

    it('findings が多い場合はエラーを返す', async () => {
      const result = await logImplementationHandler(
        {
          ...baseArgs,
          reviewProcess: {
            reworkCount: 1,
            reviewOutcome: 'commit',
            findings: [
              { attempt: 1, categories: ['B:設計'], summary: '指摘あり', action: 'rework' },
              { attempt: 2, categories: [], summary: '全パス', action: 'commit' },
              { attempt: 3, categories: [], summary: '余分なエントリ', action: 'commit' }
              // reworkCount=1 なので 2 件必要だが 3 件ある
            ]
          }
        },
        { ...mockContext, projectPath: '/tmp/unused' }
      );
      expect(result.success).toBe(false);
      expect(result.message).toMatch(/findings.*件数|件数.*findings/);
    });
  });

  describe('attempt 番号が連番でない → エラー', () => {
    it('attempt が 1 始まりでない場合はエラーを返す', async () => {
      const result = await logImplementationHandler(
        {
          ...baseArgs,
          reviewProcess: {
            reworkCount: 1,
            reviewOutcome: 'commit',
            findings: [
              { attempt: 2, categories: ['B:設計'], summary: '指摘あり', action: 'rework' },
              { attempt: 3, categories: [], summary: '全パス', action: 'commit' }
            ]
          }
        },
        { ...mockContext, projectPath: '/tmp/unused' }
      );
      expect(result.success).toBe(false);
      expect(result.message).toMatch(/attempt.*連番|連番.*attempt/);
    });

    it('attempt に重複がある場合はエラーを返す', async () => {
      const result = await logImplementationHandler(
        {
          ...baseArgs,
          reviewProcess: {
            reworkCount: 1,
            reviewOutcome: 'commit',
            findings: [
              { attempt: 1, categories: ['B:設計'], summary: '指摘あり', action: 'rework' },
              { attempt: 1, categories: [], summary: '全パス', action: 'commit' }
            ]
          }
        },
        { ...mockContext, projectPath: '/tmp/unused' }
      );
      expect(result.success).toBe(false);
      expect(result.message).toMatch(/attempt.*連番|連番.*attempt/);
    });
  });
});

describe('reviewProcess のマークダウン永続化（ImplementationLogManager）', () => {
  let tempDir: string;
  let specPath: string;

  beforeEach(async () => {
    tempDir = join(tmpdir(), `spec-wf-test-${Date.now()}`);
    specPath = join(tempDir, '.spec-workflow', 'specs', 'test-spec');
    await mkdir(join(specPath, 'Implementation Logs'), { recursive: true });
    // tasks.md が必要なため作成
    await mkdir(specPath, { recursive: true });
    const { writeFile } = await import('fs/promises');
    await writeFile(
      join(specPath, 'tasks.md'),
      '## Phase 1\n- [x] 1.1 テストタスク\n  - _Prompt: テスト_\n',
      'utf-8'
    );
  });

  afterEach(async () => {
    await rm(tempDir, { recursive: true, force: true });
  });

  it('reviewProcess が書き込まれ再読み込みでも保持される', async () => {
    const manager = new ImplementationLogManager(specPath);

    const reviewProcess = {
      reworkCount: 1,
      reviewOutcome: 'commit' as const,
      findings: [
        { attempt: 1, categories: ['B:設計'], summary: 'リポジトリの戻り値型が不一致', action: 'rework' as const },
        { attempt: 2, categories: [], summary: '全観点パス', action: 'commit' as const }
      ]
    };

    const entry = await manager.addLogEntry({
      taskId: '1.1',
      timestamp: new Date().toISOString(),
      summary: 'テスト実装',
      filesModified: [],
      filesCreated: [],
      statistics: { linesAdded: 10, linesRemoved: 0, filesChanged: 1 },
      artifacts: {},
      reviewProcess
    });

    // 再読み込み
    const logs = await manager.loadLog();
    const loaded = logs.entries.find((e: ImplementationLogEntry) => e.id === entry.id);

    expect(loaded).toBeDefined();
    expect(loaded!.reviewProcess).toBeDefined();
    expect(loaded!.reviewProcess!.reworkCount).toBe(1);
    expect(loaded!.reviewProcess!.reviewOutcome).toBe('commit');
    expect(loaded!.reviewProcess!.findings).toHaveLength(2);
    expect(loaded!.reviewProcess!.findings![0].attempt).toBe(1);
    expect(loaded!.reviewProcess!.findings![1].attempt).toBe(2);
  });

  it('artifacts が空でも reviewProcess が保持される', async () => {
    const manager = new ImplementationLogManager(specPath);

    const reviewProcess = {
      reworkCount: 0,
      reviewOutcome: 'commit' as const
    };

    const entry = await manager.addLogEntry({
      taskId: '1.1',
      timestamp: new Date().toISOString(),
      summary: 'artifacts なしの実装',
      filesModified: [],
      filesCreated: [],
      statistics: { linesAdded: 5, linesRemoved: 0, filesChanged: 0 },
      artifacts: {},
      reviewProcess
    });

    const logs = await manager.loadLog();
    const loaded = logs.entries.find((e: ImplementationLogEntry) => e.id === entry.id);

    expect(loaded).toBeDefined();
    expect(loaded!.reviewProcess).toBeDefined();
    expect(loaded!.reviewProcess!.reworkCount).toBe(0);
    expect(loaded!.reviewProcess!.reviewOutcome).toBe('commit');
  });
});
