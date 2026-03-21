# Test Design

## Boundary Value Analysis

Bugs cluster around boundaries. Always test values at and around each boundary.

Example — age categories (0-17: minor, 18-64: adult, 65+: senior):
- Test 17, 18 (minor/adult boundary)
- Test 64, 65 (adult/senior boundary)

## Equivalence Partitioning

Group inputs that produce the same behavior, then test one representative from each group plus all boundary values.

Example — discount tiers (0-999: 0%, 1000-4999: 5%, 5000+: 10%):
- Representative: 500, 3000, 10000
- Boundaries: 999, 1000, 4999, 5000

## Test Naming

Use a consistent pattern that makes the test's purpose clear from the name:

| Pattern | Example |
|---------|---------|
| `test_{subject}_{condition}_{expected}` | `test_total_when_cart_empty_returns_zero` |
| `test_{action}_raises_{error}_when_{condition}` | `test_add_item_raises_error_when_negative_price` |

The name should explain what went wrong when the test fails.

## Error / Exception Testing

Always test error paths, not just happy paths:
- Invalid inputs
- Boundary violations
- Resource unavailability
- Verify both error type and error message content

## Summary

- Always test boundary values
- Use equivalence partitioning for efficiency
- Clear, descriptive naming
- Don't forget error cases
