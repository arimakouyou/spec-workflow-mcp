---
name: spec-status
description: "Show the progress state of a spec. Displays phase completion (request-spec → requirements → design → test-design → tasks → implementation) and task progress for the given spec name. Triggers on: '/spec-status invocation', 'check spec progress', 'spec status', '仕様の進捗状態を確認', 'when user asks about spec progress'."
---

# Spec Status — Spec Progress Check

Check and display the current progress of the specified spec.

## Inputs

- **specName** (spec-name): Spec name (kebab-case). Received as the first argument of `$ARGS`.

**Invocation form**: `/spec-status <spec-name>` (e.g., `/spec-status user-authentication`)

## Process

### 1. File Existence Check

Use Glob to check the files under `.spec-workflow/specs/{spec-name}/`:

| File | Phase |
|---------|---------|
| `request-spec.md` | Phase 0: Request Spec |
| `requirements.md` | Phase 1: Requirements |
| `design.md` | Phase 2: Design |
| `test-design.md` | Phase 3: Test Design |
| `tasks.md` | Phase 4: Tasks |

### 2. Task Progress Aggregation

If `tasks.md` exists, count the task statuses:
- `[ ]` → pending (not started)
- `[-]` → in-progress
- `[x]` → completed

Count each pattern with grep:
```bash
grep -c '^\- \[ \]' .spec-workflow/specs/{spec-name}/tasks.md || echo 0
grep -c '^\- \[-\]' .spec-workflow/specs/{spec-name}/tasks.md || echo 0
grep -c '^\- \[x\]' .spec-workflow/specs/{spec-name}/tasks.md || echo 0
```

### 3. Determine the Current Phase

Determine the current phase from the existing files. Report **the next required phase**:
- tasks.md exists + all tasks completed → `completed`
- tasks.md exists + some tasks incomplete → `implementation`
- tasks.md exists + no tasks started → `tasks` (waiting for implementation to begin)
- up to test-design.md exists → `tasks-needed` (Phase 4 not complete)
- up to design.md exists → `test-design-needed` (Phase 3 not complete)
- up to requirements.md exists → `design-needed` (Phase 2 not complete)
- only request-spec.md exists → `requirements-needed` (Phase 1 not complete)
- nothing → `not-started`

**Legacy spec compatibility**: If `request-spec.md` does not exist but `requirements.md` does, skip Phase 0 and treat Phase 1 as complete (request-spec is a phase introduced later).

### 4. Result Display

Display in the following format:

```
## {spec-name} — Spec Progress

**Current phase**: {currentPhase}

### Phase Status
- [x] Phase 0: Request Spec
- [x] Phase 1: Requirements
- [ ] Phase 2: Design
- [ ] Phase 3: Test Design
- [ ] Phase 4: Tasks

### Task Progress (when Phase 4 is complete)
- Completed: {completed}/{total}
- In progress: {inProgress}
- Not started: {pending}
```
