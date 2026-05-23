---
always_apply: true
---

# Diagnostic Reasoning

Structured diagnosis before every fix attempt, persisted in the task log across retries. The task log (`rules/task-log-format.md`) is the durable record; this rule defines *what* to record at each retry point.

## DR1: Mandatory Diagnosis Before Fix

Before writing ANY fix (code change intended to resolve a test failure, quality check failure, or review finding), append an `attempt-start` event to the `## Events` section of the task log with the diagnosis details. This event must be appended **before** implementing the fix.

The `attempt-start` event must contain (per `task-log-format.md` TL4):

1. **approach**: What fix strategy will you use?
2. **root_cause**: What is the actual cause of the failure? (Not just "the test failed" but WHY it failed)
3. **responsible**: Which file(s) and line(s) are responsible?
4. **expected_behavior**: What should the correct behavior be, per design docs / test expectations?

Then, after running the verification, append an `attempt-result` event with:

5. **result**: PASS or FAIL
6. **category**: The FC1 main category and optional subcategory per `failure-taxonomy.md` FC2. Required on FAIL — used by DR6 to detect recurring categorical failures.
7. **summary**: Error summary on FAIL (omit on PASS).

This applies to: GREEN phase retries, quality check retries (clippy, cargo test, dotnet build, dotnet test), and rework cycles.

On the first attempt for a given phase, the diagnosis serves as upfront reasoning. On subsequent attempts, it also serves as differentiation from prior failed approaches (see DR3, DR4).

If a worker's completion report / response schema defines a `diagnosis` summary field (e.g., parallel-worker), you may also summarize the latest diagnosis there for the orchestrator's convenience, but the task log entries remain the authoritative record.

## DR2: Task Log Persistence

Persist every fix attempt as a pair of `attempt-start` + `attempt-result` events under the `## Events` section of the task log.

**Task log lifecycle**:

- Created at task start by the first worker that runs (per `task-log-format.md` TL6)
- Events are **appended** after each retry attempt (before proceeding to the next attempt or reporting results)
- Lives under `.spec-workflow/specs/{spec-name}/task-logs/{taskId}.log.md` (outside the worktree, survives worktree deletion)
- **Must NOT be in `changed_files`**: the task log is project data, not an implementation change. It lives outside the worktree so review-worker will not stage it into the commit anyway.

**Event format** (see `task-log-format.md` TL4 for the full taxonomy):

```
- `{timestamp}` parallel-worker attempt-start phase={PHASE} n={N}
  - approach: {what you will do}
  - root_cause: {specific analysis}
  - responsible: {file:line}
  - expected_behavior: {per design docs / test spec}

- `{timestamp}` parallel-worker attempt-result phase={PHASE} n={N} result={PASS|FAIL} category={FC1 main}/{FC1 sub}
  - summary: {error summary on FAIL}
```

The `category` inline key on `attempt-result` is required per `failure-taxonomy.md` FC2 + FC4. It enables DR6 to detect same-category recurrence across attempts.

The `phase` inline key uses values `RED`, `GREEN`, `REFACTOR`, `quality_check`, or for rework cycles use the wrapping `rework-start` / `rework-complete` events (the `attempt-*` events within a rework cycle use `phase=rework` or carry the inherited phase).

**Write-order (two-step)**: Append the `attempt-start` event before implementing the fix (per DR1). After running verification, append a separate `attempt-result` event with the outcome. This keeps DR1's "diagnose before fix" timing as a distinct write from the verification result.

For inter-agent retries (rework cycles), the orchestrator also passes `diagnostic_history` in the prompt. Append to the task log regardless — it serves as the durable record.

## DR3: Prior Attempts Review

When attempt > 1, BEFORE appending your `attempt-start`:

1. Read the `## Events` section of the task log to review all prior `attempt-start` / `attempt-result` entries for the current phase
2. Explicitly acknowledge what was tried and why it failed
3. Your diagnosis MUST identify something DIFFERENT from prior diagnoses — a deeper root cause, a different responsible location, or a different mechanism

If the orchestrator provides `diagnostic_history` in the prompt, cross-reference it with the task log's `rework-*` events for completeness.

## DR4: Non-Repetition Constraint

Each retry MUST use a different approach from all prior attempts for the same failure.

