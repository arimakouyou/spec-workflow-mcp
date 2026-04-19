export type ReviewSource =
  | 'pre-push-review'
  | 'handle-pr-comments'
  | 'codex-review'
  | 'phase-review-team';

export type ReviewAction = 'commit' | 'rework' | 'escalate';

export interface ReviewLogEntry {
  timestamp: string;
  source: ReviewSource;
  attempt: number;
  action: ReviewAction;
  categories: string[];
  summary: string;
  rawLine: string;
  lineNumber: number;
}

export interface ParseReviewLogResult {
  entries: ReviewLogEntry[];
  warnings: { lineNumber: number; reason: string; rawLine: string }[];
}

export interface ReviewProcessAggregate {
  reworkCount: number;
  reviewOutcome: 'approved' | 'rejected' | 'escalated' | 'unknown';
  findings: {
    source: ReviewSource;
    attempt: number;
    action: ReviewAction;
    categories: string[];
    summary: string;
    timestamp: string;
  }[];
}

const VALID_SOURCES: ReadonlySet<ReviewSource> = new Set([
  'pre-push-review',
  'handle-pr-comments',
  'codex-review',
  'phase-review-team',
]);

const VALID_ACTIONS: ReadonlySet<ReviewAction> = new Set([
  'commit',
  'rework',
  'escalate',
]);

const ISO_8601_UTC_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/;

function isValidSource(value: string): value is ReviewSource {
  return VALID_SOURCES.has(value as ReviewSource);
}

function isValidAction(value: string): value is ReviewAction {
  return VALID_ACTIONS.has(value as ReviewAction);
}

export function parseReviewLog(content: string): ParseReviewLogResult {
  const entries: ReviewLogEntry[] = [];
  const warnings: { lineNumber: number; reason: string; rawLine: string }[] = [];

  if (content.length === 0) {
    return { entries, warnings };
  }

  const hasTrailingNewline = content.endsWith('\n');
  const rawLines = content.split('\n');
  if (hasTrailingNewline) rawLines.pop();

  const lastIdx = rawLines.length - 1;

  rawLines.forEach((line, idx) => {
    const lineNumber = idx + 1;
    if (!hasTrailingNewline && idx === lastIdx) {
      if (line.length > 0) {
        warnings.push({
          lineNumber,
          reason: 'trailing line has no newline',
          rawLine: line,
        });
      }
      return;
    }
    if (line === '' || line.startsWith('#')) return;

    const fields = line.split('\t');
    if (fields.length !== 6) {
      warnings.push({
        lineNumber,
        reason: `expected 6 tab-separated fields, got ${fields.length}`,
        rawLine: line,
      });
      return;
    }

    const [timestamp, source, attemptStr, action, categoriesJson, summary] =
      fields as [string, string, string, string, string, string];

    if (!ISO_8601_UTC_PATTERN.test(timestamp)) {
      warnings.push({
        lineNumber,
        reason: 'invalid timestamp',
        rawLine: line,
      });
      return;
    }
    if (!isValidSource(source)) {
      warnings.push({
        lineNumber,
        reason: `unknown review source: ${source}`,
        rawLine: line,
      });
      return;
    }
    const attempt = Number.parseInt(attemptStr, 10);
    if (!Number.isInteger(attempt) || attempt < 1) {
      warnings.push({
        lineNumber,
        reason: `invalid attempt: ${attemptStr}`,
        rawLine: line,
      });
      return;
    }
    if (!isValidAction(action)) {
      warnings.push({
        lineNumber,
        reason: `unknown action: ${action}`,
        rawLine: line,
      });
      return;
    }
    let categories: string[];
    try {
      const parsed = JSON.parse(categoriesJson) as unknown;
      if (
        !Array.isArray(parsed) ||
        parsed.some((x) => typeof x !== 'string')
      ) {
        throw new Error('not a string array');
      }
      categories = parsed as string[];
    } catch {
      warnings.push({
        lineNumber,
        reason: 'categories is not a single-line JSON string array',
        rawLine: line,
      });
      return;
    }

    entries.push({
      timestamp,
      source,
      attempt,
      action,
      categories,
      summary,
      rawLine: line,
      lineNumber,
    });
  });

  return { entries, warnings };
}

export function aggregateReviewProcess(
  content: string,
): ReviewProcessAggregate {
  const { entries } = parseReviewLog(content);

  if (entries.length === 0) {
    return {
      reworkCount: 0,
      reviewOutcome: 'unknown',
      findings: [],
    };
  }

  const reworkCount = entries.filter((e) => e.action === 'rework').length;

  const last = entries[entries.length - 1];
  let reviewOutcome: ReviewProcessAggregate['reviewOutcome'] = 'unknown';
  if (last !== undefined) {
    switch (last.action) {
      case 'commit':
        reviewOutcome = 'approved';
        break;
      case 'rework':
        reviewOutcome = 'rejected';
        break;
      case 'escalate':
        reviewOutcome = 'escalated';
        break;
    }
  }

  return {
    reworkCount,
    reviewOutcome,
    findings: entries.map((e) => ({
      source: e.source,
      attempt: e.attempt,
      action: e.action,
      categories: e.categories,
      summary: e.summary,
      timestamp: e.timestamp,
    })),
  };
}
