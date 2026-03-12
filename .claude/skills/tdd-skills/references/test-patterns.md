# Test Patterns

## Test Fixtures

Shared setup for tests. Use your framework's fixture mechanism (e.g., `@pytest.fixture`, `beforeEach`, `@BeforeEach`) to create common test data.

## Test Data Builder

Build complex objects fluently with sensible defaults. Only specify the fields relevant to each test.

```
builder = UserBuilder().with_name("Alice").with_role("admin").build()
```

Benefits:
- Tests highlight what matters, hide what doesn't
- Easy to create variations
- Centralized default values

## Parameterized Tests

Run the same test logic with multiple inputs. Use your framework's parameterization support (e.g., `@pytest.mark.parametrize`, `test.each`, `@ParameterizedTest`).

Best for: boundary values, equivalence classes, truth tables.

## One Concept Per Test

Each test should verify one logical concept. Multiple assertions are fine if they all verify the same concept.

**Bad**: One test that checks creation, update, and deletion.
**Good**: Separate tests for each operation.

**Exception**: Multiple assertions verifying one concept (e.g., checking both status code and response body of a single API call) are fine in one test.

## Summary

- Fixtures for shared setup
- Builder pattern for flexible test data
- Parameterization to reduce duplication
- One concept per test
