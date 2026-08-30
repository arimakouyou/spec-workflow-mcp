---
always_apply: true
---

# Task Log Format

Single, append-only Markdown file capturing all per-task durable state for the spec-implement workflow (and per-job state for integration-test). Consolidates the prior `state.md`, `diagnosis.md`, and `Implementation Logs/task-*.md` into one source of truth.

This rule is the **authoritative format spec**. Agents (`parallel-worker`, `review-worker`), skills (`spec-implement`, `integration-test`, `integration-test-dotnet`, `log-implementation`), and the dashboard parser (`src/dashboard/implementation-log-manager.ts`) all reference this file.

> **Reference form**: cite locations in log entries by stable anchor (`IT-41 VP2`, `DES-2 AppBootstrap::run`, a heading or table-row key, a grep-able verbatim phrase), never by `file:line` — see `doc-crossref.md` "Reference Form". Logs are read after the cited file has been revised.


## TL1: Why a Task Log

- **Compaction / yield / crash resilience**: durable on disk, agents can resume from it
- **Single-file inspection**: one file to open for full task history
- **Append-only**: no Edit operations during the task → avoids mid-task file orchestration patterns that trigger sub-agent yields
- **Audit trail**: full attempt history, review cycles, commit hashes — usable by `feedback-loop`, post-mortems, and dashboard
- **Survives worktree deletion**: lives under `.spec-workflow/` (project data), not in the worktree

## TL2: File Path

### Spec-implement (per-task)

```
.spec-workflow/specs/{spec-name}/task-logs/{taskId}.log.md
```

