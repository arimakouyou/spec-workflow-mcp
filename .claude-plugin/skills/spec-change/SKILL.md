---
name: spec-change
description: "Change an approved spec document (at any time, including during implementation): record the change, open the most upstream document that is wrong, revise and re-approve it, re-derive the stale downstream documents, regenerate tasks and reopen exactly the tasks whose inputs changed. The only way to edit an approved document. Triggers on: '/spec-change', 'change the spec', 'design を直したい', '仕様を変更', or when review-worker escalates."
---

# Spec change

Approved documents are immutable. guard-edit refuses edits unless the document is `stale`, or listed in `.spec-workflow/specs/<spec>/.change-open`. This skill is how a document gets listed.

## 1. Decide what changes

1. Take the reason:
   - an escalation (`escalation.kind`, `ids`, `assessment`, `recommendation` from review-worker)
   - an `upstream_gap` from spec-author
   - or the user's request
2. Find the **most upstream** document that is wrong: requirements before design, and design before test-design.
   - Fix the cause, not the symptom. If test-design needs a function design lacks, the design changes.
   - If the change contradicts the request-spec or steering, ask the user first.
3. Confirm with the user (AskUserQuestion) when the change alters behaviour the user asked for. A change that only completes the design (a missing constructor, a missing error variant) needs no confirmation.

## 2. Record and open

1. Append a row to `.spec-workflow/specs/<spec>/changes.md`. Create it with the header `| CHG | Date | Documents | IDs | Reason |` if it does not exist. Number the rows `CHG-NNN`. State the reason in one line, with the IDs.
2. Open the document: `printf '%s\n' <doc> >> .spec-workflow/specs/<spec>/.change-open`.

## 3. Revise and re-approve

Run the document's phase skill (`/spec-requirements`, `/spec-design` or `/spec-test-design`) in revise mode with the change as input. It runs spec-author, then `/spec-review`, then the approval request, then `/check-approval`.

After the approval, check-approval does the following:

- removes the document from `.change-open`
- commits the documents
- finds the downstream documents that are now `stale` and revises them in dependency order through their phase skills

## 4. Bring the implementation in line

When `spec-state.sh <spec> --ready` succeeds again:

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-plan.sh <spec>`: regenerate tasks.md.
2. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-reopen.sh <spec>`: list the completed tasks whose inputs changed.
   - `reopen` rows: run the command again with `--apply` to reopen them.
   - `removed` rows: completed tasks whose component the change deleted. Their code must be removed. Tell the user which files, and add the removal to the design's next phase if it is not already covered.
3. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-git.sh docs <spec>`.
4. Resume with `/spec-implement <spec>`. The reopened tasks come first in plan order.

## Rules

- Do not edit a downstream document to hide an upstream defect.
- Never edit an approved document without `.change-open`. guard-edit enforces this.
