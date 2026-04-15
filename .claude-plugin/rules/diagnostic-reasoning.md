---
always_apply: true
---

# Diagnostic Reasoning

Structured diagnosis before every fix attempt, with session state persistence across retries.

## DR1: Mandatory Diagnosis Before Fix

Before writing ANY fix (code change intended to resolve a test failure, quality check failure, or review finding), write a `## Diagnosis` section containing:

1. **Root cause**: What is the actual cause of the failure? (Not just "the test failed" but WHY it failed)
2. **Responsible**: Which file(s) and line(s) are responsible?
3. **Expected behavior**: What should the correct behavior be, per design docs / test expectations?
4. **Approach**: What fix strategy will you use?

This applies to: GREEN phase retries, quality check retries (clippy, cargo test, dotnet build, dotnet test), rework cycles, and wave-harness retries.

On the first attempt for a given phase, the diagnosis serves as upfront reasoning. On subsequent attempts, it also serves as differentiation from prior failed approaches (see DR3, DR4).

## DR2: Session State Persistence

Persist every fix attempt as a structured entry in `{worktree_path}/diagnosis.md`.

**File lifecycle**:

- Create at task start (alongside state.md)
- Append after each retry attempt (before proceeding to the next attempt or reporting results)
- Remains in the worktree after task completion for knowledge retention
- **Must NOT be committed**: `diagnosis.md` is a local working file (like `state.md`). Workers must exclude it from `changed_files` so that review-worker does not stage it into the commit.

**Entry format**:

```markdown
### Attempt {N}/{max}
- **Root cause**: {specific analysis}
- **Responsible**: {file:line}
- **Expected behavior**: {per design docs / test spec}
- **Approach**: {what you will do}
- **Result**: {PASS or FAIL — error summary}
```

Group entries under phase headings: `## GREEN Phase`, `## Quality Checks`, `## Rework Cycle`.

For inter-agent retries (rework cycles, wave-harness), the orchestrator also passes `diagnostic_history` in the prompt. Write to `diagnosis.md` regardless — it serves as the durable record.

## DR3: Prior Attempts Review

When attempt > 1, BEFORE writing your diagnosis:

1. Read `diagnosis.md` to review all prior entries for the current phase
2. Explicitly acknowledge what was tried and why it failed
3. Your diagnosis MUST identify something DIFFERENT from prior diagnoses — a deeper root cause, a different responsible location, or a different mechanism

If the orchestrator provides `diagnostic_history` in the prompt, cross-reference it with `diagnosis.md` for completeness.

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

When retry limits are approaching (penultimate attempt), call `advisor()` with your diagnosis for validation before implementing the fix. Include the `diagnosis.md` content in your advisor context so the reviewer can assess diagnosis quality.
