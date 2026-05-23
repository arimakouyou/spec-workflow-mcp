# Hybrid Inspection Model

Defines a quality-assurance architecture that combines deterministic rules
(linters / CI tooling) with LLM-based semantic inspection.

## Inspection Architecture Overview

```
Source code change
    |
    +--- Deterministic inspection (parallel-worker / CI)
    |    +- rustfmt: format normalization
    |    +- clippy: lint warning detection
    |    +- cargo test: test execution
    |    +- cargo audit: vulnerability detection
    |    +- architecture tests: structural invariants
    |
    +--- LLM-based inspection (review-worker)
         +- A: Style — naming intent and consistency
         +- B: Design — SoC, dependency direction, YAGNI
         +- C: Security — OWASP, authentication/authorization
         +- D: Spec — spec conformance
         +- E: Tests — test quality, TDD compliance
         +- F: Design Conformance — design conformance
         +- G: API Docs — OpenAPI update verification
```

## Inspection Matrix

For each quality concern, defines which side — deterministic or LLM inspection — is responsible.

| Quality Concern | Deterministic Inspection | LLM Inspection | Responsible Agent |
|---------|-------------|---------|---------------|
| Code formatting | `cargo fmt --check` | — | parallel-worker |
| Lint warnings | `cargo clippy -D warnings` | A: Style verification | parallel-worker + review-worker |
| Unit tests | `cargo test` | E: test quality assessment | parallel-worker + review-worker |
| Security vulnerabilities | `cargo audit` | C: OWASP analysis | parallel-worker + review-worker |
| Dependency direction | `tests/architecture.rs` | B: Design assessment | tests + review-worker |
| Naming appropriateness | — | A: Style assessment | review-worker only |
| Single Responsibility Principle | — | B: Design assessment | review-worker only |
| Spec conformance | — | D: Spec verification | review-worker only |
| TDD process | — | E2: TDD compliance assessment | review-worker only |
| Design conformance | — | F: Design deviation detection | review-worker only |
| API documentation | — | G: openapi.yaml verification | review-worker only |

## Classification of Issues Each Inspection Catches

### Detectable Only by Deterministic Inspection

- Format violations (whitespace, indentation, trailing newline)
- Compiler warnings (unused variables, unreachable code)
- Known vulnerability patterns (matches against the CVE database)
- Dependency direction violations (mechanical analysis of `use crate::`)
- Test PASS/FAIL results

### Detectable Only by LLM Inspection

- Whether names accurately express intent (semantic judgment)
- Whether functions have a single responsibility (design judgment)
- Whether error messages are useful for the user (UX judgment)
- Whether the Success criteria of the spec documents are met (spec interpretation)
- Whether the code aligns with the design intent of "why it was written that way"

### Detected Through Cooperation

- Security: known CVEs via `cargo audit` + logical vulnerabilities via C: OWASP
- Test quality: PASS/FAIL via `cargo test` + meaningful assertions via E: Tests
- Style: mechanical patterns via `clippy` + project-specific naming conventions via A

## Subjective Quality Standards (Taste Invariants)

The subjective quality standards applied during LLM inspection are defined in `.claude-plugin/rules/design-principles.md`.

### Correspondence with design-principles.md

| Taste Invariant | design-principles.md | review-worker Category |
|----------------|---------------------|---------------------|
| Separation of responsibilities | D1: Separation of Concerns | B: Design |
| Dependency direction | D2: Direction of Dependencies | B: Design |
| Minimal public API | D3: Minimizing Public API | B: Design |
| Error consistency | D4: Consistent Error Handling | B: Design |
| Naming appropriateness | D5: Naming Appropriateness | A: Style |
| DRY principle | D6: DRY | B: Design |
| YAGNI principle | D7: YAGNI | B: Design |

These standards are referenced directly in the AI code review (review-worker) prompt.
review-worker reads `design-principles.md` and evaluates code based on each principle.

## Execution Timing in the Workflow

| Timing | Deterministic Inspection | LLM Inspection |
|-----------|-------------|---------|
| During TDD implementation (step 4) | parallel-worker runs rustfmt + clippy + tests | — |
| UT quality verification (step 5) | — | test-engineer assesses test quality |
| Code review (step 6) | review-worker runs rustfmt + clippy + tests | review-worker performs A-G category review |
| Phase Review (step 3.5) | cargo test + integrated verification + CVE audit | Expert Team Review (5 reviewers, launched serially per `rules/serial-execution-policy.md`) |

## Double-Check Quality Principle

parallel-worker (the implementer) and review-worker (the reviewer) are different agents, and
review-worker, based on the **Anti-Bias Protocol**, does not take parallel-worker's results at face value:

> The code has problems. Your job is to find them.
> Reasoning of the form "it passed three stages, so it must be fine" is prohibited.

This separation guarantees that passing deterministic checks does not degrade the quality of the LLM review.
