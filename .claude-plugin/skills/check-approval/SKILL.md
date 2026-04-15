---
name: check-approval
description: "Check the status of a pending approval request. Polls via Bash script with 60-minute timeout. Triggers on: 'check approval', 'poll approval status', or when called during spec workflow approval waiting."
---

# Check Approval Status

Poll the status of a pending approval and take appropriate action based on the result. This skill uses a Bash polling script that monitors the approval JSON file directly, with a 60-minute timeout.

## Usage

```
/check-approval <approvalId> next:/spec-requirements
```

The `next:` parameter is optional. When provided, check-approval will automatically invoke the specified skill after successful approval and cleanup. When omitted, check-approval will report success without auto-transitioning.

## Process

### 1. Parse Parameters

Extract the following from the invocation:
- `<approvalId>` — the approval ID to check (required)
- `next:<skill-name>` — the skill to invoke after approval (optional). Format: `next:/skill-name`

### 2. Run Polling Script

Execute the Bash polling script to wait for the approval status to change:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/poll-approval.sh" <approvalId> .spec-workflow --timeout 3600
```

The script polls the approval JSON file every 15 seconds and exits with:
- **Exit 0**: Status changed from `pending` (outputs JSON to stdout)
- **Exit 1**: Timeout reached (error to stderr)
- **Exit 2**: Error — missing file, invalid arguments, jq not installed, etc. (error to stderr)

### 3. Handle Result

Branch on the script's **exit code** first, then parse output:

#### Exit 0 — Status changed

Parse the JSON from **stdout** and act based on the `status` field:

**If `approved`:**
1. Report: "Approval granted!"
2. **Immediately run cleanup**: `approvals action:"delete" approvalId:"<approvalId>"`
   - If delete fails: report error and ask user to retry
   - If delete succeeds: report "Cleanup complete."
3. **Auto-transition** (if `next:` parameter was provided):
   - Report: "Proceeding to next phase: `{skill-name}`"
   - Immediately invoke the next skill using the Skill tool. For example, if the parameter was `next:/spec-requirements`, invoke the skill `spec-requirements`.
   - **Do NOT wait for user input** between cleanup and invoking the next skill.
4. **No auto-transition** (if `next:` parameter was omitted):
   - Report: "Approval approved and cleaned up. Ready for next steps."

**If `needs-revision`:**
1. Report the reviewer's comments from the approval response.
2. Tell the user: "Revision requested. Please review the comments above."
3. Do NOT auto-transition — the calling skill should update the document, re-run self-review, request a NEW approval (obtaining a new approvalId), then run `/check-approval <newApprovalId>` (include `next:` if auto-transition is needed).

**If `rejected`:**
1. Report the rejection reason.
2. Tell the user: "Approval was rejected. Please review the feedback."
3. Do NOT auto-transition — the calling skill should revise the document, request a NEW approval, then run `/check-approval <newApprovalId>`.

#### Exit 1 — Timeout

Stdout is empty. Read **stderr** for the timeout error.
1. Report: "Approval polling timed out after 60 minutes."
2. Tell the user they can re-run `/check-approval <approvalId>` to resume polling, or check the dashboard directly.

#### Exit 2 — Error

Stdout is empty. Read **stderr** for the specific error (e.g., approval file not found, jq not installed, invalid arguments).
1. Report the error details to the user.
2. Do NOT auto-transition — resolve the error before retrying.

## Rules

- This skill only checks status and performs cleanup — it does not modify spec documents
- Verbal approval is NEVER accepted — only dashboard/VS Code extension approval counts
- The `approvals action:'delete'` must succeed before the workflow can proceed
- If delete fails, do not proceed — ask user to retry
- The `next:` parameter triggers auto-transition ONLY on the `approved` path — never on `needs-revision` or `rejected`
