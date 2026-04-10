# Quality Gate

Judgment criteria used by Pentagon (Reviewer) when reviewing test files.
All items must PASS for approval; any single FAIL results in rejection.

## Judgment Items

### A. 5-Category Coverage

- [ ] Happy path tests exist
- [ ] Error path tests (validation errors, 404, etc.) exist
- [ ] Boundary tests (empty collections, max-length, etc.) exist
- [ ] Edge cases (duplicates, concurrent updates, etc.) are considered
- [ ] External dependency failure behavior is tested (when applicable)

### B. Behavioral Contract Verification

- [ ] HTTP status codes are correct
- [ ] Response body structure is correct (property names, types)
- [ ] DB state changes are verified after POST/PUT/DELETE (via DbContext)
- [ ] Error response format is consistent (ProblemDetails or project convention)

### C. Code Quality

- [ ] Given-When-Then (Arrange-Act-Assert) structure is clear
- [ ] Test method names describe the behavior under test
- [ ] Tests are independent of each other (can run in any order)
- [ ] No unnecessary assertions (one concept per test)
- [ ] No hardcoded magic numbers without explanation

### D. Hermetic & Deterministic

- [ ] Each test has isolated DB state (Testcontainers + per-test seeding or transactions)
- [ ] External HTTP APIs are stubbed via WireMock.NET (not real network calls)
- [ ] Time-dependent tests use a clock abstraction (e.g., `TimeProvider`)
- [ ] Tests do not depend on execution order
- [ ] Tests do not rely on `Task.Delay` or fixed timeouts for correctness

### E. .NET / C# Specific

- [ ] `async Task` is used correctly for async test methods
- [ ] `IAsyncLifetime` is used for async setup/teardown (not constructors)
- [ ] `IClassFixture<T>` / `ICollectionFixture<T>` is used appropriately for shared state
- [ ] FluentAssertions is used consistently (no mix of `Assert.*` and `.Should()`)
- [ ] `dotnet format` produces no changes
- [ ] Build completes with no warnings (`-warnaserror`)
- [ ] `using` / `await using` is used correctly for disposable resources

## Judgment Flow

```
Check all items
  +-- All PASS -> PASS (test approved)
  +-- FAIL exists (fixable) -> FAIL + specific fix instructions
  +-- FAIL exists (design-level) -> FAIL + design change proposal
```

## Report Format

```
[Pentagon Review] {test_file}

Verdict: PASS / FAIL

A. 5-Category Coverage: PASS / FAIL
   {details if issues found}

B. Behavioral Contract: PASS / FAIL
   {details if issues found}

C. Code Quality: PASS / FAIL
   {details if issues found}

D. Hermetic: PASS / FAIL
   {details if issues found}

E. .NET Specific: PASS / FAIL
   {details if issues found}

Fix instructions: (FAIL only)
  1. {specific fix}
  2. {specific fix}
```
