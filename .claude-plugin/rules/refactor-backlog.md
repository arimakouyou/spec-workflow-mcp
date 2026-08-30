# Refactor Backlog

Refactoring that a task notices but must not perform in that task is **recorded**, then **performed in the Phase's `_PhaseRefactor: true_` task**. Nothing is refactored ad hoc outside its task scope, and nothing noticed is silently dropped.

## RB1: The backlog file

Path: `.spec-workflow/specs/{spec-name}/refactor-backlog.md` (one per spec; created on first entry).

```markdown
# Refactor Backlog: {spec-name}

| ID | Status | Found in | Files | Symptom | Proposed change | Resolved in |
| --- | --- | --- | --- | --- | --- | --- |
| RF-001 | open | 3.10 review | crates/x/tests/it_a.rs, it_b.rs | 2 files nearly identical (~730 lines, 3 literals differ) | extract decide→status→assert helper into tests/support/ | — |
| RF-002 | done | 3.11 impl | ... | ... | ... | 3.38 |
| RF-003 | deferred | 3.35 review | ... | ... | ... | Phase 4 (reason: files change again in 4.2) |
```

- **ID**: `RF-NNN`, sequential per spec, never reused
- **Status**: `open` / `done` / `deferred` / `rejected`
- **Found in**: task id + `impl` (parallel-worker) or `review` (review-worker)
- **Files**: repo-relative paths (grep-able anchors, not prose)
- **Symptom**: what is duplicated / unclear / misplaced — observable facts, with sizes where relevant
- **Proposed change**: the concrete restructuring (helper name, target module, what collapses into what)
- **Resolved in**: task id that closed it, or the Phase / reason for `deferred`, or the reason for `rejected`

## RB2: What goes in

Record an entry when you notice, in the current task, restructuring that would improve the code but is **outside the task's scope** — typically:

- Duplication with files written by **other** tasks (the TDD REFACTOR phase covers only the code written in this task)
- A helper / fixture that two or more tests should share
- Naming, module placement, or responsibility splits that touch files the task does not own
- Test-code structure that makes the next similar test a copy-paste (record it when writing the **second** copy, not the third)

Do **not** record:

- Defects (spec non-conformance, failing behavior) — those are findings, handled by review-worker's severity rules
- Anything that changes observable behavior, the public API, or design.md — that is a design change, not a refactor
- Refactoring inside the task's own files — do it now in the REFACTOR phase

## RB3: Who writes

| Actor | When | How |
| --- | --- | --- |
| parallel-worker | REFACTOR phase, when it sees an out-of-scope candidate | Append the row; list the IDs under `known_concerns` in the handoff |
| review-worker (per-task) | Category B / E observations that are quality-not-defect | Append the row; list the IDs in the completion report `refactor_backlog` key. Do not carry them as prose concerns |
| review-worker (Phase Review) | Quality & maintainability perspective | Append remaining candidates; verify RB5 |
| orchestrator (spec-implement) | Never edits rows | Reads the file to build the `_PhaseRefactor` task prompt |

Appending is a plain table-row edit; no approval is required. Keep one row per candidate; if a later task widens an existing candidate (a third copy of the same file), update that row's Files / Symptom rather than adding a new row.

## RB4: The `_PhaseRefactor: true_` task

spec-tasks places one `_PhaseRefactor: true_` task in every Phase, immediately before the `_PhaseReview: true_` task (after IT / CT / ST tasks). It has no `_TestFocus` (no new behavior, no new tests) and its `_Prompt` says: consume the backlog.

Execution (spec-implement Step 3.6):

1. Scope = every `open` row whose Files are in this Phase or earlier. Rows found in the current Phase are mandatory; earlier `deferred` rows whose stated reason no longer holds are also in scope
2. Behavior-preserving only: no test expectation changes, no public API changes, no design.md changes, no new features. If a row cannot be done without one of those, mark it `rejected` with the reason (or `deferred` with a concrete condition) — do not do half of it
3. Each row is one commit-able step: apply, run the full quality checks (`quality-checks.md` for the project type), confirm every existing test still passes, then update the row to `done` with `Resolved in`
4. An empty backlog is a legitimate outcome: the task completes with `refactor_backlog: none` in its report, and the task-log records that the file was checked
5. review-worker reviews the task like any other (categories A–G apply; D is "every in-scope row is `done`, `deferred`, or `rejected` with a stated reason, and no row changed behavior")

## RB5: Phase Review gate

Phase Review (review-worker) checks the backlog:

- No `open` row whose Files are in this Phase or earlier → pass
- An `open` row remaining → `review_action: rework` of the `_PhaseRefactor` task (it did not consume its scope)
- `deferred` rows must name the Phase or condition that resolves them; a `deferred` row without a reason is treated as `open`

The final Phase Review additionally requires no `deferred` rows at all: by the end of the spec every row is `done` or `rejected`.
