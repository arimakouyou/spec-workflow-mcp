---
name: spec-review
description: "The single checker for spec documents in the v2 workflow: deterministic lint (and sigcheck for design), then a read-only semantic review by spec-reviewer, fixed by spec-author, at most 3 rounds. Called by every spec phase skill before requesting approval. Triggers on: 'review spec', 'check spec document', '仕様書をレビュー', '仕様チェック'."
---

# Spec Review

Every spec document passes through this procedure before its approval request. The phase skills do not carry their own checklists: grammar is `rules/doc-format.md`, and the semantic checks are in the spec-reviewer agent.

## Inputs

`SPEC`, `DOC` (steering / request-spec / requirements / design / test-design), `ROOT`.

## Procedure

Run the steps in order. Launch at most one Agent per message: agents run serially, and each Agent call returns only after the agent has finished.

1. **Deterministic checks**
   - Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-lint.sh <SPEC> <ROOT>`. For steering documents use `_steering` as the spec name.
   - For design, also run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-sigcheck.sh <SPEC> <ROOT>`.
     - Exit 3 means a required tool is missing, or the language is undeclared. Stop and report it. Never skip it.
     - `unsupported (<reason>)` is reported as-is in the approval request.
2. **Fix loop for the deterministic checks** (at most 3 rounds). If step 1 reported violations:
   1. Launch `spec-workflow-mcp:spec-author` with `MODE: revise` and the violations.
   2. Re-run step 1.
3. **Semantic review.** Launch `spec-workflow-mcp:spec-reviewer` for the document.
4. **Fix loop for the semantic review** (at most 3 rounds). If the verdict is `fail`:
   1. Launch `spec-author` with `MODE: revise` and the findings.
   2. Re-run step 1.
   3. Re-run step 3.
5. **Result**
   - All clean → report `spec-review: pass` and return to the calling skill, which requests approval.
   - Still failing after 3 rounds → stop. Report the remaining findings to the user, one line each with IDs. Do not request approval.
   - `spec-author` reported an `upstream_gap` → stop. The upstream document must change first, so tell the user which document and IDs (`/spec-change`). Do not work around the gap in this document.
   - `spec-author` reported `open_decisions` → put them to the user as one round (`rules/grilling.md` §5) and pass the answers as `DECISIONS` to the next revise.

## Rules

- This skill never edits documents itself. Only spec-author writes.
- A document is never sent for approval with lint or sigcheck failures.
