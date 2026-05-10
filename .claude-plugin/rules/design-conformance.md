---
always_apply: true
---

# Design Conformance

Rules to prevent deviations from the approved design.md.

## Principle

**Do not change the approved design during the implementation phase.** The DB schema, API design, and data model defined in design.md are a "contract" for the implementation; implementers must not change them unilaterally.

## Prohibited Actions During Implementation

### DC1: DB Schema
- Do not add tables or columns not defined in design.md
- Do not change the type or constraints of already-defined columns
- Do not add or remove indexes without authorization
- **Implement FK ON DELETE behavior exactly as defined in design.md** (do not change or add CASCADE / RESTRICT / SET NULL without authorization)
- Follow design.md for NULL / NOT NULL definitions

### DC2: API
- Do not add endpoints not defined in design.md
- Do not change defined HTTP methods, paths, or status codes
- Do not add, remove, or change the type of request/response fields
- Do not change the format of error responses
- **Error codes**: Use only the error codes defined in the Error Handling section of design.md. If an undefined error case arises during implementation, handle it in the following order:
  1. Consider whether an error code already defined in design.md can serve as a substitute (e.g., if `Conflict` is undefined, substitute with `BadRequest("duplicate key")`)
  2. If substitution is not possible, escalate and confirm with the user

### DC3: Data Model
- Do not add fields to Model / DTO that are not defined in design.md
- Do not create mismatches between DTO and API definitions

### DC4: Module Boundaries

**Severity: Critical** — violations of this rule require `review_action: escalate` and user-authorized resolution (Path A or Path B). The `## Module Boundaries` section of design.md (Layer Definitions table + Dependency direction rules + Cross-cutting concerns + Shared type definitions) is a contract; implementers must not change layer assignments or dependency directions unilaterally.

**What counts as conformance** (do NOT flag as a violation):

- A file placed under any `Directory` listed in the Layer Definitions table is **conforming** — adherence is judged by **Layer Directory prefix**, not by exact path match against individual cells in design.md
- A `src/<facade>.rs` file paired with `src/<layer>/<facade>.rs` when the design.md cell uses `Re-exports X from Y` / `re-exported from` / `facade` notation: **both files are expected**, neither is a violation
- A struct/trait/class moved within the same Layer Directory tree (e.g., `src/infra/foo.rs` → `src/infra/foo/mod.rs`) when the Layer membership is preserved

**What counts as a violation** (escalate as Critical):

