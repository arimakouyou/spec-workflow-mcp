# Disabled: Parallel Execution

Archive of parallel-execution-related documentation and Skills that have been temporarily disabled in the spec-workflow-mcp plugin.

## Why these were disabled

In consumer projects, the orchestrator (parent Claude) was observed skipping the `Resource-aware parallel control` step in the `spec-implement` Skill (i.e., not running the resource-detection snippet, not obtaining `MAX_HEAVY_AGENTS`, not splitting the wave into sub-batches) and instead launching agents in parallel based on DAG-allowed wave parallelism alone. The `SWM_MAX_PARALLEL_AGENTS=1` env override is ineffective in this scenario because the Skill body that reads it is itself being skipped — there is no enforcement point at the env layer.

As the simplest reliable fix, parallel launching was removed from all Skills and Agents in the plugin and replaced with serial-only execution. This directory archives the original parallel content for possible future restoration.

See `rules/serial-execution-policy.md` for the active policy that replaces these.

## Archive contents

| File | Origin | Purpose |
|---|---|---|
| `resource-aware-parallelism/SKILL.md` | `skills/resource-aware-parallelism/SKILL.md` | The full resource-detection / `MAX_HEAVY_AGENTS` / `SWM_MAX_PARALLEL_AGENTS` override Skill |
| `integration-test-references-parallel-execution.md` | `skills/integration-test/references/parallel-execution.md` | The alpha/bravo Worker parallel launch flow for `integration-test` |
| `integration-test-dotnet-references-parallel-execution.md` | `skills/integration-test-dotnet/references/parallel-execution.md` | The .NET counterpart of the above |
| `spec-implement-parallel-sections.md` | `skills/spec-implement/SKILL.md` (wave-parallel sections) | Wave sub-batching and parallel launch rules |
| `integration-test-parallel-sections.md` | `skills/integration-test/SKILL.md` (Worker-parallel sections) | alpha/bravo resource-adaptive parallel control rules |
| `integration-test-dotnet-parallel-sections.md` | `skills/integration-test-dotnet/SKILL.md` (Worker-parallel sections) | The .NET counterpart of the above |
| `spec-e2e-implement-parallel-sections.md` | `skills/spec-e2e-implement/SKILL.md` | Parallel IT/E2E generation via parallel-worker |

## Re-enabling

1. Move each archived file back to its original location (reverse of the `git mv` performed at archive time)
2. Delete `rules/serial-execution-policy.md`
3. Revert the serial-only wording in each Skill body to the prior parallel rules (consult commit history)
4. Add an orchestrator-compliance enforcement mechanism (e.g., a PreToolUse hook that requires the resource-check log to appear before any heavy-agent launch) — without this, the same skipping behavior will recur

## Related commits

- Archive creation + Skill rewrites: branch `refactor/plugin-redesign-phase-a`
