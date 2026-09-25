---
name: spec-request-spec
description: "Phase 0 of the v2 spec workflow: create the request specification (RQ-N requests, task_type, out of scope) for a new spec, on its own spec/<name> branch. Starts steering first when steering is not approved. Triggers on: 'new spec', 'start spec workflow', 'request spec', '新しい spec', '要求仕様を作る'."
---

# Request Specification (Phase 0)

## 1. Preconditions

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-state.sh steering`. If any steering document is not `approved`, run `/steering-doc` first and stop here. The approval server also refuses the request-spec request until steering is approved.
2. Choose the spec name: kebab-case, unique under `.spec-workflow/specs/`.
3. Create the spec branch from the current default branch: `git switch -c spec/<name>`. All documents and all implementation commits of this spec live on this branch.

## 2. Classify

Agree the `task_type` with the user (AskUserQuestion):

| task_type | Use when | Evidence collected in Phase 0.5 |
|---|---|---|
| feature-add | new API / screen / command in existing code | code, contract |
| feature-modify | changing behaviour of existing code | code, contract, tests |
| bugfix | fixing a defect | code, tests, regressions |
| refactor | no behaviour change | code, tests |
| legacy-migration | porting legacy code | code, contract, tests |
| greenfield | no code yet | lib (external library contracts) |
| legacy | evidence collection is not worth it (give `legacy_reason`) | none |

## 3. Grill

Settle the requests with the user by following `${CLAUDE_PLUGIN_ROOT}/rules/grilling.md` (read it first). Start the tree from the user's description and the task_type. It covers:

- who needs what, and what problem each request solves
- the observable outcome that shows each request is met
- the boundary of each request and what is out of scope

## 4. Write

Launch `spec-workflow-mcp:spec-author` with:

- `DOC: request-spec`, `MODE: create`
- the user's description of what they want
- the task_type
- `DECISIONS`: the list the user confirmed in §3

The request-spec owns only the requests (`RQ-N`) and the out-of-scope list. The technology and the runtime belong to steering tech.md and design, not here.

## 5. Review and approve

1. Run `/spec-review` with `DOC: request-spec`.
2. Request approval: `approvals action:"request"`, with
   - `filePath: .spec-workflow/specs/<name>/request-spec.md`
   - `category: spec`
   - `categoryName: <name>`
   - `type: document`
3. Run `/check-approval <approvalId>`.

check-approval continues to `/spec-investigate`, or to `/spec-requirements` for `legacy`.
