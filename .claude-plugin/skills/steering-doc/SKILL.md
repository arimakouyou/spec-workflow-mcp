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

When called with `STALE: <doc>` (from check-approval), or when spec-state reports a document `stale`, decide the mode and go to §5 for that document.

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

Steering is not reviewed with `/spec-review`. It is the project layer, not a spec, and its checks compare the three documents with each other. Review them together once all three are written. Launch at most one Agent per message.

1. **Lint.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-lint.sh _steering <ROOT>`. If it reports violations, launch `spec-author` with `MODE: revise` and the violations, once per document they name, and re-run (at most 3 rounds).
2. **Review.** Launch `spec-workflow-mcp:steering-reviewer` with `MODE: decide | extract` (from §1) and `ROOT`.
3. **Fix loop** (at most 3 rounds). If the verdict is `fail`, launch `spec-author` with `MODE: revise` and the findings, once per document they name. Then re-run steps 1 and 2.
4. **Result.**
   - Still failing after 3 rounds → stop. Report the remaining findings to the user, one line each with document and heading. Do not request approval.
   - `spec-author` reported `open_decisions` → ask the user with AskUserQuestion and pass the answers as `DECISIONS` to the next revise.

Then, for each document written in this run:

1. Request approval: `approvals action:"request"`, with
   - `filePath: .spec-workflow/steering/<doc>.md`
   - `type: document`
   - `category: steering`
   - `categoryName: steering`
   - `title: steering <doc>`
2. Run `/check-approval <approvalId>`.

A revised document whose earlier request is still pending gets a new request. Tell the user to reject the older one in the dashboard: a pending request cannot be deleted, and approving it fails with `CONTENT_CHANGED`.

When all three are approved and none is `stale`, check-approval continues to `/spec-request-spec`.

## 5. Stale documents

The ledger records, for tech (upstream: product) and structure (upstream: product, tech), the upstream file's sha at approval. When an upstream file changes afterwards (a revision after rejection, or a `/steering-doc` revise), the downstream document becomes `stale` (`contract/approval-ledger-v1.md` §5). A stale document is re-checked, not rewritten by default:

1. Get the upstream diff: `.spec-workflow/approvals/steering/content/<recorded sha>.md` against the current upstream file. The recorded sha is `entries.<doc>.upstream.<upstream>` in `.spec-workflow/approvals/steering/ledger.json`.
2. Launch `spec-workflow-mcp:steering-reviewer` with `MODE`, `ROOT`, `STALE: <doc>` and the diff.
3. No finding names `<doc>` → request approval of `<doc>` unchanged (§4 approval steps). Approving it records the new upstream sha and clears `stale`.
4. Findings name `<doc>` → launch `spec-author` with `MODE: revise` and those findings only, then run the §4 review loop and request approval.
