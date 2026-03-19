---
name: spec-impl-review
description: "TDD REFACTOR phase for spec-implement workflow. Reviews and refactors both test and production code for quality. Designed to run as a subagent — spawn it with the Agent tool. Triggers on: subagent calls from spec-implement orchestrator only."
---

# Code Reviewer — REFACTOR Phase (Subagent)

This skill is designed to run as a **subagent** via the Agent tool. It reviews and refactors both test and production code, following TDD's REFACTOR phase.

## How the Calling Agent Should Invoke This

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "REFACTOR: Review and clean up",
  prompt: `You are a TDD refactoring reviewer. Review and refactor the code written in the RED-GREEN phases.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Task prompt: {task _Prompt content}
    Test files: {test-file-paths}
    Implementation files: {implementation-file-paths}
    Success criteria: {success criteria from _Prompt}

    Follow the /spec-impl-review skill instructions.

    Return the list of changes made and quality assessment.`
})
```

## REFACTOR Phase Rules

1. **Do NOT change test expectations** — assertions and expected values must stay the same
2. **Do NOT add new features** — refactoring changes structure, not behavior
3. **Tests must still pass after every change** — refactor in small, safe steps
4. **Improve clarity and maintainability** — the goal is clean, readable code

## Execution Steps

### 1. Read All Code

Read both the test files and implementation files to understand:
- The full picture of what was built
- How tests and production code relate
- Current code quality and structure

### 2. Check Success Criteria

Verify against the task's `_Prompt` Success criteria:
- Are all success criteria addressed by the implementation?
- Are there any gaps between what was asked and what was built?
- Flag any unmet criteria (but do NOT add untested features to fix them)

### 3. Apply Design Principles

Reference `/tdd-skills` and `tdd-skills/references/tdd-and-design.md` for design guidance:

**Production Code Refactoring:**
- **Duplication**: Extract shared logic into helper functions
- **Naming**: Improve variable, function, and class names for clarity
- **Responsibility**: Split functions/classes that do too much (SRP)
- **Error handling**: Ensure consistent and appropriate error handling
- **Type safety**: Tighten types, remove `any` where possible
- **Code organization**: Improve imports, ordering, grouping

**Test Code Refactoring:**
- **Readability**: Improve test names, add describe blocks for grouping
- **DRY setup**: Extract repeated setup into `beforeEach` / fixtures
- **Assertion clarity**: Use more specific matchers where available
- **Test independence**: Ensure no shared mutable state between tests

### 4. Perform Refactoring

Make changes in small, incremental steps. For each change:
- It should be a clear improvement in code quality
- It must not change observable behavior
- It must not change test expectations or add new assertions

### 5. Assess Quality

Evaluate the final code on:
- **Correctness**: Does it meet the task requirements?
- **Readability**: Is the code easy to understand?
- **Maintainability**: Is it easy to modify in the future?
- **Test coverage**: Do tests adequately cover the behavior?
- **Consistency**: Does it follow existing codebase patterns?

## Output Format

Return to the calling agent:

```
## REFACTOR Phase Complete

### Refactoring Changes
- {file}: {what was changed and why}
- ...

### Quality Assessment
- Correctness: {PASS/CONCERN} — {details}
- Readability: {GOOD/FAIR/POOR} — {details}
- Maintainability: {GOOD/FAIR/POOR} — {details}
- Test coverage: {GOOD/FAIR/POOR} — {details}
- Consistency: {GOOD/FAIR/POOR} — {details}

### Success Criteria Check
- [ ] {criterion 1}: {met/unmet}
- [ ] {criterion 2}: {met/unmet}

### Concerns (if any)
- {any issues that need attention}

### Result: {CLEAN / NEEDS_ATTENTION}
```
