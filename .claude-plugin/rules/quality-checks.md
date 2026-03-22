---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Quality Check Commands

Unified command specification for quality checks run by parallel-worker, review-worker, and other agents. All agents must use the commands defined in this rule.

## rustfmt

```bash
cargo fmt --all -- --check
```

- Targets both `src` and `tests` (do not check only one of them)
- To auto-fix, run without `--check`: `cargo fmt --all`

## clippy

```bash
cargo clippy --quiet --all-targets -- -D warnings
```

- `--all-targets`: Includes test code, benchmarks, and examples in the check
- `-D warnings`: Treats all warnings as errors
- `--quiet`: Suppresses progress output

## test

```bash
cargo test --quiet
```

- Runs all tests (unit + integration)
- To run a specific test only: `cargo test --test {test_name} -- --nocapture`

## Leptos Full-Stack (WASM Frontend) Build Verification

When the project uses `cargo-leptos` (detected by `[package.metadata.leptos]` in `Cargo.toml` or the presence of a `Cargo.toml` with `crate-type = ["cdylib", "rlib"]`), the following additional checks are **required** after the standard checks above.

### cargo-leptos build

```bash
cargo leptos build
```

- Builds both SSR (server) and WASM (client) targets in a single command
- Catches WASM compilation errors that `cargo build` / `cargo test` alone cannot detect (they only compile for the host target)
- Must pass before any commit

### WASM-specific clippy (optional, when cargo-leptos is unavailable)

```bash
cargo clippy --target wasm32-unknown-unknown --no-default-features --features hydrate --quiet -- -D warnings
```

- Use this as a fallback when `cargo-leptos` is not installed
- `--features hydrate`: Compiles only the client-side code path
- Detects WASM-incompatible API usage (e.g., `std::fs`, `std::net`, `tokio::spawn`)

### Detection rule for agents

Before running quality checks, agents must check for a Leptos full-stack configuration:

```bash
grep -q 'package.metadata.leptos' Cargo.toml 2>/dev/null
```

If detected, include the `cargo leptos build` step in the quality check sequence. The full check order becomes:

1. `cargo fmt --all -- --check`
2. `cargo clippy --quiet --all-targets -- -D warnings`
3. `cargo test --quiet`
4. `cargo leptos build` (Leptos projects only)
