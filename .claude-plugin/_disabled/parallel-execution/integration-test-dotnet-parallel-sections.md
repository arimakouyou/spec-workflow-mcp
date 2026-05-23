# integration-test-dotnet Parallel Sections (archived)

Origin: `.claude-plugin/skills/integration-test-dotnet/SKILL.md`

This file preserves the alpha/bravo Worker parallel-launch rules that this Skill defined at the time of archival. To re-enable, restore these to their original locations and add an orchestrator-compliance enforcement mechanism (see `README.md`).

---

## (former) Section: P0 Worker assignment (was around L358-366)

```markdown
3. **Worker assignment**: assign to Workers per test class. Before assignment, run the resource detection snippet from `resource-aware-parallelism` Skill and obtain `MAX_HEAVY_AGENTS`. Limit Worker count to `min(Workers column below, MAX_HEAVY_AGENTS)`.

   | # of Targets | MAX_HEAVY_AGENTS | # of Workers | Assignment Method |
   |:------:|:------:|:---------:|---------|
   | 1 | any | 1 | All to alpha |
   | 2 | >= 2 | 2 | One each to alpha / bravo |
   | 2 | 1 | 1 | Both to alpha (sequential) |
   | 3+ | >= 2 | 2 | Round-robin |
   | 3+ | 1 | 1 | All to alpha (sequential) |
```

## (former) Section: P2 Resource-adaptive parallel control (was around L389-393)

```markdown
**Resource-adaptive parallel control**: Limit Worker count based on `MAX_HEAVY_AGENTS` obtained in P0. Log the resource detection result:
```
[resource-check] CPU: {CPU_CORES} cores, Free memory: {FREE_MEM_MB}MB, MAX_HEAVY_AGENTS: {MAX_HEAVY_AGENTS}
[worker-limit] Requested {N} workers, launching {M} (limited by MAX_HEAVY_AGENTS)
```
```

## (former) Section: P2 Launch Workers (was around L411)

```markdown
If there are 2 or more targets and `MAX_HEAVY_AGENTS >= 2`, launch alpha/bravo in parallel. Otherwise, launch alpha only and assign all targets sequentially.
```
