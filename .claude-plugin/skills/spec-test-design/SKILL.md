---
name: spec-test-design
description: "Phase 3 of the v2 spec workflow: write test-design.md — the single owner of test cases (UT/CT per component, IT per API, ST per feature, E2E per journey). Tests refer to design symbols by qualified reference and bind the target's parameters by name, so they cannot drift from the signatures. Triggers on: 'create test design', 'テスト設計', or automatically after design approval. Pass --revise to update."
---

# Test Design (Phase 3)

test-design.md is the only source of test cases. The implementation writes its RED tests from it, through the task brief. Read `${CLAUDE_PLUGIN_ROOT}/rules/test-taxonomy.md` for the layers and categories.

## 1. Preconditions

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-state.sh <spec>`: request-spec, requirements and design must be `approved`.

## 2. Write, one section per agent call (serially)

Launch `spec-workflow-mcp:spec-author` with `DOC: test-design`, once per scope, one Agent call per message:

| Order | Scope | Must cover (checked by lint L11) |
|---|---|---|
| 1 | `## Unit Tests`, `## Component Tests` | every DES of Kind logic / types (UT) and ui (CT); every `Raises` entry of a non-adapter function; Boundary and Negative cases |
| 2 | `## Integration Tests` | every API status in Response and Errors, including the `DEP` contract rejections; every `Raises` entry of an adapter handler |
| 3 | `## System Tests`, `## E2E Tests` | every REQ whose criteria span ui and adapter components (ST); every journey (E2E) |

Each agent writes only its sections. It uses qualified references (`` `MOD-N:Type::Variant` ``, `` `DES-N:fn` ``) and binds every Target parameter in `Given`.

When a test needs something design does not declare, spec-author reports it as `upstream_gap` instead of inventing it. Examples:

- a function to call
- a seam to replace
- a harness entry point
- an argument a later phase needs

Stop and run `/spec-change` on design.

## 3. Review and approve

1. Run `/spec-review` with `DOC: test-design`.
2. Request approval: `approvals action:"request"`, with
   - `filePath: .spec-workflow/specs/<spec>/test-design.md`
   - `category: spec`
   - `categoryName: <spec>`
   - `type: document`
3. Run `/check-approval <approvalId>`. After approval, check-approval generates `tasks.md` with `spec-plan.sh`.
