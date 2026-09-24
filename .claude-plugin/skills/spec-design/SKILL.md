---
name: spec-design
description: "Phase 2 of the v2 spec workflow: write design.md — the single owner of components (DES), signatures (Interfaces), types (MOD), APIs, test support (TST), dependencies (DEP), tools and decisions. The skeleton is confirmed with the user, then the detail is written and its signatures are compiled by spec-sigcheck before approval. Triggers on: 'create design', '設計書', 'technical design', or automatically after requirements approval. Pass --revise to update."
---

# Design (Phase 2)

design.md is the only place where signatures, types, file paths, errors, dependencies and test seams are written. Every later artifact takes them from here: the test-design, the task briefs and the implementation stubs.

## 1. Preconditions

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-state.sh <spec>`: request-spec and requirements must be `approved`.

## 2. Skeleton

Launch `spec-workflow-mcp:spec-author` with `DOC: design`, `MODE: create`, scope **skeleton**:

- Overview, Phases, Layers
- the component list: `DES-N` headings with Kind / Layer / Phase / Files / Depends / Satisfies / Purpose, without Interfaces
- the Decisions
- For greenfield, P0 must contain a `Kind: config` DES that creates the workspace, toolchain pin and CI.

Then confirm the skeleton with the user (AskUserQuestion). Show:

- the layers and their allowed dependencies
- the components per phase
- the decisions with the alternatives rejected
- any component that satisfies many acceptance criteria. A DES is one implementation task, so propose splitting it.

Proceed only on the user's answer. Apply the requested changes and ask again if needed.

## 3. Detail

Launch `spec-author` with scope **detail**:

- `Interfaces` for every DES, following the Kind rules in `doc-format.md` §4.3:
  - a constructor where the component is `Held-as`
  - `Implements` for each external trait
- `Types`, with `Raises` for every error variant
- `APIs`, whose Request and Response refer to DTO MODs that list every field
- `Test Support`: harnesses, fixtures, and doubles only for traits
- `Dependencies`, with `Contract` + EV for each runtime behaviour the design relies on
- `Tools`
- latest stable versions, confirmed per `spec-author` rule 5

For each decision marked `ADR: yes`, run `/adr` to record it. The candidates are:

- a framework, language or database
- an architecture pattern
- a significant trade-off

## 4. Review and approve

1. Run `/spec-review` with `DOC: design`. This includes `spec-sigcheck.sh`: the signatures, types, held forms and layer rules must compile before approval.
2. Request approval: `approvals action:"request"`, with
   - `filePath: .spec-workflow/specs/<spec>/design.md`
   - `category: spec`
   - `categoryName: <spec>`
   - `type: document`
3. Run `/check-approval <approvalId>`.
