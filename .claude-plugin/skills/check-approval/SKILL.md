---
name: check-approval
description: "Synchronously check the status of a pending approval request via the approvals MCP tool (no polling). Use when the user has been prompted to approve via the dashboard / VS Code extension and wants to resume the workflow after they approved. Triggers on: 'check approval', 'approval status', or programmatic invocation during spec workflow approval gates."
---

# Check Approval Status

Fetch the current status of a pending approval request in one shot. **No polling.** If the approval is still pending, instruct the user to approve via the dashboard / VS Code extension and re-invoke this skill.

## Usage

```
/check-approval <approvalId> next:/spec-requirements
```

The `next:` parameter is optional. When provided, `check-approval` invokes the specified skill after a successful approval and cleanup. When omitted, it reports success and waits for the caller's next step.

## Process

### 1. Parse Parameters

Extract the following from the invocation:

- `<approvalId>` — the approval ID to check (required)
- `next:<skill-name>` — the skill to invoke after approval (optional). Format: `next:/skill-name`

### 2. Fetch Approval Status (one-shot)

Call the `approvals` MCP tool with `action: 'status'`:

```
approvals action:"status" approvalId:"<approvalId>"
```

Read the returned `status` field. Possible values: `pending`, `approved`, `needs-revision`, `rejected`.

### 3. Handle Result

Branch on the `status` field:

#### `pending`

The reviewer has not acted yet.

1. Report: "Approval is still pending. Please approve or reject via the dashboard / VS Code extension, then re-run `/check-approval <approvalId>`."
2. Do NOT block. Return control to the caller so the user can proceed out-of-band.
3. Do NOT auto-transition.

#### `approved`

1. Report: "Approval granted."
2. **Immediately run cleanup**: `approvals action:"delete" approvalId:"<approvalId>"`.
   - If delete fails: report the error and ask the user to retry. Do NOT proceed.
   - If delete succeeds: report "Cleanup complete."
3. **Auto-transition** (if `next:` parameter was provided):
   - Report: "Proceeding to next phase: `{skill-name}`"
   - Invoke the next skill via the Skill tool. For example, if the parameter was `next:/spec-requirements`, invoke the skill `spec-requirements`.
   - Do NOT wait for user input between cleanup and invoking the next skill.
4. **No auto-transition** (if `next:` was omitted):
   - Report: "Approval approved and cleaned up. Ready for next steps."

#### `needs-revision`

1. Report the reviewer's comments from the approval response.
2. Tell the user: "Revision requested. Please review the comments above."
3. Do NOT auto-transition. The calling skill should update the document, re-run self-review, request a NEW approval (obtaining a new `approvalId`), then run `/check-approval <newApprovalId>` again (include `next:` if auto-transition is needed).

#### `rejected`

1. Report the rejection reason.
2. Tell the user: "Approval was rejected. Please review the feedback."
3. Do NOT auto-transition. The calling skill should revise the document, request a NEW approval, then run `/check-approval <newApprovalId>` again.

## Why No Polling

Polling (the previous 60-minute Bash loop) was removed because:

- Spec approval is the designated **human-in-the-loop** gate. A long Bash block added no value over letting the user explicitly say "continue" after approving.
- Polling held a Bash process open, blocking other tool calls and inflating perceived latency.
- One-shot `action:"status"` achieves the same result with zero wait time and clearer control flow.

If you need the previous auto-resume behavior, re-invoke `/check-approval <approvalId>` after approving via the dashboard. The caller skill remains in the same logical step.

## Rules

- This skill only checks status and performs cleanup — it does not modify spec documents.
- Verbal approval is NEVER accepted — only dashboard / VS Code extension approval counts.
- `approvals action:'delete'` must succeed before the workflow can proceed.
- If `delete` fails, do not proceed — ask the user to retry.
- The `next:` parameter triggers auto-transition ONLY on the `approved` path — never on `pending`, `needs-revision`, or `rejected`.
