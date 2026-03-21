---
always_apply: true
---

# Design Conformance

Rules to prevent deviations from the approved design.md.

## Principle

**Do not change the approved design during the implementation phase.** The DB schema, API design, and data model defined in design.md are a "contract" for the implementation; implementers must not change them unilaterally.

## Prohibited Actions During Implementation

### DB Schema
- Do not add tables or columns not defined in design.md
- Do not change the type or constraints of already-defined columns
- Do not add or remove indexes without authorization
- **Implement FK ON DELETE behavior exactly as defined in design.md** (do not change or add CASCADE / RESTRICT / SET NULL without authorization)
- Follow design.md for NULL / NOT NULL definitions

### API
- Do not add endpoints not defined in design.md
- Do not change defined HTTP methods, paths, or status codes
- Do not add, remove, or change the type of request/response fields
- Do not change the format of error responses
- **Error codes**: Use only the error codes defined in the Error Handling section of design.md. If an undefined error case arises during implementation, handle it in the following order:
  1. Consider whether an error code already defined in design.md can serve as a substitute (e.g., if `Conflict` is undefined, substitute with `BadRequest("duplicate key")`)
  2. If substitution is not possible, escalate and confirm with the user

### Data Model
- Do not add fields to Model / DTO that are not defined in design.md
- Do not create mismatches between DTO and API definitions

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
1. **Suspend Phase 4**: Revert in-progress tasks (`[-]`) to `[ ]`
2. **Discard implementation code**: Undo code implemented and committed in Phase 4 using `git revert`
3. **Delete tasks.md**: Delete `.spec-workflow/specs/{spec-name}/tasks.md` (Phase 3 artifact)
4. **Fix design.md**: Return to Phase 2 and fix design.md
5. **Re-review**: Re-validate design.md with spec-review (check)
6. **Re-approval**: Obtain re-approval of design.md via the Approval Workflow
7. **Re-run Phase 3**: Re-create tasks.md with `/spec-tasks`
8. **Re-run Phase 4**: Restart implementation from the beginning with `/spec-implement`

**Note:** Phase Reset carries a high cost. To avoid this, conduct thorough design reviews in Phase 2 (DB Schema, API Design, Data Model, Error Handling).

## Verification in review-worker

When performing a code review, review-worker reads `design.md` and checks the following:

- Whether the implemented DB migrations match the schema definitions in design.md
- Whether the paths, methods, and request/response types of implemented endpoints match the API definitions in design.md
- Whether the fields of implemented Model / DTO match the data model definitions in design.md
- Whether there are any additions not defined in design.md
