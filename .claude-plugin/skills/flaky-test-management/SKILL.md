---
name: flaky-test-management
description: |
  Flaky test management policy. Covers FT1 classification (Timing / Order / Environment / Data-dependent), FT2 CI-based and manual detection (`cargo test --test-threads=1`, 10x repeat, `npx jest --runInBand`), FT3 tracking via GitHub Issues (`flaky-test` label + Issue template), FT4 retry settings (cargo-nextest / Vitest / Jest / GitHub Actions nick-fields/retry), FT5 quarantine (`#[ignore]` / `.skip`, max 30 days, no more than 5% of all tests), and FT6 prevention (no sleep, no fixed ports, no `DateTime::now()`; recommend testcontainers / seeded RNG). Use when a flaky test is observed, when handling intermittently failing tests in CI, when designing test environment isolation, or when reviewing the health metrics in `regression-test-policy`. Triggers on: 'flaky test', 'intermittent test failure', 'quarantine flaky test', 'test retry', 'flakyテスト', '不安定テスト', 'テスト隔離'.
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# Flaky Test Management Policy

Defines the definition, detection, tracking, and remediation policy for flaky tests.
Addresses P6-07, P6-08, and P6-09.

## Targets

- Detection and remediation of intermittently failing tests in CI
- Quarantine decisions (`#[ignore]` / `.skip`)
- Flaky test tracking using the Issue template
- Retries in test runner configuration (cargo-nextest / Vitest / Jest / GitHub Actions)
- Test design that resists flakiness (testcontainers, seeded RNG, transaction rollback)

## Out of Scope

- General test code style -> `tdd-skills` / `tdd-skills-rust` / `tdd-skills-dotnet`
- Establishing regression tests -> `regression-test-policy` Skill
- Integration test fixture design -> `integration-test` / `integration-test-dotnet` Skill

## FT1: Definition and Classification (P6-07)

A **flaky test** is a test whose result (pass/fail) varies without code changes.

### Classification

| Category | Cause | Typical example |
|----------|-------|-----------------|
| Timing-dependent | Race conditions, timeout sensitivity | Depends on `sleep(100)`; insufficient wait for async completion |
| Order-dependent | Execution order, shared mutable state | Tests share global state; DB not cleaned up |
| Environment-dependent | Ports, file handles, network | Fixed-port collision, low disk space, DNS resolution failure |
| Data-dependent | Timestamps, random numbers, external APIs | Depends on `DateTime::now()`, external API rate limit |

## FT2: Detection (P6-08)

### CI-based Detection

If a test fails in CI and a re-run without code changes passes, record it as a flaky candidate.

### Manual Detection Commands

```bash
# Rust: isolate order dependence (single-threaded)
cargo test -- --test-threads=1

# Rust: confirm stability via repeated runs (10 times)
for i in $(seq 1 10); do
  cargo test --quiet 2>&1 || echo "FAIL on iteration $i"
done

# Node.js: isolate order dependence
npx jest --runInBand
# or
npx vitest --pool=forks --poolOptions.forks.singleFork
```

### Retry-based Detection

When retry settings (FT4) are enabled, tests that pass on the second or later retry attempt are automatically detected as flaky.

## FT3: Tracking (P6-08)

Manage flaky tests with GitHub Issues using the `flaky-test` label.

### Issue Template

```markdown
## Flaky Test Report

- **Test name**: `{test_module}::{test_name}`
- **Classification**: {FT1 category: Timing / Order / Environment / Data}
- **First detected**: {YYYY-MM-DD}
- **Frequency**: {M} of {N} runs failed (last {period})
- **CI log**: {link to failed run}
- **Owner**: @{assignee}

### Reproduction Steps

{Reproduction command and conditions}

### Hypothesis

{Hypothesized cause of flakiness}
```

## FT4: Retry Settings (P6-09)

Retries are **mitigation**, not a fix. Retried tests must still be tracked under FT3.

### Rust (cargo-nextest)

`.config/nextest.toml`:

```toml
[profile.default]
retries = 2
```

### Node.js (Vitest)

`vitest.config.ts`:

```typescript
export default defineConfig({
  test: {
    retry: 2,
  },
});
```

### Node.js (Jest)

`jest.config.js`:

```javascript
module.exports = {
  // Global retry
  // Call jest.retryTimes(2) inside the test file
};
```

### GitHub Actions (Step Level)

```yaml
- name: Tests (with retry)
  uses: nick-fields/retry@v3
  with:
    max_attempts: 3
    command: cargo test --quiet
```

## FT5: Quarantine (P6-09)

Quarantine persistently unstable tests so they do not block PR merges.

### Quarantine Method

| Language | Method | Example |
|----------|--------|---------|
| Rust | `#[ignore]` + comment | `#[ignore = "flaky: #123"]` |
| Jest/Vitest | `.skip` + comment | `it.skip('test name') // flaky: #123` |

### Quarantine Rules

- Always include the Issue number in the comment on a quarantined test
- Run quarantined tests in a separate non-blocking CI job (`flaky-quarantine`)
- **Maximum quarantine period: 30 days** — after that, fix it or delete the test
- Upper bound on quarantined count: no more than 5% of all tests in the project

### Reference CI Job for Quarantined Tests

```yaml
  flaky-quarantine:
    name: Quarantined Tests (non-blocking)
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@v4
      # Rust: run only #[ignore] tests
      - run: cargo test -- --ignored --test-threads=1
```

## FT6: Prevention

Guidelines for preventing flaky tests.

### Forbidden Patterns

| Pattern | Alternative |
|---------|-------------|
| `sleep(N)` / fixed timeout | Polling + exponential backoff + max wait |
| Fixed port number | Random port or OS-assigned (port 0) |
| Depending on `DateTime::now()` | Clock trait / inject a fixed time for tests |
| Direct calls to external APIs | Mock / WireMock / testcontainers |
| Direct writes to a shared DB | Transaction rollback / testcontainers |
| Implicit ordering between tests | Complete setup/teardown in each test |

### Recommended Patterns

- Fully isolate external services with **testcontainers**
- Use **seeded RNG** (`StdRng::seed_from_u64(42)`) for deterministic test data
- Structure test data via **factory / fixture** patterns
- Use **transaction rollback** to guarantee DB-test isolation
- Run suspected tests in isolation with `--test-threads=1` to identify the cause

## Related Rules / Skills

- Universal constraints: `quality-checks` (QC3, QC12), `diagnostic-reasoning` (DR1-DR6), `failure-taxonomy` (FC1-FC6)
- Related Skills: `regression-test-policy`, `tdd-skills`, `tdd-skills-rust`, `tdd-skills-dotnet`, `integration-test`, `integration-test-dotnet`, `setup-ci`
