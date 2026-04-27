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

- Each ref ID (REQ-N / REQ-N.M / DES-N / MOD-N / API-N / UT-N.M / IT-N / E2E-N) must exist in the referenced upstream file:
  - **REQ-N (bare, no `.M`)**: matches the `### REQ-N:` heading in requirements.md
  - **REQ-N.M**: matches either a `<!-- REQ-N.M -->` comment on an Acceptance Criterion line, or the **M-th** Acceptance Criterion (numbered list) under `### REQ-N:` — the `.M` suffix maps to the Acceptance Criteria index, not to `N`
  - **DES-N / MOD-N / API-N**: matches a `### DES-N:` / `### MOD-N:` / `### API-N:` heading in design.md
  - **UT-N.M / IT-N / E2E-N**: matches a `#### UT-N.M:` / `### IT-N:` / `### E2E-N:` heading in test-design.md
- Missing upstream ID → **error** (`dangling_reference`)
- Extra/orphan ID in upstream that no downstream references → **warn** (`orphan_upstream_id`; informational)

#### Check 3: No Cycles (SD5)

Build a graph: each file is a node, each `depends_on[].file` is a directed edge. Detect cycles:

- Cycle detected → **error** (`dependency_cycle`)
- Phase ordering violation (`tasks.md` depending on `requirements.md` directly without going through design.md): not an error in itself, but emit **info** (`phase_order_skipped`) if the user skipped an intermediate phase

#### Check 4: Requirements Coverage (I's core guarantee)

Every `REQ-N.M` in `requirements.md` must be covered by at least one task in `tasks.md` and at least one test spec in `test-design.md`.

**Task coverage rule**: A task covers `REQ-N.M` if its `_Requirements:` field includes ANY of the following values (per SD6 and the identifier equivalence below):

| `_Requirements:` value | Coverage interpretation |
|------------------------|-------------------------|
| `N.M` / `REQ-N.M` | Covers exactly `REQ-N.M` (specific Acceptance Criterion) |
| `N` / `REQ-N` | **Bare Requirement form** — covers every `REQ-N.*` under requirement N |
| `All` | Blanket coverage — matches every `REQ-N.M` in requirements.md. Typically used by final integration / PhaseReview tasks (see `tasks-template.md:107`) |
| `REQ-0` | Setup pseudo-requirement (Phase 0 Git init / container / CI / ADR). Does **not** cover any `REQ-N.M`; skip for Check 4 purposes |
| `NFR` | Non-Functional Requirement marker (filtered by `task-parser.ts`). Does **not** cover any `REQ-N.M`; skip for Check 4 purposes |

If no task covers a given `REQ-N.M` after applying the rules above → **error** (`requirement_not_implemented`).

**Test coverage rule**: At least one UT-N.M / IT-N / E2E-N in `test-design.md` covers `REQ-N.M` via the Requirements-Test Traceability Matrix → otherwise **error** (`requirement_not_tested`)

> **Identifier equivalence note** (per `spec-dependency-graph.md` SD1): the bare numeric values in tasks.md `_Requirements:` (e.g., `1.1`, `2.1`, `1`) are equivalent to the prefixed form (`REQ-1.1`, `REQ-2.1`, `REQ-1`). Normalize both sides to the `REQ-N` / `REQ-N.M` form before matching.

#### Check 5: Component Coverage

Every `DES-N` in `design.md` should be reachable:

