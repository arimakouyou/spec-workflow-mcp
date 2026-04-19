import {
  parseProgressLog,
  type ProgressEvent,
} from './progress-log-parser.js';
import {
  parseTasksFromMarkdown,
  updateTaskStatus,
} from './task-parser.js';

export type TaskState = 'pending' | 'in-progress' | 'completed';

export interface TaskStateUpdate {
  taskId: string;
  before: TaskState;
  after: TaskState;
}

export interface SyncTasksMarkdownResult {
  updatedMarkdown: string;
  updates: TaskStateUpdate[];
  missingTaskIds: string[];
}

export function computeTaskState(
  progressLogContent: string | null | undefined,
): TaskState {
  if (progressLogContent === null || progressLogContent === undefined) {
    return 'pending';
  }

  const { events } = parseProgressLog(progressLogContent);
  if (events.length === 0) {
    return 'pending';
  }

  const lastEvent = lastNonFailedEventOrLast(events);
  if (lastEvent === null) {
    return 'pending';
  }

  if (lastEvent.event === 'COMPLETE') {
    return 'completed';
  }

  return 'in-progress';
}

function lastNonFailedEventOrLast(
  events: readonly ProgressEvent[],
): ProgressEvent | null {
  if (events.length === 0) {
    return null;
  }
  return events[events.length - 1] ?? null;
}

export function syncTasksMarkdown(
  tasksMarkdown: string,
  taskStateMap: ReadonlyMap<string, TaskState>,
): SyncTasksMarkdownResult {
  const parsed = parseTasksFromMarkdown(tasksMarkdown);
  const existingIds = new Set<string>(parsed.tasks.map((t) => t.id));

  const updates: TaskStateUpdate[] = [];
  const missingTaskIds: string[] = [];

  let current = tasksMarkdown;

  for (const [taskId, desired] of taskStateMap.entries()) {
    if (!existingIds.has(taskId)) {
      missingTaskIds.push(taskId);
      continue;
    }

    const existing = parsed.tasks.find((t) => t.id === taskId);
    if (existing === undefined) {
      missingTaskIds.push(taskId);
      continue;
    }

    const before = existing.status;
    if (before === desired) {
      continue;
    }

    current = updateTaskStatus(current, taskId, desired);
    updates.push({ taskId, before, after: desired });
  }

  return {
    updatedMarkdown: current,
    updates,
    missingTaskIds,
  };
}
