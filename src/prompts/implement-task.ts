import { Prompt, PromptMessage } from '@modelcontextprotocol/sdk/types.js';
import { PromptDefinition } from './types.js';
import { ToolContext } from '../types.js';

const prompt: Prompt = {
  name: 'implement-task',
  title: 'Implement Specification Task',
  description: 'Guide for implementing a specific task from the tasks.md document using TDD (Red-Green-Refactor). Provides comprehensive instructions for task execution including writing tests first, implementing minimal code, refactoring, and logging implementation details for the dashboard.',
  arguments: [
    {
      name: 'specName',
      description: 'Feature name in kebab-case for the task to implement',
      required: true
    },
    {
      name: 'taskId',
      description: 'Specific task ID to implement (e.g., "1", "2.1", "3")',
      required: false
    }
  ]
};

async function handler(args: Record<string, any>, context: ToolContext): Promise<PromptMessage[]> {
  const { specName, taskId } = args;

  if (!specName) {
    throw new Error('specName is a required argument');
  }

  const taskIdSlot = taskId ? `"${taskId}"` : '"<TASK_ID>"';

  const messages: PromptMessage[] = [
    {
      role: 'user',
      content: {
        type: 'text',
        text: `Implement ${taskId ? `task ${taskId}` : 'the next pending task'} for the "${specName}" feature using TDD (Red-Green-Refactor).

**Context:**
- Project: ${context.projectPath}
- Feature: ${specName}
${taskId ? `- Task ID: ${taskId}` : ''}
${context.dashboardUrl ? `- Dashboard: ${context.dashboardUrl}` : ''}

---

## ⚠️ RESUME PROTOCOL — READ BEFORE DOING ANYTHING ELSE

This session may be a resume of a previously interrupted /spec-implement run (rate limit, network failure, manual abort). The source of truth for step-level progress is:

  .spec-workflow/specs/${specName}/Implementation Logs/task-<SANITIZED_TASK_ID>_progress.md

(SANITIZED_TASK_ID replaces '.' and '/' with '-'; e.g. task 2.1 → task-2-1.)

### Resume decision procedure

1. **Check progress log.** If the progress.md for this task does not exist, this is a fresh run — proceed to step 1 of the TDD workflow below.

2. **If progress.md exists**, read the last non-header line. Entries are tab-separated: \`<ISO8601>\\t<EVENT>\\t<STEP_ID>\\t<META_JSON>\`. Decide based on the last event:

   - Last event is \`COMPLETE\` → task is already done. Stop. Report to the user and exit.
   - Last event is \`VERIFIED <step>\` → the named step completed and was verified. Skip it. Start from the next step in the workflow order (see "Step order" below).
   - Last event is \`FAILED <step>\` → step failed non-recoverably. Stop and escalate to the user with the recorded \`meta.reason\`. Do NOT retry without user instruction.
   - Last event is \`END <step>\` with no subsequent \`VERIFIED\` or \`FAILED\` → the subagent returned but the orchestrator was interrupted before verifying. **Redo that step from scratch** (new attempt number).
   - Last event is \`BEGIN <step>\` with no subsequent \`END\` → the subagent itself was interrupted (rate limit, kill). **Redo that step from scratch** (new attempt number).

3. **Count the \`BEGIN\` events for the step you are about to redo.** If it is already ≥ 3, **reset to the start of the task**: stop, report to the user that the step has exceeded the retry limit, and ask for guidance before proceeding. Do not silently continue.

4. **Before redoing a step**, check whether the working tree is clean:
   - If dirty, stop and surface the state to the user. The step's partial edits must be resolved (committed, stashed, or reverted to the pre-step git checkpoint) before redo. The progress-begin hook creates a git tag \`spec-impl/${specName}/task-<SANITIZED_TASK_ID>/step-<STEP_ID>/attempt-<N>\` at each BEGIN, which can be used to \`git reset --hard\` after user approval.
   - If clean, proceed to redo.

5. **_DependsOn handling.** If the resume point is inside a task with \`_DependsOn\` references, surface the dependency chain to the user before starting: a silent redo may not re-validate downstream tasks that were built on top of this one. Ask whether downstream tasks should also be marked \`[-]\` for rework.

### Step order (canonical)

For a normal task:
\`discover → red-write → red-verify → green-code → green-verify → refactor → refactor-verify → log\`

For a \`_PhaseReview: true\` task:
\`discover → log\` (TDD cycle is skipped)

Do not introduce new step IDs. The progress-log parser treats unknown step IDs as warnings.

---

## ⚠️ METADATA TAG REQUIREMENT — MANDATORY FOR EVERY TASK CALL

Every invocation of the \`Task\` tool (subagent spawn) in this workflow must begin its prompt with the following tag on the first line:

    <spec-step spec="${specName}" task=${taskIdSlot} step="<STEP_ID>" attempt="<N>">

- \`spec\`, \`task\`, and \`step\` are required; \`attempt\` is optional (defaults to 1).
- \`step\` must be one of the canonical step IDs listed above.
- \`attempt\` is the retry count for this step within this task (1 on first try, 2 on redo, etc.).

A PreToolUse hook extracts this tag and writes a \`BEGIN\` event to progress.md, creating a git checkpoint tag at the same time. **If the tag is missing, the hook exits with code 2 and the Task call is blocked.** Do not work around this by skipping delegation — the delegation boundary is the only reliable resume checkpoint.

Do NOT run implementation work inline from the main agent (direct Read/Edit/Write/Bash). The hook does not fire on those tools, and resume will silently lose track.

### Writing verification events

The main agent (orchestrator) — not the subagent — is responsible for appending these events to progress.md after each delegation returns:

- \`VERIFIED\` — step succeeded and its outputs were inspected. Write after you confirm the subagent's result is correct.
- \`FAILED\` — step failed in a way that cannot be retried. Include \`{"reason":"..."}\` in the META_JSON.
- \`COMPLETE\` — task is fully done (write after the final \`VERIFIED: log\` succeeds).

Format: \`<ISO8601_UTC>\\t<EVENT>\\t<STEP_ID>\\t<META_JSON>\` appended as a single new line. Use the Edit/Write tool on progress.md directly for these three events only.

---

## TDD Workflow

1. **Check Current Status:**
   - Run \`/spec-status ${specName}\` to see overall progress
   - Read .spec-workflow/specs/${specName}/tasks.md to see all tasks
   - Identify ${taskId ? `task ${taskId}` : 'the next pending task marked with [ ]'}

2. **Start the Task (automatic — do not edit tasks.md manually):**
   - The tasks.md checkbox transition ([ ] → [-]) is handled automatically by the tasks-auto-update module once the first BEGIN event is written to progress.md by the progress-begin hook.
   - Do NOT manually Edit .spec-workflow/specs/${specName}/tasks.md to set [-]. Manual edits will be overwritten by the auto-updater and can cause progress/tasks drift.

3. **Read Task Guidance:**
   - Look for the _Prompt field in the task — it contains structured guidance:
     - Role: The specialized developer role to assume
     - Task: Clear description with context references
     - Restrictions: What not to do and constraints
     - Success: Specific completion criteria
   - Note the _Leverage fields for files/utilities to use
   - Check _Requirements fields for which requirements this implements

4. **Phase Review Tasks (Special Handling):**
   - If the task has \`_PhaseReview: true_\`, **skip steps 5–11** (the TDD cycle)
   - Instead: run the full test suite → code review all phase changes → commit with phase summary
   - Then proceed directly to step 12 (Log)

5. **Discover Existing Implementations (CRITICAL — delegate, do not grep inline):**
   - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
   - Prompt's first line: \`<spec-step spec="${specName}" task=${taskIdSlot} step="discover" attempt="<N>">\`
   - Body: instruct the subagent to search \`.spec-workflow/specs/${specName}/Implementation Logs/\` for prior artifacts, APIs, components, and patterns related to this task, and return a concise summary (file paths + 1-line descriptions).
   - The main agent does NOT grep/read these files directly. The delegation is the resume checkpoint.

6. **RED — Write Failing Tests:**
   - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
   - Prompt's first line: \`<spec-step spec="${specName}" task=${taskIdSlot} step="red-write" attempt="<N>">\`
   - The subagent should follow the /spec-impl-test-write skill instructions
   - Provide: project path, spec name, task ID, full _Prompt content, design doc path
   - If the task has a \`_TestFocus\` field, pass it to the subagent as "Test focus areas: {_TestFocus content}"
   - The subagent writes tests that MUST FAIL (production code doesn't exist yet)
   - Capture: test file paths and test runner command
   - After return: write \`VERIFIED: red-write\` (or \`FAILED: red-write\`) to progress.md

7. **Verify Red — All Tests Must Fail:**
   - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
   - Prompt's first line: \`<spec-step spec="${specName}" task=${taskIdSlot} step="red-verify" attempt="<N>">\`
   - The subagent should follow the /spec-impl-test-run skill instructions
   - Provide: project path, test file paths, expected mode "red"
   - ALL tests must fail. If any pass, investigate and fix the tests.
   - After return: write \`VERIFIED: red-verify\` to progress.md

8. **GREEN — Write Minimal Production Code:**
   - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
   - Prompt's first line: \`<spec-step spec="${specName}" task=${taskIdSlot} step="green-code" attempt="<N>">\`
   - The subagent should follow the /spec-impl-code skill instructions
   - Provide: project path, spec name, task ID, _Prompt content, test file paths, _Leverage files
   - Write ONLY enough code to make the tests pass (YAGNI)
   - Do NOT modify test files
   - Capture: implementation file paths
   - After return: write \`VERIFIED: green-code\` to progress.md

9. **Verify Green — All Tests Must Pass:**
   - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
   - Prompt's first line: \`<spec-step spec="${specName}" task=${taskIdSlot} step="green-verify" attempt="<N>">\`
   - The subagent should follow the /spec-impl-test-run skill instructions
   - Provide: project path, test file paths, expected mode "green"
   - ALL tests must pass. If any fail, fix the implementation and retry (max 3 attempts).
   - After return: write \`VERIFIED: green-verify\` to progress.md

10. **REFACTOR — Review and Clean Up:**
    - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
    - Prompt's first line: \`<spec-step spec="${specName}" task=${taskIdSlot} step="refactor" attempt="<N>">\`
    - The subagent should follow the /spec-impl-review skill instructions
    - Provide: project path, spec name, task ID, _Prompt content, test files, implementation files, success criteria
    - Refactor for clarity and maintainability WITHOUT changing behavior
    - Do NOT change test expectations or add new features
    - After return: write \`VERIFIED: refactor\` to progress.md

11. **Verify Refactor — Tests Still Pass:**
    - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
    - Prompt's first line: \`<spec-step spec="${specName}" task=${taskIdSlot} step="refactor-verify" attempt="<N>">\`
    - Run tests again in "green" mode
    - If tests fail after refactoring, revert the refactoring changes and escalate
    - After return: write \`VERIFIED: refactor-verify\` to progress.md

12. **Log Implementation (MANDATORY — delegate, do not skill-call inline):**
    - ⚠️ **STOP: Do NOT write \`COMPLETE\` until this step succeeds.**
    - A task without an implementation log is NOT complete. Skipping this step is the #1 workflow violation.
    - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
    - Prompt's first line: \`<spec-step spec="${specName}" task=${taskIdSlot} step="log" attempt="<N>">\`
    - Body: call the \`/log-implementation\` skill with ALL of the following:
      - specName: "${specName}"
      - taskId: ${taskId ? `"${taskId}"` : 'the task ID you just completed'}
      - summary: Clear description of what was implemented (1-2 sentences)
      - filesModified: List of files you edited
      - filesCreated: List of files you created — **include test files**
      - statistics: {linesAdded: number, linesRemoved: number}
      - artifacts: {apiEndpoints: [...], components: [...], functions: [...], classes: [...], integrations: [...]}
    - You MUST include artifacts (required field) to enable other agents to find your work
    - Why delegate: future AI agents will query logs before implementing, preventing duplicate code; and the step must be bracketed by BEGIN/END for resume tracking.
    - After return: write \`VERIFIED: log\` to progress.md

13. **Complete the Task (automatic — do not edit tasks.md manually):**
    - After step 12's \`VERIFIED: log\` is written, append a single \`COMPLETE\` event to progress.md with META_JSON \`{"log_id":"<id-returned-by-log-implementation>"}\`.
    - The tasks-auto-update module will detect the COMPLETE event and flip the tasks.md checkbox from [-] to [x] on the next sync.
    - Do NOT manually Edit tasks.md. A manual [x] without a COMPLETE event will be treated as drift and reverted.

**Important Guidelines:**
- Resume protocol (above) takes precedence over these steps. Always start by checking progress.md.
- Every Task call must carry a \`<spec-step>\` tag; missing tags are hard-blocked by the PreToolUse hook.
- Do not edit tasks.md checkboxes by hand — the auto-updater is authoritative.
- Do not run implementation work inline from the main agent — delegate.
- The main agent writes VERIFIED / FAILED / COMPLETE to progress.md; the hook writes BEGIN / END.
- Follow TDD strictly: RED (tests first) → GREEN (minimal code) → REFACTOR (clean up)
- For \`_PhaseReview: true_\` tasks, skip the TDD cycle — discover → log only (step 4)
- Pass \`_TestFocus\` content to the RED phase subagent when available
- Use existing patterns and utilities mentioned in _Leverage fields
- Include test files in filesCreated when logging implementation
- If a task has subtasks (e.g., 4.1, 4.2), complete them in order
- If you encounter blockers, write \`FAILED: <step>\` to progress.md with a \`reason\` and report to the user

**Tools and Skills to Use:**
- \`/spec-status\` skill: Check overall progress
- Agent: Spawn subagents for every step (discover, TDD phases, log) — tag each with \`<spec-step>\`
- Edit / Write (on progress.md): Append VERIFIED / FAILED / COMPLETE events only
- \`/log-implementation\` skill: MANDATORY — invoked via a subagent delegation at step 12

Please proceed with implementing ${taskId ? `task ${taskId}` : 'the next task'} following the RESUME PROTOCOL first, then the TDD workflow.`
      }
    }
  ];

  return messages;
}

export const implementTaskPrompt: PromptDefinition = {
  prompt,
  handler
};
