# Verdict (v2)

This is the single definition of how an implementation task ends. Only review-worker classifies. Implementers and verifiers report facts. The orchestrator routes on the verdict and never re-classifies it.

## 1. Verdicts

| Verdict | When | Next |
|---|---|---|
| `commit` | Every blocker and major finding is resolved, and the commit gate (`spec-git.sh commit`, G0–G9) passes | The task is recorded in one commit |
| `rework` | Anything the implementer can fix within the approved spec (§2) | The implementer runs again from `rework_from` |
| `escalate` | Only (a) the spec contradicts itself, (b) satisfying the requirement needs a design change, or (c) the rework limit is reached | The orchestrator stops and the user runs `/spec-change` or decides |

`rework_from` is `red` when tests are wrong or missing. The worker then rewrites tests and records a new RED checkpoint. Otherwise it is `green`: implementation only, and the tests stay locked.

**Rework limit**: 3 per task. The 4th would-be rework is `escalate (c)`, with the diagnosis history.

## 2. Rework, not a user decision

These are always `rework`. Never offer "relax the requirement" or "add it to the design" as an option.

| Defect | Category |
|---|---|
| An acceptance criterion, or a test-design `Then`, is not satisfied | `spec_mismatch/requirement_missing` |
| The implementation exposes something design does not define: an extra key, field, endpoint, status code, public function or side effect | `spec_mismatch/surplus` |
| A signature differs from DES Interfaces, or a type from its MOD Definition. The gate G4 also catches this | `spec_mismatch/signature` |
| A test is missing, weak or wrong: only asserts `is_ok()`, has no Negative case, depends on the clock or the environment, or has an ID that does not match test-design | `test_failure/weak_test` |
| A quality check fails: format, lint, audit, a surviving mutant | `quality_check_failure/*` |
| A layer dependency violation, or a file outside the task's scope | `spec_mismatch/layer` |
| The worker returned `blocked(retry_exhausted)` | `rework`. The count goes up |

When the worker returns `blocked(spec_conflict)`, review-worker assesses it:

- The spec really is contradictory or incomplete → `escalate (a)` or `(b)`. Name the document and IDs to change, and give your recommendation.
- The worker misread the spec → `rework`, with the correct reading cited by ID.

## 3. Findings

Each finding is `{severity, category, ids, file, text}`.

| Severity | Meaning | Effect |
|---|---|---|
| `blocker` | Violates the spec, security or a gate | `rework` or `escalate` |
| `major` | A defect in tests, design quality or error handling | `rework` |
| `minor` | Style, or a local improvement that does not violate the spec | Not a verdict driver. Put it in `rf[]` when it is worth doing later |

**Out-of-scope improvements** (duplication across files, a helper several tasks could share) are never findings and never prose. They go to `rf[]`: `spec-git.sh` appends them to `refactor-backlog.md` as `RF-NNN`, and `P{n}-REFACTOR` consumes them.

## 4. Diagnosis before retry (implementers and verifiers)

Before any retry, write down:

- the failing check
- the hypothesis
- the evidence that supports it: the error line, the test output

After two failures in the same category, change the approach instead of repeating it. Before the third attempt, call the advisor with the diagnosis so far.

Report `retry_exhausted` rather than weakening a test, skipping a check or changing a signature.

## 5. Phase review

`P{n}-REVIEW` is `commit` (recorded with `spec-git.sh record`) only when both hold:

- `spec-phase-check.sh` is all ok
- no `open` RF row originates from phase n

Otherwise it is `rework`, naming the tasks to reopen (`reopen: [...]`). The final review also refuses any remaining open RF row.
