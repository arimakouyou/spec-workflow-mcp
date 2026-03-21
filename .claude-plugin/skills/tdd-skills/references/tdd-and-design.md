# TDD and Design

## TDD Is Also a Design Technique

Practicing TDD naturally leads to:

1. **YAGNI**: Only implement what tests require
2. **Single Responsibility**: Testable classes have clear responsibilities
3. **Dependency Inversion**: Test doubles push you toward interface-based design
4. **Loose Coupling**: Testable code has low coupling

## Testable vs Untestable Design

**Untestable** — direct dependencies on external systems (DB connections, HTTP clients, file system, clock) created inside the class.

**Testable** — dependencies injected through constructor/method parameters, allowing test doubles to be substituted.

## Design Benefits from TDD

### 1. Clear Interfaces
Writing tests first forces you to design a usable API from the caller's perspective.

### 2. Responsibility Separation
When a test becomes complex, the class under test has too many responsibilities. Split it.

### 3. Loose Coupling
Using test doubles naturally decouples components through interfaces/protocols.

## Testability Principles

### Inject external dependencies
Don't create dependencies internally. Accept them via constructor or parameters.

### Separate side effects from logic
Pure computation in one function, I/O in another. Test the pure part directly.

### Make behavior deterministic
Inject sources of non-determinism (time, randomness, UUIDs) so tests can control them.

## Design Patterns That Emerge from TDD

- **Strategy**: Injected behavior → naturally testable with different strategies
- **Repository**: Abstracted data access → swap real DB for in-memory Fake
- **Factory**: Complex object creation → isolated and testable

> "Writing good tests naturally leads to good design." — t-wada

**TDD = Design-Driven Development**
