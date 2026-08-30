---
always_apply: true
---

# Failure Taxonomy

Cross-cutting failure-classification vocabulary. Used as the **shared key** for retries, send-backs, and DIVERGENT decisions across `parallel-worker` / `review-worker` / `spec-impl-test-run` and similar agents.

The objectives are the following three:

1. In addition to the free-text `last_error` each agent had been using on its own, require a **machine-readable classification tag** `failure_category`
2. Provide the vocabulary so that the threshold check for DR6 (DIVERGENT Strategy) in `diagnostic-reasoning.md` can be performed in terms of "consecutive failures of the same category"
3. Make the correspondence between review-worker's Severity Classification (Minor / Moderate / Critical) and the failure classification explicit, so that send-back decisions are consistent

## FC1: Category Set

There are four primary categories. Each one defines its own subcategories.

| Category | When to use | Sub-categories |
|----------|-------------|---------------|
| `compile_error` | Source code or test code does not pass build/compile. A failure prior to execution | `syntax_error`, `type_error`, `unresolved_import`, `missing_symbol`, `borrow_check_error`, `trait_bound_unsatisfied` |
| `test_failure` | Build succeeds, but test execution fails | `assertion_failure`, `panic`, `timeout`, `unexpected_pass` (a test expected to be RED passed), `flaky` |
| `quality_check_failure` | Failure at a quality gate | `format_violation` (rustfmt / dotnet format), `lint_violation` (clippy / Roslyn), `dependency_vulnerability` (cargo audit / dotnet list package --vulnerable), `mutation_survived` (cargo-mutants / Stryker.NET), `wasm_build_failure` (cargo leptos build), `trim_aot_incompatibility` (dotnet publish -p:PublishTrimmed=true) |
| `spec_mismatch` | Divergence between the implementation and the spec documents (requirements.md / design.md / `_Prompt` in tasks.md) | `design_conformance_violation` (review category F), `requirement_missing` (D), `restriction_violated` (D), `api_contract_mismatch` (G), `test_design_missing` (E) |

**Escalation-only category (excluded from the DIVERGENT count)**:

- `unknown`: Use this **only** when the failure does not fit any other classification. `unknown` must not be reused on a second or later attempt (FC6 explicitly prohibits this)

## FC2: Required Reporting Fields

In the locations below, include `failure_category` as a **required field** (`failure_subcategory` is optional; when omitted, leave it as an empty string or unspecified).

| Location | Format |
|---------|---------|
| `attempt-result` event in the task log's `## Events` section (per `rules/task-log-format.md` TL4) | Inline key on the event line: `category={category}/{subcategory}` |
| `parallel-worker`'s `retry_exhausted` report | `- failure_category: {category}` / `- failure_subcategory: {subcategory}` (optional) |
| `diagnosis` object in the completion report of `parallel-worker` | `failure_category: {category}` (alongside `root_cause` / `responsible_files` / `approach`) |
| `findings` entries in `review-worker` | `failure_category: {category}` / `failure_subcategory: {subcategory}` (separate from the existing `category: A|B|C|D|E|E2|F|G`; record both) |
| Verdict in the Output Format of `spec-impl-test-run` | `- **Failure Category**: {category}` / `- **Failure Subcategory**: {subcategory}` (only on fail) |
| `diagnostic_history` cumulative template in `spec-implement` | `- **Failure category**: {category}` / `{subcategory}` |

For legacy paths where `failure_category` cannot be obtained, record `(not reported)`, but the next attempt must concretize it.

## FC3: Severity Mapping (with review-worker)

Correspondence with the Severity Classification (Minor / Moderate / Critical) in `review-worker.md`. **When review-worker generates findings**, refer to this table and assign `failure_category` / `failure_subcategory` and `severity` consistently.

| failure_category | failure_subcategory | review-worker category | severity | Notes |
|------------------|---------------------|------------------------|----------|------|
| `compile_error` | (any) | — | N/A | Resolved by `parallel-worker` before reaching review. If detected during review, treat as Moderate (B) |
| `test_failure` | (any) | E | Moderate | send back |
| `quality_check_failure` | `format_violation` | A | Minor | review-worker auto-fixes |
| `quality_check_failure` | `lint_violation` | A / B | Minor / Moderate | Depends on the warning level. clippy `-D warnings` equivalent is Moderate |
| `quality_check_failure` | `dependency_vulnerability` | C | Critical | blocking (cannot commit) |
| `quality_check_failure` | `mutation_survived` | E | Moderate | Send back as insufficient tests |
| `quality_check_failure` | `wasm_build_failure` / `trim_aot_incompatibility` | B | Moderate | |
| `spec_mismatch` | `design_conformance_violation` | F | Critical | Surplus (implementation exposes a key / field / column / endpoint / behavior design.md does not define): send back (rework) to remove it. Missing / mismatched items and DC4 module-boundary violations: escalate to user (see `review-worker.md` F) |
| `spec_mismatch` | `requirement_missing` / `restriction_violated` | D | Critical | send back (rework) — the requirement is the standard, the implementer fixes the implementation. Escalate only when the spec is self-contradictory, a design.md change is required, or the rework limit is exhausted (see `review-worker.md` D) |
| `spec_mismatch` | `api_contract_mismatch` | G | Minor | Report as a `/generate-api-docs` recommendation |
| `spec_mismatch` | `test_design_missing` | E | Moderate | send back |

