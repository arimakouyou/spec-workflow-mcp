import { describe, it, expect, afterEach } from 'vitest';
import { specStatusHandler } from '../spec-status.js';
import { ToolContext } from '../../types.js';
import { join } from 'path';
import { mkdir, rm, writeFile } from 'fs/promises';

describe('spec-status フェーズ検出の後方互換性', () => {
  const tempRoot = join(process.cwd(), '.tmp-test-spec-status-phases');

  async function createSpecDir(specName: string): Promise<string> {
    const projectPath = join(tempRoot, `project-${Date.now()}-${Math.random().toString(36).slice(2)}`);
    const specDir = join(projectPath, '.spec-workflow', 'specs', specName);
    await mkdir(specDir, { recursive: true });
    return projectPath;
  }

  afterEach(async () => {
    await rm(tempRoot, { recursive: true, force: true });
  });

  it('新規spec（ドキュメントなし）は request-spec-needed を返す', async () => {
    const projectPath = await createSpecDir('new-feature');
    const context: ToolContext = { projectPath };

    const result = await specStatusHandler({ specName: 'new-feature' }, context);

    expect(result.success).toBe(true);
    expect(result.data.currentPhase).toBe('request-spec');
    expect(result.data.overallStatus).toBe('request-spec-needed');
  });

  it('request-spec.mdのみ存在する場合は requirements-needed を返す', async () => {
    const projectPath = await createSpecDir('with-request-spec');
    const specDir = join(projectPath, '.spec-workflow', 'specs', 'with-request-spec');
    await writeFile(join(specDir, 'request-spec.md'), '# 要求仕様\n');
    const context: ToolContext = { projectPath };

    const result = await specStatusHandler({ specName: 'with-request-spec' }, context);

    expect(result.success).toBe(true);
    expect(result.data.currentPhase).toBe('requirements');
    expect(result.data.overallStatus).toBe('requirements-needed');
  });

  it('レガシーspec（requirements.mdあり・request-spec.mdなし）は request-spec-needed にならない', async () => {
    const projectPath = await createSpecDir('legacy-feature');
    const specDir = join(projectPath, '.spec-workflow', 'specs', 'legacy-feature');
    await writeFile(join(specDir, 'requirements.md'), '# 要件定義\n');
    const context: ToolContext = { projectPath };

    const result = await specStatusHandler({ specName: 'legacy-feature' }, context);

    expect(result.success).toBe(true);
    // レガシーspecはrequest-spec-neededをスキップしてdesign-neededに進む
    expect(result.data.currentPhase).toBe('design');
    expect(result.data.overallStatus).toBe('design-needed');
  });

  it('レガシーspec（全ドキュメントあり・request-spec.mdなし）は正しくimplementationフェーズになる', async () => {
    const projectPath = await createSpecDir('legacy-complete');
    const specDir = join(projectPath, '.spec-workflow', 'specs', 'legacy-complete');
    await writeFile(join(specDir, 'requirements.md'), '# 要件定義\n');
    await writeFile(join(specDir, 'design.md'), '# 設計\n');
    await writeFile(join(specDir, 'test-design.md'), '# テスト設計\n');
    await writeFile(join(specDir, 'tasks.md'), '# タスク\n\n- [ ] 1.1 タスク1\n');
    const context: ToolContext = { projectPath };

    const result = await specStatusHandler({ specName: 'legacy-complete' }, context);

    expect(result.success).toBe(true);
    expect(result.data.currentPhase).toBe('implementation');
    expect(result.data.overallStatus).not.toBe('request-spec-needed');
  });
});