- (a) An implementation file placed in a Directory that maps to **no Layer** in the Layer Definitions table
- (b) Code that violates the **Dependency direction rules** table (e.g., `infra` importing from `service`, `domain` importing from `infra`) — verifiable mechanically via `/generate-arch-tests`
- (c) A struct/trait/class declared in design.md as belonging to Layer X (via `### DES-N: Name` reference under Layer X's Module Boundaries row) but actually implemented in Layer Y. Even when the implementer reasons the deviation is "infeasible to fix" (e.g., trait dependency direction), this MUST be escalated — only the user may authorize a design change
- (d) Duplicate implementations of the same symbol across Layers (e.g., `pub struct PathResolver` in both `domain/` and `infra/`) — typically indicates an incomplete migration and warrants escalation

**Mechanical detection priority**:

1. If `tests/architecture.rs` (or equivalent arch-test from `/generate-arch-tests`) exists, its PASS/FAIL is the **authoritative** signal for dependency-direction adherence (violation type `b`)
2. The PostToolUse hook `module-boundary-check.sh` emits Layer-prefix and facade-pair hints; reviewers and implementers should consult `<module_boundary_hints>` blocks before performing manual comparison
3. Manual grep-based path comparison is **secondary**; do not flag based on path string mismatch alone if the file is under a Layer Directory or matches a facade pair pattern

**Reviewer obligation (anti-ratification)**: when a violation is detected, the reviewer MUST `review_action: escalate` even if a workaround or rationale exists. Recording the rationale in the review summary while letting the deviation pass constitutes unilateral acceptance of a design change, which is prohibited by the Principle.

## When a Design Change Is Needed

If a design problem is discovered during implementation:

1. Stop the implementation
2. Clearly describe the problem and the proposed change
3. Escalate to the user (review-worker's `review_action: escalate`)

Based on the user's judgment, proceed with one of the following:

**Decision criteria (guidance for choosing A vs B):**

| Indicator | A (Implementation Adjustment) | B (Phase Reset) |
|-----------|-------------------------------|-----------------|
| Scope of change | Only the implementation approach of a single task | The DB schema / API spec / data model definitions themselves |
| Impact on existing implementation | Does not affect other completed tasks | Requires rewriting code for other tasks |
| Change to design.md | Not required (only appending to Restrictions) | Required |
| Typical example | Misinterpretation of DTO field usage, change to an existing component in use | Table definition change, addition/removal of response types, FK spec change |

### A. Adjust Implementation Within the Scope of design.md (Minor Cases)

- Append the adjustment details to the Restrictions in `_Prompt`, and return to parallel-worker via rework
- Do not change design.md

### B. design.md Change Required (Fundamental Problems) — Phase Reset

**If design.md must be changed, discard all implementation so far and restart from Phase 2.** Partial fixes are not permitted.

Phase Reset procedure:
1. **Suspend Phase 5**: Revert in-progress tasks (`[-]`) to `[ ]`
2. **Discard implementation code**: Undo code implemented and committed in Phase 5 using `git revert`
3. **Delete tasks.md**: Delete `.spec-workflow/specs/{spec-name}/tasks.md` (Phase 4 artifact)
4. **Fix design.md**: Return to Phase 2 and fix design.md
5. **Re-review**: Re-validate design.md with spec-review (check)
6. **Re-approval**: Obtain re-approval of design.md via the Approval Workflow
7. **Re-run Phase 3-4**: Re-create test-design.md with `/spec-test-design`, then tasks.md with `/spec-tasks`
8. **Re-run Phase 5**: Restart implementation from the beginning with `/spec-implement`

**Note:** Phase Reset carries a high cost. To avoid this, conduct thorough design reviews in Phase 2 (DB Schema, API Design, Data Model, Error Handling).

## Verification in review-worker

When performing a code review, review-worker reads `design.md` and checks the following:

- Whether the implemented DB migrations match the schema definitions in design.md (DC1)
- Whether the paths, methods, and request/response types of implemented endpoints match the API definitions in design.md (DC2)
- Whether the fields of implemented Model / DTO match the data model definitions in design.md (DC3)
- Whether the implementation conforms to the `## Module Boundaries` Layer Directory contract and Dependency direction rules (DC4) — adherence judged by Layer prefix, with facade pair annotations recognized; arch-test artifacts treated as the authoritative mechanical signal
- Whether there are any additions not defined in design.md

## Early Detection via Hook (PostToolUse)

When code or migration files are edited, two PostToolUse hooks run lightweight checks to detect divergence from design.md early:

`.claude-plugin/hooks/design-conformance-check.sh` (DC1 / DC2 / DC3):

- **DC1**: Warn if `CREATE TABLE` / `ALTER TABLE` in a migration file is not described in design.md
- **DC2**: Warn if an axum / ASP.NET Core / Express route definition (`/path`) is not described in design.md
- **DC3**: Because this is a simple grep-based check, false positives occur; the final judgment is made by review-worker (category F)

`.claude-plugin/hooks/module-boundary-check.sh` (DC4):

- Parses the `## Module Boundaries` section of design.md and extracts Layer / Directory rows
- Emits a `<module_boundary_hints>` block containing: (1) which Layer the edited file belongs to (Layer Directory prefix match), (2) facade-pair adherence reminders when the edited file is a `Re-exports X from Y` / `re-exported from` / `facade` cell. This hint suppresses false positives where a reviewer might flag a Layer-conforming file as a path-string deviation
- Language-agnostic for the markdown parsing and Layer prefix logic; supports the same source extensions as `design-conformance-check.sh`

Both hooks **only emit hints** and do not block implementation. When divergence is detected, respond in one of the following ways:

- Check whether an existing definition in design.md can serve as a substitute (see "Prohibited Actions During Implementation" above)
- For DC4 violations, treat as **Critical** and `review_action: escalate` — do not silently accept on practical grounds
- If substitution is not possible, perform a **Phase Reset** or use review-worker's `review_action: escalate`
- Cases such as table aliases or route prefix mismatches that the check misses can be ignored; DC4 Layer-prefix matches are conformance and must not be flagged
