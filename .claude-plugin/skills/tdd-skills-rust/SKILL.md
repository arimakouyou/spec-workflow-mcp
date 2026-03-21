---
name: tdd-skills-rust
description: >
  Rust-specific version of tdd-skills. Provides TDD principles and Rust implementation patterns based on t-wada's teachings.
  Covers the Red-Green-Refactor cycle, test implementation using Rust testing features (#[test], mockall, rstest),
  trait-based test double design, and boundary value test design.
  Use when implementing tests, designing tests, or practicing TDD in Rust projects.
---

# TDD Skills (Rust)

> For foundational principles, see the language-agnostic `/tdd-skills`. This skill focuses on Rust-specific implementation patterns.

Provides TDD principles and practices based on the teachings of t-wada (Takuto Wada), aligned with Rust language features.

## Pre-check: Know-how Reference

Read relevant know-how such as testing from the Know-how INDEX under the `feedback-loop` rule.
Incorporate checklists and counter-examples into your test design.

## The Essence of TDD

TDD is a "programming technique," not a "technique for writing tests."

> "TDD is the art of turning anxiety into boredom." - t-wada

## Red-Green-Refactor Cycle

```
Red:      Write a failing test
  ↓
Green:    Make it pass with minimal code
  ↓
Refactor: Refactor
  ↓
Red:      Next test...
```

### Green Strategies (3 Types)

1. **Fake It**: Return a constant first (safest)
2. **Triangulation**: Generalize from multiple tests
3. **Obvious Implementation**: Implement directly when the solution is clear

Details: [references/green-strategies.md](references/green-strategies.md)

## Test Structure (Given-When-Then)

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use mockall::predicate::*;

    #[test]
    fn get_user_returns_entity_when_exists() {
        // Given
        let mut mock_repo = MockUserRepository::new();
        mock_repo
            .expect_find_by_id()
            .with(eq(123))
            .returning(|_| Ok(Some(User { id: 123, name: "Alice".into() })));
        let query = UserQueryService::new(Box::new(mock_repo));

        // When
        let result = query.get_user_by_id(123).unwrap();

        // Then
        assert_eq!(result.id, 123);
    }
}
```

## Test Naming Conventions

| Pattern | Example |
|----------|-----|
| `{action}_when_{condition}` | `returns_empty_when_no_users` |
| `{action}_with_{input}` | `calculates_total_with_multiple_items` |
| `fails_when_{condition}` | `fails_when_invalid_id` |

In Rust, test functions do not require a `test_` prefix (identified by the `#[test]` attribute).
However, if used by convention, apply it consistently.

## Test Types

| Type | Target | Test Doubles | Speed |
|------|------|-------------|------|
| Unit | Domain, UseCase | trait-based mock/fake | Fast |
| Integration | API, Repository | Test DB + transaction | Slow |

## Test Doubles

| Type | Purpose | Rust Implementation |
|------|------|-------------|
| Stub | Return fixed values | trait impl or `mockall`'s `returning()` |
| Mock | Verify calls | `mockall`'s `expect_*()` |
| Fake | Lightweight implementation | `HashMap`-based InMemoryRepository |

Details: [references/test-doubles.md](references/test-doubles.md)

## F.I.R.S.T Principles

- **F**ast: Fast
- **I**ndependent: Independent
- **R**epeatable: Repeatable
- **S**elf-Validating: Self-validating
- **T**imely: Write before production code

## Troubleshooting

| Problem | Solution |
|------|--------|
| Mock type mismatch | Apply `#[automock]` to the trait, inject via `Box<dyn Trait>` |
| async tests not running | Use `#[tokio::test]` |
| Data interference between tests | Use `test_transaction` to rollback |
| Slow compilation | Isolate test-only code with `#[cfg(test)]` |

## Detailed References

| Document | Contents |
|------------|------|
| [green-strategies.md](references/green-strategies.md) | Green strategy details and practical examples |
| [test-design.md](references/test-design.md) | Boundary value analysis and equivalence partitioning |
| [test-patterns.md](references/test-patterns.md) | Fixtures and parameterized tests |
| [test-doubles.md](references/test-doubles.md) | Types of test doubles and when to use them |
| [tdd-and-design.md](references/tdd-and-design.md) | The effect of TDD on design |
| [advanced-techniques.md](references/advanced-techniques.md) | Legacy code handling and anti-patterns |
