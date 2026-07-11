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
  model: "opus",
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

### 0. Load Project-Level Context (Steering) — **Authoritative Validator**

> **Responsibility split**: `spec-impl-code` and `spec-impl-test-write` read steering as *guidance* while writing code — they consult File Placement Rules (P4-01) and the approved dependency list, but they are **not** expected to perform a full steering audit. **This REFACTOR phase is the authoritative steering validator** for the implementation: impl-code / impl-test-write catch violations opportunistically, but impl-review is the last line of defense and must flag anything they missed.

Before reviewing, load project-level instance information from steering documents **if they exist**:

- `{project-path}/.spec-workflow/steering/tech.md` — approved external dependencies, technical constraints, ADR summary. Use this as the source of truth when checking whether the implementation introduced any unapproved dependency or diverged from recorded architectural decisions.
- `{project-path}/.spec-workflow/steering/structure.md` — **File Placement Rules (P4-01)** and any Project-Specific Conventions. Use this to verify that new files were placed and named according to project rules.
- `{project-path}/.spec-workflow/steering/product.md` — product principles / non-goals (used to flag scope creep).

Skip any file that does not exist. If steering is absent, record `steering: absent — full consistency check skipped` in the quality assessment output and rely on `${CLAUDE_PLUGIN_ROOT}/rules/` project-wide policies alone.

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
- **Steering Alignment** (only if steering docs exist):
  - **File placement**: Are new source and test files placed per `structure.md` File Placement Rules (P4-01)? Flag any file placed outside the rule-mandated directory.
  - **Approved dependencies**: Does every newly imported third-party dependency appear in `tech.md` "External Dependencies (Approved)"? Flag additions that do not.
  - **ADR conformance**: Does the implementation contradict any Accepted ADR summarized in `tech.md`? Flag any such divergence.
  - **Product scope**: Does the change stay within product scope (not quietly implementing a Non-Goal from `product.md`)?

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
- Steering alignment: {PASS/CONCERN/N/A} — {details; N/A if no steering docs exist}

### Success Criteria Check
- [ ] {criterion 1}: {met/unmet}
- [ ] {criterion 2}: {met/unmet}

### Concerns (if any)
- {any issues that need attention}

### Result: {CLEAN / NEEDS_ATTENTION}
```
