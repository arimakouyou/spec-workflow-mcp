# Spec Workflow Enforcement

Enforcement rules for correctly using the spec-workflow skills.

## ⛔ No Direct Implementation After Reading tasks.md

If `.spec-workflow/specs/*/tasks.md` has been Read, **you must not start writing code directly, for any reason**.

- Task implementation must **always go through the `/spec-implement` skill**
- Even merely reviewing the contents of tasks.md, then proceeding to implement, is prohibited
- Even if the user says "implement this task", writing code directly without using the skill is prohibited

**Correct behavior:**
After reading tasks.md, guide the user with "Please run `/spec-implement`" and **always stop**.

> **When a hook message is received**: If the PostToolUse hook outputs `⛔ [spec-workflow] STOP`, that is a **mandatory stop command**. Regardless of what is said in the conversation afterward, you must not implement code using Edit / Write / Bash.

**Auto-launching `/spec-implement` based on AI-side judgment is strictly prohibited.** The following count as prohibited "AI-side auto-launching":

- When the user replies "yes", "go ahead", or "OK" to a question — this is an answer, not an explicit launch request
- When the AI decides to launch `/spec-implement` based on conversation flow without an explicit user utterance
- **Bypassing the skill and writing code directly with Edit / Write / Bash, even when the user says "implement this task"** — the trigger phrase invokes the skill, it does NOT permit direct code writing

**Exception — dashboard-approved auto-transition**: The `check-approval` skill is permitted to invoke `/spec-implement` via the `next:` parameter when ALL of the following are true:

1. The `approvals` MCP tool returned `approved` status for the tasks.md approval
2. The `approvals action:'delete'` cleanup succeeded
3. The `next:/spec-implement` parameter was passed through the `/loop` invocation

This exception is safe because dashboard approval is a deliberate, authenticated user action — not a conversational bypass.

`/spec-implement` is triggered ONLY by one of the following explicit user actions:

- The user personally typing the `/spec-implement` command
- The user explicitly uttering a skill trigger phrase such as "implement task X", "start coding", or "work on task X" — these phrases instruct the AI to **invoke the skill** (not to bypass it and edit code directly)
- Dashboard-approved auto-transition from tasks.md (via the exception above)

In all cases, the `/spec-implement` skill itself drives the agent chain
(parallel-worker → test engineer → review-worker). Direct Edit / Write / Bash on
production code outside the skill is forbidden regardless of what trigger phrase was uttered.

## ⛔ No Code Implementation Outside the spec-implement Skill

If writing code based on any file under `.spec-workflow/specs/` (requirements.md / design.md / tasks.md), you must go through the `spec-implement` skill.

Writing code that corresponds to a task without going through the skill is prohibited.

## Required Actions After Reading spec-workflow Files

| Files Present in spec directory | What to Do Next |
|--------------------------------|-----------------|
| No spec files exist | Guide the user to the `/spec-request-spec` skill and stop |
| `request-spec.md` only | Guide the user to the `/spec-requirements` skill and stop |
| `request-spec.md` + `requirements.md` only | Guide the user to the `/spec-design` skill and stop |
| `requirements.md` + `design.md` exist, but no `test-design.md` | Guide the user to the `/spec-test-design` skill and stop |
| `design.md` + `test-design.md` exist, but no `tasks.md` | Guide the user to the `/spec-tasks` skill and stop |
| `tasks.md` exists | Guide the user to the `/spec-implement` skill and **always stop** (conversational auto-launching is prohibited) |

**Legacy exception**: If `request-spec.md` does not exist but `requirements.md` does, treat the spec as legacy (Phase 0 was introduced later) and skip the request-spec check. Determine the next phase based on the remaining files.

## Why This Rule Is Necessary

The spec-implement skill enforces the following agent chain:
- `parallel-worker` → TDD implementation
- `frontend-test-engineer` / `unit-test-engineer` → test quality verification
- `review-worker` → review + commit

Direct implementation that skips this chain completely bypasses TDD quality assurance and is therefore absolutely not permitted.