- At least one task implements it (either via `depends_on.refs` in tasks.md frontmatter, or via `_Leverage` file paths that match the component's implementation location) → otherwise **warn** (`component_no_task`)
- At least one UT or IT tests it (per test-design.md) → otherwise **warn** (`component_no_test`)

#### Check 6: Test Coverage Symmetry

- Every UT-N.M / IT-N / E2E-N in `test-design.md` should appear in the Requirements-Test Traceability Matrix → otherwise **warn** (`test_not_in_matrix`)
- Every REQ-N.M in the matrix should be listed against at least one test → otherwise **error** (`requirement_missing_in_matrix`)

#### Check 7: Task-level Metadata Sanity (SD6)

- **`_Requirements:` values** must be one of the accepted forms (per SD6 + existing templates / skills):

  | Value form | Validation rule | Dangling handling |
  |------------|-----------------|-------------------|
  | `N.M` / `REQ-N.M` | Must reference an existing Acceptance Criterion in requirements.md. Match is satisfied if **either** of the following is present (OR, not AND): (a) a `<!-- REQ-N.M -->` comment on an Acceptance Criterion line, or (b) the **M-th** Acceptance Criterion (numbered list item) under a `### REQ-N:` heading — the `.M` suffix maps to the Acceptance Criteria index, not to `N`. Both (a) and (b) are valid match sources — legacy specs without comments pass via (b), new specs with comments pass via (a) | If neither (a) nor (b) is found → **error** (`task_requirement_dangling`) |
  | `N` / `REQ-N` | Must reference an existing `### REQ-N:` heading in requirements.md | If not found → **error** (`task_requirement_dangling`) |
  | `All` | Blanket marker — always valid | Emit **info** (`requirements_all`) noting the task covers every requirement |
  | `NFR` | Non-Functional Requirement marker (filtered by `task-parser.ts`) — always valid | Emit **info** (`requirements_nfr`) |
  | `REQ-0` | Reserved setup pseudo-requirement for Phase 0 scaffolding (Git init / containers / CI / ADR — see `spec-tasks/SKILL.md` Phase 0 examples) — always valid even if `REQ-0` is not declared in requirements.md | Emit **info** (`requirements_setup`) |
  | other | Unknown form | **error** (`task_requirement_unknown_form`) with the specific value |

- **`_DependsOn:` values** must reference existing task IDs within the same tasks.md → otherwise **error** (`task_dependency_dangling`)
- **`_Leverage:` file paths** should exist (best-effort filesystem check) → otherwise **info** (`leverage_file_missing`; may be intentional for future files)

#### Check 9: Type Reference Resolution (per C-3, dapper-hardening)

> 出典: `.claude/_docs/plans/dapper-hardening-orchestrator.md` 根本原因 C（C-3）。
> spec-design Step B Check 13 (TYPE_REFERENCE_RESOLUTION) と spec-test-design Step B Check 18 (SIGNATURE_MATCH) を spec-verify レベルで横断的に実行する。

For each `### DES-N:` in design.md:

1. Parse `Interfaces:` field for function signatures
2. Extract custom type references (`Result<X, E>` の `X`/`E`、`Vec<T>` の `T`、`Signal<T>` の `T`、`Callback<T>` の `T` など)
3. Check each custom type:
   - Is it defined as `### MOD-N: <Type>` heading in the same design.md?
   - Or is it a standard library type (std::*, core::*, alloc::*)?
   - Or is it a known framework type allowlist (Leptos の `Signal`, `Resource`, `Callback`、Axum の `Json`, `Path`、.NET の `IActionResult` 等)?
4. Undefined types → **error** (`undefined_type_reference`) with the type name and location

For each test specification in test-design.md (UT-N.M / CT-N.M / IT-N / ST-N / E2E-N):

1. If the test references a function or method from design.md DES-N, extract the assumed signature
2. Compare with the actual signature in design.md DES-N の `Interfaces:` field
3. Mismatch → **error** (`signature_mismatch`) with both signatures shown

Allowlist:
- Rust: `std::*`, `core::*`, `alloc::*`, `tokio::*`, `serde::*`, `chrono::*`
- Leptos: `Signal`, `RwSignal`, `ReadSignal`, `WriteSignal`, `Resource`, `Memo`, `Callback`, `RwSignal`, `Effect`, `IntoView`
- Axum: `Json`, `Path`, `Query`, `State`, `Extension`, `IntoResponse`, `Response`, `Request`
- .NET: `Task`, `IActionResult`, `ActionResult<T>`, `IEnumerable<T>`, `List<T>`, `Dictionary<K,V>`, `Nullable<T>`
- Node.js: built-in types (`Promise`, `Array`, `Map`, `Set`)
- Generic types (`<T>`) are allowed without resolution

#### Check 8: Requirement Test Layers Declaration (per K-1)

> 出典: `.claude/_docs/plans/dapper-hardening-orchestrator.md` 根本原因 K（K-1）。
> Test Taxonomy は `quality-checks.md` の Test Taxonomy セクション参照（J-3 で確定）。

For each Acceptance Criterion in `requirements.md` (numbered list under `### REQ-N:`):

- The line immediately below the AC must contain `- Test Layers: ...` declaring which test layers verify the criterion
- Allowed layer values: `UT`, `CT`, `IT-N` (or `IT`), `ST-N` (or `ST`), `E2E-N` (or `E2E`)
  - 具体 ID 形式（`IT-3` 等）は test-design.md で確定後に back-fill。requirements.md 段階では layer 名のみでも可
  - 複数組合せ可（例: `Test Layers: UT, IT-1, ST-3`）
- Missing `Test Layers:` line for any AC → **error** (`req_test_layers_missing`)
- Layer value not in allowed set → **error** (`req_test_layers_invalid_value`)
- Specific ID (`IT-N`) referenced does not exist in test-design.md → **warn** (`req_test_layers_dangling_id`)（test-design.md 未確定段階では無視）

Legacy specs without `Test Layers:` lines: emit **warn** (`req_test_layers_legacy`) instead of error, allowing gradual migration.

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
