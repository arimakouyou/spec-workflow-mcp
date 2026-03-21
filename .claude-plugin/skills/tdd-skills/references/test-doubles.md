# Test Doubles

Isolate external dependencies to make tests fast and deterministic.

## Five Types

### 1. Dummy
Fills a required parameter but is never actually used.

### 2. Stub
Returns fixed values. Use when you need to control what a dependency returns.

Use for: DB results, API responses, config values.

### 3. Spy
Records calls for later verification. Use when you need to check that something happened (e.g., email sent, event emitted).

### 4. Mock
Sets expectations upfront and verifies interactions. Use when call verification is the point of the test.

**Mock vs Spy**: Mock verifies behavior expectations. Spy records and you assert later.

### 5. Fake
A lightweight working implementation (e.g., in-memory repository). Use for complex state interactions where stubs are too simple.

## Selection Guide

```
What are you testing?
  ├─ Return value only        → Stub
  ├─ Was it called?           → Mock
  ├─ Call history/details     → Spy
  ├─ Complex state transitions → Fake
  └─ Unused parameter         → Dummy
```

| Scenario | Recommended | Reason |
|----------|-------------|--------|
| External API call | Stub / Mock | Fixed response, call verification |
| Database access | Fake / Stub | Speed, state management |
| Side effects (email, logs) | Spy / Mock | Verify it happened |
| Random values / time | Stub | Deterministic results |
| Complex business logic | Fake | Realistic behavior |

## Anti-pattern: Over-mocking

When everything is a mock, the test verifies nothing meaningful. Use real objects for the code under test; only mock external boundaries (I/O, network, time).

> "Prefer Stubs over Mocks. State verification is superior to behavior verification." — Martin Fowler

## Principle

**Use the simplest test double that works. When in doubt, start with a Stub.**
