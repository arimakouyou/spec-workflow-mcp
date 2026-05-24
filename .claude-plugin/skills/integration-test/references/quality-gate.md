# Quality Gate

Decision criteria Pentagon (Reviewer) uses when reviewing test files.
All items must PASS to be approved; even one FAIL triggers a send-back.

## Decision Items

### A. 5-Category Coverage

- [ ] Happy-path tests exist
- [ ] Error-path tests exist (validation errors, 404, etc.)
- [ ] Boundary tests exist (empty list, max length, etc.)
- [ ] Edge cases (duplicates, concurrent updates, etc.) are considered
- [ ] External-dependency error behavior is tested (where applicable)

### B. Behavior-Contract Verification

- [ ] HTTP status code is correct
- [ ] Response body shape is correct (field names, types)
- [ ] DB state changes are verified (POST/PUT/DELETE)
- [ ] Error response format is consistent

### C. Code Quality

- [ ] Given-When-Then structure is clear
- [ ] Test function names describe the behavior
- [ ] No inter-test dependencies (each runs independently)
- [ ] No unnecessary asserts (one concept per test)
- [ ] No hard-coded magic numbers

### D. Hermetic & Deterministic

- [ ] Each test has independent DB state (testcontainers or transactions)
- [ ] External APIs are swapped to test doubles via trait DI
- [ ] Time-dependent tests are controlled via a Clock trait
- [ ] No dependency on test execution order
- [ ] No reliance on `sleep` or fixed timeouts

### E. Rust-Specific

- [ ] `#[tokio::test]` is used correctly
- [ ] `unwrap()` is only used in test code (not leaked into production code)
- [ ] No `clippy` warnings
- [ ] Formatted with `rustfmt`

## Decision Flow

```
Check all items
  ├─ All PASS → PASS (test approved)
  ├─ FAIL exists (fixable) → FAIL + concrete fix instructions
  └─ FAIL exists (design-level) → FAIL + design change suggestion
```

## Report Format

```
[Pentagon Review] {test_file}

Decision: PASS / FAIL

A. 5-Category Coverage: PASS / FAIL
   {details if anything is missing}

B. Behavior Contract: PASS / FAIL
   {details if there are issues}

C. Code Quality: PASS / FAIL
   {details if there are issues}

D. Hermetic: PASS / FAIL
   {details if there are issues}

E. Rust-Specific: PASS / FAIL
   {details if there are issues}

Fix instructions:
  1. {concrete fix}
  2. {concrete fix}
```
