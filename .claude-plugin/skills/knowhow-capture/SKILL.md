---
name: knowhow-capture
description: >
  A skill for accumulating user feedback, corrections, and instructions as know-how in `.claude/_docs/know-how/`.
  Provides step-by-step procedures for recording know-how (domain selection, duplicate check, file creation, INDEX update).
  Triggers when the user says "remember this", "do this from now on", "remember", or "add to know-how",
  or when the feedback-loop rule detects feedback and instructs a recording.
  Can also be explicitly invoked with /knowhow-capture.
---

# Know-how Capture

A skill for accumulating practical team knowledge gained through interactions with the user into `.claude/_docs/know-how/`,
so the same mistakes are not repeated in future tasks.

Personal preferences and working styles should be recorded in the built-in memory system, not here.

## Two Recording Patterns

### Pattern A: Explicit Recording (User-Directed)

When the user says "remember this", "add to know-how", or "do this from now on".
Record immediately without asking for confirmation.

**Trigger examples:**
- "Remember this"
- "Add this to know-how"
- "Do it this way from now on"
- "remember this"

**Behavior:** Immediately create the know-how file and update INDEX.md.

### Pattern B: Suggested Recording (Detection + Confirmation)

The AI detects a user correction or instruction and proposes "Shall I record this as know-how?".
Record only if the user approves.

**Trigger conditions:**
- The user clearly corrected the AI's output or judgment ("That's not right, it should be...", "No, it's...")
- The user rejected the AI's approach and directed a different method
- The user shared a project-specific convention or rule
- The same type of correction was received 2 or more times within the same session

**Behavior:**
1. Summarize the correction and present it
2. Ask "Shall I record this knowledge as know-how?"
3. Record if the user approves

**Suggestion format:**

```
[know-how suggestion] The following knowledge can be recorded:
- Summary: {one-line summary of the correction}
- Domain: {testing / workflow / conventions / ...}
Shall I add this to know-how?
```

## Step-by-Step Recording Procedure

### Step 1: Determine the Domain

Select a domain based on the content of the know-how.

| Domain | Content |
|--------|---------|
| testing | Knowledge about test design, structure, and execution |
| workflow | Knowledge about development flow, Git operations, CI/CD |
| conventions | Naming conventions, directory structure, code style |
| architecture | Layer structure, DI, design decisions |
| debugging | Debugging techniques, error handling, performance |

If the content does not fit an existing domain, a new domain may be created.

### Step 2: Duplicate Check

Read `.claude/_docs/know-how/INDEX.md` and confirm that the same know-how does not already exist.
If a duplicate exists, update the existing file rather than creating a new one.

### Step 3: Create the File

Create `.claude/_docs/know-how/{domain}/{slug}.md` using the following format:

```markdown
---
created: {YYYY-MM-DD}
domain: {domain}
source: user-feedback
---

# {Title (concise)}

## Summary

{Describe the core of the knowledge in 1-2 sentences}

## Background

{Why this knowledge is needed, and in what situation it arose}

## Checklist

- [ ] {Item to verify during implementation 1}
- [ ] {Item to verify during implementation 2}

## Counter-example

{What happens if this knowledge is ignored}
```

**Constraints:**
- Aim for 50 lines or fewer (consider splitting if longer)
- `created`, `domain`, and `source` fields in frontmatter are required

### Step 4: Update INDEX.md

Add one row to the relevant domain table in `.claude/_docs/know-how/INDEX.md`.
If the domain section does not exist, add a new section.

## Pattern Decision Flowchart

```
Detect user's statement
  │
  ├─ Explicit instruction like "remember this" or "remember"?
  │   └─ YES → Pattern A (record immediately)
  │
  ├─ Did the user correct or reject the AI's judgment?
  │   └─ YES → Pattern B (suggest and confirm)
  │
  ├─ Did the user share a project-specific convention?
  │   └─ YES → Pattern B (suggest and confirm)
  │
  └─ Same correction received 2 or more times?
      └─ YES → Pattern B (suggest and confirm)
```

## Notes

- **Distinction from memory**: "Should teammates also know this?" → Yes = know-how, No = built-in memory
- Do not write temporary state (current branch name, tasks in progress, etc.) to know-how
- Know-how is meant for "practical knowledge"; established rules should be promoted to `.claude/rules/`
- If the user says "make it a rule", promote the know-how to a rule in `.claude/rules/`
- Staging and committing files after creation should only be done when the user explicitly requests it
