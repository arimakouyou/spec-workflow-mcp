---
name: spec-requirements
description: "Phase 1 of the v2 spec workflow: write requirements.md — REQ-N with EARS acceptance criteria REQ-N.M, non-functional requirements NFR-N and user journeys JRN-N — each traced to a request RQ-N. Triggers on: 'create requirements', '要件定義', or automatically after investigation / request-spec approval. Pass --revise to update after an upstream change or review comments."
---

# Requirements (Phase 1)

## 1. Preconditions

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-state.sh <spec>`: request-spec must be `approved`. Otherwise stop and name the document to fix first.

## 2. Grill

Settle the requirement decisions with the user by following `${CLAUDE_PLUGIN_ROOT}/rules/grilling.md` (read it first). Start the tree from the approved RQs. Take the facts from `evidence/`. The interview covers:

- for each RQ, the behaviour on the normal path
- the behaviour on errors, on boundary inputs and in unusual states
- each NFR number and the reason for it
- the cross-feature journeys and where each one starts and ends

## 3. Write

Launch `spec-workflow-mcp:spec-author` with:

- `DOC: requirements`
- `MODE: create`, or `revise` together with the upstream diff and review comments
- `DECISIONS`: the list the user confirmed in §2

It writes to these rules:

- Every REQ has a `Source` RQ. Every RQ is a Source of some REQ or listed under `## Out of Scope` with a reason.
- Every acceptance criterion is one EARS sentence with exactly one observable outcome. No "or".
- NFR criteria are measurable, and the rationale explains the number.
- Journeys (`JRN-N`) describe cross-feature user flows. They become the E2E tests.
- The evidence categories required by the task_type are cited.
- No test layers and no implementation terms. Test-design owns the layers and design owns the code.

## 4. Review and approve

1. Run `/spec-review` with `DOC: requirements`.
2. Request approval: `approvals action:"request"`, with
   - `filePath: .spec-workflow/specs/<spec>/requirements.md`
   - `category: spec`
   - `categoryName: <spec>`
   - `type: document`
3. Run `/check-approval <approvalId>`.
