---
name: steering-doc
description: "Create or revise the project steering documents (product.md, tech.md, structure.md). Extracts them from existing code, or decides them with the user for a greenfield project. tech.md owns the project-wide technical facts every spec relies on (stack, test commands, test layout, wiring files, health path, sigcheck language). Triggers on: 'steering doc', 'ステアリングドキュメント', 'define tech stack', 'project structure', or automatically from /spec-request-spec when steering is not approved."
---

# Steering Documents

Steering is the gate before any spec. `spec-request-spec` refuses to start until all three documents are approved (see `contract/approval-ledger-v1.md` §2).

## 1. Mode

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-state.sh steering`. If all three are `approved` and the user did not ask for a change, report it and stop.

Decide the mode from the repository:

| Situation | Mode |
|---|---|
| A manifest (`Cargo.toml`, `*.csproj`, `package.json`, …) and source directories exist | **extract**: derive the facts from the code |
| No code yet | **decide**: agree on the facts with the user, as *planned* values that the P0 bootstrap of the first spec makes real |

## 2. Decide mode: agree on the facts

Ask the user with AskUserQuestion, one topic per question, offering concrete options:

1. Purpose, users and non-goals (product.md)
2. Language and framework. Check the latest stable versions via WebSearch / registry before offering them.
3. Test commands per layer (UT / CT / IT / ST / E2E; `-` for layers not used) and test file layout
4. Directory layout (structure.md)

Then derive the remaining tech.md values:

- **Wiring Files**: manifests and module-declaration files.
- **Health path**: the health check endpoint.
- **Sigcheck**: `rust`, `dotnet`, or `unsupported (<reason>)`.

## 3. Write

Launch `spec-workflow-mcp:spec-author` once per document (product → tech → structure), one Agent call per message. Pass it:

- `DOC: product | tech | structure`
- `MODE: create` or `revise`
- the agreed facts (decide mode), or the instruction to derive the facts from the code with citations (extract mode)

The templates are `${CLAUDE_PLUGIN_ROOT}/templates/docs/{product,tech,structure}.md`.

## 4. Review and approve

For each document:

1. Run `/spec-review` with `SPEC: _steering`, `DOC: steering`.
2. Request approval: `approvals action:"request"`, with
   - `filePath: .spec-workflow/steering/<doc>.md`
   - `type: document`
   - `category: steering`
   - `categoryName: steering`
   - `title: steering <doc>`
3. Run `/check-approval <approvalId>`.

When all three are approved, check-approval continues to `/spec-request-spec`.