Correspondence between severity and action (re-stated from existing rules in `review-worker.md`):

- **Minor** -> auto-fix or advisory
- **Moderate** -> send back to parallel-worker (up to 3 reworks)
- **Critical** -> escalate to user, except D (`requirement_missing` / `restriction_violated`) and F surplus (`design_conformance_violation` where the implementation adds what design.md does not define), which are sent back to parallel-worker as rework

### Correspondence with External Severity Scales (Source of Truth)

Map the Minor / Moderate / Critical labels used in `review-worker.md` findings, log-implementation, and elsewhere onto common external severity vocabularies. **This table is the source of truth (SSoT)**, and other documents (e.g., the severity correspondence table in `review-worker.md`) are treated as a re-statement of this table.

| FC3 (this document) | Common external scale | CVSS equivalent |
|-------------|---------------------|----------|
| Minor | low | informational / low |
| Moderate | medium | medium |
| Critical | high / critical | high / critical |

When emitting findings, use Minor / Moderate / Critical labels and align the vocabulary across the Severity Classification table, the FC3 table, and the findings output. When ingesting output from external tools (`cargo audit` / `npm audit` / GitHub Advisory and so on), normalize them to the FC3 vocabulary using this table.

## FC4: Integration with DR2 (diagnostic-reasoning.md)

Add a `Failure category` line to DR2 attempt entries in `diagnostic-reasoning.md`. **The write timing is the same "write before fix"** as in DR1 (write it together with the body of the attempt entry, before the `Result` line).

```markdown
### Attempt {N}/{max}
- **Root cause**: {specific analysis}
- **Responsible**: {file:line}
- **Expected behavior**: {per design docs / test spec}
- **Approach**: {what you will do}
- **Failure category**: `{FC1 category}` / `{FC1 subcategory}`
- **Result**: {PASS or FAIL — error summary}
```

- Must not contradict `Root cause` / `Approach` (e.g., `Root cause` says "the test does not pass" while `Failure category: compile_error` is inconsistent)
- `failure_category` is determined at the time the attempt begins to be written (as part of the cause investigation). It is not allowed to add it after the fact once `Result` is decided
- If the **primary category** is consecutive with a previous attempt, it becomes a candidate for DIVERGENT under FC5

## FC5: DIVERGENT Trigger Condition

The threshold judgment in DR6 of `diagnostic-reasoning.md` is performed using `failure_category` (**primary category only**; subcategories are ignored).

- Within the same phase (`## GREEN Phase` / `## Quality Checks` / `## Rework Cycle`), if the same `failure_category` is recorded as `Result: FAIL` **2 consecutive times** in the most recent attempts, the next attempt runs in DR6 DIVERGENT mode
- Even if `failure_subcategory` differs, the count applies as long as the primary category is the same (e.g., `test_failure / assertion_failure` -> `test_failure / panic` is treated as the "same mechanism")
- If the primary category changes, the counter is reset (e.g., `compile_error` -> `test_failure`)
- The counter is also reset across phases (test_failure in GREEN Phase and test_failure in Quality Checks are counted separately)

## FC6: Prohibited Patterns

The following are prohibited because they undermine the reliability of classification. When review-worker detects these during finding review, they serve as grounds for sending the work back via rework.

1. **Repeated use of `unknown`**: `unknown` must not be reused on a second or later attempt. It must always be reduced to a concrete classification
2. **Missing `failure_category`**: When `failure_category` is omitted in a retry, send-back, or `attempt-result` task-log event, the orchestrator records `(not reported)` and emits a warning log. The next attempt must include it
3. **Listing multiple categories**: One category per attempt. If the failure really is composite, choose **the most essential cause** (the one that serves as the starting point for the fix)
4. **Contradiction between severity and category**: In review-worker findings, severities that contradict the FC3 correspondence table must not be assigned (e.g., assigning `Critical` to `quality_check_failure / format_violation`)
5. **Inconsistency between `Approach` and `failure_category`**: The failure that `Approach` is trying to resolve and `failure_category` must point to the same root cause. Do not record the category of the side that is not being fixed
