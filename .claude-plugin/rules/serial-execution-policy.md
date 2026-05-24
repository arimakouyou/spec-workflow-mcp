---
always_apply: true
---

# Serial Execution Policy

Across the entire spec-workflow-mcp plugin, **parallel launching of subagents is prohibited**. This rule supersedes the prior `Resource-aware parallel control` / `Wave parallel execution` / `Resource-adaptive parallel control` regulations.

## Principle

- Anywhere in the plugin, subagents (parallel-worker / integ-test-worker / others) MUST NOT be launched concurrently
- A single message MAY contain at most **one** `Agent` tool invocation. Wait for the prior agent to complete before launching the next
- Even when multiple tasks within the same Wave are logically independent per the DAG (`_DependsOn:`), this rule takes precedence — launch them one at a time
- The environment variable `SWM_MAX_PARALLEL_AGENTS` and the auto-detected `MAX_HEAVY_AGENTS` are **disabled regardless of value** (treated as `min(N, 1)`)

## Scope

| Skill / Agent | Prior parallel mechanism | Behavior under this policy |
|---|---|---|
| `spec-implement` | Sub-batched parallel launch within a wave | Launch tasks within a wave one at a time |
| `integration-test` | alpha / bravo Worker parallel launch | Launch alpha only; alpha handles all targets sequentially |
| `integration-test-dotnet` | Same as above | Same as above |
| `spec-e2e-implement` | Parallel IT/E2E generation | Generate IT/E2E one at a time |

## Implementation Rules

1. **One `Agent` invocation per message**: Even when multiple independent tasks are pending, launch one, wait for its completion report (status / changed_files), then launch the next
2. **Do not run the resource detection snippet**: The prior `[resource-check]` log output is unnecessary — this policy fixes the effective limit at 1, so detection has no effect
3. **Do not retain MAX_HEAVY_AGENTS-conditional text in Skill bodies**: Serial is the only path; no branching is required
4. **DAG Wave structure is preserved**: Continue to compute waves from `_DependsOn:` as before. The change is that multiple tasks within a wave are processed serially rather than concurrently

## Rationale

The orchestrator (the parent Claude in the consumer project) was observed skipping the resource-detection snippet step required by the prior `Resource-aware parallel control` rule and launching agents in parallel directly based on DAG-allowed wave parallelism. The `SWM_MAX_PARALLEL_AGENTS=1` env override is also ineffective in this case, because the Skill body that reads it is itself being skipped — there is no enforcement point at the env layer.

A harness-side enforcement option (a PreToolUse hook on the `Agent` tool that validates a resource-check state file) was considered but rejected for these reasons:

- State file design and lifecycle complexity
- No guarantee that the orchestrator would correctly recover after receiving a deny feedback
- Keeping a single source of truth in the Skill body itself is more reliable

For these reasons, prohibiting parallel launches directly in the Skill body was chosen as the simplest reliable fix.

## Re-enabling Parallelism (Future Work)

To re-enable parallelism in the future:

1. Restore the archived sections from `.claude-plugin/_disabled/parallel-execution/` to their original locations
2. Delete this rule file
3. Revert each Skill's serial-only wording to the prior parallel rules (consult commit history)
4. Add an enforcement mechanism (e.g., a PreToolUse hook that requires resource-check log output before any heavy-agent launch) — without this, the same skipping behavior will recur

Removing only this rule file is insufficient — the Skill bodies have also been rewritten to serial-only and must be reverted in tandem.
