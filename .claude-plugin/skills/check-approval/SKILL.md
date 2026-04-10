---
name: check-approval
description: "Check the status of a pending approval request. Designed to be called by /loop for automatic polling. Triggers on: 'check approval', 'poll approval status', or when called via /loop during spec workflow approval waiting."
---

# Check Approval Status

Check the status of a pending approval and take appropriate action based on the result. This skill is designed to be called repeatedly by `/loop` during the spec workflow.

## Usage

Called automatically by `/loop` during the approval workflow:
```
/loop 1m /check-approval <approvalId> next:/spec-requirements
```

The `next:` parameter is optional. When provided, check-approval will automatically invoke the specified skill after successful approval and cleanup. When omitted, check-approval will stop the loop and report success without auto-transitioning.

## Process

### 1. Parse Parameters

Extract the following from the invocation:
- `<approvalId>` — the approval ID to check (required)
- `next:<skill-name>` — the skill to invoke after approval (optional). Format: `next:/skill-name`

### 2. Check Status

Call the `approvals` MCP tool:
```
approvals action: 'status', approvalId: '<approvalId>'
```

### 3. Handle Result

#### If `pending`:
Report: "Approval still pending. Waiting for review on dashboard/VS Code extension..."
The loop will call this skill again at the next interval.

#### If `approved`:
1. Report: "Approval granted!"
2. **Immediately run cleanup**: `approvals action:"delete" approvalId:"<approvalId>"`
   - If delete fails: report error and retry on next loop iteration
   - If delete succeeds: report "Cleanup complete."
3. **Stop the loop.**
4. **Auto-transition** (if `next:` parameter was provided):
   - Report: "Proceeding to next phase: `{skill-name}`"
   - Immediately invoke the next skill using the Skill tool. For example, if the parameter was `next:/spec-requirements`, invoke the skill `spec-requirements`.
   - **Do NOT wait for user input** between cleanup and invoking the next skill.
5. **No auto-transition** (if `next:` parameter was omitted):
   - Report: "Approval approved and cleaned up. Ready for next steps."

#### If `needs-revision`:
1. **Stop the loop.**
2. Report the reviewer's comments from the approval response.
3. Tell the user: "Revision requested. Please review the comments above."
4. Do NOT auto-transition — the calling skill should update the document based on review comments, re-run self-review, and submit a NEW approval request with a new `/loop`.

#### If `rejected`:
1. **Stop the loop.**
2. Report the rejection reason.
3. Tell the user: "Approval was rejected. Please review the feedback."

## Rules

- This skill only checks status and performs cleanup — it does not modify spec documents
- Verbal approval is NEVER accepted — only dashboard/VS Code extension approval counts
- The `approvals action:'delete'` must succeed before the workflow can proceed
- If delete fails, do not proceed — retry on the next loop iteration
- The `next:` parameter triggers auto-transition ONLY on the `approved` path — never on `needs-revision` or `rejected`
