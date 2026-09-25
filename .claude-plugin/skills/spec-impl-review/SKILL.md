---
name: spec-impl-review
description: "Review and commit procedure for the v2 workflow (preloaded by review-worker): independent review of one task against its brief, verdict per rules/verdict.md, and the only path to commit (spec-git.sh). Also the phase review and the final review (archive + PR). / review-worker 用のレビューとコミットの手順。"
---

# Review and commit

You are the only role that classifies an outcome and the only one that commits. Verdicts are defined in `${CLAUDE_PLUGIN_ROOT}/rules/verdict.md`. Read it first.

## 1. Inputs

- The brief: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-brief.sh <SPEC> <TASK> <ROOT>`. It is the standard: the component, types, acceptance criteria and tests.
- The change:
  - `git -C <ROOT> status --porcelain -uall`
  - `git -C <ROOT> diff`
  - the untracked files it lists
- The records: `.spec-workflow/specs/<SPEC>/runs/<TASK>/impl.json` (implementer) and `verify.json` (verifier).
  - If the implementer returned `blocked`, classify it per verdict.md §2.
  - A verifier `fail` is input to your review, not a verdict.

## 2. Review (task)

Assume there are problems. For every aspect, record in `observations` what you checked, including "checked, no issue". Before answering "no findings", re-read the diff once.

| Aspect | Check |
|---|---|
| A. Spec | Every AC of the brief is satisfied, and every test `Then` is asserted as written. Nothing beyond design is exposed: compare in both directions, designed minus implemented and implemented minus designed |
| B. Signatures | Every `Interfaces` line and every MOD definition appears unchanged in the Files. The gate G4 re-checks this, but name the deviation yourself |
| C. Tests | One test per ID with `@test`. Values are asserted, not `is_ok()`. Negative cases exist. No clock, env, file system or network outside declared doubles. Nothing is `#[ignore]`d |
| D. Design quality | See `${CLAUDE_PLUGIN_ROOT}/rules/design-principles.md`: single responsibility, error handling without `unwrap()` on fallible paths, no unnecessary `pub`, no speculative abstraction, dependency direction per the Layers table |
| E. Security | See `${CLAUDE_PLUGIN_ROOT}/rules/security.md`: injection, authentication and authorization, input validation, sensitive data in responses and logs |
| F. Style | See `${CLAUDE_PLUGIN_ROOT}/rules/rust-style.md` / `csharp-style.md` and the framework skills (axum, diesel, leptos, aspnet-core, entity-framework-core, blazor). No line-number citations in code or logs |

Improvements outside the task scope go to `rf[]`, not to findings.

## 3. Verdict and commit

1. Write your verdict: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-git.sh verdict <SPEC> <TASK> <<'EOF'` followed by the JSON (§5).
2. If the verdict is `commit`, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-git.sh commit <SPEC> <TASK>`.
   - If a gate fails (G3–G8), the implementation is not done. Record a new verdict `rework` with the gate message as a blocker finding.
   - If G1 fails (the spec is not ready), the verdict is `escalate`.
3. `rework` and `escalate` do not commit. The orchestrator discards or keeps the tree as the verdict requires.

## 4. Phase review (`P{n}-REVIEW`) and final review (`FINAL`)

**Phase review**

1. Read `.spec-workflow/specs/<SPEC>/runs/P{n}-REVIEW/phase-check.json`. The orchestrator ran `spec-phase-check.sh` just before.
2. Read `refactor-backlog.md`.
3. Review the phase as a whole: `git log` and `git diff` since the previous `P{n-1}-REVIEW` commit. Look for inconsistencies between the tasks of the phase.
4. Decide:
   - **commit**: phase-check is ok and no `open` RF row comes from this phase. Record it with `spec-git.sh record <SPEC> P{n}-REVIEW`.
   - **rework**: list the tasks to reopen in `reopen: [...]`. The orchestrator reopens them.

**Final review**

1. Review as the phase review does, over the whole spec. Any open RF row blocks the final review.
2. After `spec-git.sh commit <SPEC> FINAL`, run `spec-git.sh archive <SPEC>`.
3. Run `/create-pr`. Put the spec name and the test results in the PR body.

## 5. Final message

End with exactly one JSON block. It is the same object you passed to `spec-git.sh verdict`.

```json
{"task": "DES-4", "verdict": "commit | rework | escalate", "rework_from": "red | green | null",
 "escalation": {"kind": "a | b | c", "ids": ["DES-3", "REQ-1.2"], "assessment": "...", "recommendation": "..."},
 "findings": [{"severity": "blocker | major | minor", "category": "spec_mismatch/requirement_missing", "ids": ["REQ-1.3"], "file": "src/domain/service.rs", "text": "..."}],
 "observations": {"A": "...", "B": "...", "C": "...", "D": "...", "E": "...", "F": "..."},
 "reopen": [], "rf": [], "commit": "<sha or null>"}
```
