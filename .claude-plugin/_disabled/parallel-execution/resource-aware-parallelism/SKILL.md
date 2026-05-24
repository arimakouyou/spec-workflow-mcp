---
name: resource-aware-parallelism
description: |
  Skill that dynamically detects system resources (CPU core count / available memory) before launching parallel agents and automatically adjusts the maximum parallelism. For heavy agents (compile-heavy ones such as parallel-worker, integ-test-worker), it computes MAX_HEAVY_AGENTS via tiered thresholds and supports overrides through the SWM_MAX_PARALLEL_AGENTS environment variable. Reference this before wave execution in spec-implement, before Worker assignment in integration-test, and before any parallel subagent launch. Triggers on: 'resource-aware parallelism', 'detect CPU and memory', 'limit parallel agents', 'wave subbatch split', '並列エージェント', 'リソース検出', 'wave 実行', 'Worker 割当'.
allowed-tools: [Read, Bash, Grep]
---

# Resource-Aware Parallelism Skill

## Scope

- Determining max concurrency before launching multiple parallel subagents
- Subbatch splitting during wave execution in `spec-implement`
- Worker assignment in `integration-test` / `integration-test-dotnet`
- Use of parallel frameworks such as `wave-harness-worker` / `parallel-worker`

## Out of Scope

- Implementation of the actual parallel launch — see the relevant section of each Skill / Agent
- Tuning of individual jobs that demand CPU / memory — handled in project-side configuration

## Key Points

### 1. Resource Detection Snippet

**Immediately before** launching parallel agents, run the following inside a **single Bash invocation** (Claude Code's Bash does not preserve shell state across commands):

```bash
# === Resource detection + max-parallelism computation ===
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
if [ -f /proc/meminfo ]; then
  FREE_MEM_MB=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo)
elif command -v vm_stat >/dev/null 2>&1; then
  PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
  FREE_MEM_MB=$(vm_stat | awk -v PS="$PAGE_SIZE" '/Pages free/{gsub(/\./,"",$3); print int($3*PS/1048576)}')
else
  FREE_MEM_MB=4096
fi

# Numeric guard: fall back if parsing fails
case "$CPU_CORES" in ''|*[!0-9]*) CPU_CORES=2 ;; esac
case "$FREE_MEM_MB" in ''|*[!0-9]*) FREE_MEM_MB=4096 ;; esac

# Validate user override (accept positive integers only)
MAX_OVERRIDE=${SWM_MAX_PARALLEL_AGENTS:-""}
if [ -n "$MAX_OVERRIDE" ]; then
  case "$MAX_OVERRIDE" in ''|*[!0-9]*|0) MAX_OVERRIDE="" ;; esac
fi

# Heavy agents (compile-heavy: parallel-worker, integ-test-worker)
if [ -n "$MAX_OVERRIDE" ]; then
  MAX_HEAVY_AGENTS=$MAX_OVERRIDE
elif [ "$CPU_CORES" -ge 8 ] && [ "$FREE_MEM_MB" -ge 16384 ]; then
  BY_CPU=$((CPU_CORES / 2)); BY_MEM=$((FREE_MEM_MB / 4096))
  MAX_HEAVY_AGENTS=$(( BY_CPU < BY_MEM ? BY_CPU : BY_MEM ))
  MAX_HEAVY_AGENTS=$(( MAX_HEAVY_AGENTS > 4 ? 4 : MAX_HEAVY_AGENTS ))
elif [ "$CPU_CORES" -ge 4 ] && [ "$FREE_MEM_MB" -ge 8192 ]; then
  BY_CPU=$((CPU_CORES / 2)); BY_MEM=$((FREE_MEM_MB / 4096))
  MAX_HEAVY_AGENTS=$(( BY_CPU < BY_MEM ? BY_CPU : BY_MEM ))
  MAX_HEAVY_AGENTS=$(( MAX_HEAVY_AGENTS > 3 ? 3 : MAX_HEAVY_AGENTS ))
elif [ "$CPU_CORES" -ge 2 ] && [ "$FREE_MEM_MB" -ge 4096 ]; then
  MAX_HEAVY_AGENTS=2
else
  MAX_HEAVY_AGENTS=1
fi

echo "[resource-check] CPU_CORES=$CPU_CORES FREE_MEM_MB=$FREE_MEM_MB MAX_HEAVY_AGENTS=$MAX_HEAVY_AGENTS"
```

### 2. Agent Classification

| Class | Variable | Target Agents | Characteristics |
|---|---|---|---|
| Heavy | `MAX_HEAVY_AGENTS` | `parallel-worker`, `integ-test-worker` | cargo build/test/clippy, high memory |

### 3. Threshold Table (Heavy Agents)

| CPU cores | Free memory | Max parallelism | Rationale |
|:---:|:---:|:---:|---|
| >= 8 | >= 16GB | `min(cores/2, mem/4GB, 4)` | Plentiful resources. Cap at 4 for safety margin |
| >= 4 | >= 8GB | `min(cores/2, mem/4GB, 3)` | Mid-tier. Cap at 3 |
| >= 2 | >= 4GB | 2 | Minimal parallelism |
| < 2 or < 4GB | — | 1 | Serial execution (safe fallback) |

### 4. User Override

The environment variable `SWM_MAX_PARALLEL_AGENTS` overrides the auto-detected value:

```bash
# Example: limit to at most 2 agents
export SWM_MAX_PARALLEL_AGENTS=2
```

### 5. Application Rules

1. **Always run resource detection before launching parallel agents**
2. When the number of tasks in a wave exceeds `MAX_HEAVY_AGENTS`, split the wave into **subbatches**
   - Example: a wave with 6 tasks and `MAX_HEAVY_AGENTS=3` runs sequentially as `[3, 3]` subbatches
3. When `MAX_HEAVY_AGENTS=1`, run serially (no parallelism)
4. Log resource detection results so they are visible to the user
5. Fallbacks if detection commands fail: `CPU=2`, `memory=4096MB`

## Common Pitfalls

1. **Skipping resource detection and launching with a fixed parallelism**: risks SIGKILL from out-of-memory and may bring down the builder host
2. **Splitting across multiple Bash invocations**: Claude Code's Bash does not preserve shell state, so variables are lost. Always use a single invocation
3. **Skipping wave splitting when `MAX_HEAVY_AGENTS=1`**: the only downside is harder-to-read logs, so always go through the subbatch-splitting path
4. **Forgetting the upper-bound clamp on overflow**: always apply the `min(X, 4)` / `min(X, 3)` clamp

## Project-Specific Conventions

- Wave execution in `spec-implement` always goes through resource detection (direct parallel launches are prohibited)
- Worker assignment in `integration-test` follows the same rule
- In CI environments, set `SWM_MAX_PARALLEL_AGENTS` based on the runner's vCPU count

## Related Rules / Skills

- Related Skills: `spec-implement`, `integration-test`, `integration-test-dotnet`
- Related Rule: `failure-taxonomy` (classification when SIGKILL occurs due to resource exhaustion)

## References

- GNU coreutils `nproc`: <https://www.gnu.org/software/coreutils/manual/html_node/nproc-invocation.html>
- macOS `sysctl` / `vm_stat`: see man pages
