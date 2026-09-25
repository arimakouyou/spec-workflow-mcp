---
name: spec-implement
description: "Phase 5 of the v2 spec workflow: implement an approved spec task by task. The orchestrator only routes — it asks spec-next.sh for the next task, launches the implementer, verifier and reviewer agents one at a time, and follows the reviewer's verdict; every commit goes through spec-git.sh. Use only when all four spec documents are approved. Triggers on: '/spec-implement <spec>', 'implement spec X', 'continue implementation', '実装を始める', '実装を再開'."
---

# Implement (orchestrator)

You route; you do not implement, test, review or commit.

- You never edit source files: guard-edit blocks the main agent.
- You never run raw git commit / merge / reset / push: guard-git blocks it.
- You never read the spec documents' bodies. Your inputs are script output and each agent's final JSON.

Agents run one at a time. The Agent tool returns immediately and the agent runs in the background. **Wait for its completion notification before the next step.** guard-agent refuses a second agent while one is running.

## 0. Start

1. Check the preconditions:
   - The current branch is `spec/<spec>`.
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-state.sh <spec> --ready` succeeds. If not, show the states and stop: `/check-approval` or `/spec-change` must bring the documents back to approved first.
2. Mark the session: `printf '%s\n' <spec> > .spec-workflow/.active`. This arms guard-edit, guard-agent, guard-git and record-subagent.
3. If `.spec-workflow/.resume` exists, delete it after reading it: you are resuming.

## 1. Loop

Repeat until `spec-next.sh` reports DONE:

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-next.sh <spec>` prints `key <TAB> type <TAB> phase <TAB> title <TAB> tests`.
   - Exit 2: go to §3.
   - Exit 3: the spec is no longer ready. Stop and report.
2. If `runs/<key>/start.json` exists and the tree is not clean, a previous attempt was interrupted. Run `spec-git.sh discard <spec> <key>` first.
3. Dispatch by type:

| type | Steps |
|---|---|
| `tools` | `spec-git.sh start <spec> P0-TOOLS`. Then `spec-git.sh record <spec> P0-TOOLS`, which runs `spec-tools-check.sh` as its gate. If a required tool is missing, show the install commands and stop. |
| `des-logic`, `des-types`, `des-ui` | start → **impl-worker** → verifier (**unit-test-engineer**, or **frontend-test-engineer** for ui) → **review-worker** |
| `des-adapter`, `des-wiring`, `des-config`, `refactor` | start → **impl-worker** → verifier for refactor only (**unit-test-engineer**) → **review-worker** |
| `tst-*` | start → **integ-test-worker** → **review-worker** |
| `it`, `st`, `smk`, `final` | start → **integ-test-worker** → **integ-test-auditor** → **review-worker** |
| `review` | start → `spec-phase-check.sh <spec> <phase>` → **review-worker** |

- `start` means `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-git.sh start <spec> <key>`.
- Every agent prompt starts with:

  ```
  TASK: <key>
  SPEC: <spec>
  ROOT: <project root>
  MODE: implement | rework
  ```

  For rework, add `rework_from: red|green`. Nothing else is needed: each agent builds its own brief with `spec-brief.sh`.

4. Route on the reviewer's final JSON (`verdict`, defined in `${CLAUDE_PLUGIN_ROOT}/rules/verdict.md`):

| Verdict | Action |
|---|---|
| `commit` | review-worker has already committed with `spec-git.sh`. Continue the loop. |
| `rework` | Count the reworks of this task in `runs/<key>/history.jsonl`. Below 3: launch the implementer again with `MODE: rework` and the given `rework_from`. The tree is kept. Then run the verifier and review-worker again. For a phase review, run `spec-git.sh reopen <spec> <task>` for each task in `reopen`, then continue the loop. |
| `escalate` | Stop. Show the reviewer's `escalation` (kind, IDs, assessment, recommendation) and tell the user the next step: `/spec-change <spec>` for (a) and (b), a decision for (c). Keep `.active` so the state is visible. |

If the implementer returned `blocked` with `defect` (an IT found an implementation bug), review-worker reports it with `reopen: [DES-N]`. Run `spec-git.sh discard <spec> <key>`, then `spec-git.sh reopen <spec> DES-N`, and continue: that DES comes back first.

## 2. Interruption

A rate limit or a crash leaves `.resume` behind (StopFailure hook). In the next session, SessionStart shows the state. Run `/spec-implement <spec>` again: the position is recomputed from commit trailers, and §1 step 2 discards the interrupted attempt.

For unattended runs, the user can run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-resume-loop.sh <spec>`.

## 3. Finish

The `FINAL` task is the last one. Its review-worker commits, archives the spec (`spec-git.sh archive`) and opens the PR (`/create-pr`). Then:

1. Delete `.spec-workflow/.active`.
2. Report the PR URL and the commit range.
