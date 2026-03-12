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

**TDD Implementation Workflow:**

1. **Check Current Status:**
   - Use the spec-status tool with specName "${specName}" to see overall progress
   - Read .spec-workflow/specs/${specName}/tasks.md to see all tasks
   - Identify ${taskId ? `task ${taskId}` : 'the next pending task marked with [ ]'}

2. **Start the Task:**
   - Edit .spec-workflow/specs/${specName}/tasks.md directly
   - Change the task marker from [ ] to [-] for the task you're starting
   - Only one task should be in-progress at a time

3. **Read Task Guidance:**
   - Look for the _Prompt field in the task - it contains structured guidance:
     - Role: The specialized developer role to assume
     - Task: Clear description with context references
     - Restrictions: What not to do and constraints
     - Success: Specific completion criteria
   - Note the _Leverage fields for files/utilities to use
   - Check _Requirements fields for which requirements this implements

4. **Phase Review Tasks (Special Handling):**
   - If the task has \`_PhaseReview: true_\`, **skip steps 5-10** (the TDD cycle)
   - Instead: run the full test suite → code review all phase changes → commit with phase summary
   - Then proceed directly to step 11 (Log)

5. **Discover Existing Implementations (CRITICAL):**
   - BEFORE writing any code, search implementation logs to understand existing artifacts
   - Implementation logs are stored as markdown files in: .spec-workflow/specs/${specName}/Implementation Logs/

   **Option 1: Use grep/ripgrep for fast searches**
   \`\`\`bash
   # Search for API endpoints
   grep -r "GET\\|POST\\|PUT\\|DELETE" ".spec-workflow/specs/${specName}/Implementation Logs/"

   # Search for specific components
   grep -r "ComponentName" ".spec-workflow/specs/${specName}/Implementation Logs/"

   # Search for integration patterns
   grep -r "integration\\|dataFlow" ".spec-workflow/specs/${specName}/Implementation Logs/"
   \`\`\`

   **Option 2: Read markdown files directly**
   - Use the Read tool to examine implementation log files
   - Review artifacts from related tasks to understand established patterns

6. **RED — Write Failing Tests:**
   - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
   - The subagent should follow the /spec-impl-test-write skill instructions
   - Provide: project path, spec name, task ID, full _Prompt content, design doc path
   - If the task has a \`_TestFocus\` field, pass it to the subagent as "Test focus areas: {_TestFocus content}"
   - The subagent writes tests that MUST FAIL (production code doesn't exist yet)
   - Capture: test file paths and test runner command

7. **Verify Red — All Tests Must Fail:**
   - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
   - The subagent should follow the /spec-impl-test-run skill instructions
   - Provide: project path, test file paths, expected mode "red"
   - ALL tests must fail. If any pass, investigate and fix the tests.

8. **GREEN — Write Minimal Production Code:**
   - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
   - The subagent should follow the /spec-impl-code skill instructions
   - Provide: project path, spec name, task ID, _Prompt content, test file paths, _Leverage files
   - Write ONLY enough code to make the tests pass (YAGNI)
   - Do NOT modify test files
   - Capture: implementation file paths

9. **Verify Green — All Tests Must Pass:**
   - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
   - The subagent should follow the /spec-impl-test-run skill instructions
   - Provide: project path, test file paths, expected mode "green"
   - ALL tests must pass. If any fail, fix the implementation and retry (max 3 attempts).

10. **REFACTOR — Review and Clean Up:**
   - Spawn a subagent using the Agent tool with subagent_type "general-purpose"
   - The subagent should follow the /spec-impl-review skill instructions
   - Provide: project path, spec name, task ID, _Prompt content, test files, implementation files, success criteria
   - Refactor for clarity and maintainability WITHOUT changing behavior
   - Do NOT change test expectations or add new features

11. **Verify Refactor — Tests Still Pass:**
    - Spawn a subagent to run tests again in "green" mode
    - If tests fail after refactoring, revert the refactoring changes

12. **Log Implementation (MANDATORY - must complete BEFORE marking task done):**
   - ⚠️ **STOP: Do NOT mark the task [x] until this step succeeds.**
   - A task without an implementation log is NOT complete. Skipping this step is the #1 workflow violation.
   - Call log-implementation with ALL of the following:
     - specName: "${specName}"
     - taskId: ${taskId ? `"${taskId}"` : 'the task ID you just completed'}
     - summary: Clear description of what was implemented (1-2 sentences)
     - filesModified: List of files you edited
     - filesCreated: List of files you created — **include test files**
     - statistics: {linesAdded: number, linesRemoved: number}
     - artifacts: {apiEndpoints: [...], components: [...], functions: [...], classes: [...], integrations: [...]}
   - You MUST include artifacts (required field) to enable other agents to find your work
   - Why: Future AI agents will query logs before implementing, preventing duplicate code

13. **Complete the Task (only after step 12 succeeds):**
   - Confirm that log-implementation returned success in step 12
   - Verify all success criteria from the _Prompt are met
   - Edit .spec-workflow/specs/${specName}/tasks.md directly
   - Change the task marker from [-] to [x] for the completed task
   - ⚠️ If you skipped step 12, go back now — a task marked [x] without a log is incomplete

**Important Guidelines:**
- Always mark a task as in-progress before starting work
- Follow TDD strictly: RED (tests first) → GREEN (minimal code) → REFACTOR (clean up)
- For \`_PhaseReview: true_\` tasks, skip the TDD cycle — run tests, review, commit instead (step 4)
- Each TDD phase runs as a separate subagent for isolation
- Pass \`_TestFocus\` content to the RED phase subagent when available
- Use existing patterns and utilities mentioned in _Leverage fields
- Include test files in filesCreated when logging implementation
- **ALWAYS call log-implementation BEFORE marking a task [x]**
- If a task has subtasks (e.g., 4.1, 4.2), complete them in order
- If you encounter blockers, document them and move to another task

**Tools to Use:**
- spec-status: Check overall progress
- Agent: Spawn subagents for TDD phases (test-write, test-run, code, review)
- Bash (grep/ripgrep): CRITICAL - Search existing implementations before coding (step 5)
- Read: Examine markdown implementation log files directly (step 5)
- log-implementation: MANDATORY - Record implementation details with artifacts BEFORE marking task complete (step 12)
- Edit: Directly update task markers in tasks.md file
- Read/Write/Edit: Implement the actual code changes
- Bash: Run tests and verify implementation

Please proceed with implementing ${taskId ? `task ${taskId}` : 'the next task'} following this TDD workflow.`
      }
    }
  ];

  return messages;
}

export const implementTaskPrompt: PromptDefinition = {
  prompt,
  handler
};