- One file per task within a spec
- `{taskId}` is the task ID from `tasks.md` (e.g., `2.4`, `3.1.4`) — used verbatim, no sanitization
- Survives worktree deletion (lives in the main repo's `.spec-workflow/` directory, not the worktree)
- Replaces the legacy `Implementation Logs/task-{sanitizedTaskId}_{timestamp}_{idPrefix}.md` naming

### Integration-test (per-job)

When invoked with a spec context (via `--spec <name>` or detected from cwd):
```
.spec-workflow/specs/{spec-name}/integ-test-runs/{timestamp}.log.md
```

When invoked without a spec context:
```
.spec-workflow/integ-test-runs/{timestamp}.log.md
```

- `{timestamp}` is ISO 8601 UTC with separators stripped (e.g., `20260520T143200`)
- One file per `/integration-test` invocation

### Legacy locations (read-compatible, not written to)

The dashboard parser continues to read these for spec-implement tasks created before this rule:
```
.spec-workflow/specs/{spec-name}/Implementation Logs/task-{sanitizedTaskId}_{timestamp}_{idPrefix}.md
```

New tasks always write to the new path. No migration is performed.

## TL3: File Structure

```markdown
# Task Log: {taskId}

## Metadata
- spec: {spec-name}
- task-id: {taskId}
- created: {ISO 8601 UTC timestamp}
- log-id: {uuid}

## Events
(append-only event entries — see TL4)

## Summary
(written by log-implementation at task completion — see TL5)

## Statistics
(written by log-implementation at task completion — see TL5)

## Files Modified
(written by log-implementation at task completion — see TL5)

## Files Created
(written by log-implementation at task completion — see TL5)

## Artifacts
(written by log-implementation at task completion — see TL5)

## Review Process
(written by log-implementation at task completion — see TL5)
```

## TL4: Events Section (append-only)

### Event Line Format

Each event is one Markdown list item with the structure:

```
- `{timestamp}` {agent} {event-type} {key=value}...
  - {detail-key}: {detail-value}
  - {detail-key}: {detail-value}
```

- `{timestamp}`: ISO 8601 UTC, e.g., `2026-05-20T12:00:01Z`
- `{agent}`: emitting agent name (`parallel-worker`, `review-worker`, `integ-test-command`, `integ-test-worker`, `integ-test-auditor`)
- `{event-type}`: kebab-case event identifier (see TL4.1)
- `{key=value}`: zero or more inline key-value pairs for the primary attributes of the event. Values that contain spaces or commas must be double-quoted (e.g., `summary="assert!() failed at L42"`)
- Indented sub-lines: optional, for richer structured fields (one key per line; `key: value` format with two-space indent)

### TL4.1: Event Type Taxonomy

#### parallel-worker events

| Event type | Inline keys | Detail keys |
|---|---|---|
| `phase-start` | `phase` (RED / GREEN / REFACTOR) | — |
| `phase-complete` | `phase`, `files` (comma-separated list, no spaces) | `key_decisions` (one line, comma-separated) |
| `attempt-start` | `phase`, `n` (attempt number) | `approach`, `root_cause`, `responsible`, `expected_behavior` |
| `attempt-result` | `phase`, `n`, `result` (PASS / FAIL), `category` (FC1 main / sub or empty) | `summary` |
| `divergent-analysis` | `phase`, `before_attempt` | `common_implicit_assumption`, `why_prior_failed`, `challenge` |
| `handoff` | — | `summary`, `known_concerns` |
| `rework-start` | `cycle` | — |
| `rework-complete` | `cycle`, `changed_files` | — |

#### review-worker events

| Event type | Inline keys | Detail keys |
|---|---|---|
| `cycle-start` | `n` | — |
| `cycle-end` | `n`, `verdict` (commit / rework / escalate), `findings_count` | `severities` |
| `commit` | `hash` | — |

#### Integration-test events (Command-emitted)

For the integration-test SKILLs, the Command (orchestrator) is the only event emitter. Workers and Pentagon do not write to the log; Command extracts info from their final responses and appends events.

| Event type | Inline keys | Detail keys |
|---|---|---|
| `job-start` | `targets` (comma-separated domain list) | `goal`, `key_questions` |
| `domain-analysis` | `domain` | `endpoints`, `external_deps` |
| `worker-launch` | `domain`, `cycle` | — |
| `worker-return` | `domain`, `cycle`, `result` (PASS / FAIL based on self-checks) | `test_counts`, `findings_excerpt` |
| `pentagon-launch` | `domain`, `cycle` | — |
| `pentagon-return` | `domain`, `cycle`, `verdict` (PASS / FAIL) | `issues_excerpt` |
| `domain-done` | `domain`, `status` (PASS / done-with-issues), `cycles` | — |
| `job-end` | `targets`, `status` (success / partial) | — |

### TL4.2: Example Events Section

```markdown
## Events

- `2026-05-20T12:00:01Z` parallel-worker phase-start phase=RED
- `2026-05-20T12:00:30Z` parallel-worker phase-complete phase=RED files=tests/foo.rs
- `2026-05-20T12:01:00Z` parallel-worker attempt-start phase=GREEN n=1
  - approach: Obvious Implementation
- `2026-05-20T12:01:45Z` parallel-worker attempt-result phase=GREEN n=1 result=FAIL category=test_failure/assertion_failure
  - root_cause: predicate at L42 is too loose
  - responsible: src/foo.rs:42
  - expected_behavior: tight predicate check
  - summary: "assert!() failed at L42"
- `2026-05-20T12:02:00Z` parallel-worker attempt-start phase=GREEN n=2
  - approach: Fake It
  - root_cause: predicate at L42 is too loose
- `2026-05-20T12:02:30Z` parallel-worker attempt-result phase=GREEN n=2 result=PASS
- `2026-05-20T12:03:00Z` parallel-worker phase-complete phase=REFACTOR files=src/foo.rs
  - key_decisions: extracted helper fn parse_xyz
- `2026-05-20T12:03:30Z` parallel-worker handoff
  - summary: GREEN/REFACTOR complete, helper extracted
  - known_concerns: edge case at empty input deferred
- `2026-05-20T12:04:00Z` review-worker cycle-start n=1
- `2026-05-20T12:04:30Z` review-worker cycle-end n=1 verdict=rework findings_count=3
  - severities: "Moderate x2, Minor x1"
- `2026-05-20T12:05:00Z` parallel-worker rework-start cycle=1
- `2026-05-20T12:05:30Z` parallel-worker rework-complete cycle=1 changed_files=src/foo.rs
- `2026-05-20T12:06:00Z` review-worker cycle-start n=2
- `2026-05-20T12:06:20Z` review-worker cycle-end n=2 verdict=commit findings_count=0
- `2026-05-20T12:06:25Z` review-worker commit hash=abc1234
```

## TL5: Completion Sections (written by log-implementation)

These sections preserve the structure of the legacy Implementation Log so that downstream consumers (dashboard parser, feedback-loop) have a stable schema. They are written **once** at task completion by the `log-implementation` skill.

```markdown
## Summary

{one-line summary of implementation}

## Statistics

- Lines Added: +{linesAdded}
- Lines Removed: -{linesRemoved}
- Files Changed: {filesModified.length + filesCreated.length}
- Net Change: {linesAdded - linesRemoved}

## Files Modified
- {path}
- ...
(or `_No files modified_` if empty)

## Files Created
- {path}
- ...
(or `_No files created_` if empty)

## Artifacts

(For each artifact category that has entries — empty categories are omitted)

### API Endpoints
#### {method} {path}
- **Purpose:** {purpose}
- **Location:** {location}
- **Request Format:** {requestFormat}
- **Response Format:** {responseFormat}

### Components
#### {name}
- **Type:** {type}
- **Purpose:** {purpose}
- **Location:** {location}

### Functions
#### {name}
- **Purpose:** {purpose}
- **Location:** {location}
- **Exported:** Yes/No

### Classes
#### {name}
- **Purpose:** {purpose}
- **Location:** {location}
- **Exported:** Yes/No

### Integrations
#### Integration
- **Description:** {description}
- **Frontend Component:** {frontendComponent}
- **Backend Endpoint:** {backendEndpoint}
- **Data Flow:** {dataFlow}

## Review Process

```json
{"reworkCount": N, "reviewOutcome": "commit", "findings": [...]}
```
```

Note: `## Review Process` JSON content can be derived from the `## Events` section's `review-worker cycle-*` and `parallel-worker rework-*` entries.

## TL6: Read/Write Rules

| Who | What | When |
|-----|------|------|
| **parallel-worker** | Create file (header + `## Metadata`) | Task start, if file does not yet exist (only the very first agent in the task creates it) |
| **parallel-worker** | Append `## Events` entries | Each phase transition, attempt start/result, divergent-analysis, handoff, rework start/complete |
| **review-worker** | Append `## Events` entries | Each review cycle start/end, commit |
| **integration-test Command** | Create file + append `## Events` | Job start (Command creates), per worker/pentagon launch and return |
| **integ-test-worker** | — | Never reads or writes the log |
| **integ-test-auditor** | — | Never reads or writes the log |
| **log-implementation skill** | Append `## Summary` / `## Statistics` / `## Files Modified` / `## Files Created` / `## Artifacts` / `## Review Process` | Once, at task completion (before marking `[x]`) |
| **log-implementation.sh hook** | Same as the skill, **only if the skill did not run** | Safety net at Stop time |
| **Anyone** | Read the file | Compaction recovery, review start, DR retrieval, dashboard fetch |

**Edit (in-place modification of existing content) is forbidden.** Only Write-to-create and Append-to-existing are permitted. This invariant keeps the file an honest log and avoids mid-task yield-trigger patterns.

The single exception is the completion sections written by `log-implementation`: it appends the sections, but each section is written once. Subsequent runs do not re-edit them.

## TL7: Path Construction Helpers

### For parallel-worker / review-worker (within a worktree)

The orchestrator (`spec-implement` skill) passes the absolute path:

```
Task log path: {project-root}/.spec-workflow/specs/{spec-name}/task-logs/{taskId}.log.md
```

The worker resolves this and writes via that absolute path. The file lives in the main repo (not in the worktree-local `.spec-workflow/` if any), so it persists after worktree deletion.

### For integration-test Command

The Command resolves the path at P1:

```python
if spec_context:
    log_path = f".spec-workflow/specs/{spec_name}/integ-test-runs/{timestamp}.log.md"
else:
    log_path = f".spec-workflow/integ-test-runs/{timestamp}.log.md"
```

The Command creates the parent directory if needed.

## TL8: Migration Note

- Tasks completed under the legacy `Implementation Logs/` directory remain in place. They are not migrated.
- Worktrees with existing `state.md` / `diagnosis.md` continue to operate under the legacy mode (the worker does not switch protocols mid-task).
- New tasks created after this rule comes into effect use the task log exclusively.
