---
name: spec-verify
description: "Verify spec-to-spec and spec-to-test-to-implementation consistency. Use this skill when the user wants to validate traceability across requirements.md / design.md / test-design.md / tasks.md, check that every REQ is covered by tests and tasks, detect missing or dangling references, or audit the dependency graph. Triggers on: 'verify spec', 'check spec consistency', 'spec audit', 'traceability check', '/spec-verify'. Implements the Harness-as-Code self-verification pattern (three-way match between spec, test, and implementation)."
---

# Spec Verify (Harness-as-Code Verification)

Cross-check the consistency of `requirements.md` ⇔ `design.md` ⇔ `test-design.md` ⇔ `tasks.md` within a single spec directory. Report missing references, dangling references, cycles, and coverage gaps per `.claude-plugin/rules/spec-dependency-graph.md` SD1-SD7.

This skill is the self-verification counterpart to `/spec-impact-analyze` — impact-analyze tells you **what needs revisiting when upstream changes**, spec-verify tells you **whether the spec set is internally consistent right now**.

## When to Use

- After completing `/spec-tasks` (Phase 4) to ensure the full spec set is consistent before implementation starts
- After manual edits to any spec file, to catch broken references before they reach `/spec-implement`
- During `/spec-status` review, as a deeper integrity check
- When migrating a legacy spec: identify which files still lack frontmatter

## Prerequisites

1. `.spec-workflow/specs/{spec-name}/` exists
2. At minimum `requirements.md` exists. Missing downstream files (design / test-design / tasks) are reported as warnings, not errors

## Inputs

- **spec name** (kebab-case, required)
- **fail-on** (optional; one of `error`, `warn`, `never`; default: `error`):
  - `error` — exit code 1 if any error-level finding is present
  - `warn` — exit code 1 if any warning or error is present
  - `never` — always exit 0, pure reporting

## Process

### 1. Discover Files and Frontmatter

List files in `.spec-workflow/specs/{spec-name}/`:

- `requirements.md` — required
- `design.md` — warn if absent
- `test-design.md` — warn if absent
- `tasks.md` — warn if absent

For each file, read the YAML frontmatter. If absent:

- For `requirements.md` / `design.md` / `test-design.md` / `tasks.md`: record as `frontmatter_missing` (severity depends on file — see Check 1)
- Legacy specs (all four files missing frontmatter) fall back to pure content scanning for IDs (best-effort; some checks will be downgraded to `not_available`)

### 2. Extract IDs from Content

Parse each file's body for IDs, using the heading conventions from `.claude-plugin/rules/spec-dependency-graph.md` SD1:

| File | Heading pattern | Captured ID |
|------|-----------------|-------------|
| requirements.md | `### REQ-N:` heading + numbered Acceptance Criteria | `REQ-N.M` (one per Acceptance Criterion) |
| design.md | `### DES-N:` / `### MOD-N:` / `### API-N:` | `DES-N` / `MOD-N` / `API-N` |
| test-design.md | `#### UT-N.M:` / `### IT-N:` / `### E2E-N:` | `UT-N.M` / `IT-N` / `E2E-N` |
| tasks.md | `- [ ] N.M ...` or `- [x] N.M ...` list items (via task-parser conventions) | `N.M` (task-id) |

Also extract:
- **tasks.md `_Requirements:` values** — per-task REQ references
- **test-design.md Requirements-Test Traceability Matrix rows** — REQ ↔ UT/IT/E2E

### 3. Run Consistency Checks

Each check produces zero or more findings with severity (`error` / `warn` / `info`).

#### Check 1: Frontmatter presence (SD2, SD3)

For each of `requirements.md` / `design.md` / `test-design.md` / `tasks.md` that exists:

- If frontmatter is absent → **warn** (`frontmatter_missing`). Downstream checks that depend on frontmatter are downgraded to `not_available` for this file
- If frontmatter is malformed YAML → **error** (`frontmatter_malformed`)
- If `spec_id` does not match `{spec-name}` → **error** (`spec_id_mismatch`)
- If `phase` is not the expected value for the file → **error** (`phase_mismatch`)

#### Check 2: Reference Integrity (SD4)

For each downstream file's `depends_on[].refs`:

- Each ref ID (REQ-N.M, DES-N, etc.) must exist in the referenced upstream file (by heading or `<!-- REQ-N.M -->` comment)
- Missing upstream ID → **error** (`dangling_reference`)
- Extra/orphan ID in upstream that no downstream references → **warn** (`orphan_upstream_id`; informational)

#### Check 3: No Cycles (SD5)

Build a graph: each file is a node, each `depends_on[].file` is a directed edge. Detect cycles:

