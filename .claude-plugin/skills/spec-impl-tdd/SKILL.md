---
name: spec-impl-tdd
description: "TDD procedure for one DES task in the v2 workflow (preloaded by impl-worker): RED against a stub copied verbatim from design Interfaces with tests taken only from test-design, GREEN without touching signatures or tests, REFACTOR, then quality checks. Also covers wiring/config tasks and P{n}-REFACTOR. / impl-worker 用の TDD 手順。"
---

# TDD for a DES task

## 0. Read only the brief

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-brief.sh <SPEC> <TASK> <ROOT>
```

The brief is the complete input: the component, its types, the dependency interfaces, the acceptance criteria, the tests, the test support and the test layout. For details, read the owning block by ID (`spec-slice.sh <SPEC> <ID>`). Never read `tasks.md`: it is only a generated index.

- **Test cases** come only from the test-design blocks in the brief. **Signatures and types** come only from DES `Interfaces` and MOD `Definition`.
- If they disagree, or you need a function, type, dependency or seam the design does not declare, stop and return `status: blocked`, `blocked_reason: spec_conflict` with the IDs. Do not choose one side, and do not work around it.

## 1. RED

1. **Stubs.**
   - Copy every item of the DES `Interfaces` block verbatim into the DES `Files`, replacing each elided body with `todo!()` (C#: `throw new NotImplementedException()`).
   - Copy every owned MOD `Definition` verbatim into its owner's file.
   - Add module declarations only in the Wiring Files (`mod.rs`, `lib.rs`, …).
2. **Tests.**
   - Write every UT / CT of the brief, one test per ID, into the file given by tech.md `Test Layout`. For Rust UT the layout is `{stem}_tests.rs` beside the source, included with `#[cfg(test)] #[path = "{stem}_tests.rs"] mod tests;`.
   - Put `// @test UT-N.M` on the line above each test. The set of markers must equal the task's test IDs (gate G5).
   - Bind the Target's parameters exactly as `Given` names them, and assert exactly the `Then` outcome. Assert values, not just `is_ok()`.
   - Use only the doubles the brief lists (`TST` entries). No real clock, RNG, environment, file system or network in UT.
3. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-run-tests.sh UT <ROOT>` (CT for ui).
   - The tests must **compile and fail**, on `todo!()` or on an assertion. A compile error means a test disagrees with a signature: fix the test, never the signature.
4. Record RED: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-git.sh checkpoint <SPEC> <TASK> <test files...>`. From now on the test files and the signature lines are locked (gates G4, G6).

## 2. GREEN

Replace the `todo!()` bodies with the simplest implementation that passes. Do not edit a signature line, a MOD definition or a test file. Run the tests until they pass.

## 3. REFACTOR

Improve the internals only. The tests and signatures stay as they are, and the tests stay green. An improvement outside this task's files goes to `rf[]`. Do not make it.

## 4. Quality

Run the tech.md `Quality Commands` (format, lint) and fix what they report.

## Other task kinds

| Kind / task | Procedure |
|---|---|
| wiring, config | No RED. Implement the Files: manifests, CI, bootstrap. Build, and run the UT command so everything compiles. Leave `tests.ids` empty. |
| ui | As above, with CT. Follow `${CLAUDE_PLUGIN_ROOT}/skills/tdd-skills-rust/references/leptos-frontend-testing.md` (Leptos) or `${CLAUDE_PLUGIN_ROOT}/skills/tdd-skills-dotnet/references/blazor-testing.md` (Blazor). |
| `P{n}-REFACTOR` | Take the `open` rows of `refactor-backlog.md` in the brief. Change only production code: no test file, no signature. Keep every layer green. List what you completed in `rf_done`. |

## Rework

- `rework_from: green`: fix the implementation only.
- `rework_from: red`: rewrite the tests named in the findings, then run the checkpoint again.

Either way, read the findings in the brief (`前回のレビュー指摘`).

## Retries

Follow `${CLAUDE_PLUGIN_ROOT}/rules/verdict.md` §4. Before a retry, write the failing check, your hypothesis and the evidence. After two failures of the same kind, change the approach. Before a third attempt, call the advisor. Return `blocked`, `retry_exhausted` rather than weakening a test.

## Final message

End with exactly one JSON block. The SubagentStop hook records it, and the commit gate reads it.

```json
{"task": "DES-4", "status": "done | blocked", "blocked_reason": "spec_conflict | retry_exhausted | null",
 "conflict": {"ids": ["DES-4", "UT-4.2"], "text": "..."},
 "tests": {"ids": ["UT-4.1", "UT-4.2"], "files": ["src/domain/service_tests.rs"], "red_failed": true, "green_passed": true},
 "rf": ["..."], "rf_done": [], "handoffs": [{"to": "DES-5", "text": "..."}], "notes": "..."}
```
