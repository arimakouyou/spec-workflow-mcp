import { describe, it, expect } from 'vitest';
import {
  parseTasksFromMarkdown,
  computeExecutionWaves,
  findNextPendingWave,
  type PhaseInfo,
  type ParsedTask
} from '../task-parser.js';

describe('task-parser', () => {
  describe('_DependsOn: パース', () => {
    it('単一依存を正しくパースする', () => {
      const content = `## Phase 1: Core

- [ ] 1.1 Create model
  - File: src/model.ts
  - _Requirements: REQ-1_

- [ ] 1.2 Create service
  - File: src/service.ts
  - _DependsOn: 1.1_
`;
      const result = parseTasksFromMarkdown(content);
      const task = result.tasks.find(t => t.id === '1.2');
      expect(task?.dependsOn).toEqual(['1.1']);
    });

    it('複数依存をカンマ区切りでパースする', () => {
      const content = `## Phase 1: Core

- [ ] 1.1 Create model
  - File: src/model.ts

- [ ] 1.2 Create repository
  - File: src/repo.ts

- [ ] 1.3 Create service
  - File: src/service.ts
  - _DependsOn: 1.1, 1.2_
`;
      const result = parseTasksFromMarkdown(content);
      const task = result.tasks.find(t => t.id === '1.3');
      expect(task?.dependsOn).toEqual(['1.1', '1.2']);
    });

    it('_DependsOn: がないタスクは dependsOn が undefined', () => {
      const content = `## Phase 1: Core

- [ ] 1.1 Create model
  - File: src/model.ts
  - _Requirements: REQ-1_
`;
      const result = parseTasksFromMarkdown(content);
      const task = result.tasks.find(t => t.id === '1.1');
      expect(task?.dependsOn).toBeUndefined();
    });

    it('_Prompt: 内の DependsOn は無視する', () => {
      const content = `## Phase 1: Core

- [ ] 1.1 Create model
  - File: src/model.ts
  - _Prompt: Role: Dev | Task: Create model _DependsOn: ignore_ | Restrictions: None | Success: Done_
`;
      const result = parseTasksFromMarkdown(content);
      const task = result.tasks.find(t => t.id === '1.1');
      expect(task?.dependsOn).toBeUndefined();
    });
  });

  describe('computeExecutionWaves', () => {
    function makeTasks(defs: Array<{
      id: string;
      status?: 'pending' | 'in-progress' | 'completed';
      dependsOn?: string[];
      isPhaseReview?: boolean;
    }>): { tasks: ParsedTask[]; phase: PhaseInfo } {
      const tasks: ParsedTask[] = defs.map(d => ({
        id: d.id,
        description: `Task ${d.id}`,
        status: d.status || 'pending',
        lineNumber: 0,
        indentLevel: 0,
        isHeader: false,
        completed: d.status === 'completed',
        inProgress: d.status === 'in-progress',
        phase: 'Phase 1: Core',
        ...(d.dependsOn && { dependsOn: d.dependsOn }),
        ...(d.isPhaseReview && { isPhaseReview: true }),
      }));
      const phase: PhaseInfo = {
        name: 'Phase 1: Core',
        taskIds: defs.map(d => d.id),
        reviewTaskId: defs.find(d => d.isPhaseReview)?.id,
      };
      return { tasks, phase };
    }

    it('依存なしのタスクは全て Wave 0 に入る', () => {
      const { tasks, phase } = makeTasks([
        { id: '1.1' },
        { id: '1.2' },
        { id: '1.3' },
      ]);
      const waves = computeExecutionWaves(tasks, phase);
      expect(waves).toHaveLength(1);
      expect(waves[0].waveIndex).toBe(0);
      expect(waves[0].taskIds).toEqual(['1.1', '1.2', '1.3']);
    });

    it('チェーン依存: A → B → C で Wave 0, 1, 2', () => {
      const { tasks, phase } = makeTasks([
        { id: '1.1' },
        { id: '1.2', dependsOn: ['1.1'] },
        { id: '1.3', dependsOn: ['1.2'] },
      ]);
      const waves = computeExecutionWaves(tasks, phase);
      expect(waves).toHaveLength(3);
      expect(waves[0].taskIds).toEqual(['1.1']);
      expect(waves[1].taskIds).toEqual(['1.2']);
      expect(waves[2].taskIds).toEqual(['1.3']);
    });

    it('A,B 独立 + C が両方に依存 → Wave 0:[A,B], Wave 1:[C]', () => {
      const { tasks, phase } = makeTasks([
        { id: '1.1' },
        { id: '1.2' },
        { id: '1.3', dependsOn: ['1.1', '1.2'] },
      ]);
      const waves = computeExecutionWaves(tasks, phase);
      expect(waves).toHaveLength(2);
      expect(waves[0].taskIds).toEqual(['1.1', '1.2']);
      expect(waves[1].taskIds).toEqual(['1.3']);
    });

    it('completed タスクを含む場合はスキップされる', () => {
      const { tasks, phase } = makeTasks([
        { id: '1.1', status: 'completed' },
        { id: '1.2', dependsOn: ['1.1'] },
      ]);
      const waves = computeExecutionWaves(tasks, phase);
      // 1.1 は completed なので Wave に含まれず、1.2 は依存解決済みで Wave 0
      expect(waves).toHaveLength(1);
      expect(waves[0].taskIds).toEqual(['1.2']);
      expect(waves[0].waveIndex).toBe(0);
    });

    it('PhaseReview は常に最終 Wave', () => {
      const { tasks, phase } = makeTasks([
        { id: '1.1' },
        { id: '1.2' },
        { id: '1.3', isPhaseReview: true },
      ]);
      const waves = computeExecutionWaves(tasks, phase);
      expect(waves).toHaveLength(2);
      expect(waves[0].taskIds).toEqual(['1.1', '1.2']);
      expect(waves[1].taskIds).toEqual(['1.3']);
    });

    it('PhaseReview のみの場合', () => {
      const { tasks, phase } = makeTasks([
        { id: '1.1', isPhaseReview: true },
      ]);
      const waves = computeExecutionWaves(tasks, phase);
      expect(waves).toHaveLength(1);
      expect(waves[0].taskIds).toEqual(['1.1']);
    });

    it('循環依存がある場合は進行不可タスクが残る', () => {
      const { tasks, phase } = makeTasks([
        { id: '1.1', dependsOn: ['1.2'] },
        { id: '1.2', dependsOn: ['1.1'] },
      ]);
      const waves = computeExecutionWaves(tasks, phase);
      // 循環依存により両方とも Wave に入れない → 空
      expect(waves).toHaveLength(0);
    });

    it('ダイヤモンド依存: A → B,C → D', () => {
      const { tasks, phase } = makeTasks([
        { id: '1.1' },
        { id: '1.2', dependsOn: ['1.1'] },
        { id: '1.3', dependsOn: ['1.1'] },
        { id: '1.4', dependsOn: ['1.2', '1.3'] },
      ]);
      const waves = computeExecutionWaves(tasks, phase);
      expect(waves).toHaveLength(3);
      expect(waves[0].taskIds).toEqual(['1.1']);
      expect(waves[1].taskIds).toEqual(['1.2', '1.3']);
      expect(waves[2].taskIds).toEqual(['1.4']);
    });
  });

  describe('findNextPendingWave', () => {
    it('最初の Phase の pending Wave を返す', () => {
      const content = `## Phase 1: Core

- [ ] 1.1 Create model
  - File: src/model.ts

- [ ] 1.2 Create service
  - File: src/service.ts
  - _DependsOn: 1.1_

## Phase 2: API

- [ ] 2.1 Create endpoint
  - File: src/api.ts
`;
      const result = parseTasksFromMarkdown(content);
      const next = findNextPendingWave(result.tasks, result.phases);
      expect(next).not.toBeNull();
      expect(next!.phase.name).toMatch(/Phase 1/);
      expect(next!.wave.taskIds).toEqual(['1.1']);
    });

    it('Phase 1 が全て完了なら Phase 2 を返す', () => {
      const content = `## Phase 1: Core

- [x] 1.1 Create model
  - File: src/model.ts

## Phase 2: API

- [ ] 2.1 Create endpoint
  - File: src/api.ts

- [ ] 2.2 Create middleware
  - File: src/middleware.ts
`;
      const result = parseTasksFromMarkdown(content);
      const next = findNextPendingWave(result.tasks, result.phases);
      expect(next).not.toBeNull();
      expect(next!.phase.name).toMatch(/Phase 2/);
      expect(next!.wave.taskIds).toEqual(['2.1', '2.2']);
    });

    it('全タスク完了なら null を返す', () => {
      const content = `## Phase 1: Core

- [x] 1.1 Create model
  - File: src/model.ts
`;
      const result = parseTasksFromMarkdown(content);
      const next = findNextPendingWave(result.tasks, result.phases);
      expect(next).toBeNull();
    });
  });
});
