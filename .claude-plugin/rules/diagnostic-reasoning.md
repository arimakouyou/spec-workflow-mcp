---
always_apply: true
---

# Diagnostic Reasoning

Structured diagnosis before every fix attempt, with session state persistence across retries.

## DR1: Mandatory Diagnosis Before Fix

Before writing ANY fix (code change intended to resolve a test failure, quality check failure, or review finding), write the diagnosis for the current attempt into `diagnosis.md` (located in the current worktree root) as that attempt's structured entry (see DR2 for the exact entry format and phase grouping). This `diagnosis.md` entry is the required durable record and must be written before implementing the fix.

The diagnosis entry must contain:

1. **Root cause**: What is the actual cause of the failure? (Not just "the test failed" but WHY it failed)
2. **Responsible**: Which file(s) and line(s) are responsible?
3. **Expected behavior**: What should the correct behavior be, per design docs / test expectations?
4. **Approach**: What fix strategy will you use?
5. **Failure category**: The FC1 main category (and optional subcategory) per `failure-taxonomy.md` FC2. Required — used by DR6 to detect recurring categorical failures.

This applies to: GREEN phase retries, quality check retries (clippy, cargo test, dotnet build, dotnet test), rework cycles, and wave-harness retries.

On the first attempt for a given phase, the diagnosis serves as upfront reasoning. On subsequent attempts, it also serves as differentiation from prior failed approaches (see DR3, DR4).

If a worker's completion report / response schema defines a `diagnosis` summary field (e.g., parallel-worker, wave-harness-worker), you may also summarize the diagnosis there, but that summary is optional and does NOT replace the required `diagnosis.md` entry.

## DR2: Session State Persistence

Persist every fix attempt as a structured entry in `diagnosis.md` (located in the current worktree root).

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
- **Failure category**: `{FC1 main category}` / `{FC1 subcategory}`
- **Result**: {PASS or FAIL — error summary}
```

The `Failure category` line is required per `failure-taxonomy.md` FC2 + FC4. It is written at the same time as the rest of the entry (before the fix, per the two-step write order below) — not added after the `Result` is known. It enables DR6 to detect same-category recurrence across attempts.

Group entries under phase headings: `## GREEN Phase`, `## Quality Checks`, `## Rework Cycle`.

**Write-order (two-step)**: Write the entry without the `Result` line before implementing the fix (per DR1 — the entry must be written and saved to `diagnosis.md` before implementing the fix; "committed" here means persisted to the file, NOT a git commit — `diagnosis.md` itself must never be git-committed per the File lifecycle above). After running verification, Edit the same entry to append the `Result` line with the outcome. This keeps DR1's "diagnose before fix" timing consistent with DR2's complete entry format.

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

Before the final allowed attempt — when you have one attempt remaining — call `advisor()` with your diagnosis for validation before implementing the fix. Include the `diagnosis.md` content in your advisor context so the reviewer can assess diagnosis quality.

## DR6: DIVERGENT Strategy on Recurring Categorical Failures

When the most recent **2 attempts in the current phase** share the same `failure_category` (per `failure-taxonomy.md` FC5), the next attempt MUST enter **DIVERGENT mode**. This is an extension of DR4 (non-repetition) — DR4 forbids repeating a failed *approach*, DR6 forbids continuing to fix within the same *premise* when two attempts under that premise have already failed.

### Trigger Condition (cross-references FC5)

- Same phase heading in `diagnosis.md` (`## GREEN Phase`, `## Quality Checks`, or `## Rework Cycle`)
- The most recent 2 `Result: FAIL` attempt entries both carry the same **main** `failure_category` (subcategory is ignored per FC5)
- When the main category changes or an attempt succeeds, the counter resets
- When the phase heading changes, the counter resets (GREEN and Quality Checks are counted separately)

### Required Procedure

Before writing the next DR2 attempt entry, insert a **Divergent Analysis block** under the current phase heading. Place this block **above** the `### Attempt {N}/{max}` heading (not inside it):

```markdown
## GREEN Phase

### Divergent Analysis (before Attempt {N}/{max})
- **Common implicit assumption**: {what assumption was shared across attempts {N-2} and {N-1}, not explicitly stated in either diagnosis?}
- **Why prior attempts kept failing under this assumption**: {one-sentence explanation of how the assumption forced both fixes to miss the real cause}
- **Challenge**: {what different premise this attempt will operate under}

### Attempt {N}/{max}
- **Root cause**: ...
- **Responsible**: ...
- **Expected behavior**: ...
- **Approach**: {must invalidate the implicit assumption — not a parameter tweak, reordering, or variant of prior approaches}
- **Failure category**: `{category}` / `{subcategory}`
```

The `Approach` in the DIVERGENT attempt must **fundamentally differ** from both prior attempts. Mechanical variants (swap two arguments, try a different constant, reorder the same operations) do NOT count as divergent and must be rejected by the worker itself before proceeding.

### Interaction with DR4 and DR5

- **DR4**: DIVERGENT is a stricter form of DR4 — DR4 requires a different approach, DR6 requires a different *premise*. If the DIVERGENT attempt shows the same premise as the prior two, it is not actually divergent and violates DR6
- **DR5**: If DIVERGENT triggers on the final attempt (the one that would normally require `advisor()`), the Divergent Analysis block becomes part of the advisor context. Include the entire `diagnosis.md` content AND the Divergent Analysis in the advisor prompt

### Failure of DIVERGENT

If the DIVERGENT attempt itself fails:

- Do NOT attempt another DIVERGENT variation within the same phase retry budget (retry_exhausted applies normally)
- Invoke DR4(c): escalate via `advisor()` or orchestrator report
- The completion / `retry_exhausted` report must record `divergent_applied: true` so that the orchestrator can include this signal in `diagnostic_history`

### Rationale

Repeated failure under the same `failure_category` indicates that the approach is operating on a wrong premise, not that the fix is incomplete. Mechanically trying "one more variant" of the same idea wastes retry budget. DR6 forces the worker to articulate and invalidate the premise before spending another attempt. This is the `failure-taxonomy`-driven version of "challenge the common implicit assumption" — the pattern that consistently produced improved success rates in multi-attempt agent workflows.