- Cycle detected → **error** (`dependency_cycle`)
- Phase ordering violation (`tasks.md` depending on `requirements.md` directly without going through design.md): not an error in itself, but emit **info** (`phase_order_skipped`) if the user skipped an intermediate phase

#### Check 4: Requirements Coverage (I's core guarantee)

Every `REQ-N.M` in `requirements.md` must be covered:

- At least one task in `tasks.md` has `_Requirements:` that includes `N.M` (or `N` covering all its Acceptance Criteria) → otherwise **error** (`requirement_not_implemented`)
- At least one UT-N.M / IT-N / E2E-N in `test-design.md` covers `REQ-N.M` via the Requirements-Test Traceability Matrix → otherwise **error** (`requirement_not_tested`)

> **Identifier equivalence note** (per `spec-dependency-graph.md` SD1): the bare numeric values in tasks.md `_Requirements:` (e.g., `1.1`, `2.1`) are equivalent to the prefixed form (`REQ-1.1`, `REQ-2.1`). When matching `_Requirements: 1.1` against requirements.md, treat it as `REQ-1.1`.

#### Check 5: Component Coverage

Every `DES-N` in `design.md` should be reachable:

- At least one task implements it (either via `depends_on.refs` in tasks.md frontmatter, or via `_Leverage` file paths that match the component's implementation location) → otherwise **warn** (`component_no_task`)
- At least one UT or IT tests it (per test-design.md) → otherwise **warn** (`component_no_test`)

#### Check 6: Test Coverage Symmetry

- Every UT-N.M / IT-N / E2E-N in `test-design.md` should appear in the Requirements-Test Traceability Matrix → otherwise **warn** (`test_not_in_matrix`)
- Every REQ-N.M in the matrix should be listed against at least one test → otherwise **error** (`requirement_missing_in_matrix`)

#### Check 7: Task-level Metadata Sanity (SD6)

- `_Requirements:` values in tasks.md must reference existing REQ-N.M → otherwise **error** (`task_requirement_dangling`)
- `_DependsOn:` values must reference existing task IDs within the same tasks.md → otherwise **error** (`task_dependency_dangling`)
- `_Leverage:` file paths should exist (best-effort filesystem check) → otherwise **info** (`leverage_file_missing`; may be intentional for future files)

### 4. Generate Report

Output a markdown report. Do not write to any spec file. Optionally save to `.spec-workflow/specs/{spec-name}/reviews/verify-{YYYY-MM-DD-HHMM}.md` if the user requests.

```markdown
# Spec Verify: {spec-name}

**Date**: {YYYY-MM-DD HH:MM}
**fail-on**: {error | warn | never}

## Summary

- ✅ 0 errors
- ⚠️ 2 warnings
- ℹ️ 1 info

**Verdict**: PASS / FAIL (based on fail-on)

## Findings

### Errors

(none)

### Warnings

1. **frontmatter_missing** — `tasks.md` has no frontmatter. Downstream dependency checks downgraded to `not_available` for this file. Action: add frontmatter per spec-dependency-graph.md SD2.
2. **component_no_test** — `DES-3 (UserExport)` has no UT/IT in test-design.md. Action: add UT spec covering DES-3.

### Info

1. **leverage_file_missing** — task 1.2 references `_Leverage: src/types/export.ts` which does not exist yet. May be intentional for future implementation.

## Coverage Matrix

| REQ-ID | Implemented (task) | Tested (UT/IT/E2E) |
|--------|--------------------|--------------------|
| REQ-1.1 | 1.1, 1.2 | UT-1.1, IT-1 |
| REQ-1.2 | 1.3 | UT-1.2 |
| REQ-2.1 | 2.1 | IT-2, E2E-1 |

## Next Steps

For each error or warning, the recommended fix is listed in the "Action" field. Run /spec-verify again after fixes to confirm PASS.
```

### 5. Exit Behavior

- If `fail-on: never` — always exit 0 (pure reporting mode)
- If `fail-on: warn` — exit 1 if any warning or error
- If `fail-on: error` (default) — exit 1 if any error

## Rules

- **Read-only** — never modifies any spec file
- **Legacy-tolerant** — files without frontmatter produce warnings, not errors (SD3 opt-in compatibility)
- **Heuristic-free classification** — this skill only reports; it does not decide whether a coverage gap is acceptable
- **Does not gate `/spec-implement`** by default — but `/spec-implement` or CI may opt to call `/spec-verify` as a pre-flight check and block on `fail-on: error`
- **Coverage semantics** — "covered" means a forward reference chain exists: `REQ` → at least one task (`_Requirements:`) AND at least one test (Traceability Matrix). Missing either side is an error
