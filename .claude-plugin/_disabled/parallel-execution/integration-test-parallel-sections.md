# integration-test Parallel Sections (archived)

Origin: `.claude-plugin/skills/integration-test/SKILL.md`

This file preserves the alpha/bravo Worker parallel-launch rules that this Skill defined at the time of archival. To re-enable, restore these to their original locations and add an orchestrator-compliance enforcement mechanism (see `README.md`).

---

## (former) Section: P0 Worker assignment (was around L117-125)

```markdown
3. **Worker assignment**: assign to Workers per test file. Before assigning, run the resource-detection snippet from the `resource-aware-parallelism` Skill to obtain `MAX_HEAVY_AGENTS`. Cap the number of Workers at `min(Workers column in the table below, MAX_HEAVY_AGENTS)`.

   | # of Targets | MAX_HEAVY_AGENTS | # of Workers | Assignment Method |
   |:------:|:------:|:---------:|---------|
   | 1 | any | 1 | All to alpha |
   | 2 | >= 2 | 2 | One each to alpha / bravo |
   | 2 | 1 | 1 | Both to alpha (sequential) |
   | 3+ | >= 2 | 2 | Round-robin |
   | 3+ | 1 | 1 | All to alpha (sequential) |
```

## (former) Section: P2 Resource-adaptive parallel control (was around L148-152)

```markdown
**Resource-adaptive parallel control**: cap the number of Workers based on the `MAX_HEAVY_AGENTS` obtained in P0. Log the resource-detection result:
```
[resource-check] CPU: {CPU_CORES} cores, Free memory: {FREE_MEM_MB}MB, MAX_HEAVY_AGENTS: {MAX_HEAVY_AGENTS}
[worker-limit] Requested {N} workers, launching {M} (limited by MAX_HEAVY_AGENTS)
```
```

## (former) Section: P2 Launch Workers (was around L170)

```markdown
If there are 2 or more targets and `MAX_HEAVY_AGENTS >= 2`, launch alpha/bravo in parallel. Otherwise, launch alpha only and assign all targets sequentially.
```
