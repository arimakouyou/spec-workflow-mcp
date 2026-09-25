---
name: check-approval
description: "Check an approval request once (no polling) and, when approved, clean it up, commit the approved spec documents and move to the next phase according to the fixed transition table. Use after the user approved in the dashboard. Triggers on: 'check approval', 'approval status', '承認を確認', or '/check-approval <approvalId>'."
---

# Check Approval

```
/check-approval <approvalId>
```

The next step is decided by the transition table below, not by the caller.

## Procedure

1. Call the `approvals` MCP tool: `action: "status"`, `approvalId: <approvalId>`.
2. Branch on `status`:

| Status | Action |
|---|---|
| `pending` | Tell the user to approve or reject in the dashboard, then run `/check-approval <approvalId>` again. Stop. |
| `needs-revision` / `rejected` | Show the reviewer's comments and annotations. Run the phase skill of that document again in revise mode, passing the comments. It re-runs its review (spec-review, or steering-reviewer for steering) and requests a new approval. Stop. |
| `approved` | Continue with step 3. |

3. `approvals action:"delete" approvalId:<approvalId>`. If it fails, report the error and stop. If the document is listed in `.spec-workflow/specs/<spec>/.change-open` (or `.spec-workflow/steering/.change-open`), remove its line: the change is approved and the document is immutable again.
4. Record the approved documents in git: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-git.sh docs <spec>`. This commits only `.spec-workflow/specs/<spec>/` and `.spec-workflow/approvals/<spec>/`. For steering, use `steering` as the spec name.
5. Check the whole spec: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-state.sh <spec>`.
   - If any document is `stale` or `modified`, open the **first** one in dependency order with its phase skill in revise mode. Pass it the upstream diff (`.spec-workflow/approvals/<spec>/content/<old-sha>.md` vs the current upstream file) and the lint output. Stop here.
6. Transition by the document that was just approved:

| Approved | Next |
|---|---|
| steering (product / tech / structure) | when all three are approved: `/spec-request-spec` |
| request-spec | `/spec-investigate`. If `task_type: legacy`, go to `/spec-requirements` instead. |
| requirements | `/spec-design` |
| design | `/spec-test-design` |
| test-design | Generate tasks with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-plan.sh <spec>`, run `spec-git.sh docs <spec>` again, and report that the spec is ready for `/spec-implement <spec>`. |

Invoke the next skill directly, without waiting for user input. The user's approval in the dashboard is the consent to proceed.

## Rules

- Verbal approval is never accepted. Only the dashboard approval counts. The server records it in the approval ledger.
- Never poll. One status call per invocation.
- This skill does not edit spec documents.
