---
name: tdd-skills
description: "TDD principles and practices based on t-wada's teachings. Covers Red-Green-Refactor cycle, test structure, test doubles, boundary value testing, and design through TDD. Use when implementing tests, designing test strategies, or practicing TDD — regardless of language or framework."
---

**TDD Skills Active**

# TDD Skills

TDD principles and practices based on t-wada's (Takuto Wada) teachings.

## Core Principle

**TDD is a programming technique, not a testing technique.**

> "TDD transforms anxiety into boredom." — t-wada

## Red-Green-Refactor Cycle

```
RED:      Write a failing test
  ↓
GREEN:    Make it pass with minimal code
  ↓
REFACTOR: Clean up without changing behavior
  ↓
RED:      Next test...
```

### Green Strategies

1. **Fake It**: Return a constant first (safest)
2. **Triangulation**: Generalize from multiple test cases
3. **Obvious Implementation**: Implement directly when the solution is clear

Details: [references/green-strategies.md](references/green-strategies.md)

## Test Structure (Given-When-Then)

```
// Given — set up preconditions
// When  — perform the action
// Then  — verify the outcome
```

## Test Naming

| Pattern | Example |
|---------|---------|
| `test_{action}_when_{condition}` | `test_returns_empty_when_no_users` |
| `test_{action}_raises_{error}_when_{condition}` | `test_raises_not_found_when_invalid_id` |

## Test Types

| Type | Target | Mocking | Speed |
|------|--------|---------|-------|
| Unit | Domain, Use Case | All deps | Fast |
| Integration | API, Repository | DB connection | Slow |

## Test Doubles

| Type | Purpose |
|------|---------|
| Stub | Return fixed values |
| Mock | Verify interactions |
| Fake | Lightweight implementation (e.g., in-memory store) |

Details: [references/test-doubles.md](references/test-doubles.md)

## F.I.R.S.T Principles

- **F**ast: Tests run quickly
- **I**ndependent: No test depends on another
- **R**epeatable: Same result every run
- **S**elf-Validating: Pass/fail without manual inspection
- **T**imely: Written before production code

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Can't verify mock calls | Use spec-based mocks (e.g., `Mock(spec=Port)` in Python, typed mocks in TS) |
| Fixture loading errors | Ensure test config files are in the correct directory |
| Async test failures | Use the appropriate async test decorator/runner for your framework |

## References

| Priority | Document |
|----------|----------|
| High | [green-strategies.md](references/green-strategies.md) — Green strategies |
| High | [test-design.md](references/test-design.md) — Boundary value analysis |
| Mid | [test-patterns.md](references/test-patterns.md) — Test patterns |
| Mid | [test-doubles.md](references/test-doubles.md) — Test doubles |
| Low | [advanced-techniques.md](references/advanced-techniques.md) — Advanced techniques |
| Low | [tdd-and-design.md](references/tdd-and-design.md) — TDD and design |
