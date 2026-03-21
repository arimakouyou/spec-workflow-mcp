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
