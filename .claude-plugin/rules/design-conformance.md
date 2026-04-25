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

- Whether the implemented DB migrations match the schema definitions in design.md
- Whether the paths, methods, and request/response types of implemented endpoints match the API definitions in design.md
- Whether the fields of implemented Model / DTO match the data model definitions in design.md
- Whether there are any additions not defined in design.md

## Early Detection via Hook (PostToolUse)

`.claude-plugin/hooks/design-conformance-check.sh` がコード or migration 編集時に
軽量チェックを実行し、design.md との乖離を早期検出する:

- **DC1**: migration ファイルの `CREATE TABLE` / `ALTER TABLE` が design.md に未記載なら warning
- **DC2**: axum / ASP.NET Core / Express のルート定義 (`/path`) が design.md に未記載なら warning
- **DC3**: 簡易 grep ベースのため false positive あり、最終判断は review-worker (カテゴリ F) で

本 hook は **warning のみ** で実装をブロックしない。乖離検知時は以下のいずれかで対応:

- design.md に既存定義から代替できないか確認 (上記 "Prohibited Actions During Implementation" 参照)
- 代替不可なら **Phase Reset** または review-worker の `review_action: escalate`
- table 別名 / route prefix 違いなど検出漏れの場合は無視可
