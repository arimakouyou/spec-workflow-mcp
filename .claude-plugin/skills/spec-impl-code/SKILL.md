---
name: spec-impl-code
description: "TDD GREEN phase for spec-implement workflow. Writes minimal production code to make failing tests pass. Designed to run as a subagent — spawn it with the Agent tool. Triggers on: subagent calls from spec-implement orchestrator only."
---

# Code Writer — GREEN Phase (Subagent)

This skill is designed to run as a **subagent** via the Agent tool. It writes the minimal production code needed to make failing tests pass, following TDD's GREEN phase.

## How the Calling Agent Should Invoke This

```javascript
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "GREEN: Implement to pass tests",
  prompt: `You are a TDD implementer. Write minimal code to make the failing tests pass.

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Task prompt: {task _Prompt content}
    Test files: {test-file-paths}
    Leverage files: {_Leverage file paths}
    Evidence files: {_Evidence EV IDs, resolved to full paths by the orchestrator}

    Follow the /spec-impl-code skill instructions.
    Read ONLY the listed evidence files — do not load other EV-*.md files.

    Return the list of files created/modified and implementation approach.`
})
```

## GREEN Phase Rules

1. **Make the tests pass** — that is the only goal
2. **Write minimal code** — just enough to satisfy the tests (YAGNI)
3. **Do NOT modify test files** — tests are the specification
4. **Do NOT add untested features** — if there's no test for it, don't build it

## Execution Steps

### 0. Load Project-Level Context (Steering)

Before reading the tests, load project-level instance information from steering documents **if they exist**:

- `{project-path}/.spec-workflow/steering/tech.md` — project-specific technology constraints (approved dependencies, required versions, external integrations, performance targets). Any new dependency introduced during GREEN must already be listed in the "External Dependencies (Approved)" table; if it is not, STOP and flag it to the caller rather than introducing it silently.
- `{project-path}/.spec-workflow/steering/structure.md` — **File Placement Rules (P4-01)**. Use this table to decide where new source files MUST be placed and how they MUST be named. Do not invent a placement if the rule exists.
- `{project-path}/.spec-workflow/steering/product.md` — product principles and non-goals (skip if absent; used only to resolve ambiguity).

**When steering docs are absent**: Skip the load step entirely. In Output Notes, record `steering: absent — pre-approval dependency check and file placement rule check skipped`. The caller (spec-implement orchestrator) will see this note and treat it as an expected legacy condition rather than a missed check. Do not block implementation on missing steering docs — steering docs are optional (see `steering-doc/SKILL.md`). General engineering policies (design principles, style, security) live in `.claude-plugin/rules/` and are already applied project-wide — do not re-read them here.

### 1. Read and Understand the Tests

- Read each test file to understand:
  - What modules/functions are imported (these need to be created)
  - What interfaces are expected (parameters, return types)
  - What behavior is verified (assertions define the contract)
  - What error conditions are tested

### 1.5 Load Evidence (Selective)

If the task carries an `_Evidence:` line (`.claude-plugin/rules/evidence-coverage.md` EC2) — resolved by the orchestrator to `.spec-workflow/specs/{spec-name}/evidence/{category}/EV-{category}-{NNN}.md` paths — read **only those files** before implementing.

- Evidence files capture the relevant existing-code context (current contracts, callers, branches) that informed this task's design. Loading them up-front avoids re-reading the codebase for behavior the spec already anchored.
- Do **not** read other EV files from the spec's `evidence/` directory — they are for other tasks. Loading them is wasteful and can introduce unrelated constraints.
- Do **not** fall back to crawling the codebase to rediscover behavior that evidence files already cite. If an evidence file cites `path:Lx-Ly`, open that exact range rather than scanning the whole file.
- If the task has no `_Evidence:` line (e.g. a Phase 0 setup task), skip this step.
- Legacy specs (no `task_type` in `request-spec.md`) will also have no `_Evidence:` lines. This is normal — skip.

### 2. Plan the Implementation

From the tests, derive:
- Which files need to be created
- What functions/classes/methods are needed
- What types/interfaces are expected
- What the input/output contracts are

### 3. Choose a Green Strategy

Follow `/tdd-skills` Green Strategies:

1. **Obvious Implementation** (preferred when solution is clear): Implement the real logic directly
2. **Fake It** (when uncertain): Return a constant first, then generalize
3. **Triangulation** (when multiple cases exist): Generalize from multiple test assertions

### 4. Implement

- Read `_Leverage` files to understand existing patterns and utilities
- Follow the codebase's existing conventions (naming, structure, error handling)
- Create new source files **at the target directory dictated by `structure.md` File Placement Rules (P4-01)**. If the rule table has no matching row for the file type, use the closest analog and note the assumption in Output Notes.
- Do not introduce any third-party dependency that is not listed in `tech.md` "External Dependencies (Approved)". If the test requires one that is missing, STOP and report it to the caller.
- Implement functions/classes with the expected signatures
- Handle all test cases including error scenarios

**Key constraint**: Write only what the tests demand. If a test doesn't check for input validation, don't add it. If a test doesn't verify logging, don't add it.

**Leptos Frontend Components:**
Leptos フロントエンドテストを満たすための実装:
- 抽出ロジック関数を **先に** 実装する（テストがインポートする対象）
- 次に `#[component]` 関数と `view!` マクロにロジックを配線する
- ロジック関数は `pub` または `pub(crate)` でテストからアクセス可能にする
- テスト通過後、`cargo leptos build` で WASM コンパイルを検証する

### 5. Verify Locally (Optional Quick Check)

If possible, do a quick mental check that:
- All imported modules now exist
- All expected exports are present
- Function signatures match what tests call
- Return types match what tests assert

## Output Format

Return to the calling agent:

```
## GREEN Phase Complete

### Files Created
- {path/to/new-file-1}: {brief description}
- {path/to/new-file-2}: {brief description}

### Files Modified
- {path/to/existing-file}: {what was changed}

### Implementation Approach
{1-3 sentences describing the approach taken and key decisions}

### Green Strategy Used
{Obvious Implementation / Fake It / Triangulation} — {reason}
```
