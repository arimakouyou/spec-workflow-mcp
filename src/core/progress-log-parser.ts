export type ProgressEventKind = 'BEGIN' | 'END' | 'VERIFIED' | 'FAILED' | 'COMPLETE';

export interface ProgressEvent {
  timestamp: string;
  event: ProgressEventKind;
  stepId: string;
  meta: Record<string, unknown>;
  rawLine: string;
  lineNumber: number;
}

export interface ParseWarning {
  lineNumber: number;
  reason: string;
  rawLine: string;
}

export interface ParseProgressLogResult {
  events: ProgressEvent[];
  warnings: ParseWarning[];
}

export type ResumeAction =
  | { kind: 'start-fresh'; step: string; attempt: 1 }
  | { kind: 'resume-next'; step: string; attempt: 1 }
  | { kind: 'redo-step'; step: string; attempt: number; reason: string }
  | { kind: 'reset-to-task-start'; reason: string }
  | { kind: 'escalate'; step: string; reason: string }
  | { kind: 'needs-complete'; step: string }
  | { kind: 'already-done' };

export interface DecideResumeActionOptions {
  maxAttemptsPerStep?: number;
  stepOrder?: readonly string[];
}

export const DEFAULT_STEP_ORDER: readonly string[] = Object.freeze([
  'discover',
  'red-write',
  'red-verify',
  'green-code',
  'green-verify',
  'refactor',
  'refactor-verify',
  'ut-quality',
  'simplify',
  'review-commit',
  'log',
  'phase-integration',
  'phase-cve',
  'phase-experts',
  'phase-commit',
]);

export const DEFAULT_MAX_ATTEMPTS_PER_STEP = 3;

const VALID_EVENT_KINDS: ReadonlySet<ProgressEventKind> = new Set([
  'BEGIN',
  'END',
  'VERIFIED',
  'FAILED',
  'COMPLETE',
]);

const STEP_ID_PATTERN = /^[a-z0-9-]+$/;

const ISO_8601_UTC_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/;

function isValidIsoTimestamp(value: string): boolean {
  if (!ISO_8601_UTC_PATTERN.test(value)) {
    return false;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed);
}

function isValidEventKind(value: string): value is ProgressEventKind {
  return VALID_EVENT_KINDS.has(value as ProgressEventKind);
}

function parseMetaJson(raw: string): Record<string, unknown> | null {
  const trimmed = raw.trim();
  if (trimmed === '') {
    return {};
  }
  try {
    const parsed = JSON.parse(trimmed) as unknown;
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return null;
    }
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

export function parseProgressLog(content: string): ParseProgressLogResult {
  const events: ProgressEvent[] = [];
  const warnings: ParseWarning[] = [];

  if (content.length === 0) {
    return { events, warnings };
  }

  const hasTrailingNewline = content.endsWith('\n');
  const rawLines = content.split('\n');
  if (hasTrailingNewline) {
    rawLines.pop();
  }

  const lastIndex = rawLines.length - 1;

  rawLines.forEach((line, idx) => {
    const lineNumber = idx + 1;

    if (!hasTrailingNewline && idx === lastIndex) {
      if (line.length > 0) {
        warnings.push({
          lineNumber,
          reason: 'trailing line has no newline, treated as incomplete',
          rawLine: line,
        });
      }
      return;
    }

    if (line === '') {
      return;
    }

    if (line.startsWith('#')) {
      return;
    }

    const fields = line.split('\t');
    if (fields.length !== 4) {
      warnings.push({
        lineNumber,
        reason: `expected 4 tab-separated fields, got ${fields.length}`,
        rawLine: line,
      });
      return;
    }

    const [timestamp, event, stepId, metaRaw] = fields as [
      string,
      string,
      string,
      string,
    ];

    if (!isValidIsoTimestamp(timestamp)) {
      warnings.push({
        lineNumber,
        reason: `invalid ISO 8601 UTC timestamp: ${timestamp}`,
        rawLine: line,
      });
      return;
    }

    if (!isValidEventKind(event)) {
      warnings.push({
        lineNumber,
        reason: `unknown event kind: ${event}`,
        rawLine: line,
      });
      return;
    }

    if (!STEP_ID_PATTERN.test(stepId)) {
      warnings.push({
        lineNumber,
        reason: `invalid step id: ${stepId}`,
        rawLine: line,
      });
      return;
    }

    const meta = parseMetaJson(metaRaw);
    if (meta === null) {
      warnings.push({
        lineNumber,
        reason: 'meta is not a valid single-line JSON object',
        rawLine: line,
      });
      return;
    }

    events.push({
      timestamp,
      event,
      stepId,
      meta,
      rawLine: line,
      lineNumber,
    });
  });

  return { events, warnings };
}

function countBeginEventsForStep(events: ProgressEvent[], stepId: string): number {
  let count = 0;
  for (const ev of events) {
    if (ev.event === 'BEGIN' && ev.stepId === stepId) {
      count += 1;
    }
  }
  return count;
}

function findSuccessorStep(
  current: string,
  stepOrder: readonly string[],
): string | null {
  const idx = stepOrder.indexOf(current);
  if (idx === -1) {
    return null;
  }
  if (idx === stepOrder.length - 1) {
    return null;
  }
  return stepOrder[idx + 1] ?? null;
}

export function decideResumeActionFromEvents(
  events: ProgressEvent[],
  options: DecideResumeActionOptions = {},
): ResumeAction {
  const maxAttempts = options.maxAttemptsPerStep ?? DEFAULT_MAX_ATTEMPTS_PER_STEP;
  const stepOrder = options.stepOrder ?? DEFAULT_STEP_ORDER;
  const firstStep = stepOrder[0] ?? 'discover';

  if (events.length === 0) {
    return { kind: 'start-fresh', step: firstStep, attempt: 1 };
  }

  const last = events[events.length - 1];
  if (last === undefined) {
    return { kind: 'start-fresh', step: firstStep, attempt: 1 };
  }

  switch (last.event) {
    case 'COMPLETE':
      return { kind: 'already-done' };

    case 'VERIFIED': {
      const next = findSuccessorStep(last.stepId, stepOrder);
      if (next === null) {
        return { kind: 'needs-complete', step: last.stepId };
      }
      return { kind: 'resume-next', step: next, attempt: 1 };
    }

    case 'FAILED': {
      const reasonRaw = last.meta['reason'];
      const reason = typeof reasonRaw === 'string' ? reasonRaw : 'step failed';
      return { kind: 'escalate', step: last.stepId, reason };
    }

    case 'END':
    case 'BEGIN': {
      const attempts = countBeginEventsForStep(events, last.stepId);
      if (attempts >= maxAttempts) {
        return {
          kind: 'reset-to-task-start',
          reason: `step ${last.stepId} exceeded max attempts (${attempts} >= ${maxAttempts})`,
        };
      }
      const redoReason =
        last.event === 'END'
          ? 'delegation returned but verification was not recorded'
          : 'delegation did not finish (subagent interruption)';
      return {
        kind: 'redo-step',
        step: last.stepId,
        attempt: attempts + 1,
        reason: redoReason,
      };
    }
  }
}

export function decideResumeAction(
  content: string | null | undefined,
  options: DecideResumeActionOptions = {},
): ResumeAction {
  const stepOrder = options.stepOrder ?? DEFAULT_STEP_ORDER;
  const firstStep = stepOrder[0] ?? 'discover';

  if (content === null || content === undefined) {
    return { kind: 'start-fresh', step: firstStep, attempt: 1 };
  }

  const { events } = parseProgressLog(content);
  return decideResumeActionFromEvents(events, options);
}
