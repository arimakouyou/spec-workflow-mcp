---
always_apply: true
---

# Feedback Loop

## Distinction from Built-in Memory

- **know-how** (`.claude/_docs/know-how/`): Project-specific practical knowledge. Managed under Git and shared with the team. Technical decisions, pitfalls, and best practices.
- **built-in memory** (`~/.claude/projects/.../memory/`): Personal preferences and working style. Not under Git management.

When in doubt, ask "Should team members know this?" Yes → know-how, No → memory.

## Referencing at Task Start

Before starting a task, check `.claude/_docs/know-how/INDEX.md`, and if there is relevant know-how, Read the corresponding file.

Reference flow:
1. Check the domain list in INDEX.md
2. Identify domains that match the task's keywords (e.g., "testing", "migration", "cache")
3. Reflect the relevant know-how's "checklists" and "counter-examples" in your implementation decisions

If INDEX.md is empty or no matching domain exists, you may skip this step.

## Detecting and Recording Feedback

When any of the following is detected, use the `/knowhow-capture` skill to record know-how:

- The user says something like "remember this" or "from next time, do ~" → Skill Pattern A (record immediately)
- The user corrects or negates an AI judgment → Skill Pattern B (proposal type)
- The same feedback has been received two or more times → Skill Pattern B (proposal type)

For recording procedures, format, and rule promotion, follow the `/knowhow-capture` skill.
