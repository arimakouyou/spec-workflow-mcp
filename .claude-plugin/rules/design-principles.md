---
always_apply: true
---

# Design Principles (Taste Invariants)

Design principles to apply during code reviews and implementation.
These serve as the project's **taste invariants** — subjective quality criteria that
are enforced by AI code review (review-worker) alongside deterministic checks.
See `hybrid-inspection.md` for the full inspection model.

## D1: Separation of Concerns

- Each function, struct, or module should focus on a single responsibility
- Do not write business logic in handlers. Handlers should be limited to "accepting input → calling services/repositories → building responses"
- Place validation, data transformation, and business rules in their appropriate layers
- If you cannot explain "what this function does" in one sentence, consider splitting it

## D2: Direction of Dependencies

- Higher layers depend on lower layers (handler → service/repository → model)
- Reverse dependencies (e.g., model referencing handler) are prohibited
- Do not create circular dependencies
- Abstract dependencies on external services using traits; avoid direct dependencies on concrete types

## D3: Minimizing the Public API

- Do not add unnecessary `pub`. Keep things private if they do not need to be accessed from outside the module
- Do not expose internal implementation details (helper functions, intermediate types)
- Use `pub(crate)` to limit visibility to the minimum necessary

## D4: Consistent Error Handling

- Use the project-wide shared error type (e.g., `AppError`) and convert errors from each layer using `From`
- `unwrap()` / `expect()` are only permitted in test code or as invariants during initialization. Use the `?` operator in business logic
- Error messages should include "what happened" and "what was expected"
- Separate user-facing errors from internal log errors (do not return internal details to the client)

## D5: Naming Appropriateness

- Type names, function names, and variable names should accurately express their intent
- Avoid abbreviations; use searchable names (`usr` → `user`; `ctx` is conventionally acceptable)
- Prefix bool variables and functions with `is_`, `has_`, `can_`, etc. to make intent explicit
- Avoid negative naming (`is_not_empty` → express as the negation of `is_empty`)

## D6: DRY (Don't Repeat Yourself)

- If the same logic appears in two or more places, consider consolidating it
- However, do not force consolidation for coincidental similarity (code that happens to look the same). Judge by "do they change for the same reason?"
- Consider consolidation in this order: function extraction, trait extraction, generics — and choose the simplest approach

## D7: YAGNI (You Aren't Gonna Need It)

- Do not preemptively implement features, abstractions, or configuration options that are not currently needed
- "Might be used in the future" is not a reason to implement something. Add it when it becomes necessary
- Prioritize concrete, understandable implementations over excessive generalization
