---
name: cargo-mutants
description: >
  Mutation testing with cargo-mutants. Introduces small code changes (mutants) and verifies
  that tests detect them. Survived mutants indicate weak test coverage. Long-running — invoke
  explicitly when you want to validate test quality for specific modules or recent changes.
  Use for: mutation testing, test quality analysis, coverage gaps, survived mutants.
argument-hint: "[--package <crate>] [--file <path>] [--base-branch <branch>] [--timeout <secs>]"
user-invokable: true
---

# cargo-mutants — Mutation Testing

Runs mutation testing to assess the quality of your test suite. Unlike code coverage,
mutation testing verifies that tests actually *detect* changes to the code.

> **Warning**: Mutation testing is slow. It re-runs the test suite once per mutant
> (potentially hundreds of times). Use targeted options to limit scope.

## Prerequisites

```bash
command -v cargo-mutants >/dev/null 2>&1 || {
  echo "cargo-mutants is not installed. Install with: cargo install cargo-mutants"
  exit 1
}
```

## Arguments

| Argument | Required | Description |
|----------|:--------:|-------------|
| `--package <crate>` | — | Limit to a specific crate in a workspace |
| `--file <path>` | — | Limit to mutations in a specific source file |
| `--base-branch <branch>` | — | Only mutate lines changed since `<branch>` (e.g., `main`). Internally generates a diff file and passes it to `cargo mutants --in-diff`. **Recommended** |
| `--timeout <secs>` | — | Per-mutant timeout (default: 300s). Prevents runaway tests |
| `--jobs <N>` | — | Number of parallel test jobs (default: auto-detect from CPU cores) |

### Usage Examples

```bash
# Mutation test only the code changed since main
/cargo-mutants --base-branch main

# Target a specific source file
/cargo-mutants --file src/db/repository/users.rs

# Target a specific workspace crate with custom timeout
/cargo-mutants --package my-server --timeout 120
```

## Core Command Pattern

The standard invocation uses `--no-shuffle -vV --in-diff` with a diff file:

```bash
# Generate diff against base branch (default: main)
BASE_BRANCH="${BASE_BRANCH:-main}"
git diff "$BASE_BRANCH" -- '*.rs' > git.diff

# Run mutation testing
cargo mutants --no-shuffle -vV --in-diff git.diff

# Clean up
rm -f git.diff
```

- `--no-shuffle`: Deterministic execution order for reproducibility
- `-vV`: Verbose output — shows both the mutant list and per-mutant test output
- `--in-diff git.diff`: Limit mutations to only the changed lines in the diff file

When additional filters are specified, append them:

```bash
# With package filter
cargo mutants --no-shuffle -vV --in-diff git.diff --package my-crate

# With file filter
cargo mutants --no-shuffle -vV --in-diff git.diff --file src/handler.rs

# With timeout
cargo mutants --no-shuffle -vV --in-diff git.diff --timeout 120
```

## Execution Steps

### 1. Parse Arguments and Detect Environment

```bash
# Detect workspace vs single crate
if [ -f Cargo.toml ] && grep -Eq '^\[workspace\]$' Cargo.toml; then
  echo "Workspace detected"
fi

# Build base command
BASE_BRANCH="${BASE_BRANCH:-main}"
git diff "$BASE_BRANCH" -- '*.rs' > git.diff

CMD="cargo mutants --no-shuffle -vV --in-diff git.diff --timeout ${TIMEOUT:-300}"

# Add filters from arguments
# --package <crate>  -> CMD="$CMD --package <crate>"
# --file <path>      -> CMD="$CMD --file <path>"
# --jobs <N>         -> CMD="$CMD --jobs <N>"
```

### 2. Run Baseline Test

Before running mutations, verify that the test suite passes without any mutations:

```bash
cargo test --quiet
```

If baseline tests fail, **abort**. Mutation testing requires a green test suite.

### 3. Execute Mutation Testing

```bash
# Check diff is non-empty
if [ ! -s git.diff ]; then
  echo "No .rs changes in diff — skipping mutation testing"
  rm -f git.diff
  exit 0
fi

# Run with sccache if available (cargo-mutants invokes cargo build/test internally)
if command -v sccache >/dev/null 2>&1; then
  RUSTC_WRAPPER=sccache $CMD
else
  $CMD
fi

rm -f git.diff
```

Expected duration: minutes to hours depending on codebase size and test suite speed.

### 4. Parse and Report Results

cargo-mutants outputs results to `mutants.out/` directory. Parse the outcomes:

| Outcome | Meaning | Action |
|---------|---------|--------|
| **Killed** | Test suite detected the mutant | Good — tests are effective |
| **Survived** | Mutant was NOT detected by tests | **Action needed** — tests are insufficient |
| **Timeout** | Test exceeded the timeout limit | Review if timeout is too short, or test is slow |
| **Unviable** | Mutant caused a build error | Ignore — not a meaningful mutation |

### 5. Output Summary

Report results in the following format:

```
## Mutation Testing Results

- **Scope**: {description of what was tested}
- **Total mutants**: {N}
- **Killed**: {N} ({percentage}%)
- **Survived**: {N} ({percentage}%)
- **Timeout**: {N}
- **Unviable**: {N}
- **Mutation score**: {killed / (killed + survived)}%

### Survived Mutants (action required)

| # | File | Line | Mutation | Description |
|---|------|------|----------|-------------|
| 1 | src/handler.rs | 42 | Replace `>` with `>=` | Boundary condition not tested |
| ... | | | | |

### Recommendations

{For each survived mutant, suggest what test to add}
```

## Mutation Score Threshold（P3-08/P3-11 対応）

ミューテーションスコアの最低閾値を定義する。閾値未達は品質不足を示す。

### 閾値設定

| レベル | 閾値 | 適用場面 | 動作 |
|--------|------|---------|------|
| Advisory | 60% | TDD 実装時（parallel-worker） | 警告のみ、ブロックしない |
| Blocking | 70% | CI 週次チェック（`--with-scheduled`） | Issue 作成 |
| Strict | 80% | Phase Review 時 | Expert Team Review の品質担当が判定 |

### CI 統合（P3-11）

`/setup-ci --with-scheduled` で生成される週次 CI に以下のステップを追加可能:

```yaml
# --- Mutation testing (weekly) ---
# - name: Mutation testing
#   id: mutation
#   continue-on-error: true
#   run: |
#     cargo install cargo-mutants --locked
#     cargo mutants --no-shuffle -vV --timeout 300 2>&1 | tee /tmp/mutation-output.txt
#     # Extract mutation score
#     SCORE=$(grep "mutation score" /tmp/mutation-output.txt | grep -oP '\d+\.\d+' | tail -1)
#     echo "MUTATION_SCORE=$SCORE" >> "$GITHUB_ENV"
```

閾値判定は週次 Issue 作成ステップで実施する。

## Integration with Other Workflows

- **TDD implementation** (`parallel-worker`): Automatically runs `cargo mutants --no-shuffle -vV --in-diff git.diff` after quality checks pass. Survived mutants trigger supplementary test writing (up to 2 retries)
- **Standalone invocation**: Run `/cargo-mutants --base-branch main` to verify test quality for recent changes
- **Periodic audit**: Run on the full codebase periodically to find coverage gaps（`--with-scheduled` で自動化可能）

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Very slow execution | Use `--file` or `--in-diff` to limit scope |
| Too many unviable mutants | Normal for some code patterns. Focus on survived count |
| OOM during parallel runs | Reduce `--jobs` to 1 or 2 |
| `mutants.out/` clutters repo | Add `mutants.out/` to `.gitignore` |
