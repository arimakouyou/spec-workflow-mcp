---
name: dotnet-build-cache
description: |
  Build cache configuration for every agent that runs the dotnet command in a .NET project. Covers MSBuild incremental builds (enabled by default, no configuration needed), the NuGet package cache (`~/.nuget/packages` is auto-shared and safe for concurrent access), the prohibition on sharing `bin/` / `obj/` (absolute-path differences across worktrees), the optimization chain `dotnet restore -> build --no-restore -> test --no-build`, hot reload via `dotnet watch`, what to target with `actions/cache` in CI, and troubleshooting via `dotnet clean` / `dotnet nuget locals all --clear`. Reference immediately before running dotnet build / test / publish, or before launching .NET parallel-worker / integ-test-worker. Triggers on: 'dotnet build cache', 'NuGet cache', 'MSBuild incremental build', 'dotnet restore --no-restore', '.NET ビルドキャッシュ', 'dotnet build / test / publish 実行前', 'NuGet キャッシュ設定'.
allowed-tools: [Read, Bash, Grep]
---

# .NET Build Cache

Build cache configuration guide for every agent that runs `dotnet` commands in a .NET project.
Unlike Rust's sccache, .NET relies on built-in cache mechanisms.

## In Scope

- Immediately before running dotnet build / test / publish
- Configuring the NuGet cache in CI (deciding what to target with `actions/cache`)
- Pre-processing before parallel `dotnet` command execution within a worktree
- Before launching .NET-flavored `parallel-worker` / `integ-test-worker`

## Out of Scope

- Rust build cache -> `rust-build-cache` Skill
- Detailed `actions/cache` setup in CI workflows -> `setup-ci` Skill
- Agent parallelism control -> `rules/serial-execution-policy.md` (subagent launch is serial-only across the plugin)

## MSBuild Incremental Build

MSBuild automatically tracks input/output timestamps. No special configuration is required for local development.

- `dotnet build` recompiles only changed files
- Incremental build is enabled by default; no configuration needed
- Do not share `bin/` or `obj/` directories across worktrees (they contain worktree-specific absolute paths)

## NuGet Package Cache

The NuGet package cache is automatically shared at `~/.nuget/packages`.

- Safe for concurrent access across worktrees
- CI: cache `~/.nuget/packages` with `actions/cache`
- Environment variables to keep CI output clean:
  - `DOTNET_CLI_TELEMETRY_OPTOUT=1`
  - `DOTNET_NOLOGO=true`

## Cache Strategy in Worktree Environments

| Mechanism | Recommendation | Reason |
|-----------|----------------|--------|
| NuGet cache (`~/.nuget/packages`) | Recommended | Shared across worktrees, safe for concurrent access |
| Sharing `bin/` / `obj/` | **Forbidden** | Contains absolute paths; sharing across worktrees causes build corruption |
| MSBuild incremental build | Default | Automatic, no configuration |

## dotnet restore Optimization

Run `dotnet restore` first, then pass `--no-restore` to subsequent commands to skip redundant restores.

```bash
# Recommended chain: restore -> build -> test
dotnet restore
dotnet build --no-restore
dotnet test --no-build
```

## dotnet watch (Local Development)

`dotnet watch run` starts a development server with hot reload.

- For local development only — do not use in CI
- Hot Reload is supported for Blazor, Razor Pages, and MVC

## Troubleshooting

### When the build looks stale

```bash
dotnet clean
dotnet build
```

### When NuGet restore fails

Clear the local cache and retry:

```bash
dotnet nuget locals all --clear
dotnet restore
```

## Related Rules / Skills

- Universal constraints: `quality-checks` (QC12)
- Related Skills: `csproj`, `aspnet-core`, `entity-framework-core`, `blazor`, `setup-ci`
- Related Rule: `rules/serial-execution-policy.md`
- Related Agents: `parallel-worker`, `integ-test-worker`, `review-worker`