If your diagnosis leads to the same root cause as a prior attempt, you must either:

- (a) Identify a deeper root cause that the prior diagnosis missed
- (b) Choose a fundamentally different fix strategy (e.g., switch from Obvious Implementation to Fake It)
- (c) Escalate — call `advisor()` or report to orchestrator

"DO NOT repeat failed approaches" — if attempt N used approach X and failed, attempt N+1 MUST NOT use approach X.

## DR5: Diagnosis Quality Gate

A diagnosis is **insufficient** if it:

- Restates the error message without analysis
- Identifies the same root cause as a prior failed attempt without new insight
- Names no specific file or line
- Proposes the same approach that already failed

Before the final allowed attempt — when you have one attempt remaining — call `advisor()` with your diagnosis for validation before implementing the fix. Include the recent `## Events` entries (especially `attempt-result` entries for this phase) in your advisor context so the reviewer can assess diagnosis quality.

## DR6: DIVERGENT Strategy on Recurring Categorical Failures

When the most recent **2 attempts in the current phase** share the same `failure_category` (per `failure-taxonomy.md` FC5), the next attempt MUST enter **DIVERGENT mode**. This is an extension of DR4 (non-repetition) — DR4 forbids repeating a failed *approach*, DR6 forbids continuing to fix within the same *premise* when two attempts under that premise have already failed.

### Trigger Condition (cross-references FC5)

- Same `phase=` value across `attempt-result` events (RED / GREEN / REFACTOR / quality_check, or `rework-*` wrapped events for rework cycles)
- The most recent 2 `attempt-result` events with `result=FAIL` both carry the same **main** `failure_category` (subcategory is ignored per FC5)
- When the main category changes or an attempt succeeds, the counter resets
- When the phase changes, the counter resets (GREEN and Quality Checks are counted separately)

### Required Procedure

Before appending the next `attempt-start` event, insert a `divergent-analysis` event:

```
- `{timestamp}` parallel-worker divergent-analysis phase={PHASE} before_attempt={N}
  - common_implicit_assumption: {what assumption was shared across the prior 2 attempts, not explicitly stated in either diagnosis?}
  - why_prior_failed: {one-sentence explanation of how the assumption forced both fixes to miss the real cause}
  - challenge: {what different premise this attempt will operate under}
```

Then append the next `attempt-start` event, where the `approach` field must reflect a fundamentally different premise:

```
- `{timestamp}` parallel-worker attempt-start phase={PHASE} n={N}
  - approach: {must invalidate the implicit assumption — not a parameter tweak, reordering, or variant of prior approaches}
  - root_cause: ...
  - responsible: ...
  - expected_behavior: ...
```

The `approach` in the DIVERGENT attempt must **fundamentally differ** from both prior attempts. Mechanical variants (swap two arguments, try a different constant, reorder the same operations) do NOT count as divergent and must be rejected by the worker itself before proceeding.

### Interaction with DR4 and DR5

- **DR4**: DIVERGENT is a stricter form of DR4 — DR4 requires a different approach, DR6 requires a different *premise*. If the DIVERGENT attempt shows the same premise as the prior two, it is not actually divergent and violates DR6
- **DR5**: If DIVERGENT triggers on the final attempt (the one that would normally require `advisor()`), the `divergent-analysis` event content becomes part of the advisor context. Include the entire recent `## Events` history AND the `divergent-analysis` event details in the advisor prompt

### Failure of DIVERGENT

If the DIVERGENT attempt itself fails:

- Do NOT attempt another DIVERGENT variation within the same phase retry budget (retry_exhausted applies normally)
- Invoke DR4(c): escalate via `advisor()` or orchestrator report
- The completion / `retry_exhausted` report must record `divergent_applied: true` so that the orchestrator can include this signal in `diagnostic_history`

### Rationale

Repeated failure under the same `failure_category` indicates that the approach is operating on a wrong premise, not that the fix is incomplete. Mechanically trying "one more variant" of the same idea wastes retry budget. DR6 forces the worker to articulate and invalidate the premise before spending another attempt. This is the `failure-taxonomy`-driven version of "challenge the common implicit assumption" — the pattern that consistently produced improved success rates in multi-attempt agent workflows.
