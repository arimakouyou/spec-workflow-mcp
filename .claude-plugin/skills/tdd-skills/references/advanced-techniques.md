# Advanced TDD Techniques

## Dealing with Uncertain Specifications

When specs are vague, start with concrete examples rather than abstract tests. Write a test for the simplest specific case, then expand.

**Bad**: `test_calculate_price` (too abstract, unclear what to assert)
**Good**: `test_calculate_price_single_item_no_discount` (concrete, actionable)

## Applying TDD to Legacy Code

1. Write characterization tests that capture current behavior
2. Refactor in small steps under test protection
3. Add new features using TDD

Characterization tests don't assert "correct" behavior — they assert "current" behavior, creating a safety net for refactoring.

## When Tests Get Complex

Complex tests signal complex code. Respond by:
1. Extracting test helper methods
2. Using Builder / Factory patterns for test data
3. Splitting the class under test (Single Responsibility)

## Anti-patterns

### 1. Skipping the test
Write the test first. Always.

### 2. Steps too large
If a test requires implementing multiple things at once, break it into smaller tests.

### 3. Testing trivial getters/setters
Test behavior, not data access. If a getter just returns a field, it doesn't need a dedicated test.

### 4. Testing private methods directly
Test through the public API. If a private method is complex enough to need its own test, it likely belongs in a separate class.

### 5. Test interdependence
Each test must work in isolation. No shared mutable state between tests.

## TODO List Technique

Keep a running list of test cases to write. Check them off as you go. Add new ideas as they arise during implementation.

Benefits:
- Stay focused on the current test
- Don't lose ideas
- Visible progress
