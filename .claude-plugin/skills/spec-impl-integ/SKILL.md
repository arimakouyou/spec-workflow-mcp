---
name: spec-impl-integ
description: "Procedure for test-support and integration-level tasks in the v2 workflow (preloaded by integ-test-worker): TST harnesses / fixtures / doubles, P{n}-IT, P{n}-ST, P{n}-SMK smoke tests and the FINAL E2E. Tests come only from test-design; production code is never changed by these tasks. / integ-test-worker 用の手順。"
---

# Test support, IT / ST / smoke / E2E

## 0. Read only the brief

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-brief.sh <SPEC> <TASK> <ROOT>`

Language know-how:

| Topic | Rust |
|---|---|
| Patterns | `references/rust/test-patterns.md` |
| Fixtures | `references/rust/fixture-catalog.md` |
| External API doubles | `references/rust/external-api-mock.md` |
| Case design / quality gate | `references/rust/test-case-design.md`, `references/rust/quality-gate.md` |

For .NET, use `${CLAUDE_PLUGIN_ROOT}/skills/tdd-skills-dotnet/` and `aspnet-core` / `entity-framework-core` (WebApplicationFactory + Testcontainers). The .NET integration references are not ported yet.

## TST task (harness / fixture / double)

- Copy the TST `Interfaces` verbatim into its `Files`, then implement the bodies.
- A double implements exactly the trait its `Implements` names.
- The IT / ST tasks that use this support check it. For this task, the build and the UT command must pass.

## P{n}-IT / P{n}-ST

1. Write each test of the brief into the `File` that test-design declares, with `// @test IT-N` / `// @test ST-N` above it.
2. Call the `Setup` functions with exactly the named arguments. The request, steps and `Then` come from test-design, and every `Then` item is asserted.
3. **Never change production code.** A failure caused by the implementation is a defect of that component. Return `status: blocked`, `blocked_reason: defect`, with the target DES and the failing test. Review then reopens that DES. The commit gate G3 enforces this.
4. Run `spec-run-tests.sh IT` (or `ST`) until your tests pass.

## P{n}-SMK

Generate the smoke tests from design and tech.md, into files matching the tech.md `SMK` command, one test per `SMK-*` ID of the task:

| Level | Test |
|---|---|
| SMK-L1 | GET the tech.md `Health` path → 200 |
| SMK-L2-API-N | call API-N with the minimal request (empty body `{}` for bodies, a placeholder id for paths) → not 5xx |
| SMK-L3-API-N | API-N with `Auth: required`, without credentials → 401 |
| SMK-L4-API-N | each Request field of API-N at a type boundary (empty string, over-long string, integer overflow, unknown enum value, missing required field, malformed id) → 400 or 422 |

List the test files in `tests.files`.

## FINAL

Write each E2E of the brief, one per journey, with `// @test E2E-N`. Then run every layer: UT, CT, IT, ST, SMK and E2E.

## Final message

End with exactly one JSON block:

```json
{"task": "P2-IT", "status": "done | blocked", "blocked_reason": "defect | spec_conflict | retry_exhausted | null",
 "defect": {"des": "DES-5", "test": "IT-4", "text": "..."},
 "tests": {"ids": ["IT-1"], "files": ["tests/it_todos.rs"], "green_passed": true},
 "rf": [], "handoffs": [], "notes": "..."}
```
