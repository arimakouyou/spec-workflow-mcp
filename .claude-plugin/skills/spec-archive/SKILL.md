---
name: spec-archive
description: "Move a finished or abandoned spec from .spec-workflow/specs/<name>/ to .spec-workflow/archive/specs/<name>/ in one commit. Normally done by review-worker at the end of the FINAL task; use this skill for a spec abandoned outside an implementation session. Triggers on: '/spec-archive', 'archive spec', 'spec をアーカイブ'."
---

# Spec archive

1. Check the preconditions:
   - `.spec-workflow/.active` does not name this spec. Inside an implementation session only review-worker archives, at `FINAL`.
   - The working tree is clean.
2. If the spec is not finished (`spec-next.sh <spec>` does not exit 2), confirm with the user that it is abandoned.
3. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-git.sh archive <spec>`. It moves the directory and commits with the trailer `Spec-Archive: <spec>`.

The approval ledger under `.spec-workflow/approvals/<spec>/` stays where it is, as the record of what was approved.
