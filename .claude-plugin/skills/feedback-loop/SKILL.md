---
name: feedback-loop
description: |
  Feedback loop operations: distinguishing know-how from built-in memory (FL1),
  consulting the know-how INDEX at task start (FL2), recording know-how when
  user corrections or recurring feedback are detected (FL3), the promotion path
  from know-how to rule/ADR/tech-debt (FL4), periodic knowledge audits at Phase
  Review completion (FL5), and the analysis and harness-improvement cycle for
  agent failure patterns (reworkCount >= 2, review_action: escalate, etc.) (FL6).
  Reference this when starting a new task and you want to consult related
  know-how, when receiving a correction or a "remember this" instruction from
  the user, when the same feedback recurs two or more times, when judging
  know-how maturity or considering promotion to a rule/ADR/tech-debt, when
  auditing single-author concentration or implicit knowledge during Phase
  Review, and when analyzing agent failure patterns (rework, escalation) to
  improve the harness (rules, skills, agent definitions).
  Triggers on: 'feedback loop', 'know-how vs memory', 'capture feedback', 'promote know-how to rule', 'agent failure pattern', 'phase review knowledge audit', 'フィードバックループ', 'know-how 記録', 'ルール昇格', 'Agent 失敗パターン'.
allowed-tools: [Read, Edit, Write, Bash, Grep]
---

# Feedback Loop

## FL1: Distinguishing know-how from built-in memory

- **know-how** (`.claude/_docs/know-how/`): project-specific practical knowledge. Tracked under Git and shared with the team. Technical judgments, pitfalls, best practices.
- **built-in memory** (`~/.claude/projects/.../memory/`): personal preferences and working style. Not tracked in Git.

Decision criterion when in doubt: "Should other team members know this?" Yes → know-how / No → memory.

## FL2: Consulting know-how at task start

Before starting a task, check `.claude/_docs/know-how/INDEX.md` and Read the relevant
files if any related know-how exists.

Reference flow:

1. Review the domain list in INDEX.md
2. Identify domains matching the task's keywords (e.g., "testing", "migration", "cache")
3. Reflect the matching know-how's "checklist" and "counter-examples" into your implementation decisions

If INDEX.md is empty or no domain matches, you may skip this step.

## FL3: Detecting and recording feedback

When any of the following is detected, record know-how using the `/knowhow-capture` skill:

- The user says "remember this" or "from now on, ..." → Pattern A (immediate recording)
- The user corrects or rejects the AI's judgment → Pattern B (proposal-based)
- The same feedback has been received two or more times → Pattern B (proposal-based)

Follow the `/knowhow-capture` skill for the recording procedure, format, and rule promotion.

## FL4: Promotion Path

Mature know-how that goes beyond practical tips can be promoted to more formal artifacts:

| From | To | Condition | Skill |
|------|----|-----------|-------|
| know-how | `.claude-plugin/rules/` | Established convention that should be enforced | `/knowhow-capture` ("make it a rule") |
| know-how (domain: architecture) | `.claude/_docs/adr/` | Significant and irreversible architectural decision | `/adr` |
| know-how (domain: debugging/architecture) | `.claude/_docs/tech-debt/` | Structural/chronic problem, not a single tip | `/tech-debt add` |

- When promoting to an ADR, keep the know-how file as background context and reference it from the ADR.
- When promoting to tech-debt, keep the know-how file and reference the original know-how from the tech-debt entry summary.

## FL5: Periodic Knowledge Audit (P5-04)

Periodically identify implicit knowledge to eliminate "ask that one person" situations.

- **Timing**: at Phase Review completion, or manually via `/knowhow-capture --audit`
- **Targets**: files concentrated in a single author, undocumented domain logic, non-obvious configuration values
- **Output**: Knowledge Gap Report → know-how recording (Pattern A) or ADR creation
- **CI integration**: a knowledge concentration check can be added to `scheduled-quality.yml` (enable with `--with-scheduled`)

## FL6: Agent Failure Pattern Improvement Cycle (P9-05)

A continuous improvement cycle that systematically collects and analyzes agent failure patterns and feeds them back into the harness (rules, skills, agent definitions).

### Detecting Failure Signals

Detect the following signals as agent failure patterns:

| Signal source | Detection condition | Data location |
|-----------|---------|-----------|
| reworkCount | >= 2 (rework occurred two or more times for the same task) | `reviewProcess.reworkCount` in `/log-implementation` |
| review_action: escalate | review-worker decides user escalation is needed | review-worker completion report |
| FL3 same fix | Same fix occurs three or more times across sessions | Duplicate detection on know-how entries |

### Recording

Use `/knowhow-capture` to record failure patterns:

- **Domain**: `agent-improvement`
- **Pattern A** (immediate recording): when `review_action: escalate` occurs — a serious failure requiring user intervention
- **Pattern B** (proposal-based): when `reworkCount >= 2` or FL3 same-fix detection occurs — propose "Record as agent-improvement know-how?"
- **Required fields**: agent name, failure type, occurrence frequency, root cause hypothesis

### Periodic Analysis

Periodically analyze know-how in the agent-improvement domain in conjunction with the FL5 knowledge audit:

- **Timing**: at Phase Review completion, or manually via `/knowhow-capture --audit`
- **Process**: aggregate entries in the agent-improvement domain by failure type
- **Output**: Agent Improvement Report (agent name | failure pattern | frequency | recommended action)
- **Threshold**: three or more occurrences of the same pattern → improvement action required

### Harness Improvement Actions

Based on the analysis, improve the harness with the following actions:

| Failure pattern | Improvement target | Artifact |
|-------------|---------|----------------|
| Repeated rework in a specific category | Clarify the rule, add counter-examples | Edit a rule file under `.claude-plugin/rules/` |
| Agent misunderstands requirements | Strengthen instructions in skill/agent definitions | Edit .md under `.claude-plugin/agents/` or `skills/` |
| Quality checks miss the issue | Add or strengthen check items | Update `quality-checks.md` + promote enforcement-levels |
| Structural harness defect | Record as an architectural decision | Create an ADR via `/adr` (referencing the know-how entry) |

- For significant changes, create an ADR via `/adr` and reference the original agent-improvement know-how entry as context.
- For minor improvements (prompt tuning, threshold changes), update the status of the know-how entry itself to "applied".
