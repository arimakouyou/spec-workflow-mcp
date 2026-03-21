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

**Launching `/spec-implement` yourself is strictly prohibited.** All of the following count as "auto-launching" and are prohibited:
- When the user replies "yes", "go ahead", or "OK"
- When the user says "implement this task" (direct implementation without using the skill is also prohibited)

`/spec-implement` is triggered only when the user personally types one of the following from their keyboard:
- The `/spec-implement` command
- Skill trigger phrases such as "implement task X", "start coding", "work on task X"

## ⛔ No Code Implementation Outside the spec-implement Skill

If writing code based on any file under `.spec-workflow/specs/` (requirements.md / design.md / tasks.md), you must go through the `spec-implement` skill.

Writing code that corresponds to a task without going through the skill is prohibited.

## Required Actions After Reading spec-workflow Files

| File Read | What to Do Next |
|-----------|-----------------|
| `requirements.md` only | Guide the user to the `/spec-design` skill and stop |
| `requirements.md` + `design.md` only | Guide the user to the `/spec-tasks` skill and stop |
| `tasks.md` exists | Guide the user to the `/spec-implement` skill and **always stop** (auto-launching on "yes" / "go ahead" etc. is prohibited) |

## Why This Rule Is Necessary

The spec-implement skill enforces the following agent chain:
- `parallel-worker` → TDD implementation
- `unit-test-engineer` → test quality verification
- `review-worker` → review + commit

Direct implementation that skips this chain completely bypasses TDD quality assurance and is therefore absolutely not permitted.
