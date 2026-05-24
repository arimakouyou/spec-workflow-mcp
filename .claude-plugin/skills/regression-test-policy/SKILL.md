---
name: regression-test-policy
description: |
  Operational policy for regression testing. Defines the flow for converting user bug reports into test cases (RT1), turning acceptance criteria (REQ-N) into permanent regression tests (RT2), and managing regression suite composition and health metrics (RT3). Reference when creating reproduction tests during bug fixes, maintaining the Requirements-Test Traceability Matrix, judging test suite deletions or changes, or reviewing suite health. Triggers on: 'regression test', 'bug reproduction test', 'traceability matrix', 'regression suite', 'リグレッションテスト', 'バグ再現テスト', 'トレーサビリティマトリクス', 'リグレッションスイート'.
allowed-tools: [Read, Edit, Write, Bash, Grep]
---

# Regression Test Policy Skill

## Scope

- Fixing user-reported bugs (create reproduction tests first per RT1)
- Designing the mapping between acceptance criteria (REQ-N) and tests (UT / CT / IT / ST / E2E)
- Updating and verifying the Traceability Matrix
- Reviewing the composition of the regression suite

## Regression is a cross-cutting type, not a layer (clarified by J-8)

> Source: `.claude/_docs/plans/dapper-hardening-orchestrator.md` root cause J (J-8).

Regression is positioned as a **cross-cutting type** (a transverse attribute), not a test layer:

- A regression marker can be applied to **any layer** of the existing test taxonomy (UT / CT / IT / ST / smoke / E2E; see Test Taxonomy in `quality-checks.md`)
- For example, IT-regression for preventing backend bug recurrence, CT-regression for UI state transition bugs, E2E-regression for broken user journey scenarios

Examples of each layer combined with regression:

| Layer | Regression test example | File location / naming |
|---|------|---|
| UT | `regression_issue_123_login_fails_with_special_chars` | inside inline `#[cfg(test)] mod tests` |
| CT | `regression_issue_456_signal_does_not_fire_after_unmount` | inside `tests/component/` |
| IT | `regression_issue_789_db_constraint_violation` | `tests/integration/it_regression_*.rs` |
| ST | `regression_issue_012_search_resets_after_filter_change` | `tests/system/st_regression_*.spec.ts` |
| E2E | `regression #345: full checkout flow breaks on coupon` | `tests/e2e/e2e-regression-NNN.spec.ts` |

RT1/RT2/RT3 apply to **all layers**. Pick the layer based on the bug's scope: ST-regression when a single feature involves UI, E2E-regression for a critical bug that breaks chains of multiple features.

## Out of Scope

- How to write the test code itself -> `tdd-skills` / `tdd-skills-rust` / `tdd-skills-dotnet`
- Handling flaky tests -> `flaky-test-management` Rule
- CI configuration -> `setup-ci` Skill

## Key Points

### 1. RT1: Bug Report -> Test Case Conversion

For user-reported bugs, **always create the reproduction test case before fixing**. Keep the test after the fix to prevent recurrence of the same bug.

#### Conversion Flow

```text
1. Bug report received
   |
2. Identify reproduction conditions
   |
3. Write a failing test case (RED)
   |
4. Fix the bug (GREEN)
   |
5. Add the test to the regression suite
   |
6. Confirm it runs automatically in CI
```

#### Naming Convention

Make tests trackable by issue number:

```rust
#[test]
fn regression_issue_123_login_fails_with_special_chars() {
    // GH#123: login fails when the username contains special characters
}
```

```typescript
it('regression #123: login fails with special chars in username', () => {
  // GH#123: login fails when the username contains special characters
});
```

#### Test Level Assignment (updated in J-8 to reflect new taxonomy)

| Bug scope | Test level | Location |
|---|---|---|
| Single function / method | UT (Unit Test) | inline `#[cfg(test)] mod tests` |
| Component reactivity (mount -> signal -> DOM) | **CT (Component Test)** | `tests/component/` or `*_ct.rs` |
| Backend HTTP API endpoint | IT (Integration Test, backend HTTP only) | `tests/integration/` or `crates/server/tests/it_regression_*.rs` |
| Single-feature full-stack behavior (UI -> backend -> UI) | **ST (System Test)** | `tests/system/` or `tests/e2e/st_regression_*.spec.ts` |
| User journey involving chains of multiple features | E2E (End-to-End) | `tests/e2e/e2e-regression-NNN.spec.ts` |

