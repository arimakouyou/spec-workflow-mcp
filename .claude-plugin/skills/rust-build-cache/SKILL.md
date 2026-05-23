---
name: rust-build-cache
description: |
  Build cache configuration for all agents that run cargo commands in Rust projects. Uses sccache as the `RUSTC_WRAPPER` to share compilation results across worktrees and accelerate build, test, and lint. Sharing `CARGO_TARGET_DIR` is forbidden (file-lock contention); the Cargo registry cache and incremental compilation require no setup. Covers handling when cargo-nextest is in use, recovery from corrupted sccache caches, and fallback in environments without sccache installed. Reference this immediately before running cargo fmt/clippy/test/build, and before launching compile-heavy agents such as parallel-worker or integ-test-worker. Triggers on: 'rust build cache', 'sccache setup', 'cargo build cache', 'worktree cache strategy', 'Rust ビルドキャッシュ', 'sccache 設定', 'cargo キャッシュ'.
allowed-tools: [Read, Bash, Grep]
---

# Rust Build Cache

Build cache configuration guide for all agents that run cargo commands in Rust projects.
Sharing compilation results across worktrees significantly accelerates build, test, and lint.

## Scope

- Immediately before running cargo fmt / clippy / test / build
- Pre-processing before launching `parallel-worker` / `integ-test-worker` / `review-worker`
- Accelerating Rust jobs in CI environments
- Sharing compilation results during parallel implementation that uses worktrees

## Out of Scope

- .NET / dotnet build cache → `dotnet-build-cache` Skill
- CI workflow `actions/cache` setup → `setup-ci` Skill

## Detecting and Using sccache

sccache caches compilation results and avoids recompiling unchanged sources. The cache is shared transparently across worktrees and is safe under parallel builds (it uses internal lock control).

### Recommended Pattern: Environment Variable Prefix

Claude Code's Bash tool does not preserve shell state across commands. Because `export` is effective only within the same Bash invocation, prefer prefixing each cargo command with `RUSTC_WRAPPER=sccache`.

```bash
# Detect sccache
if command -v sccache >/dev/null 2>&1; then
  RUSTC_WRAPPER=sccache cargo fmt --all -- --check
  RUSTC_WRAPPER=sccache cargo clippy --quiet --all-targets -- -D warnings
  RUSTC_WRAPPER=sccache cargo test --quiet
else
  cargo fmt --all -- --check
  cargo clippy --quiet --all-targets -- -D warnings
  cargo test --quiet
fi
```

For a single command:

```bash
# Use sccache if available, otherwise run normally
if command -v sccache >/dev/null 2>&1; then
  RUSTC_WRAPPER=sccache cargo test --quiet
else
  cargo test --quiet
fi
```

### Export Form (when running consecutive commands within a single Bash invocation)

```bash
if command -v sccache >/dev/null 2>&1; then
  export RUSTC_WRAPPER=sccache
fi
cargo fmt --all -- --check && cargo clippy --quiet --all-targets -- -D warnings && cargo test --quiet
```

## Cache Strategy in Worktree Environments

| Mechanism | Recommended | Reason |
|-----------|------|------|
| sccache (`RUSTC_WRAPPER`) | Recommended | Transparently shares compilation results across worktrees. Parallel-safe |
| `CARGO_TARGET_DIR` sharing | **Forbidden** | Parallel workers cause lock contention. Cargo uses file locks within `target/`, and multiple processes using the same target dir cause build failures or deadlocks |
| Cargo registry cache | No setup needed | `~/.cargo/registry` and `~/.cargo/git` are automatically shared across all processes |
| Incremental compilation | No setup needed | Enabled by default for debug builds |

## cargo-nextest (Optional)

cargo-nextest runs test binaries in parallel and is faster. It can be used as an option when available. However, the `cargo test` command in the `quality-checks` Rule is the canonical specification, so any switch to nextest is managed centrally there.

```bash
# Check whether nextest is available (use is optional)
command -v cargo-nextest >/dev/null 2>&1 && echo "cargo-nextest available"
```

## Troubleshooting

### When the build fails due to a corrupted sccache cache

```bash
sccache --stop-server
sccache --start-server
```

If restarting the server does not resolve it, clear the cache:

```bash
sccache --stop-server
cache_dir="${SCCACHE_DIR:-"$HOME/.cache/sccache"}"
# Guard against dangerous paths just in case
if [ -n "$cache_dir" ] && [ "$cache_dir" != "/" ]; then
  rm -rf -- "$cache_dir"
else
  echo "Refusing to remove suspicious sccache directory: '$cache_dir'" >&2
fi
sccache --start-server
```

### When sccache is not installed

In environments where sccache is not installed, the fallback path runs ordinary cargo commands as-is and the build is expected to succeed (with `RUSTC_WRAPPER` left unset). On the other hand, if sccache is installed but does not work due to misconfiguration or corruption, isolate the issue by temporarily clearing `RUSTC_WRAPPER` and running `cargo` directly.

## Related Rules / Skills

- Universal constraint: `quality-checks` (QC1-QC3: canonical commands for cargo fmt/clippy/test)
- Related Skills: `cargo-toml`, `axum`, `diesel`, `leptos`
- Related Rule: `rules/serial-execution-policy.md` (subagent launch is serial-only across the plugin)
- Related Agents: `parallel-worker`, `integ-test-worker`, `review-worker`
