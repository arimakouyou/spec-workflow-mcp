---
name: spec-status
description: "Show where a spec stands: document states from the approval ledger (pending / unapproved / modified / stale / approved), task progress per phase from commit trailers, the next task, open refactor backlog rows and uncovered acceptance criteria. Read-only. Triggers on: '/spec-status', 'spec status', '仕様の進捗', 'どこまで進んだ'."
---

# Spec status

Read-only. Run these scripts and report the results compactly, one section each.

1. **Documents**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-state.sh <spec>`, and `spec-state.sh steering`. For each document that is not `approved`, say what to do:

   | State | Next |
   |---|---|
   | pending | approve it in the dashboard, then `/check-approval` |
   | modified / stale | revise and re-approve it (`/spec-change` or the phase skill) |
   | unapproved | run its phase skill |

2. **Tasks**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-plan.sh <spec> --tsv`. Count done / total per phase. Name the first open task, or run `spec-next.sh <spec>`.
3. **Implementation session**:
   - Does `.spec-workflow/.active` exist?
   - Does `.spec-workflow/.resume` exist? Report its reason and time.
   - List the tasks with records in `runs/` but no completion commit.
4. **Refactor backlog**: the `open` rows of `.spec-workflow/specs/<spec>/refactor-backlog.md`.
5. **Traceability**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-trace.sh <spec>`. Show only the rows with `-`. `spec-lint.sh` reports each of them as L11.

Do not edit anything.