See Test Taxonomy in `quality-checks.md` for the full responsibility scope of each layer. Pick the **narrowest appropriate layer** based on the essence of the bug — UT if reproducible at the unit level, CT/ST if UI integration is needed, E2E if a user journey is required — to balance test stability and cost.

#### Issue Template (recommended fields)

```markdown
## Bug Report

### Reproduction Steps

1. ...
2. ...

### Expected Behavior

...

### Actual Behavior

...

### Test Case

- [ ] Reproduction test created (test file: )
- [ ] Added to regression suite
```

### 2. RT2: Permanent Regression of Acceptance Criteria

Acceptance criteria defined in the Requirements-Test Traceability Matrix in `test-design.md` are maintained as **permanent regression tests** even after implementation.

#### Principles

1. **No deletion**: acceptance criteria tests must not be deleted without a spec change
2. **On spec change**: handle by updating, not by deleting
3. **Run all in CI**: include them in the default execution targets of `cargo test` / `npm test` etc.
4. **Maintain traceability**: link each test to a Requirement ID (REQ-N) via comment or naming

#### Traceability Matrix Example (CT/ST columns added by J-8)

```markdown
| Requirement ID | UT Specs | CT Specs | IT Specs | ST Specs | E2E Specs | Notes |
|---|---|---|---|---|---|---|
| REQ-1 | UT-1.1, UT-1.2 | CT-1 | IT-1 | ST-1 | E2E-1 | |
```

**Verification**: every REQ-N is linked to at least one UT plus the related CT/IT/ST/E2E (per the responsible layer). Uncovered items are detected and required to be added during Phase Review.

### 3. RT3: Regression Suite Management

#### Suite Composition (CT/ST columns added by J-8)

| Suite | Run timing | Contents |
|---|---|---|
| Unit Regression | Pre-commit / PR CI | All UT (including bug-derived) |
| **Component Regression** | Phase Review / PR CI | All CT (including bug-derived) |
| Integration Regression | Phase Review / E2E Gate / PR CI | All IT (backend HTTP only) |
| **System Regression** | Phase Review / Final E2E Gate / PR CI | All ST (single-feature full-stack) |
| E2E Regression | Final E2E Gate / PR CI | All E2E (user journey) |

**CI gating (finalized as QC16 in J-9)**: at PR / merge time, require all layers + all regression-marked tests to PASS. The `regression_issue_*` pattern is auto-collected from git history. See QC16 in `quality-checks.md` for details.

#### Health Metrics

| Metric | Healthy | Caution |
|---|---|---|
| Overall PASS rate | 100% | Act immediately if below 99% |
| Flaky test rate | 0-2% | Quarantine via FT5 if above 5% |
| PR CI test runtime | Within 5 min | Consider parallelization beyond 10 min |
| Bug recurrence rate | 0% | Recurrence indicates insufficient testing |

#### Integration with spec-workflow

- **Phase 3 (test-design)**: decompose acceptance criteria into UT/IT/E2E and record in the Traceability Matrix
- **Phase 5 (implement)**: write tests first in the TDD RED phase
- **Phase Review**: verify full REQ coverage in the Traceability Matrix
- **On bug fix**: follow the RT1 flow (reproduction test -> fix -> add to regression)

## Common Pitfalls

1. **Writing the test after fixing**: violates RT1. The RED test must be created before the fix
2. **Failing to update the Traceability Matrix**: REQ-to-test mapping becomes stale and coverage is no longer visible
3. **Deleting acceptance criteria tests as "outdated"**: deletion without an accompanying spec change is forbidden
4. **Leaving flaky tests alone**: above 5%, quarantine per `flaky-test-management` (FT5)

## Project-specific Conventions

- Place the Traceability Matrix in `.spec-workflow/specs/{spec-id}/test-design.md`
- Subject to `doc-freshness` 120-day threshold for `test-design.md` freshness checks
- When divergence is detected, prioritize updating the test

## Related Rules / Skills

- Universal constraints: `quality-checks` (QC3), `diagnostic-reasoning` (DR1-DR6: test failure diagnosis)
- Related Skills: `tdd-skills`, `tdd-skills-rust`, `tdd-skills-dotnet`, `spec-test-design`, `flaky-test-management`

## References

- spec-workflow templates: under `.claude-plugin/templates/`
- Place the Traceability Matrix at `.spec-workflow/specs/{spec-id}/test-design.md`
