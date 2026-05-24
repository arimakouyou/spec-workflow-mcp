# spec-implement Parallel Sections (archived)

Origin: `.claude-plugin/skills/spec-implement/SKILL.md`

This file preserves the wave-parallel-execution rules that this Skill defined at the time of archival. To re-enable, restore these to their original locations and add an orchestrator-compliance enforcement mechanism (see `README.md`).

---

## (former) Section: Multi-task wave handling and sub-batch splitting (was around L221-247)

```markdown
**Single-task wave**: If the wave contains only one task, process it as before (sequential flow).

**Multi-task wave**: If the wave contains multiple tasks, process them in parallel:

- Mark ALL tasks in the wave from `[ ]` to `[-]` in tasks.md
- Prepare worktrees for all tasks (step 3.7)
- Launch parallel-workers in resource-aware batches (step 4)

**Session update (at the start of each task)**: For each task marked `[-]`, run the following to update the session's `current_task` (in a multi-task wave, the last task started within the wave becomes current_task; this is best-effort and may be inaccurate):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-manage.sh" start-task {task-id}
```

**Resource-aware parallel control**: Before processing a multi-task wave, run the resource detection snippet from the `resource-aware-parallelism` skill to obtain `MAX_HEAVY_AGENTS`. If the number of tasks in the wave exceeds `MAX_HEAVY_AGENTS`, split the wave into **sub-batches** of `MAX_HEAVY_AGENTS` tasks each, and process each sub-batch sequentially. If `MAX_HEAVY_AGENTS=1`, run all tasks serially.

Sub-batch split examples:

- wave with 6 tasks, MAX_HEAVY_AGENTS=3 → sub-batches [3, 3]
- wave with 4 tasks, MAX_HEAVY_AGENTS=2 → sub-batches [2, 2]
- wave with 3 tasks, MAX_HEAVY_AGENTS=1 → sub-batches [1, 1, 1] (serial execution)

> Note: In a multi-task wave, multiple tasks being `[-]` (in-progress) at the same time is **intended, normal behavior**. This is an explicit exception to guidance such as "Only one task should be in-progress at a time" in prompts like `implement-task`.

**PhaseReview exclusion during wave computation**: Tasks with `_PhaseReview: true` are always excluded from wave computation. PhaseReview is processed alone after all regular tasks in the phase complete.

**No `_DependsOn:` metadata**: If no tasks in the Phase have `_DependsOn:`, all non-PhaseReview tasks form Wave 0 and are processed as a single multi-task wave in **parallel**. Mark them from `[ ]` to `[-]` together, following the same multi-task wave rules described above.

**Per-task processing in a multi-task wave**: Each task in the wave runs steps 3-8 (worktree creation → parallel-worker → UT verification → review-worker → log → merge/cleanup → mark `[x]`) **independently per task**. Each task works in its dedicated worktree/branch and is merged individually on completion. Proceed to the next wave only after all tasks in the wave have completed (or failed).
```

## (former) Section: Wave parallel execution (in step 4, was around L551-558)

```markdown
**Wave parallel execution**: For multi-task waves, apply resource-aware parallelism control (see `resource-aware-parallelism` Skill). Before launching in parallel, run the resource detection snippet to obtain `MAX_HEAVY_AGENTS`. If the number of tasks in a wave exceeds `MAX_HEAVY_AGENTS`, split into sub-batches and launch only the agents within each sub-batch concurrently. Wait for each sub-batch to finish before launching the next, and proceed to step 5 only after all sub-batches finish. When the number of tasks in a wave is at or below `MAX_HEAVY_AGENTS`, launch all agents concurrently.

Record the resource detection result in logs:

```text
[resource-check] CPU: {CPU_CORES} cores, Free memory: {FREE_MEM_MB}MB, MAX_HEAVY_AGENTS: {MAX_HEAVY_AGENTS}
[wave-split] Wave has {N} tasks, processing in {M} sub-batch(es) of {sizes}
```
```
