---
name: check-approval
description: "Check the status of a pending approval request. Designed to be called by /loop for automatic polling. Triggers on: 'check approval', 'poll approval status', or when called via /loop during spec workflow approval waiting."
---

# Check Approval Status

Check the status of a pending approval and take appropriate action based on the result. This skill is designed to be called repeatedly by `/loop` during the spec workflow.

## Usage

Called automatically by `/loop` during the approval workflow:
```
/loop 1m /check-approval <approvalId>
```

## Process

### 1. Check Status

Call the `approvals` MCP tool:
```
approvals action: 'status', approvalId: '<approvalId>'
```

### 2. Handle Result

#### If `pending`:
Report: "Approval still pending. Waiting for review on dashboard/VS Code extension..."
The loop will call this skill again at the next interval.

#### If `approved`:
1. Report: "Approval granted!"
2. **Immediately run cleanup**: `approvals action:"delete" approvalId:"<approvalId>"`
   - If delete fails: report error and retry on next loop iteration
   - If delete succeeds: report "Cleanup complete."
3. **Stop the loop** — tell the user: "Approval approved and cleaned up. Proceeding to next phase."
4. The calling skill's auto-transition will handle proceeding to the next phase.

#### If `needs-revision`:
1. **Stop the loop.**
2. Report the reviewer's comments from the approval response.
3. Tell the user: "Revision requested. Please review the comments above."
4. The calling skill should update the document based on review comments, re-run self-review, and submit a NEW approval request with a new `/loop`.

#### If `rejected`:
1. **Stop the loop.**
2. Report the rejection reason.
3. Tell the user: "Approval was rejected. Please review the feedback."

## Rules

- This skill only checks status and performs cleanup — it does not modify spec documents
- Verbal approval is NEVER accepted — only dashboard/VS Code extension approval counts
- The `approvals action:'delete'` must succeed before the workflow can proceed
- If delete fails, do not proceed — retry on the next loop iteration
