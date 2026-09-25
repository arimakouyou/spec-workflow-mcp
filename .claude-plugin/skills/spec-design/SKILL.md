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

Then settle the skeleton with the user by following `${CLAUDE_PLUGIN_ROOT}/rules/grilling.md` (read it first). The skeleton's choices are the recommended answers. Build the tree in dependency order: a decision the layers depend on comes before the layers, and the layers come before the component split. The interview covers:

- each decision, with the alternatives it rejects
- the layers and the dependencies each layer may have
- the components in each phase
- any component that satisfies many acceptance criteria. A DES is one implementation task, so propose splitting it.

When the confirmed list changes the skeleton, launch `spec-author` again with `MODE: revise`, scope **skeleton** and `DECISIONS`: the confirmed list. Proceed to the detail only after the user confirms.

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
