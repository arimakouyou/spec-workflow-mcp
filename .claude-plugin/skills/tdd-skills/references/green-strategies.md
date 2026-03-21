# Green Strategies

Three strategies to make a failing test pass as quickly as possible.

## 1. Fake It

**Safest approach. Return a constant to make the test pass first.**

```
// Test: empty collection should have zero total
// Implementation: return 0  (hardcoded constant)
```

When to use:
- Implementation path is unclear
- Complex logic is needed
- Building confidence in small steps

## 2. Triangulation

**Generalize from multiple test cases.**

Process:
1. First test → Fake It (return constant)
2. Add second test that breaks the constant
3. Generalize to pass both tests
4. Add more tests if needed

```
Test 1: empty → total is 0       →  return 0
Test 2: one item(100) → total 100  →  return sum(items)
```

When to use:
- Unclear how to generalize
- Want tests to drive the design
- Need to avoid premature abstraction

## 3. Obvious Implementation

**Fastest but riskiest. Implement the real solution directly.**

When to use:
- Solution is trivially clear
- Simple logic
- Experienced with the problem domain

**If the test fails after "obvious" implementation, immediately fall back to Fake It.**

## Decision Flow

```
Is the implementation obvious?
  ├─ Yes → Try Obvious Implementation
  │         ├─ Passes → Done
  │         └─ Fails  → Fall back to Fake It
  └─ No  → Start with Fake It
            ├─ One test  → Keep the fake
            └─ Multiple tests → Triangulate to generalize
```

## Summary

| Strategy | Speed | Safety | When |
|----------|-------|--------|------|
| Fake It | Slow | High | Default choice, when unsure |
| Triangulation | Medium | High | Complex generalization |
| Obvious Implementation | Fast | Low | Only when trivially clear |

**When in doubt, Fake It. When experienced, go Obvious. When complex, Triangulate.**
