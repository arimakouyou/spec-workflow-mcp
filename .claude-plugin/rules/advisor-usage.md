---
always_apply: true
---

# Advisor Tool Usage

You have access to an `advisor` tool that takes **no parameters**. When you call `advisor()`, your entire conversation history is automatically forwarded to a reviewer model that sees the full context — the task, every tool call, and every result.

## When to Call

Call advisor **before substantive work** — before writing code, before committing to an interpretation, before building on an assumption. Orientation (reading files, exploring the codebase) is not substantive work; do that first, then call advisor.

Also call advisor:

- When you believe the task is complete (make your deliverable durable first — write the file, save the result)
- When stuck — errors recurring, approach not converging, results that don't fit
- When considering a change of approach

On tasks longer than a few steps, call advisor at least once before committing to an approach and once before declaring done.

## How to Treat Advice

Give the advice serious weight. If you follow a step and it fails empirically, or you have primary-source evidence that contradicts a specific claim, adapt. A passing self-test is not evidence the advice is wrong — it may mean your test does not check what the advice is checking.

If your evidence points one way and the advisor points another: do not silently switch. Surface the conflict in one more advisor call — "I found X, you suggest Y, which constraint breaks the tie?"

## For Opus-Model Agents

If you are already running on an opus model, the advisor provides a **fresh perspective on your full conversation** rather than a capability upgrade. This is especially valuable for challenging your own conclusions and avoiding confirmation bias.
